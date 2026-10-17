# `data/bop/` —— Module 2 的外部证据输入层

> 这里是 **Module 2（BoP 式 meta-regression）唯一的输入**。
> 脚本 `code/05a_module2_bop.R` 读 `rr_table.csv`，产出
> `output/bop_rr_draws.rds`（RR 曲线集）供 `05` 的 Module 3 使用；
> 脚本 `code/05b_verify_bop_table.R` 对本表做**可复算审计**（百分位复算 + 原文值核对 + 结构/方向检查）。
>
> **原则：只放"从原始文献抽出来的数"，不放任何派生量。**
> `logRR` 与 `SE` 由脚本从 `hr/hr_lo/hr_hi` 计算，不写进 CSV —— 这样数字可审计、可复算。
> **唯一例外**是 `exposure_center / exposure_ref_center`：它们是**百分位**（派生量），
> 因此每一行都必须用 `pct_rule` 声明推导口径，并同时保留 `exposure_orig_unit /
> exposure_orig_lo / exposure_orig_hi` 三个**原始刻度**字段，使换算可被复核。

---

## 1. 文件清单

| 文件 | 说明 |
|---|---|
| `rr_table.csv` | **主输入**。22 行 / 6 来源 / 6 研究（设备 4 + 自报 2），见 §3。**05a/05b 只读它，从未被任何脚本写入** |
| `extraction_log.csv` | 人工抽取台账：谁、何时、从哪张表抽的、**百分位怎么推的**、复核人；含**被拒来源**记录与**本项目自算**行（见 §6） |
| `rr_table_nhanes_sensitivity.csv` | **非主输入**：`rr_table.csv` + 16 行 NHANES 自算行的快照，由 `05c` 产出，仅供审计（见 §6） |
| `文献传递申请单_腕式总量来源.md` | 路径 1（Ko 2025 / Inan-Eroglu 2024 全文）的机构文献传递申请单 + 逐字段确认清单 |
| `README.md` | 本文件：列定义 + 抽取规范 + 待补清单 |

---

## 2. `rr_table.csv` 列定义

| 列 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `row_id` | 字符 | ✅ | 唯一行号，命名规则 `来源_指标_对比`（如 `EK19_total_Q4`） |
| `source` | 字符 | ✅ | 一级来源短名（`Ekelund2019`） |
| `study` | 字符 | ✅ | **随机效应的聚类单位**。协调化 meta 分析整体算 1 个"研究" |
| `design` | 字符 | ✅ | `harmonised_meta` / `pooled_cohort` / `cohort` / `rct` |
| `method` | 字符 | ✅ | `device`（设备测量）或 `self`（自报） |
| `device_type` | 字符 | ✅ | `ActiGraph (uniaxial)` / `Axivity AX3` / `mixed` / `NA` |
| `wear_site` | 字符 | ✅ | `hip` / `wrist` / `mixed` / `NA`（自报填 `NA`） |
| `metric_definition` | 字符 | ✅ | `total_PA` / `LPA` / `MVPA` / `steps` |
| `exposure_scale` | 字符 | ✅ | 本表统一为**百分位刻度**，取值标出该百分位如何得到：`quartile_pct` / `tertile_pct` / `pct_from_counts` / `pct_equal_share_assumed` |
| `exposure_center` | 数值 | ✅ | **该类别在其自身分布中的中点百分位**（如 `37.5` = Q2 中点） |
| `exposure_ref_center` | 数值 | ✅ | **该研究参照类别**的中点百分位（该行 RR 相对它而言，按构造 RR=1） |
| `exposure_orig_unit` | 字符 | ✅ | 原文刻度单位：`MET_h_per_wk` / `LPA_h_per_day` / `quartile_of_total_counts` … |
| `exposure_orig_lo` / `_hi` | 数值 | 建议 | 原文类别边界（开放上界留空）。**换算可审计性的关键** |
| `category_n` | 数值 | 建议 | 该类别人数（原文报告时填，可反算百分位） |
| `pct_rule` | 字符 | ✅ | 百分位推导口径，四选一（见 §3.1） |
| `outcome` | 字符 | ✅ | `all_cause` / `ihd` / `stroke` / `diabetes` / `ckd` / `crc` / `breast_ca` / `tb` |
| `n_total` | 数值 | 建议 | 分析样本量 |
| `n_cases` | 数值 | 建议 | 事件数（**原文未报告时留空**，不猜） |
| `hr` / `hr_lo` / `hr_hi` | 数值 | ✅ | 报告的风险比与 95% CI |
| `sex` / `mean_age` / `followup_y` / `region` | — | 建议 | 描述性字段 |
| `population` | 字符 | ✅ | `general`（社区/一般人群队列，含老年人群队列）或 `clinical_subgroup`（疾病人群）。**主分析只纳入 `general`**，`clinical_subgroup` 仅进敏感性 —— 见 §3.3 |
| `pmid` / `doi` | 字符 | ✅ | 溯源用；投稿时便于生成补充表 |
| `notes` | 字符 | 建议 | 抽取备注（哪张表、哪个模型、校正了什么、有什么坑） |

