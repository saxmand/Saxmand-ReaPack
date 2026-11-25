#ifdef _WIN32

// video_decoder, Windows: Media Foundation for the decode, WIC for the encode.
//
// Random access -- one frame wherever the playhead is -- in process, so previews and
// thumbnails need nothing installed. Both halves are part of Windows.
//
// Two details that are easy to get wrong and silently produce rubbish:
//
//   RGB32 out of MF is BGRA, and it is bottom-up whenever MF_MT_DEFAULT_STRIDE comes
//   back negative. Ignoring the sign gives a vertically mirrored picture, which looks
//   like a decode that "works" until someone notices every frame is upside down.
//
//   The WIC JPEG encoder does not take 32bppBGRA. Rather than let SetPixelFormat
//   negotiate to something and then having to match whatever it chose, the pixels are
//   converted to 24bppBGR here, which both JPEG and PNG accept. Video has no alpha to
//   lose.

#include "win_mf.h"
#include "frame_cache.h"
#include "vp_fileio.h"
#include "bgra_rows.h"
#include "frame_pick.h"

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <wincodec.h>
#include <objbase.h>

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <thread>
#include <cstddef>
#include <string>
#include <vector>

namespace {

// GUID_NULL lives in uuid.lib, and pulling a whole import library in for one all-zero
// constant means one more thing to get right in two build scripts. As the time-format
// argument to SetCurrentPosition it simply means "100-nanosecond units", the default.
static const GUID kTimeFormatDefault = { 0, 0, 0, { 0, 0, 0, 0, 0, 0, 0, 0 } };

template <class T> struct Rel {
    T* p = nullptr;
    ~Rel() { if (p) p->Release(); }
    T** operator&() { return &p; }
    T*  operator->() const { return p; }
    operator T*() const { return p; }
};

// WIC and MF both want COM up on the calling thread. RPC_E_CHANGED_MODE means it is
// already up in the other apartment model, which is fine -- we are a guest in REAPER's
// process and must not re-initialise or tear down its COM.
void comEnsure() {
    static thread_local bool done = false;
    if (done) return;
    done = true;
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
}

// row0 points at image row 0 and rowStep is the signed step to the row below, so a
// bottom-up buffer needs no flag of its own.
bool writeBGR24(const std::string& path, int w, int h,
                const uint8_t* row0, ptrdiff_t rowStep) {
    comEnsure();

    bool isPng = path.size() > 4 &&
                 (_stricmp(path.c_str() + path.size() - 4, ".png") == 0);

    int n = MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, nullptr, 0);
    std::wstring wpath(n > 0 ? n - 1 : 0, L'\0');
    if (n > 0) MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, &wpath[0], n);

    Rel<IWICImagingFactory> factory;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory)))) return false;

    Rel<IWICStream> stream;
    if (FAILED(factory->CreateStream(&stream))) return false;
    if (FAILED(stream->InitializeFromFilename(wpath.c_str(), GENERIC_WRITE))) return false;

    Rel<IWICBitmapEncoder> enc;
    if (FAILED(factory->CreateEncoder(isPng ? GUID_ContainerFormatPng
                                            : GUID_ContainerFormatJpeg,
                                      nullptr, &enc))) return false;
    if (FAILED(enc->Initialize(stream, WICBitmapEncoderNoCache))) return false;

    Rel<IWICBitmapFrameEncode> frame;
    IPropertyBag2* bag = nullptr;
    if (FAILED(enc->CreateNewFrame(&frame, &bag))) return false;
    if (bag) { frame->Initialize(bag); bag->Release(); }
    else if (FAILED(frame->Initialize(nullptr))) return false;

    if (FAILED(frame->SetSize((UINT)w, (UINT)h))) return false;
    WICPixelFormatGUID fmt = GUID_WICPixelFormat24bppBGR;
    if (FAILED(frame->SetPixelFormat(&fmt))) return false;
    if (fmt != GUID_WICPixelFormat24bppBGR) return false;   // not negotiating; see above

    const int dstStride = ((w * 3) + 3) & ~3;               // WIC wants 4-byte rows
    std::vector<uint8_t> rows((size_t)dstStride * h, 0);
    for (int y = 0; y < h; y++) {
        const uint8_t* src = row0 + (ptrdiff_t)y * rowStep;
        uint8_t* dst = rows.data() + (size_t)y * dstStride;
        for (int x = 0; x < w; x++) {
            dst[x * 3 + 0] = src[x * 4 + 0];   // B
            dst[x * 3 + 1] = src[x * 4 + 1];   // G
            dst[x * 3 + 2] = src[x * 4 + 2];   // R
        }
    }
    if (FAILED(frame->WritePixels((UINT)h, (UINT)dstStride,
                                  (UINT)rows.size(), rows.data()))) return false;
    if (FAILED(frame->Commit())) return false;
    return SUCCEEDED(enc->Commit());
}

