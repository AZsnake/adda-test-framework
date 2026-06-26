"""AD9640 register dump + sanity check.

Quick diagnostic for when ADC captures look like garbage.  Connects via the
same UART/SPI bridge used by adda_test_gui, reads every relevant AD9640
register, and flags anything that would explain weird samples (test mode on,
wrong output format, clock divider, sync, etc.).

Usage:
    python tools/scripts/adc/ad9640_dump.py --port COM18

Optional:
    --reset    : after dump, soft-reset AD9640 (0x00 ← 0x3C self-clearing) and
                 re-dump.
    --untest   : after dump, force-clear 0x0D (test mode) and 0xFF transfer.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
import _bootstrap  # noqa: F401, E402

from rf_uart_client import CHIP_AD9640, RfAddaUart


# ---- AD9640 register map (ADI datasheet Rev. C, Table 16) ------------------
# Only the registers that matter for bring-up debug are listed here; the chip
# has many more.  Comments give the *expected* value for our use case
# (122.88 MS/s, CMOS SDR, channel A=I channel B=Q, two's complement).
AD9640_REGS = [
    (0x00, "SPI port config",       "0x18 (MSB-first, 3-wire SDIO)"),
    (0x01, "Chip ID",               "0x82 (AD9640)"),
    (0x02, "Chip grade",            "speed bin (-80/-105/-125/-150)"),
    (0x05, "Channel index",         "0x03 = both A&B (global)"),
    (0x08, "Modes",                 "0x00 = normal operation (no PD)"),
    (0x09, "Clock",                 "0x01 = duty-cycle stabiliser ON"),
    (0x0A, "Clock divider phase",   "0x00"),
    (0x0B, "Clock divider",         "0x00 = divide by 1 (122.88 MS/s)"),
    (0x0D, "Test mode",             "0x00 = OFF.  Non-zero = pattern!"),
    (0x10, "Offset adjust",         "0x00"),
    (0x14, "Output mode",           "0x01 = CMOS, two's complement, normal"),
    (0x15, "Output adjust",         "0x00 = 1.8 V CMOS standard drive"),
    (0x16, "Clock phase ctrl",      "0x00 = no DCO inversion"),
    (0x17, "DCO output delay",      "0x00 = no delay"),
    (0x18, "VREF select",           "0x04 = 2.0 Vpp default"),
    (0x19, "User pattern 1 LSB",    "(any) - only used if 0x0D selects user pattern"),
    (0x1A, "User pattern 1 MSB",    "(any)"),
    (0x1B, "User pattern 2 LSB",    "(any)"),
    (0x1C, "User pattern 2 MSB",    "(any)"),
    (0x21, "Serial control",        "0x00 = LSB output disabled"),
    (0x22, "Serial channel stat",   "0x00"),
    (0x100, "Sample rate override", "(usually unused; high regs may be unreachable via 8-bit addr)"),
]

TEST_MODE_NAMES = {
    0x0: "OFF (normal ADC data)",
    0x1: "midscale short",
    0x2: "+full-scale short",
    0x3: "-full-scale short",
    0x4: "checkerboard 0xAAA/0x555",
    0x5: "PN23 pseudo-random",
    0x6: "PN9 pseudo-random",
    0x7: "1/0 word toggle (0xFFF/0x000)",
    0x8: "user pattern 1 (regs 0x19/0x1A)",
    0x9: "user pattern 2 (regs 0x19..0x1C)",
    0xA: "user pattern alternating",
    0xF: "ramp",
}


def dump(u: RfAddaUart) -> dict[int, int]:
    print("=" * 78)
    print(f"{'Addr':>5}  {'Hex':>5}  {'Bin':>10}  {'Decoded':<28} Notes")
    print("-" * 78)
    out: dict[int, int] = {}
    for addr, name, expected in AD9640_REGS:
        try:
            v = u.spi_read(CHIP_AD9640, addr & 0xFF)
        except Exception as e:
            print(f"  {addr:#05x}  ----  ----------  {name:<28} READ FAILED ({e})")
            continue
        out[addr] = v
        bits = format(v, "08b")
        print(f"  {addr:#05x}  0x{v:02X}  {bits}  {name:<28} {expected}")
    print("=" * 78)
    return out


def analyse(regs: dict[int, int]) -> int:
    """Return 0 if clean, non-zero if suspect."""
    bad = 0
    print()
    print("---- analysis ----")

    # SPI-link sanity: 0x00 should read back 0x18 (default SPI port config,
    # MSB-first 3-wire SDIO).  Chip ID varies by AD9640 die variant; what we
    # really care about is that reads are consistent and non-default registers
    # like 0x14/0x0D look sane below.
    port_cfg = regs.get(0x00, -1)
    chip_id  = regs.get(0x01, -1)
    if port_cfg != 0x18:
        print(f"  [!!] 0x00 = 0x{port_cfg:02X} ≠ 0x18 — SPI port config not at default.")
        bad += 1
    else:
        print(f"  [ok] 0x00 = 0x18 — SPI link OK (port config at default).")
    print(f"  [..] Chip ID 0x01 = 0x{chip_id:02X} (record this for your board; varies by AD9640 grade)")

    tm = regs.get(0x0D, -1)
    if tm < 0:
        print("  [!!] 0x0D unreadable.")
        bad += 1
    elif tm == 0:
        print(f"  [ok] Test mode 0x0D = 0x00 (normal ADC data).")
    else:
        kind = TEST_MODE_NAMES.get(tm & 0x0F, "unknown")
        gen_on = (tm >> 6) & 0x03  # bits[7:6]: PN/user generator enable
        print(f"  [!!] 0x0D = 0x{tm:02X} — test mode ON: {kind}, gen[7:6]=0x{gen_on:X}")
        print("       → This is exactly why captures look like a digital pattern.")
        print("       → Run with --untest to clear, or write 0x00 to 0x0D then 0x01 to 0xFF.")
        bad += 1

    out_mode = regs.get(0x14, -1)
    if out_mode >= 0:
        # bits[1:0]: output data format: 00=offset binary, 01=two's complement
        # bit[2]:    output invert
        # bits[7:6]: output interface: 00=CMOS, 01=LVDS ANSI, 10=LVDS RSDS
        # bit[3]:    DDR enable for CMOS (some variants)
        fmt = out_mode & 0x03
        invert = (out_mode >> 2) & 0x01
        iface = (out_mode >> 6) & 0x03
        ddr = (out_mode >> 3) & 0x01
        print(f"  [..] 0x14 = 0x{out_mode:02X}: iface={['CMOS','LVDS-ANSI','LVDS-RSDS','reserved'][iface]}, "
              f"DDR={ddr}, invert={invert}, fmt={['offsetbin','2sC','GrayC','reserved'][fmt]}")
        if iface != 0:
            print(f"       [!!] FPGA is wired for CMOS but AD9640 says iface≠CMOS. Capture WILL fail.")
            bad += 1
        if ddr != 0:
            print(f"       [!!] DDR=1 but FPGA does single-edge SDR capture. Throws every other sample.")
            bad += 1
        if fmt != 1:
            print(f"       [!!] Expected AD9640 two's-complement output (fmt=01) for current FPGA build.")
            bad += 1

    clkdiv = regs.get(0x0B, -1)
    if clkdiv > 0:
        print(f"  [!!] 0x0B = 0x{clkdiv:02X} — clock divider ON. Sample rate is 122.88/(div+1) MS/s.")
        bad += 1
    elif clkdiv == 0:
        print(f"  [ok] 0x0B = 0x00 — no clock divide (fs = clock_in = 122.88 MS/s).")

    pwr = regs.get(0x08, -1)
    if pwr > 0:
        print(f"  [!!] 0x08 = 0x{pwr:02X} — power-down bits non-zero.")
        bad += 1

    print()
    if bad == 0:
        print("Result: AD9640 looks correctly configured.")
        print("        If captures still look wrong, the issue is the DCOA/data")
        print("        capture path on the FPGA side (timing — see XDC + IDELAY).")
    else:
        print(f"Result: {bad} suspicious register(s).  Fix these and re-capture.")
    return bad


def clear_test_mode(u: RfAddaUart) -> None:
    print("\n>> writing 0x0D ← 0x00 (clear test mode)")
    u.spi_write(CHIP_AD9640, 0x0D, 0x00)
    print(">> writing 0xFF ← 0x01 (transfer / commit buffered regs)")
    u.spi_write(CHIP_AD9640, 0xFF, 0x01)


def soft_reset(u: RfAddaUart) -> None:
    print("\n>> writing 0x00 ← 0x3C (soft reset, self-clearing)")
    u.spi_write(CHIP_AD9640, 0x00, 0x3C)
    print(">> writing 0xFF ← 0x01 (transfer)")
    u.spi_write(CHIP_AD9640, 0xFF, 0x01)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--port", required=True, help="serial port, e.g. COM18 or /dev/ttyUSB0")
    p.add_argument("--baud", type=int, default=921600)
    p.add_argument("--reset",  action="store_true", help="soft-reset AD9640 then re-dump")
    p.add_argument("--untest", action="store_true", help="clear 0x0D and commit, then re-dump")
    args = p.parse_args()

    u = RfAddaUart(args.port, baud=args.baud)
    try:
        print(f"opened {args.port} @ {args.baud}")
        regs = dump(u)
        analyse(regs)

        if args.untest:
            clear_test_mode(u)
        if args.reset:
            soft_reset(u)
        if args.untest or args.reset:
            print("\n---- post-action re-dump ----")
            regs = dump(u)
            analyse(regs)
    finally:
        u.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
