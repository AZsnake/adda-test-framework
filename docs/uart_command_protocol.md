# 串口命令协议

PC 经 **UART 921600 8N1** 与 FPGA 通信；FPGA 解析 5 字节命令帧，路由到 SI5340 / AD9640 / AD9117 的 SPI（及 `rf_adda_top` 上的 ADC 快照 BRAM），并回复 4 字节 ACK。本文供 PC 工具与 Verilog（`uart_cmd_parser`）共用。

---

## 目录

1. [快速上手（可复制）](#1-快速上手可复制)
2. [帧格式](#2-帧格式)
3. [芯片 ID](#3-芯片-id)
4. [命令参考](#4-命令参考)
5. [返回帧与状态码](#5-返回帧与状态码)
6. [交互示例](#6-交互示例)
7. [FPGA 实现](#7-fpga-实现)
8. [LED 指示（`rf_adda_top`）](#8-led-指示rf_adda_top)

---

## 1. 快速上手

**串口：** 921600 8N1，HEX 发送/接收。每条命令固定 **5 字节**（`0xAA` 起）；ACK 固定 **4 字节**（`0xBB` 起）。校验：`ck = 0xBB ⊕ status ⊕ data`。

下方表格为完整上板调试清单（按推荐顺序）。ACK 列中 **加粗** 为会随芯片/板卡/状态变化的 `data` 字节；`status≠00` 时 `data` 恒为 `00`。本板 SI534x 读 `0x02`/`0x0C` 为 ADDA 实测。

### 1.1 命令大全

#### A. 上电后先查状态（等 boot 自动完成 ≈20 ms 后再发 SPI 类命令）

| 说明 | 发送（PC → FPGA） | 预期 ACK（FPGA → PC） |
|------|-------------------|------------------------|
| boot 状态（理想） | `AA 21 00 00 00` | `BB 00 70 CB` |
| 错误查询（无历史错误） | `AA FE 00 00 00` | `BB 00 00 BB` |
| Ping | `AA F0 00 00 00` | `BB 00 BB BB` |
| 读 FPGA 固件版本 | `AA F1 00 00 00` | `BB 00 01 BA` |

**`0x21` 其它常见 ACK data**（`ck = BB ⊕ 00 ⊕ data`）：

| data | 含义 |
|:----:|------|
| `70` | `busy=0, done=1, lolb=1, losxb=1, chip=0` — 配置完成且时钟正常 |
| `B1` | `busy=1, done=0, lolb=1, losxb=1, chip=1` — 正在配 SI5340 |
| `40` | `lolb=0` — PLL 未锁（查参考时钟 / 配置） |
| `00` | `losxb=0` — 无输入参考时钟 |

**`0xFE` 常见 ACK data**：

| data | 含义 |
|:----:|------|
| `00` | 无历史错误 |
| `05` | 上次命令因 boot 忙被拒（`status=05`） |
| `10` | SI5340 PLL lock 超时（boot 失败） |

#### B. 读芯片 ID / 版本（验证 SPI 双向）

| 说明 | 发送（PC → FPGA） | 预期 ACK（FPGA → PC） |
|------|-------------------|------------------------|
| SI5340 PN_BASE[15:8]（本板实测） | `AA 02 01 02 00` | `BB 00` **`40`** `FB` |
| SI5340 PN_BASE[7:0]（与 OPN 有关，请实测） | `AA 02 01 03 00` | `BB 00` **`53`** `E8` |
| SI5340 DEVICE_GRADE（本板实测） | `AA 02 01 0C 00` | `BB 00` **`C0`** `7B` |
| AD9640 Chip ID（Rev C = `0x11`） | `AA 02 02 01 00` | `BB 00` **`11`** `AA` |
| AD9117 Version 寄存器 | `AA 02 03 1F 00` | `BB 00` **`0A`** `B1` |

> SI5340 读回全 `00`：查 `pad_si5340_sdo` → `spi0_miso1`（[§7.2](#72-spi-物理层阶段一)）。AD9117 读回全 `FF`：查 `pad_dac_reset` 为低（SPI 模式）。

#### C. 单寄存器写（成功时 ACK data 恒 `00`）

| 说明 | 发送（PC → FPGA） | 预期 ACK（FPGA → PC） |
|------|-------------------|------------------------|
| 写 SI5340 reg `0x10` | `AA 01 01 10 AA` | `BB 00` **`00`** `BB` |
| 写 AD9640 reg `0x14` | `AA 01 02 14 01` | `BB 00` **`00`** `BB` |
| 写 AD9117 reg `0x05` | `AA 01 03 05 12` | `BB 00` **`00`** `BB` |
| 写 AD9117 reg0 = Reset | `AA 01 03 00 20` | `BB 00` **`00`** `BB` |
| 读 AD9640（为下一行做准备） | `AA 02 02 01 00` | `BB 00` **`11`** `AA` |
| 写 AD9117；ACK data 不得泄漏 `11` | `AA 01 03 05 AA` | `BB 00` **`00`** `BB` |

#### D. 芯片控制宏命令

| 说明 | 发送（PC → FPGA） | 预期 ACK（FPGA → PC） |
|------|-------------------|------------------------|
| AD9117 软复位 `0x20→0x00` | `AA 10 03 00 00` | `BB 00` **`00`** `BB` |
| AD9640 宏（写 reg0=`0x20`，非官方软复位） | `AA 10 02 00 00` | `BB 00` **`00`** `BB` |
| SI5340 宏（写 reg0=`0x20`，no-op） | `AA 10 01 00 00` | `BB 00` **`00`** `BB` |
| AD9117 输出使能开 | `AA 11 03 00 01` | `BB 00` **`00`** `BB` |
| AD9117 输出使能关 | `AA 11 03 00 00` | `BB 00` **`00`** `BB` |
| AD9117 掉电 | `AA 12 03 00 01` | `BB 00` **`00`** `BB` |
| AD9117 退掉电 | `AA 12 03 00 00` | `BB 00` **`00`** `BB` |

#### E. 突发写 `0x03`（命令帧后紧接 N 字节，无第二帧头）

| 说明 | 发送（PC → FPGA） | 紧接数据流 | 预期 ACK（FPGA → PC） |
|------|-------------------|------------|------------------------|
| AD9117 `addr=05` `N=3` | `AA 03 03 05 03` | `11 22 33` | `BB 00` **`03`** `B8` |
| AD9117 `addr=00` `N=4` | `AA 03 03 00 04` | `D0 D1 D2 D3` | `BB 00` **`04`** `BF` |
| SI5340 `addr=10` `N=2`（每字节 2 次 SPI） | `AA 03 01 10 02` | `AA BB` | `BB 00` **`02`** `B9` |

#### F. 初始化 / 复位

| 说明 | 发送（PC → FPGA） | 预期 ACK（FPGA → PC） |
|------|-------------------|------------------------|
| 触发 boot_fsm（空闲时） | `AA 20 00 00 00` | `BB 00` **`01`** `BA` |
| boot 完成后再次查询 | `AA 21 00 00 00` | `BB 00` **`70`** `CB` |
| 全局硬复位 10 ms → 自动重跑 boot | `AA F2 FF 00 00` | `BB 00` **`00`** `BB` |
| `F2` 非法 chip（须 `FF`） | `AA F2 00 00 00` | `BB` **`02`** **`00`** `B9` |

#### G. boot 忙时行为（boot 进行中发 SPI 类命令；`F0`/`21`/`FE` 仍可用）

| 说明 | 发送（PC → FPGA） | 预期 ACK（FPGA → PC） |
|------|-------------------|------------------------|
| boot 状态（配 SI5340 中） | `AA 21 00 00 00` | `BB 00` **`B1`** `0A` |
| SPI 写被拒 | `AA 01 03 05 12` | `BB` **`05`** **`00`** `BE` |
| 重复触发 boot 被拒 | `AA 20 00 00 00` | `BB` **`05`** **`00`** `BE` |
| Ping 仍成功 | `AA F0 00 00 00` | `BB 00` **`BB`** `BB` |

#### H. 故障注入（测完会污染 `0xFE`，建议放最后）

| 说明 | 发送（PC → FPGA） | 预期 ACK（FPGA → PC） |
|------|-------------------|------------------------|
| 未知命令 | `AA 55 00 00 00` | `BB` **`01`** **`00`** `BA` |
| 非法 chip | `AA 01 FF 00 55` | `BB` **`02`** **`00`** `B9` |
| 错误查询（读回 `status=01`） | `AA FE 00 00 00` | `BB 00` **`01`** `BA` |
| 再次错误查询（仍为 `01`） | `AA FE 00 00 00` | `BB 00` **`01`** `BA` |
| Ping（成功命令不清 err_reg） | `AA F0 00 00 00` | `BB 00` **`BB`** `BB` |
| 错误查询（仍为 `01`） | `AA FE 00 00 00` | `BB 00` **`01`** `BA` |

清 `err_reg`：发一条成功的 SPI/系统命令后再 `AA FE`；或上电/boot 无错时直接得 `00`。

#### I. ADC 快照捕获（`adc_capture`，chip 固定 `00`）

| 说明 | 发送（PC → FPGA） | 预期 ACK（FPGA → PC） | ACK 分析 |
|------|-------------------|------------------------|----------|
| ADC arm，`N=16` | `AA 30 00 00 10` | `BB 00` **`00`** `BB` | 捕获完成；`N={addr[3:0],data}={0,0x10}=16` |
| ADC arm，`N=1024` | `AA 30 00 04 00` | `BB 00` **`00`** `BB` | `N={0x04[3:0],0x00}=0x400=1024` |
| ADC arm，`N=0`（RTL 视为 4096） | `AA 30 00 00 00` | `BB 00` **`00`** `BB` | `adc_capture` 将 `N=0` 当作 4096 |
| ADC read **hi**，BRAM 地址 `0x000` | `AA 31 00 00 00` | `BB 00` **`xx`** `cc` | **data** = 样本 `[13:6]`（14 bit 高 8 位） |
| ADC read **hi**，BRAM 地址 `0x005` | `AA 31 00 00 05` | `BB 00` **`EA`** `51` | 例：BRAM=`14'h3ABC` → `[13:6]`=`0xEA` |
| ADC read **lo**，BRAM 地址 `0x005` | `AA 32 00 00 05` | `BB 00` **`3C`** `87` | 例：BRAM=`14'h3ABC` → `{2'b00, [5:0]}`=`0x3C` |
| 重组 14 位样本 | — | — | `sample = (hi << 6) \| (lo & 0x3F)` |
| 捕获进行中再次 arm | `AA 30 00 00 10` | `BB` **`05`** **`00`** `BE` | `i_adc_busy=1` 时仅 `0x30` 被拒 |
| 捕获进行中读 BRAM | `AA 31 00 00 05` | `BB 00` **`xx`** `cc` | `0x31`/`0x32` 不受 `adc_busy` 限制 |
| 非法 chip（须 `00`） | `AA 30 01 00 10` | `BB` **`02`** **`00`** `B9` | ADC 命令不经 SPI |

**12 位字段编码（`0x30` / `0x31` / `0x32` 共用）：**

```text
{addr[3:0], data[7:0]}   # addr = 帧 byte3，data = 帧 byte4
```

| 命令 | 字段含义 | 范围 |
|:----:|----------|------|
| `0x30` | 采样个数 `N` | `1`…`4096`（`N=0` → 4096） |
| `0x31` | BRAM 读地址（返回 14 bit 样本的 `[13:6]`） | `0`…`4095`（须 `< N`，否则为未写入垃圾） |
| `0x32` | BRAM 读地址（返回 14 bit 样本的 `{2'b00, [5:0]}`） | 同上 |

**推荐流程：** `0x30` arm → 等 ACK → 循环对每个 `addr` 发送 `0x31` 取高 8 位、再发送 `0x32` 取低 6 位，PC 端重组：`sample14 = (hi << 6) | (lo & 0x3F)`。

#### J. DAC 波形发生器（`dac_tone_gen`，chip 固定 `00`）

| 说明 | 发送（PC → FPGA） | 预期 ACK（FPGA → PC） | ACK 分析 |
|------|-------------------|------------------------|----------|
| 启动波形输出 | `AA 40 00 00 01` | `BB 00` **`01`** `BA` | 使能输出；按当前波形/频率/幅度配置驱动 DAC |
| 停止波形输出 | `AA 40 00 00 00` | `BB 00` **`00`** `BB` | DAC 输出回中点 `0x0000` |
| 设波形 = 正弦 | `AA 41 00 00 00` | `BB 00` **`00`** `BB` | `data[1:0]=0` |
| 设波形 = 方波 | `AA 41 00 00 01` | `BB 00` **`01`** `BA` | `data[1:0]=1` |
| 设波形 = 三角波 | `AA 41 00 00 02` | `BB 00` **`02`** `B9` | `data[1:0]=2` |
| 设频率字高字节 | `AA 42 00 00 02` | `BB 00` **`02`** `B9` | `freq_word[15:8]=0x02` |
| 设频率字低字节 | `AA 42 00 01 22` | `BB 00` **`22`** `99` | `freq_word[7:0]=0x22`（示例最终 `0x0222`） |
| 设幅度 50% | `AA 43 00 00 32` | `BB 00` **`32`** `89` | `amp_pct=0x32=50` |
| boot 进行中启动 | `AA 40 00 00 01` | `BB` **`05`** **`00`** `BE` | boot_busy 期间拒绝，与 SPI 类命令一致 |
| 非法 chip（须 `00`） | `AA 40 01 00 01` | `BB` **`02`** **`00`** `B9` | — |

**说明：**
- AD9117 init（`reg 0x02 = 0xB4`）：TWOS(b7)=1（二进制补码）、IFIRST(b5)=1、IRISING(b4)=1、DCI_EN(b2)=1、DDR。⚠ `0x34`（TWOS=0，上电默认）为无符号二进制，与 FPGA 输出不匹配。
- `dac_tone_gen` / `dac_wave_player` 均以 61.44 MSa/s/ch 输出 16-bit 并行 I/Q，经 `tx_iq_dsp` 2× 插值后由 `tx_ddr_out` ODDRE1 交织到 `FPGA_DAC_DB`（I@DCLKIO 上升沿 / Q@下降沿）。
- `0x40` 仅控制开关（兼容旧工具）；`0x41`/`0x42`/`0x43` 分别配置波形、频率字、幅度。
- `0x42` 编码：`addr=0` 写高字节、`addr=1` 写低字节，最终形成 `freq_word[15:0]`。
- `freq_word` 与输出频率关系：`f_out = freq_word * SYS_CLK_HZ / 65536`。在 `SYS_CLK_HZ=122.88 MHz` 时，`freq_word=85` 对应约 160 kHz（旧 19.2 MHz 默认 `freq_word=546`）。
- `0xF2` 全局复位会清零 `o_dac_tone_en` 并恢复 DAC 参数默认值（正弦、160 kHz、50%）。

#### K. 垃圾字节重同步

| 说明 | 发送（PC → FPGA） | 预期 ACK（FPGA → PC） |
|------|-------------------|------------------------|
| 非 `0xAA` 前缀（忽略） | `55 F0` | — |
| 下一帧重新对齐 | `AA F0 00 00 00` | `BB 00` **`BB`** `BB` |

### 1.2 编码与模板

**`0x21` 状态字节：** `{busy[7], done[6], lolb[5], losxb[4], chip[3:0]}`

| 位域 | 含义 |
|------|------|
| `busy` | `1` = boot_fsm 正在配置 |
| `done` | 累计完成标志（首次 boot 后置 `1`，重新触发清零） |
| `lolb` | `1` = SI5340 PLL 已锁（实时管脚，与 boot_err 独立） |
| `losxb` | `1` = SI5340 输入参考时钟存在 |
| `chip[3:0]` | 当前配置芯片：`0` 空闲/完成 · `1` SI5340 · `2` AD9640 · `3` AD9117 |

| 命令模板 | 发送（PC → FPGA） |
|----------|-------------------|
| 单寄存器写 | `AA 01 <chip> <addr> <data>` |
| 单寄存器读 | `AA 02 <chip> <addr> 00` |
| Ping（系统命令） | `AA F0 00 00 00` |
| ADC arm，`N` 样本 | `AA 30 00 <addr_hi> <data_lo>` |
| ADC read，BRAM 地址 | `AA 31 00 <addr_hi> <data_lo>` |

| 芯片 ID | 芯片 | 说明 |
|:-------:|:-----|:-----|
| `00` | — | 系统命令 `F0`–`FE` |
| `01` | SI5340 | spi0，4-wire |
| `02` | AD9640 | spi1，3-wire SDIO |
| `03` | AD9117 | spi2，3-wire SDIO |
| `FF` | 广播 | 仅 `F2` 全局复位 |

---

## 2. 帧格式

### 2.1 命令帧（PC → FPGA）— 固定 5 字节

以 `0xAA` 同步；收到帧头后才开始解析后续 4 字节。

| 偏移 | 字段 | 说明 |
|:----:|:-----|:-----|
| 0 | `0xAA` | 帧头 |
| 1 | cmd | [命令字](#4-命令参考) |
| 2 | chip | [芯片 ID](#3-芯片-id) |
| 3 | addr | 寄存器地址或命令参数 |
| 4 | data | 写入值 / 长度 N / 占位 `00` |

**突发写 `0x03`：** 上表 5 字节中 `addr`=起始地址、`data`=字节数 `N`；**无额外帧头**，紧接发送 `N` 字节 `d0…d(N-1)`（典型：SI5340 初始化表）。

```text
AA 03 <chip> <addr> <N>   # 命令帧
<d0> <d1> … <d(N-1)>      # 数据流（连续 N 字节）
```

### 2.2 返回帧（FPGA → PC）— 固定 4 字节

每条命令均回复。

| 偏移 | 字段 | 说明 |
|:----:|:-----|:-----|
| 0 | `0xBB` | 帧头 |
| 1 | status | [状态码](#5-返回帧与状态码) |
| 2 | data | 读回值、版本、进度等 |
| 3 | checksum | `0xBB ⊕ status ⊕ data` |

---

## 3. 芯片 ID

| ID | 芯片 | SPI 通道 | 说明 |
|:--:|:-----|:---------|:-----|
| `01` | SI5340 | spi0，4-wire，16 bit/帧 | 时钟；单次访问自动 2 帧 CS |
| `02` | AD9640 | spi1，3-wire SDIO，24 bit | ADC（原理图位号 AD9627，时序同 AD9640） |
| `03` | AD9117 | spi2，3-wire SDIO，16 bit | DAC；`addr[7:5]` 须为 0 |
| `00` | — | 不经 SPI | 系统命令 `F0`–`FE`、`20`/`21`、`30`–`33`、`40`–`43` 填 `00` |
| `FF` | 广播 | 全部芯片 | 仅用于 `F2` 全局复位 |

---

## 4. 命令参考

### 4.1 寄存器访问

| cmd | 名称 | addr | data | 可复制示例 |
|:---:|:-----|:-----|:-----|:-----------|
| `01` | 写 | 目标 | 写入值 | `AA 01 03 00 20` |
| `02` | 读 | 目标 | `00` | `AA 02 03 1F 00` |
| `03` | 突发写 | 起始 | 长度 N | `AA 03 01 00 10` + 16 字节数据 |

读操作：ACK 的 **data** 字节为读回值。写操作（`01`）及无数据系统命令：ACK 的 **data** 固定为 `00`（勿沿用上一次读回值）。

### 4.2 芯片控制

封装常用寄存器写，PC 无需记芯片内部地址。

| cmd | 名称 | addr | data | 可复制示例 |
|:---:|:-----|:-----|:-----|:-----------|
| `10` | 软复位 | `00` | `00` | `AA 10 03 00 00` |
| `11` | 输出使能 | `00` | `01`开 / `00`关 | `AA 11 03 00 01` |
| `12` | 掉电 | `00` | `01`掉电 / `00`正常 | `AA 12 03 00 00` |

> `10` 对 AD9117 等价于写 `reg[0x00]=0x20` 再写 `0x00`（对 PC 透明）。

### 4.3 初始化

| cmd | 名称 | 帧 | 说明 |
|:---:|:-----|:---|:-----|
| `20` | 执行预置初始化 | `AA 20 00 00 00` | SI5340 → AD9640 → AD9117；可多次 ACK |
| `21` | 初始化状态查询 | `AA 21 00 00 00` | 返回各芯片是否完成 |

### 4.4 ADC 快照捕获（chip 固定 `00`）

经 `adc_iq_snapshot` 在 `sys_clk` 域缓存 **`adc_iq_rx_chain` 输出的 I/Q**（不是原始 ADC 14-bit！数据已经过 CIC 抽取 → DDC → IQ 平衡 → FIR 链路），由 UART 解析器在 `sys_clk` 域等待快照完成。与 SPI / boot **无关**。要看原始 ADC 输入，先 `0x45 data=0x18`（fir_bypass=1, iq_bypass=1, dec=1x）再 `0x30`。

`0x30` arm 永远同时启动 A、B 两路。`0x31`/`0x32`/`0x33` 由 **`addr[6]`** 选通道（`0=I/A`，`1=Q/B`），`addr[5:0] + data[7:0]` 仍是 14-bit BRAM 地址。`0x45` 现用于 RX 链参数配置（抽取比/快照与流式模式/IQ 与 FIR bypass，详见 4.6）。

| cmd | 名称 | addr + data 编码 | ACK | 说明 |
|:---:|:-----|:-----------------|:----|:-----|
| `30` | ADC arm | `N = {addr[5:0], data[7:0]}` | `status=00`，**data=`00`** | 同时拉高两路 `o_adc_arm` 直至两路 `i_adc_done` 都置位（FSM 内部为 done_a & done_b）；采满 `N` 个样本后 ACK |
| `31` | ADC read **hi** | `chan = addr[6]`；`addr = {addr[5:0], data[7:0]}` | **data = 样本 `[13:6]`** | BRAM 读口 1 周期延迟；返回 14 bit 样本的**高 8 位** |
| `32` | ADC read **lo** | `chan = addr[6]`；`addr = {addr[5:0], data[7:0]}` | **data = `{2'b00, 样本[5:0]}`** | 返回 14 bit 样本的**低 6 位**（编码在 ACK data 的低 6 bit）|
| `33` | ADC **burst read** | `chan = addr[6]`，其它字段忽略 | 见下 | 流式读出最近 `0x30` arm 的全部 `N` 个样本：先 `2N` 字节负载 + 4 字节 ACK 收尾 |

| 可复制示例 | 发送 | 含义 |
|:-----------|:-----|:-----|
| arm 1024 点 | `AA 30 00 04 00` | `N=0x400=1024` |
| arm 16 点 | `AA 30 00 00 10` | `N=16` |
| 读地址 0 高 8 位 | `AA 31 00 00 00` | BRAM `[0]` `[13:6]` |
| 读地址 0 低 6 位 | `AA 32 00 00 00` | BRAM `[0]` `{2'b00, [5:0]}` |
| 读地址 5 高 8 位 | `AA 31 00 00 05` | BRAM `[5]` `[13:6]` |
| 读地址 5 低 6 位 | `AA 32 00 00 05` | BRAM `[5]` `{2'b00, [5:0]}` |
| burst 全部读出 | `AA 33 00 00 00` | 收 `2N` 字节流 + `BB 00 <xor8> <ck>` |
| 14 位重组 | — | `sample = (hi << 6) \| (lo & 0x3F)` |

- **BRAM 深度：** 4096×14 bit（`adc_capture.DEPTH`）；`N=0` 时 RTL 按 4096 处理。
- **忙拒绝：** `i_adc_busy=1` 时新的 `0x30` 返回 `status=05`；`0x31`/`0x32`/`0x33` 仍可读已捕获数据。
- **时钟：** `adc_clk` = 122.88 MHz（`FPGA_ADC_DCOA`，由 SI5340 OUT0 → AD9640 DCOA）；捕获时长 ≈ `N / 122.88e6` s（加 CDC 裕量）。

#### 0x33 ADC burst read 详细

5 字节命令帧 `AA 33 00 00 00`，chip/addr/data 字段忽略（FPGA 使用最近一次 `0x30`
锁存的样本数 `N`，未先 arm 时按上电默认 `N=0 → 4096` 处理）。

响应**没有逐样本 ACK**：FPGA 先连续吐出 `2N` 字节的原始负载，紧接 1 个 4 字节 ACK 收尾。

```
hi[0] lo[0] hi[1] lo[1] ... hi[N-1] lo[N-1]   BB <status> <xor8> <checksum>
```

| 字段 | 含义 |
|------|------|
| `hi[i]` | `sample[i][13:6]` |
| `lo[i]` | `{2'b00, sample[i][5:0]}` |
| `status` | 同其他 ACK，目前固定 `0x00`（成功）|
| `xor8`   | 整段 `2N` 字节负载逐字节异或（数据完整性校验）|
| `checksum` | `0xBB ^ status ^ xor8` |

PC 侧应：在写完 5 字节命令后，先阻塞读 `2N` 字节负载，再读 4 字节 ACK，最后用 `xor8`
校验负载完整性。921600 8N1 下，4096 点的负载约 89 ms；相比逐样本 `0x31`/`0x32`
往返快约 8×。

依赖：必须先发 `0x30` 把 `N` 锁定。`0x33` 期间 BRAM 写口若被新的 `0x30` 重新触发会污染
读出数据，因此推荐流程是 `arm → wait ACK → burst → 处理`。

### 4.6 DAC 波形发生器（chip 固定 `00`）

`0x40 DAC_TONE_EN`：仅使能/关闭 DAC 波形输出。  
`0x41 DAC_WAVE_SEL`：设置波形类型。  
`0x42 DAC_FREQ_WORD`：设置 16-bit 频率字（分高/低字节写入）。  
`0x43 DAC_AMP_PCT`：设置幅度百分比（0..100）。

| 项目 | 值 |
|------|----|
| 帧 | `AA 40 00 00 <01/00>` |
| ACK | `BB 00 <01/00> <chk>` |
| 频率配置 | `AA 42 00 00 <hi>` + `AA 42 00 01 <lo>`，组成 `freq_word={hi,lo}` |
| 波形配置 | `AA 41 00 00 <wave>`，`wave`: `0=sine, 1=square, 2=triangle, 3=ramp, 4=dc_test(I=FS,Q=0)` |
| 幅度配置 | `AA 43 00 00 <amp_pct>`，范围 `0..100`（超范围会钳位） |
| 数据格式 | 14-bit two's-complement，中点 `0x0000`，幅度由 `amp_pct` 缩放（0..100% FS） |
| 接口 | DDR 交织（TWOS=1, IFIRST=1, IRISING=1；`reg 0x02=0xB4`） |
| 时序 | 基带 61.44 MSa/s/ch → `tx_iq_dsp` 2× → 122.88 MSa/s/ch；`tx_ddr_out` ODDRE1 交织 @245.76 MSa/s；DCLKIO 由 `sys_clk_dco`(90°) 驱动 |
| 频率换算 | `f_out = freq_word * SYS_CLK_HZ / 65536`，`SYS_CLK_HZ=122.88 MHz` 时 `freq_word=85` 约为 160 kHz |
| 忙拒绝 | `boot_busy=1` 时返回 `status=05`；`adc_busy` 不影响 |
| 关停回退 | `0x40 data=0`、`0xF2` 全局复位、`pad_adda_rstn=0` 都会把 DB 拉回 `0x0000` |

**典型流程：** `AA 20` 触发 boot → `AA 41` 选波形 → `AA 42` 写频率字高/低字节 → `AA 43` 写幅度 → `AA 40 00 00 01` 开音 → `AA 40 00 00 00` 关音。

### 4.6.1 数字 DDC 复混频（chip 固定 `00`）

板上模拟 IQ 解调器把 I/Q 差分对分别送到 AD9640 通道 A、B；FPGA 端再用一个轻量数字 NCO + 复混频器（`ddc_complex_mixer_v2.v`）做残余载波修正：

```
I' = I·cos(ωt) − Q·sin(ωt)
Q' = I·sin(ωt) + Q·cos(ωt)        f_NCO = freq_word · adc_clk / 65536
```

`0x44` 写 16-bit NCO 频率字（高/低字节分两次写，编码与 `0x42` 相同）；`0x45` 配置 RX 链控制位：`data[1:0]=dec_ratio(1x/2x/4x)`、`data[2]=capture_mode(0=snapshot,1=stream)`、`data[3]=fir_bypass`、`data[4]=iq_bypass`、`data[6:5]=fir_sel`（FIR 系数档：`0=Fs/8` 默认、`1=Fs/16` 窄、`2=CIC droop comp`（sinc³ 逆补偿，配合抽取使用）、`3=all-pass` 全通）。两条命令都立即生效、跨复位保持默认。

| cmd | 名称 | addr + data 编码 | ACK | 说明 |
|:---:|:-----|:-----------------|:----|:-----|
| `44` | NCO freq | `addr=0` 写 `freq[15:8]`；`addr=1` 写 `freq[7:0]` | data 回送写入字节 | 复位/`0xF2` 后默认 `0`（NCO 不转） |
| `45` | RX cfg | `data[6:0]` | data 回显写入值 | `data[1:0]=dec_ratio`，`data[2]=capture_mode`，`data[3]=fir_bypass`，`data[4]=iq_bypass`，`data[6:5]=fir_sel`；复位默认 `0x18`（bypass 全开、dec=1x、fir_sel=0） |

`fir_sel` 仅在 `fir_bypass=0` 时影响输出；`fir_bypass=1` 时 FIR 直通（与 `fir_sel` 无关）。系数档为准静态：切档后第一拍系数稳定，不影响吞吐。`fir_sel=3`（all-pass）与 `fir_bypass=1` 的区别是前者仍走 MAC 流水（延迟与真实滤波一致），便于做「FIR 在路但不整形」的对照。

`fir_sel=2`（CIC droop comp）补偿前级 `cic_decimator` 的 sinc³ 通带下垂，**仅在抽取开启时（`dec_ratio>0`）有意义**；`dec_ratio=0`（CIC 直通）时无下垂可补，请改用 `0`/`1` 或直接 `fir_bypass=1`。15 阶 FIR 受限：补偿后 CIC×comp 在输出 Nyquist 的 `F≤0.10` 内平坦到 ~0.18 dB p-p、`F≤0.15` 内 ~0.40 dB p-p（未补偿时分别为 −0.43 / −0.97 dB）。系数由 `tools/adda/adc/gen_cic_comp_fir.py` 生成。**推荐采集组合：** `dec_ratio>0` + `fir_bypass=0` + `fir_sel=2`，即 `0x45 data=0x51`（dec=2x、fir on、iq_bypass、fir_sel=2）或 `data=0x52`（dec=4x）。`fir_sel` 默认仍为 OFF（`fir_bypass=1`），原始全速采集不受影响。

**典型流程：** `AA 30 …` 先采一次原始 A/B 看时域；`AA 44 00 00 <hi>` + `AA 44 00 01 <lo>` 写 NCO 频率；`AA 45 00 00 01` 切到混频通路；再 `AA 30 …` 采一次 → PC 端 FFT 应看到峰值平移 `f_NCO`。

`freq_word=0` 等价于 `cos=peak / sin=0`，I'/Q' ≈ raw A/B（仅有一次乘法的 ~0.0001% 增益损失）。

### 4.6.2 IQ 平衡（`rf_iq_balance14`，chip 固定 `00`）

模拟 IQ 解调残余的幅相不平衡 + DC 漂移由 `rf_iq_balance14` 在 `adc_clk` 域校正：

```
I' = I + offset_i
Q' = ( (I + offset_i) * op1 + (Q + offset_q) * op2 ) >> 14     # Q2.14 系数
```

`op1` / `op2` 均为 **Q2.14 有符号** 16-bit；`op1=0x4000`（=1.0）、`op2=0` 即恒等。`offset_i`/`offset_q` 是 **14-bit signed** DC 偏置，加到 ADC 中心化后样本上。所有四个寄存器在 `0xF2` / 上电后回到默认值。

| cmd | 名称 | addr + data 编码 | ACK | 说明 |
|:---:|:-----|:-----------------|:----|:-----|
| `46` | IQ balance op1 (Q2.14) | `addr=0` 写 `op1[15:8]`；`addr=1` 写 `op1[7:0]` | data 回送写入字节 | 默认 `0x4000` |
| `47` | IQ balance op2 (Q2.14) | `addr=0` 写 `op2[15:8]`；`addr=1` 写 `op2[7:0]` | data 回送写入字节 | 默认 `0x0000` |
| `48` | DC offset I (s14) | `addr=0` 写 `offset_i[13:8]`（仅 `data[5:0]` 有效）；`addr=1` 写 `offset_i[7:0]` | data 回送写入字节 | 默认 `0` |
| `49` | DC offset Q (s14) | `addr=0` 写 `offset_q[13:8]`（仅 `data[5:0]` 有效）；`addr=1` 写 `offset_q[7:0]` | data 回送写入字节 | 默认 `0` |

**写入顺序：** 高字节先、低字节后（两条 5-byte 帧）。`0x45` 的 `iq_bypass=1` 时整个 IQ 平衡块直通，OP1/OP2/offset 立即可被「下次 bypass=0」启用。

**典型流程（消镜频）：**
1. `AA 45 00 00 11` — `iq_bypass=1, fir_bypass=1, dec=1x`，先看原始残余镜像
2. `AA 30 …` snapshot → PC 端 FFT 测幅度不平衡与相位差
3. 写 `op1`、`op2`、`offset_i`、`offset_q`
4. `AA 45 00 00 01` — 关 `iq_bypass`
5. 再 `0x30` 比对镜像抑制比

### 4.6.3 ADC 流式回送 `0x34`（chip 固定 `00`）

`rf_uart` 内置 4-byte/sample 串行器（`adc_iq_stream_drain`），把 `adc_iq_rx_chain` 输出按 `I_hi, I_lo, Q_hi, Q_lo` 顺序串到 UART。`0x30` snapshot 与 `0x34` stream 共用同一条 RX 链，但 `0x34` 不写 BRAM、直接吐字节。

| 模式 | 帧 | 行为 |
|------|----|------|
| Bounded `N>0` | `AA 34 00 <addr_hi> <data_lo>` | `N={addr[5:0],data[7:0]}` 个 IQ 样本，**`4N` 字节负载** + 4-byte ACK |
| Continuous `N==0` | `AA 34 00 00 00` | FPGA 持续吐字节直到主机发**任意 UART 字节**为止；FPGA 补齐当前样本（4 字节边界对齐）后再发 ACK |

**ACK 格式：** `BB <status> <xor8> <ck>`，`xor8` 是 `4N`（或停止前实际发送）字节负载的逐字节异或，`ck = BB^status^xor8`。`status=0x00` 成功，`status=0x05` 说明 `stream_drain` 期间 `o_overflow=1`（FPGA 内部 256-byte FIFO 被 IQ 链跑满，PC 收不及）。

**14-bit 重组：** `I = (I_hi << 6) | (I_lo & 0x3F)`，Q 同。`I_lo`/`Q_lo` 高 2 位固定为 0，主机可用作完整性检查。

**吞吐：** 921600 8N1 → 92.16 kB/s ≈ 23040 IQ/s。若 `dec_ratio=1x` 且 ADC 持续输出 122.88 MS/s，`stream_drain` FIFO 几乎瞬间溢出 → 必须先用 `0x45` 抬 `dec_ratio` 或确保上游 valid 稀疏。

**典型流程：**
```
→  AA 45 00 00 06          # dec=2x, capture_mode=1, bypass全开
→  AA 34 00 04 00          # N=1024 → 4096 字节负载 + ACK
←  <4096 bytes>            # I_hi, I_lo, Q_hi, Q_lo, ...
←  BB 00 <xor8> <ck>
```

连续模式：
```
→  AA 34 00 00 00
←  <持续字节流>
→  AA                       # 任意单字节即停止
←  <剩余补齐字节> BB 00 <xor8> <ck>
```

### 4.7 系统级（chip 固定 `00`）

| cmd | 名称 | 帧 | ACK data 含义 |
|:---:|:-----|:---|:--------------|
| `F0` | Ping | `AA F0 00 00 00` | 常为 `BB`（与 ACK 帧头一致） |
| `F1` | 读版本 | `AA F1 00 00 00` | FPGA 固件版本 |
| `F2` | 全局复位 | `AA F2 FF 00 00` | chip=`FF` 广播 |
| `FE` | 错误查询 | `AA FE 00 00 00` | 上一条命令错误码 |

### 4.8 命令字速查

| 范围 | 类别 |
|------|------|
| `01`–`03` | 寄存器读 / 写 / 突发写 |
| `10`–`12` | 芯片控制 |
| `20`–`21` | 初始化 |
| `30`–`33` | ADC 快照 arm / 高 8 位读 / 低 6 位读 / burst 全量读（`addr[6]` 选通道） |
| `34` | ADC 流式回送（bounded `N>0` 或 continuous，`xor8` 校验） |
| `40`–`43` | DAC 波形发生器（开关 / 波形 / 频率字 / 幅度） |
| `44`–`45` | 数字 DDC（NCO 频率字 / RX 链配置） |
| `46`–`49` | IQ 平衡（op1 / op2 Q2.14、DC offset I/Q s14） |
| `F0`–`F2`, `FE` | 系统级 |

---

## 5. 返回帧与状态码

**校验：** `checksum = 0xBB ⊕ status ⊕ data`（异或，与下文示例一致）。

| status | 含义 |
|:------:|:-----|
| `00` | 成功 |
| `01` | 未知命令字 |
| `02` | 芯片 ID 无效 |
| `03` | SPI 超时 |
| `04` | 校验错误 |
| `05` | boot 或 ADC 捕获忙，命令被拒绝（`boot_fsm` busy 拒 SPI/`0x20`；`adc_capture` busy 仅拒 `0x30`） |

---

## 6. 交互示例

每条：**发送一行复制 → 接收一行对照**。校验列可自行验算 `BB ⊕ status ⊕ data`。

### Ping

```text
→  AA F0 00 00 00
←  BB 00 BB BB
```

### 读 AD9117 版本寄存器 `0x1F`（假设读回 `0x0A`）

```text
→  AA 02 03 1F 00
←  BB 00 0A B1          # B1 = BB ⊕ 00 ⊕ 0A
```

### 全局复位

```text
→  AA F2 FF 00 00
←  BB 00 00 BB
```

### 预置初始化（多帧 ACK）

```text
→  AA 20 00 00 00
←  BB 00 01 …            # 进行中
←  BB 00 FF 44          # 全部完成；44 = BB ⊕ 00 ⊕ FF
```

### ADC arm（1024 点）

```text
→  AA 30 00 04 00       # N = {0x04, 0x00} = 1024
←  BB 00 00 BB          # 捕获完成，status OK，data 固定 00
```

### ADC read（读 BRAM 地址 0）

```text
→  AA 31 00 00 00
←  BB 00 xx cc          # data = 样本 [13:6]；cc = BB ⊕ 00 ⊕ xx（搭配 0x32 取低 6 位重组 14 bit）
```

### ADC read（地址 5，BRAM = 14'h3ABC）

```text
→  AA 31 00 00 05
←  BB 00 EA 51          # 14'h3ABC [13:6] = 0xEA；51 = BB ⊕ 00 ⊕ EA
→  AA 32 00 00 05
←  BB 00 3C 87          # 14'h3ABC [5:0] = 0x3C → data = {2'b00, 0x3C} = 0x3C；87 = BB ⊕ 00 ⊕ 3C
# 重组：sample = (0xEA << 6) | (0x3C & 0x3F) = 0x3A80 | 0x3C = 0x3ABC ✓
```

### ADC 忙时再次 arm

```text
→  AA 30 00 00 10       # 上一笔捕获尚未结束
←  BB 05 00 BE          # status=05，data=00
```

---

## 7. FPGA 实现

### 7.1 解析状态机（`uart_cmd_parser`）

每状态收 **1 字节**；`0x03` 在 `RECV_DATA` 后继续收 N 字节流。

```text
IDLE ──(0xAA)──► RECV_CMD ──► RECV_CHIPID ──► RECV_ADDR ──► RECV_DATA
                                                                    │
                    ┌───────────────────────────────────────────────┤
                    ▼                                               ▼
              ADC_WAIT (0x30)                                  DECODE
                    │                                               │
                    ▼                                    WAIT_SPI / BURST …
            ADC_RD (0x31/0x32)                                        │
                    │                                               ▼
                    └──────────────► SEND_ACK ◄─────────────────────┘
                                          │
                                          ▼
                                        IDLE
```

| 状态 | 行为 |
|------|------|
| IDLE | 等 `0xAA` |
| RECV_CMD / CHIP / ADDR / DATA | 锁存 cmd、chip、addr、data |
| DECODE | 路由 SPI；`0x03` 收满 N 字节；`0x30`/`0x31`/`0x32` 进 ADC 分支 |
| WAIT_SPI | 等 `spi_done` |
| ADC_WAIT | `0x30`：保持 `o_adc_arm` 直至 `i_adc_done` 或 `i_adc_busy` 下降沿 |
| ADC_RD | `0x31`/`0x32`：等 2 个 `sys_clk` 周期后锁存样本；`0x31` 取 `[13:6]`，`0x32` 取 `{2'b00, [5:0]}` |
| SEND_ACK | UART 发 4 字节 ACK |

### 7.2 SPI 物理层（阶段一）

- **Mode 0：** CPOL=0，CPHA=0，MSB first；`spi0` 四线 `bidirection=0`，`spi1`/`spi2` 三线 `bidirection=1`。
- **SI5340 MISO（`rf_adda_top`）：** `rf_spi_core` 在 `bidirection=0` 时采样 **`spi0_miso1`**（4 线 SDO），`bidirection=1` 时采样 `spi0_miso0`（3 线 SDIO）。板级须把 `pad_si5340_sdo` 接到 `spi0_miso1`；若误接 `miso0` 则读回恒为 `00`。
- **UART 地址：** 8 bit = 寄存器低字节，隐含 **page=0**（`00`–`FF`）。
- **SI5340：** 单次读/写 = `SetAddr` + `Read`/`Write` 两次 CS（各 16 bit），`uart_spi_pack` 自动组帧。
- **AD9640：** 24 bit（16b 指令 + 8b 数据）；**AD9117：** 16 bit（`addr[4:0]` 有效）。
- **AD9640 指令字（`uart_spi_pack`）：** 16 bit = `{R/W, W1, W0, 5'b0, addr[7:0]}`；读 `0x01`（Chip ID）→ `0x8001`，勿写成 24 bit 拼接（会截断成写 `0x0001`）。
- **三线 SDIO（`rf_adda_top`）：** `spi1_oen`/`spi2_oen`=0 时 FPGA 驱动 `pad_*_sdio`；`=1` 时高阻，由芯片在读相驱动（`rd_switch_point` 分别为 16 / 8 bit）。`adda_io.xdc` 对 SDIO 有 **PULLUP**，读相若芯片未驱动会读到 `FF`。
- **AD9117 `pad_dac_reset`：** 须为低电平 SPI 模式（`~pad_adda_rstn`）；若为高则 SDIO 作 FORMAT，读版本恒似 `FF`（仅上拉）。
- **AD9640 模式脚：** 无独立 SPI/引脚模式选择脚在 `rf_adda_top`；`CSB` 须由 FPGA 拉低（已接 `spi1_cs`）。`CSB` 常高则 SPI 高阻（数据手册）。

### 7.3 相关 RTL

| 文件 | 作用 |
|------|------|
| `rf_uart/uart_rx.v`, `uart_tx.v` | 8N1 @ 921600；`CLK_HZ` 须与 `rf_ctrl_path` 时钟一致 |
| `rf_uart/uart_spi_pack.v` | 按 chip 打包 `spi_cmd` |
| `rf_uart/uart_cmd_parser.v` | 命令 FSM + ACK（含 `0x30`/`0x31`） |
| `adc_capture.v` | `adc_clk` 采样 → BRAM；`sys_clk` 读端口 |
| `rf_adda_top.v` | 例化 `adc_capture`，接 `FPGA_ADC_DA` / `FPGA_ADC_DCOA` |
| `rf_ctrl_path/rf_ctrl_path.v` | `uart_busy` 时 UART 独占 SPI |

---

## 8. LED 指示（`rf_adda_top`）

十路 LED：**蓝** / **红** + `pad_output_d[7:0]`，由 [`led_status.v`](../led_status.v) 驱动（**UART 帧格式不变**）。

- **触发：** `uart_cmd_parser` 在 `ST_SEND_ACK` 时根据 `o_last_status` 播放 **1 s** 结果动效；新帧 `0xAA`（`o_frame_start`）可提前结束动效回到闲置。

| 场景 | 蓝 | 红 | 灯带 `pad_output_d` |
|------|:--:|:--:|:---------------------|
| 闲置 / 命令进行中 | ~1 Hz 闪 | 灭 | 乒乓球 `1<<pos`，pos 0↔7 |
| ACK 成功 | 常亮 1 s | 灭 | 1 s 内全亮闪 4 次（~125 ms 半周期） |
| ACK 失败 | 继续闪 | 亮 1 s 后灭 | LFSR 随机亮灭 1 s |

默认 **122.88 MHz**（`rf_adda_top.SYS_CLK_HZ`，由 `clk_wiz_0` 从 19.2 MHz ×32/5 倍频得到）：`HB_DIV=CLK_HZ/2`，`PING_DIV=CLK_HZ/10`（~100 ms/格），`RESULT_TICKS=CLK_HZ`，`OK_PHASE=CLK_HZ/8`。

观测口：`uart_cmd_parser` 的 `o_state`、`o_frame_start`、`o_last_*`。

---

## 9. 波形播放器（`0x50` / `0x51` / `0x52`）

向 256K × 32-bit URAM 加载任意 IQ 波形并循环播放。文件由 `tools/adda/dac/wave_upload.py`
分块上传到 FPGA。`dac_wave_player` 以 61.44 MSa/s/ch 输出 16-bit 并行 I/Q，经
`tx_iq_dsp` 2× 插值与 `tx_ddr_out` DDR 交织后送到 AD9117（I@DCLKIO 上升 / Q@下降）。
播放时 `wave_play_en` 优先于 tone_gen。

### 数据布局

- URAM 字 = `{I[15:0], Q[15:0]}`（高 16 bit=I，低 16 bit=Q）
- 样本为 **14-bit signed（±8191 = 满标）** 装在 16-bit 容器里；`dac_wave_player` 原样透传，
  `tx_iq_dsp` 做 2× 插值后 16→14 **1:1 直通 + 饱和（不再 `>>2`/÷4）**，DAC 直达满标。
  host 文件用 `tools/adda/dac/gen_sine_iq_waveform.py` 生成（s14，留 ~1 dB 过冲 backoff）。
- 文件位 byte order：`.WAVEFORM` = big-endian，`.bin` = little-endian
- FPGA 端只看 LE 字节流：`I_lo, I_hi, Q_lo, Q_hi`；PC 工具负责字节序转换

### `0x50` 波形写入（块大小固定 1024 字节 = 256 IQ 样点）

| 字段 | 含义 |
|------|------|
| `cmd`  | `0x50` |
| `chip` | `chunk_addr[9:8]`（高 2 bit） |
| `addr` | `chunk_addr[7:0]`（低 8 bit） |
| `data` | 保留，写 `0x00` |
| payload | **紧随其后** 1024 字节，按 LE I/Q 交错 |
| ACK | `BB 00 00 BB`（chunk_addr 回写 0 后续可改成真实 echo） |

URAM 写入地址 = `chunk_addr * 256`，块内 256 个 IQ 顺序写入下一个 URAM word。
**前置条件**：`o_wave_play_en == 0`，否则 FPGA 回 `BB 06 00 ck`（status `0x06`
= wave player busy）。

### `0x51` 控制（sub-address 风格，跟 `0x42`/`0x44` 一致）

| `addr` | `data` | 作用 |
|--------|--------|------|
| `0x00` | `[0]=play_en` | 立即启用/停用播放；启用瞬间 `play_addr=0` |
| `0x01` | `loop_len_minus1[7:0]` | 循环长度低字节 |
| `0x02` | `loop_len_minus1[15:8]` | 循环长度中字节 |
| `0x03` | `[1:0]=loop_len_minus1[17:16]` | 循环长度高 2 bit |

**循环长度语义**：写入值 = 实际样点数 − 1。完整 1 MB 文件 = 262144 样点
→ 写 `loop_len_minus1 = 0x3FFFF`。改 loop_len 应在 `play_en=0` 时操作；
on-the-fly 修改不会引起 URAM 越界，但会立即改变下一循环起点。

### `0x52` 极性翻转

| `data` | 含义 |
|--------|------|
| `[0]` | `swap_iq` — 输出对调 I 与 Q（修正 sideband 反相） |
| `[1]` | `neg_q` — Q 取相反数（修正镜频选择） |

### 新增状态码

| code | 含义 |
|------|------|
| `0x06` | wave player busy — 0x50 拒绝，需要先 `AA 51 00 00 00` |

### 0x50 / 0x51 / 0x52 与 0x40~0x43 互斥关系

- `wave_play_en=1` 时 DAC pad 由 wave_player 驱动，`0x40 tone_en` 仍生效但不上 pad
- `wave_play_en=0` 时 DAC pad 回到 tone_gen，便于扫频测谐波
- `0xF2` 全局复位会把 `wave_play_en` 清 0，回到 tone_gen，`loop_len_minus1` 回到 `0x3FFFF`

### 示例：上传 1 MB coherent sine 后启用循环

PC 工具 `tools/adda/dac/wave_upload.py`：

```
python tools/adda/dac/wave_upload.py COM7 docs/wave/sine_iq_9M00_-6dBFS.WAVEFORM --play
```

等价的 UART 字节序列（前两 chunk 与最后一 chunk 简写）：

```
AA 51 00 00 00                            # disable
AA 50 00 00 00 <1024B payload>            # chunk 0  → URAM[0..255]
AA 50 00 01 00 <1024B payload>            # chunk 1  → URAM[256..511]
...
AA 50 03 FF 00 <1024B payload>            # chunk 1023 → URAM[262144-256..262143]
AA 52 00 00 00                            # swap_iq=0, neg_q=0
AA 51 00 01 FF                            # loop_len_minus1[7:0]  = 0xFF
AA 51 00 02 FF                            # loop_len_minus1[15:8] = 0xFF
AA 51 00 03 03                            # loop_len_minus1[17:16]= 0x3   → 0x3FFFF
AA 51 00 00 01                            # enable
```

### 加载耗时估算

UART 921600 bps ≈ 92.16 KB/s。1 MB 数据 + 1024 帧头（每帧 5+4=9B 额外）
≈ 1024·1033B / 92160 B/s ≈ **12 s**。一次性 cost，coherent 单频文件加载完就
能持续循环不丢相位。
