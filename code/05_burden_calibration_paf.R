# =============================================================================
# 05_burden_calibration_paf.R
# Module 1 后半（校准）+ Module 2（证据合成骨架）+ Module 3（PAF 与负担重算）
# 输出：Fig 4、Fig 5、Table 3、Table 4
# =============================================================================

# ---- 统一引导（勿改）：locale 修复 + 加载 00_setup.R（提供 ROOT/DIR_*/PA_SEED）----
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
})
if (!isTRUE(getOption("PA_SETUP_DONE"))) {
  .ps <- NULL
  for (.c in c("00_setup.R", file.path(getwd(), "00_setup.R"),
               file.path(dirname(gsub("\\\\", "/", sub("^--file=", "",
                 grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))), "00_setup.R"))) {
    if (!is.null(.c) && nzchar(.c) && file.exists(.c)) { .ps <- normalizePath(.c); break }
  }
  if (is.null(.ps)) stop("未找到 00_setup.R：请 setwd() 到 code/ 目录后重试")
  source(.ps); rm(.ps, .c)
}

suppressPackageStartupMessages({
  library(data.table); library(tidyverse)
})
# 贝叶斯部分（Part B）需要：library(brms) 或 library(cmdstanr)
# ROOT / DIR_DERIV / DIR_GBD / DIR_OUT 由 00_setup.R 统一提供

adm <- readRDS(file.path(DIR_DERIV, "analytic.rds")); setDT(adm)

# =============================================================================
# Part A. 自报 <-> 设备 校准（Module 1 核心）
# =============================================================================
cal <- adm[!is.na(met_min_wk) & !is.na(mims_per_day) & RIDAGEYR >= 25]

# A1. 设备指标 ~ 自报 MET-min（含年龄/性别交互）
m_cal <- lm(mims_per_day ~ splines::ns(met_min_wk, 3) + age * female, data = cal)
sink(file.path(DIR_OUT, "Table3_calibration.txt")); print(summary(m_cal)); sink()

# A2. TMREL 的设备等效值 + 单调化校准函数
#    ⚠️ 口径（GBD 2023）：LPA case definition 为「25 岁以上、每领域每次 ≥10 min、
#       总 MET-min/周 < 3600–4400」（来源：GBD 2023 风险因素定义，JACC 2025 复述）。
#       旧的 3000–4500 是 GBD 2021 口径，勿再使用。
#    ℹ️ MET 阈值取自 00_setup.R §7b（跨脚本单一真源）—— 04 的曲线参照点也用它，
#       避免"04 用占位分位、05 用 TMREL"的口径分裂。
tmrel_lo_met <- TMREL_LO_MET; tmrel_hi_met <- TMREL_HI_MET

# ⚠️ 实测缺陷（2026-10-11，真实数据）：`ns(met, 3)` 是自然样条，在数据范围两端会**回折**
#    → 直接拿它做 MET→MIMS 映射会得到**非单调**曲线（本机自检：range 11950–14919 内非单调），
#    并且把整个分布压进一个窄带，严重扭曲 PAF。
#    修法：在细网格上取 cummax() 强制单调不减，再用 approx 插值；同时保留残差 SD 以恢复离散度。
MET_CAP   <- max(cal$met_min_wk, na.rm = TRUE) * 1.5
MET_ANCH  <- seq(0, MET_CAP, length.out = 2000)
.pm_raw   <- function(met) {
  nd <- data.frame(met_min_wk = met, age = median(cal$age), female = 0)
  as.numeric(predict(m_cal, newdata = nd))
}
.pm_mono  <- cummax(.pm_raw(MET_ANCH))
pred_mims <- function(met) approx(MET_ANCH, .pm_mono, xout = met, rule = 2)$y
SIGMA_MIMS <- sd(residuals(m_cal))   # 条件分布残差 SD（同方差假定）

tmrel_lo_mims <- pred_mims(tmrel_lo_met)
tmrel_hi_mims <- pred_mims(tmrel_hi_met)

# --- 漂移断言：重算值必须与 00_setup.R §7b 登记的常量一致 ---------------------
#   这两个值同时被 04 用作曲线参照锚点，必须**同一口径**。若校准数据/口径变了
#   而常量未同步，此处立即失败（而不是让 04 与 05 悄悄用两个不同的锚点）。
{
  tol <- 1e-6
  d_lo <- abs(tmrel_lo_mims - TMREL_LO_MIMS)
  d_hi <- abs(tmrel_hi_mims - TMREL_HI_MIMS)
  d_sg <- abs(SIGMA_MIMS - SIGMA_MIMS_REF)
  if (d_lo > tol || d_hi > tol || d_sg > tol) {
    stop(sprintf(paste0(
      "TMREL 设备等效值已漂移，00_setup.R §7b 的常量过期：\n",
      "  tmrel_lo_mims  重算 %.10f vs 常量 %.10f  (Δ=%.3g)\n",
      "  tmrel_hi_mims  重算 %.10f vs 常量 %.10f  (Δ=%.3g)\n",
      "  SIGMA_MIMS     重算 %.10f vs 常量 %.10f  (Δ=%.3g)\n",
      "  请把 00_setup.R 的 TMREL_LO_MIMS / TMREL_HI_MIMS / SIGMA_MIMS_REF ",
      "更新为重算值后重跑（04 的参照锚点会随之更新）。"),
      tmrel_lo_mims, TMREL_LO_MIMS, d_lo,
      tmrel_hi_mims, TMREL_HI_MIMS, d_hi,
      SIGMA_MIMS, SIGMA_MIMS_REF, d_sg))
  }
}
message(sprintf("TMREL %g-%g MET-min/wk -> 设备等效 %.1f - %.1f MIMS/day（中 %.1f；校准 R2=%.2f, 残差 SD=%.1f）",
                tmrel_lo_met, tmrel_hi_met, tmrel_lo_mims, tmrel_hi_mims,
                (tmrel_lo_mims + tmrel_hi_mims) / 2,
                summary(m_cal)$r.squared, SIGMA_MIMS))
# 与 04 的参照锚点一致性核对（04 已先跑，产物在 output/）
{
  fa <- file.path(DIR_OUT, "Table2_reference_anchor.csv")
  if (file.exists(fa)) {
    a <- data.table::fread(fa, encoding = "UTF-8")
    a <- a[exposure == "mims_per_day"]
    if (nrow(a) == 1L && abs(a$ref_val[1] - TMREL_MID_MIMS) > 1e-6)
      stop(sprintf("04 的曲线参照锚点（%.4f）≠ TMREL 设备等效中点（%.4f）——口径分裂",
                   a$ref_val[1], TMREL_MID_MIMS))
    message(sprintf("  锚点一致性核对：04 与 05 同用 %.4f MIMS/day ✓",
                    TMREL_MID_MIMS))
  }
}

