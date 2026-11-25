#ifdef _WIN32

// frame_source, Windows: Media Foundation.
//
// The sequential whole-file read that fingerprinting, cut detection and version
// matching are built on. In-process, so it needs nothing installed -- which is the
// whole point of having it beside the ffmpeg backend.
//
// NV12 is asked for because its first plane IS the luma, which is exactly what the
// fingerprint wants and means no colour conversion has to happen at all. The same
// reasoning as the macOS path, which asks AVFoundation for the same thing.

#include "win_mf.h"

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>

#include <cmath>
#include <cstddef>
#include <string>
#include <vector>

namespace {

// Releases a COM pointer on the way out of scope. Written out rather than pulled in
// from a library because it is six lines and this file would otherwise leak on every
// early return -- of which there are many, since almost every MF call can fail.
template <class T> struct Rel {
    T* p = nullptr;
    ~Rel() { if (p) p->Release(); }
    T** operator&() { return &p; }
    T*  operator->() const { return p; }
    operator T*() const { return p; }
};

class MFFrameSource : public FrameSource {
public:
    ~MFFrameSource() override {
        unlock();
        if (reader) reader->Release();
    }

    bool open(const char* path, int w, int h, std::string* errOut) {
        if (!mfEnsureStarted()) { if (errOut) *errOut = "Media Foundation unavailable"; return false; }

        int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, nullptr, 0);
        std::wstring wpath(n > 0 ? n - 1 : 0, L'\0');
        if (n > 0) MultiByteToWideChar(CP_UTF8, 0, path, -1, &wpath[0], n);

        Rel<IMFAttributes> attr;
        if (FAILED(MFCreateAttributes(&attr, 2))) { if (errOut) *errOut = "MFCreateAttributes failed"; return false; }
        // Lets MF insert a converter and scaler, which is what makes it possible to ask
        // for a format and size the file does not actually contain.
        attr->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
        attr->SetUINT32(MF_SOURCE_READER_DISABLE_DXVA, FALSE);

        if (FAILED(MFCreateSourceReaderFromURL(wpath.c_str(), attr, &reader)) || !reader) {
            // The ordinary outcome for ProRes or DNxHD: Windows has no decoder, so the
            // caller falls through to ffmpeg.
            if (errOut) *errOut = "Media Foundation cannot read this file";
            return false;
        }