class MFDecoder : public VideoDecoder {
public:
    ~MFDecoder() override {
        stopWorker();                     // joins before anything it touches is freed
        if (reader) reader->Release();
    }

    // A worker never starts a worker of its own.
    void markAsWorker() { isWorker = true; }

    bool open(const char* path, std::string* errOut) {
        if (!mfEnsureStarted()) { if (errOut) *errOut = "Media Foundation unavailable"; return false; }
        comEnsure();
        src  = path;
        hash = hashPath(path);

        int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, nullptr, 0);
        std::wstring wpath(n > 0 ? n - 1 : 0, L'\0');
        if (n > 0) MultiByteToWideChar(CP_UTF8, 0, path, -1, &wpath[0], n);

        Rel<IMFAttributes> attr;
        if (FAILED(MFCreateAttributes(&attr, 1))) { if (errOut) *errOut = "MFCreateAttributes failed"; return false; }
        attr->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);

        if (FAILED(MFCreateSourceReaderFromURL(wpath.c_str(), attr, &reader)) || !reader) {
            if (errOut) *errOut = "Media Foundation cannot read this file";
            return false;
        }
        reader->SetStreamSelection((DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE);
        if (FAILED(reader->SetStreamSelection((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE))) {
            if (errOut) *errOut = "no video stream";
            return false;
        }

        // Off the native type, before the output type is set: a prefetch window steps
        // by one frame, so it needs the file's own rate and not a guess. Read from the
        // output type it would be whatever the type built below happens to carry, which
        // is how the fingerprint path once came to label every store 25 fps.
        {
            Rel<IMFMediaType> native;
            if (SUCCEEDED(reader->GetNativeMediaType(
                    (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &native)) && native) {
                UINT32 num = 0, den = 0;
                if (SUCCEEDED(MFGetAttributeRatio(native, MF_MT_FRAME_RATE, &num, &den))
                    && num && den)
                    rate = (double)num / (double)den;
            }
        }

        Rel<IMFMediaType> want;
        if (FAILED(MFCreateMediaType(&want))) { if (errOut) *errOut = "MFCreateMediaType failed"; return false; }
        want->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        want->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
        if (FAILED(reader->SetCurrentMediaType(
                (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, want))) {
            if (errOut) *errOut = "Media Foundation will not decode this to RGB";
            return false;
        }
        readType();

        PROPVARIANT var;
        PropVariantInit(&var);
        if (SUCCEEDED(reader->GetPresentationAttribute(
                (DWORD)MF_SOURCE_READER_MEDIASOURCE, MF_PD_DURATION, &var))) {
            if (var.vt == VT_UI8) dur = (double)var.uhVal.QuadPart / 1.0e7;
        }
        PropVariantClear(&var);
        return dur > 0.0 && width > 0 && height > 0;
    }

    double duration() const override { return dur; }
    bool framePending() const override { return pending; }

    std::string getFrame(double timeSec, int maxW, int maxH) override {
        timeSec = clampTime(timeSec);

        // Asked for the same frame again, which is what a paused playhead does. Only a
        // settled frame short-circuits: while one is pending, lastTime still describes
        // the stand-in being shown, so this would answer about a different moment than
        // the one asked for and the pending state would never clear.
        if (!pending && timeSec == lastTime && maxW == lastW && maxH == lastH
            && !lastPath.empty())
            return lastPath;

        const long long ms  = (long long)(timeSec * 1000.0 + 0.5);
        const std::string out = cacheFramePath(hash, ms, maxW, maxH);
        const double step = frameDur();

        uint64_t have = 0;
        const bool fromWindow = vpStat(out, &have, nullptr) && have > 0;

        std::string result;
        if (fromWindow) {
            cacheTouch(out, have);        // on screen now, so the newest thing there
            result = out;
            pending = false;

            // Move the window on at its midpoint, while the worker is still filling the
            // back half of the current one. Waiting until the window ran out would put a
            // seek and a keyframe decode exactly where playback cannot absorb it.
            const double mid = batchStart + (BATCH / 2) * step;
            if (batchStart < 0.0 || timeSec >= mid || maxW != batchW || maxH != batchH) {
                batchStart = timeSec + step;
                batchW = maxW; batchH = maxH;
                requestWindow(batchStart, maxW, maxH);
            }
        } else {
            // A miss is either a real seek, or the window has not reached here yet.
            const double windowEnd = batchStart + BATCH * step;
            const bool seeked = batchStart < 0.0 || maxW != batchW || maxH != batchH
                             || timeSec < batchStart - 2.0 || timeSec > windowEnd + 2.0;
            if (seeked) {
                // Start the window behind the request, so the run has its keyframe
                // decoded by the time playback arrives rather than opening with a stall.
                batchStart = timeSec;
                batchW = maxW; batchH = maxH;
                requestWindow(std::max(0.0, timeSec - (BATCH / 2) * step), maxW, maxH);
            }

            // The frame itself goes to the worker too, ahead of the window. Decoding it
            // here instead is what made selecting a cut stall: a seek means a keyframe
            // and then a walk forward, which on Media Foundation is hundreds of
            // milliseconds where AVFoundation pays tens -- and the interface is calling
            // this for two previews at once. Showing the frame already on screen for a
            // tick or two is the better trade; the next call finds this one on disk.
            requestPoint(timeSec, maxW, maxH);

            if (timeSec != missTime) { missTime = timeSec; missCount = 0; }
            missCount++;

            // Unless it has not arrived for long enough that something is wrong with it,
            // in which case decode it here and be certain rather than leave the wrong
            // picture up for good.
            if (!lastPath.empty() && missCount <= 30) {
                // Say so, or the caller leaves this on screen until the playhead moves
                // again: it asks for a frame on a move and not otherwise.
                pending = true;
                return lastPath;
            }

            if (!decodeTo(timeSec, maxW, maxH, out)) { pending = false; return std::string(); }
            cacheTouch(out, 0);
            pending = false;
            result = out;
        }

        if (!result.empty()) {
            lastTime = timeSec; lastW = maxW; lastH = maxH; lastPath = result;
        }
        return result;
    }

    bool extractTo(double timeSec, int maxW, int maxH, const char* outPath) override {
        if (!outPath || !outPath[0]) return false;
        return decodeTo(clampTime(timeSec), maxW, maxH, outPath);
    }

private:
    // Starts the worker on first use rather than at open: a decoder that only ever has
    // one frame taken out of it -- a thumbnail -- should not pay for a second reader.
    void ensureWorker() {
        if (isWorker || workerStarted) return;
        workerStarted = true;
        workerTh = std::thread([this] { workerLoop(); });
    }

    void stopWorker() {
        if (!workerTh.joinable()) return;
        {
            std::lock_guard<std::mutex> lk(wmu);
            wStop = true;
            wGen++;                       // abandons the window in flight
        }
        wcv.notify_one();
        workerTh.join();
    }

    // Asks for a window. A request supersedes whatever is running: the generation moves,
    // and the run in flight notices at its next frame boundary rather than mid-frame, so
    // the longest anything waits is one frame's decode.
    void requestWindow(double startTime, int w, int h) {
        ensureWorker();
        {
            std::lock_guard<std::mutex> lk(wmu);
            if (wPending && wStart == startTime && wW == w && wH == h) return;
            wStart = startTime; wW = w; wH = h;
            wPending = true;
            wGen++;
        }
        wcv.notify_one();
    }

    // Asks the worker for one frame, ahead of any window.
    void requestPoint(double timeSec, int w, int h) {
        ensureWorker();
        {
            std::lock_guard<std::mutex> lk(wmu);
            if (wPointPending.load() && wPointTime == timeSec && wPointW == w && wPointH == h)
                return;                   // already asked for exactly this
            wPointTime = timeSec; wPointW = w; wPointH = h;
            wPointPending.store(true);
        }
        wcv.notify_one();
    }

    void workerLoop() {
        // The reader is created here and used only here. comEnsure puts a thread into a
        // single-threaded apartment, so a reader built on the interface's thread and
        // read from this one is a cross-apartment call on an STA object -- which tends
        // to appear to work right up until it does not. This thread also writes the
        // JPEGs, through WIC, which wants COM on it regardless.
        comEnsure();
        MFDecoder w;
        w.markAsWorker();
        if (!w.open(src.c_str(), nullptr)) return;   // no prefetch; decoding on demand
                                                     // still answers every request
        for (;;) {
            bool   doPoint = false;
            double pt = 0.0; int ptW = 0, ptH = 0;
            double start = 0.0; int w_ = 0, h_ = 0; uint64_t gen = 0;
            {
                std::unique_lock<std::mutex> lk(wmu);
                wcv.wait(lk, [this] { return wStop || wPending || wPointPending.load(); });
                if (wStop) return;
                if (wPointPending.load()) {
                    doPoint = true;
                    pt = wPointTime; ptW = wPointW; ptH = wPointH;
                    wPointPending.store(false);
                } else {
                    start = wStart; w_ = wW; h_ = wH;
                    wPending = false;
                    gen = wGen.load();
                }
            }

            if (doPoint) {
                // Straight to the cache path the interface is looking for, by the same
                // route and so the same frame a direct decode would have produced.
                const long long ms = (long long)(pt * 1000.0 + 0.5);
                w.decodeTo(pt, ptW, ptH, cacheFramePath(w.hash, ms, ptW, ptH));
                continue;                 // a window waiting goes next time round
            }

            // Abandoned as soon as the generation moves -- a new window or a shutdown --
            // and also when a single frame is wanted, which cannot sit behind four
            // seconds of decoding.
            w.decodeRun(start, BATCH, w_, h_,
                        [this, gen] { return wGen.load() != gen || wPointPending.load(); });
        }
    }

    void readType() {
        Rel<IMFMediaType> cur;
        if (FAILED(reader->GetCurrentMediaType(
                (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &cur))) return;
        UINT32 w = 0, h = 0;
        if (SUCCEEDED(MFGetAttributeSize(cur, MF_MT_FRAME_SIZE, &w, &h))) {
            fullWidth = width = (int)w; fullHeight = height = (int)h;
        }
        // Negative means the rows run bottom to top, which is usual for RGB out of MF.
        UINT32 st = 0;
        if (SUCCEEDED(cur->GetUINT32(MF_MT_DEFAULT_STRIDE, &st)))
            bottomUp = ((INT32)st) < 0;

        // The coded size is padded up to whole macroblocks -- 1440x1080 arrives as
        // 1440x1088 -- and only the aperture says which part is the picture. Without
        // this a thumbnail carries rows of padding and is squashed by that much.
        cropX = cropY = 0;
        MFVideoArea area;
        memset(&area, 0, sizeof(area));
        if (SUCCEEDED(cur->GetBlob(MF_MT_MINIMUM_DISPLAY_APERTURE,
                                   (UINT8*)&area, sizeof(area), nullptr))
            || SUCCEEDED(cur->GetBlob(MF_MT_GEOMETRIC_APERTURE,
                                      (UINT8*)&area, sizeof(area), nullptr))) {
            int ax = area.OffsetX.value, ay = area.OffsetY.value;
            int aw = area.Area.cx,       ah = area.Area.cy;
            if (aw > 0 && ah > 0 && ax >= 0 && ay >= 0
                && ax + aw <= fullWidth && ay + ah <= fullHeight) {
                cropX = ax; cropY = ay; width = aw; height = ah;
            }
        }
    }

    double clampTime(double t) const { return t < 0.0 ? 0.0 : (t > dur ? dur : t); }

    bool seekTo(double timeSec) {
        PROPVARIANT pos;
        PropVariantInit(&pos);
        pos.vt = VT_I8;
        pos.hVal.QuadPart = (LONGLONG)(timeSec * 1.0e7);
        HRESULT hr = reader->SetCurrentPosition(kTimeFormatDefault, pos);
        PropVariantClear(&pos);
        return SUCCEEDED(hr);
    }

    double frameDur() const { return 1.0 / (rate > 0.0 ? rate : 25.0); }

    // Decodes a window of `count` frames from startTime, writing each to the cache under
    // the grid time it serves. One seek and then forward reads, which is the whole point:
    // the frames of a group of pictures are nearly free once its keyframe has been
    // decoded, so a window costs little more than the single frame at its start.
    //
    // Which grid point a frame serves comes from gridIndexFor, so a frame written here is
    // the same one decodeTo would have written for that time -- either may answer the
    // request, and they must not disagree.
    int decodeRun(double startTime, int count, int maxW, int maxH,
                  const std::function<bool()>& cancelled) {
        if (!reader || count <= 0) return 0;
        if (!seekTo(startTime)) return 0;

        const double step = frameDur();
        int written = 0;

        for (;;) {
            if (cancelled()) break;

            DWORD      flags = 0;
            LONGLONG   ts    = 0;
            IMFSample* smp   = nullptr;
            if (FAILED(reader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
                                          0, nullptr, &flags, &ts, &smp)))
                break;
            if (flags & MF_SOURCE_READERF_ENDOFSTREAM) { if (smp) smp->Release(); break; }
            if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) readType();
            if (!smp) continue;

            const double pts = (double)ts / 1.0e7;
            const int    idx = gridIndexFor(pts, startTime, step, count);
            if (idx < 0) {
                // Before the window: the seek landed on an earlier keyframe, and these
                // frames are the cost of reaching the ones wanted. Past it: done.
                const bool past = pts > startTime + count * step;
                smp->Release();
                if (past) break;
                continue;
            }

            const long long ms = (long long)((startTime + idx * step) * 1000.0 + 0.5);
            const std::string out = cacheFramePath(hash, ms, maxW, maxH);
            uint64_t have = 0;
            if (!(vpStat(out, &have, nullptr) && have > 0)) {
                if (encodeSampleAtomic(smp, maxW, maxH, out)) {
                    cacheTouch(out, 0);
                    written++;
                }
            }
            smp->Release();
        }
        return written;
    }

    bool decodeTo(double timeSec, int maxW, int maxH, const std::string& outPath) {
        // SetCurrentPosition seeks to the nearest keyframe AT OR BEFORE the request and
        // stops there -- it does not decode on to the time asked for. This used to take
        // whatever that first sample was without looking at its timestamp, so every
        // thumbnail came from the preceding keyframe: out by anything from nothing to a
        // whole GOP, differently for each one. The frame wanted is the one on screen at
        // timeSec, which is the last frame whose timestamp has not passed it -- the same
        // frame AVFoundation returns on the other platform, where the tolerances are
        // pinned to zero for exactly this reason.
        if (!seekTo(timeSec)) return false;

        const LONGLONG target = (LONGLONG)(timeSec * 1.0e7);
        IMFSample* best = nullptr;
        LONGLONG   bestTs = 0;
        // Bounded only to keep a decoder that reports non-advancing timestamps from
        // spinning; a sane keyframe interval ends the loop long before this.
        for (int tries = 0; tries < 900; tries++) {
            DWORD      flags = 0;
            LONGLONG   ts    = 0;
            IMFSample* smp   = nullptr;
            if (FAILED(reader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
                                          0, nullptr, &flags, &ts, &smp))) {
                if (best) best->Release();
                return false;
            }
            // End of stream with something in hand is not a failure: a request at the
            // very end of a file legitimately resolves to the last frame.
            if (flags & MF_SOURCE_READERF_ENDOFSTREAM) { if (smp) smp->Release(); break; }
            if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) readType();
            if (!smp) continue;

            // See frame_pick.h for the rule and why it is nearest.
            const FramePick pick = framePick((long long)ts, (long long)target,
                                             (long long)bestTs, best != nullptr);
            if (pick == FramePick::Overshot) { smp->Release(); break; }
            if (best) best->Release();
            best = smp; bestTs = ts;
            if (pick == FramePick::Take) break;
        }
        if (!best) return false;

        // Atomic here too: the worker answers single-frame requests through this, into
        // the same cache the interface is watching -- and a thumbnail half-written when
        // REAPER quits would otherwise be served as a complete one ever after.
        bool ok = encodeSampleAtomic(best, maxW, maxH, outPath);
        best->Release();
        if (!ok) return false;
        uint64_t size = 0;
        return vpStat(outPath, &size, nullptr) && size > 0;
    }

    // Writes through a sibling temp file and renames into place.
    //
    // The worker writes frames while the interface is checking for them, so a direct
    // write is visible half-finished: the file exists, has a size, and is not a picture
    // yet. A rename is atomic, so a frame is either absent or complete. It also means an
    // interrupted write -- a cancelled window, a crash -- leaves no corrupt frame behind
    // to be served from the cache forever after.
    bool encodeSampleAtomic(IMFSample* smp, int maxW, int maxH, const std::string& outPath) {
        static std::atomic<unsigned> seq{0};
        char suffix[32];
        snprintf(suffix, sizeof(suffix), ".%u.tmp", seq.fetch_add(1));
        const std::string tmp = outPath + suffix;
        if (!encodeSample(smp, maxW, maxH, tmp)) { vpRemove(tmp); return false; }
        if (vpRename(tmp, outPath) != 0) {
            // Losing the race to another writer is success: the frame is there, and it
            // is the same frame either way.
            uint64_t have = 0;
            const bool present = vpStat(outPath, &have, nullptr) && have > 0;
            vpRemove(tmp);
            return present;
        }
        return true;
    }

    bool encodeSample(IMFSample* smp, int maxW, int maxH, const std::string& outPath) {
        Rel<IMFMediaBuffer> buf;
        if (FAILED(smp->ConvertToContiguousBuffer(&buf)) || !buf) return false;

        // Fit inside the box without distorting: a 4:3 or anamorphic source must not be
        // stretched into a 16:9 slot.
        int outW = width, outH = height;
        if (maxW > 0 && maxH > 0 && (width > maxW || height > maxH)) {
            double s = std::min((double)maxW / width, (double)maxH / height);
            outW = std::max(1, (int)(width * s + 0.5));
            outH = std::max(1, (int)(height * s + 0.5));
        }

        IMF2DBuffer* two = nullptr;
        BYTE* scan = nullptr;
        LONG  pitch = 0;
        bool  locked2D = false, locked = false, contiguous = false;
        if (SUCCEEDED(buf->QueryInterface(IID_PPV_ARGS(&two))) && two
            && SUCCEEDED(two->Lock2D(&scan, &pitch)) && scan) {
            locked2D = true;
        } else {
            if (two) { two->Release(); two = nullptr; }
            DWORD len = 0;
            if (FAILED(buf->Lock(&scan, nullptr, &len)) || !scan) return false;
            locked = true;
            // A contiguous buffer carries no stride of its own, so the CODED width
            // gives it -- the picture width would skew every row for a padded frame.
            if (len < (DWORD)(fullWidth * 4) * (DWORD)fullHeight) { buf->Unlock(); return false; }
            contiguous = true;
        }

        // See bgra_rows.h: padded, bottom-up and cropped all resolve to one pointer and
        // one signed step.
        const BgraRows rows = bgraCrop(
            contiguous ? bgraFromContiguous(scan, fullWidth, fullHeight, bottomUp)
                       : bgraFrom2D(scan, (ptrdiff_t)pitch),
            cropX, cropY);
        const ptrdiff_t rowStep = rows.step;
        const uint8_t*  row0    = rows.row0;

        bool ok;
        if (outW == width && outH == height) {
            ok = writeBGR24(outPath, width, height, row0, rowStep);
        } else {
            // Nearest-neighbour is enough for a preview thumbnail and keeps this free
            // of another dependency; the fingerprint path does its own area-average
            // resample and does not come through here.
            std::vector<uint8_t> small((size_t)outW * outH * 4);
            for (int y = 0; y < outH; y++) {
                int sy = (int)((double)y * height / outH);
                const uint8_t* srow = row0 + (ptrdiff_t)sy * rowStep;
                uint8_t* drow = small.data() + (size_t)y * outW * 4;
                for (int x = 0; x < outW; x++) {
                    int sx = (int)((double)x * width / outW);
                    memcpy(drow + x * 4, srow + sx * 4, 4);
                }
            }
            ok = writeBGR24(outPath, outW, outH, small.data(), (ptrdiff_t)outW * 4);
        }

        if (locked2D) { two->Unlock2D(); two->Release(); }
        if (locked)   { buf->Unlock(); }
        return ok;
    }

    IMFSourceReader* reader = nullptr;
    std::string      src;
    uint32_t         hash = 0;
    int              width = 0, height = 0;          // the picture
    int              fullWidth = 0, fullHeight = 0;  // coded, padding included
    int              cropX = 0, cropY = 0;           // where the picture sits in it
    bool             bottomUp = false;
    double           rate = 0.0;
    double           dur = 0.0;
    bool             isWorker = false;

    // Prefetch. The worker is a second decoder on the same file, so its reader and its
    // seeks never disturb the one answering the interface.
    bool                    workerStarted = false;
    std::thread             workerTh;
    std::mutex              wmu;
    std::condition_variable wcv;
    bool                    wStop = false;
    bool                    wPending = false;      // a window is waiting
    double                  wStart = 0.0;
    int                     wW = 0, wH = 0;
    std::atomic<uint64_t>   wGen{0};

    // A single frame the interface is waiting on. It preempts a window, because a
    // window is work for later while this is the picture on screen now.
    std::atomic<bool>       wPointPending{false};
    double                  wPointTime = 0.0;
    int                     wPointW = 0, wPointH = 0;

    // How long the same unanswered request has been shown the previous frame. Bounded
    // so a frame the worker cannot produce resolves to a direct decode rather than
    // leaving the wrong picture up indefinitely.
    double                  missTime = -1.0;
    int                     missCount = 0;

    // Whether the last getFrame handed back a stand-in rather than the frame asked for.
    bool                    pending = false;

    // The window most recently asked for, and the last frame successfully returned.
    double      batchStart = -1.0;
    int         batchW = 0, batchH = 0;
    std::string lastPath;
    double      lastTime = -1.0;
    int         lastW = 0, lastH = 0;

    // 100 frames is four seconds at 25 fps, comfortably more than one group of
    // pictures, which is what makes the sequential run pay for itself.
    static const int BATCH = 100;
};

} // namespace

VideoDecoder* videoDecoderOpenMF(const char* path, std::string* err) {
    if (!path || !path[0]) { if (err) *err = "no path"; return nullptr; }
    MFDecoder* d = new MFDecoder();
    if (!d->open(path, err)) { delete d; return nullptr; }
    return d;
}

#endif
