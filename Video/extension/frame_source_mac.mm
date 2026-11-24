// frame_source, macOS: AVAssetReader.
//
// Lifted out of frame_store, which is now platform-free. The one thing worth keeping in
// mind here is the scaled output request: VideoToolbox hands back luma already reduced
// to the analysis size, which is why a whole-file fingerprint pass costs a tenth of the
// CPU that decoding at full size and shrinking in software would.

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>

#include <cmath>
#include <mutex>
#include <string>

#include "frame_source.h"

namespace {

class MacFrameSource : public FrameSource {
public:
    ~MacFrameSource() override {
        if (locked) CVPixelBufferUnlockBaseAddress(locked, kCVPixelBufferLock_ReadOnly);
        if (sample) CFRelease(sample);
        if (reader && reader.status == AVAssetReaderStatusReading) [reader cancelReading];
        reader = nil;
        output = nil;
    }

    bool open(const char* path, int w, int h, std::string* errOut) {
        @autoreleasepool {
            NSURL*        url   = [NSURL fileURLWithPath:@(path)];
            AVURLAsset*   asset = [AVURLAsset URLAssetWithURL:url options:nil];
            AVAssetTrack* track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
            if (!track) { if (errOut) *errOut = "no video track"; return false; }

            dur = CMTimeGetSeconds(asset.duration);
            if (!(dur > 0.0)) dur = 0.0;
            rate = track.nominalFrameRate;
            if (!(rate > 0.0)) rate = 25.0;

            NSError* err = nil;
            reader = [AVAssetReader assetReaderWithAsset:asset error:&err];
            if (!reader) {
                if (errOut) *errOut = err ? err.localizedDescription.UTF8String
                                          : "reader init failed";
                return false;
            }

            // Ask VideoToolbox to hand back luma already scaled down -- far cheaper than
            // pulling full-res frames across and shrinking them ourselves. Some codecs
            // refuse the scale, so fall back to native size; the caller resamples from
            // whatever width and height actually arrive.
            NSDictionary* scaled = @{
                (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
                (id)kCVPixelBufferWidthKey:           @(w),
                (id)kCVPixelBufferHeightKey:          @(h),
            };
            NSDictionary* native = @{
                (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            };

            output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                               outputSettings:scaled];
            output.alwaysCopiesSampleData = NO;
            if (![reader canAddOutput:output]) {
                output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                   outputSettings:native];
                output.alwaysCopiesSampleData = NO;
                if (![reader canAddOutput:output]) {
                    if (errOut) *errOut = "cannot add reader output";
                    return false;
                }
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

    bool next(LumaFrame* out) override {
        // The previous frame's buffer stays mapped until now, which is what lets next()
        // hand over the decoder's own memory instead of copying it.
        release();

        while (reader.status == AVAssetReaderStatusReading) {
            CMSampleBufferRef sb = [output copyNextSampleBuffer];
            if (!sb) break;
            CVImageBufferRef pb = CMSampleBufferGetImageBuffer(sb);
            if (!pb) { CFRelease(sb); continue; }

            CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
            const uint8_t* y = nullptr;
            int w = 0, h = 0, stride = 0;
            if (CVPixelBufferIsPlanar(pb)) {
                y      = (const uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pb, 0);
                w      = (int)CVPixelBufferGetWidthOfPlane(pb, 0);
                h      = (int)CVPixelBufferGetHeightOfPlane(pb, 0);
                stride = (int)CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
            } else {
                y      = (const uint8_t*)CVPixelBufferGetBaseAddress(pb);
                w      = (int)CVPixelBufferGetWidth(pb);
                h      = (int)CVPixelBufferGetHeight(pb);
                stride = (int)CVPixelBufferGetBytesPerRow(pb);
            }
            if (!y || w <= 0 || h <= 0) {
                CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
                CFRelease(sb);
                continue;
            }

            double t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb));
            if (!std::isfinite(t) || t < 0.0) t = 0.0;

            sample = sb;
            locked = pb;
            out->y = y; out->w = w; out->h = h; out->stride = stride; out->ptsSec = t;
            return true;
        }

        if (reader.status == AVAssetReaderStatusFailed) {
            err = reader.error ? reader.error.localizedDescription.UTF8String : "read failed";
        }
        return false;
    }

    const char* error() const override { return err.c_str(); }
    double fps() const override { return rate; }
    double duration() const override { return dur; }

private:
    void release() {
        if (locked) {
            CVPixelBufferUnlockBaseAddress(locked, kCVPixelBufferLock_ReadOnly);
            locked = nullptr;
        }
        if (sample) { CFRelease(sample); sample = nullptr; }
    }

    AVAssetReader*            reader = nil;
    AVAssetReaderTrackOutput* output = nil;
    CMSampleBufferRef         sample = nullptr;
    CVImageBufferRef          locked = nullptr;
    std::string               err;
    double                    rate = 25.0;
    double                    dur  = 0.0;
};

} // namespace

FrameSource* frameSourceOpen(const char* path, int w, int h, std::string* err) {
    if (!path || !*path) { if (err) *err = "no path"; return nullptr; }
    MacFrameSource* s = new MacFrameSource();
    if (!s->open(path, w, h, err)) { delete s; return nullptr; }
    return s;
}

// macOS decodes in-process, so there is no ffmpeg binary to point at. Kept so the
// exported API is the same shape on both platforms and the Lua side needs no branch.
static std::mutex  g_pathMu;
static std::string g_ffmpegPath;

void frameSourceSetFFmpegPath(const char* path) {
    std::lock_guard<std::mutex> lk(g_pathMu);
    g_ffmpegPath = path ? path : "";
}

std::string frameSourceFFmpegPath() {
    std::lock_guard<std::mutex> lk(g_pathMu);
    return g_ffmpegPath;
}