        reader->SetStreamSelection((DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE);
        if (FAILED(reader->SetStreamSelection((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE))) {
            if (errOut) *errOut = "no video stream";
            return false;
        }

        // The source's own frame rate, read before the output type is overridden. This
        // is the authoritative one: the type set below is built here from scratch and
        // carries no MF_MT_FRAME_RATE, and nothing asks MF to convert the rate, so what
        // the stream declares is what arrives. Reading it back off the output type
        // instead is what labelled every Windows store 25 fps whatever the file was.
        {
            Rel<IMFMediaType> native;
            if (SUCCEEDED(reader->GetNativeMediaType(
                    (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &native)) && native) {
                UINT32 num = 0, den = 0;
                if (SUCCEEDED(MFGetAttributeRatio(native, MF_MT_FRAME_RATE, &num, &den))
                    && num && den)
                    nativeRate = (double)num / (double)den;
            }
        }

        // Ask for NV12 at the analysis size. Scaling during decode is what keeps the
        // cost down; if the scaler declines the size, ask again without one and let
        // resampleLuma deal with whatever arrives -- it already handles any size and
        // stride, because AVFoundation can refuse in the same way.
        {
            Rel<IMFMediaType> want;
            if (FAILED(MFCreateMediaType(&want))) { if (errOut) *errOut = "MFCreateMediaType failed"; return false; }
            want->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
            want->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
            MFSetAttributeSize(want, MF_MT_FRAME_SIZE, (UINT32)w, (UINT32)h);
            HRESULT hr = reader->SetCurrentMediaType(
                (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, want);
            if (FAILED(hr)) {
                Rel<IMFMediaType> plain;
                if (FAILED(MFCreateMediaType(&plain))) { if (errOut) *errOut = "MFCreateMediaType failed"; return false; }
                plain->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
                plain->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
                if (FAILED(reader->SetCurrentMediaType(
                        (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, plain))) {
                    if (errOut) *errOut = "Media Foundation will not decode this to NV12";
                    return false;
                }
            }
        }

        readActualSize();

        // Duration, in 100-nanosecond units, from the source rather than the stream.
        PROPVARIANT var;
        PropVariantInit(&var);
        if (SUCCEEDED(reader->GetPresentationAttribute(
                (DWORD)MF_SOURCE_READER_MEDIASOURCE, MF_PD_DURATION, &var))) {
            if (var.vt == VT_UI8) dur = (double)var.uhVal.QuadPart / 1.0e7;
        }
        PropVariantClear(&var);
        return true;
    }

    bool next(LumaFrame* out) override {
        unlock();
        for (;;) {
            DWORD      flags = 0;
            LONGLONG   ts    = 0;
            IMFSample* smp   = nullptr;
            HRESULT hr = reader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
                                            0, nullptr, &flags, &ts, &smp);
            if (FAILED(hr)) { err = "ReadSample failed"; if (smp) smp->Release(); return false; }
            if (flags & MF_SOURCE_READERF_ENDOFSTREAM) { if (smp) smp->Release(); return false; }
            // The decoder is entitled to change the frame size mid-stream; re-read it
            // rather than carrying on with stale dimensions.
            if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) readActualSize();
            if (!smp) continue;              // a gap in the stream, not the end of it

            sample = smp;
            if (!lockLuma(out)) { unlock(); continue; }
            out->ptsSec = (double)ts / 1.0e7;
            if (!std::isfinite(out->ptsSec) || out->ptsSec < 0.0) out->ptsSec = 0.0;
            return true;
        }
    }

    const char* error() const override { return err.c_str(); }
    double fps() const override { return rate; }
    double duration() const override { return dur; }

private:
    void readActualSize() {
        Rel<IMFMediaType> cur;
        if (FAILED(reader->GetCurrentMediaType(
                (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &cur))) return;
        UINT32 w = 0, h = 0;
        if (SUCCEEDED(MFGetAttributeSize(cur, MF_MT_FRAME_SIZE, &w, &h))) {
            width = (int)w; height = (int)h;
        }
        UINT32 num = 0, den = 0;
        if (SUCCEEDED(MFGetAttributeRatio(cur, MF_MT_FRAME_RATE, &num, &den)) && num && den)
            rate = (double)num / (double)den;
        // The stream wins over whatever the output type happens to carry, including
        // after a mid-stream type change.
        if (nativeRate > 0.0) rate = nativeRate;

        // Signed: a negative default stride means the rows are stored bottom-up.
        UINT32 ds = 0;
        defStride = SUCCEEDED(cur->GetUINT32(MF_MT_DEFAULT_STRIDE, &ds)) ? (int)(INT32)ds : 0;
    }

    // Maps the sample's luma plane. Prefers the 2D view, which reports the real stride;
    // a contiguous buffer has no stride of its own, so the rows are taken as packed.
    bool lockLuma(LumaFrame* out) {
        if (FAILED(sample->ConvertToContiguousBuffer(&buffer)) || !buffer) return false;

        IMF2DBuffer* two = nullptr;
        if (SUCCEEDED(buffer->QueryInterface(IID_PPV_ARGS(&two))) && two) {
            BYTE* scan = nullptr;
            LONG  pitch = 0;
            if (SUCCEEDED(two->Lock2D(&scan, &pitch)) && scan && pitch != 0) {
                twoD = two;
                out->y = scan;
                out->w = width;
                out->h = height;
                // Lock2D hands back the top row, so a negative pitch is the step
                // *down* the image. Taking its absolute value walked up out of the
                // buffer instead and hashed whatever lay before it.
                out->stride = (int)pitch;
                return true;
            }
            two->Release();
        }

        BYTE*  p = nullptr;
        DWORD  len = 0;
        if (FAILED(buffer->Lock(&p, nullptr, &len)) || !p) return false;
        // A contiguous buffer carries no stride of its own, so take the one the media
        // type declares. Assuming packed rows was wrong for any padded NV12 buffer, and
        // the old length check could not catch it: NV12 is w*h*3/2, so a luma plane
        // padded well past w*h still passed.
        int stride = defStride < 0 ? -defStride : defStride;
        if (stride < width) stride = width;
        if (len / (DWORD)stride < (DWORD)height) { buffer->Unlock(); return false; }
        locked = true;
        out->w = width;
        out->h = height;
        if (defStride < 0) {          // bottom-up: start at the last row and step back
            out->y = p + (ptrdiff_t)stride * (height - 1);
            out->stride = -stride;
        } else {
            out->y = p;
            out->stride = stride;
        }
        return true;
    }

    void unlock() {
        if (twoD)   { twoD->Unlock2D(); twoD->Release(); twoD = nullptr; }
        if (locked) { if (buffer) buffer->Unlock(); locked = false; }
        if (buffer) { buffer->Release(); buffer = nullptr; }
        if (sample) { sample->Release(); sample = nullptr; }
    }

    IMFSourceReader* reader = nullptr;
    IMFSample*       sample = nullptr;
    IMFMediaBuffer*  buffer = nullptr;
    IMF2DBuffer*     twoD   = nullptr;
    bool             locked = false;
    int              width = 0, height = 0;
    double           rate = 25.0;
    double           nativeRate = 0.0;   // the stream's own, authoritative
    int              defStride = 0;      // MF_MT_DEFAULT_STRIDE, signed
    double           dur  = 0.0;
    std::string      err;
};

} // namespace

FrameSource* frameSourceOpenMF(const char* path, int w, int h, std::string* err) {
    if (!path || !*path) { if (err) *err = "no path"; return nullptr; }
    MFFrameSource* s = new MFFrameSource();
    if (!s->open(path, w, h, err)) { delete s; return nullptr; }
    return s;
}

#endif
