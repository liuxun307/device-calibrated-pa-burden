# 代码包运行手册

## 目录

```
范式A_低体力活动_加速度计/
├── 00_完整研究方案.md        ← 主方案（先读这个）
├── code/
│   ├── 00_run_all.R          ← 总入口（按序跑到 98）
│   ├── 00_setup.R            ← 环境锁定 / 路径常量 / 种子 / 日志
│   ├── 01_fetch_data.R       ← 下载 + 读入 NHANES/GHDx（SHA-256 固化）
│   ├── 01b_fetch_pam_2003_2006.R    ← 2003-2006 髋式 PAM 原始件 + rnhanesdata 参考数据
│   ├── 01c_verify_paxinten_vs_raw.R ← 【核验】参考宽表 vs 原始 xpt 全文件逐人一致
│   ├── 02_accel_processing.R ← 加速度计清洗 + 暴露构建
│   ├── 03_exposure_merge_survival.R ← 自报 MET-min + 协变量 + 死亡合并
│   ├── 03b_pam_exposure_2003_2006.R ← 2003-2006 髋式暴露（同口径）+ 协变量 + 死亡
│   ├── 03c_hip_wear_rule_variants.R ← 髋式 wear 判定**规则全谱**（5 套，同一分钟矩阵）
│   ├── 03d_wrist_criterion_variants.R ← 腕式有效日**判据全谱**（7 套，含"全天佩戴"对齐髋侧）
│   ├── 04_cox_dose_response.R← 加权 Cox + RCS 剂量-反应
│   ├── 04b_pam_site_rr.R     ← 佩戴部位效应：髋式 vs 腕式（百分位轴）→ Table 6
│   ├── 04c_site_wear_sensitivity.R ← 部位效应矛盾裁决：髋规则 × 腕判据 → 比值矩阵（Table 8）
│   ├── 04d_lit_site_contrast.R ← 文献侧"部位效应"可分解性 + 与 NHANES 的相容性检验（**metric-aware**：§0 运行时机器校验 NHANES 曲线属总量轴，§2b 量化跨指标许可）
│   ├── 04e_pam_intensity_rr.R ← **强度维度**（髋式分钟级 Peak-30 / MVPA 的剂量-反应）→ `Table11_pam_intensity_*`（**辅助，不入主链**：但 `08c` 的 Fig 3(c)(d) 面板消费其产物，故其产物须先在盘上）；04e 编号的占用见 `04f` 注
│   ├── 04f_lit_site_anchor.R ← 文献侧部位效应的**指标稳健性**：腕式 × total_PA 外部锚定 + 与 NHANES 的**同指标**对照（2026-10-16 由 `tools/site_anchor_totalPA.R` 提升为正式步骤，紧接 04d 之后）
│   ├── lib/pa_site_lib.R     ← **曲线拟合唯一实现**（04b 内联副本 + 04c/04d 共用本库）
│   ├── 05a_module2_bop.R     ← Module 2：外部队列池化（方法 × 佩戴部位 为协变量）
│   ├── 05b_verify_bop_table.R← Module 2 输入表审计（百分位复算 + 方向/结构）
│   ├── 05c_module2_nhanes_site_sensitivity.R ← NHANES 两臂接入 BoP 池的**受控敏感性**
│   ├── 05d_bop_intake_pending.R ← 路径 1 待命入表管线（**默认 dry-run**，V1–V10 校验 + 幂等入表）
│   ├── 05_burden_calibration_paf.R ← 校准 + S1′（SD–mean 关系）+ BoP 合成 + PAF 重算
│   ├── 06_manifest.R         ← 产物指纹清单
│   ├── 95_module3_paf.R      ← Module 3 PAF（两条通道：`PA_CV_MODE=s1p` 主分析 / `grid` 敏感性；已入主链，06 之前；**2026-10-15 改确定性枚举后 grid ≈ 35 s、s1p ≈ 48 s**，原为 15 min / 4 min；`PA_M3_HELPERS_ONLY=1` 复用开关供 95c 共享桥接逻辑，**零行为变更已验证**，见 logs/_95gate_verification.md）
│   ├── 95c_module3_bycountry.R ← **Module 3 逐国版**（205 location = Global + 204 国）→ Fig 5(b)(c) + Table S4 底表；按 location 并行（`PA_M3_CORES`，默认核数-1 上限 8）；**2026-10-15 改确定性枚举后 205 国 s1p ≈ 1.1 min（原 ≈ 17 min）**；并行确定性已验证（CORES=1 与 4 的 4 个产物逐字节一致）；`PA_M3_RESUME=1` 显式断点续跑（复用 checkpoint，仅限 §5 聚合逻辑改动时）；注意它 **`source("95_module3_paf.R")`**，故会连带以 s1p 模式重跑 95 并产出 `PREVIEW_module3_s1p_*`
│   ├── 96b_sdi_anchor.R      ← **SDI 锚点表**（205 location × 1990/2022/2023 + 官方五分位）→ Table 14；金标准 183/183 与官方 quintile 逐条一致；秒级
│   ├── scratch/              ← 一次性探测脚本（_probe_*），不属管线
│   ├── 95b_paf_impact_compare.R ← A（文献池 s1p）vs B（+NHANES s1p）的 PAF 影响力对照 → **Table 7**（**2026-10-15 入主链**，位于 95c 之后、97 之前；内部会把 95 跑一遍生成 B 档，约 1 min）
│   ├── 96_gbd_download_plan.R← GBD 下载计划复算 + 已下载分片核验（辅助，不入主链）
│   ├── 97_m3_scenarios.R     ← **Module 3 情景表**：fold 口径分解 + 正式定级（Table 9）+ GBD 口径对齐 + 稳健性（Table 10×2）；影子脚本（不改主链、不覆盖冻结产物）
│   ├── 07_fig5d_waterfall.R  ← **Fig 5(d) 口径分解瀑布图**（只读 97 的 Table4/9，fold 5.79→0.99 的三段分解 + 8 地区补充图；已入主链，97 与 06 之间）
│   ├── 09_tables.R           ← Table 1–4 投稿版（加权基线 / HR / 校准 / 负担对比）
│   ├── 10_captions.R         ← **图注 / 表注生成器**（中英双语；Fig 1–6 共 17 面板 + Table 1–4 + 补充表 S1–S12；所有数值从 `output/` 产物动态读取，脚本内不写死结果数字；末尾附「口径一致性自检」段，约 6 s）
│   ├── tools/                ← 开发期辅助工具（`lint_sprintf_args.py`：sprintf 占位符-实参一致性静态检查；`syncheck.R`：带 locale 回退链的语法总检）。**注**：`tools/site_anchor_totalPA.R` 已于 2026-10-16 提升为正式步骤 `04f_lit_site_anchor.R` 并删除，仓库内无残留引用
│   ├── 97_test_module3.R     ← Module 3 函数级真数据自检
│   ├── 98_verify_reproducibility.R ← 五层复现性核验
│   └── 99_smoketest.R        ← 合成数据烟囱测试
├── data/
│   ├── raw/                  ← 原始 xpt/dat（脚本自动下载）
│   ├── derived/              ← 缓存的 rds
│   ├── bop/                  ← Module 2 外部证据输入（rr_table.csv + 抽取规范）
│   └── gbd/                  ← 手工下载的 GBD 2023 CSV
└── output/                   ← 图（PDF/PNG）与表（CSV）
```

## 环境依赖

**本机已验证可用的 R**：`D:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe`（R 4.5.2）

| 版本 | 状态 |
|---|---|
| **R-4.5.2** | **用这个**。`haven/data.table/tidyverse/survey/ggplot2/patchwork/rms` 全齐（库：`C:/Users/Lenovo/AppData/Local/R/win-library/4.5`） |
| R-4.5.1 | 同 4.5.2，也可用 |
| R-4.6.0 | ⚠️ 只有 data.table，缺其余全部依赖，**不要用** |

**Module 2 的引擎（2026-10-16 更新：已升级为真贝叶斯）**：原先本机**无 C++ 工具链**（`gcc/g++/make/gfortran` 全缺，
`R CMD SHLIB` 报 `'make' not found`）→ Stan / brms 装了也跑不起来。**该限制已解除**：
已装 Rtools45 到 `D:\rtools45` 并经 `~/.Renviron` 的 `RTOOLS45_HOME` 生效，Stan 链路打通。
`05a_module2_bop.R` 的**默认引擎**现为 `brms::brm`（真贝叶斯多水平 meta-regression），
`metafor::rma.mv` 退为**兜底**（设 `PA_BOP_ENGINE=metafor` 显式启用）。

| 包 | 版本 | 作用 |
|---|---|---|
| `brms` | 2.23.0 | **默认引擎**：多水平贝叶斯 meta-regression（`brm`） |
| `rstan` | **2.32.7** | brms 的 Stan 后端（**必须**配 StanHeaders 2.32.x，见下） |
| `StanHeaders` | **2.32.10** | 与 rstan 严格配对；误装 2.39.1 会编译失败 |
| `metafor` | 5.2-1 | **兜底引擎**：`rma.mv()` 多水平随机效应 + 方法学协变量 |
| `clubSandwich` | 0.7.0 | CR2 聚类稳健方差（聚类于 study；仅 metafor 路径） |
| `meta` | 8.5-0 | 森林图等辅助 |

⚠️ **版本配对是硬约束**：`rstan 2.32.7` 配 `StanHeaders 2.39.1` 会在
`.../stan/mcmc/hmc/hamiltonians/dense_e_metric.hpp:21` 处编译失败。装 `StanHeaders_2.32.10.tar.gz`（CRAN Archive）即可。
另注意 `brms`/`rstan` 是 `mi`/`broom` 等**间接依赖的 S3 方法覆盖源**，升级时留意 `Registered S3 method overwritten` 提示。

```r
install.packages(c("metafor", "clubSandwich", "meta"), type = "binary")
```

> **2026-10-16 已完成：Module 2 升级为真贝叶斯引擎。** 方案/正文写的是「贝叶斯 meta-regression（BoP 框架）」，
> 而本机原先无 C++ 工具链（`gcc` / `make` / `gfortran` 全缺，`R_RTOOLS45_PATH` 指向不存在的 `c:/rtools45`），
> 故 `05a_module2_bop.R` 实际跑的是 `metafor::rma.mv`（REML）+ `clubSandwich` CR2 + `MASS::mvrnorm` 参数自助。
> 为使名实相符，**已补装 Rtools45 并完成 brms/rstan 链路打通**（实测：`0` 次发散转移、斜率 max Rhat = `1.0025`）。
>
> **① Rtools45 的路径机制（关键）**：R 4.5.2 的 `etc/Rcmd_environ` 第 39–42 行**由 `RTOOLS45_HOME` 推导**工具链 PATH，
> 缺省值为 `c:/rtools45`：
> ```
> R_RTOOLS45_PATH="${RTOOLS45_HOME:-c:/rtools45}/x86_64-w64-mingw32.static.posix/bin;${RTOOLS45_HOME:-c:/rtools45}/usr/bin"
> PATH="${R_CUSTOM_TOOLS_PATH:-${R_RTOOLS45_PATH}};${PATH}/"
> ```
> 装到**默认路径 `C:\rtools45`** → 零配置；装到别处（本机 `D:\rtools45`）则**必须显式**设 `RTOOLS45_HOME`。
> 又因 R CMD 前端在 R 进程**启动之前**就固定好 PATH，故 `~/.Renviron` 里须**同时**给三行（双保险）：
> ```
> RTOOLS45_HOME=D:/rtools45
> PATH=D:/rtools45/x86_64-w64-mingw32.static.posix/bin;D:/rtools45/usr/bin;${PATH}
> MAKE=D:/rtools45/usr/bin/make.exe
> ```
> 自检验证：`R CMD SHLIB` 能编出一个平凡 C 文件即通过（原先报 `'make' not found`）。
>
> **② 版本配对（否则 Stan 编译必失败，已实测）**：`rstan 2.32.7` 必须配 **`StanHeaders 2.32.x`**（本机 `2.32.10`）。
> 若装成 CRAN 当前的 `StanHeaders 2.39.1`（与 rstan 打包时间差 18 个月、跨大版本），
> 会在 `StanHeaders/include/src/stan/mcmc/hmc/hamiltonians/dense_e_metric.hpp:21` 处编译报错。
> 修法：从 CRAN Archive 源码安装 `StanHeaders_2.32.10.tar.gz`（约 5 min）。
> 用 **TUNA（清华）镜像**装二进制可免编译（官方 CRAN 直连本机约 12 KB/s，清华约 5.4 MB/s）。
> 正确的 Rtools45 安装包文件名是 **`rtools45-6768-6492.exe`**（483,090,888 字节），
> 官方站的 `rtools45-x86_64.exe` 是 404。
>
> **③ 模型口径（`se()` 的确切语义，已用 `make_stancode` 实测确认）**：
> - `se(sqrt(vi), sigma = FALSE)` → Stan 生成 `real sigma = 0;`，似然方差**恰为**已知抽样方差 `se²`
>   → 与 `metafor::rma.mv(yi, V = vi, random = ~1|study)`（方差 = `vi + τ²`）**严格同模型**，
>   `(1|study)` 单独承担研究间异质性。**本脚本默认此项**（开关 `PA_BOP_SE_SIGMA`，默认 `false`）。
> - `se(..., sigma = TRUE)` → 生成 `real<lower=0> sigma;`，似然方差 = `sigma² + se²`，额外允许未建模的组内残差异质性；
>   实测 `sigma→0` 边界形成漏斗，**产生 3 次发散转移** → 故不采用。
> - ⚠️ `se(..., sigma = )` 的实参**必须是字面量** `TRUE`/`FALSE`：传变量名会被 brms 当数据列名查找并报
>   `The following variables can neither be found in 'data' nor in 'data2'`。脚本用 `switch()` 展开为 4 个字面量公式。
>
> **④ 确定性**：固定 `seed = PA_SEED`，曲线池从后验抽样按**等距无放回**取 `N_DRAW` 条（后验 ≥ N_DRAW 时），
> 故跨运行逐字节可复现（E 层对照已验证「一致 297 / 不一致 0」，2026-10-16 连续两轮链跑）。
>
> 由于 `05a` 的**输入表与输出契约不变**，换引擎不需要改动任何其他脚本；
> 换引擎后 BoP 后验已变 → 下游 `95/95c/95b/97/07/08*/09/10/06/98` 需整体重跑一遍。
> 回退开关：`PA_BOP_ENGINE=metafor`（脚本会打印 WARN 表明用的是兜底引擎）。
>
> **⑤ 引擎已抽成共享模块 `code/lib/pa_bop_engine.R`（2026-10-16）**。`05a_module2_bop.R`
> 与 `05c_module2_nhanes_site_sensitivity.R` **必须同引擎**，否则 ① Methods 会出现两套池化口径；
> ② 05c 的「A 档逐值复现 05a 主产物（< 1e-6）」自检必然失败——A 档的数据就等于 05a 的 `dt_main`，
> 只有同引擎 + 同 seed 才可能逐值一致。模块对外提供 `FORM_MAIN`/`FORM_CURV`、`fit_pool()`、
> `coef_of()`、`build_X()`、`predict_from()`、`contrast()`、`device_arm_lvs()`、`pooled_w()`，
> 并自行读取 `PA_BOP_*` 开关。**新增按此引擎拟合的脚本时，一律 `source()` 该模块，不要另写一份。**
>
> **⑥ ★ Windows 中文路径下 rstan 并行链必然挂死（必读）**。`cores > 1` 时 rstan 走
> `parallel::makeCluster(type = "PSOCK")`，由主进程 `system2()` 拉起 worker 子进程，命令行带项目 cwd；
> 而本项目为读中文路径已把 `LC_CTYPE` 设为 UTF-8 → **R 无法把中文路径转成本地编码传给子进程**
> → worker 起不来，`sampling()` 静默挂死（无报错、无输出、无新文件）。
> **这正是本文档「坑 3」的同一根因**（坑 3 当时只表现为 `system2()` 报错，这里是静默挂死，更难发现）。
> 实测：`cores = 4` 在 `E:/WorkBuddy/.../范式A_低体力活动_加速度计` 下**主模型 12 分钟零进展**；
> `cores = 1` 同一模型 **2.1 分钟**完成。故脚本已内置自动降级：
> ```r
> BOP_ASCII_PATH <- !grepl("[^ -~]", PA_ROOT)
> BOP_CORES <- if (.Platform$OS.type == "windows" && !BOP_ASCII_PATH) 1L else BOP_CORES_REQ
> ```
> 路径含非 ASCII 字符时强制串行（**只影响墙钟时间，不影响后验**——每条链的种子由 `seed + chain_id`
> 决定，与 `cores` 无关）。要覆盖可设 `PA_BOP_CORES`。→ **若把项目目录改成纯 ASCII，可恢复 4 核并行。**
>
> **⑦ 排查长跑脚本时，别用 `cat()` 打进度**：`cat()` 写 stdout 到文件是**块缓冲**的，
> 10 分钟的跑批在日志里"看起来像卡死"（只有 `message()`/`stderr` 会即时落盘）。
> `fit_pool()` 现已用 `message()` 报告每次拟合的起止与耗时。

## 运行顺序

**单入口编排器**（每步独立 R 进程执行，日志落盘 `logs/<RUN_ID>/`，失败即停）：

```
"D:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe" 00_run_all.R
# 分段运行（01 已有结果时省时）：
#   00_run_all.R --from 02_accel_processing
#   00_run_all.R --from 03_exposure_merge_survival --to 04_cox_dose_response
```

注意 `--from/--to` 的参数是**完整步骤名**（如 `02_accel_processing`），不是纯数字。

每步的 stdout/stderr 写入 `logs/<RUN_ID>/step_<步骤>.log`，结束时生成 `steps_summary.csv`。**子进程一律用纯 ASCII 相对路径调用**（编排器内部已处理；这是 Windows 上"UTF-8 locale + 中文路径 + system2"冲突的唯一解，见下文坑 3）。

## ⚠️ 两个 Windows 专属的坑（已在本机踩过并修复）

**坑 1｜R 读不了中文路径。**
Windows 下 R 启动时 `LC_CTYPE` 常为 `"C"`，此时 R **无法解析中文目录名**——`list.files()` 返回空、`source()` 会把路径截断。所有脚本顶部都加了环境引导，把 `LC_CTYPE` 依次尝试置为 `Chinese_China.utf8` → `zh_CN.UTF-8` → `English_United States.utf8` → `C.UTF-8`。
**如果仍失败**，最稳的办法是把整个项目目录改名为纯 ASCII，例如 `ParadigmA_LPA_Accelerometer`。

**坑 2｜图形里不能放中文。**
同一原因下，PDF/PNG 图形设备渲染中文字符会报 `mbcsToSbcs conversion failure`。**所有图内标签一律用英文/ASCII**（脚本 `04` 已按此写法）。图注中文写进 Word/ Illustrator 里再做。

**坑 3｜UTF-8 locale + 中文路径 + system2 调子进程必然失败。**
把 `LC_CTYPE` 设为 UTF-8 修复坑 1 后，会产生新问题：R 无法把中文路径转成 Windows 本地编码传给外部进程，`system2()` 报 `unable to translate ... to native encoding`（退出码 5）。实测退回 936/GBK locale 也不行——`list.files()` 对中文目录反而失效。**唯一可靠解法：cwd 切到脚本目录后，给子进程传纯 ASCII 的相对路径**。`00_run_all.R` 与 `99_smoketest.R` 已按此实现。

## 管道测试（强烈建议先跑）

`99_smoketest.R` 会在 `_smoketest/` 目录里**生成符合 NHANES 变量结构的合成数据**（含故意植入的 1% 质控违规、8% 佩戴不足样本、自报特殊码 7777/9999），然后按序跑通 `02→03→04→05` 全链路。

