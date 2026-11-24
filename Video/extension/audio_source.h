#pragma once

#include <cstdint>
#include <string>

// The boundary between "decode a file's audio" and the fingerprinting above it, the
// counterpart of FrameSource.
//
// Everything downstream wants one thing: mono 32-bit float samples at a fixed rate, in
// order. Asking the decoder for exactly that is deliberate -- it does the downmix and
// the resample, so two deliveries of the same material reduce to comparable stores no
// matter what they were encoded as.
//
// macOS fills it with AVAssetReaderAudioMixOutput. Windows pipes `-f f32le -ac 1 -ar N`
// out of the ffmpeg binary, which is the same request in another spelling.

class AudioSource {
public:
    virtual ~AudioSource() {}

    // Appends up to `want` samples to `dst` and returns how many were added. 0 means
    // end of stream -- or a failure, which error() distinguishes.
    virtual int read(float* dst, int want) = 0;

    virtual const char* error() const = 0;
    virtual double duration() const = 0;
};

// Opens `path`, resampled and downmixed to mono float at `rate`. nullptr on failure,
// with the reason in err when err is non-null.
AudioSource* audioSourceOpen(const char* path, double rate, std::string* err);
