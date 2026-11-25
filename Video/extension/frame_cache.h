#pragma once

#include <cstdint>
#include <string>

// The on-disk cache of decoded frames, and the budget that keeps it from growing
// without end. Plain C++: the only platform-specific part is listing a directory, which
// is a dozen lines at the bottom of frame_cache.cpp.
//
// Frames are content-addressed, so a name always identifies the same picture and a
// cached file can be reused forever. That was the whole design, and the flaw in it:
// nothing ever deleted anything, so seven videos had left 138,468 files and 7.69 GB in
// the temporary folder.
//
// Going through memory instead turned out to be impossible: REAPER hands a `char*`
// out-parameter to Lua with strlen, so a JPEG arrives cut off at its first null byte
// (measured -- 3 bytes of an 8-byte pattern survive). JS_ReaScriptAPI's JS_String, the
// one function built to read raw memory into Lua, uses that same convention, so there
// is no way around it from an extension.
//
// So the files stay, and are simply kept to a budget. The decode cost is what matters
// and the writes were never the problem: a working set this small never leaves the
// operating system's page cache, so reading a frame back does not touch the disk at
// all. It behaves like the in-memory cache while remaining a plain path, which is what
// ReaImGui wants anyway.

// 256 MB is ~4,400 frames at the 58 KB a 640x360 JPEG averages. Playback needs about
// 200 (one batch window ahead for each of the two videos being compared), so there is
// ample room for timeline thumbnails to survive a playthrough and still be there
// afterwards.
// The budget, settable at runtime because what it should be depends on the machine and
// the footage: 256 MB is ample for 640x360 previews and nowhere near enough to keep a
// long comparison warm at a higher preview resolution. Lowering it evicts down to the
// new figure straight away.
uint64_t cacheBudget();
void     cacheSetBudget(uint64_t bytes);

// The range the setting is held to. The floor is what one prefetch window of two videos
// needs at a generous frame size -- below it the window would evict its own frames
// before playback reached them, which is slower than having no cache at all.
static const uint64_t CACHE_BUDGET_MIN = 32ull  * 1024ull * 1024ull;
static const uint64_t CACHE_BUDGET_MAX = 8192ull * 1024ull * 1024ull;
static const uint64_t CACHE_BUDGET_DEFAULT = 256ull * 1024ull * 1024ull;
extern const char*    CACHE_PREFIX;

// Where the cached frames live. The system temporary folder, which is also why they
// survive a REAPER restart and why something has to bound them.
std::string cacheDir();

std::string cacheFramePath(uint32_t pathHash, long long ms, int w, int h);

// Records a frame as the newest thing in the cache, evicting to stay inside the budget.
// `bytes` is 0 when the size is not already known, in which case it is read from disk.
void cacheTouch(const std::string& path, uint64_t bytes);

// Adopts whatever earlier sessions left behind, then evicts down to the budget. Runs on
// a thread of its own: this is the pass that has gigabytes to walk the first time, and
// REAPER should not wait for it to start up.
void cacheAdoptExisting();

// What the cache currently occupies on disk: total bytes, and the number of files in
// `files` when it is not null. Measured by listing the folder rather than reported from
// the in-memory index, so it is the truth even before the adopt pass has run and even
// if something outside this process has been at the files.
uint64_t cacheUsage(int* files);

// Deletes every cached frame of the current generation and empties the index. Returns
// how many files went. Frames reappear as they are decoded again, so this costs time,
// never correctness.
int cacheClear();

// FNV-1a of a file path -- the cache-file discriminator, so frames from different videos
// never share a slot even when handles are reused across restarts.
uint32_t hashPath(const char* s);