**2026-10-11 本机验证结果**：
- 语法解析 7/7 通过；
- `02` 质控恒等式报告精确捕捉到 0.99% 的故意违规（阈值应为 0）；
- `03` 1,379 人入组、130 例死亡；
- `04` 两个 Cox 模型拟合成功，`Fig3_dose_response.pdf/.png` + `rr_curves.csv` 正常产出，曲线在参照点（第 60 百分位 ≈ 12,310 MIMS/day）处穿过 HR=1，方向正确；
- `05` 校准方程跑通（TMREL 3000–4500 MET-min/周 → 设备等效 ≈ 11,260–11,326 MIMS/day），PAF 函数与闭式解一致（1e-12 内），`recompute_burden()` 正常。

**跑完可整体删除 `_smoketest/`，不影响真实数据。**

## 三步必做的人工动作

1. **路径**：默认根目录已内置；如移动项目位置，用环境变量 `PARADIGM_A_ROOT` 覆盖即可，无需改代码。
2. **下 GBD**：完整规格见 `data/gbd/GBD2023_下载指南.md`。
   - 暴露包（GHDx 整包）**已到位**，无需再下；
   - 归因负担与 cause 总负担须用 **Results 工具**下载，且**必然要分片**。先跑
     `"D:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe" 96_gbd_download_plan.R`
     得到行数预算与分片清单，再照单下载，放入 `data/gbd/`；
   - ⚠️ **Results 工具 10 万行上限**：`Deaths` 与 `DALYs` **必须分两次下**（同时勾 = 行数翻倍必报错）；Sex 只勾 `Both`（`Both = Male + Female`，三个同勾纯属重复）；Age 只勾 `All ages`（`Age-standardized` 是率口径，会污染）；
   - **文件命名与目录随意**：Results 工具导出的是「一目录一文件」的 hash 结构（`data/gbd/IHME-GBD_2023_DATA-<hash>-1/...csv`），`05` 的 `read_gbd_shards()` 按**内容**（`rei_name` 是否有值）区分批次 1/批次 2 并**递归**扫描、自动拼接多分片，同时对分片重叠做报警。**不要改名、不要移动、不要改数值**；
   - 下完跑 `96_gbd_download_plan.R`（`PA_GBD_PLAN_MODE=audit`）核验行数、维度乘积与分片互斥性，报告落盘 `logs/GBD_download_audit.txt`。
3. **核对两处映射**：
   - `03` 中 `UCOD_LEADING`（已按官方 layout 核实：1=心脏病、5=脑血管病、7=糖尿病；注意它**分不出 IHD 与缺血性卒中**，需写入论文局限）；
   - `05` 的 `LPA_CAUSES`：**不用手工改**。脚本会自动从批次 1 检出文件读取真实 cause 清单；只有文件缺失时才回退到内置的 8 类兜底清单。下载时**不要选 `All causes` 或父级节点**。

## 真实数据验证记录（2026-10-11）

`00_run_all.R` 全量运行（01–98 八步全部成功，总用时约 1.5 分钟）：

| 节点 | 结果 |
|---|---|
| 01 | 43/43 原始文件 SHA-256 固化；LMF 19,931 行（符合资格 11,949，死亡 1,095） |
| 02 | 日级暴露 13,027 人；质控三项违规率均为 0 |
| 03 | 分析集 7,854 人（educ 特殊码 7/9 置 NA 后完整案例 7,007） |
| 04 | svycoxph 收敛；参照值 13,222.1 MIMS/day（TMREL 绝对锚点，2026-10-15 起）；曲线呈 L 形（低活动端 HR≈2.8） |
| 05 | 校准方程 R²=0.19；自报 inactive 人群 63% 落入设备 Q1、24% 落入 Q2（报告偏倚量化） |
| 98 | **PASS 192 / WARN 0 / FAIL 0**（共 194 项，2026-10-16 贝叶斯轮）；连续两轮链跑 E 层跨运行指纹 **一致 297 / 不一致 0**（唯一差异为 PDF 内嵌时间戳与自指元产物，已列入豁免） |

**真实数据抓到的第 5 个 bug**：DMDEDUC2 的特殊应答码 7（拒答，n=1）/9（不知道，n=6）未清洗，近零方差哑变量导致 svycoxph 协方差矩阵奇异（`U[16,16]=0`）。合成数据造不出这种分布，只有真实数据才能暴露——已修复。

## Module 2：外部队列池化（2026-10-12 首次跑通）

```
"D:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe" 05a_module2_bop.R
```

读 `data/bop/rr_table.csv`（抽取规范见 `data/bop/README.md`）→ 拟合 →
产出 `output/Table5_bop_pooled_RR.csv`、`Table5_bop_method_effect.csv`、
`bop_rr_draws.rds`（1000 条曲线 × 57 网格点）、`QC_bop_status.csv`。

**首次运行结果（种子 = Ekelund 2019，9 行 / 1 研究 / 仅 device）**：

| 项 | 结果 |
|---|---|
| 拟合 | `pilot_per_metric`：`~ 0 + 指标:offset`（**强制过原点**），REML |
| 曲线集 | 1000 条 × 57 点，正常落盘 |
| 拟合优度 | `Table5_bop_fit_diagnostic.csv`：观测点最大 \|log 残差\| = **0.249**（RR 因子 1.28）→ **WARN**（失拟已显式量化） |
| 方向校验 | 最低分位 RR = 1.118 > 1，随活动量单调下降 —— **方向正确** |
| 门禁 | `NOT_READY`（研究数 1 < 3；缺 `self` 组 → 方法效应估不出） |

**踩到的三个坑（已修）**：

1. **模型未锚定参照组（真 bug）**：表内只有 Q2/Q3/Q4（HR 均 <1），没有 Q1 的 `HR=1`，
   直接对 `exposure_center` 线性拟合会**外推出"越不活跃风险越低"的错误形状**
   （实测 total_PA 在 5 百分位算出 RR = 0.70）。→ 改为以参照组为原点
   `offset = 暴露中心 − 参照中心` + `~ 0 + ...:offset` 强制过原点，RR(参照) 恒为 1。
2. metafor 的 `rma`/`rma.mv` 对象**没有 terms 分量**，`terms(fit)` 报
   `no terms component nor attribute` → 必须用建模时保存的公式（`MOD_FORMULA`）重建设计矩阵。
   预测改为**显式计算**（`X %*% coef` + `sqrt(rowSums((X %*% V) * X))`），与参数自助共用同一设计矩阵。
3. R 顶层 **`if(...) expr` 换行后再写 `else` 是语法错误**（`unexpected 'else'`）→ 必须加花括号。

> ⚠️ **做语法检查时记得先设 locale**：`Rscript -e 'parse("f.R")'` 在未设 locale 时会把
> 含中文变量名的脚本（如 `06_manifest.R` 的 `文件数`）误报为 `unexpected invalid token`。

---

## Module 2 第二轮：补齐自报组 → 方法效应可估（2026-10-12）

```
"D:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe" 05a_module2_bop.R   # 合成
"D:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe" 05b_verify_bop_table.R  # 输入表审计
```

输入表从 9 行扩到 **18 行 / 4 研究 / 2 方法**，门禁 `NOT_READY` → **`READY`**。

### 关键发现：原定的 Ekelund 2016 不能用

按上一次 README 的计划应抽 **Ekelund 2016 *Lancet*（PMID 27475271）** 作自报组，**核查后弃用**：
该文摘要报告的全部 HR 都是**久坐分层内的 PA 效应**（如久坐 <4 h/day 且最低活动四分位 HR=1.27；
久坐 >8 h/day 且最低活动四分位 HR=1.59），**没有 PA 单独分位的边际 HR**。
直接抽取会把久坐效应混进自报 PA 曲线。→ 已在 `extraction_log.csv` 留下 `REJECTED_EK16` 记录。

改用两个来源更契合、且数值完全可核实的自报研究（都是自报、都报告**边际** HR）：

| 来源 | n / 死亡 | 指标 | 概率 | 百分位口径 |
|---|---|---|---|---|
| **Moore 2012**（PLoS Med，PMID 23139642） | 654,827 / 82,465 | 休闲 MVPA（MET-h/wk，5 个非参照类别） | 5 行 | **由原文各类别人数复算**（精确、可审计） |
| **PURE 2017**（Lancet，PMID 28943267） | 130,843 / 未获 | 总体力活动（MET-min/wk，中/高） | 2 行 | 等份额假定（近似，须敏感性） |

设备侧同时补了 **Tarp 2024**（AJPM，PMID 39089430，46,682 人 / 4,666 死亡，活动量三分位），
使设备侧不止一个研究。⚠️ 但它与 Ekelund2019 同属一个研究组、队列高度重叠 → **非独立**，已升为显式 WARN。

### 一并修掉的两个**结构性错误**（不是笔误，是真错）

| # | 错误 | 为什么是错的 | 修法 |
|---|---|---|---|
| 1 | 用**全表** `median(exposure_ref_center)` 做统一锚点 | 四分位（ref=12.5）与三分位（ref=16.667）混排时会把 Ekelund 曲线整体平移 4.2 个百分位点 | 改为**逐行** `offset = exposure_center − exposure_ref_center` |
| 2 | 公式 `~ 0 + method:offset + metric:offset` | 设备侧有 LPA/MVPA、自报侧没有 → 设计矩阵**秩亏**（二分图关联矩阵秩 = 顶点 5 − 连通分量 1 = 4 < 5 参数），会产生 NA 系数 | 改用显式**组合因子** `mm = method\|metric`，`~ 0 + mm:offset` → 秩满、可预测 |

### 结果：方法效应（`Table5_bop_method_effect.csv`）

在 `offset = 60`（约为第 12.5 → 72.5 百分位）处，**device 的 RR ÷ self 的 RR**：

| 指标 | 设备斜率 | 自报斜率 | RR 比 [95%CI] | p | 解读 |
|---|---|---|---|---|---|
| **total_PA** | −0.01221 | −0.00622 | **0.698 [0.542, 0.906]** | 0.010 | **自报显著低估剂量-反应**（设备曲线更陡）|
| MVPA | −0.00430 | −0.00472 | 1.025 [0.851, 1.221] | 0.78 | 无可检出差异 |

> 上表为**贝叶斯引擎**（`brms`）的主分析结果；p 为**后验尾概率** 2·min(P(Δ>0), P(Δ<0))，
> 与 metafor 路径的 Wald p 略不同（如 total_PA：0.010 vs 0.0039），点估计则几乎逐位一致
> （0.6978 vs 0.6957；MVPA 1.0253 vs 1.0197）→ **引擎升级未改变科学结论**。

**曲率敏感性**（`Table5_bop_sensitivity_curvature.csv`）：把共享曲率项 `(offset/60)²` 加入后，
total_PA 的比值 0.698 → **0.696 [0.545, 0.897]**、MVPA 1.025 → **1.004 [0.840, 1.199]**，几乎不动
→ **方法效应结论对 L 形曲率稳健**；且曲率项确实改善了拟合：固定部分最大 \|log 残差\| 从 **0.398 降到 0.319**，
曲率项本身在 offset=60 处的 log-RR 贡献 = **0.135 [0.054, 0.214]**（换算回每百分位² = 3.8e-05，
与 metafor REML 的 3.9e-05 一致）。

> ⚠️ **该敏感性分析一度在贝叶斯引擎下失效，根因与修法务必记住**（2026-10-16）：
> 曲率列原先直接取 `offset²`（量级达 7.2e3），其系数（~4e-5）与斜率（~1e-2）相差 3 个数量级；
> 且它在**似然权重 1/vi** 下与 `self|MVPA` 斜率列近共线（**加权 r = 0.78**，未加权只有 0.31——
> 因为 Moore2012 的权重比其余行高一个数量级，且它是唯一覆盖 offset 12.5→85 的组合）。
> 两者叠加 → NUTS 在量级极端的近平脊上 1000 步 warmup 内无法适应 →
> **实测 max Rhat = 3.61（链未收敛）**、斜率后验 SD 被虚增到 REML 标准误的 30–82 倍、
> MVPA 的 RR 的 97.5% 分位被虚推到 **88674**。
> 改为标准化列 `(offset/60)²`（**纯线性重标，不改变任何似然**）后 Rhat = 1.011、0 发散、结果与 REML 吻合。
> 脚本现已**同时门禁「收敛」与「残差」**，并新增 QC 行「曲率模型后验诊断」（阈值 Rhat < 1.02）。
> **教训：共线性必须用似然权重算；未加权的 corr 会掩盖问题。**

**必须写进 Methods 的局限**（`QC_bop_status.csv` 里对应 WARN 均可追溯）：
① Ekelund2019 的观测点最大 \|log 残差\| = 0.398（RR 因子 1.49）→ 过原点直线对 **L 形**剂量-反应
存在系统性失拟（加共享曲率后降至 0.319，仍未消除）；
② `self|total_PA` 仅 2 行（PURE）→ 该斜率稳健性受限；
③ Tarp2024 与 Ekelund2019 队列重叠 → 设备侧非独立；
④ PURE 的百分位为等份额**假定**；
⑤ 池中**腕式来源仅覆盖 LPA**（total_PA / MVPA 无腕式）→ 这两个指标无法估部位效应；
用本曲线替换 NHANES 腕式曲线外推全球时，该缺口须在局限性中声明。

### 新增 `05b_verify_bop_table.R`：把"百分位怎么算的"变成可复算检查

Module 2 唯一输入把**不同来源的暴露刻度**统一到"各自分布内的百分位"——这是全池最易被质疑的一步换算。
`05b` 因此**只读**输入表并做四层检查，已挂进 `00_run_all.R`（链上第 6 步）：

| 层 | 检查 |
|---|---|
| A | 硬编码**原文印刷值**（Moore 2012 各类别人数/死亡数）重新合计，与原文报告的总数对账 |
| B | 由原文类别人数**复算百分位**，逐行比对（容差 0.02 百分点）；并校验百分位排序与原文类别边界一致 |
| **B2** | **腕式来源（A3 新增）**：Sun2025 / Cao2024 的 HR、CI、样本量、事件数**逐项对原文**；参照锚定；非单调性已登记；临床亚组已隔离；同队列非独立已登记 |
| C | 结构：必需列齐备（含 `wear_site` / `population`）、HR 落在 CI 内、**每行严格在自身参照之上**、同来源同指标无重复暴露点、近似口径已登记 |
| D | 方向：组内 HR 单调不升（**按回升幅度分级**：≤0.05 → WARN，>0.05 → FAIL）、剂量-反应为负相关 |
| E | **arm 覆盖**（按方法 × 佩戴部位分轴）：双方法可比、**髋式与腕式双覆盖**、行数充足性、临床亚组未混入主分析、设备侧研究独立性 |

当前结果 **PASS 25 / WARN 3 / FAIL 0**（3 个 WARN = Sun2025 源数据非单调 + `self|total_PA` 仅 2 行 + 设备侧研究非独立，均为有意保留的真实局限）。
报告落在 `logs/bop_table_audit.txt`，逐项状态在 `output/QC_bop_table_audit.csv`。

---

## Module 2 第三轮（A3）：补齐腕式来源 → 佩戴部位效应可估（2026-10-12）

### 为什么必须做这一步

本项目暴露来自 **NHANES 腕式**设备，而第二轮结束时池内**全部设备研究都是髋式/混合**。
后果：在 `~ 0 + arm|metric:offset` 里，`method = device` 与 `wear_site = hip` 是**完全共线**的
——「设备 vs 自报」的 RR 比里同时包含**方法差异 + 佩戴部位差异**，二者**数学上不可分离**。
用髋式曲线替换 NHANES 腕式曲线去外推全球，偏差方向与大小都无从判断。这是外推链条上**最大的未吸收偏差**。

### 两个候选的核查结论（原文已逐项核实）

| 候选 | 结论 | 处理 |
|---|---|---|
| **Sun 2025**（*J Sport Health Sci*，PMID **41201595**，DOI 10.1016/j.jshs.2025.101099） | UK Biobank **一般人群**（n=69,492，8.04 年，死亡 2,024）腕式，ML 分类 LPA **四分位**，报告 Q2/Q3/Q4 三个边际 HR | ✅ **入主分析**（3 行）。与 Ekelund2019 的 LPA 分位**结构同构** → 可直接做髋 vs 腕对比 |
| **Cao 2024**（*Eur J Prev Cardiol*，PMID **39087659**，DOI 10.1093/eurjpc/zwae248） | UK Biobank **既往 CVD 亚组**（n=8,024，6.8 年，死亡 691）腕式，**仅报最高四分位** | ⚠️ 入表但标 `population = clinical_subgroup`，**不入主分析**，仅作敏感性 |
| ⛔ Polo-López 2024（PMID 39389333，UK Biobank 76,074 人） | 用 RCS 样条报告，摘要只有 `10 min/wk` 处 HR=0.98，**无任何分位 HR** | 弃用（`REJECTED_PL24`）—— 无法换算到百分位刻度 |
| ⛔ Cao 2024 的 **MPA / VPA** | 池中**没有任何同指标对照臂** → 只能形成 1 行的孤立组合，零信息量还稀释 metric 轴 | 弃用（`REJECTED_CAO_MPA_VPA`） |

**为什么不能直接用 Cao 2024 当腕式锚点**（重要）：它的人群是既往 CVD，基线风险完全不同。
若与一般人群混入同一斜率，会把**人群差异**当作**佩戴部位差异** —— 而这两者在该文中**完全共线**
（唯一腕式亚组来源）。因此 `05a` **主分析按 `population == "general"` 过滤**，
`clinical_subgroup` 只在第二套拟合 `spec = sensitivity_all_populations` 下纳入，**两个数值都报告**。

### 结构改造

| 改造 | 内容 |
|---|---|
| 主轴 | `method`（2 水平）→ **`arm` = 方法 × 佩戴部位（4 水平）**：`self` / `device_hip` / `device_mixed` / `device_wrist` |
| 组合因子 | `mm = arm\|metric`（仍是**显式因子**，秩满、无 NA 系数；当前 7 个非空组合） |
| 拟合引擎 | 抽成 `fit_pool(dat, tag)`，对**两个数据子集**各拟合一次（主分析 / 敏感性） |
| 设备曲线 | 新增 **`device_pooled`**：跨佩戴部位按**逆方差合并**的设备曲线 → Module 3 只消费这一条（`curve_role == "device_pooled"`） |
| 对比推断 | 统一走 `contrast()`（线性组合 + `c' V c` 求 SE），方法效应与部位效应共用同一套机器 |
| 新产物 | `Table5_bop_wear_site.csv`（佩戴部位效应，含 4 个偏移点 × 2 个 spec） |

### 结果

**① 佩戴部位效应首次可估**（同一 LPA 指标、同一相对百分位；主分析 = 一般人群）：

| 偏移 | 髋式 RR ÷ 腕式 RR [95%CI] |
|---|---|
| 25 百分位点 | 0.841 [0.741, 0.945] |
| 50 | 0.707 [0.550, 0.894] |
| **60（汇报点）** | **0.660 [0.488, 0.874]，p = 0.0055** |
| 75 | 0.595 [0.407, 0.845] |

斜率：髋式 **−0.00867**/百分位点 vs 腕式 **−0.00174**/百分位点（约 5.0 倍）。

**解读**：在**相同相对百分位**上，髋式测量的 LPA 显示出**明显更强**的保护关联。
由于 NHANES 是腕式，直接套用髋式曲线会**系统性放大**剂量-反应 → 必须用腕式锚点校正。这正是 A3 要量化的量。

**② 敏感性（加入既往 CVD 亚组）**：`hip/wrist` 比值 0.660 → **0.690 [0.528, 0.907]，p = 0.0070**
—— 方向与显著性**均不变**，仅轻微向 1 收缩（CVD 亚组的腕式曲线更陡）。**部位效应结论对人群构成稳健。**

**③ 方法效应（贝叶斯引擎）**：

