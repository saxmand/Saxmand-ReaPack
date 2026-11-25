// frame_store — whole-file per-frame fingerprints, for comparing two versions of a cut.
//
// A single sequential pass over the file decodes every frame -- through FrameSource,
// which is AVAssetReader on macOS and an ffmpeg pipe on Windows -- and reduces each one
// to a fixed-size fingerprint:
//
//   dhash64  9x8 gradient hash — the MATCH signature.  Each bit is "this cell is
//            brighter than the one to its right", so it keys on local gradients and
//            survives exposure, gamma and grade shifts that would move absolute levels.
//   grid16   16x16 luma — the DIFF signature.  Magnitude-sensitive, and because the
//            cells are spatial it also says *where* in frame something changed.
//   ptsMs    presentation time, so frame index -> timeline position stays correct on
//            variable-frame-rate sources instead of assuming idx/fps.
//
// Why a store at all: matching two hour-long reels means tens of millions of frame
// comparisons.  Decoding for each one is hopeless, so decode once, keep 268 bytes per
// frame (~24MB/hour), and let every later stage run as integer array math.
//
// On-disk layout is structure-of-arrays, not an array of structs, so the matcher can
// stream the hashes (8*N bytes — 720KB/hour, L2-resident) without dragging the 256-byte
// grids through cache behind them.
//
//   FSHeader
//   uint64 dhash[frameCount]
//   uint32 ptsMs[frameCount]
//   uint8  grid [frameCount * 256]

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <sys/stat.h>

#include "vp_api.h"
#include "frame_store.h"
#include "frame_source.h"
#include "vp_fileio.h"

// Decode target.  32x32 is far more than the 16x16 grid and 9x8 hash need, which keeps
// the resample cheap while leaving headroom if the fingerprint grows.  Square on purpose:
// both versions get normalised identically, so the comparison is aspect-agnostic.
// Analysis decodes at native size and does its own downscaling -- see frameSourceOpen.
// These are no longer a request to the decoder, only a record of what the fingerprint
// is derived to; the grid and the 9x8 hash come straight from the native frame.
static const int ANALYZE_W = 0;
static const int ANALYZE_H = 0;
static const int GRID      = FS_GRID;
static const int GRID_SZ   = FS_GRID_SZ;

// -----------------------------------------------------------------------
// Fingerprinting
// -----------------------------------------------------------------------

// Area-average resample of an 8-bit single-channel image.  Box filter rather than
// point sampling: averaging is what makes the fingerprint stable against the pixel
// jitter that re-encoding introduces.
// stride may be negative, for a bottom-up buffer whose src already points at image
// row 0 -- hence ptrdiff_t below rather than size_t, which would wrap.
static void resampleLuma(const uint8_t* src, int sw, int sh, int stride,
                         uint8_t* dst, int dw, int dh) {
    for (int y = 0; y < dh; y++) {
        int y0 = y * sh / dh, y1 = (y + 1) * sh / dh;
        if (y1 <= y0) y1 = y0 + 1;
        for (int x = 0; x < dw; x++) {
            int x0 = x * sw / dw, x1 = (x + 1) * sw / dw;
            if (x1 <= x0) x1 = x0 + 1;
            uint32_t sum = 0, n = 0;
            for (int yy = y0; yy < y1 && yy < sh; yy++) {
                const uint8_t* row = src + (ptrdiff_t)yy * stride;
                for (int xx = x0; xx < x1 && xx < sw; xx++) { sum += row[xx]; n++; }
            }
            dst[y * dw + x] = n ? (uint8_t)(sum / n) : 0;
        }
    }
}

// 9x8 luma -> 64 bits: one bit per horizontally-adjacent pair.
static uint64_t dhash9x8(const uint8_t* p) {
    uint64_t h = 0;
    int bit = 0;
    for (int y = 0; y < 8; y++)
        for (int x = 0; x < 8; x++, bit++)
            if (p[y * 9 + x] > p[y * 9 + x + 1]) h |= (1ull << bit);
    return h;
}

// -----------------------------------------------------------------------
// Store I/O
// -----------------------------------------------------------------------

