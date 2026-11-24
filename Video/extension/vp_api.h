#pragma once

// One exported Lua-visible function. Modules publish a table of these; the plugin
// entrypoint in video_preview.mm registers every table it knows about.
struct VPFunc {
    const char* name;
    void*       func;
    void*       vararg;
    const char* retType;
    const char* argTypes;
    const char* argNames;
    const char* desc;
};

// frame_store.mm
extern const VPFunc g_frameStoreFuncs[];
extern const int    g_frameStoreFuncCount;
void frameStoreShutdown();

// audio_store.mm
extern const VPFunc g_audioStoreFuncs[];
extern const int    g_audioStoreFuncCount;
void audioStoreShutdown();

// matcher.mm
extern const VPFunc g_matcherFuncs[];
extern const int    g_matcherFuncCount;
