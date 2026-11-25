#pragma once
// Choosing which decoded frame answers a request for the picture at a given time.
//
// A seek lands on the nearest keyframe at or before the request and stops there, so the
// frames after it have to be walked. The one wanted is the frame on screen at that
// moment -- the last one whose timestamp has not passed it. Not the nearest frame: at
// 1.03 s on 25 fps material the picture showing is still the frame from 1.00 s, and
// AVFoundation with its tolerances pinned to zero answers the same way, which is what
// keeps the two platforms agreeing.
//
// eps absorbs timestamp jitter, so that a request landing on a frame's own timestamp
// accepts that frame rather than the one before it. It has to: a cut's time reaches us
// rounded to the millisecond, so a frame whose real timestamp is 1.0004 s is asked for
// as 1.000 s, and without the tolerance every cut thumbnail would come out one frame
// early -- systematically, on every file.
//
// The tolerance is symmetric, so a request falling within eps BEFORE a frame snaps
// forward to it: 1.0395 s answers with the 1.040 s frame rather than 1.000 s. That is
// the deliberate trade. It can only happen when a caller asks for a time that is not a
// frame time, i.e. free scrubbing, where a millisecond either way is invisible -- and
// the alternative misplaces every thumbnail in the program.
//
// It stays far smaller than a frame regardless: at half a frame the rule would become
// round-to-nearest, and 1.03 s would wrongly answer with 1.04 s.

#include <cstdint>

static const long long FRAME_PICK_EPS = 10000;   // 1 ms in 100-nanosecond units

enum class FramePick {
    Continue,   // this frame is a candidate, but a later one may be better
    Take,       // this frame is the answer; stop reading
    Overshot,   // gone past; the candidate already held is the answer
};

inline FramePick framePick(long long ts, long long target, bool haveCandidate,
                           long long eps = FRAME_PICK_EPS) {
    if (ts > target + eps)
        // Past the request. Normally the held frame is the answer; with nothing held
        // the seek must have landed after the request, so this frame is the best there
        // is -- returning nothing would leave a blank where a picture belongs.
        return haveCandidate ? FramePick::Overshot : FramePick::Take;
    if (ts + eps >= target)
        return FramePick::Take;      // this is the frame covering the request
    return FramePick::Continue;
}
