# init_tables（本地板级配置，不入库）

本目录存放 **SI5340 / AD9640 / AD9117** 初始化表与 boot ROM 镜像，含时钟树与寄存器序列，属于板级机密，**不在 git 中跟踪**。

## 首次准备

1. 从内部资料获取 ClockBuilder Pro 导出表（`.txt`）及 `ad9640_init.txt`、`ad9117_init.txt`。
2. 生成各芯片 `.mem` 与合并 boot 镜像：

```bash
python tools/boot/cbpro_to_mem.py --chip si5340 Si5340-Registers.txt -o init_tables/si5340_init.mem
python tools/boot/cbpro_to_mem.py --chip ad9640 ad9640_init.txt -o init_tables/ad9640_init.mem
python tools/boot/cbpro_to_mem.py --chip ad9117 ad9117_init.txt -o init_tables/ad9117_init.mem

python tools/boot/cbpro_to_mem.py --concat \
  init_tables/si5340_init.mem init_tables/ad9640_init.mem init_tables/ad9117_init.mem \
  -o init_tables/boot_rom.mem
```

3. Vivado 工程中将 `init_tables/boot_rom.mem` 加为 Memory Initialization File，或设置 `BOOT_MEM_FILE` 指向该路径。

## 文件说明

| 文件 | 说明 |
|------|------|
| `Si5340-*-Registers.txt` | ClockBuilder Pro 导出（保留当前使用的一版即可） |
| `ad9640_init.txt` / `ad9117_init.txt` | 芯片 init 源表 |
| `*.mem` | `$readmemh` 用 boot 条目 |
| `boot_rom.mem` | 三芯片合并表（`boot_rom.v` 默认加载） |
