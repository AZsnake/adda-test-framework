# 开源展示与隐私保护

本仓库采用 **「公开框架 + 私有板级包」** 模型：对外展示 UART 协议、RTL 架构、仿真与 PC 工具；**不**公开具体 PIN、原理图、时钟 init 与实测指标。

## 可以公开的内容（当前 HEAD）

| 类别 | 路径 | 说明 |
|------|------|------|
| RTL | `rf_adda_top.v`、`rf_uart/`、`rf_ctrl_path/`（自研部分）、RX/TX 链 | 展示架构与工程能力 |
| 协议 | `docs/uart_command_protocol.md` | 接口设计（可泛化 ACK 示例） |
| 工具 | `tools/adda/` | GUI / CLI / 分析脚本 |
| 仿真 | `sim/tb_*.v` | 验证方法论 |
| 约束模板 | `constraints/adda_io.template.xdc`、`adda_clocks.xdc`、`adda_dac_ddr.xdc` | 无 PACKAGE_PIN |
| 参考波形 | `docs/wave/` | 与具体板卡无关的测试向量 |

## 必须保留在本地的内容（`.gitignore`）

见 [`BOARD_LOCAL_FILES.md`](BOARD_LOCAL_FILES.md)：

- `constraints/adda_io.xdc` — 真实 PACKAGE_PIN
- `init_tables/*` — SI5340/AD9640/AD9117 boot 序列
- `docs/schematics/` — 原理图 PDF
- `docs/metrics/` — 内部测试数据
- 系统设计框图 SVG

克隆公开仓库后 **无法直接综合上板**，需自行准备上述文件——这是刻意的隐私边界。

## 公开前必做：清理 Git 历史

本仓库曾短暂设为 **Public**（含 v1.0.0），历史中仍可能包含：

- 完整 `adda_io.xdc`
- 原理图 PDF、`init_tables/*.mem`
- 测试 metrics

**仅改 Private → Public 不够**；新访客仍可能通过旧 commit / fork 缓存看到历史。

### 推荐方案 A：孤儿分支（最简单，适合作品集）

保留当前干净树，丢弃旧历史：

```powershell
git checkout --orphan public-main
git add -A
git commit -m "feat: ADDA test framework (open-source release)"
git branch -M main
git push -f origin main
git tag -f v1.0.0-public
git push -f origin v1.0.0-public
```

然后 `gh repo edit --visibility public`。旧 tag `v0.0.1` / `v1.0.0` 在 GitHub 上应删除或替换 Release 说明。

### 方案 B：`git filter-repo`（保留线性历史）

从所有 commit 中删除敏感路径：

```powershell
pip install git-filter-repo
git filter-repo --path constraints/adda_io.xdc --path docs/schematics/ --path docs/metrics/ `
  --path init_tables/ --path docs/VU13P_ADDA_整体设计框图.svg --invert-paths
git push -f origin main
```

## 可选增强

1. **拆成两个仓库**  
   - `adda-test-framework`（Public）— 本仓库当前结构  
   - `adda-board-config`（Private）— 仅 PIN + init + 原理图，内部 CI 用

2. **芯片手册** — 从 git 移除 `docs/specs/*.pdf`，README 改为厂商下载链接（减少再分发风险）。

3. **协议文档** — 将「本板实测 ACK」改为占位符 `xx`，避免泄露 SI5340 读回指纹。

4. **INNOFIDEI 模块** — 公开前做法务确认，或替换 `rf_ctrl_path` 中 legacy SPI 栈（见 [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)）。

## 对外 README 建议表述

> Open-source ADDA bring-up **framework** for VU13P-class designs with SI5340 / AD9640 / AD9117.  
> Board-specific pin constraints and boot images are **not included**; bring your own schematic.

这样既诚实，又突出框架价值而非硬件细节。
