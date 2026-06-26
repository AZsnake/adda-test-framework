"""Quick ADC diagnostic over UART (COM14, 921600 8N1)."""
import serial, time, sys

PORT = "COM14"
BAUD = 921600

def send(ser, frame, extra=b"", n_ack=4, label=""):
    ser.reset_input_buffer()
    ser.write(bytes(frame) + extra)
    ack = ser.read(n_ack)
    tx = " ".join(f"{b:02X}" for b in frame)
    rx = " ".join(f"{b:02X}" for b in ack) if ack else "<timeout>"
    ok = ""
    if len(ack) == 4 and ack[0] == 0xBB:
        cs = 0xBB ^ ack[1] ^ ack[2]
        ok = " OK" if cs == ack[3] and ack[1] == 0 else f" status={ack[1]:02X}"
    print(f"  [{label:<28}] TX {tx}   RX {rx}{ok}")
    return ack

def read_reg(ser, chip, addr, label=""):
    ack = send(ser, [0xAA, 0x02, chip, addr, 0x00], label=label or f"R chip{chip} 0x{addr:02X}")
    return ack[2] if len(ack) == 4 else None

def write_reg(ser, chip, addr, data, label=""):
    return send(ser, [0xAA, 0x01, chip, addr, data], label=label or f"W chip{chip} 0x{addr:02X}={data:02X}")

def adc_capture(ser, N):
    hi = (N >> 8) & 0x0F
    lo = N & 0xFF
    return send(ser, [0xAA, 0x30, 0x00, hi, lo], label=f"ADC arm N={N}")

def adc_read(ser, addr):
    hi = (addr >> 8) & 0x0F
    lo = addr & 0xFF
    a_hi = send(ser, [0xAA, 0x31, 0x00, hi, lo], label=f"  read[{addr}] hi")
    a_lo = send(ser, [0xAA, 0x32, 0x00, hi, lo], label=f"  read[{addr}] lo")
    if len(a_hi) == 4 and len(a_lo) == 4:
        return (a_hi[2] << 6) | (a_lo[2] & 0x3F)
    return None

def section(title):
    print(f"\n=== {title} ===")

with serial.Serial(PORT, BAUD, timeout=0.5) as ser:
    time.sleep(0.1); ser.reset_input_buffer()

    section("A. liveness + boot")
    send(ser, [0xAA, 0xF0, 0x00, 0x00, 0x00], label="Ping")
    send(ser, [0xAA, 0x21, 0x00, 0x00, 0x00], label="boot status (0x21)")
    send(ser, [0xAA, 0xFE, 0x00, 0x00, 0x00], label="err query (0xFE)")
    send(ser, [0xAA, 0x02, 0x02, 0x01, 0x00], label="AD9640 ChipID (expect 0x11)")

    section("B. baseline AD9640 regs (init defaults)")
    for a, name in [(0x08, "power"), (0x14, "out_mode"), (0x0D, "test_mode"),
                    (0x05, "ch_idx"), (0x09, "DCS"),    (0x0B, "clk_div"),
                    (0x15, "out_adjust"), (0x16, "clk_phase"), (0x18, "vref")]:
        read_reg(ser, 0x02, a, label=f"reg 0x{a:02X} ({name})")

    section("C. capture baseline (analog input as-is)")
    adc_capture(ser, 32)
    vals = [adc_read(ser, i) for i in range(8)]
    print(f"  samples[0..7] = {[f'0x{v:04X}' if v is not None else '??' for v in vals]}")

    section("D. force AD9640 test_mode = positive full-scale (0x0D=0x02)")
    write_reg(ser, 0x02, 0x0D, 0x02, label="W 0x0D=0x02 (pos FS)")
    write_reg(ser, 0x02, 0xFF, 0x01, label="W 0xFF=0x01 (transfer)")
    read_reg(ser, 0x02, 0x0D, label="readback 0x0D")
    adc_capture(ser, 32)
    vals = [adc_read(ser, i) for i in range(8)]
    print(f"  samples[0..7] = {[f'0x{v:04X}' if v is not None else '??' for v in vals]}")
    print("  --> expect ~0x3FFF on every sample if digital path OK")

    section("E. test_mode = checkerboard (0x0D=0x04)")
    write_reg(ser, 0x02, 0x0D, 0x04, label="W 0x0D=0x04")
    write_reg(ser, 0x02, 0xFF, 0x01, label="W 0xFF=0x01")
    adc_capture(ser, 32)
    vals = [adc_read(ser, i) for i in range(8)]
    print(f"  samples[0..7] = {[f'0x{v:04X}' if v is not None else '??' for v in vals]}")
    print("  --> expect alternating 0x2AAA / 0x1555")

    section("F. test_mode = PN9 (0x0D=0x06)")
    write_reg(ser, 0x02, 0x0D, 0x06, label="W 0x0D=0x06")
    write_reg(ser, 0x02, 0xFF, 0x01, label="W 0xFF=0x01")
    adc_capture(ser, 32)
    vals = [adc_read(ser, i) for i in range(8)]
    print(f"  samples[0..7] = {[f'0x{v:04X}' if v is not None else '??' for v in vals]}")
    print("  --> expect pseudo-random non-zero")

    section("G. restore (0x0D=0x00)")
    write_reg(ser, 0x02, 0x0D, 0x00, label="W 0x0D=0x00 (off)")
    write_reg(ser, 0x02, 0xFF, 0x01, label="W 0xFF=0x01")
    read_reg(ser, 0x02, 0x0D, label="readback 0x0D")

print("\nDone.")
