"""ADC spectrum and dynamic-metrics analysis helpers.

Separated from UART/protocol code so analysis logic can evolve independently.
"""

from __future__ import annotations

import math
import statistics

DEFAULT_ADC_FS_HZ = 122_880_000.0
# Per-channel IQ rate for dac_wave_player URAM playback (sys_clk / 2).
DAC_WAVE_FS_HZ = 61_440_000.0


def iq_words_to_s14(words, *, prefer_shift2: bool = False):
    """Convert int16 interleaved IQ words to signed-14 codes for analysis.

    Unified DAC convention: wave files are now signed-14 (peak ≤ ±8191) and the
    TX chain plays them 1:1 (no ``>>2``), so the default decode is s14-direct.

    Legacy/other sources still auto-detected by heuristic:
    - Old DAC ``.bin`` / ``.WAVEFORM`` files written as s16 (peak > 8191): the
      ``dac_wave_player`` used to apply ``>>2`` — fall back to ``>>2`` decode.
    - MATLAB / ``iqfftbin`` exports: s14 stored in int16 with 2 LSB zero (``<<2``).

    Clipping s16 values above ±8191 without ``>>2`` first flattens sine peaks and
    makes such legacy files look like non-sinusoidal garbage in the GUI.
    """
    import numpy as np

    arr = np.asarray(words, dtype=np.int16)
    if arr.size == 0:
        return np.asarray([], dtype=np.int16), "empty"
    vals = arr.astype(np.int32, copy=False)
    peak = int(np.max(np.abs(vals)))
    mode = "s14 direct"
    if peak > 8191:
        vals = np.right_shift(vals, 2)
        mode = "int16>>2 to s14"
    elif prefer_shift2 or (
        peak > 0 and np.count_nonzero((vals & 0x3) == 0) >= int(0.8 * vals.size)
    ):
        vals = np.right_shift(vals, 2)
        mode = "q14>>2 to s14"
    vals = np.clip(vals, -8192, 8191).astype(np.int16, copy=False)
    return vals, mode

# Window function catalog. Each entry maps an internal key to a label and a
# builder that returns an N-point window as a numpy array. All windows are
# defined symmetrically over [0, N-1]; they are applied to the time-domain
# block, and the magnitude is normalised by the window's coherent gain so
# the displayed peak equals the input sine amplitude.
WINDOW_CHOICES: list[tuple[str, str]] = [
    ("rect", "Rectangular (none)"),
    ("hann", "Hann"),
    ("hamming", "Hamming"),
    ("blackman", "Blackman"),
    ("blackmanharris", "Blackman-Harris (4-term)"),
    ("flattop", "Flat-top"),
    ("bartlett", "Bartlett (triangular)"),
    ("kaiser", "Kaiser beta=8.6"),
]
WINDOW_KEYS = [k for k, _ in WINDOW_CHOICES]
WINDOW_LABEL_TO_KEY = {label: key for key, label in WINDOW_CHOICES}
WINDOW_KEY_TO_LABEL = {key: label for key, label in WINDOW_CHOICES}
DEFAULT_WINDOW = "hann"


def build_window(name: str, n: int):
    """Return an N-point window as a numpy array. ``name`` is a WINDOW_KEYS key."""
    import numpy as np

    key = (name or DEFAULT_WINDOW).strip().lower()
    if key in ("none", "rect", "rectangular", "boxcar"):
        return np.ones(n, dtype=np.float64)
    if key in ("hann", "hanning"):
        return np.hanning(n)
    if key == "hamming":
        return np.hamming(n)
    if key == "blackman":
        return np.blackman(n)
    if key == "bartlett":
        return np.bartlett(n)
    if key in ("kaiser", "kaiser8.6"):
        return np.kaiser(n, 8.6)
    if key in ("blackmanharris", "bh", "bh4"):
        # 4-term Blackman-Harris (-92 dB sidelobes).
        a = (0.35875, 0.48829, 0.14128, 0.01168)
        k = np.arange(n)
        return (
            a[0]
            - a[1] * np.cos(2 * np.pi * k / (n - 1))
            + a[2] * np.cos(4 * np.pi * k / (n - 1))
            - a[3] * np.cos(6 * np.pi * k / (n - 1))
        )
    if key in ("flattop", "ft"):
        # SR785 / matplotlib flat-top coefficients (±0.01 dB amplitude flatness).
        a = (0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368)
        k = np.arange(n)
        return (
            a[0]
            - a[1] * np.cos(2 * np.pi * k / (n - 1))
            + a[2] * np.cos(4 * np.pi * k / (n - 1))
            - a[3] * np.cos(6 * np.pi * k / (n - 1))
            + a[4] * np.cos(8 * np.pi * k / (n - 1))
        )
    raise ValueError(f"unknown window: {name}")


