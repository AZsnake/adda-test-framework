# ADDA Test Framework

面向 **Xilinx VU13P + SI5340 / AD9640 / AD9117** 的 FPGA bring-up 与验证框架：UART 命令、三芯片 SPI boot、ADC IQ DSP 链、DAC 2× DDR 发射，以及 PySide6 / Python 测试工具链。

**Vivado top:** `rf_adda_top`

> **Open source / privacy model**  
> This repo publishes the **framework** (RTL, protocol, tools, simulation).  
> Board-specific **pin constraints**, **schematics**, and **boot init tables** are **not** in git — clone后需本地补齐。详见 [`docs/OPEN_SOURCE.md`](docs/OPEN_SOURCE.md) 与 [`docs/BOARD_LOCAL_FILES.md`](docs/BOARD_LOCAL_FILES.md)。

License: [MIT](LICENSE)（第三方模块见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)）

---

## Highlights

| Area | Content |
|------|---------|
| End-to-end bring-up | UART Ping → SPI → auto boot → ADC capture → DAC waveform |
| UART protocol | 921600 8N1; SPI, boot, ADC snapshot/stream, DAC tone/wave, RX chain config |
| Zero-PC boot | `boot_fsm` + `boot_rom` for three chips |
| RX DSP | CIC → DDC → IQ balance → FIR → BRAM snapshot / UART stream |
| TX 2× DDR | Halfband interp + ODDRE1 I/Q mux; DCLKIO phase mux |
| Host tools | PySide6 GUI + CLI capture / FFT / waveform upload |
| Simulation | 11 testbenches (UART, boot, TX/RX chains) |

---

## Architecture

```
rf_adda_top
├── clk_wiz_0 / clk_wiz_1 + dac_dclk_phase_mux
├── rf_ctrl_path          ← UART + SPI + boot + DAC
├── adc_iq_rx_chain
├── dac_tone_gen / dac_wave_player → tx_iq_dsp → tx_ddr_out
└── led_status
```

---

## Quick start (after clone)

1. Copy pin template → local constraints (fill PACKAGE_PIN from **your** schematic):

   ```bash
   copy constraints\adda_io.template.xdc constraints\adda_io.xdc
   ```

2. Generate boot ROM locally — [`init_tables/README.md`](init_tables/README.md)

3. Vivado: Top `rf_adda_top`, constraints = local `adda_io.xdc` + `adda_clocks.xdc` + `adda_dac_ddr.xdc`

4. Host tools:

   ```bash
   pip install -r tools/adda/requirements.txt
   python tools/adda/gui/adda_test_gui_qt.py
   ```

---

## Documentation

| Doc | Purpose |
|-----|---------|
| [`docs/uart_command_protocol.md`](docs/uart_command_protocol.md) | Full UART command reference |
| [`docs/OPEN_SOURCE.md`](docs/OPEN_SOURCE.md) | What is public vs local; history cleanup before going public |
| [`docs/BOARD_LOCAL_FILES.md`](docs/BOARD_LOCAL_FILES.md) | Board-confidential file list |
| [`tools/README.md`](tools/README.md) | Python tool layout |

---

## Simulation

Set sim top to `tb_uart_cmd_parser`, run `run -all` in XSim → expect `tb_uart_cmd_parser: PASS`.

---

## Notes

- Target part example: `xcvu13p-fhga2104-2-i` (adapt to your board).
- `SYS_CLK_HZ` = `122_880_000` must match `clk_wiz_0`.
- Before making this repo **public**, scrub git history if it ever contained pin/schematic/init files — see [`docs/OPEN_SOURCE.md`](docs/OPEN_SOURCE.md).
