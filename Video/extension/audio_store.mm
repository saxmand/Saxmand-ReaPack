// audio_store — per-hop audio fingerprints, for matching two versions by sound.
//
// Why this exists: checking our picture matching against Matchbox's own diff export
// showed that every stretch we still failed to match was one where the two pictures
// are genuinely unrelated (Hamming 27-30 of 64, i.e. different shots) and yet the
// material corresponds. Matchbox can only have aligned those by sound. On a 15-minute
// reel that was 127 seconds of material a picture-only matcher cannot reach in
// principle, so sound is not a refinement here, it is the missing half.
//
// The fingerprint is deliberately shaped to be a 64-bit hash per hop, in the same
// store layout as the video fingerprints. That means the matcher — band index,
// diagonal voting, seed and extend, run chaining — runs on audio untouched, because
// every step of it reduces to Hamming distance between 64-bit values. The only
// difference is what an index means: audio hops rather than video frames, with the
// rate recorded in the header.
//
// Per hop the hash follows Haitsma and Kalker's robust audio hash: take band
// energies, then set each bit from the sign of how one band's energy moved relative
// to its neighbour, compared against the previous hop. Differencing across both
// frequency and time is what survives level changes, EQ and re-encoding — the same
// reasoning that makes a gradient hash the right choice for pictures. A constant gain
// cancels entirely; a filter that lifts one region cancels in the time difference.

#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>

#include <atomic>
#include <cmath>
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

// 16 kHz mono: everything the fingerprint looks at sits below 6 kHz, and asking
// AVFoundation for this directly makes it do the downmix and resample for us.
static const double AS_RATE     = 16000.0;
static const int    AS_FFT_LOG2 = 10;
static const int    AS_FFT      = 1 << AS_FFT_LOG2;   // 1024 samples, 64 ms
static const int    AS_BINS     = AS_FFT / 2;
static const int    AS_HOP      = 160;                // 10 ms, so 4 hops per video frame
static const double AS_HZ       = AS_RATE / AS_HOP;   // 100 hops per second
static const int    AS_BANDS    = 64;                 // 64 bands -> one bit each
static const double AS_LO_HZ    = 250.0;
static const double AS_HI_HZ    = 6000.0;

struct AudioJob {
    std::thread       th;
    std::atomic<int>  state{0};      // 0 running, 1 done, 2 error
    std::atomic<int>  hopsDone{0};
    std::atomic<int>  hopsTotal{0};
    std::atomic<bool> cancel{false};
    std::atomic<int>  hopCount{0};
    std::mutex        errMu;
    std::string       error;
};

static std::mutex                 g_aMu;
static std::map<int, AudioJob*>   g_aJobs;
static int                        g_aNext = 1;

static AudioJob* getAudioJob(int id) {
    auto it = g_aJobs.find(id);
    return (it != g_aJobs.end()) ? it->second : nullptr;
}

static bool audioStoreFresh(const std::string& storePath, const std::string& srcPath) {
    FSHeader h;
    if (!fsReadHeader(storePath, &h)) return false;
    if ((h.flags & FS_FLAG_AUDIO) == 0) return false;
    // A store written before peaks existed is treated as stale rather than loaded
    // without a waveform: re-analysis is 30x realtime, and silently showing an empty
    // strip would look like broken audio rather than an out-of-date cache.
    if ((h.flags & FS_FLAG_PEAKS) == 0) return false;
    struct stat st;
    if (stat(srcPath.c_str(), &st) != 0) return false;
    return h.srcSize == (int64_t)st.st_size && h.srcMtime == (int64_t)st.st_mtime;
}