def window_main_lobe_half_bins(name: str) -> int:
    """Approximate one-sided main-lobe width in bins."""
    key = (name or DEFAULT_WINDOW).strip().lower()
    table = {
        "rect": 1, "rectangular": 1, "none": 1, "boxcar": 1,
        "hann": 3, "hanning": 3,
        "hamming": 3,
        "blackman": 4,
        "bartlett": 3,
        "kaiser": 5, "kaiser8.6": 5,
        "blackmanharris": 5, "bh": 5, "bh4": 5,
        "flattop": 6, "ft": 6,
    }
    return table.get(key, 3)


# --- DC blocking -------------------------------------------------------------
# Time-domain DC-removal methods applied (optionally) before FFT / metrics so
# that the spectrum plot and the numeric metrics share one consistent input.
# A separate frequency-domain mask (``dc_mask_bins``) nulls the lowest bins to
# kill any residual DC leakage skirt after windowing.
DC_METHOD_CHOICES: list[tuple[str, str]] = [
    ("mean", "Mean subtract"),
    ("median", "Median subtract"),
    ("iir", "IIR DC blocker (zero-phase)"),
    ("detrend", "Linear detrend"),
]
DC_METHOD_KEYS = [k for k, _ in DC_METHOD_CHOICES]
DC_METHOD_LABEL_TO_KEY = {label: key for key, label in DC_METHOD_CHOICES}
DC_METHOD_KEY_TO_LABEL = {key: label for key, label in DC_METHOD_CHOICES}
DEFAULT_DC_METHOD = "mean"
DEFAULT_DC_MASK_BINS = 2
DEFAULT_IIR_DC_ALPHA = 0.995


def apply_dc_block(
    samples,
    *,
    method: str = DEFAULT_DC_METHOD,
    bypass: bool = False,
    iir_alpha: float = DEFAULT_IIR_DC_ALPHA,
):
    """Return a float64 numpy array with the DC component removed.

    ``bypass=True`` returns the samples unchanged (still float64) so callers
    can see the raw DC.  Otherwise the chosen ``method`` is applied:

      * ``mean``    – subtract the block mean (cheapest, zero distortion on a
                      coherently-captured tone; matches the legacy behaviour).
      * ``median``  – subtract the median (robust to clipping / outliers).
      * ``iir``     – first-order DC blocker y[n]=x[n]-x[n-1]+a*y[n-1] run
                      forward then backward for zero phase (hardware-equivalent
                      high-pass with a notch at DC).
      * ``detrend`` – remove the least-squares linear trend (DC + slow drift).
    """
    import numpy as np

    x = np.asarray(samples, dtype=np.float64)
    if bypass or x.size == 0:
        return x

    key = (method or DEFAULT_DC_METHOD).strip().lower()
    if key == "mean":
        return x - x.mean()
    if key == "median":
        return x - float(np.median(x))
    if key == "detrend":
        n = x.size
        if n < 2:
            return x - x.mean()
        t = np.arange(n, dtype=np.float64)
        a_mat = np.vstack([t, np.ones(n)]).T
        slope, intercept = np.linalg.lstsq(a_mat, x, rcond=None)[0]
        return x - (slope * t + intercept)
    if key == "iir":
        a = float(iir_alpha)

        def _fwd(v):
            y = np.empty_like(v)
            x_prev = 0.0
            y_prev = 0.0
            for i in range(v.size):
                y_i = v[i] - x_prev + a * y_prev
                y[i] = y_i
                x_prev = v[i]
                y_prev = y_i
            return y

        # Forward-backward → zero phase, cancels the IIR's group delay so the
        # tone bin stays put and only DC is notched.
        y = _fwd(x)
        return _fwd(y[::-1])[::-1]

    # Unknown method → safe fallback.
    return x - x.mean()


