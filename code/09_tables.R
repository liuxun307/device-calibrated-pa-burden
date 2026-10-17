# =============================================================================
# 09_tables.R —— 投稿表格 Table 1–4（PDF + CSV 双输出）
# -----------------------------------------------------------------------------
# Table 1  基线特征（NHANES 加权，按设备活动量四分位；svymean）
# Table 2  暴露与死亡的 HR：四分位 + 连续 per-IQR，2 结局 x 2 调整集（svycoxph）
# Table 3  校准方程参数 + 报告偏倚因子
# Table 4  重算 vs GBD 2023 现报的归因负担对比（8 地区 x 2 年 x 2 口径）
#
# 输出：figures/tables/Table*.pdf(+png)；output/Table{n}_manuscript*.csv
# 说明：图内/表内文字一律 ASCII；数据全部从既有产物动态读取，不硬编码。
# =============================================================================
t0 <- Sys.time()
source("08_fig_style.R")
pa_log("===== 09 投稿表格 =====")
suppressPackageStartupMessages({ library(survey); library(splines) })
options(survey.lonely.psu = "adjust")

adm <- readRDS(file.path(DIR_DERIV, "analytic.rds")); setDT(adm)
adm[, all_cause := died]; adm[, cvd := cvd_death]

# =============================================================================
# Table 1 —— 基线特征（加权，按 mims_q4）
# =============================================================================
t1d <- adm[!is.na(mims_q4) & !is.na(WTMEC4YR)]
des1 <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC4YR,
                  nest = TRUE, data = as.data.frame(t1d))

row_mean <- function(v, fmt = "%.1f", digits = 1) {
  s <- svyby(as.formula(paste0("~", v)), ~mims_q4, des1, svymean, na.rm = TRUE)
  o <- svymean(as.formula(paste0("~", v)), des1, na.rm = TRUE)
  list(vals = c(sprintf(fmt, coef(o)), sprintf(fmt, coef(s))),
       ses  = c(sprintf(" (%.1f)", SE(o)), sprintf(" (%.1f)", SE(s))))
}
row_pct <- function(v) {
  # 0/1 变量的加权均值即百分比（%）；svyby 的 SE 统一 as.vector 防维度差异
  s <- svyby(as.formula(paste0("~", v)), ~mims_q4, des1, svymean, na.rm = TRUE)
  o <- svymean(as.formula(paste0("~", v)), des1, na.rm = TRUE)
  list(vals = c(sprintf("%.1f", 100 * as.numeric(coef(o))),
                sprintf("%.1f", 100 * as.numeric(coef(s)))),
       ses  = c(sprintf(" (%.1f)", 100 * as.numeric(SE(o))),
                sprintf(" (%.1f)", 100 * as.numeric(SE(s)))))
}
rbind_row <- function(nm, lst) data.table(variable = nm,
  Overall = paste0(lst$vals[1], lst$ses[1]),
  Q1 = paste0(lst$vals[2], lst$ses[2]), Q2 = paste0(lst$vals[3], lst$ses[3]),
  Q3 = paste0(lst$vals[4], lst$ses[4]), Q4 = paste0(lst$vals[5], lst$ses[5]))

t1 <- rbindlist(list(
  rbind_row("Age, years",                  row_mean("age", "%.1f")),
  rbind_row("Female, %",                   row_pct("female")),
  rbind_row("BMI, kg/m2",                  row_mean("bmi", "%.1f")),
  rbind_row("Systolic BP, mmHg",           row_mean("sbp", "%.1f")),
  rbind_row("Poverty-income ratio",        row_mean("pir", "%.2f")),
  rbind_row("Current smoker, %",           row_pct("cur_smoke")),
  rbind_row("Alcohol drinker, %",          row_pct("drink_any")),
  rbind_row("Diabetes, %",                 row_pct("diabetes")),
  rbind_row("Cardiovascular history, %",   row_pct("cvd_hx")),
  rbind_row("Self-reported MET-min/week",  row_mean("met_min_wk", "%.0f")),
  rbind_row("Device MIMS/day",             row_mean("mims_per_day", "%.0f"))
))
# 样本量与死亡（未加权计数）
ns <- t1d[, .(N = fmt_n(.N), Deaths = fmt_n(sum(all_cause, na.rm = TRUE))), by = mims_q4]
t1 <- rbindlist(list(
  data.table(variable = "N", Overall = fmt_n(nrow(t1d)),
             Q1 = ns[mims_q4 == "Q1", N], Q2 = ns[mims_q4 == "Q2", N],
             Q3 = ns[mims_q4 == "Q3", N], Q4 = ns[mims_q4 == "Q4", N]),
  data.table(variable = "Deaths", Overall = fmt_n(sum(t1d$all_cause, na.rm = TRUE)),
             Q1 = ns[mims_q4 == "Q1", Deaths], Q2 = ns[mims_q4 == "Q2", Deaths],
             Q3 = ns[mims_q4 == "Q3", Deaths], Q4 = ns[mims_q4 == "Q4", Deaths]),
  t1))
