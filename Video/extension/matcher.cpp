// matcher — works out which parts of a new cut came from where in the old cut.
//
// Not an N x M similarity matrix.  Comparing every shot against every shot is
// quadratic and still only answers the question at shot granularity.  This is
// seed-and-extend, the approach sequence aligners use:
//
//   1. Index every frame of A by four 16-bit slices of its hash.  Two hashes within
//      Hamming distance 3 must agree exactly on at least one slice (pigeonhole), so
//      the index gives complete recall at d<=3 and good recall well past it, without
//      ever scanning A linearly.
//
//   2. Vote on diagonals.  A frame pair (i,j) is evidence for the offset d = i-j.
//      A real matched stretch puts many votes on one d; coincidental frame
//      similarity scatters across many.  Cheap, and robust to isolated bad frames.
//
//   3. Extend the winning diagonals.  Walk B along each one and take the maximal
//      stretches where the hashes keep agreeing, tolerating brief dropouts so a
//      single compression-damaged frame doesn't sever a run.
//
//   4. Chain the survivors.  Runs can overlap and contradict each other, so pick the
//      non-overlapping subset covering the most of B — weighted interval scheduling.
//      Nothing here requires the chosen runs to be in ascending order of A, which is
//      what lets a relocated block survive as a run with its own diagonal.
//
// Everything the user sees — inserted, removed, trimmed, moved — falls out of the
// gaps between chained runs, and that classification happens in Lua.
//
// Static content is the failure mode to know about: a held frame or a title card
// gives hundreds of frames the same hash, so those hashes carry no positional
// information.  Posting lists longer than MAX_POSTINGS are dropped as stop-words,
// and the surrounding runs are what pin such a stretch down.

#include "vp_api.h"
#include "frame_store.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

static const int    GAP_TOL      = 3;    // consecutive mismatches tolerated inside a run
static const size_t MAX_POSTINGS = 400;  // above this a hash is uninformative
static const int    MERGE_GAP    = 30;   // frames a same-diagonal merge may bridge

static inline int ham(uint64_t a, uint64_t b) { return __builtin_popcountll(a ^ b); }

// band 0..3 of the hash, tagged with the band number so one map holds all four
static inline uint32_t bandKey(uint64_t h, int b) {
    return (uint32_t)((h >> (b * 16)) & 0xFFFFu) | ((uint32_t)b << 16);
}

struct Run {
    int    aStart, bStart, len;
    double meanHam;
};

// Grows runs outward from the frames that actually voted for this diagonal.
//
// Two thresholds, not one. A run may only *begin* on a frame that matches tightly,
// but once underway it continues on a far looser test. Using a single threshold for
// both forces an unhappy choice: tight enough to refuse coincidental matches also
// severs real runs wherever a dissolve, grain or compression damage pushes a few
// frames over the line, and the same stretch then comes back as several fragments at
// slightly different offsets. Seeding tight and extending loose is how sequence
// aligners avoid that, and it keeps unchanged material in one piece.
//
// Working from the seeds rather than sweeping all of B is what makes it affordable to
// consider every candidate diagonal. Sweeping cost O(frames) per diagonal, which had
// to be paid for with a cap on how many diagonals were tried; that cap kept only the
// highest-voting ones, so a short but perfect match — few votes by definition — was
// discarded before it was ever examined. Cost here is proportional to what the runs
// actually cover, so nothing needs to be thrown away up front.
static void runsFromSeeds(const FrameStore& A, const FrameStore& B, int d,
                          const std::vector<int>& seeds,
                          int seedThresh, int extendThresh, int minRun,
                          std::vector<Run>& out) {
    const int nA = A.frames(), nB = B.frames();
    const int jLo = std::max(0, -d);
    const int jHi = std::min(nB, nA - d);
    if (jHi - jLo < minRun) return;

    auto dist = [&](int j) { return ham(A.dhash[j + d], B.dhash[j]); };

    // Walk one direction from the seed until the mismatches stop being brief enough to
    // ride through. Returns the furthest frame still part of the run.
    auto walk = [&](int from, int step, int limit) {
        int last = from, gap = 0;
        for (int j = from + step; (step > 0 ? j < limit : j >= limit); j += step) {
            if (dist(j) <= extendThresh) { last = j; gap = 0; }
            else if (++gap > GAP_TOL) break;
        }
        return last;
    };

    int covered = jLo - 1;   // furthest frame already absorbed into a run here
    for (int s : seeds) {
        if (s <= covered || s < jLo || s >= jHi) continue;
        if (dist(s) > seedThresh) continue;

        int lo = walk(s, -1, jLo);
        int hi = walk(s, +1, jHi);
        if (lo <= covered) lo = covered + 1;

        if (hi - lo + 1 >= minRun) {
            long long sum = 0;
            int n = 0;
            for (int j = lo; j <= hi; j++) {
                int h = dist(j);
                if (h <= extendThresh) { sum += h; n++; }
            }
            out.push_back({ lo + d, lo, hi - lo + 1, n ? (double)sum / n : 0.0 });
        }
        if (hi > covered) covered = hi;
    }
}