| 指标 | device_pooled ÷ self 的 RR（@off60） | p |
|---|---|---|
| total_PA | **0.698 [0.542, 0.906]** | 0.010 |
| MVPA | 1.025 [0.851, 1.221] | 0.78 |

`total_PA` 的 0.698 与 REML 时代的 0.696 实质相同 → 确认**换引擎没有改变既有结论**。
MVPA 由 1.066（第二轮）→ 1.020（REML）→ **1.025（贝叶斯）**，是因为新增 3 行改变了方差分量估计。

**④ 拟合诊断**：观测点最大 \|log 残差\| = **0.398**（RR 因子 1.49）；加共享曲率后降至 **0.319** → 仍为 WARN，失拟已显式量化。

### 必须写进 Methods 的局限（更新版，`QC_bop_status.csv` 可追溯）

① 过原点直线对 **L 形**剂量-反应存在系统性失拟（最大 \|log 残差\| 0.398，加曲率后 0.319 未消除）；
② `self|total_PA` 仅 2 行（PURE）→ 该斜率稳健性受限；
③ Tarp2024 与 Ekelund2019 队列高度重叠、**Sun2025 与 Cao2024 同属 UK Biobank** → 设备侧研究**非独立**；
④ PURE 的百分位为等份额**假定**；
⑤ ~~本池无任何腕式研究~~ → **已由 A3 解决**，但**部位效应只能在 `LPA` 上估**
（腕式来源尚未提供 `total_PA` / `MVPA`）→ MIMS/day 主线的部位校正仍需谨慎；
⑥ 部位对比两侧的 LPA **测量定义本身不同**（髋式 ActiGraph 计数 vs 腕式 ML 分类时长），
百分位刻度只能对齐**相对位置**、不能对齐**绝对内容**；
⑦ device_pooled 的逆方差合并把**权重视为固定**，未传播权重自身的不确定性 → SE 略偏乐观。

**下一步（见 `Module2_外部队列数据申请清单.md`）**：① 补**腕式 × `total_PA`/`MVPA`** 来源（让主线的部位校正也有腕式锚点）
→ ② 补 Asia Cohort Consortium（PMID 29490039，东亚、n=467,729）提升中国外推可信度
→ ③ PURE 等份额假定需 IPAQ 总分分布。三项**均不需审批**，ProPASS 原始数据申请转为并行增强项。


## Module 3 dry-run（2026-10-12，真实 GBD 数据）

GBD 四件套到位后（暴露包 + 批次1 Deaths/DALYs + 批次2 Deaths/DALYs），用 `95_dryrun_module3.R` 在 SD 定稿前把 PAF 链跑通了一次（产物带 `DRYRUN_S3` 标记，**不得进正文**）：

```
"D:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe" 95_dryrun_module3.R   # 约 2.5 分钟
```

**三个结论（写进方案 12.5 节）**：

| # | 结论 | 证据 |
|---|---|---|
| 1 | 机器全链路可跑通 | Global/China × 1990/2022 × CV 网格 = 20 组 PAF 全部算出，`recompute_burden()` 无报错 |
| 2 | **M1 条件均值映射把国别/年际差异抹平了**（实证） | 四个组合映射后设备均值 12,859–12,966 MIMS/day（差 <0.9%），而输入自报均值差 5%（2158–2275 MET-min/wk）→ **必须改 M2 保秩映射**，否则 Fig5 无差异可画 <br>⚠️ **2026-10-15 实测作废「改 M2 即可解决」**：M2 保秩的设备均值极差比仅 **1.040×**（M1 = 1.033×），同样救不了 —— 因为映射用的 `F_y` 是**同一套 NHANES 设备分布**。详见下文「Module 3 病因诊断」节 |
| 3 | **RR 占位（而非 SD）是 PAF 的主导项** | 重算 PAF ≈21–22% vs GBD 现报 ≈2–3%；CV 0.4→1.0 只让 PAF 从 0.212→0.220（+4%）→ Module 2（BoP 病因特异性 RR）才是关键路径 |

**GBD 侧自校验通过**：批次 1 检出的 Global 2022 LPA 归因死亡 660,032，与 GBD 已发表量级一致 → 说明分母口径、cause 匹配、单位都正确。

产物：`output/DRYRUN_module3_{totals,by_cause,exposure_diag}.csv`，运行日志 `logs/dryrun_module3.log`。


## Module 3 PAF 预览（2026-10-12，**RR 已换为真实池化曲线**）

`95_dryrun_module3.R` 已被 **`95_module3_paf.R`** 取代（旧脚本保留未删）。
RR 来源从「NHANES `all_cause` **占位**曲线」升级为 **Module 2 产出
`output/bop_rr_draws.rds` 中的 `device_pooled` × `total_PA` 后验（1000 条）**。
至此 Module 3 的**唯一假定项只剩暴露分布 CV（S1/S2/S3 未定稿）**。

```
"D:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe" 95_module3_paf.R   # 约 15 分钟
```

### 两处必须显式处理的桥接

| 步骤 | 式子 | 为什么必须做 |
|---|---|---|
| ① 尺度桥接 | `p(y)=F_px(y)`；`off(y)=max(0, 100·p(y) − 12.5)` | M2 曲线横轴是「相对各研究自身参照类的百分位偏移」，`RR(offset=0)=1` 锚在**最低四分位**（`ref_canon=12.5`）；而 M3 暴露是 MIMS/day。**用目标人群自身分布定百分位** <br>⚠️ **2026-10-15 更正**：此处原写「因此国别/年际异质性被完整保留」—— **实测不成立**。设备尺度国别均值极差比仅 1.033×（M1）/ 1.040×（M2），而 MET 尺度是 2.92×。原因是校准模型 R²=0.19、且映射共用同一 `F_y`。详见下文「Module 3 病因诊断」节 |
| ② 反事实重锚定 | `RR_abs(y) = max(1, RR_pooled(off(y)) / RR_pooled(off(TMREL)))`，≥TMREL 段封顶为 1 | PAF 定义要求 RR 相对**反事实（TMREL）** 为 1；直接代入锚在最低四分位的曲线会把 PAF 算成负值。`PA_RR_NOCLAMP=1` 关闭封顶作敏感性 |

TMREL = **13,222 MIMS/day**（GBD 2023 口径 3600–4400 MET-min/周 → 设备等效区间 13,168–13,276）。

### 结论（主情景 CV=0.6）

| # | 结论 | 证据 |
|---|---|---|
| 1 | **锚定 + 封顶逻辑验证生效** | Global 2022：`MIMS 8629/10530/12870/15064/17111/18281` → `off 0/11.85/37.70/62.08/77.36/82.28` → `RR_abs 1.671/1.445/1.053/**1.000/1.000/1.000**`（≥TMREL 段全部封顶为 1） |
| 2 | **真实池化曲线使归因负担下降约 21%**，对数差距从 7.30× 收窄到 **5.72×** | Global 2022：pooled PAF **0.1719**（3,776,382 死亡）vs NHANES 占位 **0.2193**（4,817,866）；GBD 现报 660,032（PAF 0.0300） |
| 3 | **SD 仍不是主导项** | CV 0.4 → 3,726,566；CV 1.0 → 3,876,164（**仅 +4.0%**）。fold 全谱 3.82（Brazil 2022）– 12.97（Nigeria 1990），分母越小 fold 越大 |
| 4 | 分病因产出完整（8 类） | Global 2022：IHD **1,505,627** [1,211,724–1,826,148] > Stroke 1,168,441 > Diabetes 342,005 > CKD 253,373 > Colorectal 186,611 > TB 178,439 > Breast 129,408 > PAD 12,478 |

产物：`output/PREVIEW_module3_{totals,by_cause,exposure_diag,rr_source_compare,rr_bridge}.csv`，
运行日志 `logs/module3_paf.log`。**仍属预览**——准入正文前须先定稿 SD 来源、暴露均值人口加权。

### 工程化（本轮新增）

- `95_module3_paf.R` 内**显式 `set.seed(PA_SEED + 3L)`**：原先只依赖 `00_setup` 的全局种子，
  一旦改动 `05` 的抽样次数，后验抽样序列就会漂移；钉死后本脚本自包含、可逐字节复现。
- `00_run_all.R` 的 `ALL_STEPS` 已**挂入 `95_module3_paf.R`**（位于 `05_burden_calibration_paf.R`
  与 `06_manifest.R` 之间）→ 产物自动进 `manifest.csv` 指纹清单；代价是全流程 +约 15 min。
  只跑这一段：`Rscript 00_run_all.R --only 95_module3_paf`。
- `98_verify_reproducibility.R` 的 D 层 `KEY_OUT` 已增列 5 个 `PREVIEW_module3_*.csv`。
- `06_manifest.R` 的 `rows_cols()` 加 **`fill = TRUE`** —— 修 `data/gbd/TABLE_INDEX_extracted.csv`
  （含空字段行）导致 `fread`「第 43 行提前停止」的**静默行数错误 + 干扰性 warning**。

**可复现性已硬验证**：`95_module3_paf.R` 独立复跑第二遍（12 min 40 s），
5 个 `PREVIEW_module3_*.csv` 的 md5 **全部逐字节一致**；`98_verify_reproducibility.R`
总体结论 **PASS 63 / WARN 0 / FAIL 0**，E 层跨运行 **132 个文件指纹一致、0 漂移**。

### ⚠️ 反复踩到的 R 陷阱

- **`pmax(1, 矩阵)` 会丢掉 `dim` 属性** → 下游 `colMeans()` 报
  `'x' must be an array of at least two dimensions`。**统一改用就地索引赋值 `x[x < 1] <- 1`**。
- ⚠️ **PAF 是非线性函数：`E[PAF(rr)] ≠ PAF(E[rr])`（Jensen 不等式，2026-10-15 实测）**。
  Global 2022 同一后验池下：**逐曲线算 PAF 再平均 = 0.174079**，而
  **先对曲线求平均再算 PAF = 0.174495**，相差 **0.24%**。
  `recompute_burden()`（`05`）走 `E[PAF]`，是统计上正确的口径；任何诊断列
  （`implied_paf_pooled`）、影子脚本（`97` 的 `mk_rr_shadow`）都必须同口径，
  **否则 Table 4 与 Table 9 会出现 0.24% 的假差异，且极易被误判成 Monte Carlo 噪声**。
  同理：后验幅度缩放必须作用于**整条曲线集**，不能只缩放均值曲线。
- ⚠️ **「后验均值」只能靠枚举，不能靠抽样**（2026-10-15）。旧写法
  `D[sample.int(nrow(D), 1L), ]` 每抽一条算一次再取均值，是 MC 近似：400 draws 的
  标准误 0.535%，`95`/`95c`/`95b`/`97` 四处产物最大相差 1.55%。
  现行写法：`make_rr_fun_pooled()` 返回 **n_curve × n_off 矩阵**（首次调用建缓存），
  `recompute_burden()` 用 `paf_from_dist_mat()` 一次矩阵乘法算完全部曲线 →
  **确定性、方差 0、跨脚本严格一致**，且比原来快 1–2 个数量级
  （`95` 15 min → 32 s，`95c` 17 min → 1.1 min）。
- ⚠️ **`fread(fill = TRUE)` 不带 `sep` 会静默选错分隔符（2026-10-15 实测，此前理解有误）**：
  不是「`fill=FALSE` 才提前停止」。真实机制是 —— 一旦给了 `fill = TRUE`，分隔符自动探测会退化：
  当**表头字段名含空格**时（如 GBD 的 `Location ID,Location Name,2023 SDI Index Value,SDI Quintile`），
  探测会把 `" "` 选作分隔符 → 列数错（7 而正确 4）、读到中途「Stopped early」、行数静默错误（220 而正确 934）。
  最小复现：表头含空格 + 400 行 → `fill=TRUE` 得 7 列，不给 `fill` 得 4 列。
  **规则：凡用 `fill = TRUE`，必须同时显式给 `sep`**（`06_manifest.R` 的 `rows_cols()`、
  `05c` 的台账读取、`05d` 的待命表读取均已补齐）。
  受影响文件：`data/gbd/SDI/IHME_GBD_2023_SDI_1950_2023_SDI_QUINTILES_*.csv`
  （该文件还叠加了 **Latin-1 编码**，见 `96b_sdi_anchor.R` 头部说明）。
- `fread` 遇到空字段行会**提前停止且只给 warning**，行数静默错误 —— 需要容错时用 `fill = TRUE` **并显式给 `sep`**。
- R 顶层 `if(...) expr` 换行后再写 `else` 是语法错误（`unexpected 'else'`），须加花括号或写成单行。



`PAXMIN_G/H`（分钟级）约 8,800 万行，直接 `read_xpt` 会占用 >8 GB。主分析只用 `PAXDAY`（日级）即可完成 `MIMS/day` 暴露；仅当需要 `MVPA 分钟` 或 `Peak-30` 时才用分钟文件，建议走 PhysioNet 预处理宽表或 `02` 中的分块函数。

## S1 核查：GBD 2023 Capstone Appendix 2（2026-10-12）

**背景**：`EXPO_CV <- NA_real_` 是 Module 3 唯一剩余的阻塞项 —— GBD 暴露文件只有 `mean/lower/upper`，**没有 SD**，而 PAF 公式需要它。

**核查**：把 Lancet GBD 2023 Capstone 的 **Supplementary appendix 2**（**488 页**）逐页核查。
完整报告 → `data/gbd/capstone/S1_核查报告.md`；逐页证据 → `data/gbd/capstone/LPA_section_p374-381.txt`。

### 结论：S1 **部分成立 —— 附录给方法、不给数值**

| 问题 | 结论 |
| --- | --- |
| 附录是否**描述** LPA 暴露 SD 的估计方法 | ✅ **是**（`ln(SD) = β₀ + β₁·ln(MEAN) + β₂·Age + β₃·SR + β₄·Fem`，在全国代表性 IPAQ 调查上拟合后外推） |
| 附录是否给回归**系数** β₀–β₄ | ❌ **无** |
| 附录是否给 per-location×year×age×sex 的 **SD 数值表** | ❌ **无** |
| 能否据此**直接复算** GBD 的精确 SD | ❌ **不能** |

### 三条真正产出

1. ⭐ **SD–mean 关系的函数形式** → 据此提出 **S1′ 方案**：照 GBD 公布的形式，在 **NHANES 数据（`output/analytic.rds`）** 上自行拟合
   `ln(SD) = β₀ + β₁·ln(MIMS_mean) + β₂·Age + β₃·Region + β₄·Female`
   → 把 SD 从「假定 `CV_MAIN = 0.60`」升级为「**GBD 方法 + 本土估计**」，同时保留 CV 网格做敏感性。
   **这是 Module 3 最后一个待补环节**，实现位置 `05_burden_calibration_paf.R`（新增 `fit_sd_mean_relation()`）。
2. ⭐⭐ **GBD 官方认定「加速度计 = 参考标准」**（p.378 Table 3，MR-BRT crosswalk）：
   Accelerometer = **Ref** ／ Self-reported GPAQ-IPAQ = **Alt**，log β = **−0.721**，**校正因子 2.075**
   → **为本文「用 NHANES 加速度计重算 GBD 归因负担」的核心卖点提供 GBD 官方背书**，可直接写进 Introduction / Discussion。
3. 自报↔客观的官方校正因子 **2.075**，可与 Module 1 自建校准互证。

**同源证据**：p.368（Low BMD 章节）连续型暴露用 **minimum coefficient of variation**（global 0.1 / super-region 0.06 / region 0.08）
→ 二者印证：**GBD 的暴露离散度是"建模/约束"出来的，不公开发布**（这正是 GHDx 暴露表没有 SD 列的原因）。

### 获取路径（踩坑记录，可复现）

| 途径 | 结果 |
| --- | --- |
| `arts.units.it` 直链、`thelancet.com` 附件、`europepmc.org/articles/.../bin/mmc2.pdf` | ❌ 全部 **Cloudflare "Just a moment" 挑战 → 403** |
| `pmc.ncbi.nlm.nih.gov` | ❌ 本出口 SSL 000 / 不可达 |
| ✅ **Europe PMC 补充材料 API** | `https://www.ebi.ac.uk/europepmc/webservices/rest/PMC12535840/supplementaryFiles` |

⚠️ 该 API **不支持 HTTP Range**（返回整文件），只能整包下载（126,379,080 bytes ≈ 120.5 MiB：`mmc1.pdf` 82.9 MB + **`mmc2.pdf` 31.9 MB** + `mmc3.pdf` 13.5 MB + `mmc4.pdf` 0.9 MB）。
✅ **变通**：zip 为**流式 deflate + data descriptor**（local header 里 `csize=0`），用 `zlib.decompressobj(-15)` **手动解 local header**，
即可从**部分下载的前段**直接解出 `mmc2.pdf` 的前 19 MB 解压内容 —— **已完整覆盖 LPA 章节 p.374–381**。
解析用 `pymupdf`（截断版补 `%%EOF` 后可读 487 页；**完整版 488 页直接可读**），装于 `~/.workbuddy/binaries/python/envs/default`。完整版已归档为 `data/gbd/capstone/GBD2023Capstone_Appendix2_risk_factor_methods.pdf`（31.9 MB，md5 `32bb4fc0beaa803005eced630d20bc0a`）。

---

## D2 落地：PAF 分母换 25+ 年龄口径（2026-10-14）

**要解决的问题**：LPA 的暴露定义只覆盖 **25 岁以上**（Capstone appendix 2, p.375），
但 PAF 的**分母**（批次 2 cause 总负担）当时是 `All ages` —— 含 0–24 岁、而 0–24 岁**不产生任何归因**
→ **PAF 被系统性低估**。D2 决策（用户选**方案 B**）＝ 补拉 25+ 年龄分组做分母，使**分子分母同口径**。

### 新数据（`data/gbd/`）

| 目录 | measure | 行数 | 判定 |
| --- | --- | --- | --- |
| `IHME-GBD_2023_DATA-e203c19c-1` | DALYs | 49,200 | 8×205×1×15×2×1 维度乘积自洽 ✅ |
| `IHME-GBD_2023_DATA-a12a894a-1` | Deaths | **47,970** | 缺 1,230 行，见下 |

**1,230 行缺口 = 工具省略零值行（无偏，非下载错误）**：缺口**全部**是
`Lower extremity peripheral arterial disease` 的 **25-29 / 30-34 / 35-39 × 2 年 × 205 国**
（PAD 在 <40 岁既无 YLL 也无 YLD，Deaths 与 DALYs 同为 0）。证据：
① 1,230 个缺失键中 `DALYs ≠ 0` 的个数 = **0**；② Global 2022 PAD `40-44 = 346.49`、`50-54 = 1,176.46`（一旦 >0 必出现）；
③ 缺口是整齐的 cause×age 方块，非文件尾部截断。
**总量对账**：205 国 × 2 年 × 8 cause 逐格检查「Σ25+ ≤ All ages」→ **0 例违例**；差额 = 0–24 岁负担。

### 三层防护（本轮新增）

| 层 | 位置 | 内容 |
| --- | --- | --- |
| **数据层** | `05` / `96` | 新增 `gbd_not_archived()` / 归档目录排除：路径任一层目录名以 `_archive` 开头即忽略。旧版 `All ages` 分母已移入 **`data/gbd/_archive_AllAges/`** |
| **核验层** | `96` 的 `audit_shards()` | ① `zero_omission_verdict()`：缺口格若在同角色参照文件中**全为 0** → 判「零值省略、按 0 无偏」而非 FAIL；② 新增**年龄口径混用**硬检查：同角色内同时见 `All ages` 与五岁组 → `❌`；批次 2 仅 `All ages` → `⚠️ D2 未完成`；为 25+ 五岁组 → `✅` |
| **计算层** | `95` 的 `build_wide()` | `dcast` 之前先按 `cause_name × meas` **对年龄组求和**（旧版不聚合 → 同键 15 行重复 → `dcast` 静默退化为计数）；并新增 `assert_denominator_age()`：分母一旦含 `All ages`/`Age-standardized` 立即 `stop()` |

