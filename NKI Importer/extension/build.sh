#!/bin/sh
# Builds the NKI Importer extension into the package folder (next to reaper_nki_importer.ext,
# where ReaPack picks them up):
#   macOS (universal: Apple Silicon + Intel) - also installed into REAPER's UserPlugins
#   Windows x64 (needs `brew install mingw-w64`)
# Restart REAPER afterwards. Bump @version in reaper_nki_importer.ext when releasing.
set -e
cd "$(dirname "$0")"
PACKAGE=..

clang++ -std=c++17 -O2 -dynamiclib -arch arm64 -arch x86_64 -mmacosx-version-min=10.13 \
  -fvisibility=hidden -lobjc \
  -o "$PACKAGE/reaper_nki_importer.dylib" nki_importer.cpp

PLUGINS="$HOME/Library/Application Support/REAPER/UserPlugins"
rm -f "$PLUGINS/reaper_nki_importer-arm64.dylib" # older arm64-only build, would load twice
cp "$PACKAGE/reaper_nki_importer.dylib" "$PLUGINS/"
echo "Built reaper_nki_importer.dylib and installed it - restart REAPER"

if command -v x86_64-w64-mingw32-g++ >/dev/null; then
  x86_64-w64-mingw32-g++ -std=c++17 -O2 -s -shared -static -static-libgcc -static-libstdc++ \
    -o "$PACKAGE/reaper_nki_importer-x64.dll" nki_importer.cpp -luser32 -lshell32
  echo "Built reaper_nki_importer-x64.dll (Windows)"
else
  echo "mingw-w64 not found - Windows build skipped"
fi
