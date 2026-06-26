#!/usr/bin/env python3
"""Upload an IQ waveform file to the AD9117 wave player URAM over UART.

Frame protocol (see docs/uart_command_protocol.md §4.x):

  0x50  chunk write     AA 50 ah al cl   + 1024 bytes payload   (256 IQ pairs)
        chunk_addr[9:0] = {ah[1:0], al[7:0]}   ah=f_chip, al=f_addr, cl=f_data
        wait: BB 00 00 BB

  0x51  control sub-addr style
        f_addr=0x00 → data[0]=play_en
        f_addr=0x01 → loop_len_minus1[7:0]
        f_addr=0x02 → loop_len_minus1[15:8]
        f_addr=0x03 → loop_len_minus1[17:16]

  0x52  polarity      data[0]=swap_iq, data[1]=neg_q

File formats (auto-detected by extension, override with --endian):
  .WAVEFORM  -> big-endian   16-bit signed I/Q interleaved
  .bin       -> little-endian 16-bit signed I/Q interleaved

Usage:
  python tools/scripts/dac/wave_upload.py COM7 ../docs/wave/sine_iq_9M00_-6dBFS.WAVEFORM \\
                       --play --loop-len 262144
"""
from __future__ import annotations

import argparse
import os
import struct
import sys
import time
from pathlib import Path

try:
    import serial
except ImportError:
    sys.exit("error: pyserial not installed (pip install pyserial)")


CHUNK_BYTES = 1024
CHUNK_IQ    = CHUNK_BYTES // 4    # 256 IQ pairs per chunk
MAX_CHUNKS  = 1024                # 1 MB / 1024
URAM_WORDS  = 262144              # 256K


def detect_endian(path: Path) -> str:
    if path.suffix.upper() == ".WAVEFORM":
        return "big"
    if path.suffix.lower() == ".bin":
        return "little"
    return "little"


