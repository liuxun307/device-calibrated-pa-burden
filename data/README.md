# 原始数据层说明（data/）

本目录是**原始数据层**，是整套复现链条的起点。原则：

> **原始数据只进不改。** 任何清洗、派生、合并都写到 `data/derived/`，
> 任何对外交付的图与表都写到 `output/`。`data/raw/` 里的文件一旦落盘即视为冻结。

---

## 1. 目录职责

| 目录 | 内容 | 是否版本控制 | 是否可重建 |
|---|---|---|---|
| `data/raw/` | NHANES 原始 `.xpt` + NCHS 官方 LMF `.dat` + 官方读入程序 | 否（体积大） | ✅ 由 `01_fetch_data.R` 自动重建 |
| `data/derived/` | 清洗后的中间 `.rds`（accel_daily / analytic / MORT） | 否 | ✅ 由 `02`/`03` 重建 |
| `data/gbd/` | GBD 2023 结果 CSV（GHDx 手工获取） | 否 | ⚠️ 需人工获取，见第 3 节 |
| `data/sources/` | 数据清单、指纹台账、官方读入程序 | **是**（体积小，必须留存） | — |
| `output/` | 图（PDF/PNG）与表（CSV）、manifest、复现报告 | 部分 | ✅ 由 `04`–`06` 重建 |

---

## 2. NHANES 原始数据（自动获取）

### 2.1 清单文件是唯一事实来源

`data/sources/nhanes_files.csv` 由 `01_fetch_data.R` 首次运行时生成，之后**以盘上文件为准**。
它逐行记录每个待获取文件的：周期、年份、组件、文件名、URL、类别、是否必需、最小字节数、用途。

要修改获取范围（例如加入新周期、增删协变量），**直接编辑这个 CSV**，而不是改 R 代码。
若要恢复脚本内置的默认清单，设置环境变量 `PARADIGM_A_REFRESH_MANIFEST=1` 后重跑 `01`。

### 2.2 涉及的两个周期

| 代号 | 周期 | 加速度计设备 | 说明 |
|---|---|---|---|
| G | 2011–2012 | ActiGraph GT3X+，**腕式** | MIMS 单位 |
| H | 2013–2014 | ActiGraph GT3X+，**腕式** | MIMS 单位 |

两周期合并后用 4 年权重 `WTMEC4YR = WTMEC2YR / 2`。

### 2.3 大文件（分钟级 PAXMIN）

`PAXMIN_G/H.xpt` 约 8,800 万行、单文件数百 MB。**默认不下载**。
主分析只需日级 `PAXDAY` 即可得到 `MIMS/day` 暴露。
仅当需要 MVPA 时长或 Peak-30 时，才设置 `PARADIGM_A_DOWNLOAD_HUGE=1` 重跑 `01`，
或改用 PhysioNet 已预处理的 1440 宽表（`doi:10.13026/d7sw-f662`）。

---

## 3. GBD 2023 数据（手工获取）

> ⚠️ **GBD 结果无法脚本化下载**：GHDx 要求注册并接受 IHME 使用条款。
> 因此本方案的做法是：把"获取步骤"当作数据来源的一部分**显式、逐字段记录**，
> 并对拿到手的文件本体做严格校验。复现者照下面步骤操作，即可得到同一份数据。

### 3.1 获取路径

- 入口：<https://ghdx.healthdata.org/gbd-2023>
- 或结果工具：<https://vizhub.healthdata.org/gbd-results/>
- 需注册 IHME 账号（免费）并接受使用条款。

### 3.2 需要导出的两组结果

**组 A — 风险因素（Low physical activity）**

| 字段 | 取值 |
|---|---|
| Risk | `Low physical activity` |
| Measure | `Deaths`、`DALYs (Disability-Adjusted Life Years)` **且** `Attributable` |
| Metric | `Number`、`Rate`、`Percent` |
| Location | `Global` + `21 GBD regions` + `204 countries and territories` |
| Year | `1990`–`2023` |
| Age | `All ages` + `Age-standardized` |
| Sex | `Both` |

**组 B — 归因结局（cause 层，用于 PAF 分母）**

Cause 取以下 **8 类**（GBD 2021 起扩展，GBD 2023 沿用；**以 Results 工具下拉框实际列出者为准**）：

