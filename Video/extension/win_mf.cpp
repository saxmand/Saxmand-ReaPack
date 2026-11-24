#ifdef _WIN32

#include "win_mf.h"

#include <windows.h>
#include <mfapi.h>
#include <mutex>

// MFStartup is reference counted by Windows, but calling it once and never shutting
// down is both simpler and correct here: the extension's decoders come and go for the
// whole life of the REAPER session, and tearing MF down between them would only add a
// way to get the ordering wrong.
bool mfEnsureStarted() {
    static std::once_flag once;
    static bool ok = false;
    std::call_once(once, []{
        // NOSOCKET: no network sources are wanted, and it skips that initialisation.
        ok = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET));
    });
    return ok;
}

static std::mutex  g_backendMu;
static std::string g_backend = "none";

void mfNoteBackend(const char* name) {
    std::lock_guard<std::mutex> lk(g_backendMu);
    g_backend = name ? name : "none";
}

const char* mfLastBackend() {
    // Returned as a pointer into a static string: the diagnostics print it immediately
    // and nothing holds onto it.
    static std::string copy;
    std::lock_guard<std::mutex> lk(g_backendMu);
    copy = g_backend;
    return copy.c_str();
}

#endif
