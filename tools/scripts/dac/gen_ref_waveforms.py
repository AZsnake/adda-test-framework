#!/usr/bin/env python3
"""Regenerate all reference IQ sine files under docs/wave/.

Naming standard (self-describing, see docs/wave/README.md):

    sine_iq_<tone>_<level>.<ext>
      sine_iq  complex sine, interleaved I/Q
      <tone>   tone frequency, RKM notation: 9M00 = 9.00 MHz, 3M84 = 3.84 MHz
      <level>  amplitude in dBFS vs s14 full scale (±8191): -6dBFS / -12dBFS ...
      <ext>    .bin = little-endian,  .WAVEFORM = big-endian (same data, swapped)

All files: Fs = 61.44 MSa/s/ch (sys_clk/2), 1 MB (262144 IQ pairs), coherent
record (integer cycles -> seamless loop + coherent FFT), unified 14-bit (s14)
amplitude so the TX chain plays them 1:1 to the DAC.

Run from repo root:

  python tools/scripts/dac/gen_ref_waveforms.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
GEN = REPO_ROOT / "tools" / "scripts" / "dac" / "gen_sine_iq_waveform.py"
WAVE_DIR = REPO_ROOT / "docs" / "wave"

# s14 full scale = ±8191. dBFS -> peak amplitude (each 6 dB step halves it).
#   -6 dBFS -> 4096,  -12 dBFS -> 2048,  -18 dBFS -> 1024
# (stem, tone_hz, amplitude_s14)
PRESETS: list[tuple[str, int, int]] = [
    ("sine_iq_3M84_-6dBFS",  3_840_000, 4096),  # low tone, general bring-up
    ("sine_iq_9M00_-6dBFS",  9_000_000, 4096),  # primary reference tone
    ("sine_iq_9M00_-12dBFS", 9_000_000, 2048),  # amplitude sweep (SFDR vs level)
    ("sine_iq_9M00_-18dBFS", 9_000_000, 1024),  # amplitude sweep (SFDR vs level)
]


def main() -> None:
    if not GEN.is_file():
        sys.exit(f"error: generator not found: {GEN}")

    WAVE_DIR.mkdir(parents=True, exist_ok=True)
    for stem, tone_hz, amp in PRESETS:
        bin_out = WAVE_DIR / f"{stem}.bin"
        wf_out = WAVE_DIR / f"{stem}.WAVEFORM"
        cmd = [
            sys.executable,
            str(GEN),
            "--mode", "coherent-record",
            "--tone-hz", str(tone_hz),
            "--amplitude", str(amp),
            "-o", str(bin_out),
            "--waveform-out", str(wf_out),
        ]
        print(f"[gen] {stem}  tone={tone_hz/1e6:.2f} MHz  amp={amp} (s14)")
        subprocess.run(cmd, check=True)

    print(f"[ok] wrote {len(PRESETS)} bin + WAVEFORM pairs under {WAVE_DIR}")


if __name__ == "__main__":
    main()