static void audioWorker(AudioJob* job, std::string srcPath, std::string storePath) {
    auto fail = [job](const std::string& m) {
        { std::lock_guard<std::mutex> lk(job->errMu); job->error = m; }
        job->state = 2;
    };

    @autoreleasepool {
        NSURL*      url   = [NSURL fileURLWithPath:@(srcPath.c_str())];
        AVURLAsset* asset = [AVURLAsset URLAssetWithURL:url options:nil];
        NSArray<AVAssetTrack*>* tracks = [asset tracksWithMediaType:AVMediaTypeAudio];
        if (tracks.count == 0) { fail("no audio track"); return; }

        double duration = CMTimeGetSeconds(asset.duration);
        if (!(duration > 0.0)) duration = 0.0;
        job->hopsTotal = (int)(duration * AS_HZ);

        NSError*       err    = nil;
        AVAssetReader* reader = [AVAssetReader assetReaderWithAsset:asset error:&err];
        if (!reader) {
            fail(err ? err.localizedDescription.UTF8String : "reader init failed");
            return;
        }

        // Asking for mono float at a fixed rate makes AVFoundation do the downmix and
        // resample, so stores from different deliveries are directly comparable.
        NSDictionary* settings = @{
            AVFormatIDKey:               @(kAudioFormatLinearPCM),
            AVSampleRateKey:             @(AS_RATE),
            AVNumberOfChannelsKey:       @(1),
            AVLinearPCMBitDepthKey:      @(32),
            AVLinearPCMIsFloatKey:       @YES,
            AVLinearPCMIsBigEndianKey:   @NO,
            AVLinearPCMIsNonInterleaved: @NO,
        };
        AVAssetReaderAudioMixOutput* out =
            [AVAssetReaderAudioMixOutput assetReaderAudioMixOutputWithAudioTracks:tracks
                                                                   audioSettings:settings];
        if (![reader canAddOutput:out]) { fail("cannot add audio reader output"); return; }
        [reader addOutput:out];
        if (![reader startReading]) {
            fail(reader.error ? reader.error.localizedDescription.UTF8String : "startReading failed");
            return;
        }

        // log-spaced band edges, as FFT bin indices
        int edge[AS_BANDS + 1];
        {
            double binLo = AS_LO_HZ * AS_FFT / AS_RATE;
            double binHi = AS_HI_HZ * AS_FFT / AS_RATE;
            double ratio = pow(binHi / binLo, 1.0 / AS_BANDS);
            double b = binLo;
            for (int i = 0; i <= AS_BANDS; i++) {
                int v = (int)(b + 0.5);
                if (v < 1) v = 1;
                if (v > AS_BINS - 1) v = AS_BINS - 1;
                edge[i] = v;
                b *= ratio;
            }
        }

        float hann[AS_FFT];
        vDSP_hann_window(hann, AS_FFT, vDSP_HANN_DENORM);
        FFTSetup fft = vDSP_create_fftsetup(AS_FFT_LOG2, kFFTRadix2);
        if (!fft) { fail("fft setup failed"); return; }

        std::vector<float>    pending;      // samples not yet consumed by a window
        std::vector<uint64_t> hashes;
        std::vector<uint32_t> ptsMs;
        std::vector<uint16_t> peaks;
        hashes.reserve(job->hopsTotal.load() > 0 ? job->hopsTotal.load() : 4096);

        float windowed[AS_FFT], realp[AS_BINS], imagp[AS_BINS], mag[AS_BINS];
        DSPSplitComplex split = { realp, imagp };
        double bandE[AS_BANDS + 1], prevE[AS_BANDS + 1];
        bool   havePrev = false;
        long long hopIndex = 0;

        while (reader.status == AVAssetReaderStatusReading) {
            if (job->cancel) break;
            @autoreleasepool {
                CMSampleBufferRef sb = [out copyNextSampleBuffer];
                if (!sb) break;
                CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
                if (bb) {
                    size_t len = 0;
                    char*  ptr = nullptr;
                    if (CMBlockBufferGetDataPointer(bb, 0, NULL, &len, &ptr) == kCMBlockBufferNoErr
                        && ptr && len >= sizeof(float)) {
                        const float* f = (const float*)ptr;
                        pending.insert(pending.end(), f, f + (len / sizeof(float)));
                    }
                }
                CFRelease(sb);

                size_t consumed = 0;
                while (pending.size() - consumed >= (size_t)AS_FFT) {
                    const float* src = pending.data() + consumed;
                    vDSP_vmul(src, 1, hann, 1, windowed, 1, AS_FFT);
                    vDSP_ctoz((const DSPComplex*)windowed, 2, &split, 1, AS_BINS);
                    vDSP_fft_zrip(fft, &split, 1, AS_FFT_LOG2, FFT_FORWARD);
                    vDSP_zvmags(&split, 1, mag, 1, AS_BINS);

                    for (int m = 0; m <= AS_BANDS; m++) {
                        int lo = edge[m], hi = (m < AS_BANDS) ? edge[m + 1] : edge[AS_BANDS];
                        if (hi <= lo) hi = lo + 1;
                        double sum = 0.0;
                        for (int k = lo; k < hi && k < AS_BINS; k++) sum += mag[k];
                        // log energy, so the differencing below compares ratios and a
                        // change of level drops out
                        bandE[m] = log(sum + 1e-9);
                    }

                    if (havePrev) {
                        uint64_t h = 0;
                        for (int m = 0; m < AS_BANDS; m++) {
                            double d = (bandE[m] - bandE[m + 1]) - (prevE[m] - prevE[m + 1]);
                            if (d > 0.0) h |= (1ull << m);
                        }
                        hashes.push_back(h);
                        ptsMs.push_back((uint32_t)(hopIndex * 1000.0 / AS_HZ + 0.5));

                        // Level over this hop's own samples, not the whole 1024-sample
                        // window, so consecutive peaks tile the file exactly once. The
                        // hash cannot supply this: differencing across frequency and
                        // time is what makes it survive a level change, which means it
                        // has thrown level away by construction.
                        float mx = 0.0f;
                        vDSP_maxmgv(src, 1, &mx, AS_HOP);
                        if (mx > 1.0f) mx = 1.0f;   // float PCM can exceed full scale
                        peaks.push_back((uint16_t)(mx * 65535.0f + 0.5f));

                        hopIndex++;
                        job->hopsDone = (int)hashes.size();
                    }
                    memcpy(prevE, bandE, sizeof(bandE));
                    havePrev = true;

                    consumed += AS_HOP;
                }
                if (consumed > 0) pending.erase(pending.begin(), pending.begin() + consumed);
            }
        }

        vDSP_destroy_fftsetup(fft);

        if (job->cancel) { [reader cancelReading]; fail("cancelled"); return; }
        if (reader.status == AVAssetReaderStatusFailed) {
            fail(reader.error ? reader.error.localizedDescription.UTF8String : "read failed");
            return;
        }
        if (hashes.empty()) { fail("no audio decoded"); return; }

        struct stat st;
        int64_t srcSize = 0, srcMtime = 0;
        if (stat(srcPath.c_str(), &st) == 0) {
            srcSize  = (int64_t)st.st_size;
            srcMtime = (int64_t)st.st_mtime;
        }

        FSHeader hdr;
        memset(&hdr, 0, sizeof(hdr));
        memcpy(hdr.magic, FS_MAGIC, 8);
        hdr.frameCount = (uint32_t)hashes.size();
        hdr.grid       = 0;              // no grid: this is an audio store
        hdr.fps        = AS_HZ;          // hops per second
        hdr.duration   = duration;
        hdr.srcSize    = srcSize;
        hdr.srcMtime   = srcMtime;
        hdr.flags      = FS_FLAG_AUDIO | FS_FLAG_PEAKS;

        // Per-job temp name, not a shared ".tmp". Two analyses of the same file can now
        // legitimately be in flight at once -- the waveform starts one as soon as the
        // tab opens, the match may start another -- and a shared temp file would have
        // them writing over each other. With separate temps whichever renames last
        // wins, and since both produce identical bytes from identical input, either
        // outcome is correct.
        char tmpSuffix[48];
        snprintf(tmpSuffix, sizeof(tmpSuffix), ".tmp%llx",
                 (unsigned long long)(uintptr_t)job);
        std::string tmp = storePath + tmpSuffix;
        FILE* fo = fopen(tmp.c_str(), "wb");
        if (!fo) { fail("cannot open audio store for writing"); return; }
        bool ok = fwrite(&hdr, sizeof(hdr), 1, fo) == 1
               && fwrite(hashes.data(), sizeof(uint64_t), hashes.size(), fo) == hashes.size()
               && fwrite(ptsMs.data(),  sizeof(uint32_t), ptsMs.size(),  fo) == ptsMs.size()
               && fwrite(peaks.data(),  sizeof(uint16_t), peaks.size(),  fo) == peaks.size();
        fclose(fo);
        if (!ok) { remove(tmp.c_str()); fail("audio store write failed"); return; }
        remove(storePath.c_str());
        if (rename(tmp.c_str(), storePath.c_str()) != 0) { fail("audio store rename failed"); return; }

        job->hopCount = (int)hashes.size();
        job->state    = 1;
    }
}

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