// Weighted interval scheduling over B. Weight is run length, plus a modest bonus for
// match tightness so the cleaner of two competing runs wins, minus a fixed per-run
// charge.
//
// That charge matters more than it looks. Periodic or repetitive footage lets the same
// stretch of B be explained either by one long run or by several shorter ones at
// different offsets, covering exactly as many frames either way. Length alone ties, and
// the tie breaks arbitrarily — which shows up as a single unchanged shot reported as two
// relocated fragments. Editors cut in contiguous blocks, so charging per run makes the
// simpler explanation win. Kept below minRun so a legitimately short match still scores
// above zero.
static std::vector<Run> chainRuns(std::vector<Run>& runs, int hamThresh, int minRun) {
    const int R = (int)runs.size();
    if (R == 0) return {};

    std::sort(runs.begin(), runs.end(), [](const Run& a, const Run& b) {
        return a.bStart + a.len < b.bStart + b.len;
    });

    const double runPenalty = minRun * 0.5;
    auto weight = [&](const Run& r) {
        double tight = 1.0 - r.meanHam / (double)(hamThresh + 1);
        return r.len * (1.0 + 0.25 * tight) - runPenalty;
    };

    std::vector<int>    prev(R, -1);
    std::vector<double> best(R + 1, 0.0);

    for (int i = 0; i < R; i++) {
        // rightmost run finishing at or before this one starts
        int lo = 0, hi = i, p = -1;
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            if (runs[mid].bStart + runs[mid].len <= runs[i].bStart) { p = mid; lo = mid + 1; }
            else hi = mid;
        }
        prev[i] = p;
        double withI = weight(runs[i]) + (p >= 0 ? best[p + 1] : 0.0);
        best[i + 1]  = std::max(best[i], withI);
    }

    std::vector<Run> chosen;
    for (int i = R - 1; i >= 0; ) {
        double withI = weight(runs[i]) + (prev[i] >= 0 ? best[prev[i] + 1] : 0.0);
        if (withI >= best[i]) { chosen.push_back(runs[i]); i = prev[i]; }
        else i--;
    }
    std::reverse(chosen.begin(), chosen.end());

    // Stitch back together anything that is contiguous on the same diagonal — a run
    // severed by a dropout longer than GAP_TOL, or two runs the DP happened to pick
    // end to end. One unbroken stretch is the honest description.
    std::vector<Run> merged;
    for (const Run& r : chosen) {
        if (!merged.empty()) {
            Run& m = merged.back();
            int gap = r.bStart - (m.bStart + m.len);
            if (m.aStart - m.bStart == r.aStart - r.bStart && gap >= 0 && gap <= MERGE_GAP) {
                double n = (double)m.len + r.len;
                m.meanHam = (m.meanHam * m.len + r.meanHam * r.len) / n;
                m.len     = r.bStart + r.len - m.bStart;
                continue;
            }
        }
        merged.push_back(r);
    }
    return merged;
}

