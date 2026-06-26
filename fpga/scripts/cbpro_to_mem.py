#!/usr/bin/env python3
"""
cbpro_to_mem.py — Convert chip register tables to $readmemh-loadable boot ROM image.

Sources:
  * SI5340: ClockBuilder Pro CSV-style script export (`.txt`), with preamble /
    delay / main-block / postamble sections.
  * AD9640 / AD9117: plain CSV (`addr,data` per line, `#` and blank lines ignored).

Entry encoding (32-bit, one entry per line):

    [31:28] opcode  0=WRITE, 1=DELAY, 2=WAIT_LOL, 0xF=EOF
    [27:24] chip    1=SI5340, 2=AD9640, 3=AD9117  (same as UART chip ID;
                    0 reserved for system/none)
    [23:16] page    SI5340 register address high byte; 0 for AD9640/AD9117
    [15: 8] addr    register address low byte (or delay-index for DELAY)
    [ 7: 0] data    register data (don't care for DELAY/WAIT_LOL/EOF)

`boot_fsm` is expected to:
  * issue an SPI write of {page, addr, data} for opcode=WRITE
    (for SI5340, auto-emit `reg[0x01] = page` whenever page changes)
  * pause N cycles on opcode=DELAY, where N = delay_table[ data[7:0] ]
  * stall until pad_si5340_lolb=1 on opcode=WAIT_LOL (with 100 ms timeout)
  * halt on opcode=EOF (chip table boundary; final EOF stops boot)

Usage:
    python fpga/scripts/cbpro_to_mem.py --chip si5340 INPUT.txt -o si5340_init.mem
    python fpga/scripts/cbpro_to_mem.py --chip ad9640 INPUT.csv -o ad9640_init.mem
    python fpga/scripts/cbpro_to_mem.py --concat si5340_init.mem ad9640_init.mem ad9117_init.mem \\
                    -o boot_rom.mem
"""

import argparse
import re
import sys
from pathlib import Path

CHIP_ID = {"si5340": 0x1, "ad9640": 0x2, "ad9117": 0x3}

OP_WRITE    = 0x0
OP_DELAY    = 0x1
OP_WAIT_LOL = 0x2
OP_EOF      = 0xF

# Delay-index table — boot_fsm must mirror this (in cycles @ boot clock).
# Index 0 is reserved for the SI5340 post-preamble 300 ms calibration delay.
DELAY_INDEX = {
    0: "300 ms (SI5340 PLL calibration)",
    1: "10 ms  (chip POR settle)",
}

ADDR_RE = re.compile(r"^\s*0x([0-9A-Fa-f]+)\s*,\s*0x([0-9A-Fa-f]+)\s*$")


def encode(opcode: int, chip: int, page: int, addr: int, data: int) -> str:
    """Pack a single 32-bit entry as 8-hex-digit string."""
    assert 0 <= opcode <= 0xF
    assert 0 <= chip   <= 0xF
    assert 0 <= page   <= 0xFF
    assert 0 <= addr   <= 0xFF
    assert 0 <= data   <= 0xFF
    word = (opcode << 28) | (chip << 24) | (page << 16) | (addr << 8) | data
    return f"{word:08x}"