fwrite(t1, file.path(DIR_OUT, "Table1_baseline_manuscript.csv"), bom = TRUE)
save_table_pdf(t1, "Table1_baseline",
  title = "Table 1. Baseline characteristics of NHANES 2011-2014 adults with valid accelerometry, by device-measured activity quartile",
  footnote = paste0("Weighted means (SE) using NHANES MEC 4-year weights; N and Deaths are unweighted counts. ",
                    "Q1 = lowest activity quartile. Deaths are counted among the ",
                    fmt_n(sum(!is.na(t1d$died))), " participants with linked mortality follow-up; ",
                    fmt_n(nrow(t1d) - sum(!is.na(t1d$died))), " participants had no mortality linkage and ",
                    "contribute to N only."),
  width = 11)

# =============================================================================
# Table 2 —— HR：四分位 + 连续 per-IQR（2 结局 x 2 调整集）
# =============================================================================
mod_dt <- copy(adm)[!is.na(surv_mo) & surv_mo > 0]
covars <- c("age","female","race","educ","pir","bmi","sbp","cur_smoke","drink_any","diabetes","cvd_hx")
for (v in c("mims_per_day", intersect(covars, names(mod_dt)), "WTMEC4YR")) mod_dt <- mod_dt[!is.na(get(v))]

# ---- 样本口径定义表落盘（2026-10-16 新增）-----------------------------------
# 背景：Table 1 描述「完整协变量限制之前」的设备样本（t1d，7,854 人），
#   Table 2 的模型跑在 mod_dt（完整案例集，7,007 人）上 —— 两者此前在图注里
#   都被称作 "modelling sample"，属口径混淆（B9）。
# 本表把两段的 N 与死亡数**独立落盘**，使 10_captions.R 能把
#   「Fig 2(a) 流程节点 / 08b」与「本表 / 09」两条推导路径做跨脚本比对。
# 另含一处必须写清的精度细节（此前只在方案手记里，未进产物、也未进图注）：
#   设备样本 7,854 行中，有 **12 行** 的 died / cvd_death / surv_mo 同时缺失
#   （未链接到 NDI 死亡随访）→ 「769 例死亡」的分母实际是 **7,842** 行，
#   而非 7,854。图注若直接写「7,854 人中 769 例死亡」会被审稿人以分母错误质疑。
# 实测（code/tools/_probe_769_denominator.R）：NA 数 12，且 12 行三类字段同缺。
# 2026-10-16 追加两行随访时长：Methods 2.1 / Results R1 正文（manuscript/
#   Methods_2.1_Results_R1_样本与暴露_中英对照.md）需引用「中位随访 81.0 个月
#   = 6.75 年」，此前该值在项目产物中**无处落盘**（只在方案手记里）。按本方案
#   「正文数字一律有产物来源」的原则，在此与样本口径一并落盘。
#   随访时间 = surv_mo（PERMTH_EXM），即 MEC 检查至死亡或至链接截止（2019-12-31）的月数。
# 2026-10-16 再追加一行心血管死亡数：Results R1 与 Discussion L4 均引用
#   「Cox 分析集中 207 例心血管死亡」，该值此前**没有任何产物来源**（只在诊断脚本
#   code/tools/_probe_m21_numbers.R 的控制台里）→ 按同一原则落盘，并与 08b 的
#   Fig2a_flow_numbers.csv（cvd_deaths 列）构成跨脚本独立推导，由 10_captions.R 逐值比对。
SDEF <- data.table(
  item = c("Device sample (aged >= 25, valid accelerometry)",
           "Device sample with linked mortality follow-up",
           "Deaths in the device sample",
           "Cox analysis set (complete covariates and follow-up)",
           "Deaths in the Cox analysis set",
           "Cardiovascular deaths in the Cox analysis set",
           "Median follow-up in the device sample (months)",
           "Median follow-up in the Cox analysis set (months)"),
  n    = c(nrow(t1d), sum(!is.na(t1d$died)), sum(t1d$died, na.rm = TRUE),
           nrow(mod_dt), sum(mod_dt$all_cause, na.rm = TRUE),
           sum(mod_dt$cvd, na.rm = TRUE),
           median(t1d$surv_mo, na.rm = TRUE), median(mod_dt$surv_mo, na.rm = TRUE)),
  note = c("Table 1 的描述对象；= analytic.rds 全量（年龄 >= 25 且加速度计有效）",
           "其中 died / cvd_death / surv_mo 均非缺失者（其余行未链接到死亡随访）",
           "未加权计数；**分母为有随访链接的 7,842 人**，非 7,854",
           "Table 2 的拟合样本；Model 1 与 Model 2 共用同一完整案例集",
           "未加权计数，与 Table 1 的 Deaths 行同口径",
           "cvd_death（UCOD_LEADING 为 1 或 5，即心脏病或脑血管病）；主结局用全因死亡，此为次结局",
           "surv_mo（PERMTH_EXM）中位数；阶段 1 随访至 2019-12-31（IQR 见 Methods 2.1）",
           "阶段 2（完整案例集）的同一量；两段中位数相同（81.0 月 = 6.75 年）"))
