#!/bin/sh
# Builds the video_preview REAPER extension (macOS universal binary)
# and installs it into REAPER's UserPlugins folder.
# Restart REAPER after running.
set -e
cd "$(dirname "$0")"
PACKAGE=..

clang++ -std=c++17 -O2 -dynamiclib \
  -arch arm64 -arch x86_64 \
  -mmacosx-version-min=10.15 \
  -fvisibility=hidden \
  -fobjc-arc \
  -framework AVFoundation \
  -framework CoreMedia \
  -framework CoreGraphics \
  -framework CoreImage \
  -framework CoreVideo \
  -framework ImageIO \
  -framework Accelerate \
  -framework Foundation \
  -o "$PACKAGE/reaper_video_preview.dylib" \
  video_preview.mm \
  frame_store.mm \
  matcher.mm \
  audio_store.mm

PLUGINS="$HOME/Library/Application Support/REAPER/UserPlugins"
cp "$PACKAGE/reaper_video_preview.dylib" "$PLUGINS/"
echo "Built and installed reaper_video_preview.dylib — restart REAPER"