> ⚠️ **踩过的坑**：`96` 原「分片互斥检查」对新旧分母并存报 **`✅ 未检出重复键` —— 假通过**。
> 因为 `All ages` 与 `25-29 years` 的 `age_name` 不同，键天然不重叠，普通重叠检测**看不见这个冲突**。
> 这正是「检测通过 ≠ 正确」的典型 —— 必须补「年龄口径混用」这一维度的显式检查。
>
> ⚠️ 另一个坑：`build_wide()` 的 `dcast` 在**同键多行**且未给 `fun.aggregate` 时**只发 warning、不报错**，
> 会把数值列悄悄换成**计数**。属于最危险的一类静默错误。

### 复现验证

```bash
PA_GBD_PLAN_MODE=audit "D:/Program Files/R/R-4.5.2/bin/Rscript.exe" code/96_gbd_download_plan.R
"D:/Program Files/R/R-4.5.2/bin/Rscript.exe" code/00_run_all.R --only 95_module3_paf
```

- `96` audit 报告落盘 `logs/GBD_download_audit.txt`（批次 2 剩 2 个文件；判为 25+ 五岁组口径）。
- 逐项核验报告见 **`data/gbd/B1_核验报告.md`**；手工下载走查见 **`data/gbd/B1_25plus_分母_下载操作步骤.md`**。

### 分母修复前后对照（Global 1990）

| 项 | 修复前（`All ages`） | 修复后（`Σ 25+`） |
| --- | --- | --- |
| `total_deaths` | 15,265,380 | **14,740,226** |
| `total_dalys` | 428,316,413 | **382,791,884** |
| PAF | 偏小 | 正确 |

### 附带：`05` 的 `find_gbd` / `find_gbd_role` 也加了归档排除

两个函数都是 `recursive = TRUE` 扫描 `data/gbd/` → 若不排除，归档文件仍会被识别为批次 2。
新增共享 helper `gbd_not_archived()`，两处统一调用。

---

## S1′ 落地 + 暴露均值人口加权（2026-10-14）

D2 换掉 PAF 分母后，Module 3 只剩两个未闭合环节：**（决策①）暴露分布的 SD**、
**（建议直接做）暴露均值的 25+ 人口加权**。本轮一起落地，完整证据见
**`logs/module3_s1p_verification.txt`**。

> ⚠️ **先记住这条硬约束**：`exposure_dist(mean_met, cv)` 的 `cv` 作用在 **MET 尺度**
> （第一步先建 MET 对数正态，再经 `pred_mims` + 残差核映射到设备尺度）。
> 所以 s1p 主轨**必须**用 `SD_FIT$met_w`；`device_*` 只能作独立交叉校验。
> 把 device 的 CV 喂进去是**量纲错配**，不报错但结果全错。

### 1. S1′：`fit_sd_mean_relation()`（`05` Part A5）

形式照抄 GBD 2023 Capstone appendix 2 **p.378**（`ln(SD) = β₀ + β₁·ln(MEAN) + β₂·Age + β₃·SR + β₄·Fem`），
数据换成 **NHANES 25+ 加速度计个体数据**，按 cell（5 岁组 × 性别）拟合：

| 模型 | CV 范围 | R² | cell 数 |
| --- | --- | --- | --- |
| **MET · 加权（主轨）** | **1.312 – 2.228** | 0.966 | 24 |
| MET · 未加权 | 1.276 – 2.202 | 0.963 | 24 |
| 设备 · 加权 | 0.231 – 0.270 | 0.797 | 24 |
| 设备 · 未加权 | 0.231 – 0.275 | 0.879 | 24 |

产物 `output/Table3_sd_mean_relation_{coefs,cells}.csv` + `Table3_sd_mean_age_map.csv`
（GBD 的 85+ 组**刻意截断**到 NHANES 上限组 80+，避免把年龄效应线性外推 3 个五岁组；映射显式落盘以便审稿复核）。

### 2. 暴露均值人口加权（`05` Part A6）

GBD 暴露文件给出 15 个 25+ 年龄组 × 2 性别的 cell 均值，**没有 population 列** → 合并必须按人口占比加权。
数据源优先级：`data/gbd/population_25plus/`（GBD Population）→ `data/external/owid_pop5.csv`
（UN WPP 2024，已落盘）→ 皆无则均匀权重 + WARN。

**为什么简单平均有偏**：15 个五岁组各占 1/15，但 80+ 就占了 **4 组（=27% 权重）**，
而该年龄段实际人口占比通常 <5%，且 80+ 暴露最低 → 简单平均**系统性低估**。

| location | 2022 简单平均 | 2022 人口加权 | 差 |
| --- | --- | --- | --- |
| Global | 2,190 | **2,795** | +27.6% |
| India | 2,823 | **4,122** | +46.0% |
| China | 2,158 | **2,632** | +22.0% |
| Japan | 1,388 | **1,413** | +1.8% |

### 3. 运行方式（双轨；**全链已自足**）

```bash
# 直接全链运行 —— 95 会自动按 [grid → s1p] 各跑一次，两条轨产物均刷新
Rscript code/00_run_all.R

# 只重跑 Module 3 预览（两条轨各自单独触发；--only 选中同一脚本的全部轮次）
PA_CV_MODE=s1p Rscript code/00_run_all.R --only 95_module3_paf
Rscript code/00_run_all.R --only 95_module3_paf
```

产物 `PREVIEW_module3_s1p_*.csv`（主分析 A 档，5 个）vs `PREVIEW_module3_*.csv`（grid 敏感性，5 个）。

> ⚠️ **2026-10-16 修的缺口（重要，勿回退）**
>
> **修前**：直接 `Rscript code/00_run_all.R` 全链运行时，95 只跑**默认的 grid** 轨
> → 主分析 A 档 `PREVIEW_module3_s1p_*.csv` **不刷新**，退化为陈旧孤儿文件；
> 而下游 `07` / `08e` / `09` / `10` / `95b` 读的**正是** A 档（`95b` 第 100 行还对其存在做硬断言）
> → **Fig 5 / Table 4 / Table 7 / 图注会引用未参与本次运行的数据**。
>
> **为何隐蔽**：只有当 Module 2 的 BoP 后验变化时才会暴露 —— 表现为图注末尾
> 「口径一致性自检」由 `0.00%` 跳到 `0.07%`（跨轨假差异），而非报错。
> 实测触发场景即 2026-10-16 的贝叶斯引擎升级。
>
> **修法**：`00_run_all.R` 新增 `STEP_PLAN`，让 95 在同一处按 **grid → s1p** 各跑一次
> （产物文件名互不覆盖，grid 轨仍保留为敏感性双轨）；同一处对 `95b` 传 `--force`，
> 强制重算其 B 档 `PREVIEW_NHANES_s1p_*`（原先默认「有则复用」，同样会陈旧）。
>
> **根因**：2026-10-15 那次修正只把**消费方**（`95b` 的 `P_A`）从 grid 改到 s1p，**漏了生产方**。
> 教训：**改口径时必须同时改生产端与消费端**，否则一致性自检只会在换引擎这类"外部扰动"下才暴露。
>
> ⚠️ **2026-10-16 追加修的第二个隐患（同一处代码）**
>
> 上面这个 `STEP_PLAN` 执行器第一版自身有 bug，**已在 RUN `20261016_151920` 上暴露**：
> 它在 95 的**网格轮跑完（产物已落盘）后**崩溃 —— `Error in ev_old[[k]] : subscript out of bounds`，
> 于是 **s1p 主分析轮根本没开始**，问题原样存在（只是"看起来跑过了"）。
>
> 成因：`Sys.getenv()` 缺省 `names = NA` 下**只在长度 > 1 时**给返回值加名字，
> 单个变量（如 `PA_CV_MODE`）返回的是**无名**向量 → 按名字取 `ev_old[[k]]` 越界。
>
> ```r
> # 错：单变量无名 → 越界
> for (k in ev_names) if (is.na(ev_old[[k]])) Sys.unsetenv(k) else ...
> # 对：一律按位置索引
> for (i in seq_along(ev_names)) {
>   if (is.na(ev_old[i])) Sys.unsetenv(ev_names[i])
>   else do.call(Sys.setenv, setNames(list(ev_old[i]), ev_names[i]))
> }
> ```
>
> 已用 `code/tools/_test_env_restore.R` 四场景（未设置 / 已有值 / 双变量 / 两轮互不串味）实测正确；
> 修复后 RUN `20261016_154842` 的 95 已正常打印 `[s1p]` 轮头。
> **教训**：给编排器加"按轮次改环境变量"的能力时，还原逻辑要自己实测边界（长度 0 / 1 / 一有一无），
> 别凭直觉写 —— 写错时链条只是**静默少跑一轮**，不报错。

> ⚠️ **2026-10-16 修的第三、四个隐患：核验脚本 `98` 自身的可审计性缺陷**
>
> **B6 — E 层「跨运行复现判定」可自指（假绿）**：`06_manifest.R` 会把 `output/manifest.csv`
> **原样拷进** `logs/<RUN_ID>/manifest.csv`。所以凡**未包含 06 的运行**（如
> `Rscript 00_run_all.R --only 98_verify_reproducibility` 单跑核验），`output/manifest.csv`
> 没被重算 → 与"最近一次历史 manifest"（上一次 run 结束时那份同一拷贝）**逐字节相同** →
> 报出 **313 一致 / 0 不一致的假绿 PASS**，把真实的 15 项差异**全部掩盖**。
> **修法**：E 层加自指防护 `MF_REGENERATED <- file.exists(file.path(PA_RUN_DIR, "step_06_manifest.log"))`，
> **只有本次确实重算过清单才做跨运行判定**；否则报 INFO 并说明跳过原因。
> — 它给的**不是报错而是满分**，比 FAIL 难发现得多。
>
> **B7 — 差异展示硬上限 10 项（漏报）**：实测有 15 项未豁免差异，报告只列了 10 项。
> **修法**：上限提到 40，超出时显式加"共 N 项不一致，上方仅列前 40 项"。
>
> **附带**：`manifest.csv` 的 `content_hash` **只对 RDS 类产物计算**，CSV/PDF/.md 为空串 ——
> 写"内容是否一致"的判据**必须加 `nzchar()`**，否则空串相等会被误判为"内容一致"
> （自查脚本 `code/tools/_diff_runs2.R` 踩过一次：32 项真实差异被全判成"仅元数据变"）。

### 4. 主结果对照（`rr_source = pooled`）

| location | 年 | MET(grid) | MET(s1p) | PAF(grid) | PAF(s1p) | fold(grid) | fold(s1p) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Global | 1990 | 2,220 | 2,942 | 0.1704 | 0.1720 | 6.93 | 7.00 |
| Global | 2022 | 2,190 | 2,795 | 0.1719 | 0.1734 | 5.65 | 5.70 |
| China | 2022 | 2,158 | 2,632 | 0.1729 | 0.1748 | 6.32 | 6.39 |
| Japan | 2022 | 1,388 | 1,413 | 0.1847 | **0.1917** | 5.06 | 5.25 |
| United States of America | 2022 | 1,997 | 2,371 | 0.1731 | 0.1797 | 5.65 | 5.86 |
| India | 2022 | 2,823 | 4,122 | 0.1641 | **0.1615** | 4.89 | 4.81 |
| Nigeria | 2022 | 2,279 | 2,799 | 0.1701 | 0.1743 | 8.36 | 8.56 |
| Brazil | 2022 | 1,489 | 1,914 | 0.1828 | 0.1840 | 3.80 | 3.83 |
| Germany | 2022 | 1,959 | 2,181 | 0.1759 | 0.1832 | 5.67 | 5.91 |

（`fold` = 本研究重算归因死亡 / GBD 现报归因死亡）

### 5. ⭐ 本轮最重要的发现：PAF 对暴露参数几乎不敏感

grid 口径 CV 扫描（Global 2022, pooled）：CV 0.40 → 3,680,892；0.50 → 3,690,186；
0.60 → 3,730,098；0.80 → 3,770,113；**1.00 → 3,828,656**。
**CV 翻 2.5 倍，结果只动 +4.0%**；s1p（MET 尺度 `cv_wavg ≈ 1.61`）给 3,762,012，正落在这条带内。

**原因**：设备尺度分布被**校准残差核** `SIGMA_MIMS = 3335` MIMS/day 主导
（校准 R² 仅 0.19 → 自报 MET 对设备 MIMS 解释力很弱）。

**推论（很重要）**：`fold ≈ 4–12` 的系统性差异**不来自** SD/CV 的选择，也**不来自**人口加权
—— 换 S1′ 不会改变这个量级。要解释 fold，须从 ① RR 曲线陡度、② 落在 TMREL 以下的质量
与 GBD 口径的差异 入手。（见文末「遗留」）

### 6. 内一致性硬证据

| 路径 | 得到 |
| --- | --- |
| A：S1′ **设备尺度**拟合（直接估 cell 内 MIMS 的 SD/mean） | CV 0.231 – 0.270 |
| B：s1p 主轨输出的 `cv_eff_dev`（合并后设备分布 SD/mean） | CV 0.259 – 0.265 |

两条独立路径几乎重合 → 「MET 分布 → 校准映射 → 设备尺度」这一链条自洽。

### 7. 本轮修掉的三个真 bug（都会静默出错）

| # | 症状 | 根因 |
| --- | --- | --- |
| **B1** | **人口权重被彻底抹掉**，`w_cell` 恒等于 1/30 → 静默退化为均匀权重 | 两次归一化互相抵消：先 `w_age/sum(w_age) by age_group_id`（把组内两性别压成 0.5），再全局 `/sum(w_age)`（按「年龄组个数 15」除） |
| **B2** | `POP_SRC` 显示 `none`，人工核对会误判为「权重未生效」 | `data.table` 的 `[` **会丢弃 attributes** —— `attr(lng,"src") <- ...` 后 `return(lng[, .(...)])` 属性全丢 |
| **B3** | GBD 含非 ASCII 的国名（`Türkiye` / `Côte d'Ivoire`）在 locale 下匹配不上人口表 | `pop_norm_loc()` 加 `iconv(ASCII//TRANSLIT)` 折叠变音符号；`POP_LOC_ALIAS` 改为按**归一化键**索引 |

### 8. 复现验证

| 步骤 | 结果 |
| --- | --- |
| 95 主链 s1p（`20261014_212358`） | ✅ EXIT=0 / 229.3 s |
| 95 主链 s1p 独立复跑（`20261014_212909`） | ✅ EXIT=0 / 2.3 min |
| **逐字节比对 `PREVIEW_module3_s1p_*.csv`** | ✅ **5/5 一致** |
| `06_manifest` | ✅ 248 行，s1p 产物 + `Table3_sd_mean_*` 已登记 SHA-256 |
| `98_verify_reproducibility` | ✅ **PASS 133 / WARN 0 / FAIL 0** |
| grid 冻结产物是否被触碰 | ✅ 未触碰（前缀不同） |

### 遗留 —— 均已于 2026-10-15 结清（见下节「Module 3 情景表」）

- ~~**L1**：`fold ≈ 4–12` 的科学解释（见第 5 节）—— 当前最大的科学问题。~~
  → **已结清**：主导项 = RR 曲线超额幅度（L3 单独 −89%）；口径对齐后 fold **0.994** 完全闭合。
- ~~**L2**：`M1`（条件均值映射）把国别差异压平：MET 均值差 2.03× → 设备均值差仅 **2.2%**；~~
- ~~README 早前记「M2 保秩映射 = 主分析」，但 **M2 尚未实现**（本轮未动）。~~
  → **已结清**：M2 已实现且**未能**保留国别差异（设备极差 M1 1.033× vs M2 1.040×）；
  人口加权后 MET 尺度差为 **2.92×**、设备尺度只剩 **3.3%**。**该卖点已按 N2 决策放弃**，
  改用「PAF 对暴露参数高度稳健」+「设备尺度国别同质化」两条正面结论。
  ⚠️ 国别**排序**保留的说法同样已失效（`L1a_p70`/`L1b_p85` 的 fold 在 8 地区**完全相同**，
  说明「相对百分位」口径下 PAF 与地区无关是数学必然）。

---

## 路径 2：佩戴部位效应的本土自估 + 受控回灌敏感性（2026-10-12）

**要回答的问题**（审稿人必问）：本研究的暴露侧是**腕式**设备（MIMS/day），而 Module 2 池里
总量曲线的设备来源**几乎全是髋式/混合**。「腕式曲线能不能用髋式曲线替代？」这个假设若不检验，
整个 M1→M2→M3 链条的地基就是悬空的。

**做法**：用**同一个国家、同一调查体系、同一套协变量定义**的两套实测数据各估一条曲线，
再放到**同一个「人群加权百分位」轴**上比较。不比较暴露绝对值（`counts/min` 与 `MIMS` 量纲
不可通约），只比较「相同百分位处的 RR」。

| 环节 | 脚本 | 关键口径 |
|---|---|---|
| 取数 | `01b_fetch_pam_2003_2006.R` | 2 个 PAM ZIP（898 MB）+ 10 个 `rnhanesdata` rda；逐文件精确 `expect` 字节 + SHA-256 |
| **核验** | `01c_verify_paxinten_vs_raw.R` | 参考宽表 vs **原始 xpt 全文件逐人**比对（非抽样） |
| 暴露 | `03b_pam_exposure_2003_2006.R` | `counts_per_day` = 有效日「佩戴分钟内 counts 之和」的均值（**体量型**，不用 TAC）；有效日 = 佩戴 ≥ 600 min，且 ≥ 4 日 |
| 曲线 | `04b_pam_site_rr.R` | 两侧同用 `age, female, race(5类), educ, pir, bmi, sbp, cur_smoke, drink_any, diabetes, cvd_hx`；`RIDRETH3` **折叠为 5 类**与 `RIDRETH1` 对齐；参照 = 各自人群加权 **12.5 百分位** |
| 回灌 | `05c_module2_nhanes_site_sensitivity.R` | 三档对照 A/B/C；**不改主池** |

### 核验闭环：参考宽表 = 原始 xpt（全文件，逐人）

`PAXINTEN_C/D` + `Flags_C/D` 是**外部衍生数据**，而 M1/M2 的设备侧暴露都靠它。
`01c` 把这条链补成可核验的：两侧都**先按 SEQN 汇总全部日行**再比。

| 周期 | 受试者 | 逐人一致 | 原始非 NA 分钟 | 宽表非 NA 分钟 | 计数总和（原始 vs 宽表） |
|---|---|---|---|---|---|
| 2003–2004 (C) | 7,176 | **7,176 / 7,176** | 72,250,027 | 72,250,027 | 16,052,577,596 **=** 16,052,577,596 |
| 2005–2006 (D) | 7,455 | **7,455 / 7,455** | 74,874,095 | 74,874,095 | 24,520,528,153 **=** 24,520,528,153 |

> ⚠️ **踩过的坑（核验脚本自身 bug）**：`PAXINTEN_*` / `Flags_*` 是**受试者-日**表
> （同一 SEQN 占 **7 行** × 1440 列），原始 xpt 是每人最多 10080 行（7 天 × 1440 分钟）。
> 首次运行按 `merge(by="SEQN")` 关联 → 只命中第 1 天（1440 分钟）→ 误报「0/52185 一致」。
> 实际把 7 行加总后与原始值**逐值相等**。**结论：两侧都必须先按 SEQN 汇总再比。**

### 结果一：部位效应在总量轴上**不可检出**

`04b` 在百分位轴上拟合两条曲线（髋式 5,334 人 / 1,351 死亡；腕式 7,007 人 / 664 死亡）：