**脚本会自动施加的硬门禁**（不满足直接 `stop()`，不静默）：

1. 必填列齐备；
2. 每行满足 `0 < hr_lo ≤ hr ≤ hr_hi`；
3. `exposure_center` 非缺失，且**严格大于** `exposure_ref_center`（逐行锚定）；
4. `population` 取值必须 ∈ {`general`, `clinical_subgroup`}；
5. 每行必须能由 `method × wear_site` **唯一归入一个 arm**（见 §3.3）；
6. 模型系数不得出现 `NA`（否则是设计矩阵秩亏，脚本会指名报错）。

---

## 3. 当前池内容（22 行）

| `source` | `study` | arm | 指标 | 行数 | 暴露刻度 | 说明 |
|---|---|---|---|---|---|---|
| Ekelund2019 | `Ekelund2019_harmonised` | device_**hip** | total_PA / LPA / MVPA | 9 | 四分位 | 8 队列个体数据协调化，髋式 ActiGraph；BMJ 2019 |
| Tarp2024 | `Tarp2024_harmonised` | device_**mixed** | total_PA | 2 | 三分位 | 9 队列协调化，加速度计活动量；AJPM 2024 ⚠️ 与上一行队列重叠 |
| **Sun2025** | `UKB_wrist_general` | device_**wrist** | LPA | 3 | 四分位 | **A3 新增**：UK Biobank **一般人群**腕式（n=69,492 / 死亡 2,024）；*J Sport Health Sci* 2025 |
| **Cao2024** | `UKB_wrist_CVD` | device_**wrist** | LPA | 1 | 四分位 | **A3 新增**：UK Biobank **既往 CVD** 亚组（n=8,024 / 死亡 691）→ `clinical_subgroup`，**不入主分析** |
| Moore2012 | `Moore2012_nci_pool` | **self** | MVPA | 5 | **人数复算** | NCI 队列联盟 6 队列自报休闲 MVPA；PLoS Med 2012 |
| PURE2017 | `PURE2017_17countries` | **self** | total_PA | 2 | **等份额假定** | IPAQ 自报总体力活动，17 国含中国；Lancet 2017 |

### 3.1 `pct_rule` 四种口径

| 取值 | 含义 | 精度 | 涉及来源 |
|---|---|---|---|
| `by_construction_equal_share` | 分位/三分位**按构造**等份额 → 中点百分位可直接写出（Q2 = 37.5；T2 = 50.0） | **精确** | Ekelund2019、Tarp2024、Sun2025、Cao2024 |
| `reported_category_counts` | 原文报告了**各类别人数** → 累计分布中点反算百分位 | **精确、可复算** | Moore2012 |
| `equal_share_assumption` | 原文未报告类别人数，**假定**各类别各占 1/n | **近似，须敏感性** | PURE2017 |
| `reported_exposure_boundaries` | 原文给出绝对暴露且给分布参数 → 由分布函数换算 | 精确（需分布参数） | *（暂无）* |

