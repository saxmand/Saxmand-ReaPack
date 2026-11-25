// frame_source, Windows: raw frames piped out of the ffmpeg binary.
//
// The frames the fingerprint wants are tiny -- 32x32 single-channel is 1 KB, so a 15
// minute file at 25 fps is about 23 MB in total -- which is why a pipe is a sensible way
// to carry them and why asking ffmpeg to scale on its side costs nothing worth saving.
//
// Output is forced to constant frame rate at the detected rate. ffmpeg's rawvideo format
// carries no timestamps, so a frame's position has to come from its index; forcing CFR
// is what makes index/fps exactly right rather than approximately. On a variable-rate
// source ffmpeg then duplicates or drops frames to fit the grid, which is the same
// normalisation the matcher would need anyway for two files to be comparable.

#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <string>
#include <vector>

#include "frame_source.h"
#include "ffmpeg_pipe_win.h"
#include "win_mf.h"

static std::mutex  g_pathMu;
static std::string g_ffmpegPath;

void frameSourceSetFFmpegPath(const char* path) {
    std::lock_guard<std::mutex> lk(g_pathMu);
    g_ffmpegPath = path ? path : "";
}

std::string frameSourceFFmpegPath() {
    std::lock_guard<std::mutex> lk(g_pathMu);
    // "ffmpeg" alone is a reasonable last resort: if it is on PATH this works with no
    // configuration, and if it is not, CreateProcess fails and the caller reports it.
    return g_ffmpegPath.empty() ? std::string("ffmpeg") : g_ffmpegPath;
}

namespace {

class WinFrameSource : public FrameSource {
public:
    bool open(const char* path, int w, int h, std::string* errOut) {
        reqW = w; reqH = h;

        std::string exe = frameSourceFFmpegPath();
        ffp::Probe pr;
        if (!ffp::probe(exe, path, &pr, errOut)) return false;
        if (!pr.hasVideo) { if (errOut) *errOut = "no video track"; return false; }

        dur  = pr.duration;
        rate = (pr.fps > 0.0) ? pr.fps : 25.0;

        // No size asked for means native, and no scale filter -- see frameSourceOpen.
        if (reqW <= 0 || reqH <= 0) {
            if (pr.width <= 0 || pr.height <= 0) {
                if (errOut) *errOut = "could not read the video size";
                return false;
            }
            reqW = pr.width; reqH = pr.height;
            scaling = false;
        }

        char vf[128], fpsArg[64];
        snprintf(vf, sizeof(vf), "scale=%d:%d", reqW, reqH);
        snprintf(fpsArg, sizeof(fpsArg), "%.6f", rate);

        // yuv420p and not gray: "gray" puts swscale in the way, which expands video
        // range to full range and clips at both ends. That is a non-monotonic change,
        // so it moves hash bits -- measured at 1.4 bits of mean Hamming against the
        // same frames taken as a raw luma plane, which is enough to matter when the
        // point is for this backend to agree with Media Foundation and AVFoundation.
        // The chroma planes are read and dropped in next().
        // -nostdin so it cannot sit waiting on a console that is not there, and
        // -v quiet so the frame data on stdout is never mixed with log text.
        std::wstring cmd =
            ffp::quoteArg(ffp::widen(exe)) +
            L" -nostdin -v quiet -i " + ffp::quoteArg(ffp::widen(path)) +
            L" -an -sn -dn" +
            (scaling ? (L" -vf " + ffp::quoteArg(ffp::widen(vf))) : std::wstring()) +
            L" -pix_fmt yuv420p -r " + ffp::widen(fpsArg) +
            L" -fps_mode cfr -f rawvideo -";

        buf.resize((size_t)reqW * reqH);
        // yuv420p carries half-resolution chroma, rounded up on odd dimensions.
        chroma.resize((size_t)2 * (((size_t)reqW + 1) / 2) * (((size_t)reqH + 1) / 2));
        if (!pipe.start(cmd, /*mergeStderr=*/false)) {
            if (errOut) *errOut = ffp::startFailure(exe, pipe.lastError);
            return false;
        }
        return true;
    }

    bool next(LumaFrame* out) override {
        const int need = (int)buf.size();
        int got = pipe.readExact(buf.data(), need);
        if (got < need) {
            // A clean end lands exactly on a frame boundary. Anything else means the
            // stream was cut mid-frame, which is worth reporting rather than treating
            // as a short file.
            if (got != 0) err = "ffmpeg output ended mid-frame";
            return false;
        }
        if (!chroma.empty()) {
            const int cneed = (int)chroma.size();
            if (pipe.readExact(chroma.data(), cneed) < cneed) {
                err = "ffmpeg output ended mid-frame";
                return false;
            }
        }
        out->y      = buf.data();
        out->w      = reqW;
        out->h      = reqH;
        out->stride = reqW;          // rawvideo is tightly packed
        out->ptsSec = (double)index / rate;
        index++;
        return true;
    }

    const char* error() const override { return err.c_str(); }
    double fps() const override { return rate; }
    double duration() const override { return dur; }

private:
    ffp::Pipe            pipe;
    std::vector<uint8_t> buf;
    std::vector<uint8_t> chroma;      // read and discarded; only luma is fingerprinted
    bool                 scaling = true;
    std::string          err;
    int                  reqW = 0, reqH = 0;
    long long            index = 0;
    double               rate = 25.0;
    double               dur  = 0.0;
};

} // namespace

FrameSource* frameSourceOpenFFmpeg(const char* path, int w, int h, std::string* err) {
    if (!path || !*path) { if (err) *err = "no path"; return nullptr; }
    WinFrameSource* s = new WinFrameSource();
    if (!s->open(path, w, h, err)) { delete s; return nullptr; }
    return s;
}