fwrite(SDEF, file.path(DIR_OUT, "Sample_definition.csv"), bom = TRUE)

des2 <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC4YR,
                  nest = TRUE, data = as.data.frame(mod_dt))
mod_dt[, q4n := as.integer(mims_q4)]
iqr <- as.numeric(diff(quantile(mod_dt$mims_per_day, c(.25, .75))))

fit_hr <- function(outcome, covs, spec) {
  if (spec == "q4")  fm <- as.formula(paste0("Surv(surv_mo, ", outcome, ") ~ mims_q4 + q4n + ", paste(covs, collapse = " + ")))
  else               fm <- as.formula(paste0("Surv(surv_mo, ", outcome, ") ~ z_iqr + ", paste(covs, collapse = " + ")))
  if (spec == "iqr") environment(fm)$z_iqr <- scale(mod_dt$mims_per_day)[, 1] * 0  # 占位，实际用 per-IQR 变量
  m <- svycoxph(fm, design = des2)
  m
}
# per-IQR 连续暴露（一次性生成，避免公式环境问题）
mod_dt[, mims_iqr := mims_per_day / iqr]
des2 <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC4YR,
                  nest = TRUE, data = as.data.frame(mod_dt))

rows2 <- list()
for (oc in c("all_cause", "cvd")) {
  for (st in c("minima", "full")) {
    covs <- if (st == "minima") setdiff(covars, c("bmi", "sbp")) else covars
    m4 <- svycoxph(as.formula(paste0("Surv(surv_mo, ", oc, ") ~ mims_q4 + ", paste(covs, collapse = " + "))), design = des2)
    s4 <- summary(m4)$coefficients
    # P for trend：单独拟合（q4n 与 mims_q4 完全共线，不能同入一个模型）
    mt <- svycoxph(as.formula(paste0("Surv(surv_mo, ", oc, ") ~ q4n + ", paste(covs, collapse = " + "))), design = des2)
    ptrend <- summary(mt)$coefficients["q4n", "Pr(>|z|)"]
    for (q in c("Q2", "Q3", "Q4")) {
      k <- paste0("mims_q4", q)
      est <- exp(coef(m4)[k]); lo <- exp(coef(m4)[k] - 1.96 * s4[k, "se(coef)"]); hi <- exp(coef(m4)[k] + 1.96 * s4[k, "se(coef)"])
      rows2[[length(rows2) + 1]] <- data.table(
        outcome = oc, model = st, term = q,
        hr = sprintf("%.2f (%.2f, %.2f)", est, lo, hi), p = fmt_p(s4[k, "Pr(>|z|)"]))
    }
    rows2[[length(rows2) + 1]] <- data.table(outcome = oc, model = st, term = "P for trend",
                                             hr = "-", p = fmt_p(ptrend))
    mi <- svycoxph(as.formula(paste0("Surv(surv_mo, ", oc, ") ~ mims_iqr + ", paste(covs, collapse = " + "))), design = des2)
    si <- summary(mi)$coefficients
    est <- exp(coef(mi)["mims_iqr"]); lo <- exp(coef(mi)["mims_iqr"] - 1.96 * si["mims_iqr", "se(coef)"]); hi <- exp(coef(mi)["mims_iqr"] + 1.96 * si["mims_iqr", "se(coef)"])
    rows2[[length(rows2) + 1]] <- data.table(outcome = oc, model = st,
      term = sprintf("Per IQR (%.0f MIMS/day)", iqr),
      hr = sprintf("%.2f (%.2f, %.2f)", est, lo, hi), p = fmt_p(si["mims_iqr", "Pr(>|z|)"]))
  }
}
t2 <- rbindlist(rows2)
t2[, outcome := ifelse(outcome == "all_cause", "All-cause mortality", "Cardiovascular mortality")]
t2[, model := ifelse(model == "minima", "Model 1 (minimally adjusted)", "Model 2 (fully adjusted)")]
fwrite(t2, file.path(DIR_OUT, "Table2_hr_manuscript.csv"), bom = TRUE)
save_table_pdf(t2, "Table2_hazard_ratios",
  title = sprintf("Table 2. Hazard ratios (95%% CI) for device-measured activity (MIMS/day) and mortality, NHANES 2011-2014 (n = %s)", fmt_n(nrow(mod_dt))),
  footnote = "Weighted Cox proportional hazards models (svycoxph); reference = lowest quartile. Model 1 adjusts for age, sex, race, education, poverty-income ratio, smoking, alcohol, diabetes, cardiovascular history; Model 2 additionally adjusts for BMI and systolic blood pressure.",
  width = 9.5)