def compute_fft_spectrum(
    samples: list[int],
    *,
    fs_hz: float = DEFAULT_ADC_FS_HZ,
    bits: int = 14,
    window: str = DEFAULT_WINDOW,
    dc_block: bool = True,
    dc_method: str = DEFAULT_DC_METHOD,
    dc_mask_bins: int = DEFAULT_DC_MASK_BINS,
) -> tuple[list[float], list[float], list[float], list[float]]:
    """Return (freq_hz, mag_linear, mag_db, power_pct) for single-sided spectrum.

    DC handling: when ``dc_block`` is True the time-domain DC is removed via
    ``dc_method`` and the lowest ``dc_mask_bins`` FFT bins are nulled (so the
    DC residual is excluded from the plot, the 0 dB reference, and power%).
    When ``dc_block`` is False nothing is removed — the raw DC bin is shown.
    """
    try:
        import numpy as np
    except ImportError as e:
        raise RuntimeError("numpy not installed: pip install numpy") from e

    n = len(samples)
    if n < 4:
        raise ValueError("need at least 4 samples for FFT")

    x = apply_dc_block(samples, method=dc_method, bypass=not dc_block)
    win = build_window(window, n)
    xw = x * win
    spec = np.fft.rfft(xw)
    freqs = np.fft.rfftfreq(n, d=1.0 / fs_hz)
    norm = max(float(np.sum(win)) / 2.0, 1e-12)
    mag = np.abs(spec) / norm
    # Frequency-domain DC mask: null the lowest bins so leakage past the
    # time-domain removal cannot show as a spike or pollute power%.
    k = max(0, int(dc_mask_bins)) if dc_block else 0
    if k > 0:
        mag[: min(k, mag.size)] = 0.0
    mag_db = 20.0 * np.log10(np.maximum(mag, 1e-12))
    # 0 dB reference = strongest non-masked bin (always skip at least bin 0).
    ref_start = max(1, k)
    if mag_db.size > ref_start:
        peak_ref = float(np.max(mag_db[ref_start:]))
    else:
        peak_ref = float(mag_db[0])
    mag_db = mag_db - peak_ref
    power = mag * mag
    total_power = float(np.sum(power))
    if total_power > 0.0:
        power_pct = 100.0 * power / total_power
    else:
        power_pct = np.zeros_like(power)
    return freqs.tolist(), mag.tolist(), mag_db.tolist(), power_pct.tolist()


def compute_fft_db(
    samples: list[int],
    *,
    fs_hz: float = DEFAULT_ADC_FS_HZ,
    bits: int = 14,
    window: str = DEFAULT_WINDOW,
) -> tuple[list[float], list[float]]:
    """Return (freq_hz, magnitude_db) for single-sided spectrum."""
    freqs, _mag, mag_db, _pct = compute_fft_spectrum(
        samples, fs_hz=fs_hz, bits=bits, window=window
    )
    return freqs, mag_db