# A3. 报告偏倚因子：自报"达 600 MET-min/wk"者的设备活动量 vs 未达者的差值
b <- cal[, .(mims_mean = mean(mims_per_day, na.rm = TRUE),
             n = .N), by = .(meets_600 = met_min_wk >= 600)]
fwrite(b, file.path(DIR_OUT, "Table3_reporting_bias.csv"))

# A4. 暴露分布 f(x)（供 PAF 用）—— 设备尺度的连续分布
# ---------------------------------------------------------------------------
# ⚠️ 关键事实（2026-10-11 核对 GBD 2023 官方暴露文件后确认）：
#   `IHME_GBD_2023_RISK_EXPOSURE_LOW_PHYSICAL_ACTIVITY_Y2025M10D10.CSV`
#   （80.9 万行）里 measure **只有 "continuous" 一种**，给的是
#   **MET-min/周 的均值**（mean + lower/upper 95% UI）。
#   → 它**既没有 4 分档比例（inactive/low/moderate/high），也没有暴露分布的 SD**。
#   而 GBD 计算 PAF 需要 5 个输入，其中第 2 个明确就是
#   "the standard deviation of the exposure distribution"（JACC 2025 对 GBD 2023 方法学的复述）。
#   → SD 必须另找来源，**不能凭空设定后当作已知**，否则整条重算链失效。
#
# SD 的四条闭合路径（2026-10-14 更新；详见 data/gbd/GBD2023_下载指南.md
# 与 data/gbd/capstone/S1_核查报告.md）：
#   (S1)  ❌ **已排除** —— Capstone 附录 2 只在正文描述方法
#         （ln(SD)=b0+b1*ln(MEAN)+b2*Age+b3*SR+b4*Fem），既不给系数、
#         也不给 per-cell 数值表 → **无法据此复算 GBD 的精确 SD**
#         （逐页核查结论：S1「部分成立」）；
#   (S1′) ⭐ **已实现**（本文件 Part A5）—— 照 GBD 公布的方法形式，
#         在 NHANES 本土数据上自估 SD–mean 关系，
#         得到 cell 级 CV(mean, age, sex)，取代原来的"凭空假定 CV"；
#   (S2)  向 IHME 索取：data@healthdata.org
#         （若成功，可替换 S1′ 并做一致性比对）；
#   (S3)  以外部大样本调查估计 CV，作为**明示的假定**分布参数，
#         并强制做敏感性分析（见 EXPO_SD_GRID）。
#   ⚠️ 接入点：`95_module3_paf.R` 的 PA_CV_MODE=grid（默认，S3 网格）|
#      s1p（S1′ cell 级查表）。两者产物文件名不同，互不覆盖。
# ---------------------------------------------------------------------------
EXPO_CV      <- NA_real_                        # 保留占位：S1′ 起 CV 改为 cell 级查表
EXPO_SD_GRID <- c(0.40, 0.50, 0.60, 0.80, 1.00) # S3 敏感性网格（主链默认口径）
EXPO_SHAPE   <- "lognormal"                     # GBD 连续型暴露常用右偏分布
#
# 🔴 待定的设计决策（必须在跑 Module 3 前定稿并写进 Methods）：
#   本机实测校准模型 R² 仅 ≈0.19（自报 MET-min/周 对设备 MIMS 解释力很弱，符合文献 r≈0.3–0.4）。
#   后果：把 GBD 各国 MET 分布经「条件均值」映射到设备尺度后，
#   **国别间差异会被大幅压缩**（各国设备分布趋同），而国别异质性正是 Fig 5 的核心卖点。
#   两个可选口径（择一并做敏感性分析）：
#     (M1) 条件均值 + 残差混合（当前实现）：保留个体离散度，但压缩国别差异；
#     (M2) **分位数–分位数映射（保秩）**：y_c(p) = F_y^{-1}( F_met( Q_met^c(p) ) )，
#          用 NHANES 的 (met, mims) 经验联合分布做保秩变换 —— 按构造保留国别排序与差异。
#   建议主分析用 M2、敏感性用 M1，并在 Methods 说明校准的固有不确定性。
# ---------------------------------------------------------------------------

# 由「均值 + CV」构造设备尺度分布 f(x)
#   两步映射（关键：不能用条件均值直接映射，否则会抹掉个体离散度）：
#     ① MET 尺度：截断对数正态 f_met(met)，参数由 mean_met 与 CV 定
#     ② 设备尺度：f_device(y) = Σ_i f_met(met_i) × N(y | pred_mims(met_i), SIGMA_MIMS)
#        —— 条件分布混合，保留 GBD 国家间差异 + NHANES 个体内残差两个来源的变异。
exposure_dist <- function(mean_met, cv, n_met = 301, n_mims = 301,
                          met_cap = MET_CAP,
                          mims_cap = max(adm$mims_per_day, na.rm = TRUE) * 1.2) {
  if (!is.finite(cv) || cv <= 0)
    stop("需要有效的 CV —— 请先落实 SD 来源（S1/S2/S3），不要用默认值硬跑。")
  if (!is.finite(mean_met) || mean_met <= 0) stop("mean_met 无效")

  sdlog <- sqrt(log(1 + cv^2)); mulog <- log(mean_met) - sdlog^2 / 2
  met <- seq(0, met_cap, length.out = n_met)
  f_met <- dlnorm(met, mulog, sdlog); f_met[met <= 0] <- 0
  if (sum(f_met) <= 0) stop("MET 密度全为 0：检查 mean_met / cv")
  f_met <- f_met / sum(f_met)

  y   <- seq(0, mims_cap, length.out = n_mims)
  mus <- pred_mims(met)
  D   <- outer(y, mus, function(yy, mm) dnorm(yy, mean = mm, sd = SIGMA_MIMS))
  f   <- as.numeric(D %*% f_met); f <- f / sum(f)

  list(mims = y, f = f, met = met, f_met = f_met,
       mean_mims = sum(y * f), sigma_cond = SIGMA_MIMS)
}

