// video_preview — REAPER extension for video frame extraction, fingerprinting and
// version matching.
//
// This file is the part that is the same everywhere: the handle registry, the exported
// API, and the plumbing REAPER needs to see it. Decoding lives behind two interfaces,
// one per access pattern, each with a macOS and a Windows implementation:
//
//   FrameSource    sequential, whole file, as fast as possible. Feeds fingerprinting,
//                  cut detection and version matching. AVAssetReader / ffmpeg pipe.
//   VideoDecoder   random access, one frame wherever the playhead is. Feeds previews
//                  and thumbnails. AVFoundation generators / one ffmpeg run per frame.
//
// Everything else -- the fingerprints, the cut detector, the matcher, the store format
// and the frame cache -- is plain C++ and shared, which is why both platforms produce
// identical results and can read each other's stores.
//
// Lua API (all accessible via reaper.*):
//   int    VP_Open(filePath)
//   double VP_GetDuration(handle)
//   string VP_GetFrame(handle, timePos, maxW, maxH)
//   int    VP_ExtractFrame(handle, timePos, maxW, maxH, outputPath)
//   void   VP_Close(handle)
//   void   VP_SetFFmpegPath(path)       -- Windows only; ignored on macOS

#include <atomic>
#include <map>
#include <mutex>
#include <string>
#include <cstdio>
#include <cstring>

#include "sdk/reaper_plugin.h"
#include "vp_api.h"
#include "video_decoder.h"
#include "frame_cache.h"
#include "frame_source.h"

static int (*plugin_register)(const char*, void*) = nullptr;

// -----------------------------------------------------------------------
// Registry
// -----------------------------------------------------------------------
static std::mutex                   g_mu;
static std::map<int, VideoDecoder*> g_decoders;
static std::atomic<int>             g_nextHandle{1};

static VideoDecoder* getDecoder(int h) {
    auto it = g_decoders.find(h);
    return (it != g_decoders.end()) ? it->second : nullptr;
}

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------
static int VP_Open(const char* filePath) {
    if (!filePath || !filePath[0]) return 0;
    std::string err;
    VideoDecoder* dec = videoDecoderOpen(filePath, &err);
    if (!dec) return 0;
    int h = g_nextHandle++;
    std::lock_guard<std::mutex> lk(g_mu);
    g_decoders[h] = dec;
    return h;
}

static double VP_GetDuration(int handle) {
    std::lock_guard<std::mutex> lk(g_mu);
    VideoDecoder* d = getDecoder(handle);
    return d ? d->duration() : 0.0;
}

static const char* VP_GetFrame(int handle, double timePos, int maxW, int maxH) {
    static char sBuf[4096];
    VideoDecoder* d;
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
    VideoDecoder* d = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mu);
        auto it = g_decoders.find(handle);
        if (it != g_decoders.end()) { d = it->second; g_decoders.erase(it); }
    }
    delete d;
}

static int VP_ExtractFrame(int handle, double timePos, int maxW, int maxH, const char* outputPath) {
    VideoDecoder* d;
    {
        std::lock_guard<std::mutex> lk(g_mu);
        d = getDecoder(handle);
    }
    if (!d || !outputPath || !outputPath[0]) return 0;
    return d->extractTo(timePos, maxW, maxH, outputPath) ? 1 : 0;
}

// Where ffmpeg is, for the platforms that decode through it. macOS ignores this; it is
// exported on both so the script can call it without caring which it is running on.
static void VP_SetFFmpegPath(const char* path) {
    frameSourceSetFFmpegPath(path ? path : "");
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
static void* VA_VP_SetFFmpegPath(void** args, int nargs) {
    if (nargs >= 1) VP_SetFFmpegPath((const char*)args[0]);
    return nullptr;
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
      "Return JPEG path for frame at timePos. On macOS an async batch keeps upcoming "
      "frames on disk; on Windows each frame is one ffmpeg run, so scrubbing is slower." },
    { "VP_Close",       (void*)VP_Close,       (void*)VA_VP_Close,
      "void",        "int",                 "handle",
      "Close decoder and release resources." },
    { "VP_ExtractFrame", (void*)VP_ExtractFrame, (void*)VA_VP_ExtractFrame,
      "int", "int,double,int,int,const char*", "handle,timePos,maxW,maxH,outputPath",
      "Extract frame at timePos to outputPath (.jpg or .png). Returns 1 on success." },
    { "VP_SetFFmpegPath", (void*)VP_SetFFmpegPath, (void*)VA_VP_SetFFmpegPath,
      "void", "const char*", "path",
      "Tell the extension where the ffmpeg binary is. Windows decodes through it, so "
      "cut detection and previews need this (or ffmpeg on PATH). Ignored on macOS, "
      "which decodes in-process -- safe to call on both." },
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