| 百分位 | offset | RR 髋式 | RR 腕式 | 腕式/髋式 | 95% CI |
|---|---|---|---|---|---|
| 12.5（参照） | 0 | 1.000 | 1.000 | — | — |
| 22.5 | 10 | 0.768 | 0.848 | 1.103 | 1.022–1.192 |
| 32.5 | 20 | 0.668 | 0.733 | 1.096 | 0.949–1.275 |
| 42.5 | 30 | 0.628 | 0.664 | 1.056 | 0.871–1.279 |
| 52.5 | 40 | 0.599 | 0.614 | 1.025 | 0.825–1.265 |
| 62.5 | 50 | 0.585 | 0.584 | 1.001 | 0.763–1.263 |
| 72.5 | 60 | 0.574 | 0.566 | 0.994 | 0.681–1.449 |
| 82.5 | 70 | 0.555 | 0.556 | 1.014 | 0.599–1.753 |
| 92.5 | 80 | 0.509 | 0.549 | 1.099 | 0.565–2.145 |

**9 个点里 8 个的 CI 含 1**（仅 22.5 百分位下界 1.022 略高于 1）。
→ 部位效应**在本调查体系内不可检出**，即「髋式曲线可用于腕式暴露侧」这一假设有实证支持。
这正是对审稿人质疑的直接答复。不确定性用**两周期独立样本**的系数抽样（各 1000 组 `N(beta, V)`）
算 `log(RR_wrist) − log(RR_hip)` 的抽样分布得到。

### 结果二：门控式回灌 —— 三档对照

**裁定：NHANES 两臂不进主分析池。** 三条理由（须写进 Methods）：

1. **定位冲突**：Module 2 立论是「池化**外部**文献队列以支持全球外推」，注入自算分析会使其部分自我循环。
2. **设计不可通约**：NHANES 单次 7 天基线测量、随访中位 **14.3 年**；池内 Ekelund2019 为 5.8 年、UKB 系 8 年。
   随访越长 → 回归稀释 + 反向因果越重 → 向 1 衰减。NHANES 曲线整体更平（`off80`：RR 0.509 vs 池化 0.373）正是该机制产物。
3. **权重压倒**：NHANES 每点 log-SE ≈ 0.028，EK19 约 0.058 → 固定效应权重约 **4 倍**
   （实测在 `device_hip` 臂占 **83%**、`device_wrist` 臂占 **100%**）。

| 档 | 池内容 | 行数/研究 | total_PA 的髋÷腕比值 @off60 | 95% CI | p |
|---|---|---|---|---|---|
| **A** | 仅外部文献（= 复现 05a 主分析） | 21 / 5 | 不可估（无腕式 total_PA 来源） | — | — |
| **B** | 文献 + NHANES 两臂 | 37 / 7 | **0.978** | 0.795–1.203 | **0.835** |
| **C** | 仅 NHANES 两臂 | 16 / 2 | 1.143 | 0.916–1.426 | 0.237 |

- **A 档复现 05a 达机器精度**：`device_pooled × total_PA` 最大绝对偏差 **4.441e-16** → 对照基准成立。
- 文献侧唯一可估的部位效应（LPA，A 档）为 **0.660 [0.488, 0.874], p=0.0055** —— **方向与 NHANES 相反**（文献说髋式更陡）。
  并入 NHANES 后 LPA 该比值变为 0.791 [0.605, 1.033], p=0.085。
- **并入 NHANES 会使池化曲线整体变平**：`device_pooled × total_PA` 在 `off80` 由 RR **0.3732 → 0.4831**（比值 1.294），
  `off60` 由 0.4775 → 0.5795（比值 1.214）。

### 影响力敏感性：把 B 档曲线灌回 Module 3

`95_module3_paf.R` 新增三个**环境变量覆盖**（**默认值 = 原硬编码值，不设变量时行为逐字节不变**）：

| 变量 | 默认 | 用途 |
|---|---|---|
| `PA_RR_DRAWS` | `output/bop_rr_draws.rds` | 换 RR 后验来源（如 `bop_rr_draws_withNHANES.rds`） |
| `PA_PREVIEW_TAG` | `PREVIEW_RealRR_S3SD` | 产物内 tag 字段 |
| `PA_OUT_PREFIX` | `PREVIEW_module3_` | 产物**文件名前缀** → 敏感性运行不覆盖 ② 的冻结产物 |

**默认行为不变性已硬验证**（这是新增覆盖机制的前提）：
以默认参数、仅换输出前缀再跑一遍 95 → 5 个产物的 md5 与 ② 的冻结件**全部 IDENTICAL**。
证据落盘 `output/QC_95_env_override_invariance.csv`（5 行，`identical = IDENTICAL`）。

```bash
# 一键完成：B 档 PAF + 行为不变性证据 + A/B 对照表
cd code
Rscript 95b_paf_impact_compare.R                    # 复用已有 B 档（无则自动生成 B，约 12 min）
Rscript 95b_paf_impact_compare.R --force            # 强制重算 B 档
PA_VERIFY_DEFAULT=1 Rscript 95b_paf_impact_compare.R  # 额外重跑默认轮做不变性再验证（+约 12 min）
```

`95b` **已挂进 `00_run_all.R` 的 `ALL_STEPS`**（2026-10-15 入链：其产物 `Table7_*` 被 `10` 直接引用，
留在链外会与主链不同步）。链中对其传 **`--force`**（2026-10-16 补），强制重算 B 档
`PREVIEW_NHANES_s1p_*` —— 原先默认「有则复用」，会让 B 档在 BoP 后验变化后陈旧（同 §3 的双轨缺口）。
`98` 里其产物被列为 `D 交付产出（按需敏感性）` —— **存在则 PASS，不存在则 INFO**，
因此"只跑主链"的全新克隆**不会**因缺这些文件而 FAIL。

### 结论：影响力敏感性（Global 2022，`rr_source = pooled`）

| 档 | PAF | 归因死亡 | 相对 GBD 现报（660,032） |
|---|---|---|---|
| **A** 文献池（主结果） | 0.1719 | 3,776,382 | **5.72×** |
| **B** 文献池 + NHANES | **0.1269** | **2,787,331** | **4.22×** |

**并入 NHANES 使 PAF 统一下降约 26%，但结论不变——最保守的池下仍是 GBD 现报值的 4.2 倍。**
该下降在全部 8 国 × 2 年上高度一致（−25.8% ~ −27.2%，中位 −26.2%），
因为 B/A 比值在各个 offset 上近似恒定（见 `Table7_bop_nhanes_pooled_curve.csv` 的 `B_over_A` 列）。

8 国 × 2022 的 fold（A → B）：Nigeria 9.04 → **6.67**、China 6.33 → 4.69、Global 5.72 → 4.22、
Germany 5.67 → 4.13、USA 5.65 → 4.20、Japan 5.06 → 3.73、India 4.94 → 3.63、Brazil 3.82 → **2.83**。
→ **全部 >2.8×**。分病因下降同样一致（8 类全为 −26.2%）。

> 注意：`rr_source = nhanes`（M1 自身曲线占位）在两档间**完全不变**（0.0%），
> 因为它不由 BoP 池派生 —— 这也从侧面确认了 B 档的变动**只**来自池的改动。

### 路径 2 的产物

| 文件 | 内容 |
|---|---|
| `output/Table6_nhanes_hip_wrist_RR.csv` | 两条曲线 + 部位效应比值（百分位轴） |
| `output/Table6_pam_percentile_map.csv` | 百分位 ↔ 暴露值映射（审稿人复核用） |
| `output/QC_pam_site_fit.csv` / `QC_pam_2003_2006.csv` | 样本量/事件数/佩戴分钟/counts 分位 |
| `output/QC_paxinten_vs_raw.csv` | 宽表 vs 原始 xpt 逐人核验结论（PASS） |
| `output/Table7_bop_nhanes_site_sensitivity.csv` | 三档 × 部位效应 |
| `output/Table7_bop_nhanes_pooled_curve.csv` | A vs B 的 `device_pooled × total_PA` 曲线 |
| `output/Table7_bop_nhanes_weight_share.csv` | NHANES 在 B 档设备臂的权重占比 |
| `output/Table7_bop_nhanes_paf_impact.csv` | **逐 location×year 的 PAF 影响力对照**（按需） |
| `output/Table7_bop_nhanes_paf_impact_by_cause.csv` | 分病因影响力对照（按需） |
| `output/QC_95_env_override_invariance.csv` | 95 默认行为不变性 md5 记录（按需） |
| `output/bop_rr_draws_withNHANES.rds` | B 档后验（**不覆盖**主产物） |
| `data/bop/rr_table_nhanes_sensitivity.csv` | 追加后输入快照（**不是**主输入） |


### 必须写进局限的口径差异

- **wear 判定算法不同**：2003–2006 用 `rnhanesdata` 的 `Flags_C/D`（= `process_flags()`，
  **Choi et al. 2011** 算法，`window=90/tol=2/tol_upper=99`，源自 `accelerometry::weartime`）；
  2011–2014 用 CDC 官方 `PAXPREDM`。同属「佩戴/非佩戴」判定的**不同实现**。
  → **已于 2026-10-12 做完全谱敏感性**（见下文「部位效应矛盾裁决」）：在两套站得住的髋侧规则下
    部位效应比值稳定在 0.754–1.048、14/14 组合 CI 含 1，**算法差异不足以解释矛盾**。
- **2003–2006 无成人 GPAQ 自报模块**（`PAQ_C/D` 只有 `PAD0xx` 系列）→ 该周期曲线为**纯设备曲线**，
  无法做自报 × 设备的个体内校准。本子分析正需要纯设备曲线。
- **两周期是独立样本**（不同人），故部位效应的不确定性按独立系数向量抽样；
  但同一周期内 8 个对比点共用同一参照组 → 组内相关未建模（与 05a 同一局限）。
- 暴露均值/中位随访为**人群加权**结果；髋式 `counts_per_day` 中位数 224,855（P25 150,763 / P75 317,676），
  佩戴中位数 861 min/day。

## 部位效应矛盾裁决：wear 规则 × 判据全谱（2026-10-12）

### 要裁决的矛盾

| 来源 | 部位效应（腕/髋 或 髋/腕） | 95% CI | p |
|---|---|---|---|
| NHANES 同调查内自估（`04b`） | 腕/髋 ≈ **1.00**（9 点里 8 点 CI 含 1） | — | — |
| 文献池自估（`05c` A 档，LPA） | 髋/腕 = **0.660**（= 腕/髋 1.52） | 0.488–0.874 | **0.0055** |

方向相反 → 必须查清是**真实部位效应**还是**口径假象**。最大嫌疑：两波的 wear 判定口径不同
（髋式 = Choi 2011 + **全天**佩戴 ≥600 min；腕式 = CDC `PAXPREDM` + **清醒**佩戴 ≥600 min）。
→ 不只是算法不同，**窗口语义也不同**。

### 先说清：分钟级「同算法」为什么没做成（硬证据，别再试）

| 渠道 | 实测结论 |
|---|---|
| CDC `PAXMIN_G/H` | `Content-Length` = 8,129,196,000 / 9,351,691,760 B（合计 **17.5 GB**）；`ftp.cdc.gov` 实测 **28.6 KB/s** → 约 **170 小时**，不可行 |
| PhysioNet `minute-level-step-count-nhanes/1.0.0` | 提供 1440 宽表（`PAXMTSM`/`PAXPREDM`/`PAXFLGSM`/`AC`，CC0，130,186 受试者-日）→ 但 `physionet.org/files/...` 直链 **403（需登录）**；`physionet-open.s3.amazonaws.com` 404；配套 GitHub 仓库只放了派生 `rds` |
| `rnhanesdata` | 只有 C/D，**没有 G/H** |
| `ftp.cdc.gov/pub/pax_g/` | 是**逐人 80 Hz 原始包**（`62161.tar.bz2` …），对 wear 复算无用 |

→ 绕开的办法：**在各自可控的一侧把规则空间铺满**，再用矩阵覆盖组合空间。

### 做法（全部零下载，用已落盘数据）

| 脚本 | 换什么 | 规则/判据 |
|---|---|---|
| `03c_hip_wear_rule_variants.R` | 髋侧 **wear 判定算法**（同一份未掩码 `PAXINTEN_C/D` 分钟矩阵） | `R0_choi2011`（基准）/ `R1_anydata` / `R2_signal_gt0` / `R3_no_zero_run60` / `R4_awake_signal` |
| `03d_wrist_criterion_variants.R` | 腕侧 **有效日判据与窗口语义**（`PAXDAY_G/H`） | `C0_wake600`（基准）/ `C1_allwear600` / `C2_wake720` / `C3_valid600_qual` / `C4_allwear600_qual` / `C5_allwear600_d6` / `C6_allwear600_d7` |
| `04c_site_wear_sensitivity.R` | 5 × 7 = **35 组合**的比值矩阵 + 指标轴对照 | 参见 `Table8_*` |
| `04d_lit_site_contrast.R` | 文献侧「部位效应」的**可分解性** + 与 NHANES 的**相容性检验**；**metric-aware**：显式标注两侧所属指标轴（文献侧 LPA vs NHANES 总量），并以 §2b 的**量化许可**（共同 offset 处比值差 ≤ 25%）为跨指标比较背书 | 参见 `Table8_lit_*` + `Table8_lit_site_metric_license.csv` |
| `04f_lit_site_anchor.R` | 文献侧部位效应换到**第二个指标轴**（总量活动）重算，腕侧由外部锚定队列 Ko2025 提供；并给出全项目**唯一同指标轴**的文献 vs NHANES 对照 | 参见 `Table8b_site_*` + `QC_site_anchor_license_xcheck.csv` |

> ⚠️ 实测更正（勿凭直觉写论文）：髋式 counts 在静坐/静立时**大量恰为 0**（腕式 MIMS 极少恰为 0），
> 所以严格度顺序是 `R1 ⊃ R0 ≈ R3 ⊃ R2 ⊃ R4`，R2/R4 落在**更严**的一端、并非「最接近腕侧」。
> 纳入人数：R1 7,289 / R0 5,890 / R3 5,918 / R2 2,999 / R4 2,708。

### 结果

**1）髋侧曲线对规则敏感，但敏感的是「两端」，不是「算法实现」**

| offset | R0 Choi | R3 长零段 | R1 不剔除 | R2 严格信号 | R4 严格+清醒 |
|---|---|---|---|---|---|
| 30 | 0.628 | 0.634 | 0.498 | 0.894 | 0.857 |
| 60 | 0.574 | 0.559 | 0.432 | 1.041 | 0.931 |
| 80 | 0.509 | 0.508 | 0.392 | 1.016 | 0.948 |

→ **R0 ≈ R3（Choi 与长零段规则几乎重合）**；R2/R4 把低活动分钟的"活性"剥掉后关联**消失**。

**2）部位效应比值矩阵（腕/髋 @offset60）**

| 髋规则 ↓ / 腕判据 → | C0 | C1 | C2 | C3 | C4 | C5 | C6 |
|---|---|---|---|---|---|---|---|
| **R0_choi2011** | 0.987 | 0.934 | 1.022 | 0.754 | 0.930 | 0.943 | 0.978 |
| **R3_no_zero_run60** | 1.012 | 0.959 | 1.048 | 0.774 | 0.954 | 0.968 | 1.003 |
| R1_anydata | 1.311 | 1.242 | 1.358 | 1.002 | 1.235 | 1.254 | 1.299 |
| R2_signal_gt0 | 0.544 | 0.515 | 0.563 | 0.416 | 0.512 | 0.520 | 0.539 |
| R4_awake_signal | 0.608 | 0.576 | 0.630 | 0.465 | 0.573 | 0.582 | 0.603 |

- **在两个站得住的髋侧规则（R0/R3）下，跨全部 7 个腕侧判据，比值 0.754–1.048，14/14 组合 CI 含 1。**
- 全部 35 组合中 9 个 CI 不含 1，**全部出自 R2/R4**（即髋式曲线已被规则摧毁的那两档），
  且方向与文献**相反**（比值 < 1）。
- 结论：**无论怎么换腕侧的日级判据，只要髋侧用站得住的口径，部位效应都不可检出。**

**3）文献侧的「部位效应」其实是两研究对照**

- LPA 下 hip 侧只有 `Ekelund2019` 三行、wrist 侧只有 `Sun2025` 三行（`Cao2024` 是既往 CVD 亚组，按
  `05a` 主分析口径 `population == "general"` 已排除）→ **arm 效应与「研究」完全共线**。
- 逐 offset 直接对照（腕/髋）：off25 **1.367** [1.156, 1.615]、off50 **1.705** [1.404, 2.070]、
  off75 **2.026** [1.462, 2.808]。
- 相容性检验（NHANES 网格为 10/20/…/80，25 与 75 用**对数尺度插值**）：

| offset | 文献 | NHANES 自估 | NHANES 95%CI 是否含文献点 |
|---|---|---|---|
| 25（插值） | 1.367 | 1.075 [0.901, 1.299] | **否** |
| 50（网格点） | 1.705 | 0.993 [0.780, 1.283] | **否** |
| 75（插值） | 2.026 | 1.034 [0.557, 1.883] | **否** |

→ **文献侧点估计在三个档位全部落在 NHANES 95% CI 之外**，不能被解释为单纯的佩戴部位效应。

**4）指标轴本身影响陡度**（髋侧、同一人群，`Table8_metric_axis_check.csv`）

| 指标 | RR@off30 | RR@off60 | RR@off80 | off80/off30 |
|---|---|---|---|---|
| 总量 counts | 0.628 | 0.574 | 0.509 | **0.811** |
| 轻强度体量 LPA 100–2020 | 0.648 | 0.595 | 0.560 | **0.864**（更浅） |
| 静坐体量 <100 | 0.820 | 0.763 | 0.787 | 0.960 |
| MVPA 体量 ≥2020 | 0.604 | 0.476 | 0.358 | **0.593**（最陡） |

→ 指标的**操作化**（体量 vs 时长、哪一强度带）本身就能改变陡度；
文献侧 EK19（轻强度 counts 体量）与 SV25（ML 分类 LPA **时长**）虽同标称 `LPA`，操作化并不同。

### 等价性硬核验（敏感性与主分析同源，不是另写一套）

| 核验 | 结果 |
|---|---|
| `03c` 的 `R0` vs `03b`（`pam_2003_2006.rds`） | **逐值一致**，最大相对偏差 < 1e-10 |
| `03d` 的 `C0` vs `analytic.rds` | **逐值一致**，最大相对偏差 < 1e-10 |
| `04c` 的 `R0×C0` vs `04b` `Table6` | `rr_hip` 5.6e-16、`rr_wrist` 4.4e-16、插入式比值 1.3e-15（**机器精度**） |
| 抽样均值比值的差异 0.027 | 蒙特卡洛噪声（`04b` 与本脚本随机流不同），非不一致 |

所有 15 条曲线（5 髋规则 + 3 体量带 + 7 腕判据）都由 `code/lib/pa_site_lib.R` **同一套实现**拟合。

### 本轮新增的 R 陷阱

- **`..names(x)` 依旧不能用**（`..` 只对裸符号生效）；本轮又踩到一次同类问题：
  写台账时按**首列名**查重会错（`extraction_log.csv` 首列是 `date_utc`，不是 `row_id`）
  → 台账必须**按台账自身列名构造**，否则日期落到不存在的列、产生整列 NA 的"幽灵行"。
- **`load()` 进 `new.env()` 后必须用 `get(name, envir = e)` 取对象**；直接 `get()` 会命中全局同名残留。

## 路径 1 待命管线：全文到手即可一键入表（`05d`）

- 输入：`data/bop/rr_table_pending_intake.csv`（首次运行由脚本自动生成，含 5 个候选行：
  `Ko2025` 四分位 ×3、`Inan-Eroglu2024` 三分位 ×2，全部 `intake_status = pending`）。
- **默认 dry-run**：只校验不改表。10 条硬规则 →
  `V1` row_id 唯一 / `V2` 15 个必需列齐备 / `V3` `0 < hr_lo ≤ hr ≤ hr_hi` /
  `V4` `method=device & wear_site=wrist` / `V5` 暴露中心与参照齐备且 `ref < center` /
  `V6` `population=general` / `V7` `intake_axis_confirmed=total_PA` / `V8` pmid+doi 齐备 /
  `V9` 参照为最低类 / `V10` 切点数值已知。