static int VP_AnalyzeAudio(const char* mediaPath, const char* storePath, int force) {
    if (!mediaPath || !mediaPath[0] || !storePath || !storePath[0]) return 0;

    auto* job = new AudioJob();
    if (!force && audioStoreFresh(storePath, mediaPath)) {
        FSHeader h;
        fsReadHeader(storePath, &h);
        job->hopCount  = (int)h.frameCount;
        job->hopsTotal = (int)h.frameCount;
        job->hopsDone  = (int)h.frameCount;
        job->state     = 1;
    }

    int id;
    {
        std::lock_guard<std::mutex> lk(g_aMu);
        id = g_aNext++;
        g_aJobs[id] = job;
    }
    if (job->state == 0)
        job->th = std::thread(audioWorker, job, std::string(mediaPath), std::string(storePath));
    return id;
}

static int VP_AudioState(int id) {
    std::lock_guard<std::mutex> lk(g_aMu);
    AudioJob* j = getAudioJob(id);
    return j ? j->state.load() : 2;
}
static double VP_AudioProgress(int id) {
    std::lock_guard<std::mutex> lk(g_aMu);
    AudioJob* j = getAudioJob(id);
    if (!j) return 0.0;
    if (j->state == 1) return 1.0;
    int total = j->hopsTotal.load();
    if (total <= 0) return 0.0;
    double p = (double)j->hopsDone.load() / (double)total;
    return p < 0.0 ? 0.0 : (p > 1.0 ? 1.0 : p);
}
static int VP_AudioHops(int id) {
    std::lock_guard<std::mutex> lk(g_aMu);
    AudioJob* j = getAudioJob(id);
    return j ? j->hopCount.load() : 0;
}
static const char* VP_AudioError(int id) {
    static char sBuf[1024];
    sBuf[0] = '\0';
    std::lock_guard<std::mutex> lk(g_aMu);
    AudioJob* j = getAudioJob(id);
    if (j) {
        std::lock_guard<std::mutex> lk2(j->errMu);
        snprintf(sBuf, sizeof(sBuf), "%s", j->error.c_str());
    }
    return sBuf;
}
static void VP_AudioCancel(int id) {
    std::lock_guard<std::mutex> lk(g_aMu);
    AudioJob* j = getAudioJob(id);
    if (j) j->cancel = true;
}
static void VP_AudioRelease(int id) {
    AudioJob* j = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_aMu);
        auto it = g_aJobs.find(id);
        if (it != g_aJobs.end()) { j = it->second; g_aJobs.erase(it); }
    }
    if (!j) return;
    j->cancel = true;
    if (j->th.joinable()) j->th.join();
    delete j;
}
// Hops per second recorded in an audio store, for turning matched hop ranges into time.
static double VP_AudioRate(const char* storePath) {
    FSHeader h;
    if (!storePath || !fsReadHeader(storePath, &h)) return 0.0;
    return (h.flags & FS_FLAG_AUDIO) ? h.fps : 0.0;
}