// Result blob, parsed by Lua:
//   F <framesA> <framesB> <fpsA> <fpsB> <runCount>
//   R <aStart> <bStart> <len> <meanHam>
// Runs are ascending in B and never overlap in B. Ordering in A is free, which is
// how a moved block is represented.
static const char* VP_Match(const char* storeA, const char* storeB,
                            int hamThresh, int minRun) {
    static std::string out;
    out.clear();

    if (!storeA || !storeB) { out = "E bad arguments"; return out.c_str(); }
    if (hamThresh < 1)  hamThresh = 4;
    if (hamThresh > 32) hamThresh = 32;
    if (minRun < 1)     minRun = 12;

    // hamThresh is the seeding bar: how close two frames must be before a match is
    // allowed to start there. Extension rides much looser so a run survives dissolves
    // and compression damage rather than shattering into fragments.
    // Capped: past roughly a quarter of the 64 bits, "still matching" stops meaning
    // anything and a run will happily ride straight through unrelated material.
    const int seedThresh   = hamThresh;
    const int extendThresh = std::min(16, hamThresh * 2 + 4);

    FrameStore A, B;
    if (!fsLoad(storeA, &A, false)) { out = "E cannot load store A"; return out.c_str(); }
    if (!fsLoad(storeB, &B, false)) { out = "E cannot load store B"; return out.c_str(); }
    if (A.frames() == 0 || B.frames() == 0) { out = "E empty store"; return out.c_str(); }

    // 1. band index over A
    std::unordered_map<uint32_t, std::vector<int>> idx;
    idx.reserve(A.frames() * 4);
    for (int i = 0; i < A.frames(); i++)
        for (int b = 0; b < 4; b++)
            idx[bandKey(A.dhash[i], b)].push_back(i);
    for (auto& kv : idx)
        if (kv.second.size() > MAX_POSTINGS) kv.second.clear();   // stop-word

    // 2. diagonal voting. Sampling B at this stride still lands at least twice inside
    //    any run long enough to be reported, at a fraction of the comparisons. The
    //    voting frames are kept, not just counted, since they become the seeds that
    //    extension grows from.
    const int stride   = std::max(1, minRun / 2);
    const int minVotes = 2;

    std::unordered_map<int, std::vector<int>> seedsByDiag;
    std::vector<int> cand;
    for (int j = 0; j < B.frames(); j += stride) {
        cand.clear();
        for (int b = 0; b < 4; b++) {
            auto it = idx.find(bandKey(B.dhash[j], b));
            if (it == idx.end()) continue;
            for (int i : it->second)
                if (ham(A.dhash[i], B.dhash[j]) <= seedThresh) cand.push_back(i);
        }
        // the four bands overlap, so the same frame can arrive more than once
        std::sort(cand.begin(), cand.end());
        cand.erase(std::unique(cand.begin(), cand.end()), cand.end());
        for (int i : cand) seedsByDiag[i - j].push_back(j);
    }

    // 3. grow runs from the seeds on every diagonal that drew enough votes. Seeds
    //    arrive in ascending order of j because the loop above walks B forwards.
    std::vector<Run> runs;
    for (auto& kv : seedsByDiag) {
        if ((int)kv.second.size() < minVotes) continue;
        runsFromSeeds(A, B, kv.first, kv.second, seedThresh, extendThresh, minRun, runs);
    }

    // 4. chain
    std::vector<Run> chosen = chainRuns(runs, extendThresh, minRun);

    char line[160];
    snprintf(line, sizeof(line), "F %d %d %.6f %.6f %d\n",
             A.frames(), B.frames(), A.h.fps, B.h.fps, (int)chosen.size());
    out = line;
    for (const Run& r : chosen) {
        snprintf(line, sizeof(line), "R %d %d %d %.2f\n",
                 r.aStart, r.bStart, r.len, r.meanHam);
        out += line;
    }
    return out.c_str();
}

static void* VA_VP_Match(void** a, int n) {
    if (n < 2) return (void*)"E bad arguments";
    int hamThresh = (n >= 3) ? (int)(intptr_t)a[2] : 4;
    int minRun    = (n >= 4) ? (int)(intptr_t)a[3] : 12;
    return (void*)VP_Match((const char*)a[0], (const char*)a[1], hamThresh, minRun);
}

const VPFunc g_matcherFuncs[] = {
    { "VP_Match", (void*)VP_Match, (void*)VA_VP_Match,
      "const char*", "const char*,const char*,int,int", "storeA,storeB,hamThresh,minRun",
      "Match two framestores. Returns lines: 'F framesA framesB fpsA fpsB runCount' then "
      "'R aStart bStart len meanHam' per matched run (ascending, non-overlapping in B). "
      "hamThresh is the seeding bar, default 4 (extension rides looser); minRun default "
      "12 frames. meanHam indicates confidence: real matches sit near 0, around 6+ is "
      "doubtful. 'E msg' on error." },
};
const int g_matcherFuncCount = (int)(sizeof(g_matcherFuncs) / sizeof(g_matcherFuncs[0]));