# =============================================================================
# Table 3 —— 校准方程参数 + 报告偏倚
# =============================================================================
cal <- adm[!is.na(met_min_wk) & !is.na(mims_per_day) & RIDAGEYR >= 25]
m_cal <- lm(mims_per_day ~ splines::ns(met_min_wk, 3) + age * female, data = cal)
cf <- summary(m_cal)$coefficients
t3a <- data.table(
  term = rownames(cf),
  estimate = sprintf("%.2f", cf[, 1]),
  se = sprintf("%.2f", cf[, 2]),
  p = fmt_p(cf[, 4]))
bias <- fread(file.path(DIR_OUT, "Table3_reporting_bias.csv"))
bias[, meets_600 := ifelse(meets_600, "Meets 600 MET-min/wk", "Below 600 MET-min/wk")]
bias[, mims_mean := sprintf("%.0f", mims_mean)]
bias[, n := fmt_n(n)]
setnames(bias, c("meets_600", "mims_mean", "n"), c("Self-reported guideline status", "Device MIMS/day (mean)", "N"))
t3 <- list(a = t3a, b = bias)
fwrite(t3a, file.path(DIR_OUT, "Table3_calibration_coefs_manuscript.csv"), bom = TRUE)
save_table_pdf(t3a, "Table3_calibration_coefficients",
  title = "Table 3. Calibration model: device-measured activity (MIMS/day) regressed on self-reported MET-minutes/week",
  footnote = sprintf("Linear model with natural cubic spline (3 df) on self-reported MET-min/week plus age-by-sex interaction; n = %s. R2 = %.3f; residual SD = %.0f. Monotonicity enforced by cumulative maximum for the MET->MIMS mapping used in Module 3.",
                     fmt_n(nrow(cal)), summary(m_cal)$r.squared, sd(residuals(m_cal))),
  width = 8.5)
save_table_pdf(bias, "Table3b_reporting_bias",
  title = "Table 3 (panel b). Reporting bias: device-measured activity by self-reported guideline status",
  footnote = "Self-reported meeting of the 600 MET-min/week guideline vs device-measured mean activity; the gap quantifies self-report overestimation.",
  width = 8)

# =============================================================================
# Table 4 —— 重算 vs GBD 现报（8 地区 x 2 年）
# =============================================================================
TOT <- fread(file.path(DIR_OUT, "PREVIEW_module3_s1p_totals.csv"), encoding = "UTF-8")
d4 <- TOT[rr_source == "pooled"]
d4[, location := fifelse(location == "United States of America", "USA", location)]
t4 <- d4[order(year, factor(location, levels = c("Global", sort(setdiff(unique(location), "Global"))))),
         .(Year = year, Location = location,
           `PAF (this study)` = sprintf("%.4f", paf_deaths),
           `PAF (GBD 2023)`   = sprintf("%.4f", gbd_paf_deaths),
           `Deaths (this study)` = fmt_n(recomputed_deaths),
           `Deaths (GBD 2023)`   = fmt_n(gbd_deaths),
           `DALYs (this study)`  = fmt_n(recomputed_dalys),
           `DALYs (GBD 2023)`    = fmt_n(gbd_dalys),
           `Fold (deaths)` = sprintf("%.1f", recomputed_deaths / gbd_deaths),
           `Fold (DALYs)`  = sprintf("%.1f", recomputed_dalys / gbd_dalys))]