# =============================================================================
# Part A5. S1′：暴露分布 SD 的本土自估（2026-10-14 新增）
# -----------------------------------------------------------------------------
# 【为什么需要 S1′】
#   GBD 2023 Risk Factors Capstone 的 Supplementary appendix 2（PDF p.378）
#   **只描述方法、不公开参数**：
#       ln(SD) = b0 + b1*ln(MEAN_i) + b2*Age_i + b3*SR_i + b4*Fem_i
#       "...we applied the coefficients of this regression ... to calculate the
#        standard deviation by country, year, age, and sex."
#   —— 系数（b0–b4）与 per-cell SD 数值表都没给；同章 p.368 还显示连续型
#   暴露（Low BMD）用的是 minimal CV 约束（global 0.1 / super-region 0.06 /
#   region 0.08），说明 GBD 的暴露离散度是**建模产物**、不随结果发布。
#   （逐页核查见 data/gbd/capstone/S1_核查报告.md）
#   → 因此"照抄 GBD 的 SD"这条路不存在；可行的是**照它的方法形式在本土
#     数据上自估**，即 S1′。
#
# 【S1′ 的口径】
#   · 函数形式与 GBD 完全同构（唯一省略 SR —— 单国样本无法识别区域项）；
#   · cell 定义与 GBD 一致：5 岁年龄组 × 性别；
#   · 数据：NHANES 2011–2014 加速度计子样本（analytic.rds，25 岁及以上）；
#   · 权重：NHANES 4 年 MEC 权重 WTMEC4YR，贴合 GBD 的
#     "nationally representative" 口径；同时给出未加权结果备查。
#
# 【两个尺度（互为交叉验证）】
#   scale="met"    ：因变量 = 自报 MET-min/周 的 cell 内 SD
#                    —— 与 GBD 的 SD 同尺度（GBD 也是在调查自报数据上回归）
#   scale="device" ：因变量 = 加速度计 MIMS/day 的 cell 内 SD
#                    —— 用于验证"经 M1 校准映射后设备尺度的离散度"是否与
#                       加速度计实测离散度自洽（两条独立证据的一致性检查）
# =============================================================================

SD_AGE_BREAKS <- c(25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, Inf)  # 12 组
SD_MIN_CELL_N <- 20L

# GBD 暴露包的 age_group_id -> NHANES 5 岁组序号（1..12）
#   10..20  = 25-29 … 75-79（11 组）
#   30/31/32/235 = 80-84 / 85-89 / 90-94 / 95+  -> **全部截断到上限组**
#   ⚠️ 截断是刻意为之：NHANES 2011–2014 的 RIDAGEYR 在 80 处 topcode，
#      对 85+ 外推等于把年龄效应线性延伸 3 个 5 岁组，风险大于收益。
#      该映射会显式落盘（Table3_sd_mean_age_map.csv），便于审稿复核。
SD_GBD_AGE2IDX <- c(`10` = 1L, `11` = 2L, `12` = 3L, `13` = 4L, `14` = 5L,
                    `15` = 6L, `16` = 7L, `17` = 8L, `18` = 9L, `19` = 10L,
                    `20` = 11L, `30` = 12L, `31` = 12L, `32` = 12L, `235` = 12L)

fit_sd_mean_relation <- function(dat = adm, scale = c("met", "device"),
                                 weighted = TRUE, min_n = SD_MIN_CELL_N) {
  scale <- match.arg(scale)
  ycol  <- if (scale == "met") "met_min_wk" else "mims_per_day"
  wcol  <- "WTMEC4YR"
  d <- as.data.table(dat)
  miss <- setdiff(c("RIDAGEYR", ycol, "female", wcol), names(d))
  if (length(miss)) stop("fit_sd_mean_relation 缺列：", paste(miss, collapse = ", "))

  d <- d[!is.na(RIDAGEYR) & RIDAGEYR >= 25 & !is.na(get(ycol))]
  if (!nrow(d)) stop("fit_sd_mean_relation：25+ 无有效观测")
  d[, agegrp := cut(RIDAGEYR, breaks = SD_AGE_BREAKS, right = FALSE, labels = FALSE)]
  d <- d[!is.na(agegrp)]
  d[, wgt := if (weighted) fifelse(is.na(get(wcol)) | get(wcol) <= 0, 0, get(wcol)) else 1]

  wm <- function(x, w) sum(w * x) / sum(w)
  ws <- function(x, w) { m <- wm(x, w); sqrt(sum(w * (x - m)^2) / sum(w)) }

  cells <- d[wgt > 0,
             .(n = .N, mean_y = wm(get(ycol), wgt), sd_y = ws(get(ycol), wgt)),
             by = .(agegrp, female)][order(agegrp, female)]

  fc <- cells[n >= min_n & is.finite(mean_y) & mean_y > 0 &
                is.finite(sd_y) & sd_y > 0]
  if (nrow(fc) < 8L)
    stop("fit_sd_mean_relation：可用 cell 仅 ", nrow(fc), " 个，不足以拟合")
  fc[, `:=`(ln_sd = log(sd_y), ln_mean = log(mean_y), age_idx = as.numeric(agegrp))]

  m  <- lm(ln_sd ~ ln_mean + age_idx + female, data = fc)
  cf <- coef(m)

  pred_sd <- function(mean_y, age_idx, female)
    exp(as.numeric(cf[["(Intercept)"]] + cf[["ln_mean"]] * log(mean_y) +
                     cf[["age_idx"]] * as.numeric(age_idx) + cf[["female"]] * female))

  cells[, cv      := sd_y / mean_y]
  cells[, cv_pred := pred_sd(mean_y, as.numeric(agegrp), female) / mean_y]

  list(scale = scale, weighted = weighted, lm = m, coef = cf,
       r2 = summary(m)$r.squared, n_cell = nrow(fc), cells = cells,
       pred_sd = pred_sd,
       cv_min = min(cells$cv_pred, na.rm = TRUE),
       cv_max = max(cells$cv_pred, na.rm = TRUE))
}

SD_FIT <- list(
  met_w    = fit_sd_mean_relation(adm, "met",    weighted = TRUE),
  met_u    = fit_sd_mean_relation(adm, "met",    weighted = FALSE),
  device_w = fit_sd_mean_relation(adm, "device", weighted = TRUE),
  device_u = fit_sd_mean_relation(adm, "device", weighted = FALSE)
)

