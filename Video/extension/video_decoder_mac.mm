// video_decoder, macOS: AVFoundation.
//
// Decode strategy:
//   Sequential (playback):  Dual ping-pong async batch generators. Each batch requests
//                           BATCH_SIZE frames; the generators hand off at the midpoint so
//                           the active one is never cancelled during normal playback --
//                           only the idle generator is repurposed for the next window.
//                           The entire GOP is decoded in one sequential P-frame pass that
//                           starts long before those frames are needed, so the main thread
//                           always finds the file already on disk, with no stall.
//   Random access (scrub):  copyCGImageAtTime, ~5-30 ms. On any seek or batch miss both
//                           generators are cancelled and the batch restarts from there.
//
// Lifted out of video_preview, which is now platform-free. The prefetching is the part
// worth keeping in mind: it is why scrubbing and playback feel immediate. Windows has
// the same thing now, built by hand in video_decoder_mf.cpp -- Media Foundation has no
// asynchronous batch decode, so there is a worker thread with a reader of its own in
// place of these two generators.

#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <Foundation/Foundation.h>

#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <mutex>
#include <string>

#include "video_decoder.h"
#include "frame_cache.h"

namespace {
struct Decoder : public VideoDecoder {
    AVAssetImageGenerator* gen       = nil;  // sync (copyCGImageAtTime, main thread)
    AVAssetImageGenerator* batchGenA = nil;  // ping-pong async batch generators
    AVAssetImageGenerator* batchGenB = nil;
    bool batchActiveIsA = true;  // which generator holds the most-recently-kicked batch

    double   dur       = 0.0;   // named apart from duration(), the interface's accessor
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

            dur = CMTimeGetSeconds(asset.duration);

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

    double duration() const override { return dur; }

    double clamp(double t) const {
        return (t < 0.0) ? 0.0 : (t > dur ? dur : t);
    }

    // Write a CGImage to outPath as JPEG.
    // Writes through a sibling temp file and renames into place.
    //
    // The batch generators write frames from their own queues while the main thread is
    // checking for them, so a direct write is visible half-finished: the file exists,
    // has a size, and is not a picture yet. A rename is atomic, so a frame is either
    // absent or complete -- and an interrupted write leaves nothing corrupt behind to be
    // served from the cache ever after.
    static bool writeJPEGAtomic(CGImageRef img, NSString* outPath) {
        static std::atomic<unsigned> seq{0};
        NSString* tmp = [outPath stringByAppendingFormat:@".%u.tmp",
                         seq.fetch_add(1)];
        NSFileManager* fm = [NSFileManager defaultManager];
        if (!writeJPEG(img, tmp)) { [fm removeItemAtPath:tmp error:nil]; return false; }
        NSError* err = nil;
        if (![fm moveItemAtPath:tmp toPath:outPath error:&err]) {
            // Losing the race to another writer is success: the frame is there, and it
            // is the same frame either way.
            bool present = [fm fileExistsAtPath:outPath];
            [fm removeItemAtPath:tmp error:nil];
            return present;
        }
        return true;
    }

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
                bool ok = writeJPEGAtomic(img, outPath);
                CGImageRelease(img);
                if (!ok) return "";
            }
        }
        cacheTouch(out, 0);
        return out;
    }

    // Synchronous frame extraction to a caller-specified path (.jpg or .png).
    bool extractTo(double timePos, int maxW, int maxH, const char* outputPath) override {
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
            if (t > dur) break;
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
                if (writeJPEGAtomic(image, outPath)) cacheTouch(out, 0);
            }
        }];
    }

    // Normal sequential advance: cancel only the IDLE generator, repurpose it for the
    // next window, then swap active/idle.  The currently-running generator is untouched
    // so its in-flight P-frame chain continues writing files without interruption.
    void kickNextBatch(double startTime, int w, int h) {
        startTime = clamp(startTime);
        if (startTime >= dur) return;

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
    std::string getFrame(double timePos, int maxW, int maxH) override {
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
} // namespace

VideoDecoder* videoDecoderOpen(const char* path, std::string* err) {
    if (!path || !path[0]) { if (err) *err = "no path"; return nullptr; }
    Decoder* d = new Decoder(path, (int)hashPath(path));
    if (d->dur <= 0.0) {
        delete d;
        if (err) *err = "could not open video";
        return nullptr;
    }
    return d;
}