> ⚠️ **PURE2017 的等份额假定是当前池里唯一的近似点**，已在 `05a` 的 `QC_bop_status.csv`
> 里升为 `WARN`，并进入 `Table5_bop_sensitivity_curvature.csv` 的敏感性框架。
> 若要消除，需 IPAQ 总分在 17 国人群中的分布（PURE 补充材料或作者索取）。

### 3.2 已知的**非独立性**（必须写进 Methods）

1. **Tarp2024 与 Ekelund2019**：同属 Ekelund 团队，队列（9 vs 8 个）高度重叠 →
   设备侧两个研究**不独立**，随机效应模型会低估设备侧不确定性。
2. **Sun2025 与 Cao2024**：**同属 UK Biobank**（同一批腕式测量、同一死亡登记）。
   本池把二者放在**不同 `study`** 下（供随机效应区分），但它们**不是独立证据**：
   Cao2024 只有 1 行、且人群为既往 CVD，主分析排除、仅作敏感性。
3. **Moore2012 与 Arem2015**：同一 NCI 队列联盟 6 队列。本池**只取 Moore2012**（因为它报告了
   各类别人数，百分位可复算），Arem2015 保留为敏感性用，**不得同时计入**。

### 3.3 `arm` 分轴（方法与佩戴部位）与 `population` 隔离

`05a` **不直接用 `method` 作主轴**，而是由 `method × wear_site` 派生 4 水平的 `arm`：

| arm | 定义 | 当前来源 |
|---|---|---|
| `self` | 自报 | Moore2012、PURE2017 |
| `device_hip` | 设备 · 髋式 | Ekelund2019 |
| `device_mixed` | 设备 · 混合佩戴部位 | Tarp2024 |
| `device_wrist` | 设备 · 腕式 | Sun2025、Cao2024 |

**为什么要这样分**：本项目的暴露来自 **NHANES 腕式**设备，而 A3 之前池内**全部设备研究都是髋式/混合**
—— 此时「设备 vs 自报」的方法效应会把**佩戴部位**差异一并吞掉，部位效应**不可分离**。
补齐腕式来源后，`LPA` 上首次出现 hip × wrist 双覆盖，部位效应才可估（结果见 `code/README.md`）。

**`population` 为什么要单独一列**：Cao2024 的人群是**既往确诊 CVD**（基线风险完全不同）。
若与一般人群混在同一斜率里，会把"人群差异"算成"佩戴部位差异"——而这两者在该文中**完全共线**
（唯一腕式亚组来源）。因此主分析按 `population == "general"` 过滤，`clinical_subgroup`
只在 `spec = sensitivity_all_populations` 下纳入，**两个数值都报告**。

---

## 4. 抽取规范（**照着做，别自由发挥**）

1. **先看模型**：只抽**校正后（fully adjusted）**的 HR；未校正/年龄-性别校正的模型只作敏感性进 `notes`。
2. **参照组**：只抽"相对于**该研究最低活跃类别**"的对比。若原文以最高类别为参照，**必须换算**
   （倒数 + CI 取倒数后**上下界互换**），并在 `notes` 写明已换算。
3. **每一行 = 一对对比**，各带自己的 CI。
4. **CI 口径**：只接受 **95% CI**。90%/99% CI 或 SE 必须换算并写明，不得直接当 95% 用。
5. **统一到百分位刻度**（本池的核心换算）：
   - 先确认原文的**类别构造方式**，据此选 `pct_rule`；
   - **优先**用原文类别人数反算（可复算）；**其次**用构造等份额；**最后**才用等份额假定并标注；
   - `exposure_orig_unit / _lo / _hi` **必须填**，否则换算不可审计（`05b` 会检查）；
   - `exposure_ref_center` 填**该研究参照类别**的中点百分位（不是全表统一的 12.5）。
