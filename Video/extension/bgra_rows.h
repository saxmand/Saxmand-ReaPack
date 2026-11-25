#pragma once
// Resolving a decoded BGRA frame's layout to one representation.
//
// A decoded frame can differ from the picture in it three ways at once, and getting any
// of them wrong skews or shifts every row:
//
//   padded     the step from one row to the next exceeds the frame width
//   bottom-up  the rows are stored last-first, so the first row in memory is the
//              image's bottom row
//   cropped    a codec pads the coded size up to whole macroblocks, so a 1440x1080
//              frame arrives as 1440x1088 and only part of it is the picture
//
// Rather than carry a flag per case, everything resolves to a pointer at image row 0 of
// the picture and a *signed* step to the row below it. A bottom-up frame is then just a
// negative step, and a consumer walks rows the same way whatever arrived.

#include <cstddef>
#include <cstdint>

struct BgraRows {
    const uint8_t* row0 = nullptr;   // image row 0 of the picture
    std::ptrdiff_t step = 0;         // signed bytes to the row below; may be negative
};

// A 2D-locked buffer: IMF2DBuffer::Lock2D hands back the top row already, and its pitch
// is signed, so the pitch *is* the step. Taking its absolute value and re-applying a
// bottom-up flag on top double-counts, and walks off the end of the buffer.
inline BgraRows bgraFrom2D(const uint8_t* scanline0, std::ptrdiff_t pitch) {
    return { scanline0, pitch };
}

// A contiguous buffer, which carries no stride of its own: the coded width gives it.
// Using the picture width here would skew a padded frame progressively.
inline BgraRows bgraFromContiguous(const uint8_t* bufStart, int codedWidth,
                                   int codedHeight, bool bottomUp) {
    const std::ptrdiff_t rowBytes = (std::ptrdiff_t)codedWidth * 4;
    if (bottomUp)
        return { bufStart + rowBytes * (codedHeight - 1), -rowBytes };
    return { bufStart, rowBytes };
}

// Step into the picture, past any coded padding. cropY times a negative step walks the
// right way for a bottom-up frame too, since row0 is image row 0 either way.
inline BgraRows bgraCrop(BgraRows r, int cropX, int cropY) {
    return { r.row0 + (std::ptrdiff_t)cropY * r.step + (std::ptrdiff_t)cropX * 4, r.step };
}