# 落盘：系数表 + cell 级明细 + 年龄映射登记
{
  cf_tab <- rbindlist(lapply(names(SD_FIT), function(k) {
    f <- SD_FIT[[k]]
    data.table(model = k, scale = f$scale, weighted = f$weighted,
               term = names(f$coef), estimate = as.numeric(f$coef),
               r2 = f$r2, n_cell = f$n_cell,
               cv_min = f$cv_min, cv_max = f$cv_max)
  }))
  fwrite(cf_tab, file.path(DIR_OUT, "Table3_sd_mean_relation_coefs.csv"))

  cell_tab <- rbindlist(lapply(names(SD_FIT), function(k) {
    d <- copy(SD_FIT[[k]]$cells); d[, model := k]; d
  }), fill = TRUE)
  fwrite(cell_tab, file.path(DIR_OUT, "Table3_sd_mean_relation_cells.csv"))

  fwrite(data.table(age_group_id = names(SD_GBD_AGE2IDX),
                    nh_mims_agegrp_idx = as.integer(SD_GBD_AGE2IDX),
                    note = "GBD 85+ 组截断到 NHANES 上限组(80+)"),
         file.path(DIR_OUT, "Table3_sd_mean_age_map.csv"))
}

message(sprintf(paste0(
  "S1' 拟合完成（NHANES 25+，cell = 5 岁组 x 性别）：\n",
  "  · MET   加权   ：CV %.3f-%.3f  (R2=%.3f, %d cells)   <- 主轨\n",
  "  · MET   未加权 ：CV %.3f-%.3f  (R2=%.3f)\n",
  "  · 设备  加权   ：CV %.3f-%.3f  (R2=%.3f)\n",
  "  · 设备  未加权 ：CV %.3f-%.3f  (R2=%.3f)"),
  SD_FIT$met_w$cv_min,    SD_FIT$met_w$cv_max,    SD_FIT$met_w$r2,    SD_FIT$met_w$n_cell,
  SD_FIT$met_u$cv_min,    SD_FIT$met_u$cv_max,    SD_FIT$met_u$r2,
  SD_FIT$device_w$cv_min, SD_FIT$device_w$cv_max, SD_FIT$device_w$r2,
  SD_FIT$device_u$cv_min, SD_FIT$device_u$cv_max, SD_FIT$device_u$r2))

# =============================================================================
# Part A6. 25+ 分年龄人口权重（2026-10-14 新增）
# -----------------------------------------------------------------------------
# 用途：GBD 暴露文件给出的是 **15 个 25+ 年龄组 × 2 性别** 的 cell 级均值
#       （其中没有 population 列）。要合并成"25+ 总体暴露分布"，必须按
#       该 location × year 的 **人口占比** 加权。
#
# 🔎 简单平均为何有偏（方向已实证）：
#   15 个五岁组各占 1/15 权重，但 80+ 占了 4 个组（80-84/85-89/90-94/95+）
#   —— 即把 27% 的权重给了一个实际人口占比通常 <5% 的年龄段；而 80+ 的暴露
#   最低。故简单平均会**系统性低估** 25+ 的暴露均值。
#   实测（s1p 口径）：Global 2022 简单平均 = 2190 MET-min/wk，
#   人口加权 = 2795（+27.6%）；India 2022 为 2823 → 4122（+46%）。
#
# 数据源优先级（均为 location × year × 5 岁组 人口）：
#   (1) data/gbd/population_25plus/  —— 用户从 GBD Results 工具下载的
#       Population（GBD Estimate = Population），与其余 GBD 输入同源，最严谨；
#   (2) data/external/owid_pop5.csv  —— UN WPP 2024（Our World in Data 整理），
#       已随项目落盘。GBD 自身的人口估算亦以 UN WPP 为主要输入，
#       25+ 年龄权重的差异 <1%（Methods 中如实声明来源即可）。
#   (3) 两者皆无 -> 均匀权重 + WARN，并在产物 tag 标注 "noweights"。
#
# 性别维度：OWID 版本只有两性合计。因 GBD 暴露文件本身以 Male/Female 分列、
#           且现有 pop_mean_met() 已按"两性简单平均"约定处理，这里同样把
#           年龄权重在两个性别 cell 之间等分（w_age / 2）。若日后换成 GBD
#           Population（含性别），本函数会自动提供 sex-specific 权重。
# =============================================================================

# GBD location_name -> UN WPP / OWID 的 Entity 名（仅列需要别名的）
POP_LOC_ALIAS <- c(
  "Global"                                = "World",
  "United States of America"              = "United States",
  "Russian Federation"                    = "Russia",
  "Viet Nam"                              = "Vietnam",
  "Iran (Islamic Republic of)"            = "Iran",
  "Republic of Korea"                     = "South Korea",
  "Democratic People's Republic of Korea" = "North Korea",
  "Democratic Republic of the Congo"      = "Democratic Republic of Congo",
  "United Republic of Tanzania"           = "Tanzania",
  "Bolivia (Plurinational State of)"      = "Bolivia",
  "Venezuela (Bolivarian Republic of)"    = "Venezuela",
  "Syrian Arab Republic"                  = "Syria",
  "Lao People's Democratic Republic"      = "Laos",
  "Republic of Moldova"                   = "Moldova",
  "Czechia"                               = "Czech Republic",
  "Eswatini"                              = "Eswatini",
  # ---- 2026-10-15 补 4 条（逐国版 205 国全量核出的缺口；OWID 实体名已逐一确证）----
  # 此前 "Cabo Verde" 映射到自身是**错的**（OWID 用的是 "Cape Verde"）。
  # 这四条若不补，resolve_pop_loc() 会返回 NA → px_cells_s1p() 静默回退「均匀人口权重」，
  # 不报错也不留痕 —— 属静默降级，故在 95c 里另加了「205 国必须全部可解」的硬断言。
  "Cabo Verde"                            = "Cape Verde",
  "Brunei Darussalam"                     = "Brunei",
  "Micronesia (Federated States of)"      = "Micronesia (country)",
  "Timor-Leste"                           = "East Timor",
  "T\u00fcrkiye"                          = "Turkey",
  "C\u00f4te d'Ivoire"                    = "Cote d'Ivoire",
  "Taiwan (Province of China)"            = "Taiwan")

# GBD age_group_id <-> UN WPP / OWID 的 5 岁组列名（95+ 由 95-99 与 100+ 合并）
POP_AGE_COLS <- c(`10` = "25-29 years", `11` = "30-34 years", `12` = "35-39 years",
                  `13` = "40-44 years", `14` = "45-49 years", `15` = "50-54 years",
                  `16` = "55-59 years", `17` = "60-64 years", `18` = "65-69 years",
                  `19` = "70-74 years", `20` = "75-79 years", `30` = "80-84 years",
                  `31` = "85-89 years", `32` = "90-94 years")

