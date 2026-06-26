#!/usr/bin/env python3
"""Capture IQ stream bytes over UART command 0x34."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
import _bootstrap  # noqa: F401, E402

from rf_uart_client import RfAddaUart, MAX_SAMPLES


def parse_args() -> argparse.Namespace:
  p = argparse.ArgumentParser(description="ADC IQ stream capture (0x34)")
  p.add_argument("--port", required=True, help="Serial port, e.g. COM14")
  p.add_argument("--samples", type=int, default=4096, help="Number of IQ samples")
  p.add_argument("--dec-ratio", type=int, default=2, choices=(0, 1, 2), help="0=1x, 1=2x, 2=4x")
  p.add_argument("--split-iq", action="store_true", help="Save as two files: *_i.bin and *_q.bin")
  p.add_argument("--out", default="", help="Output .bin path")
  return p.parse_args()


def main() -> int:
  args = parse_args()
  n = max(1, min(int(args.samples), MAX_SAMPLES))
  default_dir = Path(__file__).resolve().parents[2] / "data"
  out = Path(args.out) if args.out else default_dir / f"adc_stream_{time.strftime('%Y%m%d_%H%M%S')}.bin"
  out.parent.mkdir(parents=True, exist_ok=True)

  with RfAddaUart(args.port) as uart:
    uart.set_rx_config(dec_ratio=args.dec_ratio, capture_mode=1, fir_bypass=True, iq_bypass=True)
    i_samples, q_samples = uart.adc_stream_iq(n)

  if args.split_iq:
    out_i = out.with_name(out.stem + "_i.bin")
    out_q = out.with_name(out.stem + "_q.bin")
    out_i.write_bytes(bytes().join(int(s).to_bytes(2, "little", signed=False) for s in i_samples))
    out_q.write_bytes(bytes().join(int(s).to_bytes(2, "little", signed=False) for s in q_samples))
    print(f"saved I {len(i_samples)} samples to {out_i}")
    print(f"saved Q {len(q_samples)} samples to {out_q}")
  else:
    payload = bytes()
    for si, sq in zip(i_samples, q_samples):
      payload += bytes([(si >> 6) & 0xFF, si & 0x3F, (sq >> 6) & 0xFF, sq & 0x3F])
    out.write_bytes(payload)
    print(f"saved {len(payload)} bytes to {out}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
