// video_preview — REAPER extension for fast video frame extraction (macOS).
//
// Decode strategy:
//   Sequential (playback):  Dual ping-pong async batch generators.  Each batch requests
//                           BATCH_SIZE frames; the generators hand off at the midpoint so
//                           the active one is never cancelled during normal playback —
//                           only the idle generator is repurposed for the next window.
//                           The entire GOP is decoded in one sequential P-frame pass that
//                           starts long before those frames are needed, so the main thread
//                           always finds the file already on disk → 0ms stall.
//   Random access (scrub):  copyCGImageAtTime: — same as before, ~5-30ms.
//                           On any seek / batch miss both generators are cancelled and
//                           the batch restarts from the new position.
//
// Decoded frames are cached as JPEGs in /tmp under a least-recently-used budget; see
// "Frame cache" below for why they are files and not memory.
//
// Lua API (all accessible via reaper.*):
//   int    VP_Open(filePath)
//   double VP_GetDuration(handle)
//   string VP_GetFrame(handle, timePos, maxW, maxH)
//   int    VP_ExtractFrame(handle, timePos, maxW, maxH, outputPath)
//   void   VP_Close(handle)

#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <Foundation/Foundation.h>

#include <atomic>
#include <algorithm>
#include <list>
#include <map>
#include <mutex>
#include <string>
#include <vector>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <sys/stat.h>
#include <unistd.h>

#include "sdk/reaper_plugin.h"
#include "vp_api.h"

static int  (*plugin_register)(const char*, void*) = nullptr;

// -----------------------------------------------------------------------
// Decoder
// -----------------------------------------------------------------------

// FNV-1a hash of a file path — used as the cache-file discriminator instead of
// the handle integer, so frames from different videos never share a cache slot
// even when handles are reused across REAPER restarts (tmp files survive restarts).
static uint32_t hashPath(const char* s) {
    uint32_t h = 2166136261u;
    while (*s) { h ^= (uint8_t)*s++; h *= 16777619u; }
    return h;
}

// -----------------------------------------------------------------------
// Frame cache — bounded, least-recently-used
// -----------------------------------------------------------------------
// Frames are content-addressed, so a name always identifies the same picture and a
// cached file can be reused forever. That was the whole design, and the flaw in it:
// nothing ever deleted anything, so seven videos had left 138,468 files and 7.69 GB
// in /tmp.
//
// Going through memory instead turned out to be impossible: REAPER hands a `char*`
// out-parameter to Lua with strlen, so a JPEG arrives cut off at its first null byte
// (measured — 3 bytes of an 8-byte pattern survive). JS_ReaScriptAPI's JS_String, the
// one function built to read raw memory into Lua, uses that same convention, so there
// is no way around it from an extension.
//
// So the files stay, and are simply kept to a budget. The decode cost is what matters
// and the writes were never the problem: a working set this small never leaves the
// operating system's page cache, so reading a frame back does not touch the disk at
// all. It behaves like the in-memory cache while remaining a plain path, which is what
// ReaImGui wants anyway.
//
// 256 MB is ~4,400 frames at the 58 KB a 640x360 JPEG averages. Playback needs about
// 200 (one BATCH_SIZE window ahead for each of the two videos being compared), so
// there is ample room for timeline thumbnails to survive a playthrough and still be
// there afterwards.
static const uint64_t CACHE_BUDGET_BYTES = 256ull * 1024ull * 1024ull;

static const char* CACHE_PREFIX = "vp2_";

static std::string cacheFramePath(uint32_t pathHash, long long ms, int w, int h) {
    char buf[256];
    snprintf(buf, sizeof(buf), "/tmp/%s%u_%lld_%dx%d.jpg", CACHE_PREFIX, pathHash, ms, w, h);
    return buf;
}

// Touched from the async batch completion handlers as well as the main thread.
static std::mutex g_cacheMu;
static std::list<std::string>                                   g_lru;      // front = newest
static std::map<std::string, std::list<std::string>::iterator>  g_lruPos;
static std::map<std::string, uint64_t>                          g_lruSize;
static uint64_t                                                 g_lruBytes = 0;

// Drop the coldest files until the total is back inside the budget. Caller holds the
// lock. Returns how many files were removed.
static int cacheEvictLocked() {
    int removed = 0;
    while (g_lruBytes > CACHE_BUDGET_BYTES && !g_lru.empty()) {
        const std::string victim = g_lru.back();
        g_lru.pop_back();
        g_lruPos.erase(victim);
        auto it = g_lruSize.find(victim);
        if (it != g_lruSize.end()) {
            g_lruBytes -= std::min(g_lruBytes, it->second);
            g_lruSize.erase(it);
        }
        unlink(victim.c_str());
        removed++;
    }
    return removed;
}