// -----------------------------------------------------------------------
// Waveform display
// -----------------------------------------------------------------------
// Decimation happens here rather than in the script because the script would
// otherwise have to carry 120,000 numbers per 20-minute file across the Lua boundary
// and reduce them itself every time the view moved. Asking for exactly the visible
// range at exactly the visible pixel width keeps each call to roughly a thousand
// buckets, small enough to request again on every scroll step.
//
// Two values per bucket: the peak, and the mean of the peaks within it. The peak alone
// makes every busy passage look equally loud, because one transient fills the strip;
// the mean is what separates sustained level from a spike.

struct PeakCache {
    std::string           path;
    int64_t               srcSize = 0, srcMtime = 0;
    double                hz = 0.0, duration = 0.0;
    std::vector<uint16_t> peak;
};
// Two slots: the two versions on screen. Re-reading the header each call (64 bytes)
// is what catches a store that has just been re-analysed underneath us.
static PeakCache  g_pk[2];
static int        g_pkNext = 0;
static std::mutex g_pkMu;

static const PeakCache* peakCacheGet(const char* storePath) {
    FSHeader h;
    if (!fsReadHeader(storePath, &h)) return nullptr;
    if ((h.flags & FS_FLAG_AUDIO) == 0 || (h.flags & FS_FLAG_PEAKS) == 0) return nullptr;

    for (PeakCache& c : g_pk) {
        if (c.path == storePath && c.srcSize == h.srcSize && c.srcMtime == h.srcMtime
            && c.peak.size() == (size_t)h.frameCount)
            return &c;
    }

    FrameStore fs;
    if (!fsLoad(storePath, &fs, false) || fs.peak.empty()) return nullptr;

    PeakCache& c = g_pk[g_pkNext];
    g_pkNext  = (g_pkNext + 1) % 2;
    c.path     = storePath;
    c.srcSize  = h.srcSize;
    c.srcMtime = h.srcMtime;
    c.hz       = h.fps;
    c.duration = h.duration;
    c.peak     = std::move(fs.peak);
    return &c;
}