- 真入表：`PA_INTAKE_APPLY=1`（**校验全绿才写**）；自动备份原表 → `rr_table_backup_<RUN_ID>.csv`，
  台账按 `row_id` 幂等追加；末尾打印**入表后必须重跑的命令序列**。
- **已端到端实测**（用一条 `TESTONLY` 行）：ACCEPT 1 → 主表恰好 +1 行、台账恰好 +1 条；
  重跑幂等（md5 不变）；测试后主表/台账**逐字节还原**（md5 与测试前一致）并已删除测试备份。



## Module 3 情景表：fold 从哪来 + 正式定级 + GBD 口径对齐（2026-10-15）

**背景**：s1p 主分析下 `recomputed_deaths / gbd_deaths` 的 fold 在 8 个地区为 **3.8–14.9**（Global 2022 = 5.70，见第 4 节）。
纯 PAF 口径的 fold（本研究 PAF ÷ GBD PAF）在本节 8 个地区为 **5.36–6.38**（Global 2022 = **5.79**）。
此前推测过三个来源（暴露 SD/CV、人口加权、分母口径）—— **前两个已被实测排除**
（CV 0.40→2.20 只动 **8.2%**；人口加权开关只动 **4.2%**）。

**做法**：影子脚本 `code/97_m3_scenarios.R`（**不改主链、不覆盖冻结产物**）。该文件是同一天
`97_m3_diagnose.R` 的**转正版**（旧件已删）；用 12 个情景拨动三个旋钮 + 一组稳健性网格 + 一张同质化表。
产物：`Table4_m3_decomp.csv`（全量分解）、**`Table9_m3_scenario_summary.csv`（⭐ 正式定级表，投稿用）**、
`Table10_m3_robustness.csv`、`Table10_m3_country_homogeneity.csv`、`logs/m3_diagnosis.txt`。

**三项决策落地（2026-10-15 用户拍板，全选推荐项）**

| 编号 | 决策 | 落地 |
|---|---|---|
| **N1** | fold 从「主发现」降为**口径分解 + 上界敏感性** | 主结果 = `S0_base`（保守口径）；`D2_p85_nosig` 定为**上界**；其余 10 个为敏感性 |
| **N2** | **放弃**「国别异质性」卖点；改卖「PAF 对暴露参数高度稳健」+「设备尺度国别同质化」 | 新增 CV 网格 / 人口加权开关（Table 10）+ 同质化表（Table 10） |
| **N3** | 加「GBD 口径对齐」敏感性情景（RR 幅度**自动求解**对齐） | `GBD_ALIGNED_RR` / `GBD_FAITHFUL` 两个情景 |

> ⚠️ **转正时修掉两个真 bug，会小幅移动数值（≤ ~2%），结论方向不变**：
> **R1** 首版 `mk_rr_shadow()` 在情景循环里沿用全局 RNG 流 → **同一情景在不同表里抽到不同后验子集**
> （`S0_base` 在 [A] 表 0.1755、在 [H] 表 0.1728，差 1.5%）。现在函数内固定 `set.seed(RR_SEED)`
> （后验 draw 可交换，固定子集是正确的）→ **PAF 成为 `(px, tmrel, rr_scale)` 的纯函数**。
> **R2** 首版把所有非 `abs` 档 TMREL **都**解析到第 85 百分位 → `L1a_p70` 实际是 `L1b_p85` 的副本；
> 被 MC 噪声掩盖（12.60 vs 12.44 看似"有差"），固定种子后两者逐位相同（12.59 = 12.59）才暴露。
> 新增 `tmrel_at_pct()` 修正后 `L1a_p70` 的 fold 为 **9.14**，单调落在 5.79 与 12.59 之间 ✅

### 结果（Global 2022，pooled；含 role 定级）

| role | 层 | 情景 | pct_below | RR̄_below | k 锚定 | PAF | fold | vs 基准 |
|---|---|---|---|---|---|---|---|---|
| **main** | 基准 | `S0_base` | 0.541 | 1.395 | 1.683 | 0.1760 | **5.79** | — |
| **upper_bound** | 上界 | TMREL 85 百分位 + 取消卷积 | 0.806 | 1.685 | 2.436 | 0.3558 | **11.70** | +102% |
| **gbd_aligned** | N3-A | RR 幅度对齐（TMREL 保持绝对口径） | 0.541 | **1.0369** | 1.683 | 0.0196 | **0.64** | −89% |
| **gbd_aligned** | N3-B | TMREL 85 百分位 + RR 幅度对齐 | 0.844 | **1.0369** | 2.436 | 0.0302 | **0.99** | **−83%** |
| sensitivity | L1 | TMREL → 第 70 百分位 | 0.689 | 1.559 | 2.028 | 0.2781 | 9.14 | +58% |
| sensitivity | L1 | TMREL → 第 85 百分位（= GBD 定义） | 0.844 | 1.735 | 2.436 | 0.3830 | 12.59 | **+118%** |
| sensitivity | L2 | `SIGMA_MIMS` 3335 → 1600 | 0.584 | 1.440 | 1.788 | 0.2043 | 6.72 | +16% |
| sensitivity | L2 | `SIGMA_MIMS` 3335 → 800 | 0.654 | 1.513 | 1.969 | 0.2510 | 8.25 | +43% |
| sensitivity | L2 | `SIGMA_MIMS` 3335 → 100（≈取消卷积） | 0.806 | 1.641 | 2.373 | 0.3406 | 11.20 | **+93%** |
| sensitivity | L3 | RR 幅度缩到 GBD 水平（s = 0.0954，首版固定系数） | 0.541 | 1.038 | 1.683 | 0.0200 | 0.66 | **−89%** |
| sensitivity | M2 | 保秩映射 + 绝对 TMREL | 0.483 | 1.334 | 1.565 | 0.1388 | 4.56 | −21% |
| sensitivity | M2 | 保秩映射 + TMREL 85 百分位 | 0.850 | 1.728 | 2.436 | 0.3821 | 12.56 | +117% |

> 附带数学事实：`L1a_p70` 与 `L1b_p85` 的 fold 在 **8 个地区完全相同**（9.14 / 12.59，band 无展宽）。
> 原因：RR 曲线的自变量是**百分位偏移** `off = 100·p − 12.5`，TMREL 一旦定在固定百分位，
> 整条曲线就与地区无关 → **「相对百分位」口径下 PAF 与地区无关是数学必然**；
> 地区差异只可能来自「绝对口径」（TMREL 固定 13222 MIMS）下的分布形状差异。
> 这独立地说明「国别异质性」不是一个可售卖的发现（见下 N2）。

### 四条结论（其中两条与事前推测相反）

1. **fold 的唯一主导是 RR 曲线的超额风险幅度**（L3 单独即 **−89%**）。
   我们 <TMREL 人群的平均 RR = **1.395**，GBD 的隐含水平 = **1.0369**（由官方 PAF 反算）。
   这不是「口径 bug」，而是**两条曲线本身不同**：我们的来自文献池化（连续、未收缩），
   GBD 的经 MR-BRT 收缩 + 年龄衰减 + 4 档分类化 → **两者不可直接比较**。
2. **❌ 按 GBD 定义改 TMREL 会让 fold 翻倍**（**+118%**），与事前预期相反。
   原因：TMREL 右移后重锚定系数 k 从 1.683 → 2.436，整条 RR 曲线被放大，净效应超过「暴露不足比例」的变化。
   → **D2 双轨（用户选 2A）的实测结论是「不要改」**。
3. **❌ 取消 `SIGMA_MIMS` 卷积同样让 fold 翻倍**（**+93%**）。
   也就是说，**这个校准副产品反而在帮我们靠近 GBD**（把 pct_below 从 80.6% 压到 54.1%）。
   → 事前把它当作「抹平病灶」的判断不成立。
4. **⭐ 口径对齐后完全闭合（N3）** —— 见下节。

### ⭐ N3：GBD 口径对齐 —— fold 被完全解释（本轮最强结果）

`rr_scale = "auto"` 会让脚本**反解**一个幅度缩放系数 s，使「<TMREL 人群的平均 RR」恰好等于 GBD 在其
TMREL 定义下隐含的 **1.0369**。两个情景（Global 2022）：

| 情景 | TMREL | pct_below | 反解出的 s | RR̄_below | PAF | fold |
|---|---|---|---|---|---|---|
| `S0_base`（主分析） | 13222 MIMS（绝对口径） | 0.541 | 1.0000 | 1.395 | 0.1760 | 5.79 |
| `GBD_ALIGNED_RR` | 13222 MIMS | 0.541 | **0.0935** | 1.0369 | 0.0196 | **0.64** |
| `GBD_FAITHFUL` | 16315 MIMS（第 85 百分位） | 0.844 | **0.0502** | 1.0369 | 0.0302 | **0.99** |

**读法**

- **A（只对齐 RR 幅度，TMREL 保持绝对口径）**：fold 5.79 → **0.64**。在 RR 强度相同的条件下，
  本研究基于设备测量的 PAF **低于** GBD —— 因为我们把 TMREL 定在人群分布第 **54.1** 百分位，
  而 GBD 定在第 **85** 百分位，被判为「暴露不足」的人口少得多。
- **B（TMREL 与 RR 幅度同时对齐）**：fold **0.994**，8 个地区 band **0.99–1.00** → **完全闭合**。

> **这就是 N1「口径分解」的终点**：GBD 与本研究的 PAF 差异可被
> **①TMREL 定义（第 85 百分位）** + **②RR 幅度（MR-BRT 收缩 + 年龄衰减 + 4 档分类化）**
> 两项**完全解释**，不需要任何「GBD 算错了」的论断。
> 可直接写进 Abstract / Discussion 的结论句：
> **「GBD 的 LPA 归因负担水平主要由其 TMREL 定义驱动，而非 RR 强度；在对齐 RR 强度后，
> 基于设备测量的估计比 GBD 低约 36%。」**

### N2：稳健性与国别同质化（替换掉「国别异质性」卖点）

**（1）PAF 对暴露分布参数高度稳健** —— CV 网格（8 地区全做，表内为 Global 2022）

| CV（MET 尺度） | 0.40 | 0.60 | 0.80 | 1.00 | 1.60 | **2.20** | S1′ 主分析（cell 级） |
|---|---|---|---|---|---|---|---|
| PAF | 0.1655 | 0.1670 | 0.1690 | 0.1712 | 0.1764 | 0.1792 | **0.1760** |

**CV 跨度 5.5 倍，PAF 极差仅 8.2%**；S1′ 主分析值正落在这条带内。
**人口加权开关**：Global 0.1760（开）→ 0.1838（关），只动 **4.2%**。
→ **fold 不可能由 CV/SD 的选择或人口加权解释**，只可能来自口径（见上 N3）。这是一条正面结论，进 Results。

**（2）设备尺度国别同质化**（`Table10_m3_country_homogeneity.csv`）

| 尺度 | 国别均值极差比 |
|---|---|
| MET 尺度（GBD 自报） | **2.92×** |
| 设备尺度（校准后） | **1.033×** |

MET 尺度上 India 的活动量是 Japan 的 2.92 倍；映射到设备尺度后只剩 **3.3%**，
PAF 国别极差 0.0310（范围 0.1630–0.1940）。

> **这是校准模型 R²=0.19 的固有衰减，不是 M1 的实现缺陷。** 但它同时是一条可写的正面论断：
> 自报口径下的巨大国别异质性里含有大量**测量伪影**成分，客观测量下全球体力活动分布高度同质。
> ⚠️ 必须同时在 Discussion 如实写明：该压缩幅度**部分**来自低 R² 的校准映射，不可全部归因于"测量伪影"。

### D3（M2 保秩映射）的意外结果 —— 已放弃该卖点

| 项 | M1（现状） | M2（保秩） |
|---|---|---|
| 设备均值极差比 | 1.033× | **1.040×** |
| PAF 国别极差 | 0.0310 | 0.0261 |
| pct_below 范围 | 0.520–0.569 | 0.435–0.486 |
| fold（Global 2022） | 5.79 | 4.56 |

**M2 并没有实现「保留国别差异」** —— 与本节上文早前「按构造保留国别排序与差异」的说法**相反**（该句已失效）。
原因：M2 用的 `F_y` 是**同一套 NHANES 设备经验分布**，而 15 个 cell 的 MET 分布形状相近（sdlog 接近）、只是位置不同
→ 经同一 `F_y` 映射后设备分布几乎重合。**要保留国别差异，需要国别特定的 `F_y`（我们没有）。**
→ 按 N2 决策：**不做 M2′；M2 仅作为敏感性情景留在 Table 4 / Table 9。**

> 附带的硬事实：MET 尺度国别均值差 **2.92×**，设备尺度只剩 **3.3%（M1）/ 4.0%（M2）**。
> 这是**校准模型（R²=0.19）的固有性质**，不是 M1 的实现缺陷 → 必须写进 Discussion 局限。

### 复现

```bash
cd code && Rscript 97_m3_scenarios.R   # ~1–2 min；产物 Table4 / Table5 / Table9 / Table10×2 / m3_diagnosis.txt
```

| 核验项 | 结果 |
| --- | --- |
| 连续两次运行，5 个产物 md5 逐字节比对 | ✅ **5/5 一致**（R1 固定种子后成为确定性脚本） |
| 冻结产物完整性（运行前后） | ✅ `PREVIEW_module3_s1p_*.csv` 5 个 + `Table3_sd_mean_*` 3 个，共 **8/8 md5 未变** |
| 同情景一致性自查 | ✅ `S0_base` PAF = 人口加权「开（主分析）」PAF = 0.1760356…（R1 修复前两者差 1.5%） |

> ⚠️ 踩过的坑（共三个，**全部属于「静默失效」**）：
> ① 首版 97 直接调 05 的 `exposure_dist()` 并想用参数拨动 sigma —— 它的 sigma 是**闭包捕获的全局 `SIGMA_MIMS`**，
> 传参无效 → L2 三档**静默失效**（fold 只动 −1%，看起来像"卷积无影响"）。改为复制逻辑 + 显式参数化后正常。
> ② **R1**：`sample.int` 沿用全局 RNG 流 → 同一情景在不同表里两个数（0.1755 vs 0.1728）。
> ③ **R2**：非 `abs` 档 TMREL 全部解析到第 85 百分位 → `L1a_p70` 是 `L1b_p85` 的副本。
> **静默失效比报错更危险** —— 三个坑都是靠「逐字节复跑 + 同情景交叉对照」才挖出来的。

---

## Fig 5(d) 口径分解瀑布图（`07_fig5d_waterfall.R`，2026-10-15）

**定位**：把 §上文「GBD 口径对齐后 fold = 0.99，差异被完全解释」的结论图形化（N1 决策的图像证据）。
**只读** 97 的 `Table9_m3_scenario_summary.csv` + `Table4_m3_decomp.csv`（不重算、不覆盖任何冻结产物），
已入 `00_run_all.R` 主链（97 与 06 之间，约 5 s）。

**图的结构**（Global 2022，y 轴 = 死亡口径 PAF，fold 通过柱旁标注呈现）：

| 柱 | 内容 | PAF | fold | 倍数因子 |
|---|---|---|---|---|
| 1 | 本研究主结果（`S0_base`，含 8 地区误差棒 5.36–6.38） | 0.176 | 5.79 | — |
| 2 | − RR 超额幅度对齐（RR̄ 1.395 → 1.037） | 0.020 | 0.64 | ×0.11 |
| 3 | + TMREL 定义对齐（第 54.1 → 第 85 百分位） | 0.030 | 0.99 | ×1.54 |
| 4 | 残余（GBD 暴露分布 / 年龄结构 / MR-BRT 形状等，按设计几乎不可见） | 0.030 | 1.00 | ×1.006 |
| 5 | GBD 2023 现报 | 0.030 | 1.00 | — |

**内置断言**（脚本会硬失败而非画错图）：
① `paf_gbd` 必须仍是全局常数（fold 分母假设）；
② `Table9` 的 `paf_global` 与 `Table4` 的 Global 行逐位一致（防两表口径漂移）。

**产物 6 件**：`Fig5d_waterfall_decomposition.pdf/.png`（主图，4.6×3.6 in）、
`Fig5d_waterfall_by_region.pdf/.png`（8 地区小倍数补充图，7.2×4.0 in）、
`Fig5d_waterfall_data.csv`（逐段数值，11 列 × 45 行）、`Fig5d_waterfall_caption.md`（中英双语图注）。

**复现**：`cd code && Rscript 07_fig5d_waterfall.R`（~3.5 s）；连续两次运行 PNG×2 + CSV + MD **4/4 md5 一致**；
图内文字一律 ASCII（Windows 非 UTF-8 locale 渲染约束）；PDF 时间戳由 98 的 E 层豁免（PNG 承担内容一致性）。

---

## 投稿图表体系（`08a–08f` + `09`，2026-10-15）

**目录约定（panel-by-panel，供手动编辑与重组）**：

```
figures/
├── panel/     每个子图一份独立可编辑 PDF（+ 同名 PNG 预览），命名 Fig{n}{letter}_*.pdf
├── combined/  拼合后的整图 PDF（Fig1–Fig6）
└── tables/    Table 1–4 投稿 PDF
```

**共享风格 `08_fig_style.R`**：Okabe–Ito 色盲友好色板、`theme_pa()`、
`save_panel()/save_combined()/save_table_pdf()`（全部 cairo_pdf，图内文字一律 ASCII）。

| 脚本 | 产物 | 状态 |
|---|---|---|
| `08a_fig1_design.R` | Fig 1 三模块流程图（数字动态读取，7,007/664/5 研究 21 曲线） | ✅ |
| `08b_fig2_sample.R` | Fig 2(a) 流程 14,693→13,027→7,854→7,007（**+deaths 列 +cvd_deaths 列**：769 / 664 与 242 / 207，两段式样本口径的落盘来源）；(b) 加权密度（自报达标 61.7% vs 设备低于 TMREL 51.1%）；(c) 加权交叉热图 | ✅ |
| `08c_fig3_dose_response.R` | Fig 3 **六面板**：行1 腕式 MIMS（参照锚点 **13,222 = TMREL 3600–4400 的设备等效中点**，读 `04` 的 `Table2_reference_anchor.csv`，不反推）；行2 髋式 Peak-30；行3 髋式 MVPA。行2–3 每面板画 M0 未调体量（实线）+ M1 调体量（虚线）双曲线 | ✅ |
| `08d_fig4_calibration.R` | Fig 4(a) 校准散点+曲线；(b) 患病率自报 vs 设备；(c) 报告偏倚。内置与 Table4 主链的一致性断言（差 >50 MIMS 硬警告） | ✅ |
| `08e_fig5_burden.R` | Fig 5 **四面板齐**：(a) 哑铃图（重算 vs GBD，fold 3.8–8.7）；**(b) SDI 五分位分组柱 + fold 标注（Low 9.4 → 其余 4.9–5.8）**；**(c) 204 国 × 8 病因 fold 热图（按 SDI 排序，色阶上界 fold=43 截 2.0%；⚠️ 原定 PAF 热图因 PAF 在 cause 间恒等而退化，改画 fold）**；(d) 瀑布渲染（读 07 的 CSV） | 整图 `Fig5_a_b_c_d.pdf`（8.4×10.6 in） |
| `08f_fig6_sensitivity.R` | Fig 6 **三面板**：(a) 情景森林（Table9 的 12 情景 fold + 8 地区 band）；(b) leave-one-out（Table12）；(c) E-value（Table13） | ✅ |
| `09_tables.R` | Table 1 加权基线（svymean）/ Table 2 HR（4 svycox + trend + per-IQR）/ Table 3 校准系数+报告偏倚 / Table 4 负担对比；另落盘 **`Sample_definition.csv`**（两段式样本口径 **8 行**：设备样本 7,854/769、Cox 分析集 7,007/664、**Cox 集心血管死亡 207**、随访链接 7,842、两段中位随访 81 月） | ✅ |
| `10_captions.R` | 图注 / 表注（中英双语）：Fig 1–6 共 17 面板 + Table 1–4 + 补充表 S1–S12（含新补的 **Table S4**）；数值全量动态读取，末尾附口径一致性自检（**当前最大相对差 0.00%**：5 处来源 Global 2022 pooled 归因死亡全为 3,775,099） | ✅ |