bool fsReadHeader(const std::string& path, FSHeader* out) {
    FILE* f = vpFopen(path, "rb");
    if (!f) return false;
    FSHeader h;
    bool ok = fread(&h, sizeof(h), 1, f) == 1;
    fclose(f);
    if (!ok || memcmp(h.magic, FS_MAGIC, 8) != 0) return false;
    // Video stores carry the 16x16 grid; audio stores carry no grid at all. Any other
    // grid size is a store written by an older fingerprint format.
    bool isAudio = (h.flags & FS_FLAG_AUDIO) != 0;
    if (isAudio ? (h.grid != 0) : (h.grid != GRID)) return false;
    if (out) *out = h;
    return true;
}

bool fsLoad(const std::string& path, FrameStore* out, bool withGrid) {
    if (!out) return false;
    if (!fsReadHeader(path, &out->h)) return false;

    FILE* f = vpFopen(path, "rb");
    if (!f) return false;
    if (fseek(f, sizeof(FSHeader), SEEK_SET) != 0) { fclose(f); return false; }

    size_t n = out->h.frameCount;
    out->dhash.resize(n);
    out->ptsMs.resize(n);
    bool ok = fread(out->dhash.data(), sizeof(uint64_t), n, f) == n
           && fread(out->ptsMs.data(), sizeof(uint32_t), n, f) == n;

    // Peaks are tiny next to the hashes and are read unconditionally: the matcher
    // ignores them, and the alternative is a second pass over the file every time the
    // waveform needs redrawing.
    if (ok && (out->h.flags & FS_FLAG_PEAKS)) {
        out->peak.resize(n);
        ok = fread(out->peak.data(), sizeof(uint16_t), n, f) == n;
    } else {
        out->peak.clear();
    }

    if (ok && withGrid && out->h.grid == FS_GRID) {
        size_t g = n * (size_t)FS_GRID_SZ;
        out->grid.resize(g);
        ok = fread(out->grid.data(), 1, g, f) == g;
    } else {
        out->grid.clear();
    }
    fclose(f);
    return ok;
}

static bool readHeader(const std::string& path, FSHeader* out) { return fsReadHeader(path, out); }

// A store is reusable only if it was built from this exact file revision and in the
// current fingerprint format.  Anything else and we re-analyse.
static bool storeIsFresh(const std::string& storePath, const std::string& srcPath, FSHeader* out) {
    FSHeader h;
    if (!readHeader(storePath, &h)) return false;
    uint64_t sz = 0; int64_t mt = 0;
    if (!vpStat(srcPath, &sz, &mt)) return false;
    if (h.srcSize != (int64_t)sz || h.srcMtime != mt) return false;
    // A video store from an older fingerprint chain describes the same file with
    // different numbers, so it has to be rebuilt rather than reused.
    if ((h.flags & FS_FLAG_AUDIO) == 0 && h.reserved != FS_VIDEO_CHAIN) return false;
    if (out) *out = h;
    return true;
}

// -----------------------------------------------------------------------
// Analysis jobs
// -----------------------------------------------------------------------

struct AnalyzeJob {
    std::thread       th;
    std::atomic<int>  state{0};        // 0 running, 1 done, 2 error
    std::atomic<int>  framesDone{0};
    std::atomic<int>  framesTotal{0};
    std::atomic<bool> cancel{false};
    std::atomic<int>  frameCount{0};
    std::mutex        errMu;
    std::string       error;
};

static std::mutex                   g_jobMu;
static std::map<int, AnalyzeJob*>   g_jobs;
static int                          g_nextJob = 1;

static AnalyzeJob* getJob(int id) {
    auto it = g_jobs.find(id);
    return (it != g_jobs.end()) ? it->second : nullptr;
}

