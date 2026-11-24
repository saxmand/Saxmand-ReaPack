#pragma once

#include <cmath>
#include <cstdint>
#include <vector>

// The handful of signal-processing primitives the audio fingerprint needs, in plain C++
// so the same code runs on every platform.
//
// These replace vDSP. The fingerprint is unaffected by the swap, and that is worth
// spelling out rather than hoping: a bit of the hash is
//
//     (log E[m] - log E[m+1]) - (log E'[m] - log E'[m+1])  >  0
//
// a difference across frequency of a difference across time, taken on logs. Scale every
// magnitude by any constant k and each log picks up the same log(k), which cancels twice
// over. vDSP's packed real FFT returns bins scaled by 2, and packs DC and Nyquist into
// one complex slot; the bands only ever span 250 Hz to 6 kHz, so neither of those bins
// is read. A true-magnitude FFT therefore produces the same bits, and stores built on
// either platform remain readable by the other.

namespace dsp {

// Spelled out rather than taken from PI, which is a POSIX extension and is absent
// from both MSVC and mingw unless _USE_MATH_DEFINES is set before <cmath>. Relying on
// a macro that three toolchains disagree about is not worth the two lines it saves.
static const double PI = 3.14159265358979323846;


// Hann window, matching vDSP_hann_window(..., vDSP_HANN_DENORM): denormalised, so the
// endpoints are zero and the divisor is N-1 rather than N.
inline void hann(float* w, int n) {
    if (n <= 1) { if (n == 1) w[0] = 1.0f; return; }
    const double k = 2.0 * PI / (double)(n - 1);
    for (int i = 0; i < n; i++) w[i] = (float)(0.5 * (1.0 - std::cos(k * (double)i)));
}

// Largest absolute value, as vDSP_maxmgv.
inline float maxMagnitude(const float* v, int n) {
    float m = 0.0f;
    for (int i = 0; i < n; i++) { float a = std::fabs(v[i]); if (a > m) m = a; }
    return m;
}

// In-place iterative radix-2 complex FFT. Size must be a power of two.
//
// Iterative rather than recursive so there is no call overhead per butterfly, and the
// twiddles are recomputed per stage from a single sin/cos pair -- at 1024 points the
// trigonometry is a rounding error beside the memory traffic, and it keeps the whole
// thing self-contained with no table to allocate or free.
class FFT {
public:
    explicit FFT(int log2n) : m_log2n(log2n), m_n(1 << log2n) {
        m_rev.resize(m_n);
        for (int i = 0; i < m_n; i++) {
            int r = 0;
            for (int b = 0; b < log2n; b++) if (i & (1 << b)) r |= 1 << (log2n - 1 - b);
            m_rev[i] = r;
        }
    }

    int size() const { return m_n; }

    // Real input of size n -> squared magnitudes of bins 0..n/2-1.
    //
    // Squared, not absolute: the bands sum energy, and a sum of squares is what the
    // band energies are defined as, so taking a square root here only to square it
    // again downstream would be wasted work and lost precision.
    void realMagnitudesSquared(const float* in, float* magSq) {
        if ((int)m_re.size() != m_n) { m_re.resize(m_n); m_im.resize(m_n); }

        // Bit-reversed load; the imaginary half starts at zero because the input is real.
        for (int i = 0; i < m_n; i++) { m_re[i] = in[m_rev[i]]; m_im[i] = 0.0; }

        for (int len = 2; len <= m_n; len <<= 1) {
            const double ang = -2.0 * PI / (double)len;
            const double wr  = std::cos(ang), wi = std::sin(ang);
            for (int i = 0; i < m_n; i += len) {
                double cr = 1.0, ci = 0.0;
                const int half = len >> 1;
                for (int j = 0; j < half; j++) {
                    const int a = i + j, b = a + half;
                    const double xr = m_re[b] * cr - m_im[b] * ci;
                    const double xi = m_re[b] * ci + m_im[b] * cr;
                    m_re[b] = m_re[a] - xr;  m_im[b] = m_im[a] - xi;
                    m_re[a] += xr;           m_im[a] += xi;
                    const double nr = cr * wr - ci * wi;
                    ci = cr * wi + ci * wr;  cr = nr;
                }
            }
        }

        const int bins = m_n / 2;
        for (int k = 0; k < bins; k++)
            magSq[k] = (float)(m_re[k] * m_re[k] + m_im[k] * m_im[k]);
    }

private:
    int                 m_log2n;
    int                 m_n;
    std::vector<int>    m_rev;
    std::vector<double> m_re, m_im;
};

} // namespace dsp
