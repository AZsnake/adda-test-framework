# tools/

Utility scripts for the RF/ADDA repo. **Not added to Vivado.** Each category lives in its own subfolder.

## Layout

```
tools/
├── adda/
│   ├── lib/          # shared Python modules (import only, not run directly)
│   ├── gui/          # desktop GUI
│   ├── adc/          # ADC capture, analysis, chip diagnostics
│   ├── dac/          # DAC waveform generation and URAM upload
│   ├── diag/         # board smoke tests and low-level UART probes
│   ├── data/         # captured CSV / exports (gitignored samples OK)
│   └── requirements.txt
├── boot/             # boot ROM / init table generators
├── vivado/           # post-implementation Tcl (run from Vivado console)
└── utf8/             # repo text encoding utilities
```

## vivado/

| Script | Purpose |
|--------|---------|
| `report_dac_timing.tcl` | After `impl_1`: DAC `dac_dclkio` / `FPGA_DAC_DB` timing + bus skew → `dac_timing_summary.rpt` |

See [docs/dac_ddr_timing_bringup.md](../docs/dac_ddr_timing_bringup.md).

## adda/

| Folder | Script | Purpose |
|--------|--------|---------|
| `lib/` | `rf_uart_client.py` | Shared UART protocol library (CLI/GUI) |
| `lib/` | `adc_analysis.py` | FFT / DC-mask / metrics helpers |
| `gui/` | `adda_test_gui_qt.py` | **综合 ADDA 测试 GUI**（PySide6 + pyqtgraph） |
| `adc/` | `adc_capture_plot.py` | Snapshot capture + plot (CLI) |
| `adc/` | `adc_stream_capture.py` | Stream capture to file |
| `adc/` | `adc_ifft_analysis.m` | MATLAB post-processing |
| `adc/` | `ad9640_dump.py` | Dump AD9640 registers over UART/SPI |
| `adc/` | `ad9640_spi_diag.py` | AD9640 SPI write/read diagnostic |
| `dac/` | `gen_sine_iq_waveform.py` | Generate looping IQ sine `.bin` / `.WAVEFORM` |
| `dac/` | `gen_ref_waveforms.py` | Regenerate all `docs/wave/` reference sine files |
| `dac/` | `wave_upload.py` | Upload waveform to AD9117 URAM over UART |
| `diag/` | `rx_chain_smoke.py` | End-to-end RX chain smoke test |
| `diag/` | `rf_diag.py` | Raw UART ping / probe |

## boot/ & utf8/

| Folder | Script | Purpose |
|--------|--------|---------|
| `boot/` | `cbpro_to_mem.py` | ClockBuilder / CSV → `init_tables/*.mem` for `boot_rom` |
| `utf8/` | `convert_all_to_utf8.py` | Batch re-encode text files to UTF-8 |

## Quick start

```bash
# ADDA GUI (recommended)
pip install -r tools/adda/requirements.txt
python tools/adda/gui/adda_test_gui_qt.py
# or: tools/adda/run_adda_gui.bat

# ADC snapshot capture
python tools/adda/adc/adc_capture_plot.py -p COM3 -n 256

# DAC waveform upload
python tools/adda/dac/wave_upload.py COM7 docs/wave/sine_iq_9M00_-6dBFS.WAVEFORM --play

# Boot ROM image
python tools/boot/cbpro_to_mem.py --chip si5340 INPUT.txt -o init_tables/si5340_init.mem

# UTF-8 conversion
python tools/utf8/convert_all_to_utf8.py .
```
