# DAC reference IQ waveforms

Looping complex-sine playback files for the AD9117 DAC path (`dac_wave_player`
→ `tx_iq_dsp` 2× halfband interp → `tx_ddr_out`). Upload with
`tools/adda/dac/wave_upload.py`; regenerate this whole folder with
`tools/adda/dac/gen_ref_waveforms.py`.

## Naming standard

```
sine_iq_<tone>_<level>.<ext>
```

| field | meaning |
|-------|---------|
| `sine_iq` | complex sine, interleaved I/Q |
| `<tone>`  | tone frequency, RKM notation — `9M00` = 9.00 MHz, `3M84` = 3.84 MHz |
| `<level>` | amplitude in dBFS vs s14 full scale (±8191): `-6dBFS`, `-12dBFS`, `-18dBFS` |
| `<ext>`   | `.bin` = little-endian, `.WAVEFORM` = big-endian (same data, byte-swapped) |

Fixed for every file (kept out of the name): **Fs = 61.44 MSa/s/ch** (sys_clk/2),
**1 MB** = 262144 IQ pairs, **coherent record** (integer cycles → seamless loop
and coherent FFT).

## Amplitude convention (unified 14-bit)

Samples are **signed-14 (±8191 = full scale)** stored in int16. The TX chain maps
them **1:1** to the DAC — no `>>2` / ÷4. dBFS ↔ peak code (each 6 dB halves it):

| level | peak (s14) |
|-------|-----------|
| −6 dBFS  | 4096 |
| −12 dBFS | 2048 |
| −18 dBFS | 1024 |

−6 dBFS is the default working level: it leaves headroom for the halfband
interpolator's passband overshoot (keep peak ≲7200 ≈ −1 dB to avoid saturation
in `tx_iq_dsp.reduce14`).

## Current files

| file | tone | level |
|------|------|-------|
| `sine_iq_3M84_-6dBFS`  | 3.84 MHz | −6 dBFS  |
| `sine_iq_9M00_-6dBFS`  | 9.00 MHz | −6 dBFS  |
| `sine_iq_9M00_-12dBFS` | 9.00 MHz | −12 dBFS |
| `sine_iq_9M00_-18dBFS` | 9.00 MHz | −18 dBFS |

The 9 MHz set forms a 6-dB amplitude ladder for SFDR-vs-level sweeps. Each stem
exists as both `.bin` and `.WAVEFORM`.