static const char* VP_AudioPeaks(const char* storePath, double fromSec, double toSec,
                                 int buckets) {
    static std::string out;
    out.clear();
    if (!storePath || !storePath[0]) { out = "E no store"; return out.c_str(); }
    if (buckets < 1)    buckets = 1;
    if (buckets > 8192) buckets = 8192;

    std::lock_guard<std::mutex> lk(g_pkMu);
    const PeakCache* c = peakCacheGet(storePath);
    if (!c) { out = "E store has no peaks"; return out.c_str(); }

    const double hz = (c->hz > 0.0) ? c->hz : AS_HZ;
    const int    n  = (int)c->peak.size();
    if (!(toSec > fromSec)) toSec = fromSec + 1.0 / hz;

    char head[160];
    snprintf(head, sizeof(head), "P %d %.6f %d %.6f\n", buckets, hz, n, c->duration);
    out  = head;
    out.reserve(out.size() + (size_t)buckets * 10);

    const double span = toSec - fromSec;
    char num[32];
    for (int b = 0; b < buckets; b++) {
        double t0 = fromSec + span * b / buckets;
        double t1 = fromSec + span * (b + 1) / buckets;
        int i0 = (int)floor(t0 * hz);
        int i1 = (int)ceil(t1 * hz);
        if (i1 <= i0) i1 = i0 + 1;       // never skip a hop when zoomed past 1:1
        if (i0 < 0) i0 = 0;
        if (i1 > n) i1 = n;

        int    mx  = 0;
        double sum = 0.0;
        int    cnt = 0;
        for (int i = i0; i < i1; i++) {
            int v = c->peak[i];
            if (v > mx) mx = v;
            sum += v;
            cnt++;
        }
        int mean = cnt ? (int)(sum / cnt) : 0;
        // 0..1000: a tenth of a percent of full scale is finer than any strip of
        // pixels can show, and three digits keeps the blob cheap to parse per frame
        snprintf(num, sizeof(num), "%d %d ", mx * 1000 / 65535, mean * 1000 / 65535);
        out += num;
    }
    return out.c_str();
}

void audioStoreShutdown() {
    std::vector<AudioJob*> jobs;
    {
        std::lock_guard<std::mutex> lk(g_aMu);
        for (auto& kv : g_aJobs) jobs.push_back(kv.second);
        g_aJobs.clear();
    }
    for (auto* j : jobs) {
        j->cancel = true;
        if (j->th.joinable()) j->th.join();
        delete j;
    }
}

// -----------------------------------------------------------------------
// Vararg wrappers. int returns cast into the pointer; doubles return a pointer.
// -----------------------------------------------------------------------
static double g_aRet;