**确定性核验**：98 五层核验 **PASS 192 / WARN 0 / FAIL 0 / INFO 2**（共 194 项；2026-10-16 贝叶斯引擎轮，含 Fig3 六面板 / Fig5 四面板 / Fig6 三面板 / Table11–14 与 Table S4）；
连续两轮链跑（`154842` → `155910` → `160733`）E 层跨运行 **一致 297 / 不一致 0**。
**已入主链**：`00_run_all.R` 顺序 …95 → 95c → **95b** → 97 → 07 → 08a–08f → 09 → **10** → 06 → 98。
**已知缺口（后续 Phase）**：① ✅ 已关闭——Fig 5(b)(c) + Table S4 全量落地（204 国，见 `data/gbd/C1_204国_覆盖核查与落地清单.md` / `C2_SDI_下载与落地清单.md`）；
② ✅ 已关闭——图注 / 表注已系统生成（`10_captions.R` → `output/CAPTIONS_figures_tables.md`，中英双语，覆盖主文 + 补充材料）；
③ ✅ 已关闭——**Module 3 口径统一为确定性后验枚举**（2026-10-15，详见下节）。

### Module 3 口径统一：确定性后验枚举（2026-10-15，**改口径 + 修一处真缺陷**）

**触发**：`10_captions.R` 的口径自检表显示 Global 2022 pooled 归因死亡在 4 处产物中
取值 3,762,012 / 3,776,382 / 3,809,723 / 3,820,177（最大相对差 1.55%）。

**排查结论（用探针定量，非猜测）——两个独立原因叠加**：

| # | 原因 | 量级 | 性质 |
|---|---|---|---|
| ① | `recompute_burden()` 是「有放回抽 1 条 × 400 次取均值」的 **MC 近似** | 0.535% 标准误 | 抽样噪声 |
| ② | **`95b` 的 A 档读的是 `grid` 轨产物**（`PREVIEW_module3_`），而 `09` / `95c` / `97` 读 `s1p` 轨 | ~1.7% | **真缺陷（跨轨比较）** |
| ③ | **Jensen 口径差**：`97` 与 `95` 的诊断列用 `PAF(E[rr])`，而 totals 用 `E[PAF(rr)]` | 0.24% | **真缺陷（口径不一致）** |

**修复**：

1. `make_rr_fun_pooled()` 的 `fun()` 改为返回 **n_curve × n_off 矩阵**（首次调用建缓存，
   另留 `fun_draw()` 供旧行为）；`make_rr_fun_nhanes()` 改为固定种子**枚举** 200 条；
   `recompute_burden()` 检测到矩阵即走确定性路径（新增批量函数 `paf_from_dist_mat()`，
   一次矩阵乘法算完全部曲线）；`97` 的 `mk_rr_shadow()` 由「抽 200 条」改为「全部曲线」，
   且幅度缩放改为作用于**整条曲线集**。
2. `95b` 的 `P_A` / `P_B` / `TAG_B` 全部改为 `s1p` 轨，且 `run95()` 显式设 `PA_CV_MODE=s1p`。
3. `95` / `95c` 的 `implied_paf_pooled` 诊断列改为 `mean(paf_from_dist_mat(px$f, br$fun()))`（`E[PAF]` 口径）。

**结果（Global 2022, `rr_source = pooled`, s1p 主轨）**：

| 产物 | 脚本 | PAF | 归因死亡 |
|---|---|---|---|
| `PREVIEW_module3_s1p_totals.csv` | 95 | 0.1739584 | 3,775,099 |
| `M3_BYCOUNTRY_totals.csv` | 95c | 0.1739584 | 3,775,099 |
| `Table4_m3_decomp.csv`（S0_base） | 97 | 0.1739584 | —（四者一致到浮点） |

> **⚠️ 2026-10-16 注（数值随引擎更新）**：本表原记 PAF 0.174079 / 3,777,713，那是 **REML 引擎**下的值。
> Module 2 升级为真贝叶斯后 BoP 后验曲线改变 → 现为 **PAF 0.1739584 / 归因死亡 3,775,099**（差 0.07%）。
> **"五处来源完全一致"这一性质不变**（仍 0.00%），变的是绝对值。分母 `total_deaths = 21,701,155.62`。

**跑时收益（意外）**：确定性枚举比 MC 重抽快 1–2 个数量级 —— `95` **15 min → 32 s**、
`95c` **17 min → 1.1 min**。

**新增工具** `code/tools/syncheck.R`：带 locale 回退链的 R 语法总检
（避免中文注释/变量名在未设 `LC_CTYPE` 时被误报 `unexpected invalid token`）。

### 强度维度：口径统一（2026-10-15，**改结论**）

`04e` 的三种参数化曾被**三种不同的体量口径**割裂，导致 MVPA「独立效应」出现方向性矛盾：

| 参数化 | 体量口径（旧） | MVPA 调整体量后（旧） | 体量口径（新） | MVPA（新） |
|---|---|---|---|---|
| RCS 曲线 | `ns(counts,4)` | HR(55.5 vs 2.7 min)=0.47 显著 | 不变 | 0.47 显著 |
| per-IQR | 另拟合 log-linear + **线性**体量 | **1.06 (0.84,1.34) 无效** | 由**同一 RCS** 做线性对比 | **0.68 (0.48,0.97) 显著** |
| 四分位 | **线性** counts | Q4 0.76 / P-trend 0.47 平坦 | `ns(counts,4)` | Q4 0.58 / P-trend 0.016 显著 |

统一后三者只差「强度项的函数形式」，体量口径恒定 → 分歧干净归因于函数形式。
**结论变更**：旧「MVPA 调整体量后完全衰减」**作废**；新结论是 **MVPA 与 Peak-30 调整体量后
都保留保护性关联**（per-IQR：MVPA 0.68 显著、Peak-30 0.78 不显著但 Q4 0.53 显著、P-trend 0.061）。
E-value 相应反转：MVPA_AC E=1.93（CI 界 1.17）、MVPA_CVD E=2.65（CI 界 1.51），
Peak-30_AC E=1.65（CI 跨 1 → E(CI)=1）。
**正文写法**：强度信号「集中于分布上部」——MVPA 的 IQR 落在曲线更远处故 per-IQR 显著，
Peak-30 的 IQR 落点更近故 per-IQR 不显著、但最高四分位仍显著。

---

## 部位效应的指标轴显式化（2026-10-16，**改表述不改数值**）

**起因**：`04d` §3 把「文献侧 LPA 腕/髋比」直接与「NHANES 总量腕/髋比」对照，长期
隐含一个未经证明的前提 —— 两者**同属一个指标轴**。实际上：
- NHANES 两条曲线是**总量轴**（髋 `R0_choi2011` = counts/day；腕 `C0_wake600` = MIMS/day）→ 由 `04c` 的 `Table8_metric_axis_check.csv` 承载；
- 文献侧池内唯一髋/腕双覆盖的指标是 **LPA** → 故 §3 实际是**跨指标**比较。

这不是数值错误，是**归属未显式化**。本轮把它变成**算出来的证据**。

### 1）§0 运行时机器校验（替代手写标签）

用 `04c` 的 `Table8_metric_axis_check.csv` 中 `spec == "R0_choi2011"` 行的 `rr_off30/60/80`
与 `04b` 的 `Table6_nhanes_hip_wrist_RR.csv` 的 `rr_hip` 在 off 30/60/80 **逐值比对**，
偏差 = **0** → 确认 NHANES 曲线属总量轴，不通过即 `stop()`，防止指标标签静默过期。

> ⚠️ 两个必须踩过的坑：① `grepl("R0", spec)` 会一次命中 4 行（`lpa_100_2020__R0` /
> `sed_lt100__R0` / `mvpa_ge2020__R0` 也含 `"R0"`），必须用 `spec == "R0_choi2011"` 精确匹配，
> 否则 `nrow != 1` 直接**静默跳过**校验；② 存储精度对齐 —— axis 表的 RR 是 `round(., 3)` 存盘、
> Table6 是全精度，直接相减会得到 4.1e-4 的**假差异**，比前须先 `round(t6$rr_hip, 3)`。

### 2）§2b 量化许可：跨指标比较是否可辩护

在**共同 offset（25/50/75）**处比较两侧的腕/髋**比值**（因为 §3 比较的就是这个量）：

| offset | 文献侧 LPA 腕/髋 | total_PA（Ko2025 锚点）腕/髋 | 相对差 |
|---|---|---|---|
| 25 | 1.367 | 1.500 | +9.7% |
| 50 | 1.705 | 1.912 | +12.1% |
| 75 | 2.026 | 2.111 | +4.2% |

**最大相差 12.2% < 25% 阈值 → 比值同量级，跨指标比较不改变结论（可辩护）。**

但**斜率之比** `|b_h|/|b_w|` **相差 −35.2%**（3.62 vs 2.35）—— 因为 LPA 腕侧斜率
（−0.00450）远平于 total_PA 腕侧（−0.00849），而腕侧斜率位于**分母**，越平越把比值放大。
故结论必须**分两层**：

- 以 LPA 的**比值**外推部位校正因子 → **可辩护**；
- 以 LPA 的**斜率比**外推 total_PA → **不可辩护**，已写入 Limitations。

> 推导：过原点模型下 `RR(o) = exp(b·o)`，共同 offset 处**腕/髋比 = exp((b_w − b_h)·o)**，
> 由**斜率之差**决定；而**斜率之比** `|b_h|/|b_w|` 把腕侧放在分母 → 两种判据会给出**相反**的方向感，
> 必须选定其一并说明。本项目选定「共同 offset 处比值」（与 §3 实际比较的量一致）。

### 3）锚点提升为正式步骤 `04f_lit_site_anchor.R`

原 `code/tools/site_anchor_totalPA.R` 已**删除**，内容全部迁入 `04f` 并入主链（紧接 `04d` 之后）。
`04e` 编号已被 `04e_pam_intensity_rr.R` 占用，故取 `04f`。新增两个核心产出：

| 产物 | 内容 | 意义 |
|---|---|---|
| `Table8b_site_anchor_vs_nhanes.csv` | 文献侧 total_PA（EK19 髋 × Ko2025 腕锚点）vs NHANES **同调查内** total_PA（`04c` 的 `R0×C0`）：**1.500 [1.279,1.759] / 1.912 [1.415,2.583] / 2.111 [1.690,2.637]** vs **1.075 / 0.993 / 1.034** | 全项目**唯一两侧同指标轴**的部位对照；CI 在 2/3 处重叠，但文献点估计在 3/3 处落在 NHANES 区间外 |
| `QC_site_anchor_license_xcheck.csv` | `04f` 与 `04d` §2b 用**同一估计量**算**同一批数**，逐值复核，**9/9 PASS**（偏差 ≤ 4e-15） | 两脚本互证；任一项 FAIL 即 `stop()` 中止入链 |

**「两来源相减」的前提**：`04f` 守卫 `if (any(anch$study %in% hip$study)) stop()`
—— 该操作只要求**两侧互为独立队列**，不要求两侧互相独立于池；而「并入池化」才要求全部行互相独立
（UKB 重复只否决后者，裁定见 `data/bop/20261016_入池裁定_UKB腕式总PA双源.md`）。

### 4）图注同步

- `10_captions.R`：Table S2 改「同一调查体系、两条同为总量轴」并注明归属校验来源；
  Table S4 新增 **(g) 指标稳健性** 与 **(h) 指标对齐对照** 两段 + 3 条定义；
  补充表映射改为 `Table8_*` + `Table8b_*`。
- `09_tables.R`：`SDEF` 由 5 行扩为 **7 行**，新增设备样本 / Cox 分析集的**中位随访月数**
  （由 `median(t1d$surv_mo)` / `median(mod_dt$surv_mo)` 动态算）。

> ⚠️ **silent sprintf 陷阱（本轮实测踩到）**：`(g)` 段一度**整段消失且无任何报错**。
> 根因是 `.rT <- .bm[metric_definition == "total_PA" & grepl("Ko2025", wrist_source)]`
> 同时命中「Ko2025 锚点」与「Ko2025 + Inan-Eroglu2024 合并档」两行 → `nrow != 1` →
> `if` 分支不进入。修复：改用 `grepl("Ko2025 锚点", wrist_source, fixed = TRUE)`，
> 并给 `else` 分支加**显式 `cat()` 告警**，让失败可见而非静默。
> 本项目凡「条件渲染」段落一律要求 `else` 有可见输出。

---

## 正文撰写进度与「数字必有出处」的两处补漏（2026-10-16）

### 已完稿段落（中英对照，全部零硬编码）

| 段落 | 文件 | 状态 |
|---|---|---|
| Methods 2.1 + Results R1 | `manuscript/Methods_2.1_Results_R1_样本与暴露_中英对照.md` | 完稿 |
| Methods 2.4 | `manuscript/Methods_M2_证据合成_中英对照.md` | 完稿 |
| **Methods 2.6 + 2.7** | `manuscript/Methods_2.6_2.7_部位指标轴_敏感性与软件_中英对照.md` | **完稿（新增）** |
| **Discussion D5（局限）** | `manuscript/Discussion_D5_局限_中英对照.md` | **完稿（新增）** |

**编号调整**：骨架原设单个 **2.6「Sensitivity analyses and software」**，现拆为
**2.6 Wear-site and metric-axis sensitivity** + **2.7 Sensitivity analyses and software** ——
「佩戴部位 × 指标轴」已构成横切方法层（支撑 Table S2/S3/S4），与「敏感性清单 + 软件」性质不同。
**回退**：删掉 `## 2.7` 标题、把 2.7 降为 2.6 的子标题即可，正文无需改动。

**D5 由 6 条扩为 8 条**：新增 (L7) 佩戴部位与指标轴不可分、(L8) 池构成与残余失拟 —— 后者含
`QC_bop_status.csv` 里两条 **WARN 级**读数（等份额百分位假定、固定部分最大 |log 残差| 0.398），
按「不隐藏不利读数」原则必须进正文。

### 补漏一：心血管死亡数 **207** 此前无产物来源

Results R1 与 Discussion L4 都要引用「Cox 分析集中 **207** 例心血管死亡」，但该值此前**只存在于
诊断脚本 `code/tools/_probe_m21_numbers.R` 的控制台输出里**，没有任何落盘产物 —— 直接违反本方案
「正文数字一律有产物来源」的硬性标准。已按与 `deaths` 完全相同的口径补落盘：

- `08b_fig2_sample.R` → `output/Fig2a_flow_numbers.csv` **新增 `cvd_deaths` 列**（设备样本 242 / Cox 集 207）；
  同时加 `if (!"cvd_death" %in% names(adm)) stop(...)` 守卫。
- `09_tables.R` → `output/Sample_definition.csv` 的 `SDEF` 由 7 行扩为 **8 行**，
  新增 `Cardiovascular deaths in the Cox analysis set`（= 207）。
- `10_captions.R` → 两段式跨脚本自检由 **4 个量 / 10 处来源** 升级为 **5 个量 / 12 处来源**，
  新增「多变量 Cox 分析集心血管死亡数」一行，仍由 08b 与 09 **独立推导、逐值比对**（现 0.0000%）。
  缺列时不再静默：写入 `MISSING` 并在控制台可见。

### 补漏二：两段式自检的**口径计数**此前会误导

`10_captions.R` 的控制台摘要原写「%d 处来源」，在新增第 5 个量后会显示 12 —— 读者会误以为
「来源数变了」。已改为明确区分 **`%d 个量 / %d 处来源`**（现「5 个量 / 12 处来源」）。

---

## E 层图件覆盖范围与已知缺口（2026-10-16，**登记不改代码**）

### 结论先行

manifest 的 scope 白名单只有 `raw / gbd / bop / derived / output`（见 `06_manifest.R` L130–134），
**`figures/` 不在其中**。因此图件**只能通过 `output/` 内的镜像副本**进入清单、被 E 层跨运行比对。

| | 数量 | 说明 |
|---|---|---|
| `figures/` 下 `.pdf`/`.png` 总数 | **74** | 面板 + combined，含表格图版 |
| 在 `output/` 有**同名镜像** | **22** | 即真正受 E 层覆盖的部分 |
| `output/` 内 PDF/PNG 条目 | **26** | = 22 同名镜像 + 2 重命名镜像（`Fig3_dose_response.*` ← `Fig3.*`）+ 2 无 `figures/` 副本（`Fig5d_waterfall_by_region.*`）|
| **未覆盖** | **52** | = 活跃产出 **46** + 旧命名残留 **6** |

### 已覆盖（26 条，即 E 层能看守的图件）

`Fig3_dose_response.*`、`Fig3a–f_mims/peak30/mvpa_*`（各 pdf+png）、`Fig5d_waterfall_decomposition.*`、
`Fig5d_waterfall_by_region.*`、`Fig6.pdf|png`、`Fig6a–c_*`。

### 未覆盖：活跃产出 46 个

| 图组 | 数 | 产出脚本 |
|---|---|---|
| Fig1（`Fig1_study_design` + `combined/Fig1`） | 4 | `08a_fig1_design.R` |
| Fig2 系（`combined/Fig2` + `Fig2a_screening_flow` + `Fig2b1_reported_density` + `Fig2b2_device_density` + `Fig2c_reported_vs_device_crosstab`） | 10 | `08b_fig2_sample.R` |
| `combined/Fig3.*`（**仅 combined 本体**；6 面板已镜像） | 2 | `08c_fig3_dose_response.R` |
| Fig4 系（`combined/Fig4` + `Fig4a_calibration_scatter` + `Fig4b_lpa_prevalence` + `Fig4c_reporting_bias`） | 8 | `08d_fig4_calibration.R` |
| Fig5 系（`combined/Fig5_a_d` + `combined/Fig5_a_b_c_d` + `Fig5a_recomputed_vs_gbd` + `Fig5b_gap_by_sdi` + `Fig5c_fold_heatmap_country_cause`） | 10 | `08e_fig5_burden.R` |
| 表格图版（`Table1_baseline` / `Table2_hazard_ratios` / `Table3_calibration_coefficients` / `Table3b_reporting_bias` / `Table4_recomputed_vs_gbd` / `TableS4_recomputed_vs_gbd_bycountry`，各 pdf+png） | 12 | `09_tables.R` |
| **合计** | **46** | |

### 未覆盖：旧命名残留 6 个（已无脚本引用）

`Fig3a_all_cause.*`、`Fig3b_cvd.*`（04 的旧 2-panel 预览，已被 6-panel `Fig3a–f` 取代）、
`Fig6_scenario_forest.*`（已被 `Fig6a_scenario_forest` 取代）。各 pdf+png。

### 为何暂不补齐（2026-10-16 决策：选「登记」而非「补镜像」）

1. **数值来源全部在清单内且已验证**：`Fig2a_flow_numbers.csv`、`Fig2c_crosstab_weighted.csv`、
   `QC_08d_calibration_check.csv`、`Table4_m3_decomp.csv`、`Table9_m3_scenario_summary.csv`、
   `Table1_baseline` 对应的 `Sample_definition.csv` 等。图件是这些产物的**确定性渲染**。
2. **PNG 渲染在本机是逐字节可复现的**：2026-10-16 Run C 实测，重跑 `08c/08f` 后
   10/10 同名 PNG 指纹完全一致（见下方「复核方式」②）。故「未纳入」不等于「不可复现」，
   只是「未被自动看守」。