fwrite(t4, file.path(DIR_OUT, "Table4_burden_manuscript.csv"), bom = TRUE)
save_table_pdf(t4, "Table4_recomputed_vs_gbd",
  title = "Table 4. Low-physical-activity-attributable burden: device-based recomputation vs GBD 2023 reported (pooled RR source)",
  footnote = "Eight study locations, 1990 and 2022. PAF = population-attributable fraction of deaths. Fold = this study / GBD 2023; the fold is a definitional-sensitivity quantity, not a claim of GBD underestimation (see Fig 5d decomposition).",
  width = 12.5, font_size = 7)

# =============================================================================
# Table S4 —— 逐国版（205 location = Global + 204 国），按 SDI 五分位排序
#   底表：output/M3_BYCOUNTRY_totals.csv（由 95c_module3_bycountry.R 产出）
#   · 这是 Table 4 的补充版：Table 4 保持 8 地区（正文主表，可读性优先），
#     逐国全表放补充材料（205 × 2 年 = 410 行）。
#   · 排序键用 quintile_ord（官方切点复算）+ SDI 2022 降序，
#     与 Fig 5(b)(c) 的分层口径一致。
#   · ⚠️ 逐国产物缺失时**不中断** 09（95c 全量需 ~15 min），只跳过并提示。
# =============================================================================
n_s4 <- 0L
f_byc <- file.path(DIR_OUT, "M3_BYCOUNTRY_totals.csv")
if (!file.exists(f_byc)) {
  cat("\n[Table S4] 跳过：未找到 ", basename(f_byc),
      "（请先跑 95c_module3_bycountry.R）\n", sep = "")
} else {
  bc <- fread(f_byc, encoding = "UTF-8")
  bc <- bc[rr_source == "pooled"]
  setorder(bc, year, quintile_ord, -sdi_2022)
  s4 <- bc[, .(
    Year = year,
    `SDI quintile` = quintile,
    `SDI (2022)` = sprintf("%.4f", sdi_2022),
    Location = location,
    `PAF (this study)` = sprintf("%.4f", paf_deaths),
    `PAF (GBD 2023)`   = sprintf("%.4f", gbd_paf_deaths),
    `Deaths (this study)` = fmt_n(recomputed_deaths),
    `Deaths (GBD 2023)`   = fmt_n(gbd_deaths),
    `DALYs (this study)`  = fmt_n(recomputed_dalys),
    `DALYs (GBD 2023)`    = fmt_n(gbd_dalys),
    `Fold (deaths)` = sprintf("%.1f", fold_deaths),
    `Fold (DALYs)`  = sprintf("%.1f", fold_dalys))]
  fwrite(s4, file.path(DIR_OUT, "TableS4_burden_bycountry_manuscript.csv"), bom = TRUE)
  save_table_pdf(s4, "TableS4_recomputed_vs_gbd_bycountry",
    title = "Table S4. Low-physical-activity-attributable burden by country: device-based recomputation vs GBD 2023 reported (pooled RR source)",
    footnote = paste0("All 205 GBD 2023 locations (Global + 204 countries), 1990 and 2022, ordered by SDI quintile ",
                      "(official GBD 2023 cut-points, 2023 SDI) then descending 2022 SDI. ",
                      "PAF = population-attributable fraction of deaths. Fold = this study / GBD 2023; ",
                      "a definitional-sensitivity quantity, not a claim of GBD underestimation (see Fig 5d). ",
                      "Country-level PAF is invariant across the 8 LPA causes under the pooled total-PA RR curve; ",
                      "cause-level differences reside entirely in GBD denominators."),
    width = 13, font_size = 6.5, page_rows = 60)
  n_s4 <- nrow(s4)
  cat(sprintf("\n[Table S4] 逐国表已产出：%d 行（%d location × %d 年）\n",
              nrow(s4), uniqueN(bc$location), uniqueN(bc$year)))
}

cat("\n--- 09 表格完成 ---\n")
cat(sprintf("Table1 %d 行 | Table2 %d 行 | Table3 %d+%d 行 | Table4 %d 行 | TableS4 %d 行\n",
            nrow(t1), nrow(t2), nrow(t3a), nrow(bias), nrow(t4), n_s4))
cat(sprintf("用时 %.1f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
pa_log("09 完成 -> figures/tables/Table*.pdf")
