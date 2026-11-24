// audio_source, Windows: mono float PCM piped out of the ffmpeg binary.
//
// `-ac 1 -ar <rate> -f f32le` asks ffmpeg for exactly what AVFoundation is asked for on
// macOS, so the two platforms hand the fingerprint the same stream and produce stores
// that can be read interchangeably.

#include <cstdio>
#include <string>
#include <vector>

#include "audio_source.h"
#include "frame_source.h"        // frameSourceFFmpegPath -- one setting for both
#include "ffmpeg_pipe_win.h"

namespace {

class WinAudioSource : public AudioSource {
public:
    bool open(const char* path, double rate, std::string* errOut) {
        std::string exe = frameSourceFFmpegPath();
        ffp::Probe pr;
        if (!ffp::probe(exe, path, &pr, errOut)) return false;
        if (!pr.hasAudio) { if (errOut) *errOut = "no audio track"; return false; }
        dur = pr.duration;

        char rateArg[64];
        snprintf(rateArg, sizeof(rateArg), "%d", (int)(rate + 0.5));

        std::wstring cmd =
            ffp::quoteArg(ffp::widen(exe)) +
            L" -nostdin -v quiet -i " + ffp::quoteArg(ffp::widen(path)) +
            L" -vn -sn -dn -ac 1 -ar " + ffp::widen(rateArg) +
            L" -f f32le -";

        if (!pipe.start(cmd, /*mergeStderr=*/false)) {
            if (errOut) *errOut = ffp::startFailure(exe, pipe.lastError);
            return false;
        }
        return true;
    }

    int read(float* dst, int want) override {
        int bytes = pipe.readExact(dst, want * (int)sizeof(float));
        if (bytes < 0) return 0;
        // A partial float at the end is not a sample; drop it rather than feeding
        // three bytes and whatever follows them into the analysis.
        return bytes / (int)sizeof(float);
    }

    const char* error() const override { return err.c_str(); }
    double duration() const override { return dur; }

private:
    ffp::Pipe   pipe;
    std::string err;
    double      dur = 0.0;
};

} // namespace

AudioSource* audioSourceOpen(const char* path, double rate, std::string* err) {
    if (!path || !*path) { if (err) *err = "no path"; return nullptr; }
    WinAudioSource* s = new WinAudioSource();
    if (!s->open(path, rate, err)) { delete s; return nullptr; }
    return s;
}