static void analyzeWorker(AnalyzeJob* job, std::string srcPath, std::string storePath) {
    auto fail = [job](const std::string& m) {
        { std::lock_guard<std::mutex> lk(job->errMu); job->error = m; }
        job->state = 2;
    };

    std::string openErr;
    FrameSource* src = frameSourceOpen(srcPath.c_str(), ANALYZE_W, ANALYZE_H, &openErr);
    if (!src) { fail(openErr.empty() ? "could not open video" : openErr); return; }

    double duration = src->duration();
    double fps      = src->fps();
    if (!(fps > 0.0))      fps = 25.0;
    if (!(duration > 0.0)) duration = 0.0;
    job->framesTotal = (int)(duration * fps + 0.5);

    std::vector<uint64_t> hashes;
    std::vector<uint32_t> ptsMs;
    std::vector<uint8_t>  grids;
    int reserve = job->framesTotal.load() > 0 ? job->framesTotal.load() : 1024;
    hashes.reserve(reserve);
    ptsMs.reserve(reserve);
    grids.reserve((size_t)reserve * GRID_SZ);

    uint8_t g16[GRID_SZ];
    uint8_t h98[9 * 8];

    LumaFrame fr;
    while (src->next(&fr)) {
        if (job->cancel) break;
        // Resampled from whatever size actually arrived: a decoder may decline to scale
        // on the way out, so the analysis size is a request rather than a guarantee.
        resampleLuma(fr.y, fr.w, fr.h, fr.stride, g16, GRID, GRID);
        resampleLuma(fr.y, fr.w, fr.h, fr.stride, h98, 9, 8);
        hashes.push_back(dhash9x8(h98));
        ptsMs.push_back((uint32_t)(fr.ptsSec * 1000.0 + 0.5));
        grids.insert(grids.end(), g16, g16 + GRID_SZ);
        job->framesDone = (int)hashes.size();
    }

    std::string readErr = src->error();
    bool cancelled = job->cancel.load();
    delete src;

    if (cancelled)          { fail("cancelled"); return; }
    if (!readErr.empty())   { fail(readErr); return; }
    if (hashes.empty())     { fail("no frames decoded"); return; }

    // Prefer a rate measured from the timestamps over the one the decoder declared.
    // The timestamps are what the frames actually carry, so this is right even where
    // the metadata is missing or wrong -- which is how every Windows store came to be
    // labelled 25 fps. Needs a span worth measuring: two frames a millisecond apart
    // would divide into nonsense, so fall back to the declared rate below that.
    if (ptsMs.size() >= 2 && ptsMs.back() > ptsMs.front()) {
        double span = (double)(ptsMs.back() - ptsMs.front()) / 1000.0;
        if (span >= 0.5) {
            double measured = (double)(ptsMs.size() - 1) / span;
            if (measured > 0.5 && measured < 1000.0) fps = measured;
        }
    }

    int64_t srcSize = 0, srcMtime = 0;
    {
        uint64_t sz = 0; int64_t mt = 0;
        if (vpStat(srcPath, &sz, &mt)) { srcSize = (int64_t)sz; srcMtime = mt; }
    }

    FSHeader hdr;
    memset(&hdr, 0, sizeof(hdr));
    memcpy(hdr.magic, FS_MAGIC, 8);
    hdr.frameCount = (uint32_t)hashes.size();
    hdr.grid       = GRID;
    hdr.fps        = fps;
    hdr.duration   = duration;
    hdr.srcSize    = srcSize;
    hdr.srcMtime   = srcMtime;
    hdr.reserved   = FS_VIDEO_CHAIN;

    // Write to a sibling temp file and rename, so an interrupted analysis can never
    // leave a half-written store that later looks valid. The name carries the job,
    // so two analyses of the same file in flight at once cannot write over each
    // other's temp -- they produce identical bytes, so whichever renames last wins
    // and either outcome is correct.
    char tmpSuffix[48];
    snprintf(tmpSuffix, sizeof(tmpSuffix), ".tmp%llx",
             (unsigned long long)(uintptr_t)job);
    std::string tmp = storePath + tmpSuffix;
    FILE* f = vpFopen(tmp, "wb");
    if (!f) { fail("cannot open store for writing"); return; }
    bool ok = fwrite(&hdr, sizeof(hdr), 1, f) == 1
           && fwrite(hashes.data(), sizeof(uint64_t), hashes.size(), f) == hashes.size()
           && fwrite(ptsMs.data(),  sizeof(uint32_t), ptsMs.size(),  f) == ptsMs.size()
           && fwrite(grids.data(),  1,                grids.size(),  f) == grids.size();
    fclose(f);
    if (!ok) { vpRemove(tmp); fail("store write failed"); return; }
    vpRemove(storePath);
    if (vpRename(tmp, storePath) != 0) { fail("store rename failed"); return; }

    job->frameCount = (int)hashes.size();
    job->state      = 1;
}