// Record a frame as the newest thing in the cache, evicting to stay inside the budget.
// `bytes` is 0 when the size is not already known, in which case it is read from disk.
static void cacheTouch(const std::string& path, uint64_t bytes) {
    if (path.empty()) return;
    std::lock_guard<std::mutex> lk(g_cacheMu);

    auto known = g_lruPos.find(path);
    if (known != g_lruPos.end()) {
        // Splicing a node onto its own position is a precondition violation for
        // list::splice, not a no-op, and the frame on screen is re-touched every single
        // frame -- so the already-newest case has to be checked, not just handled.
        if (known->second != g_lru.begin()) {
            g_lru.splice(g_lru.begin(), g_lru, known->second);
            known->second = g_lru.begin();   // the node moved; the index follows it
        }
        return;
    }

    if (bytes == 0) {
        struct stat st;
        if (stat(path.c_str(), &st) != 0) return;            // vanished; nothing to track
        bytes = (uint64_t)st.st_size;
    }

    g_lru.push_front(path);
    g_lruPos[path]  = g_lru.begin();
    g_lruSize[path] = bytes;
    g_lruBytes     += bytes;
    cacheEvictLocked();
}

// Adopt whatever earlier sessions left in /tmp, then evict down to the budget. Oldest
// first by modification time, so the files most recently useful are the ones kept.
//
// Runs off the main thread: this is the pass that has 7.69 GB to walk the first time,
// and REAPER should not wait for it to start up. Frames written while it runs are
// already tracked by cacheTouch, and adopting one twice is a no-op.
static void cacheAdoptExisting() {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSString* dir = @"/tmp";
            NSFileManager* fm = [NSFileManager defaultManager];
            NSArray<NSString*>* names = [fm contentsOfDirectoryAtPath:dir error:nil];
            if (!names) return;

            NSString* prefix = [NSString stringWithUTF8String:CACHE_PREFIX];
            struct Found { std::string path; uint64_t bytes; double mtime; };
            std::vector<Found> found;

            for (NSString* name in names) {
                if (![name hasPrefix:prefix] || ![name hasSuffix:@".jpg"]) continue;
                NSString* full = [dir stringByAppendingPathComponent:name];
                NSDictionary* at = [fm attributesOfItemAtPath:full error:nil];
                if (!at) continue;
                found.push_back({ [full UTF8String],
                                  (uint64_t)[at fileSize],
                                  [[at fileModificationDate] timeIntervalSince1970] });
            }

            std::sort(found.begin(), found.end(),
                      [](const Found& a, const Found& b) { return a.mtime < b.mtime; });

            // Oldest adopted first so it sits at the cold end and is evicted first.
            for (const Found& f : found) cacheTouch(f.path, f.bytes);
        }
    });
}

struct Decoder {
    AVAssetImageGenerator* gen       = nil;  // sync (copyCGImageAtTime, main thread)
    AVAssetImageGenerator* batchGenA = nil;  // ping-pong async batch generators
    AVAssetImageGenerator* batchGenB = nil;
    bool batchActiveIsA = true;  // which generator holds the most-recently-kicked batch

    double   duration  = 0.0;
    double   frameDur  = 1.0 / 25.0;
    int      handle    = 0;
    uint32_t pathHash  = 0;  // stable per-file id used in cache filenames

    // Sync-decode result cache
    double      cachedTimePos = -1.0;
    int         cachedW = 0, cachedH = 0;
    std::string cachedPath;

    // Most-recently-kicked batch window
    double batchStartTime = -1.0;
    int    batchW = 0, batchH = 0;

    // 100 frames @ 25fps = 4s.  A 3s GOP has 75 P-frames; one batch covers >1 full GOP.
    static const int BATCH_SIZE = 100;