6. **同一研究的多行不是独立的**：共用参照组 → 抽样误差相关。脚本按独立近似（偏乐观），
   **Methods 必须声明**；有协方差矩阵时优先补入。
7. **只抽**能与其他来源形成**对照臂**的指标：若某指标在本池中只有 1 行、且无其他来源报告，
   不要抽（会产生对任何对比都零信息量的孤立组合，还稀释 metric 轴）。例：**Cao2024 的 MPA/VPA
   被有意排除**（见 `extraction_log.csv` 的 `REJECTED_CAO_MPA_VPA`）。
8. **`population` 必须标**：社区/一般人群队列填 `general`；疾病人群（如仅 CVD、仅 CKD、仅肿瘤）
   填 `clinical_subgroup` 并在 `notes` 写明人群定义与占比。
9. **源文献自身非单调要如实登记**：如 Sun2025 的 LPA `Q4 (0.77) > Q3 (0.75)`。
   这类非单调**不是抽取错误**，必须在 `notes` 写明 —— `05b` 的方向检查会按"回升幅度"分级
   （≤0.05 → WARN；>0.05 → FAIL 需人工复核）。
10. **一条不准就标 `notes` 并在 `extraction_log.csv` 留痕**，不要"顺手修一下"。
11. **被拒来源也要留痕**：`extraction_log.csv` 中已有 `REJECTED_EK16`、`REJECTED_CAO_MPA_VPA`、
    `REJECTED_PL24` 三条。

---

## 5. 待补清单（按优先级）

| 优先级 | 来源 | 为什么重要 | 状态 |
|---|---|---|---|
| ✅ **已完成（A3）** | **Sun2025**（PMID 41201595，UK Biobank 一般人群腕式） | 唯一能与髋式做**部位对比**的一般人群腕式来源 | **已入表（3 行）** |
| ✅ **已完成（A3）** | **Cao2024**（PMID 39087659，UK Biobank 既往 CVD 腕式） | 腕式 + 临床亚组；仅报最高四分位 → 单点 | **已入表（1 行，仅敏感性）** |
| ⭐⭐⭐ | **ProPASS 纵向资源**（24 万+ 参与者，41 队列，含死亡与 NCD 结局） | 全球唯一大规模**大腿式**设备 + 前瞻结局资源；可把部位轴扩到 thigh | 向 ProPASS 数据访问委员会申请 |
| ⭐⭐⭐ | **腕式 × `total_PA` / `MVPA` 来源** | 当前部位效应**只能在 LPA 上估**；若 MIMS/day 主线也要有腕式锚点，需补此类来源 | ⚠️ **已系统检索，无一可直接抽取** → 见 §5.1；两条候选待全文确认（`PENDING_K25` / `PENDING_IE24`） |
| ⭐⭐ | **Arem 2015** | 与 Moore2012 同池但剂量层级更细（7 级）→ 仅作**敏感性**，不可与 Moore 同时计入 | 公开（PMC） |
| ⭐⭐ | **Asia Cohort Consortium**（PMID 29490039） | 东亚人群自报 LTPA，n=467,729 / 65,858 死亡；对**中国外推**直接相关 | 公开（PMC6005114） |
| ⭐ | NHANES 2003–2006（**髋式** ActiGraph） | 与 2011–2014（腕式）同国同体系，可直接估计**佩戴部位效应** | 公开下载 |

**当前状态**：`05a` 判定 **`READY`**（主分析 5 研究 ≥ 3，self + 3 类设备臂齐备），
已产出可解释的**方法效应**与**佩戴部位效应**（结果见 `code/README.md`）。

---

## 5.1 腕式 × 总量来源：系统检索结论（2026-10-12）

**结论：当前文献中不存在「一般人群 + 腕式 + `total_PA`/`MVPA` + 类别 HR」的可抽取来源。**
逐一核查了 5 个最接近的候选，全部因**设计或可得性**不可用；已在 `extraction_log.csv` 逐条留痕。