pop_norm_loc <- function(x) {
  x <- as.character(x)
  # 折叠变音符号（Türkiye->Turkiye, Côte->Cote），再剥离非字母数字。
  #   · iconv 的 ASCII//TRANSLIT 在个别平台不可用 -> 失败时保守回退原串
  #     （只影响含非 ASCII 的国名；ASCII 名不受影响，故不影响目标 8 国）
  xx <- suppressWarnings(iconv(x, from = "", to = "ASCII//TRANSLIT"))
  bad <- is.na(xx) & !is.na(x); xx[bad] <- x[bad]
  gsub("[^a-z0-9]", "", tolower(xx))
}

# 别名以「归一化键」索引，使 GBD 名里的非 ASCII（如 Türkiye）与
# 人口表的 ASCII 实体名（Turkey）在任意 locale 下都能对上。
POP_LOC_ALIAS_NORM <- local({
  n <- setNames(unname(POP_LOC_ALIAS), pop_norm_loc(names(POP_LOC_ALIAS)))
  n[!duplicated(names(n))]
})

load_pop_weights <- function(years = c("1990", "2022")) {
  yrs <- as.integer(years)

  # ---- (1) GBD Population（用户下载，优先）----
  gbd_dir   <- file.path(DIR_GBD, "population_25plus")
  gbd_files <- if (dir.exists(gbd_dir))
    list.files(gbd_dir, pattern = "\\.csv$", full.names = TRUE,
               recursive = TRUE, ignore.case = TRUE) else character(0)
  if (length(gbd_files)) {
    d <- rbindlist(lapply(gbd_files, function(f) as.data.table(fread(f))), fill = TRUE)
    if (all(c("location_name", "year", "age_group_id", "val") %in% names(d))) {
      w <- d[year %in% yrs & age_group_id %in% as.integer(names(POP_AGE_COLS)) & !is.na(val),
             .(pop = sum(val, na.rm = TRUE)), by = .(location_name, year, age_group_id)]
      if (nrow(w)) {
        w[, w := pop / sum(pop), by = .(location_name, year)]
        message("A6 人口权重来源：GBD Population（", length(gbd_files), " 个文件）")
        res <- w[, .(location_name, year, age_group_id, pop, w)]
        attr(res, "src") <- "gbd_population"
        return(res)
      }
    }
  }

  # ---- (2) UN WPP 2024（OWID 整理）----
  f_owid <- file.path(PA_ROOT, "data", "external", "owid_pop5.csv")
  if (file.exists(f_owid)) {
    d <- as.data.table(fread(f_owid))
    d <- d[Year %in% yrs]
    if (nrow(d)) {
      cols <- unname(POP_AGE_COLS)
      cols <- cols[cols %in% names(d)]
      lng <- melt(d, id.vars = c("Entity", "Year"), measure.vars = cols,
                  variable.name = "age_col", value.name = "pop")
      lng[, age_group_id := as.integer(names(POP_AGE_COLS)[match(age_col, POP_AGE_COLS)])]
      # 95+ = 95-99 + 100+
      if (all(c("95-99 years", "100+ years") %in% names(d))) {
        d95 <- d[, .(Entity, Year, pop = get("95-99 years") + get("100+ years"))]
        d95[, `:=`(age_col = "95+", age_group_id = 235L)]
        lng <- rbind(lng, d95, fill = TRUE)
      }
      lng <- lng[!is.na(age_group_id) & is.finite(pop) & pop > 0]
      lng[, w := pop / sum(pop), by = .(Entity, Year)]
      setnames(lng, c("Entity", "Year"), c("pop_entity", "year"))
      message("A6 人口权重来源：UN WPP 2024（OWID 整理，", nrow(lng), " 行）")
      # ⚠️ 属性必须在**最终返回的子集上**设置 —— data.table 的 `[` 会丢弃 attributes
      out <- lng[, .(pop_entity, year, age_group_id, pop, w)]
      attr(out, "src") <- "un_wpp2024_owid"
      attr(out, "entities") <- unique(out$pop_entity)
      return(out)
    }
  }

  message("A6 人口权重：**无可用人口文件** -> 回退均匀权重（WARN）")
  NULL
}

POP_W <- load_pop_weights()
POP_SRC <- attr(POP_W, "src"); if (is.null(POP_SRC)) POP_SRC <- "none"

# GBD location_name -> 人口表里的实体名（先归一化别名、再归一化直配）
resolve_pop_loc <- function(gbd_name) {
  if (is.null(POP_W)) return(NA_character_)
  ents <- if (!is.null(POP_W$pop_entity)) unique(POP_W$pop_entity) else unique(POP_W$location_name)
  nkey <- pop_norm_loc(gbd_name)
  cand <- POP_LOC_ALIAS_NORM[nkey]
  cand <- if (is.na(cand)) gbd_name else unname(cand)
  if (cand %in% ents) return(cand)
  hit <- ents[pop_norm_loc(ents) == nkey]
  if (length(hit)) return(hit[1])
  NA_character_
}

# =============================================================================
# Part B. 证据合成（Burden of Proof 框架）—— 代码骨架
# =============================================================================
# 目的：池化 NHANES + 外部队列，且显式以"测量方法"为协变量，
#       直接估计「自报 vs 设备」的 RR 系统性差异。
# 输入表结构（每行一个风险估计）：
#   study, design, method(self|device), device_type, wear_site,
#   metric_definition, exposure_center, outcome, logrr, se_logrr, n_cases
#
# 模型（示例，brms）：
#   logrr | se(se_logrr, sigma = TRUE) ~ method + s(exposure_center, by = method) +
#       (1 | study) + device_type + wear_site
# 说明：这是"以测量方法为协变量"的 BoP 式贝叶斯 meta-regression，
#       不是 MR-BRT（后者是 GBD 的数据交叉校验工具，用途不同）。

bop_skeleton <- function(dat_rr) {
  if (!requireNamespace("brms", quietly = TRUE)) {
    message("未安装 brms，跳过 Part B（需要时 install.packages('brms')）"); return(NULL)
  }
  library(brms)
  brm(bf(logrr | se(se_logrr, sigma = TRUE) ~
           method + s(exposure_center, by = method) + (1 | study) + device_type),
      data = dat_rr,
      prior = c(set_prior("normal(0, 1)", class = "b"),
                set_prior("student_t(3, 0, 1)", class = "sd")),
      chains = 4, iter = 4000, cores = 4, seed = 20261011)
}

