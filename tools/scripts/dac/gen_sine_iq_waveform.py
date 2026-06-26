#!/usr/bin/env python3
"""Generate seamless looping int16 IQ sine waveform .bin for VSG / DAC playback.

Layout: interleaved I0, Q0, I1, Q1, ... (little-endian int16), same as docs/wave/*.bin.
Samples are signed-14 (±8191 = DAC full scale); the TX chain plays them 1:1 (no >>2).

Two generation modes:
1) short-period: repeat a short IQ LUT (legacy behavior)
2) coherent-record: generate one full record with integer cycles for lower spurs and exact looping

IMPORTANT — correct Fs for --fs-hz:
  The dac_wave_player (rf_ctrl_path/dac_wave_player.v) outputs I and Q on alternating
  sys_clk cycles, so each channel's effective sample rate is sys_clk / 2 = 61.44 MHz.
  Always pass --fs-hz 61440000 (NOT sys_clk 122.88 MHz) to get the correct output frequency.

  Wrong (previous default):  --fs-hz 125000000  → output = tone_hz × 61.44 / 125 ≈ 0.49 × tone_hz
  Correct:                   --fs-hz 61440000   → output = tone_hz exactly

Regenerate all checked-in docs/wave/ reference files:

  python tools/scripts/dac/gen_ref_waveforms.py
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

# Unified 14-bit DAC convention: samples are signed-14 (±8191 = full scale) stored
# in int16. The TX chain (tx_iq_dsp) maps them 1:1 to the DAC — NO >>2 / ÷4.
# 4096 = 50 % of ±8191 FS (-6 dBFS), safe headroom for ADC loopback and for the
# halfband interpolator's passband overshoot. Raise via --amplitude (keep ≲7200
# to leave ~1 dB overshoot backoff before the chain saturates at ±8191).
DEFAULT_AMP = 4096
S14_MAX = 8191
S14_MIN = -8192
DEFAULT_TARGET_BYTES = 1_048_576
# Effective per-channel DAC sample rate: sys_clk (122.88 MHz) / 2 (I and Q alternate each cycle).
DAC_WAVE_FS_HZ = 61_440_000.0


def one_period_iq(samples_per_period: int, amplitude: int = DEFAULT_AMP) -> tuple[np.ndarray, np.ndarray]:
    """One cycle: I=cos, Q=sin, rounded to int16."""
    n = int(samples_per_period)
    if n < 4:
        raise ValueError("samples_per_period must be >= 4")
    t = np.arange(n, dtype=np.float64)
    phase = 2.0 * np.pi * t / n
    i_f = amplitude * np.cos(phase)
    q_f = amplitude * np.sin(phase)
    i_s = np.round(i_f).astype(np.int32)
    q_s = np.round(q_f).astype(np.int32)
    if np.any(np.abs(i_s) > S14_MAX) or np.any(np.abs(q_s) > S14_MAX):
        raise ValueError(f"amplitude too large for s14 DAC range (±{S14_MAX})")
    return i_s.astype(np.int16), q_s.astype(np.int16)


def coherent_record_iq(
    iq_pairs: int,
    fs_hz: float,
    tone_hz: float,
    amplitude: int = DEFAULT_AMP,
    force_zero_dc: bool = True,
) -> tuple[np.ndarray, np.ndarray, int, float]:
    """Generate one coherent IQ record with integer cycles across whole file."""
    n = int(iq_pairs)
    if n < 8:
        raise ValueError("iq_pairs must be >= 8")
    if fs_hz <= 0:
        raise ValueError("fs_hz must be > 0")
    if tone_hz <= 0:
        raise ValueError("tone_hz must be > 0")

    # Integer-cycle constraint for seamless looping and coherent FFT.
    cycles = int(np.round(tone_hz * n / fs_hz))
    if cycles <= 0:
        raise ValueError("requested tone is too low for current record length")

    # Stay away from Nyquist; leave margin for practical DAC reconstruction.
    if cycles >= n // 2:
        raise ValueError("requested tone is too high (>= Nyquist)")

    phase = 2.0 * np.pi * cycles * np.arange(n, dtype=np.float64) / n
    i_s = np.round(amplitude * np.cos(phase)).astype(np.int32)
    q_s = np.round(amplitude * np.sin(phase)).astype(np.int32)

    if force_zero_dc:
        i_s = i_s - int(np.round(float(i_s.mean())))
        q_s = q_s - int(np.round(float(q_s.mean())))

    i_s = np.clip(i_s, S14_MIN, S14_MAX).astype(np.int16)
    q_s = np.clip(q_s, S14_MIN, S14_MAX).astype(np.int16)
    actual_tone_hz = cycles * fs_hz / n
    return i_s, q_s, cycles, actual_tone_hz


def tile_to_byte_target(
    i_lut: np.ndarray,
    q_lut: np.ndarray,
    target_bytes: int,
) -> np.ndarray:
    period = len(i_lut)
    if period <= 0:
        raise ValueError("empty LUT")
    iq_pairs_needed = target_bytes // 4
    if iq_pairs_needed <= 0:
        raise ValueError("target_bytes too small")
    full_periods = iq_pairs_needed // period
    if full_periods < 1:
        raise ValueError(
            f"target_bytes={target_bytes} fits fewer than one period ({period} IQ pairs)"
        )
    used_pairs = full_periods * period
    if used_pairs != iq_pairs_needed:
        # Seamless loop requires integer number of periods; trim to fit.
        pass
    i_tile = np.tile(i_lut, full_periods)
    q_tile = np.tile(q_lut, full_periods)
    interleaved = np.empty(used_pairs * 2, dtype=np.int16)
    interleaved[0::2] = i_tile
    interleaved[1::2] = q_tile
    return interleaved


def interleave_iq(i: np.ndarray, q: np.ndarray) -> np.ndarray:
    interleaved = np.empty(i.size * 2, dtype=np.int16)
    interleaved[0::2] = i
    interleaved[1::2] = q
    return interleaved


def measure_purity(i: np.ndarray, q: np.ndarray, fs_hz: float) -> dict[str, float]:
    """Report carrier and largest non-carrier spur from complex FFT."""
    z = i.astype(np.float64) + 1j * q.astype(np.float64)
    z -= z.mean()
    n = len(z)
    spec = np.fft.fftshift(np.fft.fft(z))
    mag2 = np.abs(spec) ** 2
    freqs = np.fft.fftshift(np.fft.fftfreq(n, d=1.0 / fs_hz))
    k0 = int(np.argmax(mag2))
    p_carrier = mag2[k0]
    mag2[k0] = 0.0
    p_spur = float(np.max(mag2))
    return {
        "f0_hz": float(abs(freqs[k0])),
        "spur_dbc": float(10.0 * np.log10(p_spur / p_carrier)) if p_carrier > 0 else -np.inf,
    }


def write_bin(path: Path, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(samples.astype("<i2", copy=False).tobytes())


def write_waveform_swapped(path: Path, samples: np.ndarray) -> None:
    """Write .WAVEFORM with per-int16 byte swap relative to .bin."""
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = samples.astype("<i2", copy=False).view(np.uint8).reshape(-1, 2)
    swapped = raw[:, ::-1].reshape(-1)
    path.write_bytes(swapped.tobytes())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--mode",
        choices=("short-period", "coherent-record"),
        default="coherent-record",
        help="Generation method. coherent-record usually gives better spectral purity.",
    )
    ap.add_argument(
        "--samples-per-period",
        type=int,
        default=16,
        help="Used by short-period mode: IQ samples per cycle (16 @ 61.44 MHz -> 3.84 MHz)",
    )
    ap.add_argument(
        "--tone-hz",
        type=float,
        default=3_840_000.0,
        help="Used by coherent-record mode: desired tone frequency (actual snaps to coherent bin).",
    )
    ap.add_argument("--amplitude", type=int, default=DEFAULT_AMP)
    ap.add_argument(
        "--target-bytes",
        type=int,
        default=DEFAULT_TARGET_BYTES,
        help="Output size in bytes. Must be multiple of 4 (I/Q int16).",
    )
    ap.add_argument(
        "--fs-hz",
        type=float,
        default=DAC_WAVE_FS_HZ,
        help="DAC per-channel playback rate (sys_clk/2 = 61.44 MHz). Sets output frequency scale.",
    )
    ap.add_argument(
        "--no-force-zero-dc",
        action="store_true",
        help="Disable integer-mean DC correction in coherent-record mode.",
    )
    ap.add_argument("-o", "--out", type=Path, required=True)
    ap.add_argument(
        "--waveform-out",
        type=Path,
        default=None,
        help="Optional .WAVEFORM path (int16 bytes swapped vs .bin).",
    )
    args = ap.parse_args()

    if args.target_bytes % 4 != 0:
        raise ValueError("target_bytes must be multiple of 4")
    iq_pairs = args.target_bytes // 4

    if args.mode == "short-period":
        i_lut, q_lut = one_period_iq(args.samples_per_period, args.amplitude)
        interleaved = tile_to_byte_target(i_lut, q_lut, args.target_bytes)
        i_out = interleaved[0::2]
        q_out = interleaved[1::2]
        tone_hz = args.fs_hz / len(i_lut)
        mode_msg = f"samples_per_period={len(i_lut)} periods={(len(i_out) // len(i_lut))}"
    else:
        i_out, q_out, cycles, tone_hz = coherent_record_iq(
            iq_pairs=iq_pairs,
            fs_hz=args.fs_hz,
            tone_hz=args.tone_hz,
            amplitude=args.amplitude,
            force_zero_dc=not args.no_force_zero_dc,
        )
        interleaved = interleave_iq(i_out, q_out)
        mode_msg = f"iq_pairs={iq_pairs} coherent_cycles={cycles}"

    write_bin(args.out, interleaved)
    if args.waveform_out is not None:
        write_waveform_swapped(args.waveform_out, interleaved)

    used_bytes = interleaved.nbytes
    purity = measure_purity(i_out, q_out, args.fs_hz)

    print(f"wrote {args.out}")
    print(f"  mode={args.mode}  {mode_msg}")
    print(f"  bytes={used_bytes}  iq_pairs={len(interleaved)//2}")
    print(f"  Fs={args.fs_hz/1e6:.3f} MHz  f_tone={tone_hz/1e6:.6f} MHz")
    print(f"  mean(I)={float(np.mean(i_out)):.6f}  mean(Q)={float(np.mean(q_out)):.6f}")
    print(f"  peak I/Q={int(np.max(np.abs(interleaved)))}  spur_dbc(one period)={purity['spur_dbc']:.2f}")
    if args.waveform_out is not None:
        print(f"  wrote waveform(swapped) -> {args.waveform_out}")


if __name__ == "__main__":
    main()