| row_id | 来源 | 具备的条件 | ⛔ 不可用原因 |
|---|---|---|---|
| `PENDING_K25` | **Ko 2025**（J Nephrol，PMID 40721562） | 腕式、**非 CKD（≈一般人群）**、四分位、**摘要即给边际 HR**（0.72/0.65/0.57） | **指标定义未知**（DMPA 是总量？平均加速度？MVPA？）且全文付费墙 → 未确认前不得入表；另：竞争风险模型、与 Sun2025 同 UKB 腕式子样本非独立 |
| `PENDING_IE24` | **Inan-Eroglu 2024**（CEBP，PMID 38437645） | 腕式、明确含 **TPA**、三分位 | HR 全部是 **PA × 膳食 联合类别**，无 TPA 边际 HR（摘要只给 VPA 示例）→ 需全文/补充表 |
| `REJECTED_R24` | **Rezende 2024**（IJBNPA，PMID 38961452） | 腕式、强度特异性 | 设计为**久坐 × PA 联合**，只报「抵消久坐所需 PA 量」→ 无类别 HR |
| `REJECTED_EC25` | **Eckmann 2025**（Sci Rep，PMID 41353463，**开放获取**） | 两个**腕式**队列（Whitehall II + UK Biobank），且显式含 **MIMS** | 暴露是 **AvAcc × IG 联合四分位** + 按 SD 的样条 → **无 AvAcc 边际类别 HR** |
| （已有）`CAO24` | Cao 2024 | 腕式 | 临床亚组（CVD）+ 仅报最高四分位 → 已作敏感性 |

**三条闭合路径（按推荐度）**

1. **机构文献传递取全文** → 确认 `PENDING_K25` 的指标定义、或取 `PENDING_IE24` 的 TPA 边际 HR。
   成本最低；一旦确认即可补 2–3 行 `device_wrist|total_PA`。
   **2026-10-12 已定论：此路必须走文献传递** —— Unpaywall 对两篇均判 `is_oa=False / oa_status=closed`、
   `oa_locations` 为空；Europe PMC 亦为 `isOpenAccess=N / inPMC=N / hasSuppl=N`；
   机构仓储（剑桥 Apollo 等）绿色 OA 检索无命中。**申请单与逐字段确认清单见
   `data/bop/文献传递申请单_腕式总量来源.md`。**
