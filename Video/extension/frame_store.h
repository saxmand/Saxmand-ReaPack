#pragma once

#include <cstdint>
#include <string>
#include <vector>

// Framestore on-disk format. See frame_store.mm for the rationale.
//
//   FSHeader
//   uint64 dhash[frameCount]      match signature  (9x8 gradient hash)
//   uint32 ptsMs[frameCount]      presentation time, for VFR-safe idx -> time
//   uint16 peak [frameCount]      if FS_FLAG_PEAKS: level per hop, for the waveform
//   uint8  grid [frameCount*256]  if grid == FS_GRID: diff signature (16x16 luma)
//
// The two optional sections are mutually exclusive in practice — peaks only ever
// appear in an audio store and grids only in a video one — but the order above is
// what the reader assumes, so keep it if that ever stops being true.

static const int  FS_GRID    = 16;
static const int  FS_GRID_SZ = FS_GRID * FS_GRID;
static const char FS_MAGIC[8] = { 'V','P','F','S','0','0','0','1' };

// An audio store is the same file format with audio hops in place of video frames:
// one 64-bit hash each, no grid, and `fps` carrying hops per second. Keeping the two
// identical is deliberate — the matcher then works on sound with no changes at all,
// because everything it does reduces to Hamming distance between 64-bit hashes.
static const uint32_t FS_FLAG_AUDIO = 1u;

// Peak level per hop, as uint16 full scale. Only useful for drawing: the hash says
// nothing about how loud anything is, since all of its level information is
// deliberately differenced away. 2 bytes per 10 ms is 720 KB per hour, which is
// nothing beside the hashes, and it means a waveform costs no second decode pass.
static const uint32_t FS_FLAG_PEAKS = 2u;

// Which fingerprint chain a VIDEO store was built with, carried in the header's
// `reserved` field. Bumping it makes older stores read as stale and rebuild, which is
// necessary whenever the pixels behind a hash change: a store from a different chain is
// not wrong in itself, it simply cannot be compared with one from this chain. Audio
// stores do not use it -- their fingerprints are untouched by video-side changes.
//   1  decode at native size and downscale in our own code, identically on every
//      platform. Before this, each platform let its own decoder scale, which put 6.7
//      bits of mean Hamming between the same file analysed on macOS and on Windows.
static const uint32_t FS_VIDEO_CHAIN = 1u;

#pragma pack(push, 1)
struct FSHeader {
    char     magic[8];
    uint32_t frameCount;
    uint32_t grid;
    double   fps;
    double   duration;
    int64_t  srcSize;
    int64_t  srcMtime;
    uint32_t flags;
    uint32_t reserved;    // video stores: FS_VIDEO_CHAIN
};
#pragma pack(pop)

struct FrameStore {
    FSHeader              h{};
    std::vector<uint64_t> dhash;
    std::vector<uint32_t> ptsMs;
    std::vector<uint8_t>  grid;   // empty unless loaded with withGrid
    std::vector<uint16_t> peak;   // empty unless the store carries FS_FLAG_PEAKS
    int frames() const { return (int)dhash.size(); }
};

// Reads just the header. False if missing, truncated, wrong magic or wrong grid size.
bool fsReadHeader(const std::string& path, FSHeader* out);

// Loads a store. The 16x16 grids are ~32x the size of the hashes, so matching skips
// them (withGrid=false) and only diffing pays for them.
bool fsLoad(const std::string& path, FrameStore* out, bool withGrid);