    Decoder(const char* path, int h) : handle(h), pathHash(hashPath(path)) {
        @autoreleasepool {
            NSURL* url = [NSURL fileURLWithPath:@(path)];
            AVURLAsset* asset = [AVURLAsset assetWithURL:url];

            auto makeGen = [&]() {
                AVAssetImageGenerator* g = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
                g.appliesPreferredTrackTransform = YES;
                // Both tolerances zero = frame-accurate decoding.
                // A non-zero toleranceAfter lets AVFoundation snap to a nearby keyframe,
                // which stores the WRONG frame content under the requested timestamp's
                // cache path, causing a visible 12-13 frame jump every GOP (~3s).
                g.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.0, 600);
                g.requestedTimeToleranceAfter  = CMTimeMakeWithSeconds(0.0, 600);
                return g;
            };
            gen      = makeGen();
            batchGenA = makeGen();
            batchGenB = makeGen();

            duration = CMTimeGetSeconds(asset.duration);

            NSArray<AVAssetTrack*>* tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
            if (tracks.count > 0) {
                float fps = tracks[0].nominalFrameRate;
                if (fps > 0.0f) frameDur = 1.0 / fps;
            }
        }
    }

    ~Decoder() {
        [batchGenA cancelAllCGImageGeneration];
        [batchGenB cancelAllCGImageGeneration];
    }

    double clamp(double t) const {
        return (t < 0.0) ? 0.0 : (t > duration ? duration : t);
    }

    // Write a CGImage to outPath as JPEG.
    static bool writeJPEG(CGImageRef img, NSString* outPath) {
        NSURL* u = [NSURL fileURLWithPath:outPath];
        CGImageDestinationRef dst = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)u, (__bridge CFStringRef)@"public.jpeg", 1, nil);
        if (!dst) return false;
        NSDictionary* props = @{
            (__bridge NSString*)kCGImageDestinationLossyCompressionQuality: @(0.85f)
        };
        CGImageDestinationAddImage(dst, img, (__bridge CFDictionaryRef)props);
        bool ok = CGImageDestinationFinalize(dst);
        CFRelease(dst);
        return ok;
    }

    // Write a CGImage to outPath — JPEG for .jpg, PNG for .png.
    static bool writeFile(CGImageRef img, NSString* path) {
        bool isPNG = [[path.pathExtension lowercaseString] isEqualToString:@"png"];
        NSString* uti = isPNG ? @"public.png" : @"public.jpeg";
        NSURL* u = [NSURL fileURLWithPath:path];
        CGImageDestinationRef dst = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)u, (__bridge CFStringRef)uti, 1, nil);
        if (!dst) return false;
        NSDictionary* props = isPNG ? nil : @{
            (__bridge NSString*)kCGImageDestinationLossyCompressionQuality: @(0.92f)
        };
        CGImageDestinationAddImage(dst, img, props ? (__bridge CFDictionaryRef)props : nil);
        bool ok = CGImageDestinationFinalize(dst);
        CFRelease(dst);
        return ok;
    }

    // Synchronous random-access decode.  Used for scrubbing and when a batch misses.
    std::string decodeSync(double timePos, int maxW, int maxH) {
        timePos = clamp(timePos);
        long long ms = (long long)(timePos * 1000.0 + 0.5);
        std::string out = cacheFramePath(pathHash, ms, maxW, maxH);
        NSString* outPath = [NSString stringWithUTF8String:out.c_str()];

        if (![[NSFileManager defaultManager] fileExistsAtPath:outPath]) {
            @autoreleasepool {
                gen.maximumSize = CGSizeMake((CGFloat)maxW, (CGFloat)maxH);
                CMTime t = CMTimeMakeWithSeconds(timePos, 600);
                NSError* err = nil; CMTime actual;
                CGImageRef img = [gen copyCGImageAtTime:t actualTime:&actual error:&err];
                if (!img) return "";
                bool ok = writeJPEG(img, outPath);
                CGImageRelease(img);
                if (!ok) return "";
            }
        }
        cacheTouch(out, 0);
        return out;
    }

    // Synchronous frame extraction to a caller-specified path (.jpg or .png).
    bool extractTo(double timePos, int maxW, int maxH, const char* outputPath) {
        timePos = clamp(timePos);
        @autoreleasepool {
            gen.maximumSize = CGSizeMake((CGFloat)maxW, (CGFloat)maxH);
            CMTime t = CMTimeMakeWithSeconds(timePos, 600);
            NSError* err = nil; CMTime actual;
            CGImageRef img = [gen copyCGImageAtTime:t actualTime:&actual error:&err];
            if (!img) return false;
            NSString* destPath = [NSString stringWithUTF8String:outputPath];
            bool ok = writeFile(img, destPath);
            CGImageRelease(img);
            return ok;
        }
    }

    // Low-level: start an async batch on a specific generator without cancelling anything.
    void _kickOnGen(AVAssetImageGenerator* g, double startTime, int w, int h) {
        g.maximumSize = CGSizeMake((CGFloat)w, (CGFloat)h);

        NSMutableArray* times = [NSMutableArray arrayWithCapacity:BATCH_SIZE];
        for (int i = 0; i < BATCH_SIZE; i++) {
            double t = startTime + i * frameDur;
            if (t > duration) break;
            [times addObject:[NSValue valueWithCMTime:CMTimeMakeWithSeconds(t, 600)]];
        }
        if (times.count == 0) return;

        uint32_t ph_cap = pathHash;
        int w_cap = w, hh_cap = h;
        [g generateCGImagesAsynchronouslyForTimes:times
            completionHandler:^(CMTime requestedTime, CGImageRef image,
                                CMTime actualTime,
                                AVAssetImageGeneratorResult result,
                                NSError* error) {
            if (result != AVAssetImageGeneratorSucceeded || !image) return;
            double pts = CMTimeGetSeconds(requestedTime);
            long long ms2 = (long long)(pts * 1000.0 + 0.5);
            std::string out = cacheFramePath(ph_cap, ms2, w_cap, hh_cap);
            NSString* outPath = [NSString stringWithUTF8String:out.c_str()];
            if ([[NSFileManager defaultManager] fileExistsAtPath:outPath]) return;
            @autoreleasepool {
                // Counts as newly used even though playback has not reached it yet: it
                // is about to be, and the frame on screen was touched by getFrame so it
                // sits ahead of the whole batch either way.
                if (writeJPEG(image, outPath)) cacheTouch(out, 0);
            }
        }];
    }

    // Normal sequential advance: cancel only the IDLE generator, repurpose it for the
    // next window, then swap active/idle.  The currently-running generator is untouched
    // so its in-flight P-frame chain continues writing files without interruption.
    void kickNextBatch(double startTime, int w, int h) {
        startTime = clamp(startTime);
        if (startTime >= duration) return;

        // Already tracking this window
        if (std::abs(startTime - batchStartTime) < frameDur * 0.5 &&
            w == batchW && h == batchH) return;

        // Cancel idle generator and repurpose it
        AVAssetImageGenerator* idle = batchActiveIsA ? batchGenB : batchGenA;
        [idle cancelAllCGImageGeneration];

        // Swap so the newly-kicked generator becomes "active"
        batchActiveIsA = !batchActiveIsA;
        batchStartTime = startTime;
        batchW = w; batchH = h;

        _kickOnGen(batchActiveIsA ? batchGenA : batchGenB, startTime, w, h);
    }

    // Main entry point called by VP_GetFrame.
    std::string getFrame(double timePos, int maxW, int maxH) {
        timePos = clamp(timePos);

        // 1. Exact cache hit (same position as last call)
        if (cachedTimePos == timePos && cachedW == maxW && cachedH == maxH && !cachedPath.empty())
            return cachedPath;

        // 2. Check whether the async batch already wrote this frame to disk
        long long ms = (long long)(timePos * 1000.0 + 0.5);
        std::string framePath = cacheFramePath(pathHash, ms, maxW, maxH);
        NSString* outPath = [NSString stringWithUTF8String:framePath.c_str()];

        std::string result;
        bool fromBatch = [[NSFileManager defaultManager] fileExistsAtPath:outPath];

        if (fromBatch) {
            result = framePath;
            cacheTouch(result, 0);   // on screen now, so the newest thing in the cache
        } else {
            // 3. Sync decode (scrub or batch not yet ready)
            result = decodeSync(timePos, maxW, maxH);
        }

        if (!result.empty()) {
            cachedTimePos = timePos; cachedW = maxW; cachedH = maxH;
            cachedPath    = result;
        }

        if (!fromBatch) {
            // A miss means either a genuine seek or the batch is still warming up.
            double windowEnd = batchStartTime + BATCH_SIZE * frameDur;
            bool genuineSeek = (batchStartTime < 0 || maxW != batchW || maxH != batchH ||
                                timePos < batchStartTime - 2.0 ||
                                timePos > windowEnd   + 2.0);

            if (genuineSeek) {
                // Kick from BEFORE the seek point so AVFoundation builds P-frame state
                // in parallel with the main thread.
                double warmupStart = std::max(0.0, timePos - (BATCH_SIZE / 2) * frameDur);
                [batchGenA cancelAllCGImageGeneration];
                [batchGenB cancelAllCGImageGeneration];
                batchActiveIsA = true;
                batchStartTime = timePos;
                batchW = maxW; batchH = maxH;
                _kickOnGen(batchGenA, warmupStart, maxW, maxH);
                // fall through to cache the sync-decoded result below
            } else {
                // Warmup miss: batch is building P-frame state — don't stall the main
                // thread with a sync decode.  Return the last good frame instead; the
                // next call will retry the disk check once the batch catches up.
                // Only fall back to sync decode when there is no prior frame at all.
                return cachedPath.empty() ? decodeSync(timePos, maxW, maxH) : cachedPath;
            }
        } else {
            // 4. Advance to the next batch window at the midpoint WITHOUT cancelling the
            //    active generator — it keeps writing frames until the idle one is ready.
            double batchMid = batchStartTime + (BATCH_SIZE / 2) * frameDur;
            if (batchStartTime < 0 || timePos >= batchMid || maxW != batchW || maxH != batchH) {
                kickNextBatch(timePos + frameDur, maxW, maxH);
            }
        }

        return result;
    }
};

