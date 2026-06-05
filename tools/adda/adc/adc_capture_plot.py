#!/usr/bin/env python3
"""
adc_capture_plot.py — UART ADC snapshot capture, read-back, and plot (CLI).

Talks to rf_adda_top over 921600 8N1 using docs/uart_command_protocol.md.
Shared protocol implementation: tools/adda/lib/rf_uart_client.py
GUI version: tools/adda/gui/adda_test_gui_qt.py

Examples:
  python tools/adda/adc/adc_capture_plot.py -p COM3 -n 256
  python tools/adda/adc/adc_capture_plot.py -p COM3 -n 1024 --save-csv capture.csv -o wave.png
  python tools/adda/adc/adc_capture_plot.py --list-ports

Dependencies (see tools/adda/requirements.txt):
  pip install -r tools/adda/requirements.txt
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

try:
    import matplotlib.pyplot as plt
except ImportError:
    plt = None

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import _bootstrap  # noqa: F401, E402

from rf_uart_client import (
    ADC_CHAN_I,
    ADC_CHAN_Q,
    DEFAULT_ADC_FS_HZ,
    MAX_SAMPLES,
    RfAddaUart,
    decode_stream_iq_payload,
    export_matlab_ifft_bin,
    samples_to_signed,
    list_serial_ports,
    port_descriptions,
)


def save_csv(path: Path, samples: list[int]) -> None:
    with path.open("w", encoding="utf-8") as f:
        f.write("index,sample14,sample_hex\n")
        for i, s in enumerate(samples):
            f.write(f"{i},{s},0x{(int(s) & 0x3FFF):04X}\n")
    print(f"saved CSV: {path}")


def plot_samples(
    samples: list[int],
    *,
    title: str,
    output: Path | None,
    show: bool,
    fs_hz: float,
) -> None:
    if plt is None:
        raise RuntimeError("matplotlib not installed: pip install matplotlib")

    n = len(samples)
    dt_us = 1e6 / fs_hz if fs_hz > 0 else 1.0
    x = [i * dt_us for i in range(n)]
    y = samples

    fig, axes = plt.subplots(2, 1, figsize=(12, 7), constrained_layout=True)

    axes[0].plot(x, y, linewidth=0.8, color="#1f77b4")
    axes[0].set_xlabel("time (µs)")
    axes[0].set_ylabel("code (14-bit signed)")
    axes[0].set_title(title)
    axes[0].grid(True, alpha=0.3)

    if n > 1:
        axes[1].plot(x[1:], [y[i] - y[i - 1] for i in range(1, n)], linewidth=0.8, color="#d62728")
    axes[1].set_xlabel("time (µs)")
    axes[1].set_ylabel("first difference")
    axes[1].set_title("Δ between consecutive samples")
    axes[1].grid(True, alpha=0.3)

    uniq = len(set(samples))
    fig.suptitle(
        f"N={n}  unique={uniq}  min={min(samples)}  max={max(samples)}  "
        f"(14-bit signed decode after UART unpack)",
        fontsize=10,
    )

    if output is not None:
        fig.savefig(output, dpi=150)
        print(f"saved plot: {output}")

    if show:
        plt.show()
    else:
        plt.close(fig)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Capture ADC snapshot over UART and plot samples.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("-p", "--port", help="serial port (e.g. COM3, /dev/ttyUSB0)")
    p.add_argument("-b", "--baud", type=int, default=921600, help="baud rate")
    p.add_argument(
        "-n",
        "--samples",
        type=int,
        default=256,
        help=f"sample count 1..{MAX_SAMPLES} (0 → {MAX_SAMPLES})",
    )
    p.add_argument("--save-csv", type=Path, metavar="FILE", help="write index,sample CSV")
    p.add_argument(
        "--save-matlab-bin",
        type=Path,
        metavar="FILE",
        help="write adc_ifft_analysis.m-compatible int16 BIN",
    )
    p.add_argument(
        "--fs",
        type=float,
        default=DEFAULT_ADC_FS_HZ,
        metavar="HZ",
        help="ADC sample rate in Hz (used for the time-axis on the plot)",
    )
    p.add_argument("-o", "--output", type=Path, metavar="PNG", help="save figure to file")
    p.add_argument(
        "--no-show",
        action="store_true",
        help="do not open interactive plot window",
    )
    p.add_argument("--list-ports", action="store_true", help="list serial ports and exit")
    p.add_argument("-q", "--quiet", action="store_true", help="less progress output")
    p.add_argument(
        "--channel",
        choices=("a", "i", "b", "q", "both", "iq"),
        default="a",
        help="ADC channel: a/i (channel A = I, default), b/q (channel B = Q), both/iq (dual-channel I+Q)",
    )
    p.add_argument(
        "--nco-hz",
        type=float,
        default=None,
        metavar="HZ",
        help="program RX-chain NCO before arming",
    )
    p.add_argument(
        "--bram-src",
        choices=("snapshot", "stream"),
        default="snapshot",
        help="capture mode selection (legacy option name kept)",
    )
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.list_ports:
        ports = port_descriptions()
        if not ports:
            print("no serial ports found")
            return 0
        for dev, desc in ports:
            print(f"  {dev}\t{desc}")
        return 0

    if not args.port:
        print("error: -p/--port is required (or use --list-ports)", file=sys.stderr)
        return 2

    n = args.samples
    if n == 0:
        n = MAX_SAMPLES

    chan_arg = args.channel.lower()
    dual = chan_arg in ("both", "iq")
    primary_chan = ADC_CHAN_Q if chan_arg in ("b", "q") else ADC_CHAN_I
    src_mode = args.bram_src

    try:
        with RfAddaUart(args.port, baud=args.baud) as uart:
            if args.nco_hz is not None:
                word, actual = uart.set_nco_frequency_hz(args.nco_hz, adc_fs_hz=args.fs)
                if not args.quiet:
                    print(f"NCO freq word={word} (actual {actual:.1f} Hz)")
            uart.set_rx_config(
                dec_ratio=0,
                capture_mode=1 if src_mode == "stream" else 0,
                fir_bypass=True,
                iq_bypass=True,
            )
            if not args.quiet:
                print(f"capture mode: {src_mode}")

            t0 = time.perf_counter()
            if not args.quiet:
                print(f"ADC arm N={n} ...", end=" ", flush=True)
            uart.adc_arm(n)
            if not args.quiet:
                print(f"done ({time.perf_counter() - t0:.2f}s)")
            t1 = time.perf_counter()
            if src_mode == "stream":
                if not args.quiet:
                    print(f"stream read IQ N={n} ...", end=" ", flush=True)
                payload = uart.adc_stream_bytes(n)
                samples_i, samples_q = decode_stream_iq_payload(payload)
                samples_i = samples_to_signed(samples_i)
                samples_q = samples_to_signed(samples_q)
                if dual:
                    samples = samples_i
                else:
                    samples = samples_i if primary_chan == ADC_CHAN_I else samples_q
            else:
                if dual:
                    if not args.quiet:
                        print(f"burst read I+Q N={n} ...", end=" ", flush=True)
                    samples_i = uart.adc_read_burst(n, channel=ADC_CHAN_I)
                    samples_q = uart.adc_read_burst(n, channel=ADC_CHAN_Q)
                    samples_i = samples_to_signed(samples_i)
                    samples_q = samples_to_signed(samples_q)
                    samples = samples_i  # primary view for legacy plotting code
                else:
                    if not args.quiet:
                        label = "I" if primary_chan == ADC_CHAN_I else "Q"
                        print(f"burst read {label} N={n} ...", end=" ", flush=True)
                    samples = uart.adc_read_burst(n, channel=primary_chan)
                    samples = samples_to_signed(samples)
                    samples_i = samples if primary_chan == ADC_CHAN_I else None
                    samples_q = samples if primary_chan == ADC_CHAN_Q else None
            if not args.quiet:
                print(f"done ({time.perf_counter() - t1:.2f}s)")
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    if args.save_csv:
        if dual:
            # dual-channel CSV: i,q columns
            with args.save_csv.open("w", encoding="utf-8") as f:
                f.write("index,i_sample14,q_sample14\n")
                for idx, (si, sq) in enumerate(zip(samples_i, samples_q)):
                    f.write(f"{idx},{si},{sq}\n")
            print(f"saved CSV: {args.save_csv}")
        else:
            save_csv(args.save_csv, samples)
    if args.save_matlab_bin:
        export_matlab_ifft_bin(args.save_matlab_bin, samples)
        print(f"saved MATLAB BIN: {args.save_matlab_bin}")

    show = not args.no_show and args.output is None
    if args.output is not None or show:
        try:
            plot_samples(
                samples,
                title=f"ADC capture ({args.port}, N={n})",
                output=args.output,
                show=show,
                fs_hz=args.fs,
            )
        except RuntimeError as e:
            print(f"error: {e}", file=sys.stderr)
            return 1
    elif not args.save_csv and not args.save_matlab_bin:
        uniq = len(set(samples))
        print(f"samples={n} unique={uniq} min={min(samples)} max={max(samples)}")
        print("first 8:", [f"0x{s:03X}" for s in samples[:8]])

    return 0


if __name__ == "__main__":
    sys.exit(main())
