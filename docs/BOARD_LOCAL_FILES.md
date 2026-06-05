# 板级本地文件（不入库）

以下资料含 **PIN 映射、原理图、时钟 init、实测指标**，仅保存在本地或公司内部存储，**勿提交 git**。

| 类别 | 本地路径 | 说明 |
|------|----------|------|
| FPGA 引脚约束 | `constraints/adda_io.xdc` | 由 `adda_io.template.xdc` 复制后按原理图填写 |
| 原理图 | `docs/schematics/*.pdf` | 自定义 ADDA 板 PDF |
| 系统框图 | `docs/VU13P_ADDA_整体设计框图.svg` | 板级架构图 |
| 测试指标 | `docs/metrics/*.xlsx` | ADC 实测 SNR/SFDR 等 |
| 初始化表 | `init_tables/*` | SI5340/AD9640/AD9117 配置与 `boot_rom.mem` |

## Vivado 约束组合

```
constraints/adda_io.xdc          ← 本地（从 template 生成）
constraints/adda_clocks.xdc      ← 仓库内
constraints/adda_dac_ddr.xdc     ← 仓库内（板级 skew 变量在本地调参）
```

## 与公开仓库的关系

公开 clone 本框架时 **不会** 获得上表文件。详见 [`OPEN_SOURCE.md`](OPEN_SOURCE.md)。
