// The bounded, least-recently-used cache of decoded frames. See frame_cache.h for why
// it exists and why the frames are files rather than memory.

#include "frame_cache.h"

#include <algorithm>
#include <list>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <sys/stat.h>

#include "vp_fileio.h"

#ifdef _WIN32
  #include <windows.h>
#else
  #include <dirent.h>
  #include <unistd.h>
#endif

const uint64_t CACHE_BUDGET_BYTES = 256ull * 1024ull * 1024ull;
// Bumped whenever a fix changes which picture a given time resolves to. The cache is
// content-addressed by path, time and size and nothing else, so without this a frame
// written by a build that picked the wrong frame is handed straight back by the build
// that fixed it -- which is exactly what happened: thumbnails stayed wrong after the
// seek fix because they were never decoded again.
//   vp2_  up to 1.3.1: Windows seeks returned the preceding keyframe, and coded
//         padding was included in the picture
const char*    CACHE_PREFIX       = "vp3_";

// Retired prefixes, swept on startup. Without this they are orphaned: eviction only
// ever looks at the current prefix, so the old files would sit in the temporary folder
// for good -- and this cache has already filled a disk once.
static const char* CACHE_RETIRED[] = { "vp2_" };

uint32_t hashPath(const char* s) {
    uint32_t h = 2166136261u;
    while (*s) { h ^= (uint8_t)*s++; h *= 16777619u; }
    return h;
}

std::string cacheDir() {
#ifdef _WIN32
    // GetTempPathW returns a path ending in a backslash, and honours TMP/TEMP, which is
    // where Windows puts per-user scratch. Converted to UTF-8 because every path in this
    // extension is UTF-8, REAPER's included.
    wchar_t w[MAX_PATH + 1];
    DWORD n = GetTempPathW(MAX_PATH, w);
    if (n == 0 || n > MAX_PATH) return std::string("C:\\Windows\\Temp\\");
    int need = WideCharToMultiByte(CP_UTF8, 0, w, (int)n, nullptr, 0, nullptr, nullptr);
    std::string out(need, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w, (int)n, &out[0], need, nullptr, nullptr);
    return out;
#else
    return std::string("/tmp/");
#endif
}

std::string cacheFramePath(uint32_t pathHash, long long ms, int w, int h) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%s%u_%lld_%dx%d.jpg", CACHE_PREFIX, pathHash, ms, w, h);
    return cacheDir() + buf;
}

// Touched from decoder worker threads as well as the main thread.
static std::mutex g_cacheMu;
static std::list<std::string>                                  g_lru;      // front = newest
static std::map<std::string, std::list<std::string>::iterator> g_lruPos;
static std::map<std::string, uint64_t>                         g_lruSize;
static uint64_t                                                g_lruBytes = 0;

// Drops the coldest files until the total is back inside the budget. Caller holds the
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
        vpRemove(victim);
        removed++;
    }
    return removed;
}

void cacheTouch(const std::string& path, uint64_t bytes) {
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
        uint64_t sz = 0;
        if (!vpStat(path, &sz, nullptr)) return;   // vanished; nothing to track
        bytes = sz;
    }

    g_lru.push_front(path);
    g_lruPos[path]  = g_lru.begin();
    g_lruSize[path] = bytes;
    g_lruBytes     += bytes;
    cacheEvictLocked();
}

namespace {
struct Found { std::string path; uint64_t bytes; double mtime; };

// Every cache file in the temporary folder, with its size and age.
void listCacheFiles(const char* prefixIn, std::vector<Found>* out) {
    const std::string dir    = cacheDir();
    const std::string prefix = prefixIn;
#ifdef _WIN32
    std::string pat = dir + prefix + "*.jpg";
    int need = MultiByteToWideChar(CP_UTF8, 0, pat.c_str(), (int)pat.size(), nullptr, 0);
    std::wstring wpat(need, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, pat.c_str(), (int)pat.size(), &wpat[0], need);

    WIN32_FIND_DATAW fd{};
    HANDLE h = FindFirstFileW(wpat.c_str(), &fd);
    if (h == INVALID_HANDLE_VALUE) return;
    do {
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
        int n = WideCharToMultiByte(CP_UTF8, 0, fd.cFileName, -1, nullptr, 0, nullptr, nullptr);
        std::string name(n > 0 ? n - 1 : 0, '\0');
        if (n > 0) WideCharToMultiByte(CP_UTF8, 0, fd.cFileName, -1, &name[0], n, nullptr, nullptr);
        uint64_t size = ((uint64_t)fd.nFileSizeHigh << 32) | fd.nFileSizeLow;
        // FILETIME is 100 ns units since 1601; only the ordering matters here.
        uint64_t ft = ((uint64_t)fd.ftLastWriteTime.dwHighDateTime << 32)
                    | fd.ftLastWriteTime.dwLowDateTime;
        out->push_back({ dir + name, size, (double)ft });
    } while (FindNextFileW(h, &fd));
    FindClose(h);
#else
    DIR* d = opendir(dir.c_str());
    if (!d) return;
    struct dirent* e;
    while ((e = readdir(d)) != nullptr) {
        std::string name = e->d_name;
        if (name.size() <= prefix.size() || name.compare(0, prefix.size(), prefix) != 0) continue;
        if (name.size() < 4 || name.compare(name.size() - 4, 4, ".jpg") != 0) continue;
        std::string full = dir + name;
        uint64_t sz = 0; int64_t mt = 0;
        if (!vpStat(full, &sz, &mt)) continue;
        out->push_back({ full, sz, (double)mt });
    }
    closedir(d);
#endif
}
} // namespace

uint64_t cacheUsage(int* files) {
    std::vector<Found> found;
    listCacheFiles(CACHE_PREFIX, &found);
    uint64_t total = 0;
    for (const Found& f : found) total += f.bytes;
    if (files) *files = (int)found.size();
    return total;
}

int cacheClear() {
    // The index goes first and under the lock, so a decoder thread that is mid-touch
    // cannot re-insert a path that is about to be deleted.
    {
        std::lock_guard<std::mutex> lk(g_cacheMu);
        g_lru.clear();
        g_lruPos.clear();
        g_lruSize.clear();
        g_lruBytes = 0;
    }
    std::vector<Found> found;
    listCacheFiles(CACHE_PREFIX, &found);
    int removed = 0;
    for (const Found& f : found) if (vpRemove(f.path) == 0) removed++;
    return removed;
}

void cacheAdoptExisting() {
    std::thread([]{
        // Retired generations go first, so their space is freed before the budget is
        // applied to what is still valid.
        for (const char* old : CACHE_RETIRED) {
            std::vector<Found> stale;
            listCacheFiles(old, &stale);
            for (const Found& f : stale) vpRemove(f.path);
        }

        std::vector<Found> found;
        listCacheFiles(CACHE_PREFIX, &found);
        // Oldest adopted first so it sits at the cold end and is evicted first.
        std::sort(found.begin(), found.end(),
                  [](const Found& a, const Found& b) { return a.mtime < b.mtime; });
        for (const Found& f : found) cacheTouch(f.path, f.bytes);
    }).detach();
}
