#ifdef _WIN32

// audio_source, Windows: Media Foundation.
//
// Asks for mono 32-bit float at a fixed rate, which is the same request the macOS path
// makes of AVFoundation -- MF does the downmix and the resample, so two deliveries of
// the same material reduce to comparable fingerprints whatever they were encoded as.

#include "win_mf.h"

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>

#include <algorithm>
#include <string>
#include <vector>

namespace {

template <class T> struct Rel {
    T* p = nullptr;
    ~Rel() { if (p) p->Release(); }
    T** operator&() { return &p; }
    T*  operator->() const { return p; }
    operator T*() const { return p; }
};

class MFAudioSource : public AudioSource {
public:
    ~MFAudioSource() override { if (reader) reader->Release(); }

    bool open(const char* path, double rate, std::string* errOut) {
        if (!mfEnsureStarted()) { if (errOut) *errOut = "Media Foundation unavailable"; return false; }

        int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, nullptr, 0);
        std::wstring wpath(n > 0 ? n - 1 : 0, L'\0');
        if (n > 0) MultiByteToWideChar(CP_UTF8, 0, path, -1, &wpath[0], n);

        if (FAILED(MFCreateSourceReaderFromURL(wpath.c_str(), nullptr, &reader)) || !reader) {
            if (errOut) *errOut = "Media Foundation cannot read this file";
            return false;
        }
        reader->SetStreamSelection((DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE);
        if (FAILED(reader->SetStreamSelection((DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, TRUE))) {
            if (errOut) *errOut = "no audio track";
            return false;
        }

        Rel<IMFMediaType> want;
        if (FAILED(MFCreateMediaType(&want))) { if (errOut) *errOut = "MFCreateMediaType failed"; return false; }
        want->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        want->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_Float);
        want->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 1);
        want->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, (UINT32)(rate + 0.5));
        want->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 32);
        if (FAILED(reader->SetCurrentMediaType(
                (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, nullptr, want))) {
            if (errOut) *errOut = "Media Foundation will not decode this to mono float";
            return false;
        }

        PROPVARIANT var;
        PropVariantInit(&var);
        if (SUCCEEDED(reader->GetPresentationAttribute(
                (DWORD)MF_SOURCE_READER_MEDIASOURCE, MF_PD_DURATION, &var))) {
            if (var.vt == VT_UI8) dur = (double)var.uhVal.QuadPart / 1.0e7;
        }
        PropVariantClear(&var);
        return true;
    }

    int read(float* dst, int want) override {
        int got = 0;
        while (got < want) {
            if (held.empty() && !pull()) break;
            int take = std::min((int)held.size(), want - got);
            std::copy(held.begin(), held.begin() + take, dst + got);
            held.erase(held.begin(), held.begin() + take);
            got += take;
        }
        return got;
    }

    const char* error() const override { return err.c_str(); }
    double duration() const override { return dur; }

private:
    bool pull() {
        for (;;) {
            DWORD      flags = 0;
            LONGLONG   ts    = 0;
            IMFSample* smp   = nullptr;
            if (FAILED(reader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM,
                                          0, nullptr, &flags, &ts, &smp))) {
                err = "ReadSample failed";
                if (smp) smp->Release();
                return false;
            }
            if (flags & MF_SOURCE_READERF_ENDOFSTREAM) { if (smp) smp->Release(); return false; }
            if (!smp) continue;

            Rel<IMFMediaBuffer> buf;
            if (SUCCEEDED(smp->ConvertToContiguousBuffer(&buf)) && buf) {
                BYTE* p = nullptr;
                DWORD len = 0;
                if (SUCCEEDED(buf->Lock(&p, nullptr, &len)) && p && len >= sizeof(float)) {
                    const float* f = (const float*)p;
                    held.insert(held.end(), f, f + (len / sizeof(float)));
                    buf->Unlock();
                    smp->Release();
                    return true;
                }
            }
            smp->Release();
        }
    }

    IMFSourceReader*   reader = nullptr;
    std::vector<float> held;
    std::string        err;
    double             dur = 0.0;
};

} // namespace

AudioSource* audioSourceOpenMF(const char* path, double rate, std::string* err) {
    if (!path || !*path) { if (err) *err = "no path"; return nullptr; }
    MFAudioSource* s = new MFAudioSource();
    if (!s->open(path, rate, err)) { delete s; return nullptr; }
    return s;
}

#endif
