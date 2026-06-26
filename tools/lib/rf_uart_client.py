"""UART client for rf_adda_top (docs/uart_command_protocol.md)."""

from __future__ import annotations

import re
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    serial = None  # type: ignore
    list_ports = None

if TYPE_CHECKING:
    from serial.tools.list_ports_common import ListPortInfo

# --- protocol constants -------------------------------------------------------
CMD_HDR = 0xAA
ACK_HDR = 0xBB
CMD_WRITE = 0x01
CMD_READ = 0x02
CMD_PING = 0xF0
CMD_FW_VERSION = 0xF1
CMD_GLOBAL_RESET = 0xF2
CMD_ERROR_QUERY = 0xFE
CMD_BOOT_STATUS = 0x21
CMD_BOOT_RUN = 0x20
CMD_ADC_ARM = 0x30
CMD_ADC_READ_HI = 0x31
CMD_ADC_READ_LO = 0x32
CMD_ADC_READ_BURST = 0x33
CMD_ADC_STREAM = 0x34
CMD_DAC_TONE = 0x40
CMD_DAC_WAVE = 0x41
CMD_DAC_FREQ = 0x42
CMD_DAC_AMP = 0x43
CMD_NCO_FREQ = 0x44   # digital DDC frequency tuning word (16-bit, hi/lo split)
CMD_RX_CFG = 0x45

# DCLKIO fixed phase: board dip switches pad_input_s[2:0] (ON=high). UART 0x4A
# dynamic phase shift was removed; see docs/dac_ddr_timing_bringup.md §3.
# Each entry: (index, phase_deg, switch_bits "210" MSB..LSB)
DAC_DCLK_DIP_PHASES: list[tuple[int, int, str]] = [
    (0, 90, "000"),
    (1, 135, "001"),
    (2, 180, "010"),
    (3, 225, "011"),
    (4, 270, "100"),
    (5, 315, "101"),
    (6, 360, "110"),
]


def dac_dclk_dip_switch_hint(index: int) -> str:
    """Human-readable dip-switch positions for pad_input_s[2:0]."""
    idx = 0 if index == 7 else max(0, min(6, int(index)))
    _, deg, bits = DAC_DCLK_DIP_PHASES[idx]
    sw = []
    for i, b in enumerate(bits):
        sw.append(f"SW{2 - i}={'ON' if b == '1' else 'OFF'}")
    return f"pad_input_s[2:0]={bits} ({deg}°): " + ", ".join(sw)


# RX FIR coefficient banks (0x45 bit[6:5]) — see rf_filter14.v
FIR_SEL_FS8 = 0      # fc ~ Fs/8  (default)
FIR_SEL_FS16 = 1     # fc ~ Fs/16 (narrow)
FIR_SEL_FS4 = 2      # fc ~ Fs/4  (wide)
FIR_SEL_ALLPASS = 3  # all-pass (center tap only, flat)
FIR_SEL_NAMES = {
    FIR_SEL_FS8: "Fs/8 (default)",
    FIR_SEL_FS16: "Fs/16 (narrow)",
    FIR_SEL_FS4: "Fs/4 (wide)",
    FIR_SEL_ALLPASS: "all-pass",
}
CMD_IQ_OP1 = 0x46
CMD_IQ_OP2 = 0x47
CMD_IQ_OFF_I = 0x48
CMD_IQ_OFF_Q = 0x49
CMD_WAVE_WRITE = 0x50   # waveform chunk write: 5B header + 1024B payload
CMD_WAVE_CTRL  = 0x51   # play_en / loop_len sub-address writes
CMD_WAVE_FLAGS = 0x52   # swap_iq / neg_q polarity flags

# Waveform player constants
WAVE_CHUNK_BYTES = 1024
WAVE_CHUNK_IQ    = 256
WAVE_MAX_CHUNKS  = 1024
WAVE_URAM_WORDS  = 262144

ADC_CHAN_I = 0  # ADC channel A = I
ADC_CHAN_Q = 1  # ADC channel B = Q
CAPTURE_MODE_SNAPSHOT = 0
CAPTURE_MODE_STREAM = 1

CHIP_SYS = 0x00
CHIP_SI5340 = 0x01
CHIP_AD9640 = 0x02
CHIP_AD9117 = 0x03

STATUS_OK = 0x00
STATUS_NAMES = {
    0x00: "OK",
    0x01: "unknown command",
    0x02: "invalid chip ID",
    0x03: "SPI timeout",
    0x04: "checksum error",
    0x05: "boot or ADC busy",
}

MAX_SAMPLES = 16384  # FPGA BRAM depth; wire field is 14-bit (0 → 16384)
DEFAULT_BAUD = 921600
DEFAULT_ADC_FS_HZ = 122_880_000.0   # AD9640 sample rate = SI5340 OUT0
DAC_TONE_FREQ_HZ = 160_000.0
DEFAULT_SYS_CLK_HZ = 122_880_000.0  # FPGA sys_clk after clk_wiz_0 MMCM (19.2 MHz in → 122.88 MHz out)
# dac_wave_player outputs I and Q on alternate sys_clk cycles, so each channel's
# effective sample rate is sys_clk / 2.  Use this constant when generating waveform
# files with gen_sine_iq_waveform.py (--fs-hz DAC_WAVE_FS_HZ).
DAC_WAVE_FS_HZ = 61_440_000.0

