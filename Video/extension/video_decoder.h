#pragma once

#include <string>

// One open video, able to hand back a single frame at an arbitrary moment.
//
// This is the random-access counterpart of FrameSource. The two exist separately
// because they are asked for completely different things: FrameSource reads a file once
// from end to end as fast as it can, while this is asked for whatever the playhead is
// sitting on right now, in no order at all. A decoder optimised for one is wrong for
// the other.
//
// Frames come back as paths, not pixels, because that is what ReaImGui takes and
// because REAPER cannot carry binary from an extension into Lua at all -- see
// frame_cache.h.
class VideoDecoder {
public:
    virtual ~VideoDecoder() {}

    virtual double duration() const = 0;

    // A cached JPEG for this moment, decoded if it is not already there. Empty string
    // on failure. The returned path is owned by the cache and may be evicted later, so
    // callers read it now rather than keeping it.
    virtual std::string getFrame(double timeSec, int maxW, int maxH) = 0;

    // One frame written to exactly this path, JPEG or PNG by its extension. Used for
    // the thumbnails that go into the session, which have to live where the caller says
    // rather than in the cache.
    virtual bool extractTo(double timeSec, int maxW, int maxH, const char* outPath) = 0;
};

// nullptr if the file cannot be opened or has no video.
VideoDecoder* videoDecoderOpen(const char* path, std::string* err);
