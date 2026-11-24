// audio_source, macOS: AVAssetReaderAudioMixOutput.
//
// Lifted out of audio_store, which is now platform-free. The buffering is here rather
// than in the caller because the reader hands back whatever block size it likes, while
// the fingerprint wants a fixed window -- so this presents a flat stream and lets the
// caller take it in whatever lengths suit.

#import <AVFoundation/AVFoundation.h>

#include <algorithm>
#include <deque>
#include <string>
#include <vector>

#include "audio_source.h"

namespace {

class MacAudioSource : public AudioSource {
public:
    ~MacAudioSource() override {
        if (reader && reader.status == AVAssetReaderStatusReading) [reader cancelReading];
        reader = nil;
        output = nil;
    }

    bool open(const char* path, double rate, std::string* errOut) {
        @autoreleasepool {
            NSURL*      url   = [NSURL fileURLWithPath:@(path)];
            AVURLAsset* asset = [AVURLAsset URLAssetWithURL:url options:nil];
            NSArray<AVAssetTrack*>* tracks = [asset tracksWithMediaType:AVMediaTypeAudio];
            if (tracks.count == 0) { if (errOut) *errOut = "no audio track"; return false; }

            dur = CMTimeGetSeconds(asset.duration);
            if (!(dur > 0.0)) dur = 0.0;

            NSError* err = nil;
            reader = [AVAssetReader assetReaderWithAsset:asset error:&err];
            if (!reader) {
                if (errOut) *errOut = err ? err.localizedDescription.UTF8String
                                          : "reader init failed";
                return false;
            }

            // Mono float at a fixed rate: AVFoundation does the downmix and resample, so
            // stores from different deliveries are directly comparable.
            NSDictionary* settings = @{
                AVFormatIDKey:               @(kAudioFormatLinearPCM),
                AVSampleRateKey:             @(rate),
                AVNumberOfChannelsKey:       @(1),
                AVLinearPCMBitDepthKey:      @(32),
                AVLinearPCMIsFloatKey:       @YES,
                AVLinearPCMIsBigEndianKey:   @NO,
                AVLinearPCMIsNonInterleaved: @NO,
            };
            output = [AVAssetReaderAudioMixOutput assetReaderAudioMixOutputWithAudioTracks:tracks
                                                                             audioSettings:settings];
            if (![reader canAddOutput:output]) {
                if (errOut) *errOut = "cannot add audio reader output";
                return false;
            }
            [reader addOutput:output];
            if (![reader startReading]) {
                if (errOut) *errOut = reader.error
                    ? reader.error.localizedDescription.UTF8String : "startReading failed";
                return false;
            }
            return true;
        }
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
    // One reader block into `held`. False at end of stream or on failure.
    bool pull() {
        @autoreleasepool {
            while (reader.status == AVAssetReaderStatusReading) {
                CMSampleBufferRef sb = [output copyNextSampleBuffer];
                if (!sb) break;
                CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
                if (bb) {
                    size_t len = 0;
                    char*  ptr = nullptr;
                    if (CMBlockBufferGetDataPointer(bb, 0, NULL, &len, &ptr) == kCMBlockBufferNoErr
                        && ptr && len >= sizeof(float)) {
                        const float* f = (const float*)ptr;
                        held.insert(held.end(), f, f + (len / sizeof(float)));
                        CFRelease(sb);
                        return true;
                    }
                }
                CFRelease(sb);
            }
            if (reader.status == AVAssetReaderStatusFailed) {
                err = reader.error ? reader.error.localizedDescription.UTF8String
                                   : "read failed";
            }
            return false;
        }
    }

    AVAssetReader*               reader = nil;
    AVAssetReaderAudioMixOutput* output = nil;
    std::vector<float>           held;
    std::string                  err;
    double                       dur = 0.0;
};

} // namespace

AudioSource* audioSourceOpen(const char* path, double rate, std::string* err) {
    if (!path || !*path) { if (err) *err = "no path"; return nullptr; }
    MacAudioSource* s = new MacAudioSource();
    if (!s->open(path, rate, err)) { delete s; return nullptr; }
    return s;
}