DAC_WAVE_SINE = 0
DAC_WAVE_SQUARE = 1
DAC_WAVE_TRIANGLE = 2
DAC_WAVE_RAMP = 3
DAC_WAVE_DC_TEST = 4
DAC_WAVE_NAME_TO_CODE = {
    "sine": DAC_WAVE_SINE,
    "square": DAC_WAVE_SQUARE,
    "triangle": DAC_WAVE_TRIANGLE,
    "ramp": DAC_WAVE_RAMP,
    "dc_test": DAC_WAVE_DC_TEST,
    "dc": DAC_WAVE_DC_TEST,
    "sin": DAC_WAVE_SINE,
    "sq": DAC_WAVE_SQUARE,
    "tri": DAC_WAVE_TRIANGLE,
    "正弦": DAC_WAVE_SINE,
    "方波": DAC_WAVE_SQUARE,
    "三角波": DAC_WAVE_TRIANGLE,
    "锯齿波": DAC_WAVE_RAMP,
    "直流测试": DAC_WAVE_DC_TEST,
}
DAC_WAVE_CODE_TO_NAME = {v: k for k, v in DAC_WAVE_NAME_TO_CODE.items()}


def list_serial_ports() -> list[str]:
    if list_ports is None:
        return []
    return [p.device for p in list_ports.comports()]


def port_descriptions() -> list[tuple[str, str]]:
    if list_ports is None:
        return []
    out: list[tuple[str, str]] = []
    for p in list_ports.comports():
        out.append((p.device, p.description or ""))
    return out


def _serial_kwargs(baud: int, timeout: float) -> dict:
    """Windows-friendly 8N1 (no HW flow control)."""
    kw: dict = {
        "port": None,
        "baudrate": baud,
        "timeout": timeout,
        "bytesize": serial.EIGHTBITS,
        "parity": serial.PARITY_NONE,
        "stopbits": serial.STOPBITS_ONE,
        "rtscts": False,
        "dsrdtr": False,
        "xonxoff": False,
    }
    return kw


def format_serial_error(exc: BaseException, port: str) -> str:
    msg = str(exc).strip()
    hints: list[str] = []
    low = msg.lower()
    if "not functioning" in low or "permissionerror" in type(exc).__name__.lower():
        hints.append(
            f"「{port}」在本机无法打开（常见于 USB 双串口设备的无效口，如 COM10/COM11）。"
        )
        hints.append("请改选带 CH340/CP210/FTDI 且探测为 ✓ 的端口（ADDA 板 UART 多为 CH340）。")
        hints.append("并关闭占用该口的其他程序（串口助手、Vivado Hardware Manager 等）。")
    elif "access is denied" in low or "permission" in low:
        hints.append("端口可能被其他程序占用，请关闭后重试。")
    elif "exclusive access" in low:
        hints.append("Windows 串口只能独占打开；请关闭占用该口的其他程序后重试。")
    elif "could not open port" in low or "filenotfound" in type(exc).__name__.lower():
        hints.append("端口不存在或已拔掉，请点击「刷新」后重新选择。")
    body = f"无法打开 {port}：{msg}"
    if hints:
        body += "\n\n" + "\n".join(f"• {h}" for h in hints)
    return body


def probe_serial_port(port: str, baud: int = DEFAULT_BAUD) -> bool:
    """Quick open/close test; False if port is unusable on this PC."""
    if serial is None:
        return False
    try:
        kw = _serial_kwargs(baud, timeout=0.3)
        kw["port"] = port
        ser = serial.Serial(**kw)
        time.sleep(0.05)
        ser.close()
        return True
    except Exception:
        return False


def enumerate_ports(*, probe: bool = True) -> list[dict[str, str | bool]]:
    """List COM ports with description and optional probe result."""
    if list_ports is None:
        return []
    rows: list[dict[str, str | bool]] = []
    for p in list_ports.comports():
        device = p.device
        desc = p.description or ""
        ok = probe_serial_port(device) if probe else True
        rows.append({"device": device, "description": desc, "ok": ok})
    return rows


def port_choice_label(device: str, description: str, ok: bool) -> str:
    """Device name first so combobox selection always maps unambiguously."""
    mark = "✓" if ok else "✗"
    desc = re.sub(r"\(COM\d+\)", "", description, flags=re.IGNORECASE).strip()
    short = desc[:36] + ("…" if len(desc) > 36 else "")
    return f"{device} {mark} — {short}" if short else f"{device} {mark}"


def com_port_number(device: str) -> int:
    m = re.search(r"(\d+)$", device.strip(), re.IGNORECASE)
    return int(m.group(1)) if m else 0


def normalize_com_port(name: str) -> str | None:
    bare = name.strip().upper()
    if re.fullmatch(r"COM\d+", bare):
        return bare
    m = re.match(r"^(COM\d+)\b", bare)
    return m.group(1).upper() if m else None


def pick_default_port(rows: list[dict[str, str | bool]]) -> str | None:
    """Prefer highest-numbered probed-OK CH340 (dual-UART boards: upper COM is often data)."""
    ok_rows = [r for r in rows if r["ok"]]
    if not ok_rows:
        return str(rows[0]["device"]) if rows else None
    ch340 = [r for r in ok_rows if "CH340" in str(r["description"]).upper()]
    if ch340:
        best = max(ch340, key=lambda r: com_port_number(str(r["device"])))
        return str(best["device"])
    for r in ok_rows:
        d = str(r["description"]).upper()
        if any(x in d for x in ("CP210", "FTDI", "UART", "SERIAL")):
            return str(r["device"])
    return str(max(ok_rows, key=lambda r: com_port_number(str(r["device"])))["device"])


def resolve_port_name(choice: str, label_to_device: dict[str, str]) -> str:
    choice = choice.strip()
    if choice in label_to_device:
        return label_to_device[choice]
    bare = choice.upper()
    if re.fullmatch(r"COM\d+", bare):
        return bare
    if bare in label_to_device.values():
        return bare
    # Leading device field in our labels: "COM14 ✓ — …"
    m = re.match(r"^(COM\d+)\b", choice, re.IGNORECASE)
    if m:
        return m.group(1).upper()
    # Legacy label format: "✓ COM14 — …"
    m = re.match(r"^[✓✗]\s*(COM\d+)\b", choice)
    if m:
        return m.group(1).upper()
    return choice