3. 补齐的收益（投稿前最后一道保险）在全链跑一次即可获得，届时一并做更划算。

### ⚠️ 何时**必须**升级为「补齐镜像」

- 准备投preprint / 投稿冻结版时（届时应把 46 个一并纳入）；
- 任何一次**绘图代码改动**（配色、轴、分面、标注）之后 —— 此时 E 层无法证明图件是否漂移。

### 复核方式（缺口存在时的替代核验）

① 人工确认图件的**数值来源**在 `output/manifest.csv` 内且 E 层 PASS；
② 若要证明图件本身可复现：重跑对应脚本，与重跑前逐一比对同名 PNG 的 SHA-256
   （用 `manifest.csv` 的 `hash` 列，算法见 `hash_algo` 列，当前为 **sha256**）。

### 若将来要补齐（做法留档）

1. 在 `08a_fig1_design.R` / `08b_fig2_sample.R` / `08d_fig4_calibration.R` / `08e_fig5_burden.R` /
   `09_tables.R` 各加一段「交付层镜像」，**照 `08c_fig3_dose_response.R` L168–182 与
   `08f_fig6_sensitivity.R` L196–200 的现成写法**（`file.copy()` + 失败即 `stop()`，并打 `pa_log`）。
2. 在 `98_verify_reproducibility.R` 的 `KEY_OUT` 中登记对应文件名（D 层存在性检查）。
3. 预期影响：清单由 **328 → ~374** 条；下一次跑 98 的 E 层会报「新增 ~46」，属有意为之，需归因。
4. ⚠️ **不要**把图件镜像到 `output/` 下的子目录（如 `output/_archive/`）——`scan_scope(DIR_OUT)`
   使用 `list.files(recursive = TRUE)`，子目录内容同样会被扫入。

---

## 孤儿产物归档（2026-10-16）+ Methods 全部完稿

### 归档动作

把 5 个**已无脚本引用**的旧命名预览产物从 `output/` 移到
`data/scratch/_archive_orphan_20261016/`（同目录附 `README.txt`，含 MD5 与回滚说明）：

```
PREVIEW_NHANES_totals.csv            PREVIEW_NHANES_by_cause.csv
PREVIEW_NHANES_exposure_diag.csv     PREVIEW_NHANES_rr_bridge.csv
PREVIEW_NHANES_rr_source_compare.csv
```

**为什么放 `data/scratch/`**：`06_manifest.R` L130–134 的 scope 白名单只有
`raw / gbd / bop / derived / output`，`data/scratch` 不在其中 → E 层只会报「**消失 5**」。
若放到 `output/_archive/`，因 `scan_scope(DIR_OUT)` 用 `list.files(recursive = TRUE)`
会变成「消失 5 + 新增 5」的更名戏码。**只移不删，可逆。**

**归档依据**：`grep` 全 `code/`（含 `code/tools/`）对这 5 个文件名**零命中**；
且它们均**不在** `98` 的 `KEY_OUT` 中，故 D 层不受影响。

### 核验结果（`--only 06_manifest.R,98_verify_reproducibility.R`，run_id `20261016_220245`）

| 项 | 结果 |
|---|---|
| 清单条数 | **328 → 323** |
| 98 总体 | **PASS（PASS 199 / WARN 0 / FAIL 0）** |
| E 层 | 对照 `20261016_214357`：**一致 320 / 不一致 0**；豁免 3（元产物自指）；**新增 0 / 消失 5** |
| 「消失 5」明细 | 逐条等于上述归档的 5 个文件（已用 manifest 逐行比对确认）|
| 指纹不同 | 仅 3 个元产物自指（`QC_98_checks.csv`、`REPRODUCIBILITY_REPORT.txt`、`manifest_summary.txt`），属结构性豁免 |

复现：`Rscript code/00_run_all.R --only 06_manifest.R,98_verify_reproducibility.R`。
回滚：把 5 个文件移回 `output/` 即可（MD5 见归档目录 `README.txt`）。

### 正文进度（2026-10-16）

**Methods 7 小节全部完稿**：

| 文件 | 覆盖 |
|---|---|
| `manuscript/Methods_2.1_Results_R1_样本与暴露_中英对照.md` | 2.1 + R1 |
| `manuscript/Methods_2.2_结局与协变量_中英对照.md` | 2.2（结局定义、11 项协变量、两模型并列） |
| `manuscript/Methods_2.3_Module1_剂量反应与校准_中英对照.md` | 2.3（样条 Cox、TMREL 绝对锚点、校准） |
| `manuscript/Methods_M2_证据合成_中英对照.md` | 2.4 |
| `manuscript/Methods_2.5_Module3_负担重算_中英对照.md` | 2.5（PAF、8 类病因、SD 自估、确定性） |
| `manuscript/Methods_2.6_2.7_部位指标轴_敏感性与软件_中英对照.md` | 2.6 + 2.7 |
| `manuscript/Discussion_D5_局限_中英对照.md` | D5 |

撰写 2.2/2.3/2.5 时发现并记录的三处口径问题（**已在正文中改正**）：

1. **术语冲突**：`Table2_hr_manuscript.csv` 的 "Model 1 (minimally adjusted)" = 9 项（去掉 BMI 与收缩压），
   而骨架原稿把含 BMI/SBP 的 **11 项**一组叫 "Minimum Sufficient Adjustment Set" → 字面冲突。
   已统一为「Model 1 = 最小调整（9 项）/ Model 2 = 全调整（11 项）」。
2. **残差 SD 双口径**：`QC_08d_calibration_check.csv::resid_SD` = **3,335.36**（`sd(residuals)`，n−1 分母，
   **Module 3 卷积实际使用的 σ**）vs `Table3_calibration.txt` 的 `Residual standard error` = **3,337**
   （lm 的 df = 7,847 校正版）。同源不同分母，正文**只报 3,335**，避免读者当成矛盾。
3. **「21 区域」无产物支撑**：骨架 §2.5 原有该分层，但全部产物中只有 `Fig5d_waterfall_by_region`
   （实为 Global + 7 国）。已从正文删除该分层，并在 Methods 2.5 文件中留档。

---

## Results R2–R6 完稿（2026-10-16）+ 三处口径纠偏 + 一处留痕缺口

**正文状态**：`manuscript/Results_R2_R6_中英对照.md` 已完稿（R2 自报 vs 设备 / R3 剂量-反应 / R4 校准与报告偏倚
/ R5 重算负担 vs GBD / R6 敏感性）。**Methods + Results 至此全部完稿**，正文剩余 Introduction、
Discussion D1–D4/D6、Abstract 与声明段。**本次未改任何代码**，全部数字逐项回查 `output/` 产物。

**撰写中查出并纠正的三处口径问题（前两处会直接被审稿人抓）**：

1. **「204 国」必须同时满足两个筛选条件**：`M3_BYCOUNTRY_totals.csv` 每年每 location 有
   `rr_source = pooled` 与 `nhanes` **两行**。主分析口径是 **`pooled`**（其 Global fold = 5.7196，
   与 `Table9`/`Table4` 主分析一致；`nhanes` 行 Global fold = 6.2153，**不是**主结果）。
   同时必须**去掉 Global**（205 → 204）。两种误用各得一个「看起来合理」的错数：
   - 误取 `nhanes`：中位 6.51、IQR 4.97–10.31（与 A6/SDI 表矛盾）
   - 误含 `Global`：中位 6.0136、IQR 4.6225–9.4328（骨架原写 6.05 / 4.62–9.47，**正确口径**）
2. **两个残差 SD 不可混用**：`Table3_calibration.txt` 的 `Residual standard error = 3,337`
   （lm，df = 7,847 校正）vs `QC_08d_calibration_check.csv` 的 `resid_SD = 3,335.36`
   （`sd(residuals)`，n−1 分母）。同源、差 < 0.06%。**正文只报 3,335**，因为那是 Module 3
   卷积实际使用的 σ；同段出现两个数会被读成内部矛盾。
3. **留一法的百分比位移分母是「留一链自身基线 5.667」，不是主分析的 5.720**。
   `Table12_m3_loo_paf.csv` 的 `BASE_all` Global 2022 fold = **5.6674**，与 `S0_base` 的
   **5.7196** 相差 0.9%（留一链经 `Table12_bop_loo_RR.csv` 独立重算 PAF）。
   若误用 5.720 作分母，剔除 Ekelund 会算成 −33.6% 而非 **−33.0%**，与 Methods 2.7 / Table S9 不一致。

**一处留痕缺口（已登记，未改代码）**：R2 的两个读数 **61.7%**（自报达 WHO 指南，加权）与
**51.1%**（设备低于 TMREL，加权）目前**只出现在 `08b` 的控制台摘要**中，未单独落盘为 CSV。
它们由 `08b_fig2_sample.R` 的 `rate_sr` / `rate_dv` 计算（分别打印到 `step_08b_fig2_sample.log`），
链上可复现，但**不满足「每个引用数字有独立产物」的最严口径**。
> 如需闭合：在 `08b` 增加一行 `fwrite(data.table(rate_sr = rate_sr, rate_dv = rate_dv), "Fig2b_exposure_summary.csv")`，
> 随后 `--from 08b_fig2_sample.R` 重跑（08b/09/10/06/98，约 6 min）。预期影响：清单 323 → 324，
> 98 结论不变，E 层报「新增 1」。**待确认后再执行**。

**做过的两处非代码改动（登记以保可追溯）**：
- 骨架 §3 R2–R6 各段由「规格」改写为「✅ 已完稿 + 全部关键读数」，R5 挂载补 **Table S11**、
  R3 挂载补 **Table S8**、R4 挂载补 **Table 3b**、R6 挂载补 **Table S7**；
- 骨架 §7 撰写顺序把 Results 整项勾掉，下一批改为 **Discussion D1–D3 → Introduction → D4/D6 → Abstract**。

---

## Discussion D1–D4 / D6 完稿 + 08b 补落盘（2026-10-16）

**① 正文进度：Discussion 全部完稿（D1–D6）。** 新增 `manuscript/Discussion_D1_D4_D6_中英对照.md`
（D1 主要发现 / D2 与既往比较 / D3 差距来源与政策含义 / D4 优势与创新 / D6 结论；D5 为既有独立文件）。
至此 **Methods（2.1–2.7）+ Results（R1–R6）+ Discussion（D1–D6）全部完稿**，正文仅剩 Introduction、Abstract 与声明段。

**② 代码改动：`08b_fig2_sample.R` 新增一行落盘（本轮唯一代码改动）。**
- 新增产物 **`output/Fig2b_exposure_summary.csv`**：Results R2 引用的 **61.7%（自报达 WHO 指南，加权）**
  与 **51.1%（设备低于 TMREL，加权）** 此前**只打印在控制台**，不满足「正文每个引用数字都有落盘出处」的最严口径。
- 落盘列：`metric / pct_weighted / n_unweighted / w_sum / threshold / threshold_unit`；实际值
  **61.7123** 与 **51.1106**（未加权 n 均 = 7,854；阈值 600 MET-min/wk / 13,222.0729 MIMS/day）。
- 加 `stop()` 守卫两处：`nrow(d1)` 或 `nrow(d2)` 为 0、以及 `rate_sr`/`rate_dv` 非有限值时中止。
- **交叉表派生的 67.0% / 23.4% / 29.2% 未重复落盘** —— 它们可由 `Fig2c_crosstab_weighted.csv`
  （已落盘、受清单覆盖）直接复算，无需第二份来源。
- 影响（**实测已确认**，run_id `20261016_223342`，6.2 分钟）：清单 **323 → 324**；`98` 总体
  **PASS 199 / WARN 0 / FAIL 0**；E 层「一致 309 / 不一致 0 / 豁免 14 / **新增 1** / 消失 0」，
  且**新增项恰为 `output/Fig2b_exposure_summary.csv`**（逐行比对 manifest 确认）。
  本轮不触碰 04/05 系列，故 `data/bop/rr_table.csv`、`bop_rr_draws.rds`、`Table5_bop_*`(6)、
  `PREVIEW_module3_s1p_*`(5) 共 **13/13 SHA-256 三重一致**（基线清单 == 当前清单 == 磁盘实算）；
  14 项豁免中 11 个 PDF 经「对应同名 PNG 逐字节一致」**11/11** 验证，确属仅内嵌时间戳差异。

**③ D2 的一处外部引用（须进参考文献表）**：
Katzmarzyk PT, Friedenreich C, Shiroma EJ, Lee IM. *Br J Sports Med* 2022;56(101–106)，
DOI **10.1136/bjsports-2020-103640** —— 全球 **7.2%**（全因）/ **7.6%**（心血管）死亡归因于不活动，168 国。
本文 **17.4%** 约为其 **2.4 倍**（0.174 / 0.072 = 2.417），与「GBD 现报的 5.7 倍」**分母不同、不可互换**。

---

## Introduction P1–P4 完稿（2026-10-16）—— 正文主体全部完成，本轮纯写作零代码改动

**交付**：`manuscript/Introduction_P1_P4_中英对照.md`（P1 现状 / P2 测量偏离 / P3 止步点 / P4 三模块目标；
`**English.**` 投稿正文 + `**中文.**` 对照，文末附 7 行一致性核对表 + 5 条易错点 + 可复现性留痕）。

**撰写中查出的一处骨架读数无出处（重要）**：

- 骨架 §1 P2 原挂载「Table 1 末两行（自报 MET-min 升 **48%** vs 设备 MIMS 升 **35%**）」——
  **全库无产物出处**（产物/代码/日志/正文均检索无此口径）。
- 最接近的可算量是 `Table1_baseline_manuscript.csv` 的 **Q4/Overall**：自报 4,570/3,079 = **+48.4%**、
  设备 17,994/13,332 = **+35.0%** —— 数值吻合但"最高四分位 vs 全样本"的对比方法学上
  不如 R2 三个读数（67.0% / 23.4% / 1,477 MIMS/day）直接。
- **处置**：正文 P2 改用全部有落盘出处的三读数；骨架 §1 已在原挂载处标注弃用；
  若日后确需 48/35 对比，须先在 `09_tables.R` 落盘 + `10_captions.R` 登记后再引。

**Introduction 的引用占位键**（投稿排版时替换为编号）：
`[GBD2023]`、`[Ekelund2019]`、`[Tarp2024]`、`[Katzmarzyk2022]`（已核实，Katzmarzyk 见 Discussion D2 节登记）+
**`[方法先例]`**（原骨架"铅论文"，指"用模型化/客观暴露替代自报暴露的 GBD 先例"）——
**唯一未定引用**，待导师指明文献或删除该引用键（正文该句陈述不依赖它）。已列入骨架 §7 待办。

**池规模口径再确认**：`data/bop/rr_table.csv` 共 **6** 个 study 组，但 `UKB_wrist_CVD` 仅入心血管曲线，
全因池化曲线由 **5** 个数据集构成（Ekelund2019_harmonised / Moore2012_nci_pool / PURE2017_17countries /
Tarp2024_harmonised / UKB_wrist_general）——Introduction P4 写「five cohort data sets」，与 M2、D2 一致。

**骨架同步**：§0 预算表（Introduction ✅）、§0 已完稿一览（+Introduction）、§1 四段加 ✅ 与实写词数、
§7 顺序表（Introduction 结清；Abstract 为下一批）。

## Abstract + Title 完稿（2026-10-16）—— 正文全链收官，本轮纯写作零代码改动

**交付**：`manuscript/Abstract_结构化_中英对照.md` —— 结构化 4 段（Background / Methods / Results / Conclusions），
**EN 345 词**（区间 250–350；分段 54 / 125 / 121 / 45）+ 中文对照 + 8 组关键词 +
**建议 Title（14 词）**「Device-calibrated physical activity and global attributable burden: a three-module
recomputation of GBD 2023」+ Running head（38 字符）+ 10 行一致性核对表 + 6 条易错点。

**摘要的六条约束（写作时落实）**：
1. 不出现「真实负担」措辞 —— 只能写「设备校准后的归因负担估计」（与关键方法学约束一致）；
2. 5.7 倍必须带限定（"以设备暴露替代自报暴露后的重算结果"，且差距已由两项口径选择完全解释）；
3. 残差 SD 只报 **3,335**（`sd(residuals)`，Module 3 卷积实际用 σ），不报 lm 版 3,337；
4. 池规模写 "five device-based cohort data sets"（全因池 = 5，`UKB_wrist_CVD` 仅入 CVD 曲线）；
5. 摘要不带引用键 → `[方法先例]` 未定引用不影响摘要；
6. **摘要为正文数字的唯一副本**：R5/D1/D3 若改动须回改摘要（核对表 10 项）。

**词数控制留痕**：初稿 364 词（超限）→ 两轮压缩（Background 55→54、Methods 132→125、Results 128→121、
Conclusions 49→45）→ **345 词**。若目标期刊限 250 词，压缩顺序：Methods 细节 → Results 敏感性句。

**骨架同步**：§0 预算表（Title ✅ 建议稿 / Abstract ✅ 345 词）、§0 已完稿一览（+Abstract + Title）、
§7 顺序表（Abstract 结清，仅剩声明与补充材料）。

**正文全局状态**：Methods 2.1–2.7 + Results R1–R6 + Discussion D1–D6 + Introduction P1–P4 + Abstract **全部完稿**。
剩余：声明与补充材料（§9：作者/单位/通讯、基金号与致谢、伦理声明、预印本）、Title 确认、`[方法先例]` 引用。

## 声明与补充材料草稿（2026-10-16）—— 正文写作收官，本轮纯写作零代码改动

**交付**：`manuscript/声明与补充材料_草稿_中英对照.md` —— 10 节（Ethics / Consent / Data / Code / Funding /
Competing interests / Author contributions / Acknowledgements / Reporting guidelines / Supplementary material），
可填部分已写实，**5 处 `【待用户输入】`**（伦理机构与豁免、数据仓库地址、基金号、作者与单位/通讯、
COI+致谢+清单提交）已在文末单列成表。

**写作中查出一处骨架不实表述（已更正）**：骨架 §5 原写「Supplementary material：Table S1–S12 + **Fig S1–S2**」——
全库检索确认 **不存在编号补充图**；`output/CAPTIONS_figures_tables.md` 的补充材料节只有 **12 张补充表（S1–S12）**。
唯一图件类补充内容是 `Fig5d_waterfall_by_region`（8 地区小倍数分解图）→ 已在草稿中登记为**可选 Fig S1**，
做法（需 `06_manifest.R` 加 `figures/` 镜像 + 补图注）与"当前不升格"的默认处置一并留档。

**报告规范**：草稿按 **STROBE**（队列）+ **GATHER**（全球健康估计）双声明撰写，是否随稿提交清单待用户确认。

**可填部分依据**：Data availability ← NCHS 公开 + GBD Results Tool；Code availability ← `00_run_all.R` 编排 +
`98_verify_reproducibility.R` 五层核验 + `REPRODUCIBILITY_REPORT.txt` + 种子 20261011 + 模块 3 确定性口径。

**骨架同步**：§5 三行改写（补充材料更正 + 报告规范 + 草稿已出标注）。

**正文全局状态**：Methods 2.1–2.7 + Results R1–R6 + Discussion D1–D6 + Introduction P1–P4 + Abstract + 声明草稿
**全部完稿**。剩余仅**用户输入**（5 项）与 2 项确认（Title、`[方法先例]` 引用）。

## 关键方法学约束（不要绕过）

- 所有描述统计与模型**必须**带抽样权重与设计变量（`WTMEC4YR`、`SDMVPSU`、`SDMVSTRA`）。
- **主暴露用连续指标**（`mims_per_day`、`peak30`），因为 MIMS 目前**没有**外部验证的 MVPA 切点；切点只做敏感性分析并如实报告判别力。
- **RR 不得从美国人群直接外推全球**，必须经 Part B 的 BoP 池化（含地区异质性与测量方法协变量）。
- 结论措辞为「**设备校准后的归因负担估计**」，不要写成「真实负担」。