// -----------------------------------------------------------------------
// Registry
// -----------------------------------------------------------------------
static std::mutex              g_mu;
static std::map<int, Decoder*> g_decoders;
static std::atomic<int>        g_nextHandle{1};

static Decoder* getDecoder(int h) {
    auto it = g_decoders.find(h);
    return (it != g_decoders.end()) ? it->second : nullptr;
}

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------
static int VP_Open(const char* filePath) {
    if (!filePath || !filePath[0]) return 0;
    int h = g_nextHandle++;
    auto* dec = new Decoder(filePath, h);
    if (dec->duration <= 0.0) { delete dec; return 0; }
    std::lock_guard<std::mutex> lk(g_mu);
    g_decoders[h] = dec;
    return h;
}

static double VP_GetDuration(int handle) {
    std::lock_guard<std::mutex> lk(g_mu);
    Decoder* d = getDecoder(handle);
    return d ? d->duration : 0.0;
}

static const char* VP_GetFrame(int handle, double timePos, int maxW, int maxH) {
    static char sBuf[4096];
    Decoder* d;
    {
        std::lock_guard<std::mutex> lk(g_mu);
        d = getDecoder(handle);
    }
    if (!d) { sBuf[0] = '\0'; return sBuf; }
    std::string path = d->getFrame(timePos, maxW, maxH);
    snprintf(sBuf, sizeof(sBuf), "%s", path.c_str());
    return sBuf;
}