def open_serial_port(port: str, baud: int = DEFAULT_BAUD, timeout: float = 1.0):
    if serial is None:
        raise RuntimeError("pyserial not installed: pip install pyserial")
    last_exc: BaseException | None = None
    for attempt in range(3):
        try:
            kw = _serial_kwargs(baud, timeout)
            kw["port"] = port
            # exclusive=False is Linux-only; Windows rejects non-exclusive open.
            if sys.platform != "win32":
                kw["exclusive"] = False
            ser = serial.Serial(**kw)
            time.sleep(0.05)
            ser.reset_input_buffer()
            return ser
        except Exception as e:
            last_exc = e
            if attempt < 2:
                time.sleep(0.15 * (attempt + 1))
    assert last_exc is not None
    raise OSError(format_serial_error(last_exc, port)) from last_exc


def encode_u12(value: int) -> tuple[int, int]:
    """Pack a 12-bit value into (addr_nibble, data_byte). Used by non-ADC SPI
    commands whose register field is 12 bits; ADC commands use ``encode_u14``."""
    if not 0 <= value <= 0xFFF:
        raise ValueError(f"value out of 12-bit range: {value}")
    return (value >> 8) & 0x0F, value & 0xFF


def encode_u14(value: int) -> tuple[int, int]:
    """Pack a 14-bit value into (addr_lo6, data_byte).

    Wire layout for ADC commands (0x30/0x31/0x32):
      addr byte = {2'b00, value[13:8]}    # only low 6 bits of addr used
      data byte =        value[7:0]
    FPGA parser concatenates ``{f_addr[5:0], rx_data}`` → 14-bit value.
    """
    if not 0 <= value <= 0x3FFF:
        raise ValueError(f"value out of 14-bit range: {value}")
    return (value >> 8) & 0x3F, value & 0xFF


def adc_wire_count(n_samples: int) -> int:
    """Map logical sample count to 14-bit UART field (FPGA: 0 → 16384)."""
    if n_samples == MAX_SAMPLES:
        return 0
    return n_samples


def ack_checksum(status: int, data: int) -> int:
    return ACK_HDR ^ status ^ data


def build_cmd(cmd: int, chip: int, field12: int) -> bytes:
    addr_b, data_b = encode_u12(field12)
    return bytes([CMD_HDR, cmd, chip, addr_b, data_b])


def build_adc_cmd(cmd: int, field14: int, *, channel: int = 0) -> bytes:
    """Variant of build_cmd for ADC commands (0x30/0x31/0x32/0x33) that need
    a 14-bit numeric field. Wire layout uses addr[5:0] + data[7:0]; addr[6] is
    the channel select bit (0=I/A, 1=Q/B). 0x30 (arm) ignores the channel bit
    since it arms both channels simultaneously."""
    if channel not in (0, 1):
        raise ValueError(f"channel must be 0 (I/A) or 1 (Q/B), got {channel}")
    addr_b, data_b = encode_u14(field14)
    addr_b = (addr_b & 0x3F) | (channel << 6)
    return bytes([CMD_HDR, cmd, CHIP_SYS, addr_b, data_b])


def decode_stream_iq_payload(payload: bytes) -> tuple[list[int], list[int]]:
    """Decode 0x34 payload into (I, Q) 14-bit sample arrays.

    Stream payload format is 4 bytes per IQ sample:
      I_hi, I_lo(6b), Q_hi, Q_lo(6b)
    """
    if len(payload) % 4 != 0:
        raise ValueError(f"stream payload length must be multiple of 4, got {len(payload)}")
    i_samples: list[int] = []
    q_samples: list[int] = []
    for idx in range(0, len(payload), 4):
        i_s = (payload[idx] << 6) | (payload[idx + 1] & 0x3F)
        q_s = (payload[idx + 2] << 6) | (payload[idx + 3] & 0x3F)
        i_samples.append(i_s)
        q_samples.append(q_s)
    return i_samples, q_samples


def sample_code_to_signed(sample: int, *, bits: int = 14) -> int:
    """Interpret an unsigned N-bit code as two's-complement signed value."""
    mask = (1 << bits) - 1
    sign = 1 << (bits - 1)
    v = int(sample) & mask
    return v - (1 << bits) if (v & sign) else v


def samples_to_signed(samples: list[int], *, bits: int = 14) -> list[int]:
    """Convert a list of unsigned N-bit codes to signed integers."""
    return [sample_code_to_signed(s, bits=bits) for s in samples]


def build_spi_frame(cmd: int, chip: int, addr: int, data: int) -> bytes:
    return bytes([CMD_HDR, cmd, chip, addr & 0xFF, data & 0xFF])


def hz_to_dac_freq_word(freq_hz: float, *, sys_clk_hz: float = DEFAULT_SYS_CLK_HZ) -> int:
    if freq_hz < 0:
        raise ValueError("freq_hz must be >= 0")
    word = int(round(freq_hz * 65536.0 / sys_clk_hz))
    return max(0, min(0xFFFF, word))


def dac_freq_word_to_hz(freq_word: int, *, sys_clk_hz: float = DEFAULT_SYS_CLK_HZ) -> float:
    if not 0 <= freq_word <= 0xFFFF:
        raise ValueError("freq_word must be 0..65535")
    return float(freq_word) * sys_clk_hz / 65536.0