// -----------------------------------------------------------------------
// Cut detection from a framestore
// -----------------------------------------------------------------------
// A cut is a large frame-to-frame jump in the hash. The hashes are already on disk
// for matching, so this costs one pass over 8 bytes per frame -- no decode at all,
// against FFmpeg's scdet which must decode the whole file every time.
//
// A flat threshold alone is not enough: fast motion makes consecutive frames differ a
// lot, so a bar high enough to reject a whip pan also rejects a cut between two
// similar shots. The second test is therefore relative -- the jump must also stand out
// against the local median of the surrounding distances, which is naturally high in
// motion and near zero on a locked-off shot. The same idea as scdet comparing against
// recent frame difference, but on 64-bit hashes rather than pixels.

static int localMedian(const std::vector<int>& d, int at, int half) {
    int lo = std::max(0, at - half), hi = std::min((int)d.size() - 1, at + half);
    static std::vector<int> w;
    w.clear();
    for (int i = lo; i <= hi; i++)
        if (i != at) w.push_back(d[i]);
    if (w.empty()) return 0;
    std::nth_element(w.begin(), w.begin() + w.size() / 2, w.end());
    return w[w.size() / 2];
}

// thresh    absolute bar in bits of 64 (a cut must jump at least this far)
// ratioPct  the jump must also be this percentage of the local median; 0 disables
// minGap    frames; a stronger cut inside this window suppresses a weaker one
static const char* VP_Cuts(const char* storePath, int thresh, int ratioPct, int minGap) {
    static std::string out;
    out.clear();
    if (!storePath || !storePath[0]) { out = "E no store"; return out.c_str(); }
    if (thresh < 1)  thresh = 1;
    if (thresh > 64) thresh = 64;
    if (ratioPct < 0) ratioPct = 0;
    if (minGap < 0)   minGap = 0;

    FrameStore fs;
    if (!fsLoad(storePath, &fs, false)) { out = "E cannot load store"; return out.c_str(); }
    const int n = fs.frames();
    if (n < 2) { out = "E store too short"; return out.c_str(); }

    std::vector<int> d(n, 0);
    for (int i = 1; i < n; i++)
        d[i] = __builtin_popcountll(fs.dhash[i] ^ fs.dhash[i - 1]);

    struct Cand { int frame, dist, med; };
    std::vector<Cand> cands;
    const int half = 12;                  // about half a second either side at 25 fps
    for (int i = 1; i < n; i++) {
        if (d[i] < thresh) continue;
        int med = localMedian(d, i, half);
        if (ratioPct > 0 && d[i] * 100 < ratioPct * std::max(med, 1)) continue;
        cands.push_back({ i, d[i], med });
    }

    // Keep the strongest within each minGap window, so a flash frame or the two ends
    // of a short dissolve report as one cut rather than two.
    std::vector<Cand> keep;
    for (const Cand& c : cands) {
        if (!keep.empty() && c.frame - keep.back().frame <= minGap) {
            if (c.dist > keep.back().dist) keep.back() = c;
        } else {
            keep.push_back(c);
        }
    }

    char line[160];
    snprintf(line, sizeof(line), "C %d %d %.6f\n", (int)keep.size(), n, fs.h.fps);
    out = line;
    for (const Cand& c : keep) {
        // The timestamp the frame actually carries, as a fourth field. Dividing the
        // frame index by a header rate -- which is what the caller had to do before --
        // is only right for constant-rate material whose rate was read correctly, and
        // is wrong twice over otherwise: every cut moves, and the ones pushed past the
        // end of the analysed stretch get discarded as out of range.
        snprintf(line, sizeof(line), "K %d %d %d %u\n",
                 c.frame, c.dist, c.med, (unsigned)fs.ptsMs[c.frame]);
        out += line;
    }
    return out.c_str();
}

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

