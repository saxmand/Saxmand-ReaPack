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

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <wincodec.h>
#include <objbase.h>

#include <algorithm>
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

bool writeBGR24(const std::string& path, int w, int h,
                const uint8_t* bgra, int stride, bool bottomUp) {
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
        const uint8_t* src = bgra + (size_t)(bottomUp ? (h - 1 - y) : y) * stride;
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
    ~MFDecoder() override { if (reader) reader->Release(); }

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

    std::string getFrame(double timeSec, int maxW, int maxH) override {
        timeSec = clampTime(timeSec);
        long long ms = (long long)(timeSec * 1000.0 + 0.5);
        std::string out = cacheFramePath(hash, ms, maxW, maxH);

        uint64_t have = 0;
        if (vpStat(out, &have, nullptr) && have > 0) { cacheTouch(out, have); return out; }
        if (!decodeTo(timeSec, maxW, maxH, out)) return std::string();
        cacheTouch(out, 0);
        return out;
    }

    bool extractTo(double timeSec, int maxW, int maxH, const char* outPath) override {
        if (!outPath || !outPath[0]) return false;
        return decodeTo(clampTime(timeSec), maxW, maxH, outPath);
    }

private:
    void readType() {
        Rel<IMFMediaType> cur;
        if (FAILED(reader->GetCurrentMediaType(
                (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &cur))) return;
        UINT32 w = 0, h = 0;
        if (SUCCEEDED(MFGetAttributeSize(cur, MF_MT_FRAME_SIZE, &w, &h))) {
            width = (int)w; height = (int)h;
        }
        // Negative means the rows run bottom to top, which is usual for RGB out of MF.
        UINT32 st = 0;
        if (SUCCEEDED(cur->GetUINT32(MF_MT_DEFAULT_STRIDE, &st)))
            bottomUp = ((INT32)st) < 0;
    }

    double clampTime(double t) const { return t < 0.0 ? 0.0 : (t > dur ? dur : t); }

    bool decodeTo(double timeSec, int maxW, int maxH, const std::string& outPath) {
        // Seek, then take the first frame at or after the request. MF lands on the
        // nearest keyframe and decodes forward itself, so this is accurate enough for a
        // preview and costs a fraction of reading from the start.
        PROPVARIANT pos;
        PropVariantInit(&pos);
        pos.vt = VT_I8;
        pos.hVal.QuadPart = (LONGLONG)(timeSec * 1.0e7);
        HRESULT hr = reader->SetCurrentPosition(kTimeFormatDefault, pos);
        PropVariantClear(&pos);
        if (FAILED(hr)) return false;

        for (int tries = 0; tries < 240; tries++) {
            DWORD      flags = 0;
            LONGLONG   ts    = 0;
            IMFSample* smp   = nullptr;
            if (FAILED(reader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
                                          0, nullptr, &flags, &ts, &smp))) return false;
            if (flags & MF_SOURCE_READERF_ENDOFSTREAM) { if (smp) smp->Release(); return false; }
            if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) readType();
            if (!smp) continue;

            bool ok = encodeSample(smp, maxW, maxH, outPath);
            smp->Release();
            if (ok) {
                uint64_t size = 0;
                return vpStat(outPath, &size, nullptr) && size > 0;
            }
            return false;
        }
        return false;
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
        bool  locked2D = false, locked = false;
        if (SUCCEEDED(buf->QueryInterface(IID_PPV_ARGS(&two))) && two
            && SUCCEEDED(two->Lock2D(&scan, &pitch)) && scan) {
            locked2D = true;
        } else {
            if (two) { two->Release(); two = nullptr; }
            DWORD len = 0;
            if (FAILED(buf->Lock(&scan, nullptr, &len)) || !scan) return false;
            locked = true;
            pitch = width * 4;
            if ((int)len < pitch * height) { buf->Unlock(); return false; }
        }

        bool flip = bottomUp || pitch < 0;
        int  stride = (int)(pitch < 0 ? -pitch : pitch);
        const uint8_t* base = scan;
        if (pitch < 0) base = scan - (size_t)stride * (height - 1);

        bool ok;
        if (outW == width && outH == height) {
            ok = writeBGR24(outPath, width, height, base, stride, flip);
        } else {
            // Nearest-neighbour is enough for a preview thumbnail and keeps this free
            // of another dependency; the fingerprint path does its own area-average
            // resample and does not come through here.
            std::vector<uint8_t> small((size_t)outW * outH * 4);
            for (int y = 0; y < outH; y++) {
                int sy = (int)((double)y * height / outH);
                if (flip) sy = height - 1 - sy;
                const uint8_t* srow = base + (size_t)sy * stride;
                uint8_t* drow = small.data() + (size_t)y * outW * 4;
                for (int x = 0; x < outW; x++) {
                    int sx = (int)((double)x * width / outW);
                    memcpy(drow + x * 4, srow + sx * 4, 4);
                }
            }
            ok = writeBGR24(outPath, outW, outH, small.data(), outW * 4, false);
        }

        if (locked2D) { two->Unlock2D(); two->Release(); }
        if (locked)   { buf->Unlock(); }
        return ok;
    }

    IMFSourceReader* reader = nullptr;
    std::string      src;
    uint32_t         hash = 0;
    int              width = 0, height = 0;
    bool             bottomUp = false;
    double           dur = 0.0;
};

} // namespace

VideoDecoder* videoDecoderOpenMF(const char* path, std::string* err) {
    if (!path || !path[0]) { if (err) *err = "no path"; return nullptr; }
    MFDecoder* d = new MFDecoder();
    if (!d->open(path, err)) { delete d; return nullptr; }
    return d;
}

#endif