class RfAddaUart:
    """Minimal client for rf_adda_top UART command protocol."""

    def __init__(
        self,
        port: str,
        baud: int = DEFAULT_BAUD,
        timeout: float = 1.0,
    ) -> None:
        if serial is None:
            raise RuntimeError("pyserial not installed: pip install pyserial")
        self.port = port
        self.baud = baud
        self.ser = open_serial_port(port, baud=baud, timeout=timeout)

    def close(self) -> None:
        if self.ser and self.ser.is_open:
            self.ser.close()

    def __enter__(self) -> RfAddaUart:
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    @property
    def is_open(self) -> bool:
        return bool(self.ser and self.ser.is_open)

    def transact(self, frame: bytes, ack_timeout: float | None = None) -> tuple[int, int]:
        t = ack_timeout if ack_timeout is not None else self.ser.timeout
        old = self.ser.timeout
        self.ser.timeout = t
        try:
            self.ser.reset_input_buffer()
            self.ser.write(frame)
            self.ser.flush()
            ack = self.ser.read(4)
        finally:
            self.ser.timeout = old

        if len(ack) != 4:
            hint = ""
            if len(ack) == 0:
                hint = (
                    " (no bytes — FPGA may be stuck in ADC_WAIT; "
                    "reflash or power-cycle)"
                )
            raise TimeoutError(
                f"ACK timeout ({t:.2f}s): got {len(ack)} bytes "
                f"{ack.hex() if ack else ''}{hint}"
            )
        if ack[0] != ACK_HDR:
            raise ValueError(f"bad ACK header 0x{ack[0]:02X}, raw={ack.hex()}")

        status, data, ck = ack[1], ack[2], ack[3]
        if ack_checksum(status, data) != ck:
            raise ValueError(
                f"ACK checksum mismatch: status=0x{status:02X} data=0x{data:02X} "
                f"got_ck=0x{ck:02X} exp=0x{ack_checksum(status, data):02X}"
            )
        if status != STATUS_OK:
            name = STATUS_NAMES.get(status, "unknown")
            raise RuntimeError(f"FPGA status=0x{status:02X} ({name})")
        return status, data

    def ping(self) -> int:
        _, data = self.transact(build_cmd(CMD_PING, CHIP_SYS, 0))
        return data

    def firmware_version(self) -> int:
        _, data = self.transact(build_cmd(CMD_FW_VERSION, CHIP_SYS, 0))
        return data

    def error_query(self) -> int:
        _, data = self.transact(build_cmd(CMD_ERROR_QUERY, CHIP_SYS, 0))
        return data

    def boot_status(self) -> int:
        _, data = self.transact(build_cmd(CMD_BOOT_STATUS, CHIP_SYS, 0))
        return data

    def boot_run(self, ack_timeout: float = 30.0) -> int:
        _, data = self.transact(build_cmd(CMD_BOOT_RUN, CHIP_SYS, 0), ack_timeout=ack_timeout)
        return data

    def spi_write(self, chip: int, addr: int, data: int) -> int:
        _, d = self.transact(build_spi_frame(CMD_WRITE, chip, addr, data))
        return d

    def spi_read(self, chip: int, addr: int) -> int:
        _, d = self.transact(build_spi_frame(CMD_READ, chip, addr, 0))
        return d

    def read_chip_id(self, chip: int, addr: int) -> int:
        return self.spi_read(chip, addr)

    def read_common_chip_info(self) -> dict[str, int]:
        return {
            "si5340_pn_hi": self.spi_read(CHIP_SI5340, 0x02),
            "si5340_pn_lo": self.spi_read(CHIP_SI5340, 0x03),
            "si5340_grade": self.spi_read(CHIP_SI5340, 0x0C),
            "ad9640_chip_id": self.spi_read(CHIP_AD9640, 0x01),
            "ad9117_version": self.spi_read(CHIP_AD9117, 0x1F),
        }

    def adc_transfer(self, chip: int = CHIP_AD9640) -> None:
        self.spi_write(chip, 0xFF, 0x01)

    def dac_tone_enable(self, on: bool) -> int:
        """UART 0x40 — start/stop on-chip sine to AD9117. Returns ACK data (enable state)."""
        _, data = self.transact(build_cmd(CMD_DAC_TONE, CHIP_SYS, 1 if on else 0))
        return data

    def dac_set_waveform(self, wave: int | str, hb_bypass: bool = False) -> int:
        """UART 0x41 — set DAC waveform type + halfband bypass.
        bit[1:0] = wave_sel, bit[7] = hb_bypass (1 = skip 2x halfband interp)."""
        if isinstance(wave, str):
            key = wave.strip().lower()
            if key.isdigit():
                wave_code = int(key)
            else:
                if key not in DAC_WAVE_NAME_TO_CODE:
                    raise ValueError(f"wave must be one of {sorted(DAC_WAVE_NAME_TO_CODE)}")
                wave_code = DAC_WAVE_NAME_TO_CODE[key]
        else:
            wave_code = int(wave)
        if wave_code not in (DAC_WAVE_SINE, DAC_WAVE_SQUARE, DAC_WAVE_TRIANGLE, DAC_WAVE_RAMP, DAC_WAVE_DC_TEST):
            raise ValueError("wave code must be 0(sine)/1(square)/2(triangle)/3(ramp)/4(dc_test)")
        byte_val = (wave_code & 0x07) | (0x80 if hb_bypass else 0x00)
        _, data = self.transact(build_spi_frame(CMD_DAC_WAVE, CHIP_SYS, 0x00, byte_val))
        return data

    def dac_set_freq_word(self, freq_word: int) -> int:
        if not 0 <= freq_word <= 0xFFFF:
            raise ValueError("freq_word must be 0..65535")
        hi = (freq_word >> 8) & 0xFF
        lo = freq_word & 0xFF
        self.transact(build_spi_frame(CMD_DAC_FREQ, CHIP_SYS, 0x00, hi))
        _, ack = self.transact(build_spi_frame(CMD_DAC_FREQ, CHIP_SYS, 0x01, lo))
        return ack

    def dac_set_frequency_hz(self, freq_hz: float) -> tuple[int, float]:
        word = hz_to_dac_freq_word(freq_hz)
        self.dac_set_freq_word(word)
        return word, dac_freq_word_to_hz(word)

    def dac_set_amplitude_pct(self, amp_pct: int | float) -> int:
        amp = int(round(float(amp_pct)))
        if amp < 0:
            amp = 0
        if amp > 100:
            amp = 100
        _, data = self.transact(build_spi_frame(CMD_DAC_AMP, CHIP_SYS, 0x00, amp))
        return data

    def dac_config(
        self,
        *,
        wave: int | str | None = None,
        freq_hz: float | None = None,
        amp_pct: int | float | None = None,
        hb_bypass: bool = False,
    ) -> dict[str, float | int | str]:
        out: dict[str, float | int | str] = {}
        if wave is not None:
            wave_code = self.dac_set_waveform(wave, hb_bypass=hb_bypass)
            out["wave_code"] = wave_code
            out["hb_bypass"] = hb_bypass
            out["wave_name"] = DAC_WAVE_CODE_TO_NAME.get(wave_code, f"code_{wave_code}")
        if freq_hz is not None:
            word, actual_hz = self.dac_set_frequency_hz(freq_hz)
            out["freq_word"] = word
            out["freq_hz"] = actual_hz
        if amp_pct is not None:
            out["amp_pct"] = self.dac_set_amplitude_pct(amp_pct)
        return out

    # ------------------------------------------------------------------
    # Waveform player (0x50 / 0x51 / 0x52)
    # ------------------------------------------------------------------
    def wave_enable(self, on: bool) -> int:
        """0x51 sub-addr 0: play_en. Returns ACK data byte."""
        _, d = self.transact(build_spi_frame(CMD_WAVE_CTRL, CHIP_SYS, 0x00,
                                             1 if on else 0))
        return d

    def wave_set_loop_len(self, n_samples: int) -> None:
        """0x51 sub-addr 1/2/3: program loop_len in samples (1..262144).
        Wire value = n_samples - 1 split into LSB/mid/MSB bytes."""
        if not 1 <= n_samples <= WAVE_URAM_WORDS:
            raise ValueError(f"loop_len must be 1..{WAVE_URAM_WORDS}")
        n = n_samples - 1
        self.transact(build_spi_frame(CMD_WAVE_CTRL, CHIP_SYS, 0x01,  n        & 0xFF))
        self.transact(build_spi_frame(CMD_WAVE_CTRL, CHIP_SYS, 0x02, (n >>  8) & 0xFF))
        self.transact(build_spi_frame(CMD_WAVE_CTRL, CHIP_SYS, 0x03, (n >> 16) & 0x03))

    def wave_set_polarity(self, swap_iq: bool = False, neg_q: bool = False) -> int:
        """0x52: data[0]=swap_iq, data[1]=neg_q."""
        data = (1 if swap_iq else 0) | (2 if neg_q else 0)
        _, d = self.transact(build_spi_frame(CMD_WAVE_FLAGS, CHIP_SYS, 0x00, data))
        return d

    def wave_write_chunk(self, chunk_idx: int, payload: bytes,
                         ack_timeout: float | None = None) -> int:
        """0x50: write one 1024-byte chunk (256 IQ pairs) to URAM.
        chunk_addr[9:0] = {f_chip[1:0], f_addr[7:0]}.
        Player must be disabled (else FPGA returns status 0x06)."""
        if len(payload) != WAVE_CHUNK_BYTES:
            raise ValueError(f"payload must be {WAVE_CHUNK_BYTES} bytes")
        if not 0 <= chunk_idx < WAVE_MAX_CHUNKS:
            raise ValueError(f"chunk_idx must be 0..{WAVE_MAX_CHUNKS-1}")
        ah = (chunk_idx >> 8) & 0x03
        al = chunk_idx & 0xFF
        frame = bytes([CMD_HDR, CMD_WAVE_WRITE, ah, al, 0x00]) + payload
        # Custom transact: we must NOT reset_input_buffer mid-write.
        t = ack_timeout if ack_timeout is not None else 2.0
        old = self.ser.timeout
        self.ser.timeout = t
        try:
            self.ser.reset_input_buffer()
            self.ser.write(frame)
            self.ser.flush()
            ack = self.ser.read(4)
        finally:
            self.ser.timeout = old
        if len(ack) != 4 or ack[0] != ACK_HDR:
            raise IOError(f"wave_write_chunk[{chunk_idx}]: bad ack {ack.hex()}")
        if ack[1] != 0x00:
            raise IOError(f"wave_write_chunk[{chunk_idx}]: status 0x{ack[1]:02x}")
        return ack[2]

    def wave_upload_bytes(self, data: bytes, *,
                          start_chunk: int = 0,
                          progress: "callable | None" = None) -> int:
        """Upload raw LE-IQ byte stream to URAM in 1024-byte chunks.
        Pads tail with zeros if needed. Returns number of chunks written."""
        if len(data) > WAVE_MAX_CHUNKS * WAVE_CHUNK_BYTES:
            raise ValueError("data exceeds URAM capacity (1 MB)")
        pad = (-len(data)) % WAVE_CHUNK_BYTES
        if pad:
            data = data + b"\x00" * pad
        n_chunks = len(data) // WAVE_CHUNK_BYTES
        for i in range(start_chunk, n_chunks):
            self.wave_write_chunk(i, data[i*WAVE_CHUNK_BYTES:(i+1)*WAVE_CHUNK_BYTES])
            if progress:
                progress(i + 1, n_chunks)
        return n_chunks

    @staticmethod
    def wave_read_file(path: str, endian: str = "auto") -> bytes:
        """Load a .WAVEFORM (BE) or .bin (LE) IQ file, return LE bytes.
        endian: 'auto' picks BE for .WAVEFORM, LE otherwise."""
        import os
        import struct as _struct
        with open(path, "rb") as f:
            raw = f.read()
        if endian == "auto":
            endian = "big" if path.upper().endswith(".WAVEFORM") else "little"
        # Truncate trailing odd bytes
        raw = raw[: (len(raw) // 4) * 4]
        if endian == "big":
            samples = _struct.unpack(f">{len(raw)//2}h", raw)
            raw = _struct.pack(f"<{len(samples)}h", *samples)
        return raw

    def adc_arm(self, n_samples: int, timeout: float | None = None) -> None:
        if n_samples == 0:
            n_samples = MAX_SAMPLES
        if not 1 <= n_samples <= MAX_SAMPLES:
            raise ValueError(f"n_samples must be 1..{MAX_SAMPLES} (wire 0 → {MAX_SAMPLES})")
        frame = build_adc_cmd(CMD_ADC_ARM, adc_wire_count(n_samples))
        if timeout is None:
            timeout = max(5.0, n_samples / 50_000.0 + 2.0)
        self.transact(frame, ack_timeout=timeout)
        time.sleep(0.002)

    def adc_read(self, index: int, *, channel: int = ADC_CHAN_I) -> int:
        """Read one sample from BRAM. ``channel`` selects I (0, channel A) or
        Q (1, channel B); defaults to I for backwards compatibility."""
        if not 0 <= index < MAX_SAMPLES:
            raise ValueError(f"index out of range 0..{MAX_SAMPLES - 1}: {index}")
        hi_frame = build_adc_cmd(CMD_ADC_READ_HI, index, channel=channel)
        lo_frame = build_adc_cmd(CMD_ADC_READ_LO, index, channel=channel)
        _, hi = self.transact(hi_frame, ack_timeout=2.0)
        _, lo = self.transact(lo_frame, ack_timeout=2.0)
        return (hi << 6) | (lo & 0x3F)

    def adc_read_burst(
        self,
        n_samples: int,
        *,
        timeout: float | None = None,
        channel: int = ADC_CHAN_I,
    ) -> list[int]:
        """Stream all N samples back via 0x33: one 5-byte cmd → 2N raw bytes → 4-byte ACK.

        N is taken from the most recent 0x30 arm on the FPGA side; we still pass
        n_samples here so the PC knows how many bytes to read and can sanity-check.
        Caller is responsible for arming first via adc_arm(n_samples).
        """
        if n_samples == 0:
            n_samples = MAX_SAMPLES
        if not 1 <= n_samples <= MAX_SAMPLES:
            raise ValueError(f"n_samples must be 1..{MAX_SAMPLES}")

        payload_bytes = 2 * n_samples
        # Worst case at 921600 8N1: ~10.9 µs/byte → ~356 ms for 16384 samples
        # (~89 ms for 4096). Give a generous margin for the FPGA-side ACK
        # housekeeping after the payload.
        if timeout is None:
            timeout = max(2.0, payload_bytes / 8000.0 + 3.0)

        frame = build_adc_cmd(CMD_ADC_READ_BURST, 0, channel=channel)

        old = self.ser.timeout
        self.ser.timeout = timeout
        try:
            self.ser.reset_input_buffer()
            self.ser.write(frame)
            self.ser.flush()
            payload = self.ser.read(payload_bytes)
            ack = self.ser.read(4)
        finally:
            self.ser.timeout = old

        if len(payload) != payload_bytes:
            raise TimeoutError(
                f"burst payload short: got {len(payload)}/{payload_bytes} bytes"
            )
        if len(ack) != 4:
            raise TimeoutError(f"burst ACK short: got {len(ack)} bytes {ack.hex()}")
        if ack[0] != ACK_HDR:
            raise ValueError(f"bad burst ACK header 0x{ack[0]:02X}, raw={ack.hex()}")

        status, xor_rx, ck = ack[1], ack[2], ack[3]
        if ack_checksum(status, xor_rx) != ck:
            raise ValueError(
                f"burst ACK checksum mismatch: status=0x{status:02X} "
                f"xor=0x{xor_rx:02X} got_ck=0x{ck:02X} "
                f"exp=0x{ack_checksum(status, xor_rx):02X}"
            )
        if status != STATUS_OK:
            name = STATUS_NAMES.get(status, "unknown")
            raise RuntimeError(f"FPGA burst status=0x{status:02X} ({name})")

        xor_calc = 0
        for b in payload:
            xor_calc ^= b
        if xor_calc != xor_rx:
            raise ValueError(
                f"burst payload XOR mismatch: calc=0x{xor_calc:02X} rx=0x{xor_rx:02X}"
            )

        return [
            (payload[2 * i] << 6) | (payload[2 * i + 1] & 0x3F)
            for i in range(n_samples)
        ]

    def capture_all(self, n_samples: int, *, channel: int = ADC_CHAN_I) -> list[int]:
        if n_samples == 0:
            n_samples = MAX_SAMPLES
        self.adc_arm(n_samples)
        return self.adc_read_burst(n_samples, channel=channel)

    def capture_iq(self, n_samples: int) -> tuple[list[int], list[int]]:
        """Arm once, then burst-read both channels (I from A, Q from B).

        Snapshot buffers share the same arm so the two streams
        are sample-aligned; the two 0x33 transactions just stream them out
        sequentially.  Returns ``(i_samples, q_samples)``.
        """
        if n_samples == 0:
            n_samples = MAX_SAMPLES
        self.adc_arm(n_samples)
        i_samples = self.adc_read_burst(n_samples, channel=ADC_CHAN_I)
        q_samples = self.adc_read_burst(n_samples, channel=ADC_CHAN_Q)
        return i_samples, q_samples

    # ---- digital DDC / RX chain config -------------------------------------
    def set_nco_freq_word(self, freq_word: int) -> int:
        """Write the 16-bit NCO frequency tuning word for RX-chain mixer.

        f_out = freq_word * adc_clk / 65536 (≈122.88 MHz for AD9640 default).
        Sent as two 5-byte frames: high byte then low byte (mirror of 0x42).
        """
        if not 0 <= freq_word <= 0xFFFF:
            raise ValueError("freq_word must be 0..65535")
        hi = (freq_word >> 8) & 0xFF
        lo = freq_word & 0xFF
        self.transact(build_spi_frame(CMD_NCO_FREQ, CHIP_SYS, 0x00, hi))
        _, ack = self.transact(build_spi_frame(CMD_NCO_FREQ, CHIP_SYS, 0x01, lo))
        return ack

    def set_nco_frequency_hz(
        self,
        freq_hz: float,
        *,
        adc_fs_hz: float = DEFAULT_ADC_FS_HZ,
    ) -> tuple[int, float]:
        """Set NCO by absolute frequency.  Returns (programmed_word, actual_hz)."""
        if freq_hz < 0:
            raise ValueError("freq_hz must be >= 0")
        word = int(round(freq_hz * 65536.0 / adc_fs_hz))
        word = max(0, min(0xFFFF, word))
        self.set_nco_freq_word(word)
        return word, float(word) * adc_fs_hz / 65536.0

    def set_rx_config(
        self,
        *,
        dec_ratio: int = 0,
        capture_mode: int = CAPTURE_MODE_SNAPSHOT,
        fir_bypass: bool = True,
        iq_bypass: bool = True,
        fir_sel: int = 0,
    ) -> int:
        # 0x45 RX config byte:
        #   bit[1:0] dec_ratio, bit2 capture_mode, bit3 fir_bypass,
        #   bit4 iq_bypass, bit[6:5] fir_sel (FIR coefficient bank 0..3:
        #   0=Fs/8 default, 1=Fs/16 narrow, 2=Fs/4 wide, 3=all-pass).
        if dec_ratio not in (0, 1, 2):
            raise ValueError("dec_ratio must be 0/1/2 (1x/2x/4x)")
        if fir_sel not in (0, 1, 2, 3):
            raise ValueError("fir_sel must be 0..3 (Fs/8, Fs/16, Fs/4, all-pass)")
        data = (dec_ratio & 0x3)
        data |= (int(bool(capture_mode)) & 0x1) << 2
        data |= (int(bool(fir_bypass)) & 0x1) << 3
        data |= (int(bool(iq_bypass)) & 0x1) << 4
        data |= (fir_sel & 0x3) << 5
        _, data = self.transact(build_spi_frame(CMD_RX_CFG, CHIP_SYS, 0x00, data))
        return data

    def _write_split16(self, cmd: int, value: int) -> int:
        """Write a 16-bit value as two 5-byte frames: hi (addr=0) then lo (addr=1).
        Mirrors the 0x42/0x44 split-word convention used across the protocol."""
        if not -0x8000 <= value <= 0xFFFF:
            raise ValueError(f"value out of 16-bit range: {value}")
        v = value & 0xFFFF
        hi = (v >> 8) & 0xFF
        lo = v & 0xFF
        self.transact(build_spi_frame(cmd, CHIP_SYS, 0x00, hi))
        _, ack = self.transact(build_spi_frame(cmd, CHIP_SYS, 0x01, lo))
        return ack

    def _write_split14_signed(self, cmd: int, value: int) -> int:
        """Write a signed 14-bit DC-offset value as two frames: hi (addr=0,
        only data[5:0] meaningful = bits [13:8]) then lo (addr=1 = bits [7:0])."""
        if not -0x2000 <= value <= 0x1FFF:
            raise ValueError(f"value out of signed 14-bit range: {value}")
        v = value & 0x3FFF
        hi = (v >> 8) & 0x3F
        lo = v & 0xFF
        self.transact(build_spi_frame(cmd, CHIP_SYS, 0x00, hi))
        _, ack = self.transact(build_spi_frame(cmd, CHIP_SYS, 0x01, lo))
        return ack

    def set_iq_op1(self, value: int) -> int:
        """Write IQ-balance OP1 coefficient (Q2.14 signed, default 0x4000=1.0)."""
        return self._write_split16(CMD_IQ_OP1, value)

    def set_iq_op2(self, value: int) -> int:
        """Write IQ-balance OP2 coefficient (Q2.14 signed, default 0)."""
        return self._write_split16(CMD_IQ_OP2, value)

    def set_iq_offset_i(self, value: int) -> int:
        """Write IQ-balance I-channel DC offset (signed 14-bit, default 0)."""
        return self._write_split14_signed(CMD_IQ_OFF_I, value)

    def set_iq_offset_q(self, value: int) -> int:
        """Write IQ-balance Q-channel DC offset (signed 14-bit, default 0)."""
        return self._write_split14_signed(CMD_IQ_OFF_Q, value)

    # ------------------------------------------------------------------
    # 0x34 streaming — continuous mode
    # ------------------------------------------------------------------
    # Protocol (post-refactor): the host sends ``AA 34 00 00 00`` to arm
    # continuous streaming. FPGA emits 4 bytes per IQ sample forever until
    # the host sends ANY UART byte, at which point FPGA finishes the current
    # 4-byte sample and emits a 4-byte ACK ``BB | status | xor8(payload) | ck``.
    #
    # Bounded (legacy) mode is still supported by passing N>0 in the same
    # frame: FPGA will emit exactly ``N*4`` bytes + ACK without needing a
    # stop byte.

    _STREAM_STOP_BYTE = 0x55

    def adc_stream_start_continuous(self) -> None:
        """Arm 0x34 continuous streaming.  Returns immediately; bytes will
        start flowing from the FPGA right away.  Use ``adc_stream_read_bytes``
        to consume them and ``adc_stream_stop_and_drain`` to terminate."""
        frame = build_adc_cmd(CMD_ADC_STREAM, 0)
        self.ser.reset_input_buffer()
        self.ser.write(frame)
        self.ser.flush()

    def adc_stream_read_bytes(self, max_bytes: int, *, timeout: float = 0.1) -> bytes:
        """Read up to ``max_bytes`` from an active 0x34 stream.  Returns
        whatever was available within ``timeout``; may be short or empty."""
        old = self.ser.timeout
        self.ser.timeout = timeout
        try:
            return self.ser.read(max_bytes)
        finally:
            self.ser.timeout = old

    def adc_stream_stop_and_drain(
        self,
        *,
        idle_timeout: float = 0.2,
        overall_timeout: float = 2.0,
    ) -> tuple[bytes, tuple[int, int, int]]:
        """Send the stop byte, drain trailing payload bytes + 4-byte ACK.

        Returns ``(tail_payload_bytes, (status, xor_rx, checksum))``.  The
        tail contains any payload bytes that arrived between the stop byte
        being injected and the FPGA closing the current sample.  Caller is
        responsible for concatenating these with bytes previously gathered
        via :py:meth:`adc_stream_read_bytes` before XOR-validating.
        """
        # Inject a single stop byte (FPGA accepts any byte).
        self.ser.write(bytes([self._STREAM_STOP_BYTE]))
        self.ser.flush()

        old = self.ser.timeout
        self.ser.timeout = idle_timeout
        try:
            buf = bytearray()
            deadline = time.monotonic() + overall_timeout
            # Drain until the line is quiet for ``idle_timeout``.  At 921600 baud
            # a full ACK takes ~43 us; idle_timeout=200 ms is generous.
            while time.monotonic() < deadline:
                chunk = self.ser.read(4096)
                if not chunk:
                    break
                buf.extend(chunk)
        finally:
            self.ser.timeout = old

        if len(buf) < 4:
            raise TimeoutError(f"stream stop: only {len(buf)} byte(s) drained, no ACK")
        ack = bytes(buf[-4:])
        tail = bytes(buf[:-4])
        if ack[0] != ACK_HDR:
            raise TimeoutError(f"stream stop: bad ACK header in tail {ack.hex()}")
        status, xor_rx, ck = ack[1], ack[2], ack[3]
        if ack_checksum(status, xor_rx) != ck:
            raise ValueError("stream ACK checksum mismatch")
        if status not in (STATUS_OK, 0x05):  # 0x05 = drain overflow, non-fatal here
            raise RuntimeError(f"stream status=0x{status:02X}")
        return tail, (status, xor_rx, ck)

    def adc_stream_bytes(
        self,
        n_samples: int,
        *,
        timeout: float | None = None,
    ) -> bytes:
        """Collect exactly ``n_samples * 4`` bytes from a continuous 0x34 stream.

        Convenience wrapper for callers that want a fixed-size capture without
        worrying about start/stop framing.  Internally uses continuous mode so
        the FPGA never has to know N in advance.
        """
        if n_samples <= 0:
            raise ValueError("n_samples must be > 0")
        target_bytes = n_samples * 4
        # Generous default: at 921600 baud ~92 KB/s would be 22 ms for 16 KB,
        # but rx_chain throughput can be much lower in practice.  Allow up to
        # ~5 s/16 KB plus a 2 s floor.
        if timeout is None:
            timeout = max(2.0, target_bytes / 3000.0)
        self.adc_stream_start_continuous()
        try:
            buf = bytearray()
            deadline = time.monotonic() + timeout
            while len(buf) < target_bytes and time.monotonic() < deadline:
                want = target_bytes - len(buf)
                buf.extend(self.adc_stream_read_bytes(min(want, 4096), timeout=0.1))
        finally:
            tail, (_st, xor_rx, _ck) = self.adc_stream_stop_and_drain()
        buf.extend(tail)
        if len(buf) < target_bytes:
            raise TimeoutError(
                f"stream collected only {len(buf)}/{target_bytes} bytes "
                f"before timeout (rx_chain may be starving)"
            )
        payload = bytes(buf[:target_bytes])
        xor_calc = 0
        # XOR validation: FPGA's xor_rx is over ALL bytes it transmitted, which
        # equals the full buf (including any extra bytes past target).
        for b in buf:
            xor_calc ^= b
        if xor_calc != xor_rx:
            # Don't hard-fail — high baud + USB-serial overruns can drop a byte
            # silently.  Surface it as a warning via stderr.
            print(
                f"warning: stream XOR mismatch (calc=0x{xor_calc:02X} "
                f"fpga=0x{xor_rx:02X}); possible dropped byte",
                file=sys.stderr,
            )
        return payload

    def adc_stream_iq(
        self,
        n_samples: int,
        *,
        timeout: float | None = None,
    ) -> tuple[list[int], list[int]]:
        """Read IQ stream via 0x34 and decode into I/Q sample arrays."""
        payload = self.adc_stream_bytes(n_samples, timeout=timeout)
        return decode_stream_iq_payload(payload)


def samples_to_volts(
    samples: list[int],
    *,
    full_scale_v: float = 1.0,
    bits: int = 14,
) -> list[float]:
    """Convert signed ADC codes to centered voltage."""
    mid = 1 << (bits - 1)
    scale = full_scale_v / mid
    return [int(s) * scale for s in samples]


def export_matlab_ifft_bin(
    path: str | Path,
    samples: list[int],
    *,
    bits: int = 14,
) -> None:
    """Export Python ADC samples into adc_ifft_analysis.m-compatible .bin.

    The MATLAB script expects int16 words and divides by 2^2, then de-interleaves
    as [b0, a0, b1, a1, ...] when ANT_NUM=1. We only have one channel from UART,
    so duplicate each signed sample into both lanes.
    """
    import struct

    if bits <= 1:
        raise ValueError("bits must be > 1")
    signed_min = -(1 << (bits - 1))
    signed_max = (1 << (bits - 1)) - 1
    data_words: list[int] = []
    for s in samples:
        si = int(s)
        if si < signed_min:
            si = signed_min
        elif si > signed_max:
            si = signed_max
        signed = si
        w = signed << 2    # script divides by 2^2 on read
        data_words.append(w)  # b
        data_words.append(w)  # a

    p = Path(path)
    with p.open("wb") as f:
        f.write(struct.pack("<" + "h" * len(data_words), *data_words))


