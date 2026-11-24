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
extern const uint64_t CACHE_BUDGET_BYTES;
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

// FNV-1a of a file path -- the cache-file discriminator, so frames from different videos
// never share a slot even when handles are reused across restarts.
uint32_t hashPath(const char* s);
