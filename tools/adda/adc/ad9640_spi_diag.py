#!/usr/bin/env python3
"""AD9640 SPI write/read diagnostic over UART (pyserial).

Tests immediate vs shadowed registers per init_tables/ad9640_init.txt.
ACK status=00 only means FPGA completed SPI; readback verifies the chip.

Usage:
  python tools/adda/adc/ad9640_spi_diag.py -p COM14
"""

from __future__ import annotations

import argparse
import sys
import time

try:
    import serial
except ImportError:
    serial = None  # type: ignore

HDR, ACK = 0xAA, 0xBB
CMD_WRITE, CMD_READ = 0x01, 0x02
CHIP_AD9640 = 0x02
DEFAULT_BAUD = 921600


def ack_checksum(status: int, data: int) -> int:
    return ACK ^ status ^ data


def build_frame(cmd: int, chip: int, addr: int, data: int) -> bytes:
    return bytes([HDR, cmd, chip, addr, data])


def transact(ser: serial.Serial, frame: bytes, timeout: float = 1.0) -> tuple[int, int]:
    ser.reset_input_buffer()
    ser.write(frame)
    ser.flush()
    old = ser.timeout
    ser.timeout = timeout
    try:
        ack = ser.read(4)
    finally:
        ser.timeout = old
    if len(ack) != 4:
        raise TimeoutError(f"ACK timeout: got {len(ack)} bytes")
    if ack[0] != ACK:
        raise ValueError(f"bad ACK header 0x{ack[0]:02X}: {ack.hex()}")
    status, data, ck = ack[1], ack[2], ack[3]
    if ack_checksum(status, data) != ck:
        raise ValueError(f"checksum fail: {ack.hex()}")
    return status, data


def write_reg(ser: serial.Serial, addr: int, data: int) -> tuple[int, int]:
    return transact(ser, build_frame(CMD_WRITE, CHIP_AD9640, addr, data))


def read_reg(ser: serial.Serial, addr: int) -> tuple[int, int]:
    return transact(ser, build_frame(CMD_READ, CHIP_AD9640, addr, 0))


def transfer_shadow(ser: serial.Serial) -> None:
    write_reg(ser, 0xFF, 0x01)


def main() -> int:
    ap = argparse.ArgumentParser(description="AD9640 SPI diagnostic")
    ap.add_argument("-p", "--port", default="COM14", help="serial port")
    ap.add_argument("-b", "--baud", type=int, default=DEFAULT_BAUD)
    args = ap.parse_args()

    if serial is None:
        print("pip install pyserial", file=sys.stderr)
        return 1

    ser = serial.Serial(args.port, args.baud, timeout=1.0)
    time.sleep(0.05)
    print(f"=== AD9640 diagnostic on {args.port} ===\n")

    def report(label: str, st: int, d: int, expect: str = "") -> None:
        ok = "OK" if st == 0 else f"FAIL status=0x{st:02X}"
        extra = f"  ({expect})" if expect else ""
        print(f"  {label}: ACK {ok}, data=0x{d:02X}{extra}")

    # Link + boot
    st, d = transact(ser, build_frame(0xF0, 0, 0, 0))
    report("Ping", st, d)
    st, d = transact(ser, build_frame(0x21, 0, 0, 0))
    report("Boot status 0x21", st, d, "data=0x70 ideal (done+clocks)")

    print("\n--- Non-shadow: Chip ID 0x01 ---")
    st, d = read_reg(ser, 0x01)
    report("Read 0x01", st, d, "expect 0x11 Rev C")

    print("\n--- Non-shadow: channel index 0x05 (boot=0x03) ---")
    st, d = read_reg(ser, 0x05)
    report("Read baseline", st, d)
    st, d = write_reg(ser, 0x05, 0x01)
    report("Write 0x05=0x01", st, d, "ACK data=00")
    st, d = read_reg(ser, 0x05)
    report("Read after write", st, d, "expect 0x01 if SPI works")
    write_reg(ser, 0x05, 0x03)
    read_reg(ser, 0x05)

    print("\n--- Immediate: SPI port config 0x00 (default 0x18) ---")
    st, d = read_reg(ser, 0x00)
    report("Read baseline", st, d)
    st, d = write_reg(ser, 0x00, 0x19)
    report("Write 0x00=0x19", st, d)
    st, d = read_reg(ser, 0x00)
    report("Read after write", st, d, "expect 0x19 if SPI works")
    write_reg(ser, 0x00, 0x18)

    print("\n--- Shadowed: output mode 0x14 ---")
    st, d = read_reg(ser, 0x14)
    report("Read active baseline", st, d, "boot transfer sets 0x01")
    st, d = write_reg(ser, 0x14, 0x55)
    report("Write shadow 0x14=0x55 (no transfer)", st, d)
    st, d = read_reg(ser, 0x14)
    report("Read active (no transfer yet)", st, d, "often still OLD value")
    transfer_shadow(ser)
    st, d = read_reg(ser, 0x14)
    report("Read after 0xFF transfer", st, d, "expect 0x55 if SPI write worked")
    write_reg(ser, 0x14, 0x01)
    transfer_shadow(ser)

    print("\n--- Shadowed: VREF 0x18 (default 0xC0) ---")
    st, d = read_reg(ser, 0x18)
    report("Read baseline", st, d)
    write_reg(ser, 0x18, 0x80)
    st, d = read_reg(ser, 0x18)
    report("Read without transfer", st, d)
    transfer_shadow(ser)
    st, d = read_reg(ser, 0x18)
    report("Read after transfer", st, d, "expect 0x80")
    write_reg(ser, 0x18, 0xC0)
    transfer_shadow(ser)

    ser.close()
    print("\n=== Summary ===")
    print("ACK status=00 means FPGA finished SPI, not that the ADC latched shadow regs.")
    print("Regs 0x08-0x18 need write then reg 0xFF=0x01 transfer before readback matches.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
