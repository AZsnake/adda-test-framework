# tools/

ADDA 工程配套 PC 端脚本。**不加入 Vivado 工程。** 各功能按子目录分类。

## 目录结构

```
tools/
├── adda/
│   ├── lib/          # 共享 Python 模块（仅供 import，不直接运行）
│   ├── gui/          # 桌面 GUI
│   ├── adc/          # ADC 采集、分析、芯片诊断
│   ├── dac/          # DAC 波形生成与 URAM 上传
│   ├── diag/         # 板级冒烟测试与底层 UART 探测
│   ├── data/         # 采集输出 CSV / 导出文件（.gitignore 忽略）
│   └── requirements.txt
├── boot/             # boot ROM / 初始化表生成器
├── vsg/              # 外部信号发生器 ARB 波形（与 FPGA RTL 无关）
├── vivado/           # 实现后 Tcl（在 Vivado 控制台运行）
└── utf8/             # 仓库文本编码工具
```

## vivado/

| 脚本 | 用途 |
|------|------|
| `report_dac_timing.tcl` | `impl_1` 完成后：DAC `dac_dclkio` / `FPGA_DAC_DB` 时序 + 总线偏斜 → `dac_timing_summary.rpt` |

## adda/

| 目录 | 脚本 | 用途 |
|------|------|------|
| `lib/` | `rf_uart_client.py` | 共享 UART 协议库（CLI / GUI 复用） |
| `lib/` | `adc_analysis.py` | FFT / DC 掩码 / 指标计算辅助函数 |
| `gui/` | `adda_test_gui_qt.py` | **综合 ADDA 测试 GUI**（PySide6 + pyqtgraph） |
| `adc/` | `adc_capture_plot.py` | 快照采集 + 绘图（CLI） |
| `adc/` | `adc_stream_capture.py` | 流式采集到文件 |
| `adc/` | `adc_ifft_analysis.m` | MATLAB 后处理 |
| `adc/` | `ad9640_dump.py` | 通过 UART/SPI 读取 AD9640 寄存器 |
| `adc/` | `ad9640_spi_diag.py` | AD9640 SPI 写/读诊断 |
| `adc/` | `gen_cic_comp_fir.py` | 生成 CIC droop 补偿 FIR 系数 |
| `dac/` | `gen_sine_iq_waveform.py` | 生成循环 IQ 正弦 `.bin` / `.WAVEFORM` |
| `dac/` | `gen_ref_waveforms.py` | 重新生成 `docs/wave/` 下全部参考正弦文件 |
| `dac/` | `gen_halfband_interp.py` | 生成半带滤波器系数 |
| `dac/` | `wave_upload.py` | 通过 UART 将波形上传到 AD9117 URAM |
| `dac/` | `sweep_dclk_phase.py` | 扫描 DCLKIO 相位 tap |
| `diag/` | `rx_chain_smoke.py` | 端到端 RX 链冒烟测试 |
| `diag/` | `rf_diag.py` | 原始 UART ping / 探测 |

## vsg/

| 脚本 | 用途 |
|------|------|
| `gen_sq_iq_clock.py` | 生成外部 VSG 用 20 MHz 方波 IQ `.bin` / `.WAVEFORM`（125 MSa/s，I=Q） |

## boot/ 与 utf8/

| 目录 | 脚本 | 用途 |
|------|------|------|
| `boot/` | `cbpro_to_mem.py` | ClockBuilder Pro 导出 / CSV → `init_tables/*.mem`（用于 `boot_rom`） |
| `utf8/` | `convert_all_to_utf8.py` | 批量将文本文件重编码为 UTF-8 |

## 快速上手

```bash
# ADDA GUI（推荐入口）
pip install -r tools/adda/requirements.txt
python tools/adda/gui/adda_test_gui_qt.py
# 或：tools/adda/run_adda_gui.bat

# ADC 快照采集
python tools/adda/adc/adc_capture_plot.py -p COM3 -n 256

# DAC 波形上传
python tools/adda/dac/wave_upload.py COM7 docs/wave/sine_iq_9M00_-6dBFS.WAVEFORM --play

# VSG 方波时钟 ARB（外部信号发生器，非 FPGA 上传）
python tools/vsg/gen_sq_iq_clock.py \
  --fs-hz 125000000 --tone-hz 20000000 \
  -o docs/wave/sq_iq_20M00_125Msps.bin \
  --waveform-out docs/wave/sq_iq_20M00_125Msps.WAVEFORM

# 生成 boot ROM 镜像
python tools/boot/cbpro_to_mem.py --chip si5340 INPUT.txt -o init_tables/si5340_init.mem

# UTF-8 编码转换
python tools/utf8/convert_all_to_utf8.py .
```