// Returns a job id (>0).  Analysis runs on its own thread; poll VP_AnalyzeState.
// With force==0 a store already matching this file revision completes immediately.
static int VP_Analyze(const char* filePath, const char* storePath, int force) {
    if (!filePath || !filePath[0] || !storePath || !storePath[0]) return 0;

    auto* job = new AnalyzeJob();

    FSHeader h;
    if (!force && storeIsFresh(storePath, filePath, &h)) {
        job->frameCount  = (int)h.frameCount;
        job->framesTotal = (int)h.frameCount;
        job->framesDone  = (int)h.frameCount;
        job->state       = 1;
    }

    int id;
    {
        std::lock_guard<std::mutex> lk(g_jobMu);
        id = g_nextJob++;
        g_jobs[id] = job;
    }
    if (job->state == 0)
        job->th = std::thread(analyzeWorker, job, std::string(filePath), std::string(storePath));
    return id;
}

static int VP_AnalyzeState(int id) {
    std::lock_guard<std::mutex> lk(g_jobMu);
    AnalyzeJob* j = getJob(id);
    return j ? j->state.load() : 2;
}

static double VP_AnalyzeProgress(int id) {
    std::lock_guard<std::mutex> lk(g_jobMu);
    AnalyzeJob* j = getJob(id);
    if (!j) return 0.0;
    if (j->state == 1) return 1.0;
    int total = j->framesTotal.load();
    if (total <= 0) return 0.0;
    double p = (double)j->framesDone.load() / (double)total;
    return p < 0.0 ? 0.0 : (p > 1.0 ? 1.0 : p);
}

static int VP_AnalyzeFrames(int id) {
    std::lock_guard<std::mutex> lk(g_jobMu);
    AnalyzeJob* j = getJob(id);
    return j ? j->frameCount.load() : 0;
}

static const char* VP_AnalyzeError(int id) {
    static char sBuf[1024];
    sBuf[0] = '\0';
    std::lock_guard<std::mutex> lk(g_jobMu);
    AnalyzeJob* j = getJob(id);
    if (j) {
        std::lock_guard<std::mutex> lk2(j->errMu);
        snprintf(sBuf, sizeof(sBuf), "%s", j->error.c_str());
    }
    return sBuf;
}

static void VP_AnalyzeCancel(int id) {
    std::lock_guard<std::mutex> lk(g_jobMu);
    AnalyzeJob* j = getJob(id);
    if (j) j->cancel = true;
}

// Must be called once per VP_Analyze, after the job reaches done/error.  Joins the
// worker thread, so calling it while still running will block until the frame loop
// notices the cancel flag.
static void VP_AnalyzeRelease(int id) {
    AnalyzeJob* j = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_jobMu);
        auto it = g_jobs.find(id);
        if (it != g_jobs.end()) { j = it->second; g_jobs.erase(it); }
    }
    if (!j) return;
    j->cancel = true;
    if (j->th.joinable()) j->th.join();
    delete j;
}

static int    VP_StoreFrames(const char* storePath) {
    FSHeader h;
    return (storePath && readHeader(storePath, &h)) ? (int)h.frameCount : 0;
}
static double VP_StoreFPS(const char* storePath) {
    FSHeader h;
    return (storePath && readHeader(storePath, &h)) ? h.fps : 0.0;
}
// A plain-text summary of a store, for comparing the same file across two machines.
// The header alone cannot settle a timing complaint -- what matters is whether the
// frames carry sensible timestamps -- so this reports the measured rate and the pts
// spacing next to the declared one, plus a few hashes to show the pixels agree.
static const char* VP_StoreInfo(const char* storePath) {
    static std::string out;
    out.clear();
    if (!storePath) { out = "E bad arguments"; return out.c_str(); }

    FrameStore fs;
    if (!fsLoad(storePath, &fs, false)) { out = "E cannot load store"; return out.c_str(); }
    const int n = fs.frames();

    char line[512];
    snprintf(line, sizeof(line),
             "frames      %d\nfps(header) %.6f\nduration    %.3f\ngrid        %d\n"
             "srcSize     %lld\nsrcMtime    %lld\n",
             n, fs.h.fps, fs.h.duration, (int)fs.h.grid,
             (long long)fs.h.srcSize, (long long)fs.h.srcMtime);
    out = line;

    if (n >= 2) {
        double span = (double)(fs.ptsMs[n - 1] - fs.ptsMs[0]) / 1000.0;
        snprintf(line, sizeof(line),
                 "pts span    %.3f s (%u..%u ms)\nfps(measured) %.6f\n",
                 span, (unsigned)fs.ptsMs[0], (unsigned)fs.ptsMs[n - 1],
                 span > 0.0 ? (double)(n - 1) / span : 0.0);
        out += line;

        // Irregular spacing is the signature of dropped or duplicated frames, which no
        // single rate can describe; the gap histogram shows it at a glance.
        std::map<int, int> gaps;
        for (int i = 1; i < n; i++) gaps[(int)fs.ptsMs[i] - (int)fs.ptsMs[i - 1]]++;
        out += "pts gaps    ";
        int shown = 0;
        for (auto it = gaps.begin(); it != gaps.end() && shown < 6; ++it, ++shown) {
            snprintf(line, sizeof(line), "%dms x%d  ", it->first, it->second);
            out += line;
        }
        if (gaps.size() > 6) {
            snprintf(line, sizeof(line), "(+%d more)", (int)gaps.size() - 6);
            out += line;
        }
        out += "\n";
    }

    const int dump = n < 8 ? n : 8;
    out += "hashes      ";
    for (int i = 0; i < dump; i++) {
        snprintf(line, sizeof(line), "%016llx ", (unsigned long long)fs.dhash[i]);
        out += line;
    }
    out += "\n";
    return out.c_str();
}