2. **NHANES 2003–2006（髋式，公开）vs 2011–2014（腕式，本研究）** ← **证据强度最高**。
   ✅ **2026-10-12 已执行完毕** —— 结果与裁定见 **§6**（部位效应在总量轴上不可检出；
   NHANES 两臂作为**受控敏感性池**接入，不进主池）。
   同国、同调查体系、同一套处理流程 → 直接估计**佩戴部位效应**的本土证据，**无需任何数据申请**，
   且不引入任何外部人群的可迁移性假设。代价：需下载并清洗 2 个周期的分钟级文件。

   **可行性侦察（2026-10-12 实测，非推测）**

   | 项目 | 事实 |
   |---|---|
   | 文件 | `PAXRAW_C.ZIP`（2003–2004，**407.7 MB**）、`PAXRAW_D.ZIP`（2005–2006，**449.2 MB**） |
   | 直链 | ⚠️ **必须用新版路径**：`https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2003/DataFiles/PAXRAW_C.zip`、`.../Public/2005/DataFiles/PAXRAW_D.zip`<br>（CDC 已改版；旧式 `/Nchs/Nhanes/2003-2004/PAXRAW_C.ZIP` 现返回 **HTML 页面而非 ZIP**，`Content-Length` 恒为 20905 字节，2026-10-12 实测踩过） |
   | 实测校验 | 新链返回 `application/x-zip-compressed`、魔数 `50 4b 03 04`；`Content-Length` 427,543,657 / 470,990,068 字节，与 CDC 数据页标注完全一致 |
   | 设备 | ActiGraph **AM-7164，髋式**，单位 = counts/min（`PAXINTEN`）；与本研究 2011–2014 腕式 GT3X+（MIMS）**不同单位** |
   | 解压后体量 | 每周期约 **2.5 GB**（长表：一受试者-分钟一行），两周期合计约 5 GB |
   | `PAXSTEP` | **2003–2004 无**（仅 2005–2006 有） |
   | 现成流水线 | R 包 **`rnhanesdata`**（GitHub `oslerinhealth/rnhanesdata`，master，2021 年后未再更新）：`process_accel()` + `process_flags()` 一条命令产出 1440+ 格式活动计数矩阵与 wear/non-wear 标志；官方称笔记本约 **30 min**；方法学有同行评议文献支撑（**PMC7012355**） |
   | **可省 5 GB 重处理** | 该仓库 `data/` 直接提供**已处理好的参考数据**（合计约 85 MB）：<br>· `PAXINTEN_C.rda` / `PAXINTEN_D.rda`（40.9 / 42.6 MB）＝ 1440+ 格式分钟活动计数<br>· `Flags_C.rda` / `Flags_D.rda` ＝ wear/non-wear 标志<br>· `Covariate_C.rda` / `Covariate_D.rda` ＝ 人口学/生活方式/合并症协变量<br>· `Mortality_2011_C/D.rda` 与 **`Mortality_2015_C/D.rda`** ＝ NDI 死亡链接（后者随访至 2015，更优）<br>→ 已下载至 `data/raw/rnhanesdata_ref/`；本项目仍会下载原始 ZIP 并用 `process_accel()` 自跑一遍做 `identical()` 核验，形成可复现性证明 |
   | 死亡链接 | 2003–2006 周期 NDI 公共链接死亡率文件公开可得；`rnhanesdata` 已内置处理后的版本 |

   **与 Module 2 框架的接合方式（重要）**：不把两个周期当作"新指标"，而是当作**两个独立的
   新研究**加入 BoP 池，分别打 `wear_site = hip` 与 `wear_site = wrist` 标签。
   由于 2003–2006（counts）与 2011–2014（MIMS）单位不同，**不直接比较暴露绝对值**，
   而是把各自的 PA→死亡 RR 曲线表达在**各自人群的百分位偏移轴**上（即本模块已实现的
   `offset_pts` 尺度）→ 部位效应恰好落在 BoP 元回归的 `wear_site` 协变量上，
   **与现有 `device_hip` / `device_wrist` 后验用同一套估计逻辑**，无需新增方法。
   附带收益：2011–2014 正是 M1 自身队列 → 可反向校验 M1→M2 链条的自洽性。

   代价：需下载 ~0.86 GB、跑通加权 Cox+RCS（`04` 脚本可近乎原样复用），
   再补一轮 `05a` 池化。属于"工作量大但路径完全确定"的一类。

3. **ProPASS 纵向资源**（申请制）：不止解决腕式，还能把部位轴扩展到 **thigh（大腿式）**。

**顺带得到的可引用资产**：`REJECTED_EC25`（Eckmann 2025，开放获取）的结论——ENMO / MAD / **MIMS** / Counts
四种 epoch summary measure 得到的 PA–死亡关联**趋势一致（CI 全程重叠）**——可作为本研究
**选用 MIMS 作为设备尺度**的方法学依据，写入 Methods（其 Table 2/3 给出 MIMS 与 ENMO 的
AvAcc 相关 r = 0.69–0.79、IG 的 ICC 0.69–0.80）。

---

## 6. 路径 2 落地：NHANES 两臂的**受控**接入（2026-10-12）

§5.1 路径 2 已**执行完毕**。核心裁定是：**NHANES 两臂不进 `rr_table.csv`**，
而是作为**受控敏感性池**由 `code/05c_module2_nhanes_site_sensitivity.R` 在内存中追加。