def parse_si5340(path: Path) -> list[str]:
    """Parse ClockBuilder Pro `.txt` script for SI5340.

    Follows the Skyworks AN926 init sequence:
        preamble → 300 ms delay → main block → postamble → WAIT_LOL → page reset

    Note WAIT_LOL goes AFTER postamble — outputs must be re-enabled and PLL
    re-cal triggered first, otherwise the chip cannot lock and WAIT_LOL is
    guaranteed to time out.  An earlier version placed WAIT_LOL between main
    and postamble; that was wrong and produced err=0x10 every boot.

    A final `reg[0x01]=0x00` write returns SI5340 to page 0, so subsequent
    UART single-register reads (which don't touch the PAGE_SEL register)
    address page 0 by default (PartNumber, status, etc.).
    """
    chip = CHIP_ID["si5340"]
    out: list[str] = []
    delay_inserted = False
    in_postamble = False

    with path.open(encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line:
                continue

            if line.startswith("#"):
                low = line.lower()
                if "delay 300 msec" in low and not delay_inserted:
                    out.append(encode(OP_DELAY, chip, 0x00, 0x00, 0x00))
                    delay_inserted = True
                elif "start configuration postamble" in low:
                    in_postamble = True
                continue

            if line.lower().startswith("address"):
                continue   # CSV header

            m = ADDR_RE.match(line)
            if not m:
                print(f"warn: {path.name}:{lineno}: unrecognised line: {line!r}",
                      file=sys.stderr)
                continue

            addr16 = int(m.group(1), 16)
            data8  = int(m.group(2), 16)
            page   = (addr16 >> 8) & 0xFF
            addr   = addr16 & 0xFF
            out.append(encode(OP_WRITE, chip, page, addr, data8))

    # AFTER postamble: wait for PLL lock (per AN926 step 6).
    out.append(encode(OP_WAIT_LOL, chip, 0x00, 0x00, 0x00))

    # Restore page register to 0 so subsequent UART reads default to page 0
    # (avoids the "read returns 0 because we're stuck on page 0x0B" trap).
    out.append(encode(OP_WRITE, chip, 0x00, 0x01, 0x00))

    # Final EOF
    out.append(encode(OP_EOF, chip, 0x00, 0x00, 0x00))

    if not delay_inserted:
        print(f"warn: {path.name}: no 'Delay 300 msec' marker found — "
              "PLL calibration delay NOT inserted", file=sys.stderr)
    if not in_postamble:
        print(f"warn: {path.name}: postamble section not seen — output may be "
              "missing PLL re-lock writes", file=sys.stderr)

    return out


def parse_generic_csv(path: Path, chip_name: str) -> list[str]:
    """Parse plain `addr,data` CSV for AD9640 / AD9117 (no preamble/page)."""
    chip = CHIP_ID[chip_name]
    out: list[str] = []
    with path.open(encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.lower().startswith("address"):
                continue
            m = ADDR_RE.match(line)
            if not m:
                print(f"warn: {path.name}:{lineno}: unrecognised line: {line!r}",
                      file=sys.stderr)
                continue
            addr = int(m.group(1), 16)
            data = int(m.group(2), 16)
            if addr > 0xFF:
                print(f"warn: {path.name}:{lineno}: addr 0x{addr:X} > 0xFF; "
                      "AD9640/AD9117 use 8-bit addresses only", file=sys.stderr)
                addr &= 0xFF
            out.append(encode(OP_WRITE, chip, 0x00, addr, data))
    out.append(encode(OP_EOF, chip, 0x00, 0x00, 0x00))
    return out


def write_mem(entries: list[str], path: Path, header: str) -> None:
    with path.open("w", encoding="ascii", newline="\n") as fh:
        fh.write(f"// {header}\n")
        fh.write("// opcode[3:0] | chip[3:0] | page[7:0] | addr[7:0] | data[7:0]\n")
        for e in entries:
            fh.write(e + "\n")


def concat_mems(inputs: list[Path], output: Path) -> None:
    """Concatenate per-chip .mem files: strip all but the final EOF entry."""
    merged: list[str] = []
    for idx, src in enumerate(inputs):
        is_last = (idx == len(inputs) - 1)
        with src.open(encoding="ascii") as fh:
            lines = [ln.strip() for ln in fh
                     if ln.strip() and not ln.lstrip().startswith("//")]
        if not lines:
            continue
        # Drop trailing EOF unless this is the last source
        if not is_last and (int(lines[-1], 16) >> 28) == OP_EOF:
            lines = lines[:-1]
        merged.extend(lines)
    write_mem(merged, output,
              f"boot_rom concatenated from: {', '.join(p.name for p in inputs)}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", nargs="?", type=Path,
                    help="input table (ClockBuilderPro .txt for SI5340, "
                         "CSV for AD9640/AD9117)")
    ap.add_argument("-o", "--output", type=Path, required=True,
                    help="output .mem path")
    ap.add_argument("--chip", choices=list(CHIP_ID.keys()),
                    help="chip type (required unless --concat)")
    ap.add_argument("--concat", nargs="+", type=Path, metavar="MEM",
                    help="concatenate per-chip .mem files into a boot ROM image")
    args = ap.parse_args()

    if args.concat:
        concat_mems(args.concat, args.output)
        print(f"wrote {args.output} (concatenated {len(args.concat)} files)")
        return 0

    if args.input is None or args.chip is None:
        ap.error("--chip and INPUT are required (or use --concat)")

    if args.chip == "si5340":
        entries = parse_si5340(args.input)
    else:
        entries = parse_generic_csv(args.input, args.chip)

    write_mem(entries, args.output,
              f"generated from {args.input.name} (chip={args.chip})")
    n_write = sum(1 for e in entries if (int(e, 16) >> 28) == OP_WRITE)
    print(f"wrote {args.output}: {len(entries)} entries ({n_write} writes, "
          f"{len(entries) - n_write} control)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
