#!/usr/bin/env python3
"""Design the 2x polyphase halfband interpolator coefficients for tx_halfband_interp2.v.

The TX path upsamples the 61.44 MSa/s/ch baseband I/Q to 122.88 MSa/s/ch before
the AD9117 DDR bus, pushing the spectral image from ~Fs1-f out to ~2*Fs1-f so the
analog reconstruction filter has an easy job.  A halfband filter is the efficient
choice for 2x: half its taps are zero, and one polyphase branch is a pure delay.

19-tap Type-I halfband (Kaiser beta=7): center=0.5, even-offset taps forced to 0.
Image rejection (signal band edge fu of the 2x Nyquist):
  fu<=0.10 -> ~-120 dB, fu<=0.15 -> ~-40 dB, fu<=0.20 -> ~-17 dB (near input Nyquist,
  fundamentally limited by the halfband transition at 0.25).

Polyphase use in tx_halfband_interp2.v:
  y[2k]   = x[k-4]                     (pure delay; even-offset taps are 0)
  y[2k+1] = sum_j cp[j]*(x[k-j]+x[k-9+j])  (5 symmetric odd-tap pairs)

Coeffs are Q15.  Run:  python tools/scripts/dac/gen_halfband_interp.py
"""
import numpy as np

NTAPS = 19
BETA = 7.0
Q15 = 32768


def halfband():
    M = (NTAPS - 1) // 2
    n = np.arange(NTAPS) - M
    h = 0.5 * np.sinc(n / 2.0) * np.kaiser(NTAPS, BETA)
    for i, nn in enumerate(n):
        if nn != 0 and nn % 2 == 0:
            h[i] = 0.0
    h[M] = 0.5
    return n, h


def main():
    n, h = halfband()
    M = (NTAPS - 1) // 2
    # The odd polyphase branch taps are the nonzero, non-center coeffs.  By
    # symmetry they form pairs; the 5 unique pair values (nearest->farthest):
    pair_idx = [M - 1, M - 3, M - 5, M - 7, M - 9]   # 8,6,4,2,0
    # Keep the *prototype* tap values (center 0.5, sum 1.0): this is the actual
    # filter shape that sets image rejection.  The 2x interpolation 6 dB gain is
    # restored in RTL with a >>14 (== >>15 then <<1), NOT by inflating coeffs.
    q = [int(round(h[i] * Q15)) for i in pair_idx]
    # Force the odd-pair sum to exactly Q15/4 = 8192 so the implemented DC gain
    # (2*sum, with the >>14 restore) is exactly unity.  Push the tiny residual
    # into the dominant tap CP0 (a few LSB; negligible shape change).
    q[0] += (Q15 // 4) - sum(q)
    print("// 19-tap halfband 2x interpolator, prototype Q15 (tx_halfband_interp2.v)")
    print("// odd-pair sum = %d (== Q15/4, so 2*sum>>14 = unity DC)" % sum(q))
    print("// odd branch: y_odd = ( SUM cp[j]*(x[k-j]+x[k-(2M-... )]) ) >>> 14  (>>15 then x2 gain)")
    print("// even branch: y_even = x[k-5] (center tap x2 = unity; del tap xr5 keeps phases aligned)")
    names = ["CP0", "CP1", "CP2", "CP3", "CP4"]
    for nm, v in zip(names, q):
        print("  localparam signed [15:0] %s = %s16'sd%d;" % (
            nm, "-" if v < 0 else " ", abs(v)))

    # Verify quantized image rejection on the prototype (center 0.5).
    qh = np.zeros(NTAPS)
    qh[M] = round(0.5 * Q15) / Q15
    for j, idx in enumerate(pair_idx):
        qh[idx] = q[j] / Q15
        qh[NTAPS - 1 - idx] = q[j] / Q15
    W = np.linspace(0, 0.5, 4001)
    A = np.array([np.sum(qh * np.cos(2 * np.pi * f * (np.arange(NTAPS) - M))) for f in W])
    # x2 gain restoration -> passband ~0 dB
    Adb = 20 * np.log10(np.abs(2 * A) + 1e-12)
    print("//")
    for fu in (0.10, 0.15, 0.20):
        img = 0.5 - fu
        a = Adb[np.argmin(np.abs(W - img))]
        print("//   signal fu<=%.2f -> image @%.2f atten %.0f dB" % (fu, img, a))
    pb = W <= 0.15
    print("//   passband (fu<=0.15) gain %.3f .. %.3f dB" % (Adb[pb].min(), Adb[pb].max()))


if __name__ == "__main__":
    main()