### 6.1 为什么不进主池（三条，须写进 Methods）

| # | 理由 | 量化证据 |
|---|---|---|
| 1 | **定位冲突** | Module 2 立论 = 池化**外部文献**队列支持全球外推。注入自算分析 → "外部证据"部分自我循环（同一批 NHANES 既定义百分位分布、又贡献 RR） |
| 2 | **设计不可通约** | NHANES：单次 7 天基线测量 + 随访中位 **14.3 年**；池内 Ekelund2019 = 5.8 年、UKB 系 = 8 年。随访越长 → 回归稀释 + 反向因果越重 → 向 1 衰减。NHANES 曲线整体更平（`off80` RR **0.509** vs 池化 **0.373**）正是该机制的产物，而非"更准" |
| 3 | **权重压倒** | NHANES 每点 log-SE ≈ **0.028**，EK19 约 **0.058** → 固定效应权重约 4 倍。实测：NHANES 在 B 档 `device_hip` 臂占 **83%**、`device_wrist` 臂占 **100%** → 曲线被**设计差异**而非信息量拽平 |

### 6.2 三档对照结果

| 档 | 池内容 | 行数/研究 | `total_PA` 髋÷腕 @off60 | 95% CI | p |
|---|---|---|---|---|---|
| **A** | 仅外部文献（= 复现 05a 主分析） | 21 / 5 | 不可估（池内无腕式 `total_PA`） | — | — |
| **B** | 文献 + NHANES 两臂 | 37 / 7 | **0.978** | 0.795–1.203 | **0.835** |
| **C** | 仅 NHANES 两臂 | 16 / 2 | 1.143 | 0.916–1.426 | 0.237 |

- **A 档复现 05a 达机器精度**（`device_pooled × total_PA` 最大绝对偏差 **4.441e-16**）→ 对照基准成立。
- 文献侧唯一可估的部位效应（LPA，A 档）= **0.658 [0.496, 0.873], p=0.0037**，**方向与 NHANES 相反**
  （文献说髋式更陡）。并入 NHANES 后变为 0.791 [0.605, 1.033], p=0.085。**这一矛盾必须在论文里如实并列讨论。**
- 并入 NHANES 后池化曲线整体变平：`off80` RR **0.3732 → 0.4831**（比值 1.294）。

### 6.3 新增的 16 行（NHANES 自算）的行级约定

| 字段 | `device_hip` 臂（2003–2006） | `device_wrist` 臂（2011–2014） |
|---|---|---|
| `row_id` | `NH2003_2006_hip_P22.5` … `_P92.5` | `NH2011_2014_wrist_P22.5` … `_P92.5` |
| `source` / `study` | `NHANES_own_2003_2006_hip` | `NHANES_own_2011_2014_wrist` |
| `design` | `own_analysis_svycox_ns` | 同左 |
| `device_type` | `ActiGraph 7164 (uniaxial, hip)` | `ActiGraph GT3X+ (triaxial, MIMS)` |
| `wear_site` | `hip` | `wrist` |
| `metric_definition` | `total_PA` | `total_PA` |
| `exposure_scale` | `pct_weighted_quantile` | 同左 |
| `pct_rule` | `imposed_weighted_quantile_grid` | 同左 |
| `exposure_center` | 22.5 … 92.5 | 同左 |
| `exposure_ref_center` | **12.5**（= 最低四分位中点，与 `ref_canon` 一致） | 同左 |
| `exposure_orig_unit` | `counts/day` | `MIMS/day` |
| `exposure_orig_lo` | `Table6` 的 `expo_hip` | `Table6` 的 `expo_wrist` |
| `n_total` / `n_cases` | 5,334 / 1,351 | 7,007 / 664 |
| `population` | `general` | `general` |