static void VP_Close(int handle) {
    Decoder* d = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mu);
        auto it = g_decoders.find(handle);
        if (it != g_decoders.end()) { d = it->second; g_decoders.erase(it); }
    }
    delete d;
}

static int VP_ExtractFrame(int handle, double timePos, int maxW, int maxH, const char* outputPath) {
    Decoder* d;
    {
        std::lock_guard<std::mutex> lk(g_mu);
        d = getDecoder(handle);
    }
    if (!d || !outputPath || !outputPath[0]) return 0;
    return d->extractTo(timePos, maxW, maxH, outputPath) ? 1 : 0;
}

// -----------------------------------------------------------------------
// Vararg wrappers
// -----------------------------------------------------------------------
static void* VA_VP_Open(void** args, int nargs) {
    if (nargs < 1) return (void*)(intptr_t)0;
    return (void*)(intptr_t)VP_Open((const char*)args[0]);
}
static double g_durResult;
static void* VA_VP_GetDuration(void** args, int nargs) {
    if (nargs < 1) return nullptr;
    g_durResult = VP_GetDuration((int)(intptr_t)args[0]);
    return &g_durResult;
}
static void* VA_VP_GetFrame(void** args, int nargs) {
    if (nargs < 4) return (void*)"";
    return (void*)VP_GetFrame((int)(intptr_t)args[0], *(double*)args[1],
                               (int)(intptr_t)args[2], (int)(intptr_t)args[3]);
}
static void* VA_VP_Close(void** args, int nargs) {
    if (nargs >= 1) VP_Close((int)(intptr_t)args[0]);
    return nullptr;
}
static void* VA_VP_ExtractFrame(void** args, int nargs) {
    if (nargs < 5) return (void*)(intptr_t)0;
    int r = VP_ExtractFrame((int)(intptr_t)args[0], *(double*)args[1],
                            (int)(intptr_t)args[2], (int)(intptr_t)args[3],
                            (const char*)args[4]);
    return (void*)(intptr_t)r;
}

