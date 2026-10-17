# 复现协议（REPRODUCIBILITY）

> 本文档回答一个问题：**别人拿到这个项目，能不能得到和你一样的结果？**
> 结论先行：**能**，且每一步都有可核对的证据。

---

## 0. 三条硬标准与本项目的落实方式

| 标准 | 落实方式 | 证据文件 |
|---|---|---|
| **原始数据可复现** | 数据获取清单外置为 CSV；`01_fetch_data.R` 自动下载并**逐文件固化 SHA-256 指纹**；建立原始数据台账 | `data/sources/nhanes_files.csv`<br>`data/sources/checksums.csv`<br>`data/RAW_INVENTORY.csv` |
| **分析代码可复现** | 全流程 9 个脚本，单一入口；环境锁定（R 版本 + 全部包版本 + RNGkind）落盘；随机种子固定 | `code/*.R`<br>`logs/<RUN_ID>/session-info_*.txt`<br>`logs/pkg-versions_latest.csv` |
| **过程可复现** | 每步独立进程执行、独立日志；运行后生成产物清单（含指纹）与复现核验报告 | `logs/<RUN_ID>/step_*.log`<br>`output/manifest.csv`<br>`output/REPRODUCIBILITY_REPORT.txt` |

---

## 1. 从零复现：七步

前置：本机已装 R（见第 3 节）。以下命令在项目根目录执行。

```bash
# 步骤 0  环境自检（不写文件，只报告）
Rscript code/00_setup.R

# 步骤 1  获取原始数据 + 固化指纹（联网；首次约 5-10 分钟，约 130 MB）
Rscript code/01_fetch_data.R

# 步骤 2-6  全流程（自动按序执行 02 -> 06 -> 98）
Rscript code/00_run_all.R

# 或：分步执行，便于定位问题
Rscript code/00_run_all.R --from 02
```

跑完后**先看这一个文件**：

```
output/REPRODUCIBILITY_REPORT.txt     ← 总体结论 PASS / WARN / FAIL
```

若要**验证他人交付的复现包**（不做任何计算，只核验）：

```bash
Rscript code/98_verify_reproducibility.R    # 退出码 0 = PASS/WARN，1 = FAIL
```

---

## 2. 完整项目结构

```
范式A_低体力活动_加速度计/
├── 00_完整研究方案.md            研究方案（定位/假设/SAP/图表目录）
├── REPRODUCIBILITY.md            ← 本文件
│
├── code/
│   ├── 00_setup.R                环境锁定 · 路径常量 · 随机种子 · 会话快照（被其余脚本自动加载，幂等）
│   ├── 00_run_all.R              编排器（独立进程逐步执行，日志隔离，失败即停）
│   ├── 01_fetch_data.R           原始数据获取 + 指纹固化 + 台账 + 缓存
│   ├── 02_accel_processing.R     加速度计质控与暴露构建
│   ├── 03_exposure_merge_survival.R  自报 MET + 协变量 + 死亡结局合并
│   ├── 04_cox_dose_response.R    加权 Cox + 限制性立方样条剂量-反应
│   ├── 05_burden_calibration_paf.R   测量偏倚校准 + 证据合成 + PAF 重算
│   ├── 06_manifest.R             产物清单（逐文件指纹）
│   ├── 98_verify_reproducibility.R   复现核验（五层，给总体结论）
│   ├── 99_smoketest.R            冒烟测试（合成数据，不联网，测管道本身）
│   └── README.md                 运行手册与已知问题
│
├── data/
│   ├── README.md                 原始数据层说明（含 GBD 获取步骤）
│   ├── raw/                      原始 .xpt/.dat（01 自动获取；只读）
│   ├── derived/                  中间 .rds 缓存
│   ├── gbd/                      GBD 2023 CSV（GHDx 手工获取）
│   └── sources/                  ★ 清单·指纹·官方读入程序（体积小，必须留存）
│
├── output/                       ★ 交付物：图 (PDF/PNG) · 表 (CSV) · manifest · 复现报告
└── logs/
    ├── <RUN_ID>/                 每次运行：run.log · step_*.log · session-info · manifest 归档
    └── pkg-versions_latest.csv   依赖包版本快照
```

---

## 3. 环境要求与锁定

### 3.1 基线环境（本机已验证）

| 项 | 值 |
|---|---|
| R | **4.5.2**（`D:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe`） |
| 必需包 | `data.table` · `haven` · `tidyverse` · `survival` · `survey` · `splines` |
| 推荐包 | `digest`（启用 SHA-256；缺失则退回 MD5）· `patchwork` · `rms` |
| 按需包 | `brms` / `cmdstanr`（仅证据合成的贝叶斯部分）· `nhanesA`（可选数据通道） |

> ⚠️ **不要用 R-4.6.0**：本机上它的用户库只装了 `data.table`，其余全部缺失。

### 3.2 环境指纹

每次运行，`00_setup.R` 会把以下信息落盘到 `logs/<RUN_ID>/`：

- R 版本、平台、时区
- **全部已安装包的名称与版本**
- `RNGkind()`（随机数发生器类型，决定"同种子是否同结果"）
- 固定的随机种子 `PA_SEED`
- 完整 `sessionInfo()`
- locale 设置

依赖包的当前快照另存为 `logs/pkg-versions_latest.csv`，可用于逐包 `diff`。
若要严格锁定，可在有网环境执行 `install.packages(c("renv")); renv::init()` 生成标准 `renv.lock`。

### 3.3 随机性处理

| 环节 | 是否含随机性 | 处理 |
|---|---|---|
| 01–04 | 否（确定性数据处理与回归） | 结果应与数据逐字节可复现 |
| 05 的 Bootstrap / 多重插补 | 是 | 统一用 `pa_seed_with(seed, expr)` 包裹，固定种子 |
| 05 的贝叶斯 MCMC（brms/Stan） | 是 | 固定 `seed`，并**用后验摘要（均值/区间）在容差内比对**，不逐字节比对 |
| 06 / 98 | 否 | — |