- **参照点（`pct=12.5`，offset=0）不入表** —— 按构造 RR=1，与池内其它研究一致（只放对比点）。
- 每行 `notes` 内**内嵌**「本项目自算，非文献抽取」+ 设计差异 + 口径差异声明；`extraction_log.csv`
  中 `extracted_by = 本项目自算（04b）` → **与文献抽取行在台账层面即可区分**。
- 写台账是**幂等**的：`05c` 先按 `row_id` 查重，已存在则跳过（避免反复 append 撑大文件 → 破坏跨运行指纹）。

### 6.4 复现要点

```bash
# 05c 依赖 Table5（05a）与 Table6（04b），须在其后运行
Rscript 00_run_all.R --only 05a_module2_bop,05b_verify_bop_table,05c_module2_nhanes_site_sensitivity
```

`05c` 产出的 `bop_rr_draws_withNHANES.rds` 与主产物 `bop_rr_draws.rds` **结构完全一致**，
可直接喂给 `95_module3_paf.R`（用 `PA_RR_DRAWS=` 覆盖）做影响力敏感性。详见 `code/README.md`。

## 7. 路径 1 待命入表管线（`05d`，2026-10-12）

路径 1（机构文献传递取 `Ko2025` / `Inan-Eroglu2024` 全文 → 补 2–3 行 `device_wrist｜total_PA`）
需要一个**全文到手就能一键入表**且不会填错的通道。已固化为：

| 文件 | 作用 |
|---|---|
| `rr_table_pending_intake.csv` | **待填模板**（首次由 `05d` 生成）：5 个候选行（`Ko2025` 四分位 ×3、`Inan-Eroglu2024` 三分位 ×2），全部 `intake_status = pending` |
| `code/05d_bop_intake_pending.R` | 校验 + 入表 + 留痕；**默认 dry-run** |
| `output/QC_bop_intake.csv` | 逐行逐条校验结果（`ACCEPT` / `PENDING` / `SKIP`） |

**10 条硬规则**（任一不过 → 该行 `PENDING`，`APPLY` 模式下拒绝写表）：

| 规则 | 内容 |
|---|---|
| `V1` | `row_id` 非空且不与现有表重复（→ 天然幂等，重跑不会重复入表） |
| `V2` | `05a` 要求的 15 个必需列齐备 |
| `V3` | `0 < hr_lo ≤ hr ≤ hr_hi` |
| `V4` | `method == "device"` 且 `wear_site == "wrist"`（本路径只补腕式行） |
| `V5` | `exposure_center` / `exposure_ref_center` 非空且 `ref < center` |
| `V6` | `population == "general"`（与 `05a` 主分析同口径） |
| `V7` | `intake_axis_confirmed == "total_PA"`（按申请单 A1 / B2 的结论；不确定则**不入表**） |
| `V8` | `pmid` 与 `doi` 齐备 |
| `V9` | `intake_ref_is_lowest == "Y"`（PAF 反事实锚点必须锚在最低类） |
| `V10` | `intake_cutpoints_known == "Y"`（`05b` 会逐项复算百分位） |

```bash
# 1) 生成/刷新模板（只读，不改主表）
Rscript 05d_bop_intake_pending.R
# 2) 填好模板后先看校验报告
Rscript 05d_bop_intake_pending.R ; cat ../output/QC_bop_intake.csv
# 3) 全绿后真正入表（自动备份 + 台账幂等追加）
PA_INTAKE_APPLY=1 Rscript 05d_bop_intake_pending.R
# 4) 按脚本末尾打印的顺序重跑主链（05b → 05a → 05c → 04c → 04d → 95 → 95b → 06/98 ×2）
```

**已端到端实测**（2026-10-12，用一条 `TESTONLY` 行）：`ACCEPT 1` → 主表恰好 +1 行、台账恰好 +1 条；
重跑幂等（md5 不变）；测试后主表与台账**逐字节还原**（md5 与测试前一致），测试备份已删除。
⚠️ 注意 `extraction_log.csv` 的**首列是 `date_utc`（不是 `row_id`）**，台账行必须按台账自身列名构造。

