# 第三方声明

## Verilog — INNOFIDEI 历史控制路径

以下文件保留了引用 INNOFIDEI Technologies（约 2007–2012 年）的历史文件头：

- `rf_ctrl_path/rf_ctrl_path.v`
- `rf_ctrl_path/rf_ctrl_reg.v`
- `rf_ctrl_path/rf_cmd_arb.v`
- `rf_ctrl_path/rf_spram_mux.v`
- `rf_ctrl_path/spi_cmd_state.v`
- `rf_ctrl_path/gpo_cmd_state.v`
- `rf_ctrl_path/spi_core/*.v`

如需再分发本仓库，请确认是否有权包含上述模块，或以全新实现替换。

## 芯片数据手册（`docs/specs/`）

`docs/specs/` 目录下的 PDF 文件版权归各芯片厂商所有（Analog Devices、Skyworks / Silicon Labs 等）。**本仓库不再跟踪这些文件**，请直接从厂商官网下载最新版本：

| 芯片 | 下载地址 |
|------|---------|
| SI5340 | [silabs.com](https://www.silabs.com/timing/clocks/high-performance-clocks/si5340) |
| AD9640 | [analog.com](https://www.analog.com/en/products/ad9640.html) |
| AD9117 | [analog.com](https://www.analog.com/en/products/ad9117.html) |

## 厂商工具

用于生成 SI5340 初始化表的 ClockBuilder Pro 导出文件，受 Silicon Labs 工具与器件许可条款约束。
