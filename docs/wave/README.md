# DAC 参考 IQ 波形

AD9117 DAC 路径（`dac_wave_player` → `tx_iq_dsp` 2× 半带插值 → `tx_ddr_out`）的循环复数正弦播放文件。
使用 `tools/adda/dac/wave_upload.py` 上传；用 `tools/adda/dac/gen_ref_waveforms.py` 重新生成本目录全部文件。

## 命名规范

```
sine_iq_<音调>_<电平>.<扩展名>
```

| 字段 | 含义 |
|------|------|
| `sine_iq` | 复数正弦，I/Q 交错 |
| `<音调>` | 音调频率，RKM 记法 — `9M00` = 9.00 MHz，`3M84` = 3.84 MHz |
| `<电平>` | 相对 s14 满幅（±8191）的幅度 dBFS：`-6dBFS`、`-12dBFS`、`-18dBFS` |
| `<扩展名>` | `.bin` = 小端序，`.WAVEFORM` = 大端序（内容相同，字节序相反） |

每个文件固定参数（未写入文件名）：**Fs = 61.44 MSa/s/ch**（sys_clk/2），
**1 MB** = 262144 个 IQ 样点，**相干记录**（整数周期 → 无缝循环与相干 FFT）。

## 幅度约定（统一 14-bit）

样本为 **有符号 14 位（±8191 = 满幅）**，存储在 int16 中。TX 链 **1:1** 映射到 DAC，不做 `>>2` / ÷4。dBFS 与峰值码字对应关系（每 6 dB 减半）：

| 电平 | 峰值（s14） |
|------|------------|
| −6 dBFS  | 4096 |
| −12 dBFS | 2048 |
| −18 dBFS | 1024 |

−6 dBFS 为默认工作电平：为半带插值器通带过冲留有余量（峰值建议 ≲7200 ≈ −1 dB，避免 `tx_iq_dsp.reduce14` 饱和）。

## 当前文件

| 文件 | 音调 | 电平 |
|------|------|------|
| `sine_iq_3M84_-6dBFS`  | 3.84 MHz | −6 dBFS  |
| `sine_iq_9M00_-6dBFS`  | 9.00 MHz | −6 dBFS  |
| `sine_iq_9M00_-12dBFS` | 9.00 MHz | −12 dBFS |
| `sine_iq_9M00_-18dBFS` | 9.00 MHz | −18 dBFS |

9 MHz 组构成 6 dB 步进幅度阶梯，可用于 SFDR-幅度扫描。每个文件同时提供 `.bin` 和 `.WAVEFORM` 两种格式。
