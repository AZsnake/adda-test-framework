#!/usr/bin/env python3
"""Generate seamless looping int16 IQ square-wave clock for external VSG playback.

Layout: interleaved I0, Q0, I1, Q1, ... (little-endian int16), same as docs/wave/*.bin.
Samples are signed-14 style (±8191 = full scale). I and Q carry the same in-phase clock.

Default: 20 MHz square @ 125 MSa/s. Minimum coherent LUT = 25 IQ pairs (4 clock cycles).
Analog common-mode (0.6 V) and differential amplitude (0.6 Vpp) are set on the VSG,
not encoded in the file.

Example:

  python tools/vsg/gen_sq_iq_clock.py \\
    --fs-hz 125000000 --tone-hz 20000000 \\
    -o docs/wave/sq_iq_20M00_125Msps.bin \\
    --waveform-out docs/wave/sq_iq_20M00_125Msps.WAVEFORM
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np

S14_MAX = 8191
S14_MIN = -8192
DEFAULT_AMP = 8191
DEFAULT_FS_HZ = 125_000_000.0
DEFAULT_TONE_HZ = 20_000_000.0
# 25 IQ pairs = 4 exact 20 MHz cycles @ 125 MSa/s; 10485 periods -> seamless loop.
DEFAULT_PERIOD_SAMPLES = 25
DEFAULT_TARGET_BYTES = DEFAULT_PERIOD_SAMPLES * 10485 * 4  # 1_048_500


def coherent_period_samples(fs_hz: float, tone_hz: float) -> tuple[int, int]:
    """Return (period_samples, cycles_in_period) for exact seamless looping."""
    if fs_hz <= 0 or tone_hz <= 0:
        raise ValueError("fs_hz and tone_hz must be > 0")
    g = math.gcd(int(round(fs_hz)), int(round(tone_hz)))
    fs_i = int(round(fs_hz)) // g
    tone_i = int(round(tone_hz)) // g
    # period_samples / fs = cycles / tone  =>  period_samples / cycles = fs / tone
    return fs_i, tone_i


def square_coherent_lut(
    fs_hz: float,
    tone_hz: float,
    amplitude: int = DEFAULT_AMP,
) -> tuple[np.ndarray, np.ndarray, int, int]:
    """One coherent square-wave period; Q = I (in-phase on both channels)."""
    period, cycles = coherent_period_samples(fs_hz, tone_hz)
    if period < 4:
        raise ValueError("coherent period too short for square wave")
    if amplitude <= 0 or amplitude > S14_MAX:
        raise ValueError(f"amplitude must be in 1..{S14_MAX}")

    n = np.arange(period, dtype=np.float64)
    frac = (cycles * n / period) % 1.0
    s = np.where(frac < 0.5, 1, -1).astype(np.int32)
    i_s = (amplitude * s).astype(np.int16)
    q_s = i_s.copy()
    return i_s, q_s, period, cycles


def tile_to_byte_target(
    i_lut: np.ndarray,
    q_lut: np.ndarray,
    target_bytes: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
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
    i_tile = np.tile(i_lut, full_periods)
    q_tile = np.tile(q_lut, full_periods)
    interleaved = np.empty(used_pairs * 2, dtype=np.int16)
    interleaved[0::2] = i_tile
    interleaved[1::2] = q_tile
    return interleaved, i_tile, q_tile


def measure_purity(i: np.ndarray, q: np.ndarray, fs_hz: float) -> dict[str, float]:
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
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = samples.astype("<i2", copy=False).view(np.uint8).reshape(-1, 2)
    swapped = raw[:, ::-1].reshape(-1)
    path.write_bytes(swapped.tobytes())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--fs-hz", type=float, default=DEFAULT_FS_HZ)
    ap.add_argument("--tone-hz", type=float, default=DEFAULT_TONE_HZ)
    ap.add_argument("--amplitude", type=int, default=DEFAULT_AMP)
    ap.add_argument(
        "--target-bytes",
        type=int,
        default=DEFAULT_TARGET_BYTES,
        help="Output size in bytes (trimmed to integer LUT periods).",
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

    i_lut, q_lut, period, cycles = square_coherent_lut(
        args.fs_hz, args.tone_hz, args.amplitude
    )
    interleaved, i_out, q_out = tile_to_byte_target(i_lut, q_lut, args.target_bytes)

    write_bin(args.out, interleaved)
    if args.waveform_out is not None:
        write_waveform_swapped(args.waveform_out, interleaved)

    tone_hz = cycles * args.fs_hz / period
    duty = float(np.mean(i_lut > 0))
    purity = measure_purity(i_out, q_out, args.fs_hz)
    periods = len(i_out) // period

    print(f"wrote {args.out}")
    print(f"  period_samples={period}  coherent_cycles={cycles}  tiled_periods={periods}")
    print(f"  bytes={interleaved.nbytes}  iq_pairs={len(interleaved) // 2}")
    print(f"  Fs={args.fs_hz / 1e6:.3f} MHz  f_tone={tone_hz / 1e6:.6f} MHz")
    print(f"  amplitude={args.amplitude}  duty_cycle={duty:.4f}")
    print(f"  mean(I)={float(np.mean(i_out)):.6f}  mean(Q)={float(np.mean(q_out)):.6f}")
    print(f"  peak={int(np.max(np.abs(interleaved)))}  spur_dbc={purity['spur_dbc']:.2f}")
    if not np.array_equal(i_out, q_out):
        print("  WARNING: I != Q")
    if args.waveform_out is not None:
        print(f"  wrote waveform(swapped) -> {args.waveform_out}")


if __name__ == "__main__":
    main()