# =============================================================================
# Part C. PAF 与归因负担重算（Module 3）
# =============================================================================
# 反事实 PAF:  PAF = sum_x P(x)(RR(x)-1) / (1 + sum_x P(x)(RR(x)-1))
paf_from_dist <- function(px, rr_x) {
  num <- sum(px * (rr_x - 1))
  num / (1 + num)
}

# C0b. 批量 PAF —— RR 后验曲线矩阵版（确定性，无抽样）
#   输入 rr_mat：n_curve × n_off，**每一行**是一条与 px$mims 同网格对齐的后验 RR 曲线。
#   返回长度 n_curve 的向量（每条曲线对应的 PAF）。
#   恒等式：sum(px * (rr - 1)) = rr %*% px - sum(px)，故一次矩阵乘法即得全部曲线
#   （比逐条调用 paf_from_dist 快约 2 个数量级；95c 有 ~205 location × 2 年 × 多情景）。
paf_from_dist_mat <- function(px, rr_mat) {
  rr_mat <- as.matrix(rr_mat)
  num <- as.vector(rr_mat %*% as.numeric(px)) - sum(px)
  num / (1 + num)
}

# C1. GBD 侧读入
# ⚠️ 文件名规则已修正（2026-10-11）：官方整包文件名是
#    `IHME_GBD_2023_RISK_EXPOSURE_LOW_PHYSICAL_ACTIVITY_Y2025M10D10.CSV`
#    —— 既不以 risk 开头，扩展名还是大写 `.CSV`。
#    旧版 `list.files(pattern = "^risk.*csv$")` **永远匹配不到**（静默返回 NULL）。
#    改为按 **内容关键字 + 忽略大小写** 匹配，因此原始文件**不需要改名**。
# 归档目录排除（2026-10-14 新增）
#   `data/gbd/_archive_*/` 下放的是**已退役**的历史版本（如 D2 决策前的
#   All ages 分母）。因为 find_gbd()/find_gbd_role() 都是 recursive 扫描，
#   若不排除，归档文件会与新版（25+ 分母）并存 → 同键不同 age → PAF 分母
#   被**静默重复计入**（inflation ≈ 分母翻倍），且不报任何错。
#   约定：路径中任一层目录名以 `_archive` 开头即视为归档，一律忽略。
gbd_not_archived <- function(fs)
  fs[!grepl("[/\\\\]_archive", as.character(fs), ignore.case = TRUE)]

find_gbd <- function(...) {
  keys <- c(...)
  # recursive = TRUE：Results 工具导出的是「一目录一文件」结构
  #   （data/gbd/IHME-GBD_2023_DATA-<hash>-1/IHME-GBD_2023_DATA-<hash>-1.csv），
  #   非递归会直接漏掉。见下方 classify_gbd_file()。
  fs <- list.files(DIR_GBD, full.names = TRUE, recursive = TRUE, ignore.case = TRUE)
  fs <- gbd_not_archived(fs)
  fs <- fs[grepl("\\.csv$", fs, ignore.case = TRUE) &
             !grepl("TABLE_INDEX", fs, ignore.case = TRUE)]
  if (!length(fs)) return(character(0))
  hit <- vapply(basename(fs), function(b)
    any(vapply(keys, function(k) grepl(k, b, ignore.case = TRUE), logical(1))), logical(1))
  fs[hit]
}

# ---------------------------------------------------------------------------
# 按**内容**识别 GBD 文件角色
#   为什么不能靠文件名：Results 工具导出的文件名是自动生成的
#   `IHME-GBD_2023_DATA-<hash>-1.csv`（且放在同名子目录里），既不含
#   `risk_lpa` 也不含 `cause_totals` —— 任何基于文件名的匹配都会漏。
#   → 改为读表头 + 判别 key 列的内容，与文件名/目录结构完全解耦。
# ---------------------------------------------------------------------------
classify_gbd_file <- function(f) {
  hdr <- tryCatch(names(fread(f, nrows = 0)), error = function(e) NULL)
  if (is.null(hdr) || !length(hdr)) return(NA_character_)

  # (a) GHDx 整包暴露文件：含 age_group_id 且只有 mean/lower/upper
  if (all(c("mean", "age_group_id") %in% hdr)) return("lpa_exposure_pack")

  # (b) Results 工具导出（标准 20 列结构）
  if (all(c("measure_name", "cause_name", "val") %in% hdr)) {
    # Risk factor 估计 → rei_name 有非空值（如 "Low physical activity"）
    # Cause 估计      → 同样有 rei_name 列，但值为空 → 据此区分批次 1 / 批次 2
    if ("rei_name" %in% hdr) {
      rv <- tryCatch(unique(fread(f, select = "rei_name")[[1]]),
                     error = function(e) character(0))
      rv <- rv[!is.na(rv) & nzchar(as.character(rv))]
      if (length(rv)) return("lpa_attributable")
    }
    return("cause_totals")
  }
  "other"
}

# 按角色取文件（可能返回多个分片）
find_gbd_role <- function(role) {
  fs <- list.files(DIR_GBD, full.names = TRUE, recursive = TRUE, ignore.case = TRUE)
  fs <- gbd_not_archived(fs)          # 排除 data/gbd/_archive_*（已退役版本）
  fs <- fs[grepl("\\.csv$", fs, ignore.case = TRUE) &
             !grepl("TABLE_INDEX", fs, ignore.case = TRUE)]
  if (!length(fs)) return(character(0))
  fs[vapply(fs, function(f) identical(classify_gbd_file(f), role), logical(1))]
}

# 双通道取文件：先按文件名关键字（GHDx 整包这类名字有意义的），
# 再按内容角色（Results 工具导出）。两者取并集，避免任一规则失效即静默漏文件。
gbd_expo  <- find_gbd("LOW_PHYSICAL_ACTIVITY", "risk_exposure")   # 整包：暴露均值
gbd_risk  <- find_gbd_role("lpa_attributable")                    # Results 批次1：归因负担（Deaths/DALYs 两个分片）
gbd_cause <- find_gbd_role("cause_totals")                        # Results 批次2：cause 总负担（PAF 分母）