def compute_dynamic_metrics(
    samples: list[int],
    *,
    fs_hz: float = DEFAULT_ADC_FS_HZ,
    bits: int = 14,
    n_harmonics: int = 9,
    fund_half_bw_bins: int | None = 10,
    window: str = DEFAULT_WINDOW,
    floor_db: float = -140.0,
    dc_bins: int = 2,
    dc_block: bool = True,
    dc_method: str = DEFAULT_DC_METHOD,
    dc_mask_bins: int = DEFAULT_DC_MASK_BINS,
) -> dict[str, float]:
    """MATLAB-aligned dynamic metrics (adc_ifft_analysis.m reference).

    DC handling mirrors :func:`compute_fft_spectrum`: when ``dc_block`` is True
    the time-domain DC is removed via ``dc_method`` and the lowest
    ``dc_mask_bins`` bins are excluded from the fundamental search, total
    power, and spur search.  When ``dc_block`` is False, only bin 0 is held
    out of the *fundamental* pick (so DC is never mislabelled as the carrier)
    but DC is otherwise counted in noise/spur power.
    """
    try:
        import numpy as np
    except ImportError as e:
        raise RuntimeError("numpy not installed: pip install numpy") from e

    n_raw = len(samples)
    if n_raw < 16:
        raise ValueError("need at least 16 samples for dynamic metrics")
    n = 1 << (n_raw.bit_length() - 1)
    if n < 16:
        raise ValueError("effective FFT length is too short")

    nw = int(fund_half_bw_bins if fund_half_bw_bins is not None else 10)
    nw = max(1, nw)
    nh = int(max(2, n_harmonics))
    sf = float(floor_db)
    # Leading DC bins to exclude.  All downstream sums/searches start at index
    # ``dc - 1``, so to null bins 0..mask-1 (matching compute_fft_spectrum's
    # mag[:mask]=0) we set dc = mask + 1.  When bypassed, dc=1 → bin 0 included
    # in noise/spur power.  ``dc_bins`` kept as a legacy lower bound.
    if dc_block:
        mask = int(max(1, dc_mask_bins, dc_bins - 1))
        dc = mask + 1
        fund_start = mask
    else:
        dc = 1
        fund_start = 1

    xd = apply_dc_block(samples[:n], method=dc_method, bypass=not dc_block)
    x = xd / float(n)
    win = build_window(window, n)
    s = x * win

    af = np.abs(np.fft.fft(s, n))[: n // 2]
    if af.size < 4:
        raise ValueError("need at least 4 FFT bins")
    af = np.maximum(af, 1e-30)
    adb = 20.0 * np.log10(af)

    ind0 = int(np.argmax(adb[fund_start:]) + fund_start)  # 0-based Python index
    amax = float(adb[ind0])
    adb = adb - amax
    adb = np.maximum(adb, sf)

    ap = af * af
    n2 = n // 2
    sig_start = max(dc - 1, ind0 - nw)
    sig_end = min(n2 - 1, ind0 + nw)
    sp = float(np.sum(ap[sig_start : sig_end + 1]))
    adb[sig_start : sig_end + 1] = -180.0

    ind1 = [ind0 + 1]  # 1-based indices for overlap math
    harm_db: list[float] = []
    for i in range(2, nh + 1):
        hb1 = (ind0 + 1) * i
        while hb1 > n:
            hb1 -= n
        if hb1 > (n // 2):
            hb1 = n - hb1
        if hb1 < 1:
            hb1 = 1
        ind1.append(hb1)

        h_start1 = max(1, hb1 - nw - i + 1)
        h_end1 = min(n // 2, hb1 + nw + i - 1)
        h_start0 = h_start1 - 1
        h_end0 = h_end1 - 1
        h_peak = float(np.max(adb[h_start0 : h_end0 + 1])) if h_end0 >= h_start0 else sf

        overlap = False
        for j in range(0, i - 1):
            if abs(ind1[j] - hb1) < (nw + i - 1):
                overlap = True
                break
        harm_db.append(sf if overlap else h_peak)

    thd_lin = 0.0
    for h in harm_db:
        thd_lin += 10.0 ** (h / 10.0)
    thd_db = 10.0 * float(math.log10(max(thd_lin, 1e-30)))

    total_power = float(np.sum(ap[dc - 1 : n2]))
    noise_plus_dist = max(total_power - sp, 1e-30)
    sinad_db = 10.0 * float(math.log10(max(sp, 1e-30) / noise_plus_dist))

    sinad_inv = 10.0 ** (-sinad_db / 10.0)
    thd_inv = 10.0 ** (thd_db / 10.0)
    if sinad_inv > thd_inv and sinad_inv > 0.0:
        snr_db = -10.0 * float(math.log10(max(sinad_inv - thd_inv, 1e-30)))
    else:
        snr_db = sinad_db

    spur_peak = 0.0
    spur_bin0 = dc - 1
    for i0 in range(dc - 1, n2):
        if i0 < sig_start or i0 > sig_end:
            if ap[i0] > spur_peak:
                spur_peak = float(ap[i0])
                spur_bin0 = i0
    sfdr_db = 10.0 * float(math.log10(max(sp, 1e-30) / max(spur_peak, 1e-30)))
    enob = (snr_db - 1.76) / 6.02

    # `ind0` / `spur_bin0` are already 0-based FFT-bin indices where
    # bin 0 = DC, so frequency is k * Fs / N (no extra +1).
    fund_hz = float(ind0 * fs_hz / n)
    spur_hz = float(spur_bin0 * fs_hz / n)
    harm_hz = [float((hb1 - 1) * fs_hz / n) for hb1 in ind1[1:]]

    return {
        "fund_hz": fund_hz,
        "fund_bin": float(ind0),
        "snr_db": snr_db,
        "thd_db": thd_db,
        "sinad_db": sinad_db,
        "enob_bits": enob,
        "sfdr_db": sfdr_db,
        "spur_hz": spur_hz,
        "harmonics_hz": harm_hz,
    }


def spectrum_summary(
    freqs: list[float],
    mag_db: list[float],
    *,
    exclude_dc_bins: int = 2,
) -> dict[str, float]:
    """Peak frequency and noise-floor estimate (median of non-DC bins)."""
    if len(freqs) < exclude_dc_bins + 1:
        return {"peak_hz": 0.0, "peak_db": 0.0, "floor_db": 0.0}

    tail_f = freqs[exclude_dc_bins:]
    tail_m = mag_db[exclude_dc_bins:]
    peak_i = max(range(len(tail_m)), key=lambda i: tail_m[i])
    floor_db = statistics.median(tail_m)
    return {
        "peak_hz": tail_f[peak_i],
        "peak_db": tail_m[peak_i],
        "floor_db": floor_db,
    }
