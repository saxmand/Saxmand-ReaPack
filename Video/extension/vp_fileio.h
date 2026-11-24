#pragma once

#include <cstdint>
#include <cstdio>
#include <string>

// File access that works with the UTF-8 paths this extension uses everywhere.
//
// On Windows the narrow CRT calls -- fopen, stat, remove, rename -- interpret their
// path bytes in the ANSI code page, not UTF-8. REAPER hands paths over as UTF-8, and
// the temporary folder is under the user's own name, so on any machine whose user name
// or media folders are not plain ASCII the narrow calls simply fail to find files that
// are plainly there. The wide calls are the only correct ones, and this is the smallest
// shim that keeps the shared code from having to care.
//
// Everywhere else these are the ordinary functions under another name.

FILE*    vpFopen(const std::string& path, const char* mode);
bool     vpStat(const std::string& path, uint64_t* size, int64_t* mtime);
int      vpRemove(const std::string& path);
int      vpRename(const std::string& from, const std::string& to);