message(sprintf("GBD 文件识别：暴露整包 %d 个 | 归因负担 %d 个分片 | cause 总负担 %d 个分片",
                length(gbd_expo), length(gbd_risk), length(gbd_cause)))
if (!length(gbd_risk))
  message("  · 提示：data/gbd/ 下未识别到『Risk factor』结果文件（批次 1 尚未下载？）")
if (!length(gbd_cause))
  message("  · 提示：data/gbd/ 下未识别到『Cause』结果文件（批次 2 尚未下载，PAF 分母缺失）")

# ---------------------------------------------------------------------------
# 分片合并读取
#   Results 工具有 10 万行上限，同一批次常被拆成多个 CSV
#   （见 data/gbd/GBD2023_下载指南.md「分片下载方案」）。
#   本函数把同一批次的所有分片**纵向拼接**，并做重叠自检：
#   若同一 (cause × measure × location × age × sex × year) 出现在两个分片里，
#   PAF 分母会被重复计入 → 必须报警而不是静默放过。
# ---------------------------------------------------------------------------
read_gbd_shards <- function(files, label = "gbd") {
  files <- as.character(files)
  files <- files[!is.na(files) & file.exists(files)]
  if (!length(files)) return(NULL)

  ds <- lapply(files, function(f) {
    d <- as.data.table(fread(f))
    d[, .shard := basename(f)]
    d
  })
  d <- rbindlist(ds, fill = TRUE)

  if (length(files) > 1L) {
    cand <- c("cause_name", "measure_name", "location_name", "age_name",
              "sex_name", "year")
    use <- intersect(cand, names(d))
    if (length(use)) {
      k <- do.call(paste, c(as.list(d[, ..use]), sep = "|"))
      nb <- length(unique(k))
      if (nb != nrow(d))
        warning(sprintf(paste0("[%s] 分片间存在重复维度键：%d 行 vs %d 个唯一键。",
                               "重叠会让 PAF 分母被重复计入，",
                               "请核对各分片的 Location/Year/Sex 范围是否互斥。"),
                        label, nrow(d), nb), call. = FALSE)
    }
  }
  pa_log(sprintf("[%s] 合并 %d 个分片 -> %d 行", label, length(files), nrow(d)))
  d[]
}

# 暴露文件读入 + 口径修正
#   实测（本机 2026-10-11）：Global 男性 1990 各年龄组均值为
#     25-29 = 4177 … 75-79 = 1728，而 All Ages(22) = 1605、Age-standardized(27) = 1780，
#   两者都显著低于 25+ 各年龄组 → **不能用于 LPA**（LPA 定义仅覆盖 25 岁以上）。
#   必须使用 25+ 的 5 岁年龄组（10–20、30、31、32、235）。
read_lpa_exposure <- function(f = gbd_expo) {
  if (!length(f)) return(NULL)
  d <- fread(f[1])
  if (!all(c("mean", "age_group_id") %in% names(d))) return(d)  # Results 工具格式，直接返回
  d[!age_group_id %in% c(22, 27)]
}

# ---------------------------------------------------------------------------
# LPA 归因结局清单
#   权威来源 = Results 工具「Estimate = Risk factor → Risk = Low physical activity」
#   下载文件里实际出现的 cause（工具会把 Cause 框自动锁定为该风险的 risk–outcome pair）。
#   故下面的硬编码清单**只作兜底**；Batch1 文件在位时以文件内的 cause 为准。
#
#   ⚠️ 2026-10-11 更正：GBD 2021 起 LPA 的 risk–outcome pair 已由 5 类扩展为 8 类
#      （Lancet 2024;403(10440):2162–2203），GBD 2023 沿用。
#      旧清单不仅少 3 类，还有两处**名称本身是错的**：
#        "Diabetes mellitus type 2" → GBD cause 名就是 "Diabetes mellitus"（不分型）
#        "Ischemic stroke"          → GBD 2021 起为 "Stroke" 整体
# ---------------------------------------------------------------------------
LPA_CAUSES_FALLBACK <- c(
  "Ischemic heart disease",
  "Stroke",                                       # GBD 2021 起为 Stroke 整体（非仅缺血性）
  "Diabetes mellitus",                            # GBD cause 名不分型
  "Chronic kidney disease",                       # GBD 2021 新增
  "Lower extremity peripheral arterial disease",  # GBD 2021 新增
  "Colon and rectum cancer",
  "Breast cancer",
  "Tuberculosis"                                  # GBD 2021 新增
)

# 归一化名称，用于容忍大小写/标点差异（GBD 工具各处命名并不完全一致）
norm_cause <- function(x) gsub("[^a-z0-9]+", " ", tolower(as.character(x)))

# 从 Batch1（归因负担文件）自动提取真实 cause 清单；失败则回退到兜底清单
derive_lpa_causes <- function(x = NULL, fallback = LPA_CAUSES_FALLBACK) {
  read_causes <- function(f) tryCatch({
    hdr <- names(fread(f, nrows = 0))
    cn  <- intersect(c("cause_name", "cause"), hdr)[1]
    if (is.na(cn)) NULL else unique(fread(f, select = cn)[[1]])
  }, error = function(e) NULL)

  cs <- NULL
  if (is.data.frame(x)) {
    cn <- intersect(c("cause_name", "cause"), names(x))[1]
    if (!is.na(cn)) cs <- unique(x[[cn]])
  } else if (is.character(x)) {
    fs <- x[file.exists(x)]
    if (length(fs)) cs <- read_causes(fs[1])
  }
  cs <- cs[!is.na(cs) & nzchar(cs)]
  cs <- cs[norm_cause(cs) != "all causes"]     # 防御：万一误下 All causes
  if (!length(cs)) {
    message("  · 未从检出文件读到 cause 清单（Batch1 尚未下载？），改用内置兜底清单（",
            length(fallback), " 类）")
    return(fallback)
  }
  message("  · 已从检出文件读取真实 cause 清单（", length(cs), " 类）")
  cs
}

LPA_CAUSES <- derive_lpa_causes(gbd_risk)
message(sprintf("LPA 归因结局：%d 个 —— %s",
                length(LPA_CAUSES), paste(LPA_CAUSES, collapse = " | ")))
if (length(LPA_CAUSES) != length(LPA_CAUSES_FALLBACK))
  warning("检出的结局数与 GBD 2021+ 已知的 8 类不一致——请人工核对 Results 工具下拉框。")

