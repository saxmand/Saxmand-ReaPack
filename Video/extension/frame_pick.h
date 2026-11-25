#pragma once
// Choosing which decoded frame answers a request for the picture at a given time.
//
// A seek lands on the nearest keyframe at or before the request and stops there, so the
// frames after it have to be walked. The question is which one to stop on.
//
// NEAREST, not the frame whose interval contains the request. Almost every request is
// for a cut's own time, and a cut's time reaches us rounded to the millisecond out of
// the fingerprint store while the decoder reports its own, so the two disagree slightly
// and in no fixed direction. Nearest absorbs that: a frame 40 ms away never wins over
// the one a millisecond away. Containment, which is what the first version of this did,
// is right only while the two clocks agree to within the tolerance it allows -- and
// when they did not, every thumbnail came out one frame early, which is precisely what
// Windows showed.
//
// It is also the better answer for free scrubbing: dropping the playhead between two
// frames shows whichever is closer, rather than always the one behind.

#include <cstdint>

enum class FramePick {
    Continue,   // short of the request; this frame becomes the candidate
    Take,       // this frame is the answer; stop reading
    Overshot,   // gone past, and the candidate already held is closer
};

// ts and target in the decoder's own units; prevTs is the candidate's timestamp and is
// read only when havePrev. A tie goes to the later frame: at a cut that is the first
// frame of the new shot rather than the last of the old one, which is the side to err
// on for a thumbnail meant to show what the cut cuts to.
inline FramePick framePick(long long ts, long long target,
                           long long prevTs, bool havePrev) {
    if (ts < target) return FramePick::Continue;
    if (!havePrev)   return FramePick::Take;
    return (ts - target) <= (target - prevTs) ? FramePick::Take : FramePick::Overshot;
}
