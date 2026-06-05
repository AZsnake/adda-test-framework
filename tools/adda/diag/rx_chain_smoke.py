"""End-to-end smoke test for the ADC IQ RX chain (rf_adda_top phase-4).

Exercises every opcode added for the digital RX path against a real board:
  0xF2  global reset                 -> deterministic starting state
  0x45  RX cfg (dec/mode/bypass)     -> snapshot vs stream, IQ/FIR bypass
  0x44  NCO frequency word           -> DDC mixer tune
  0x46/0x47/0x48/0x49  IQ balance   -> coefficient + DC offset writes
  0x30  ADC arm  + 0x33 burst read  -> snapshot path (IQ from rx_chain output)
  0x34  stream (bounded + continuous) with XOR8 verification

Usage:
  python tools/adda/diag/rx_chain_smoke.py --port COM7

The script does NOT need the FPGA to be receiving a real RF input — even with
nothing wired into the analog front end, the snapshot/stream paths should
return the AD9640 DC midscale code (~0 after the chain's offset subtraction)
and the XOR8 of every emitted byte must match the FPGA-computed trailer.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import _bootstrap  # noqa: F401, E402

from rf_uart_client import (  # noqa: E402
    DEFAULT_ADC_FS_HZ,
    RfAddaUart,
    samples_to_signed,
)


def banner(msg: str) -> None:
    print()
    print(f"=== {msg} ===")


def fmt_iq_stats(name: str, i_samples: list[int], q_samples: list[int]) -> None:
    si = samples_to_signed(i_samples)
    sq = samples_to_signed(q_samples)
    if not si:
        print(f"  {name}: <empty>")
        return
    i_mean = sum(si) / len(si)
    q_mean = sum(sq) / len(sq)
    i_pkpk = max(si) - min(si)
    q_pkpk = max(sq) - min(sq)
    print(
        f"  {name}: N={len(si)}  I mean={i_mean:+.2f} pkpk={i_pkpk}  "
        f"Q mean={q_mean:+.2f} pkpk={q_pkpk}"
    )


def run(port: str, n_snapshot: int, stream_ms: int, nco_khz: float, adc_fs_hz: float) -> int:
    print(f"Opening {port}...")
    u = RfAddaUart(port)

    banner("0xF2 global reset")
    u.transact(bytes([0xAA, 0xF2, 0xFF, 0x00, 0x00]))
    time.sleep(0.05)
    # Wait for boot_fsm to redo SI5340 init (10 ms reset + ~20 ms boot).
    for _ in range(20):
        time.sleep(0.05)
        st = u.boot_status()
        if (st >> 6) & 1:  # done bit
            break
    print(f"  boot status byte after reset = 0x{st:02X} (expect done bit set)")

    banner("Baseline RX cfg: dec=1x, snapshot, bypass=on")
    ack = u.set_rx_config(dec_ratio=0, capture_mode=0, fir_bypass=True, iq_bypass=True)
    print(f"  0x45 ACK data = 0x{ack:02X}")

    banner(f"Snapshot {n_snapshot} samples (raw — bypasses on)")
    si, sq = u.capture_iq(n_snapshot)
    fmt_iq_stats("bypass", si, sq)

    banner(f"Set NCO to {nco_khz:.2f} kHz and enable mixing + IQ balance + FIR")
    word, actual = u.set_nco_frequency_hz(nco_khz * 1e3, adc_fs_hz=adc_fs_hz)
    print(f"  NCO word=0x{word:04X}  actual={actual/1e3:.3f} kHz")
    # Apply a non-trivial IQ correction so we can prove the wires are alive.
    u.set_iq_op1(0x4000)        # 1.0 in Q2.14
    u.set_iq_op2(0x0100)        # +0.015625 cross-coupling
    u.set_iq_offset_i(16)       # ~+0.2% FS DC bias
    u.set_iq_offset_q(-8)
    ack = u.set_rx_config(dec_ratio=0, capture_mode=0, fir_bypass=False, iq_bypass=False)
    print(f"  0x45 ACK after enabling chain = 0x{ack:02X}")

    banner(f"Snapshot {n_snapshot} samples (chain active)")
    si, sq = u.capture_iq(n_snapshot)
    fmt_iq_stats("chain", si, sq)

    banner(f"0x34 bounded stream — 256 samples (1024 byte payload + XOR8)")
    t0 = time.perf_counter()
    si, sq = u.adc_stream_iq(256)
    dt = time.perf_counter() - t0
    print(f"  bounded: {len(si)} IQ samples in {dt*1e3:.1f} ms")
    fmt_iq_stats("bounded", si, sq)

    banner(f"0x34 continuous stream for ~{stream_ms} ms (host-initiated stop)")
    u.adc_stream_start_continuous()
    deadline = time.perf_counter() + stream_ms / 1000.0
    buf = bytearray()
    while time.perf_counter() < deadline:
        buf.extend(u.adc_stream_read_bytes(4096, timeout=0.05))
    pre_stop_bytes = len(buf)
    tail, (status, xor8_rx, _ck) = u.adc_stream_stop_and_drain()
    buf.extend(tail)
    xor_calc = 0
    for b in buf:
        xor_calc ^= b
    print(f"  continuous: {pre_stop_bytes} bytes before stop, "
          f"{len(tail)} drain bytes, status=0x{status:02X}")
    print(f"  XOR8 calc=0x{xor_calc:02X}  fpga=0x{xor8_rx:02X}  "
          f"{'OK' if xor_calc == xor8_rx else 'MISMATCH'}")
    rate = len(buf) / max(1e-6, stream_ms / 1000.0)
    print(f"  effective byte rate ≈ {rate/1024:.1f} kB/s "
          f"(theoretical UART cap ≈ 92.16 kB/s @ 921600 8N1)")

    banner("Reset IQ to identity + bypasses on")
    u.set_iq_op1(0x4000)
    u.set_iq_op2(0)
    u.set_iq_offset_i(0)
    u.set_iq_offset_q(0)
    u.set_nco_freq_word(0)
    u.set_rx_config(dec_ratio=0, capture_mode=0, fir_bypass=True, iq_bypass=True)
    print("  done — board left in baseline state")

    ok = (status == 0 and xor_calc == xor8_rx)
    u.close()
    return 0 if ok else 1


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--port", required=True, help="serial port, e.g. COM7 or /dev/ttyUSB0")
    p.add_argument("--n-snapshot", type=int, default=1024)
    p.add_argument("--stream-ms", type=int, default=200,
                   help="continuous-stream duration in milliseconds")
    p.add_argument("--nco-khz", type=float, default=1000.0,
                   help="NCO frequency in kHz (default 1000 = 1 MHz)")
    p.add_argument("--adc-fs-hz", type=float, default=DEFAULT_ADC_FS_HZ,
                   help="ADC sample rate for NCO word conversion")
    args = p.parse_args()
    return run(args.port, args.n_snapshot, args.stream_ms, args.nco_khz, args.adc_fs_hz)


if __name__ == "__main__":
    sys.exit(main())
