@echo off
rem Alternative to build.sh: builds the NKI Importer extension for 64-bit Windows REAPER with
rem Visual Studio into the package folder and installs it into UserPlugins.
rem Run from an "x64 Native Tools Command Prompt for VS" (Visual Studio Build Tools, C++ workload).
rem Restart REAPER afterwards.
cd /d "%~dp0"
if not exist build mkdir build
cl /nologo /O2 /EHsc /LD /std:c++17 nki_importer.cpp /Fobuild\ /Fe:..\reaper_nki_importer-x64.dll user32.lib shell32.lib || exit /b 1
copy /y ..\reaper_nki_importer-x64.dll "%APPDATA%\REAPER\UserPlugins\" || exit /b 1
echo Installed reaper_nki_importer-x64.dll - restart REAPER