// 1 when the store matches the source file's current size+mtime and format version.
static int    VP_StoreFresh(const char* storePath, const char* filePath) {
    if (!storePath || !filePath) return 0;
    return storeIsFresh(storePath, filePath, nullptr) ? 1 : 0;
}

void frameStoreShutdown() {
    std::vector<AnalyzeJob*> jobs;
    {
        std::lock_guard<std::mutex> lk(g_jobMu);
        for (auto& kv : g_jobs) jobs.push_back(kv.second);
        g_jobs.clear();
    }
    for (auto* j : jobs) {
        j->cancel = true;
        if (j->th.joinable()) j->th.join();
        delete j;
    }
}

// -----------------------------------------------------------------------
// Vararg wrappers
//
// The return convention varies by type: an int or bool is cast straight into the
// returned pointer, while a double returns a pointer to storage holding it. Handing
// back &someInt for an int-returning function makes ReaScript read the address itself
// as the value, which surfaces in Lua as a large constant that never changes.
// -----------------------------------------------------------------------
static double g_dRet;

static void* VA_VP_Analyze(void** a, int n) {
    int r = (n < 2) ? 0 : VP_Analyze((const char*)a[0], (const char*)a[1],
                                     n >= 3 ? (int)(intptr_t)a[2] : 0);
    return (void*)(intptr_t)r;
}
static void* VA_VP_AnalyzeState(void** a, int n) {
    return (void*)(intptr_t)((n < 1) ? 2 : VP_AnalyzeState((int)(intptr_t)a[0]));
}
static void* VA_VP_AnalyzeProgress(void** a, int n) {
    g_dRet = (n < 1) ? 0.0 : VP_AnalyzeProgress((int)(intptr_t)a[0]);
    return &g_dRet;
}
static void* VA_VP_AnalyzeFrames(void** a, int n) {
    return (void*)(intptr_t)((n < 1) ? 0 : VP_AnalyzeFrames((int)(intptr_t)a[0]));
}
static void* VA_VP_AnalyzeError(void** a, int n) {
    return (n < 1) ? (void*)"" : (void*)VP_AnalyzeError((int)(intptr_t)a[0]);
}
static void* VA_VP_AnalyzeCancel(void** a, int n) {
    if (n >= 1) VP_AnalyzeCancel((int)(intptr_t)a[0]);
    return nullptr;
}
static void* VA_VP_AnalyzeRelease(void** a, int n) {
    if (n >= 1) VP_AnalyzeRelease((int)(intptr_t)a[0]);
    return nullptr;
}
static void* VA_VP_StoreFrames(void** a, int n) {
    return (void*)(intptr_t)((n < 1) ? 0 : VP_StoreFrames((const char*)a[0]));
}
static void* VA_VP_StoreFPS(void** a, int n) {
    g_dRet = (n < 1) ? 0.0 : VP_StoreFPS((const char*)a[0]);
    return &g_dRet;
}
static void* VA_VP_StoreFresh(void** a, int n) {
    return (void*)(intptr_t)((n < 2) ? 0 : VP_StoreFresh((const char*)a[0], (const char*)a[1]));
}
static void* VA_VP_StoreInfo(void** a, int n) {
    if (n < 1) return (void*)"E bad arguments";
    return (void*)VP_StoreInfo((const char*)a[0]);
}
static void* VA_VP_Cuts(void** a, int n) {
    if (n < 4) return (void*)"E bad arguments";
    return (void*)VP_Cuts((const char*)a[0], (int)(intptr_t)a[1],
                          (int)(intptr_t)a[2], (int)(intptr_t)a[3]);
}

