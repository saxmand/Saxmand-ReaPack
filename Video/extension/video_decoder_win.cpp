// video_decoder, Windows: one ffmpeg run per frame.
//
// This is the honest, plain version of random access: seek, decode one frame, write it,
// exit. There is no prefetching, because there is no in-process decoder to keep warm --
// each frame is a process. Scrubbing is therefore slower here than on macOS, roughly as
// slow as the script's own FFmpeg fallback has always been, and the frame cache in front
// of it is doing more work as a result.
//
// What this is NOT responsible for is cut detection or matching. Those read whole files
// sequentially through FrameSource, which pipes raw frames from a single ffmpeg run and
// is as fast here as anywhere -- faster than the macOS path, in fact. So the feature
// that motivated a Windows build is not the one paying this cost.
//
// -ss before -i is deliberate: it seeks the container before decoding instead of
// decoding and discarding up to the target, which is the difference between a tenth of
// a second and most of a minute on a long file. It lands on the nearest keyframe and
// then decodes forward, which is accurate enough for a preview and is what the script's
// own ffmpeg fallback already did.

#include <cstdio>
#include <cstdlib>
#include <string>

#include "video_decoder.h"
#include "frame_cache.h"
#include "frame_source.h"        // frameSourceFFmpegPath -- one setting for everything
#include "ffmpeg_pipe_win.h"
#include "vp_fileio.h"

namespace {

class WinDecoder : public VideoDecoder {
public:
    bool open(const char* path, std::string* err) {
        src  = path;
        hash = hashPath(path);
        ffp::Probe pr;
        if (!ffp::probe(frameSourceFFmpegPath(), src, &pr, err)) return false;
        if (!pr.hasVideo) { if (err) *err = "no video track"; return false; }
        dur = pr.duration;
        return dur > 0.0;
    }

    double duration() const override { return dur; }

    std::string getFrame(double timeSec, int maxW, int maxH) override {
        timeSec = clamp(timeSec);
        long long ms = (long long)(timeSec * 1000.0 + 0.5);
        std::string out = cacheFramePath(hash, ms, maxW, maxH);

        // Already decoded: content-addressed, so the name alone settles it.
        uint64_t have = 0;
        if (vpStat(out, &have, nullptr) && have > 0) { cacheTouch(out, have); return out; }

        if (!decodeTo(timeSec, maxW, maxH, out.c_str())) return std::string();
        cacheTouch(out, 0);
        return out;
    }

    bool extractTo(double timeSec, int maxW, int maxH, const char* outPath) override {
        if (!outPath || !outPath[0]) return false;
        return decodeTo(clamp(timeSec), maxW, maxH, outPath);
    }

private:
    double clamp(double t) const { return (t < 0.0) ? 0.0 : (t > dur ? dur : t); }

    bool decodeTo(double timeSec, int maxW, int maxH, const char* outPath) {
        char ss[64], vf[160];
        snprintf(ss, sizeof(ss), "%.6f", timeSec);
        // force_original_aspect_ratio so a 4:3 or anamorphic source is not stretched
        // into the box it is being fitted to.
        snprintf(vf, sizeof(vf),
                 "scale=%d:%d:force_original_aspect_ratio=decrease", maxW, maxH);

        std::wstring cmd =
            ffp::quoteArg(ffp::widen(frameSourceFFmpegPath())) +
            L" -nostdin -v quiet -y -ss " + ffp::widen(ss) +
            L" -i " + ffp::quoteArg(ffp::widen(src)) +
            L" -frames:v 1 -an -sn -dn" +
            L" -vf " + ffp::quoteArg(ffp::widen(vf)) +
            L" " + ffp::quoteArg(ffp::widen(outPath));

        ffp::Pipe p;
        if (!p.start(cmd, /*mergeStderr=*/false)) return false;
        // Wait for the PROCESS, not for its pipe to close. ffmpeg is writing a file
        // here, so what matters is that it has finished and flushed -- reading its
        // (empty) stdout only tells us it is on the way out.
        bool exited = p.waitExit(20000);
        p.close();
        if (!exited) return false;

        uint64_t size = 0;
        return vpStat(outPath, &size, nullptr) && size > 0;
    }

    std::string src;
    uint32_t    hash = 0;
    double      dur  = 0.0;
};

} // namespace

VideoDecoder* videoDecoderOpen(const char* path, std::string* err) {
    if (!path || !path[0]) { if (err) *err = "no path"; return nullptr; }
    WinDecoder* d = new WinDecoder();
    if (!d->open(path, err)) { delete d; return nullptr; }
    return d;
}
