# tools/

ADDA 工程配套 PC 端脚本。**不加入 Vivado 工程。** 各功能按子目录分类。

## 目录结构

```
tools/
├── run_gui.bat / run_gui.sh       # 启动 GUI
├── config/
│   └── requirements.txt
├── lib/                           # 共享 Python 模块（rf_uart_client 等）
├── gui/                           # PySide6 综合 ADDA 测试 GUI
├── scripts/
│   ├── adc/                       # ADC 采集、分析、芯片诊断
│   ├── dac/                       # DAC 波形生成与 URAM 上传
│   ├── diag/                      # 板级冒烟测试与底层 UART 探测
│   ├── vsg/                       # 外部信号发生器 ARB 波形（与 FPGA RTL 无关）
│   └── utf8/                      # 仓库文本编码工具
├── data/                          # 采集输出 CSV（.gitignore 忽略）
└── README.md
```

## 安装

```bash
cd tools
pip install -r config/requirements.txt
```

Linux 首次使用 shell 脚本需赋予执行权限：

```bash
chmod +x run_gui.sh
```

## 使用

### Windows

| 任务 | 命令 |
|------|------|
| GUI | `run_gui.bat` |
| ADC 快照采集 | `python scripts\adc\adc_capture_plot.py -p COM3 -n 256` |
| DAC 波形上传 | `python scripts\dac\wave_upload.py COM7 docs\wave\sine_iq_9M00_-6dBFS.WAVEFORM --play` |
| RX 链冒烟 | `python scripts\diag\rx_chain_smoke.py COM3` |

### Linux / macOS

| 任务 | 命令 |
|------|------|
| GUI | `./run_gui.sh` |
| ADC 快照采集 | `python3 scripts/adc/adc_capture_plot.py -p /dev/ttyUSB0 -n 256` |
| DAC 波形上传 | `python3 scripts/dac/wave_upload.py /dev/ttyUSB0 docs/wave/sine_iq_9M00_-6dBFS.WAVEFORM --play` |
| RX 链冒烟 | `python3 scripts/diag/rx_chain_smoke.py /dev/ttyUSB0` |

也可直接：`python gui/adda_test_gui_qt.py`（在 `tools/` 目录下）。

## 说明

- **UART**：**921600 8N1**（与 FPGA `rf_uart` 模块一致）
- Linux 串口一般为 `/dev/ttyUSB0`、`/dev/ttyACM0` 等；当前用户需 dialout 组权限（`sudo usermod -aG dialout $USER`）。

## scripts/ 脚本索引

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
| `vsg/` | `gen_sq_iq_clock.py` | 生成外部 VSG 用 20 MHz 方波 IQ `.bin` / `.WAVEFORM` |
| `utf8/` | `convert_all_to_utf8.py` | 批量将文本文件重编码为 UTF-8 |

## fpga/scripts/（工程脚本，非 PC 工具）

| 脚本 | 用途 |
|------|------|
| `create_project.tcl` | Vivado 工程一键生成 |
| `cbpro_to_mem.py` | ClockBuilder Pro 导出 → `fpga/data/*.mem` |
