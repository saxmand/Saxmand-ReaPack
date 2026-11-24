#pragma once
#ifdef _WIN32

// Media Foundation: Windows' own decoder, and the counterpart of AVFoundation on macOS.
//
// This exists so the extension needs nothing installed on Windows. Media Foundation is
// part of the OS and decodes the formats most deliveries arrive in -- H.264 and HEVC in
// MP4 or MOV, WMV -- using the same hardware paths the rest of Windows does.
//
// What it does NOT decode is ProRes and DNxHD, which have no Windows codec of their own
// and are exactly what film work tends to be cut on. So ffmpeg stays as a fallback: MF
// is tried first and ffmpeg picks up whatever it cannot open. Nothing has to be
// installed for the common case, and the awkward cases still work if ffmpeg is there.
//
// Both backends feed the same FrameSource / VideoDecoder / AudioSource interfaces, so
// nothing above this layer knows or cares which one answered.

#include <string>

#include "frame_source.h"
#include "video_decoder.h"
#include "audio_source.h"

// Starts Media Foundation once per process and keeps it up for the process's life.
// Returns false when MF is unavailable, which is the signal to go straight to ffmpeg.
bool mfEnsureStarted();

// Each backend's own entry point. nullptr with a reason in err on failure; the
// dispatchers in frame_source_win.cpp and friends decide which to try first.
FrameSource*  frameSourceOpenMF(const char* path, int w, int h, std::string* err);
FrameSource*  frameSourceOpenFFmpeg(const char* path, int w, int h, std::string* err);

VideoDecoder* videoDecoderOpenMF(const char* path, std::string* err);
VideoDecoder* videoDecoderOpenFFmpeg(const char* path, std::string* err);

AudioSource*  audioSourceOpenMF(const char* path, double rate, std::string* err);
AudioSource*  audioSourceOpenFFmpeg(const char* path, double rate, std::string* err);

// Which backend served the last successful open, for the diagnostics report.
const char* mfLastBackend();
void        mfNoteBackend(const char* name);

#endif // _WIN32
