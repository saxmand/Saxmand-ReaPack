@echo off
rem Builds the video_preview extension for 64-bit Windows REAPER with Visual Studio
rem into the package folder, and installs it into UserPlugins.
rem Run from an "x64 Native Tools Command Prompt for VS" (Visual Studio Build Tools,
rem C++ workload). Restart REAPER afterwards.
rem
rem Windows decodes through the ffmpeg binary rather than in-process, so there is
rem nothing to link against here and no SDK to install beyond the compiler. ffmpeg has
rem to be present at run time: the script passes its path to the extension, or it is
rem found on PATH.
cd /d "%~dp0"
if not exist build mkdir build

cl /nologo /O2 /EHsc /LD /std:c++17 /MT /DNDEBUG ^
  video_preview.cpp ^
  video_decoder_win.cpp ^
  frame_source_win.cpp ^
  audio_source_win.cpp ^
  frame_cache.cpp ^
  frame_store.cpp ^
  matcher.cpp ^
  audio_store.cpp ^
  /Fobuild\ /Fe:..\reaper_video_preview-x64.dll ^
  user32.lib shell32.lib || exit /b 1

copy /y ..\reaper_video_preview-x64.dll "%APPDATA%\REAPER\UserPlugins\" || exit /b 1
echo Installed reaper_video_preview-x64.dll - restart REAPER