1. `Ischemic heart disease`
2. `Stroke`（⚠️ GBD 2021 起为 Stroke 整体，**不是** `Ischemic stroke`）
3. `Diabetes mellitus`（⚠️ GBD cause 正式名不分型，**不是** `Diabetes mellitus type 2`）
4. `Chronic kidney disease`（GBD 2021 新增）
5. `Lower extremity peripheral arterial disease`（GBD 2021 新增）
6. `Colon and rectum cancer`
7. `Breast cancer`
8. `Tuberculosis`（GBD 2021 新增）

> ⛔ **在 Results 工具里绝对不要选 `All causes`**，也不要选父级节点（如 `Cardiovascular diseases`）。
> PAF = 归因负担 ÷ **同一 outcome 集合**的总负担；选 All causes 或父级会把分母污染、
> 把 PAF 稀释到 1/10 量级，且无法做 cause 分解图。必须勾到 **Level 3 的具体疾病**。

Measure = `Deaths`、`DALYs`；Metric = `Number`。

### 3.3 落盘约定

导出后重命名为下面两个文件名，放入 `data/gbd/`：

```
data/gbd/risk_lpa_2023.csv     ← 组 A
data/gbd/cause_lpa_2023.csv    ← 组 B
```

`01_fetch_data.R` 会自动计算其 SHA-256 并写入 `data/sources/gbd_checksums.csv`。
`05_burden_calibration_paf.R` 内置列名容错匹配，能接受 GBD Results Tool 的常见导出列名。

### 3.4 GBD 数据的关键口径（勿凭记忆写 Methods）

| 项 | 值 | 备注 |
|---|---|---|
| TMREL（理论最小风险暴露水平） | **3000–4500 MET-min/周** | 区间形式，取自 GBD 风险因素附录 |
| 暴露分层 | inactive `<600`；low `600–3999`；moderate `4000–7999`；high `≥8000` | MET-min/周 |
| 归因结局 | IHD、缺血性卒中、T2DM、结肠癌、乳腺癌 | ⚠️ 须核对 2023 版附录 |

---

## 4. 指纹与校验（复现的锚点）

| 文件 | 内容 |
|---|---|
| `sources/checksums.csv` | 每个 NHANES 原始文件的 SHA-256 + 字节数 + 源站 Last-Modified + 首次固化日期 |
| `sources/gbd_checksums.csv` | GBD CSV 的 SHA-256 |
| `sources/nhanes_files.csv` | 获取清单（唯一事实来源） |
| `sources/R_ReadInProgramAllSurveys.R` | NCHS 官方 LMF 读入程序（固定宽度布局的权威依据） |
| `../data/RAW_INVENTORY.csv` | 原始数据台账：文件、来源 URL、字节数、指纹、获取日期 |
| `../output/REPRODUCIBILITY_REPORT.txt` | 逐项核验结果与总体结论 |

**校验方式**：随时运行

```
Rscript code/98_verify_reproducibility.R
```

B 层全部 PASS 表示你手上的原始数据与作者**逐字节一致**。

---

## 5. 使用条款与引用

| 数据 | 条款 | 必须引用 |
|---|---|---|
| NHANES | 美国政府公开数据，无使用限制 | NCHS. *National Health and Nutrition Examination Survey, 2011–2014*. CDC. |
| NHANES LMF | 公开版链接死亡文件，随访至 2019-12-31 | NCHS. *Public-Use Linked Mortality Files, 2019*. |
| GBD 2023 | IHME 使用条款（需注册接受） | GBD 2023 Risk Factors Collaborators. *Lancet*. 2025. |

## 6. 投稿用数据可用性声明（模板）

> All NHANES data are publicly available from the U.S. National Center for Health Statistics
> (<https://wwwn.cdc.gov/nchs/nhanes/>). The 2019 Public-Use Linked Mortality Files were obtained
> from <https://ftp.cdc.gov/pub/Health_Statistics/NCHS/datalinkage/linked_mortality/>.
> GBD 2023 estimates were retrieved from the Institute for Health Metrics and Evaluation
> (<https://ghdx.healthdata.org/gbd-2023>). All analysis code, the file manifest with SHA-256
> checksums, and derived result tables are available at [repository/DOI].
> No individual-level identifiable data were used.