---

## 4. 数据指纹机制

### 4.1 为什么必须有指纹

"原始数据可复现"不等于"能下载到文件"，而等于**"能证明下载到的是同一份文件"**。
NHANES 原始文件可能被 CDC 悄悄修订（本方案下载时观察到的 `Last-Modified` 为 2020-10-29），
没有指纹就无法发现这种漂移。

### 4.2 工作方式

1. **首次运行** `01`：下载后用 SHA-256 计算每个文件的指纹，写入 `data/sources/checksums.csv`，
   同时记录字节数、源站 `Last-Modified`、首次固化日期。
2. **后续运行** `01`：重新计算指纹并与固化值比对，不一致即告警（不覆盖历史记录）。
3. **任何人**任何时候可运行 `98` 做独立核验。

`checksums.csv` 与 `nhanes_files.csv` **必须随代码一起提交/存档**——它们是"原始数据"的可移植代表，
即使原始 `.xpt` 因体积未随附，复现者可用它们验证自己获取的数据是否与作者一致。

---

## 5. 复现判定标准

`98_verify_reproducibility.R` 分五层核验，输出总体结论：

| 层 | 核验内容 | 阻断性 |
|---|---|---|
| A 环境 | R 版本、locale（中文路径可用性）、必需包、SHA-256 可用性、种子 | locale 或必需包缺失 → **FAIL** |
| B 原始数据 | 是否齐备，且 SHA-256 与 `checksums.csv` 一致 | 缺失或指纹不符 → **FAIL** |
| C 中间数据 | `accel_daily.rds` / `analytic.rds` / `MORT_2011_2014.rds` 是否存在及行数 | 缺失 → **FAIL** |
| D 交付产出 | 关键图表是否存在；字节数是否与 `manifest.csv` 一致 | 缺失 → **FAIL**；字节不符 → WARN |
| E 跨运行 | 本次产物指纹 vs 上次运行归档的 manifest | 不一致 → WARN |

**实际判定口径：**

- **B 层全 PASS** → 你的原始数据与作者**逐字节一致**。
- **E 层 PASS** → 在相同数据与代码下，产物**指纹级可复现**。
- 结论 `FAIL` 时脚本退出码为 1，可直接接入 CI。

---

## 6. 已知失败模式（照着排查）

| 现象 | 原因 | 解决 |
|---|---|---|
| `未找到 00_setup.R` | 工作目录不是 `code/` | `setwd(".../code")` 或设 `PARADIGM_A_ROOT` |
| `list.files()` 返回空 / `source()` 路径被截断 | Windows 下 `LC_CTYPE="C"` | 见 `code/README.md` 坑 1；最彻底是把项目目录改为纯 ASCII 名 |
| 图形报 `mbcsToSbcs conversion failure` | 图形设备无法渲染中文 | 图内标签一律 ASCII，中文图注在 Illustrator/Word 中加 |
| `01` 部分文件 404 | 某组件在该周期命名不同 | 打开 `data/sources/nhanes_files.csv` 手工修正 URL 后重跑 |
| `05` 报「data/gbd 为空」 | GBD 需注册手工获取 | 见 `data/README.md` 第 3 节 |
| 98 的 B 层 FAIL：指纹不一致 | CDC 修订了文件，或下载不完整 | 检查字节数；确认后决定是否删除该条记录重新固化，并**在文档中记录** |
| 两次运行 E 层不一致（仅贝叶斯部分） | MCMC 跨平台数值差异 | 属正常，改用后验摘要容差比对 |

---

## 7. 复现的边界（诚实声明）

以下内容**本协议不能保证**，投稿与共享时须如实说明：

1. **GBD 数据非脚本化获取**。GHDx 要求注册并接受使用条款，因此这是流程中唯一的人工环节。
   缓解措施：获取步骤逐字段写入 `data/README.md`，并对拿到手的文件做 SHA-256 固化与列名校验。
2. **随访窗口固定**。公开版 LMF 截止 2019-12-31，无法延长；2013–2014 周期实际随访仅约 5–6 年。
3. **原始文件可能被源站修订**。协议能**发现**漂移（指纹告警），但不能阻止。
4. **贝叶斯采样跨平台差异**。同一 `seed` 在不同 BLAS/编译器下可能有极小数值差异，
   故 E 层对这类产物只做摘要级比对。
5. **受限数据不在范围内**。本方案全部使用公开数据；温度/空气污染等需要 NCHS RDC 受限数据的设计不适用。

---

## 8. 版本控制建议

`.gitignore` 已按下列策略配置：

| 路径 | 是否提交 | 理由 |
|---|---|---|
| `code/` | ✅ | 分析代码 |
| `data/sources/` | ✅ | 清单与指纹，体积小，是复现的关键 |
| `data/README.md` | ✅ | 数据说明 |
| `data/raw/`、`data/derived/` | ❌ | 体积大，可由脚本重建 |
| `data/gbd/` | ❌ | 受 IHME 条款约束，不随附 |
| `output/` | ✅ 仅 `manifest.csv` / `REPRODUCIBILITY_REPORT.txt` | 交付证据 |
| `logs/` | ❌ | 本机运行痕迹 |
| `_smoketest/` | ❌ | 临时沙箱 |

---

## 9. 一句话总结

> **原始数据**有清单和 SHA-256 指纹；**分析代码**有单入口、环境锁定和固定种子；
> **过程**有逐步日志、产物清单和自动核验报告。
> 三者合起来，使这套分析从"作者本机能跑通"升级为"任何人可核验"。
