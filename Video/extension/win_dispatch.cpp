#ifdef _WIN32

// Which Windows backend answers, and in what order.
//
// Media Foundation first, because it is part of Windows and needs nothing installed.
// ffmpeg second, for what MF cannot read -- in practice ProRes and DNxHD, which have no
// Windows decoder and are exactly what film is usually cut on.
//
// So: nothing to install for the common case, and the awkward formats still work for
// anyone who has ffmpeg. If both fail, the reported reason is MF's, with ffmpeg's added
// where it is the more useful of the two -- "no such file: ffmpeg.exe" says more about
// what to do next than "Media Foundation cannot read this file".

#include "win_mf.h"

#include <string>

namespace {
// Keeps both reasons when both backends decline, because either one alone can send
// someone looking in the wrong place.
std::string bothFailed(const std::string& mf, const std::string& ff) {
    if (ff.empty()) return mf;
    if (mf.empty()) return ff;
    return mf + "\n" + ff;
}
} // namespace

FrameSource* frameSourceOpen(const char* path, int w, int h, std::string* err) {
    std::string mfErr;
    if (FrameSource* s = frameSourceOpenMF(path, w, h, &mfErr)) {
        mfNoteBackend("Media Foundation");
        return s;
    }
    std::string ffErr;
    if (FrameSource* s = frameSourceOpenFFmpeg(path, w, h, &ffErr)) {
        mfNoteBackend("ffmpeg");
        return s;
    }
    if (err) *err = bothFailed(mfErr, ffErr);
    return nullptr;
}

VideoDecoder* videoDecoderOpen(const char* path, std::string* err) {
    std::string mfErr;
    if (VideoDecoder* d = videoDecoderOpenMF(path, &mfErr)) {
        mfNoteBackend("Media Foundation");
        return d;
    }
    std::string ffErr;
    if (VideoDecoder* d = videoDecoderOpenFFmpeg(path, &ffErr)) {
        mfNoteBackend("ffmpeg");
        return d;
    }
    if (err) *err = bothFailed(mfErr, ffErr);
    return nullptr;
}

AudioSource* audioSourceOpen(const char* path, double rate, std::string* err) {
    std::string mfErr;
    if (AudioSource* s = audioSourceOpenMF(path, rate, &mfErr)) return s;
    std::string ffErr;
    if (AudioSource* s = audioSourceOpenFFmpeg(path, rate, &ffErr)) return s;
    if (err) *err = bothFailed(mfErr, ffErr);
    return nullptr;
}

#endif
