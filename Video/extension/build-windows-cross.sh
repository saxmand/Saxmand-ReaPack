#!/bin/sh
# Cross-builds the Windows x64 DLL from macOS or Linux with mingw-w64.
#   brew install mingw-w64      (or your distribution's package)
#
# This exists because the Windows half of the extension has to be built by whoever
# changes it, and waiting for a Windows machine to find a typo is a slow way to work.
# What it produces is a real DLL: PE32+, exporting ReaperPluginEntry, depending only on
# KERNEL32 and the Universal CRT that ships with Windows.
#
# What it cannot do is RUN the thing. Compiling proves the code is valid; only REAPER on
# Windows proves it works. Treat a successful build here as the start of testing.
#
# build-windows.bat does the same job with Visual Studio, for building on Windows itself.
set -e
cd "$(dirname "$0")"
PACKAGE=..
CXX=${CXX:-x86_64-w64-mingw32-g++}

command -v "$CXX" >/dev/null 2>&1 || {
    echo "$CXX not found - install mingw-w64 (brew install mingw-w64)" >&2
    exit 1
}

# -static and friends so the result needs no mingw runtime DLLs beside it: a user
# installing through ReaPack gets one file, not four.
"$CXX" -std=c++17 -O2 -shared -DNDEBUG \
  -o "$PACKAGE/reaper_video_preview-x64.dll" \
  video_preview.cpp \
  video_decoder_win.cpp \
  frame_source_win.cpp \
  audio_source_win.cpp \
  frame_cache.cpp \
  frame_store.cpp \
  matcher.cpp \
  audio_store.cpp \
  -static -static-libgcc -static-libstdc++ \
  -lole32 -luser32 -lshell32

x86_64-w64-mingw32-strip -s "$PACKAGE/reaper_video_preview-x64.dll"
echo "Built $PACKAGE/reaper_video_preview-x64.dll"
x86_64-w64-mingw32-objdump -p "$PACKAGE/reaper_video_preview-x64.dll" \
    | grep -q ReaperPluginEntry \
    && echo "  exports ReaperPluginEntry" \
    || { echo "  ERROR: entry point missing" >&2; exit 1; }