# C2. 重算主函数（确定性优先，Monte Carlo 兜底）
#   ⚠️ 调用前请先把 gbd_dt 过滤到目标分层（单一 location × year × age × sex）。
#      若某 cause 在 gbd_dt 中出现多行，函数内会求和并在 >1 行时报警，避免静默出错。
#
#   两条路径由 rr_device_fun() 的**返回类型**决定：
#     · 矩阵（n_curve × n_off）→ 【确定性路径】遍历全部后验曲线。点估计 = PAF 后验
#       均值，区间 = 全部曲线间的 2.5% / 97.5% 分位。方差为 0，跨脚本 / 跨运行严格一致。
#     · 向量（长度 n_off）    → 【Monte Carlo 兼容路径】抽 n_draws 次取均值（旧行为，
#       仅保留给干跑 / 自检脚本与自定义单曲线调用）。
#   2026-10-15 起 make_rr_fun_pooled() 默认走确定性路径；`n_draws` 在确定性路径下被忽略。
recompute_burden <- function(px_device, rr_device_fun, gbd_dt,
                             causes = LPA_CAUSES, n_draws = 1000) {
  gbd_dt <- copy(as.data.table(gbd_dt))
  key <- intersect(c("cause_name", "cause"), names(gbd_dt))[1]
  if (is.na(key))
    stop("gbd_dt 缺少 cause_name/cause 列——请确认传入的是 Results 工具的 Cause 结果文件。")
  gbd_dt[, .cause_key := norm_cause(get(key))]

  # 分母缺失必须显式报错，不得静默丢弃（否则 PAF 分子分母口径不一致）
  miss <- causes[!norm_cause(causes) %in% gbd_dt$.cause_key]
  if (length(miss))
    stop("以下 LPA 归因结局在 cause 总负担文件中找不到，PAF 分母缺失：\n  ",
         paste(miss, collapse = "\n  "),
         "\n→ 请检查 Results 工具批次 2 是否勾选了与批次 1 相同的结局，",
         "\n  且**没有误选 All causes / 父级节点**（父级会改名，导致匹配不上）。")

  # 分母：逐 cause 求和（多行即报警，避免把多个分层静默加在一起）
  den <- rbindlist(lapply(causes, function(cs) {
    dd <- gbd_dt[.cause_key == norm_cause(cs)]
    if (nrow(dd) > 1L)
      warning(sprintf(paste0("cause '%s' 在 gbd_dt 中有 %d 行，已在函数内求和——",
                             "请确认 gbd_dt 已过滤到单一分层（location × year × age × sex）。"),
                      cs, nrow(dd)))
    data.table(cause   = cs,
               d_total = sum(dd$deaths_total, na.rm = TRUE),
               y_total = sum(dd$dalys_total,  na.rm = TRUE))
  }))

  probe <- rr_device_fun()

  if (is.matrix(probe) || is.data.frame(probe)) {
    # ---------- 确定性路径：遍历**全部**后验曲线（方差 0，跨运行严格一致）----------
    paf_v <- paf_from_dist_mat(px_device, probe)
    st <- data.table(cause  = causes,
                     paf_m  = mean(paf_v),
                     paf_lo = quantile(paf_v, .025, names = FALSE),
                     paf_hi = quantile(paf_v, .975, names = FALSE))
    res <- den[st, on = "cause"]
    return(res[, .(cause,
                   deaths_attrib = paf_m * d_total,
                   deaths_lo     = paf_lo * d_total,
                   deaths_hi     = paf_hi * d_total,
                   dalys_attrib  = paf_m * y_total,
                   dalys_lo      = paf_lo * y_total,
                   dalys_hi      = paf_hi * y_total)])
  }

  # ---------- Monte Carlo 兼容路径（rr_device_fun() 返回单条曲线向量）----------
  out <- vector("list", n_draws)
  for (i in seq_len(n_draws)) {
    rr_x <- rr_device_fun()                      # 从 RR 后验抽一条曲线
    r <- den[, .(cause,
                 deaths_attrib = paf_from_dist(px_device, rr_x) * d_total,
                 dalys_attrib  = paf_from_dist(px_device, rr_x) * y_total)]
    r[, draw := i]; out[[i]] <- r
  }
  res <- rbindlist(out)
  res[, .(deaths_attrib = mean(deaths_attrib),
          deaths_lo = quantile(deaths_attrib, .025),
          deaths_hi = quantile(deaths_attrib, .975),
          dalys_attrib = mean(dalys_attrib),
          dalys_lo = quantile(dalys_attrib, .025),
          dalys_hi = quantile(dalys_attrib, .975)),
      by = cause]
}

# C3. 与 GBD 现报值对比（Fig 5a）
# gbd_dt 中直接包含 GBD 2023 对 LPA 的"归因死亡/DALYs"，与 C2 结果并排即可算出低估幅度。

# =============================================================================
# 运行提示
# =============================================================================
message(paste0(
  "05 骨架已就位。执行顺序：\n",
  "  1) 拟合校准模型 A1 -> 得 Table3\n",
  "  2) 用 tmrel_*_mims 回填 04 脚本的 REF_PCT/参照值，重跑 04 得最终 Fig3\n",
  "  3) 收集外部队列 RR 表 -> bop_skeleton() -> 得 RR 后验\n",
  "  4) 读入 GBD 2023 CSV -> recompute_burden() -> Fig5 + Table4\n",
  "     · 分母必须来自「Estimate = Cause」且逐个勾选 LPA 的 ", length(LPA_CAUSES), " 个 Level-3 结局，\n",
  "       ⛔ 不要选 All causes，也不要选父级节点（会污染分母且 cause_name 对不上）。\n",
  "⚠️  切勿把美国人群 RR 直接外推全球：外推必须经 BoP 池化（含地区异质性）后再做。\n",
  "✅ A4 的 SD 来源已闭合（S1′，2026-10-14）：\n",
  "   · S1 核查结论 = Capstone 附录给方法、不给系数、不给数值表 → 不能直接复算（见 data/gbd/capstone/S1_核查报告.md）；\n",
  "   · 故改用 S1′：照 GBD 公布的方法形式 ln(SD)=β0+β1·ln(MEAN)+β2·Age+β3·SR+β4·Fem，\n",
  "     在 NHANES 本土加速度计数据上自估 SD–mean 关系 → 逐 cell 查表（fit_sd_mean_relation()，上文 Part A5）。\n",
  "   · S3 网格（EXPO_SD_GRID）保留为敏感性双轨，不再是主分析。"))
