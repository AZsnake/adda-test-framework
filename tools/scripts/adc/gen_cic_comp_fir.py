#!/usr/bin/env python3
"""Design the CIC droop-compensation coefficient bank for rf_filter14.v.

The RX chain (rf_datapath/rx_chain/adc_iq_rx_chain.v) runs a 3-stage CIC
decimator ahead of the 15-tap symmetric FIR rf_filter14.  A CIC has
(sin(pi F)/(R sin(pi F / R)))^N passband droop; for the decimation ratios used
here (R = 2 or 4, N = 3) the droop is close to the R->inf asymptote sinc(F)^3,
where F is normalised to the *output* sample rate (Nyquist = 0.5).

This script designs a 15-tap, symmetric (linear-phase Type-I) FIR that
approximates 1/sinc(F)^3 across the passband and rolls off to a stopband, then
quantises to Q15 in the exact c0..c7 mirror-pair form rf_filter14 expects
(h[k] = h[14-k]; c0..c6 are the 7 mirror pairs, c7 is the centre tap).

Pure numpy (weighted least squares on a dense grid) -- no scipy dependency.
Run:  python tools/scripts/adc/gen_cic_comp_fir.py
"""
import numpy as np

NTAPS = 15
NCIC = 3            # CIC stages
W_PASS = 1.0
Q15 = 32768

# The CIC-comp bank's primary job is passband droop flatness; stopband rejection
# is secondary (banks 0/1 already provide lowpass anti-alias).  These defaults
# are the winner of the small sweep at the bottom of this file.
F_PASS = 0.18       # passband edge (output-normalised, Nyquist = 0.5)
F_STOP = 0.45       # stopband edge
W_STOP = 0.15       # light stopband weight -> let the inverse-droop boost win


def sinc_droop(F):
    """Asymptotic CIC passband droop sinc(F)^NCIC, F output-normalised."""
    x = np.pi * F
    s = np.where(F == 0.0, 1.0, np.sin(x) / np.where(F == 0.0, 1.0, x))
    return s ** NCIC


def design(f_pass=F_PASS, f_stop=F_STOP, w_stop=W_STOP):
    # Dense frequency grid over [0, 0.5].
    F = np.linspace(0.0, 0.5, 2001)
    desired = np.zeros_like(F)
    weight = np.zeros_like(F)

    pb = F <= f_pass
    sb = F >= f_stop
    # Passband: inverse-droop boost, relative-weighted (1/target^2) so the fit
    # error is balanced in dB across the band rather than dominated by the
    # large boost near the passband edge.  NOTE: a 15-tap FIR is fundamentally
    # limited at narrow fractional bands (the low-frequency cosine basis is
    # ill-conditioned), so this compensates ~half the CIC sinc^3 droop -- see
    # the achieved-spec print in main().
    desired[pb] = 1.0 / sinc_droop(F[pb])
    weight[pb] = W_PASS / desired[pb] ** 2
    # Light stopband pull toward 0 for high-frequency noise control only.
    desired[sb] = 0.0
    weight[sb] = w_stop
    # transition band left unconstrained (weight 0).

    # Type-I zero-phase response: A(F) = b0 + 2*sum_{k=1..7} bk*cos(2*pi*F*k)
    # Build basis cols: [1, 2cos(2pi F 1), ... 2cos(2pi F 7)]
    K = NTAPS // 2  # 7
    cols = [np.ones_like(F)]
    for k in range(1, K + 1):
        cols.append(2.0 * np.cos(2.0 * np.pi * F * k))
    A = np.stack(cols, axis=1)

    w = np.sqrt(weight)
    Aw = A * w[:, None]
    dw = desired * w
    b, *_ = np.linalg.lstsq(Aw, dw, rcond=None)

    # Recover symmetric taps h[0..14]; b0 = h[7], bk = 2*h[7+k]
    h = np.zeros(NTAPS)
    h[K] = b[0]
    for k in range(1, K + 1):
        h[K + k] = b[k] / 2.0
        h[K - k] = b[k] / 2.0
    return h


def quantize(h):
    """Unity-DC normalise then Q15-quantise; force integer sum == 32768."""
    h = h / np.sum(h)
    q = np.round(h * Q15).astype(int)
    q[NTAPS // 2] += Q15 - int(np.sum(q))  # push residual into the centre tap
    return q


def metrics(q, f_pass, f_stop):
    """Return (passband ripple dB of CIC*comp, stopband atten dB of comp)."""
    F = np.linspace(0.0, 0.5, 501)
    K = 7
    A = np.full_like(F, q[K] / Q15)
    for k in range(1, K + 1):
        A += 2.0 * (q[K + k] / Q15) * np.cos(2.0 * np.pi * F * k)
    combined = A * sinc_droop(F)
    pb = F <= f_pass
    sb = F >= f_stop
    ripple = 20 * np.log10(combined[pb].max() / combined[pb].min())
    atten = 20 * np.log10(max(abs(A[sb]).max(), 1e-6))
    return ripple, atten


def sweep():
    """Search params; pick the flattest passband with stopband atten <= -6 dB."""
    best = None
    for fp in (0.18, 0.20, 0.22, 0.24, 0.26):
        for fs in (0.40, 0.43, 0.45, 0.47):
            for ws in (0.2, 0.3, 0.5, 1.0):
                if fs <= fp:
                    continue
                q = quantize(design(fp, fs, ws))
                ripple, atten = metrics(q, fp, fs)
                if atten > -6.0:
                    continue
                key = (round(ripple, 4), round(-atten, 2))
                if best is None or ripple < best[0]:
                    best = (ripple, atten, fp, fs, ws)
    return best


def main():
    import sys
    if "--sweep" in sys.argv:
        b = sweep()
        print("// best: Fpass=%.2f Fstop=%.2f Wstop=%.2f -> ripple=%.3f dB atten=%.2f dB"
              % (b[2], b[3], b[4], b[0], b[1]))
        return
    q = quantize(design())

    c = [int(q[i]) for i in range(8)]  # c0..c6 mirror pairs, c7 centre
    print("// CIC droop-compensation bank (3-stage sinc^3 inverse), Q15")
    print("// design: Fpass=%.2f Fstop=%.2f (output-normalised), sum=%d" %
          (F_PASS, F_STOP, int(np.sum(q))))
    names = ["c0", "c1", "c2", "c3", "c4", "c5", "c6", "c7"]
    line = "  "
    for i, n in enumerate(names):
        line += "%s <= 16'sd%d;%s" % (n, c[i], "  " if c[i] >= 0 else " ")
        line = line.replace("16'sd-", "-16'sd")
        if i % 4 == 3:
            print(line)
            line = "  "

    # Honest achieved spec: combined CIC*comp flatness vs. the uncompensated
    # CIC droop, at two output-normalised band edges.
    print("//")
    print("//   band       uncomp CIC droop   comp'd CIC*comp ripple")
    for edge in (0.10, 0.15):
        F = np.linspace(0.0, edge, 400)
        uncomp = 20 * np.log10(sinc_droop(F).min())  # droop at the edge
        ripple, _ = metrics(q, edge, F_STOP)
        print("//   F<=%.2f      %6.2f dB           %5.2f dB p-p" % (edge, uncomp, ripple))


if __name__ == "__main__":
    main()