// -----------------------------------------------------------------------
// Plugin entry
// -----------------------------------------------------------------------
static const VPFunc kFuncs[] = {
    { "VP_Open",        (void*)VP_Open,        (void*)VA_VP_Open,
      "int",         "const char*",         "filePath",
      "Open video file. Returns handle (>0) or 0 on error." },
    { "VP_GetDuration", (void*)VP_GetDuration, (void*)VA_VP_GetDuration,
      "double",      "int",                 "handle",
      "Video duration in seconds." },
    { "VP_GetFrame",    (void*)VP_GetFrame,    (void*)VA_VP_GetFrame,
      "const char*", "int,double,int,int",  "handle,timePos,maxW,maxH",
      "Return JPEG path for frame at timePos. Async batch keeps upcoming frames on disk." },
    { "VP_Close",       (void*)VP_Close,       (void*)VA_VP_Close,
      "void",        "int",                 "handle",
      "Close decoder and release resources." },
    { "VP_ExtractFrame", (void*)VP_ExtractFrame, (void*)VA_VP_ExtractFrame,
      "int", "int,double,int,int,const char*", "handle,timePos,maxW,maxH,outputPath",
      "Extract frame at timePos to outputPath (.jpg or .png). Returns 1 on success." },
};
static const int kNumFuncs = (int)(sizeof(kFuncs) / sizeof(kFuncs[0]));

// REAPER holds onto the APIdef_ pointer for the plugin's lifetime, so the packed
// "ret\0args\0names\0desc\0" block is allocated once and deliberately never freed.
static void registerFuncs(const VPFunc* fns, int count) {
    for (int i = 0; i < count; i++) {
        const VPFunc& f = fns[i];
        plugin_register((std::string("API_")       + f.name).c_str(), f.func);
        plugin_register((std::string("APIvararg_") + f.name).c_str(), f.vararg);

        // "ret\0args\0names\0desc\0", with a spare zero byte so the block also reads as
        // an empty terminating field.
        size_t n = strlen(f.retType) + strlen(f.argTypes) + strlen(f.argNames) + strlen(f.desc) + 5;
        char* def = (char*)calloc(1, n);
        if (!def) continue;
        size_t p = 0;
        auto put = [&](const char* s) { size_t l = strlen(s) + 1; memcpy(def + p, s, l); p += l; };
        put(f.retType); put(f.argTypes); put(f.argNames); put(f.desc);
        plugin_register((std::string("APIdef_") + f.name).c_str(), def);
    }
}

static void unregisterFuncs(const VPFunc* fns, int count) {
    for (int i = 0; i < count; i++) {
        plugin_register((std::string("-API_")       + fns[i].name).c_str(), fns[i].func);
        plugin_register((std::string("-APIvararg_") + fns[i].name).c_str(), fns[i].vararg);
        plugin_register((std::string("-APIdef_")    + fns[i].name).c_str(), nullptr);
    }
}

extern "C" REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(
    REAPER_PLUGIN_HINSTANCE, reaper_plugin_info_t* rec)
{
    if (!rec) {
        if (plugin_register) {
            unregisterFuncs(kFuncs, kNumFuncs);
            unregisterFuncs(g_frameStoreFuncs, g_frameStoreFuncCount);
            unregisterFuncs(g_matcherFuncs, g_matcherFuncCount);
            unregisterFuncs(g_audioStoreFuncs, g_audioStoreFuncCount);
        }
        frameStoreShutdown();
        audioStoreShutdown();
        std::lock_guard<std::mutex> lk(g_mu);
        for (auto& kv : g_decoders) delete kv.second;
        g_decoders.clear();
        return 0;
    }
    if (rec->caller_version != REAPER_PLUGIN_VERSION) return 0;
    plugin_register = rec->Register;
    if (!plugin_register) return 0;

    // Silent on success. Whether the functions arrived is already observable from
    // ReaScript -- the editor checks for VP_Analyze and says so in its own UI -- so a
    // console line on every REAPER launch only trains people to ignore the console.
    registerFuncs(kFuncs, kNumFuncs);

    // Takes over whatever earlier sessions left behind and trims it to the budget, on a
    // background thread so REAPER's startup never waits on it.
    cacheAdoptExisting();
    registerFuncs(g_frameStoreFuncs, g_frameStoreFuncCount);
    registerFuncs(g_matcherFuncs, g_matcherFuncCount);
    registerFuncs(g_audioStoreFuncs, g_audioStoreFuncCount);
    return 1;
}
