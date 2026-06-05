# init_tables — 芯片初始化配置

本目录包含 SI5340、AD9640、AD9117 三颗芯片的寄存器初始化序列，以及合并后的 boot ROM 镜像，供 `boot_rom.v` 在上电时自动完成三芯片配置。

## 文件说明

| 文件 | 说明 |
|------|------|
| `Si5340-RevB-*-Registers.txt` | ClockBuilder Pro 导出的 SI5340 寄存器序列（122.88 MHz 时钟树） |
| `Si5340-RevB-*-Project.slabtimeproj` | ClockBuilder Pro 工程文件 |
| `ad9640_init.txt` | AD9640 寄存器初始化序列（CMOS 并行输出模式，14-bit two's complement） |
| `ad9117_init.txt` | AD9117 寄存器初始化序列（DDR 模式，TWOS=1，IFIRST=1，IRISING=1） |
| `*.mem` | 各芯片 `$readmemh` 格式 boot 条目 |
| `boot_rom.mem` | 三芯片合并表，`boot_rom.v` 默认加载 |

## 生成 boot ROM

如需针对不同时钟配置重新生成，使用 `tools/boot/cbpro_to_mem.py`：

```bash
python tools/boot/cbpro_to_mem.py --chip si5340 Si5340-Registers.txt  -o init_tables/si5340_init.mem
python tools/boot/cbpro_to_mem.py --chip ad9640 ad9640_init.txt        -o init_tables/ad9640_init.mem
python tools/boot/cbpro_to_mem.py --chip ad9117 ad9117_init.txt        -o init_tables/ad9117_init.mem

python tools/boot/cbpro_to_mem.py --concat \
  init_tables/si5340_init.mem init_tables/ad9640_init.mem init_tables/ad9117_init.mem \
  -o init_tables/boot_rom.mem
```

在 Vivado 工程中将 `boot_rom.mem` 设为 `boot_rom.v` 的 Memory Initialization File，或通过参数 `BOOT_MEM_FILE` 指定路径。
