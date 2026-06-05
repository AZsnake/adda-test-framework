"""DAC->ADC loopback metrics helper after DCLKIO dynamic phase shift removal.

DCLKIO phase is now selected by board dip switches ``pad_input_s[2:0]`` (7 fixed
taps @ 45° steps). UART 0x4A / ``set_dclk_phase()`` no longer exist.

Workflow:
  1. Set dip switches per ``dac_dclk_dip_switch_hint()`` / GUI combo reference.
  2. Run this script (or GUI loopback) at each switch setting.
  3. Pick the setting with best SFDR; leave switches parked there.

Run with the GUI serial port DISCONNECTED (Windows COM is exclusive).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

import rf_uart_client as rf  # noqa: E402
import adc_analysis as aa    # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Loopback SFDR at current dip-switch DCLKIO phase (manual sweep).")
    ap.add_argument("--port", default="COM14")
    ap.add_argument("--baud", type=int, default=rf.DEFAULT_BAUD)
    ap.add_argument("--n", type=int, default=4096, help="ADC samples per capture")
    ap.add_argument("--freq-khz", type=float, default=200.0)
    ap.add_argument("--amp", type=int, default=50)
    ap.add_argument("--channel", choices=["I", "Q"], default="I")
    ap.add_argument("--phase-index", type=int, default=None,
                    help="optional 0..6 for logging only (does not change hardware)")
    ap.add_argument("--no-setup", action="store_true",
                    help="don't re-program the tone (use whatever is running)")
    ap.add_argument("--list-phases", action="store_true",
                    help="print dip-switch table and exit")
    args = ap.parse_args()

    if args.list_phases:
        print("DCLKIO phase = pad_input_s[2:0] dip switches (ON=high):")
        for idx, deg, bits in rf.DAC_DCLK_DIP_PHASES:
            print(f"  {bits}  {deg:3d}°  —  {rf.dac_dclk_dip_switch_hint(idx)}")
        print("  111  90° (fallback)")
        return 0

    chan = rf.ADC_CHAN_I if args.channel == "I" else rf.ADC_CHAN_Q

    with rf.RfAddaUart(args.port, baud=args.baud) as dev:
        print(f"ping={dev.ping():#04x}  fw={dev.firmware_version():#04x}")
        if args.phase_index is not None:
            print("dip switches (manual):", rf.dac_dclk_dip_switch_hint(args.phase_index))
        else:
            print("dip switches: set pad_input_s[2:0] on board (see --list-phases)")

        if not args.no_setup:
            cfg = dev.dac_config(wave="sine", freq_hz=args.freq_khz * 1e3,
                                 amp_pct=args.amp)
            dev.dac_tone_enable(True)
            print(f"tone: {cfg}")
        dev.set_rx_config(dec_ratio=0, fir_bypass=True, iq_bypass=True)

        samples = dev.capture_all(args.n, channel=chan)
        signed = rf.samples_to_signed(samples, bits=14)
        m = aa.compute_dynamic_metrics(signed, fs_hz=rf.DEFAULT_ADC_FS_HZ)
        print(f"SFDR={m['sfdr_db']:.2f} dB  THD={m['thd_db']:.2f} dB  "
              f"SINAD={m['sinad_db']:.2f} dB  ENOB={m['enob_bits']:.2f}")
        print(f"fund={m['fund_hz']/1e3:.2f} kHz  spur={m['spur_hz']/1e3:.2f} kHz")
        print("\nSweep: repeat with each dip-switch setting; compare SFDR.")
        print("Run: python sweep_dclk_phase.py --list-phases")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
