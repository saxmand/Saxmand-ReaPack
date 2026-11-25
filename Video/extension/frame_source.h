#pragma once

#include <cstdint>
#include <string>

// The whole boundary between "decode a video" and everything else in this extension.
//
// The fingerprinting, the cut detector, the matcher and the store format are plain C++
// and always were. The only platform-specific thing they ever needed was a sequence of
// small greyscale frames, in order, with a timestamp each -- so that is all this is.
//
// macOS fills it with AVAssetReader, which asks VideoToolbox to scale during decode and
// is why fingerprinting costs a tenth of the CPU a full-size decode would. Windows fills
// it by piping raw frames out of the ffmpeg binary. The frames are tiny -- 32x32 grey is
// 1 KB, so a 15 minute file at 25 fps is about 23 MB in total -- which is why a pipe is
// a perfectly reasonable way to move them.
//
// Because the fingerprint is computed from these frames and nothing else, both platforms
// produce the same store for the same file, and a store built on one can be read on the
// other.

// One decoded frame. `y` is single-channel 8-bit luma and is owned by the source: it is
// valid only until the next call to next(), which is what lets a decoder hand over its
// own buffer without copying.
struct LumaFrame {
    const uint8_t* y      = nullptr;
    int            w      = 0;
    int            h      = 0;
    // Bytes from one row to the next. May exceed w for a padded buffer, and may be
    // negative for a bottom-up one -- y always points at image row 0 either way, so
    // consumers must step by a signed stride rather than assuming packed rows.
    int            stride = 0;
    double         ptsSec = 0.0;
};

class FrameSource {
public:
    virtual ~FrameSource() {}

    // Next frame in presentation order. False at end of file, and also on a mid-stream
    // failure -- call error() to tell the two apart.
    virtual bool next(LumaFrame* out) = 0;

    // Empty while all is well, otherwise why reading stopped.
    virtual const char* error() const = 0;

    // From the container. fps may be nominal on a variable-rate source, which is why
    // each frame carries its own timestamp rather than being placed at idx/fps.
    virtual double fps() const = 0;
    virtual double duration() const = 0;
};

// Opens `path` and asks for frames at about w x h. A decoder may return a different
// size -- some codecs refuse to scale on the way out -- so callers resample from
// whatever arrives rather than assuming they got what they asked for.
//
// Returns nullptr on failure, with the reason in err when err is non-null.
FrameSource* frameSourceOpen(const char* path, int w, int h, std::string* err);

// Where the ffmpeg binary is, for the platforms that decode through it. Ignored on
// macOS, which has a decoder of its own. Safe to call from any thread, and safe never
// to call: the Windows source then looks for "ffmpeg" on PATH.
void frameSourceSetFFmpegPath(const char* path);
std::string frameSourceFFmpegPath();
