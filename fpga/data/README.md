# fpga/data — 芯片初始化配置

本目录存放三芯片（SI5340 / AD9640 / AD9117）上电 boot ROM 初始化表，供 `fpga/rtl/rf_ctrl_path/boot_rom.v` 加载。

## 文件说明

| 文件 | 说明 |
|------|------|
| `si5340_init.mem` | SI5340 SPI 初始化序列 |
| `ad9640_init.mem` | AD9640 SPI 初始化序列 |
| `ad9117_init.mem` | AD9117 SPI 初始化序列 |
| `boot_rom.mem` | 三芯片合并表，`boot_rom.v` 默认加载 |
| `*_init.txt` | 人类可读的寄存器表（源文本） |
| `Si5340-*.txt` | ClockBuilder Pro 导出（参考） |

如需针对不同时钟配置重新生成，使用 `fpga/scripts/cbpro_to_mem.py`：

```bash
python fpga/scripts/cbpro_to_mem.py --chip si5340 Si5340-Registers.txt  -o fpga/data/si5340_init.mem
python fpga/scripts/cbpro_to_mem.py --chip ad9640 ad9640_init.txt        -o fpga/data/ad9640_init.mem
python fpga/scripts/cbpro_to_mem.py --chip ad9117 ad9117_init.txt        -o fpga/data/ad9117_init.mem

python fpga/scripts/cbpro_to_mem.py --concat \
  fpga/data/si5340_init.mem fpga/data/ad9640_init.mem fpga/data/ad9117_init.mem \
  -o fpga/data/boot_rom.mem
```

在 Vivado 工程中将 `boot_rom.mem` 设为 `boot_rom.v` 的 Memory Initialization File，或通过参数 `BOOT_MEM_FILE` 指定路径。
