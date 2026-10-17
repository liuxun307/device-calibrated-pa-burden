# 复现头条数字 / Reproducing the headline result

> **用途**：GATHER 第 13 项（报告计算过程的可及性）与审稿人常见追问「3,775,099 这个数怎么来的」的
> 单一入口。本文只描述**从头复现头条数字的最小路径**，不重复完整流水线文档（见 `README.md`
> 与 `docs/DATA_DICTIONARY.md`）。
>
> **对应正文位置**：Results R5、Discussion D1、Abstract Findings、Fig 5、Table S16。
> **最后核对**：2026-10-17（与 `output/Table4_burden_manuscript.csv` 第 10 行一致）。

---

## 1. 头条数字是什么

| 量 | 本文重算 | GBD 2023 现报 | 倍数 |
|---|---|---|---|
| 全球 PAF（2022，25 岁以上，低体力活动） | **0.1740** | **0.0304** | — |
| 归因死亡 | **3,775,099** | **660,032** | **5.7×** |
| 归因 DALYs | **95,737,701** | **16,096,925** | **5.9×** |

**权威来源**：`output/Table4_burden_manuscript.csv` 第 10 行（`Year=2022, Location=Global`）。
表中每一行都可直接被 `grep` 到，**正文所有负担数字均取自此文件，零硬编码**。

---

## 2. 最小复现路径（三个模块，按依赖顺序）

头条数字 = **模块 3**（负担重算）的输出，但它依赖模块 1 与模块 2 已经算好的 RR 曲线。

```
模块 1  设备校准         03 → 04        产出：RR 曲线（每 IQR / 四分位 / 连续）
模块 2  证据合成         05a → 05b      产出：池化 RR（rr_table.csv）
模块 3  负担重算         05             产出：Table4_burden_manuscript.csv  ← 头条数字
```

### 2.1 环境

```bash
# R 4.5.2；必需包版本见 output/REPRODUCIBILITY_REPORT.txt 的「A 环境」层
cd code
Rscript 00_setup.R      # 检查依赖、固定随机种子（20261011）、建立日志目录
```

⚠️ **必须 `cd code` 后运行**：多个脚本用相对路径 `source("08_fig_style.R")` 等，
在项目根目录直接调用会报 `cannot open file`。

### 2.2 逐模块命令

```bash
cd code

# 模块 1：设备测量暴露与死亡率关系（NHANES 2011-2014）
Rscript 03_exposure_merge_survival.R     # 合并暴露与死亡随访 → analytic.rds
Rscript 04_cox_dose_response.R           # 调查加权 Cox + 样条 → RR 曲线

# 模块 2：与已发表队列的剂量反应证据合成
Rscript 05a_module2_bop.R                # 池化 → data/bop/rr_table.csv
Rscript 05b_verify_bop_table.R           # 核对池化表（含留一法清单）

# 模块 3：把 RR 应用到 GBD 暴露分布与死亡分母 → 头条数字
Rscript 05_burden_calibration_paf.R      # → Table4_burden_manuscript.csv / Fig 5
```

### 2.3 一步到位（含校验）

```bash
cd code
Rscript 00_run_all.R        # 完整链 00 → 98
Rscript 98_verify_reproducibility.R
```

`98` 会重算环境、原始数据、中间数据、交付产出的全部指纹，并与 `output/manifest.csv` 逐字节比对，
结论写入 `output/REPRODUCIBILITY_REPORT.txt`。**判据：FAIL = 0**。

---

## 3. 头条数字的计算式（模块 3 内部）

对每个国家 / 年份：

```
PAF = Σ_a  P_a · (RR_a − 1) / [1 + Σ_a P_a · (RR_a − 1)]
归因死亡 = PAF × 该国家该年该年龄组全因死亡数
```

- `P_a`：GBD 2023 给出的该年龄组体力活动不足人群比例（暴露分布）
- `RR_a`：模块 1 + 模块 2 得到的**设备校准**剂量反应曲线在该年龄组活动水平上的 RR
- 分母（全因死亡）：GBD 2023 现报死亡数，与 PAF 分母同批次

**与 GBD 现报差异的唯一来源**：`RR_a` 的函数形式与取值。GBD 用**自报**问卷暴露与自报来源的 RR；
本文用**设备测量**暴露校准后的 RR。分解：
`0.1740 → 0.0196`（GBD 自报口径复现）`→ 0.0302`（换用设备暴露分布）`→ 0.1740`（换用设备校准 RR，
残余 ×1.007 为四舍五入与年龄结构残差）。详见正文 Results R5 与 D1。

---

## 4. 输入数据从哪来

| 输入 | 来源 | 版本 / 路径 |
|---|---|---|
| NHANES 2011–2014 加速度计、死亡随访 | CDC/NCHS 公开 | `data/raw/`，下载脚本 `01_fetch_data.R` |
| 已发表队列 RR | 5 个队列（Ekelund 2019、Moore 2012、PURE 2017、Tarp 2024、UKB） | `data/bop/rr_table.csv` |
| GBD 2023 暴露 / 死亡 / DALYs / PAF | IHME GBD Results Tool | `data/gbd/IHME-GBD_2023_DATA-*/`，版本 `Y2025M10D10` |
| GBD 2023 SDI 五分位 | IHME | `data/gbd/SDI/`，版本 `Y2025M10D12` |

**查询参数留痕**：每次 GBD Results Tool 查询的筛选条件（性别、年龄 25+、1990–2022、204 国、
指标 Deaths/DALYs/PAF 分母）与返回文件名记录在 `logs/<RUN_ID>/` 与 `output/manifest.csv`。
GBD 原始文件依 IHME 使用条款**不再分发**，需按上述参数自行下载。

---

## 5. 常见复现失败点

| 现象 | 原因 | 处置 |
|---|---|---|
| `cannot open file '08_fig_style.R'` | 在项目根目录运行 | `cd code` 后运行 |
| `Rscript: command not found` | R 未入 PATH | 用绝对路径 `"D:/Program Files/R/R-4.5.2/bin/Rscript.exe"` |
| 表行数 / 列数偏少 | `fread` 未显式给 `sep`，表头含空格时探测退化 | 已在 `06_manifest.R` 与 `96b` 中显式指定，勿改回 |
| `98` 报 manifest 字节不一致 | 手动改过 `output/` 下文件 | 重跑 `06_manifest.R` 再跑 `98` |
| 中文路径乱码 | `LC_CTYPE` 未设为 UTF-8 | `00_setup.R` 已处理；勿跳过 setup |

---

## 6. 留痕

| 项 | 位置 |
|---|---|
| 本文 | `docs/REPRODUCE_HEADLINE.md`（2026-10-17） |
| 头条数字产物 | `output/Table4_burden_manuscript.csv` 第 10 行 |
| 计算代码 | `code/05_burden_calibration_paf.R` |
| 校验报告 | `output/REPRODUCIBILITY_REPORT.txt` |
| 产物清单 | `output/manifest.csv`（逐文件 SHA-256） |