static void* VA_VP_AnalyzeAudio(void** a, int n) {
    int r = (n < 2) ? 0 : VP_AnalyzeAudio((const char*)a[0], (const char*)a[1],
                                          n >= 3 ? (int)(intptr_t)a[2] : 0);
    return (void*)(intptr_t)r;
}
static void* VA_VP_AudioState(void** a, int n) {
    return (void*)(intptr_t)((n < 1) ? 2 : VP_AudioState((int)(intptr_t)a[0]));
}
static void* VA_VP_AudioProgress(void** a, int n) {
    g_aRet = (n < 1) ? 0.0 : VP_AudioProgress((int)(intptr_t)a[0]);
    return &g_aRet;
}
static void* VA_VP_AudioHops(void** a, int n) {
    return (void*)(intptr_t)((n < 1) ? 0 : VP_AudioHops((int)(intptr_t)a[0]));
}
static void* VA_VP_AudioError(void** a, int n) {
    return (n < 1) ? (void*)"" : (void*)VP_AudioError((int)(intptr_t)a[0]);
}
static void* VA_VP_AudioCancel(void** a, int n) {
    if (n >= 1) VP_AudioCancel((int)(intptr_t)a[0]);
    return nullptr;
}
static void* VA_VP_AudioRelease(void** a, int n) {
    if (n >= 1) VP_AudioRelease((int)(intptr_t)a[0]);
    return nullptr;
}
static void* VA_VP_AudioRate(void** a, int n) {
    g_aRet = (n < 1) ? 0.0 : VP_AudioRate((const char*)a[0]);
    return &g_aRet;
}
static void* VA_VP_AudioPeaks(void** a, int n) {
    if (n < 4) return (void*)"E bad arguments";
    return (void*)VP_AudioPeaks((const char*)a[0], *(double*)a[1], *(double*)a[2],
                                (int)(intptr_t)a[3]);
}

const VPFunc g_audioStoreFuncs[] = {
    { "VP_AnalyzeAudio", (void*)VP_AnalyzeAudio, (void*)VA_VP_AnalyzeAudio,
      "int", "const char*,const char*,int", "mediaPath,storePath,force",
      "Start background audio fingerprinting (works on a video or a separate audio file). "
      "Returns job id (>0) or 0. The store it writes can be passed straight to VP_Match." },
    { "VP_AudioState", (void*)VP_AudioState, (void*)VA_VP_AudioState,
      "int", "int", "job", "0=running 1=done 2=error." },
    { "VP_AudioProgress", (void*)VP_AudioProgress, (void*)VA_VP_AudioProgress,
      "double", "int", "job", "Analysis progress 0..1." },
    { "VP_AudioHops", (void*)VP_AudioHops, (void*)VA_VP_AudioHops,
      "int", "int", "job", "Hops fingerprinted (valid once state=1)." },
    { "VP_AudioError", (void*)VP_AudioError, (void*)VA_VP_AudioError,
      "const char*", "int", "job", "Error message when state=2, else empty." },
    { "VP_AudioCancel", (void*)VP_AudioCancel, (void*)VA_VP_AudioCancel,
      "void", "int", "job", "Ask a running audio analysis to stop." },
    { "VP_AudioRelease", (void*)VP_AudioRelease, (void*)VA_VP_AudioRelease,
      "void", "int", "job", "Free the job and join its thread. Call once per VP_AnalyzeAudio." },
    { "VP_AudioRate", (void*)VP_AudioRate, (void*)VA_VP_AudioRate,
      "double", "const char*", "storePath",
      "Hops per second in an audio store, for converting matched hop ranges to seconds." },
    { "VP_AudioPeaks", (void*)VP_AudioPeaks, (void*)VA_VP_AudioPeaks,
      "const char*", "const char*,double,double,int", "storePath,fromSec,toSec,buckets",
      "Waveform envelope for a time range, decimated to `buckets` buckets. Returns "
      "'P buckets hopsPerSec hopCount durationSec' then, on the next line, two integers "
      "0..1000 per bucket: peak then mean of the peaks in it. Ranges past the end of the "
      "audio read as 0. 'E msg' on error." },
};
const int g_audioStoreFuncCount = (int)(sizeof(g_audioStoreFuncs) / sizeof(g_audioStoreFuncs[0]));