def read_waveform(path: Path, endian: str) -> bytes:
    raw = path.read_bytes()
    if len(raw) % 4 != 0:
        # tolerate trailing bytes by truncating (some .WAVEFORM files have padding)
        raw = raw[: (len(raw) // 4) * 4]
    if endian == "big":
        # Byte-swap each 16-bit sample: AB CD EF GH → BA DC FE HG
        # Then the FPGA sees little-endian samples natively.
        samples = struct.unpack(f">{len(raw)//2}h", raw)
        return struct.pack(f"<{len(samples)}h", *samples)
    return raw


def send_cmd(ser: serial.Serial, cmd: int, chip: int, addr: int, data: int,
             payload: bytes | None = None) -> bytes:
    frame = bytes([0xAA, cmd & 0xFF, chip & 0xFF, addr & 0xFF, data & 0xFF])
    ser.write(frame)
    if payload:
        ser.write(payload)
    ack = ser.read(4)
    if len(ack) != 4 or ack[0] != 0xBB:
        raise IOError(f"bad ack for cmd 0x{cmd:02x}: {ack.hex()}")
    if ack[1] != 0x00:
        raise IOError(f"FPGA returned status 0x{ack[1]:02x} for cmd 0x{cmd:02x}")
    return ack


def wave_disable(ser):
    send_cmd(ser, 0x51, 0x00, 0x00, 0x00)


def wave_enable(ser):
    send_cmd(ser, 0x51, 0x00, 0x00, 0x01)


def wave_set_loop_len(ser, loop_len_samples: int):
    """loop_len_samples is the actual sample count (1..262144); FPGA expects (n-1)."""
    if not 1 <= loop_len_samples <= URAM_WORDS:
        raise ValueError("loop_len out of range")
    n = loop_len_samples - 1
    send_cmd(ser, 0x51, 0x00, 0x01,  n        & 0xFF)
    send_cmd(ser, 0x51, 0x00, 0x02, (n >>  8) & 0xFF)
    send_cmd(ser, 0x51, 0x00, 0x03, (n >> 16) & 0x03)


def wave_set_polarity(ser, swap_iq: bool, neg_q: bool):
    data = (1 if swap_iq else 0) | (2 if neg_q else 0)
    send_cmd(ser, 0x52, 0x00, 0x00, data)


def wave_write_chunk(ser, chunk_idx: int, payload: bytes):
    if len(payload) != CHUNK_BYTES:
        raise ValueError(f"chunk must be {CHUNK_BYTES} bytes, got {len(payload)}")
    if not 0 <= chunk_idx < MAX_CHUNKS:
        raise ValueError("chunk_idx out of range")
    ah = (chunk_idx >> 8) & 0x03   # f_chip = high 2 bits
    al = chunk_idx & 0xFF          # f_addr = low 8 bits
    send_cmd(ser, 0x50, ah, al, 0x00, payload=payload)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("port",  help="serial port, e.g. COM7 or /dev/ttyUSB0")
    ap.add_argument("file",  type=Path, help=".WAVEFORM or .bin file")
    ap.add_argument("--baud", type=int, default=921600)
    ap.add_argument("--endian", choices=("auto", "big", "little"), default="auto",
                    help="byte order in file (default: auto by extension)")
    ap.add_argument("--loop-len", type=int, default=0,
                    help="loop length in samples (default: full file length)")
    ap.add_argument("--swap-iq", action="store_true")
    ap.add_argument("--neg-q",   action="store_true")
    ap.add_argument("--play",    action="store_true",
                    help="enable playback after upload completes")
    ap.add_argument("--no-upload", action="store_true",
                    help="skip URAM upload (only push control flags)")
    ap.add_argument("--start-chunk", type=int, default=0,
                    help="resume from this chunk index (default 0)")
    args = ap.parse_args()

    endian = detect_endian(args.file) if args.endian == "auto" else args.endian
    data = read_waveform(args.file, endian)
    n_samples = len(data) // 4
    print(f"[info] file       : {args.file.name}")
    print(f"[info] endian     : {endian} ({'byte-swap' if endian=='big' else 'native'})")
    print(f"[info] samples    : {n_samples} IQ pairs ({len(data)} bytes)")

    if n_samples == 0:
        sys.exit("error: empty file")
    if n_samples > URAM_WORDS:
        print(f"[warn] file has {n_samples} samples, URAM holds {URAM_WORDS}; "
              f"truncating to {URAM_WORDS}")
        data = data[:URAM_WORDS * 4]
        n_samples = URAM_WORDS

    loop_len = args.loop_len if args.loop_len > 0 else n_samples

    with serial.Serial(args.port, args.baud, timeout=5) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        print(f"[step] disable player")
        wave_disable(ser)

        if not args.no_upload:
            # Pad to multiple of CHUNK_BYTES with zeros
            pad = (-len(data)) % CHUNK_BYTES
            if pad:
                data += b"\x00" * pad
            n_chunks = len(data) // CHUNK_BYTES

            print(f"[step] upload {n_chunks} chunks ({len(data)} bytes) from chunk={args.start_chunk}")
            t0 = time.time()
            for i in range(args.start_chunk, n_chunks):
                payload = data[i*CHUNK_BYTES : (i+1)*CHUNK_BYTES]
                wave_write_chunk(ser, i, payload)
                if (i + 1) % 64 == 0 or i == n_chunks - 1:
                    elapsed = time.time() - t0
                    pct = 100.0 * (i + 1) / n_chunks
                    rate = (i + 1 - args.start_chunk) * CHUNK_BYTES / max(elapsed, 1e-3)
                    print(f"  chunk {i+1}/{n_chunks}  {pct:5.1f}%  {rate/1024:.1f} KiB/s")
            print(f"[done] upload took {time.time()-t0:.1f}s")

        print(f"[step] set polarity swap_iq={args.swap_iq} neg_q={args.neg_q}")
        wave_set_polarity(ser, args.swap_iq, args.neg_q)

        print(f"[step] set loop_len = {loop_len} samples")
        wave_set_loop_len(ser, loop_len)

        if args.play:
            print(f"[step] enable playback")
            wave_enable(ser)
        else:
            print(f"[info] not enabling playback (--play to enable)")

    print("[ok] done")


if __name__ == "__main__":
    main()