const VPFunc g_frameStoreFuncs[] = {
    { "VP_Analyze", (void*)VP_Analyze, (void*)VA_VP_Analyze,
      "int", "const char*,const char*,int", "filePath,storePath,force",
      "Start background frame-fingerprint analysis. Returns job id (>0) or 0. force=1 rebuilds an existing store." },
    { "VP_AnalyzeState", (void*)VP_AnalyzeState, (void*)VA_VP_AnalyzeState,
      "int", "int", "job",
      "0=running 1=done 2=error." },
    { "VP_AnalyzeProgress", (void*)VP_AnalyzeProgress, (void*)VA_VP_AnalyzeProgress,
      "double", "int", "job",
      "Analysis progress 0..1." },
    { "VP_AnalyzeFrames", (void*)VP_AnalyzeFrames, (void*)VA_VP_AnalyzeFrames,
      "int", "int", "job",
      "Frames fingerprinted (valid once state=1)." },
    { "VP_AnalyzeError", (void*)VP_AnalyzeError, (void*)VA_VP_AnalyzeError,
      "const char*", "int", "job",
      "Error message when state=2, else empty." },
    { "VP_AnalyzeCancel", (void*)VP_AnalyzeCancel, (void*)VA_VP_AnalyzeCancel,
      "void", "int", "job",
      "Ask a running analysis to stop." },
    { "VP_AnalyzeRelease", (void*)VP_AnalyzeRelease, (void*)VA_VP_AnalyzeRelease,
      "void", "int", "job",
      "Free the job and join its thread. Call once per VP_Analyze." },
    { "VP_StoreFrames", (void*)VP_StoreFrames, (void*)VA_VP_StoreFrames,
      "int", "const char*", "storePath",
      "Frame count in a framestore, or 0 if missing/unreadable." },
    { "VP_StoreFPS", (void*)VP_StoreFPS, (void*)VA_VP_StoreFPS,
      "double", "const char*", "storePath",
      "Frame rate recorded in a framestore, or 0." },
    { "VP_StoreFresh", (void*)VP_StoreFresh, (void*)VA_VP_StoreFresh,
      "int", "const char*,const char*", "storePath,filePath",
      "1 if the store was built from this file revision and current format." },
    { "VP_StoreInfo", (void*)VP_StoreInfo, (void*)VA_VP_StoreInfo,
      "const char*", "const char*", "storePath",
      "Plain-text summary of a framestore -- frame count, declared and measured frame "
      "rate, timestamp span and spacing, and the first few hashes. For comparing the "
      "same source file between two machines. 'E msg' on error." },
    { "VP_Cuts", (void*)VP_Cuts, (void*)VA_VP_Cuts,
      "const char*", "const char*,int,int,int", "storePath,thresh,ratioPct,minGap",
      "Detect cuts from a framestore, with no decoding. Returns 'C count frames fps' "
      "then 'K frame dist localMedian ptsMs' per cut. thresh is the absolute bar in bits of "
      "64 (try 18); ratioPct additionally requires the jump to be that percentage of "
      "the local median distance, which is what separates a cut from fast motion (try "
      "250, 0 disables); minGap suppresses a weaker cut within that many frames of a "
      "stronger one. 'E msg' on error." },
};
const int g_frameStoreFuncCount = (int)(sizeof(g_frameStoreFuncs) / sizeof(g_frameStoreFuncs[0]));
