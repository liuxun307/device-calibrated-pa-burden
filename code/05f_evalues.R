# =============================================================================
# 05f_evalues.R —— E-value 敏感性分析（未测混杂需多强才能推翻结论）
# -----------------------------------------------------------------------------
# 方法：VanderWeele & Ding 2017, Ann Intern Med 167:268-274
#   E = RR + sqrt(RR × (RR − 1))          （RR ≥ 1；RR < 1 时先取倒数）
#   CI 的 E 值取**靠近无效值 1 的那一端**；若 CI 跨过 1 → E(CI) = 1。
#
# 为什么同时给两个口径（这是本脚本的关键设计）
#   ① 直接对 HR 施加（多数文献做法，`E_*_direct`）；
#   ② 先按 VanderWeele 2020, Biometrics 76:1289-1293 的近似把 HR 转成 RR，再算
#        RR ≈ (1 − 0.5^√HR) / (1 − 0.5^√(1/HR))          (`E_*_primary`)
#      本研究的结局**并非罕见**（全死因随访 ~10 年；强度队列 1351/5334 = 25%），
#      此时 HR 会高估 RR → 直接用 HR 算出的 E 值偏大（偏乐观）。
#      取 ② 作为**主口径**（更保守），① 作为对照列一同输出，口径差异透明可查。
#
# 输入（全部为本研究自身的 NHANES 估计，不读任何手工数字）
#   output/Table2_hr_manuscript.csv              腕式 MIMS 总量（M1 主线，Model 1/2）
#   output/Table11_pam_intensity_per_IQR.csv     髋式 counts/min 强度（每 IQR）
#   output/Table11_pam_intensity_quartiles.csv   髋式 counts/min 强度（Q4 vs Q1）
#
# 产物
#   output/Table13_evalues.csv   逐估计的 E 值（含两口径 + 面板分组）
#   logs/evalues.txt             人读报告 + 硬校验结果
# =============================================================================
t0 <- Sys.time()

local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8"))
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
})
if (!isTRUE(getOption("PA_SETUP_DONE"))) {
  .ps <- NULL
  for (.c in c("00_setup.R", file.path(getwd(), "00_setup.R"),
               file.path(dirname(gsub("\\\\", "/", sub("^--file=", "",
                 grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))), "00_setup.R"))) {
    if (!is.null(.c) && nzchar(.c) && file.exists(.c)) { .ps <- normalizePath(.c); break }
  }
  if (is.null(.ps)) stop("未找到 00_setup.R：请 setwd() 到 code/ 目录")
  source(.ps); rm(.ps, .c)
}
suppressPackageStartupMessages(library(data.table))
pa_log("===== 05f E-value 敏感性分析 =====")

# ---------------------------------------------------------------------------
# 1. E-value 核心函数
# ---------------------------------------------------------------------------
#' 单点 E 值（VanderWeele & Ding 2017）
#' RR 与 1 的大小关系不影响 E 的大小（先归一到 ≥1 再算）
evalue_point <- function(rr) {
  if (!is.finite(rr) || rr <= 0) return(NA_real_)
  x <- if (rr < 1) 1 / rr else rr
  x + sqrt(x * (x - 1))
}

#' CI 的 E 值：取靠近无效值 1 的那一端；CI 跨 1 → 1
evalue_ci <- function(lo, hi) {
  if (!is.finite(lo) || !is.finite(hi)) return(NA_real_)
  if (lo <= 1 && hi >= 1) return(1)
  b <- if (abs(log(hi)) < abs(log(lo))) hi else lo
  evalue_point(b)
}

#' HR → RR 近似（VanderWeele 2020, Biometrics 76:1289-1293）
#' HR = 1 时恒为 1；结局非罕见时 HR 高估 RR，此处给出更保守的 RR
hr_to_rr <- function(hr) {
  if (!is.finite(hr) || hr <= 0) return(NA_real_)
  (1 - 0.5^sqrt(hr)) / (1 - 0.5^sqrt(1 / hr))
}

#' 组装一行
mk_row <- function(id, source, panel_group, exposure, exposure_scale, outcome,
                   model, contrast, hr, lo, hi, note = "") {
  rr <- hr_to_rr(hr)
  data.table(
    id = id, source = source, panel_group = panel_group,
    exposure = exposure, exposure_scale = exposure_scale,
    outcome = outcome, model = model, contrast = contrast,
    hr = hr, lo = lo, hi = hi,
    direction = ifelse(hr < 1, "protective", ifelse(hr > 1, "harmful", "null")),
    ci_crosses_null = as.integer(lo <= 1 && hi >= 1),
    rr_approx = rr,
    e_point_primary = vapply(rr, evalue_point, numeric(1)),
    e_ci_primary    = mapply(evalue_ci, hr_to_rr(lo), hr_to_rr(hi)),
    e_point_direct  = evalue_point(hr),
    e_ci_direct     = mapply(evalue_ci, lo, hi),
    note = note)
}

#' 解析 "0.48 (0.34, 0.68)" → c(hr, lo, hi)；失败返回 NA
parse_ci <- function(x) {
  m <- regmatches(trimws(x), regexec("^([0-9.]+)\\s*\\(([0-9.]+)\\s*,\\s*([0-9.]+)\\)$", trimws(x)))
  if (!length(m) || length(m[[1]]) != 4L) return(c(NA_real_, NA_real_, NA_real_))
  as.numeric(m[[1]][2:4])
}

# ---------------------------------------------------------------------------
# 2. 读入（全部程序化，不写死数字）
# ---------------------------------------------------------------------------
f2  <- file.path(DIR_OUT, "Table2_hr_manuscript.csv")
fpi <- file.path(DIR_OUT, "Table11_pam_intensity_per_IQR.csv")
fq  <- file.path(DIR_OUT, "Table11_pam_intensity_quartiles.csv")
for (f in c(f2, fpi, fq)) if (!file.exists(f)) stop("缺少输入：", f)

t2 <- fread(f2, encoding = "UTF-8")
setnames(t2, gsub("^\ufeff", "", names(t2)))
tpi <- fread(fpi, encoding = "UTF-8")
tq  <- fread(fq,  encoding = "UTF-8")

OUT_LAB <- c(died = "All-cause mortality", cvd = "Cardiovascular mortality")

rows <- list()

# ---- 2A. 腕式 MIMS 总量（M1 主线，Table 2）--------------------------------
#     只取两个"最有代表性"的对比：Q4 vs Q1（最大对比）与 Per IQR（连续尺度）
for (mdl in c("Model 1 (minimally adjusted)", "Model 2 (fully adjusted)")) {
  mtag <- if (grepl("^Model 1", mdl)) "M1" else "M2"
  for (oc in c("All-cause mortality", "Cardiovascular mortality")) {
    oshort <- if (grepl("^All", oc)) "AC" else "CVD"
    for (tm in c("Q4", "Per IQR (4879 MIMS/day)")) {
      r <- t2[outcome == oc & model == mdl & term == tm]
      if (!nrow(r)) stop("Table2 缺行：", oc, " | ", mdl, " | ", tm)
      if (nrow(r) > 1L) stop("Table2 行不唯一：", oc, " | ", mdl, " | ", tm)
      v <- parse_ci(r$hr[1])
      if (anyNA(v)) stop("Table2 HR 解析失败：", r$hr[1])
      ttag <- if (tm == "Q4") "Q4vQ1" else "perIQR"
      rows[[length(rows) + 1L]] <- mk_row(
        id = sprintf("M1_wrist_%s_%s_%s", oshort, mtag, ttag),
        source = "M1 (NHANES 2011-2014, wrist MIMS, total PA)",
        panel_group = "volume_wrist",
        exposure = "Total PA (wrist MIMS, 7-day average)",
        exposure_scale = if (tm == "Q4") "Q4 vs Q1" else "per IQR (4,879 MIMS/day)",
        outcome = OUT_LAB[[if (grepl("^All", oc)) "died" else "cvd"]],
        model = mdl, contrast = tm, hr = v[1], lo = v[2], hi = v[3],
        note = sprintf("Table 2 原始行; p=%s", r$p[1]))
    }
  }
}

# ---- 2B. 髋式 counts/min 强度维度（Table 11；vol-adj = 04e 的 M1 模型）------
#     volume-adj       = 已调整总活动量 → 回答"强度是否携带独立信息"
#     not volume-adj   = 未调整 → 作为对照（大部分信号由体量解释）
pit <- list(
  list(x = "peak30_per_day", lab = "Peak-30 (counts/min)", short = "PEAK30"),
  list(x = "mvpa_per_day",   lab = "MVPA >= 2020 cpm (min/day)", short = "MVPA")
)
for (xx in pit) {
  for (oc in c("died", "cvd")) {
    oshort <- if (oc == "died") "AC" else "CVD"
    for (adj in c(TRUE, FALSE)) {
      atag <- if (adj) "voladj" else "unadj"
      agrp <- if (adj) "intensity_independent" else "intensity_unadjusted"
      # 每 IQR
      r <- tpi[exposure == xx$x & outcome == oc & volume_adjusted == adj]
      if (!nrow(r)) stop("Table11_per_IQR 缺行：", xx$x, "|", oc, "|", adj)
      iqr_lab <- sprintf("per IQR (%.1f %s)", r$iqr[1],
                         if (xx$x == "peak30_per_day") "counts/min" else "min/day")
      rows[[length(rows) + 1L]] <- mk_row(
        id = sprintf("%s_%s_perIQR_%s", xx$short, oshort, atag),
        source = "03b/04e (NHANES 2003-2006, hip ActiGraph 7164 counts/min)",
        panel_group = agrp,
        exposure = xx$lab, exposure_scale = iqr_lab,
        outcome = OUT_LAB[[oc]], model = if (adj) "M1 (volume-adjusted)" else "M0 (volume-unadjusted)",
        contrast = "per IQR", hr = r$hr_per_iqr[1], lo = r$lo[1], hi = r$hi[1],
        note = sprintf("n=%d, events=%d, p=%.3g", r$n[1], r$n_event[1], r$p[1]))
      # Q4 vs Q1
      rq <- tq[exposure == xx$x & outcome == oc & volume_adjusted == adj & quartile == "Q4"]
      if (!nrow(rq)) stop("Table11_quartiles 缺行：", xx$x, "|", oc, "|", adj)
      rows[[length(rows) + 1L]] <- mk_row(
        id = sprintf("%s_%s_Q4vQ1_%s", xx$short, oshort, atag),
        source = "03b/04e (NHANES 2003-2006, hip ActiGraph 7164 counts/min)",
        panel_group = agrp,
        exposure = xx$lab,
        exposure_scale = sprintf("Q4 vs Q1 (Q4 range %s)", rq$q_range[1]),
        outcome = OUT_LAB[[oc]], model = if (adj) "M1 (volume-adjusted)" else "M0 (volume-unadjusted)",
        contrast = "Q4 vs Q1", hr = rq$hr[1], lo = rq$lo[1], hi = rq$hi[1],
        note = sprintf("n=%d, p=%.3g", rq$n[1], rq$p[1]))
    }
  }
}

EV <- rbindlist(rows)

# ---------------------------------------------------------------------------
# 3. 硬校验（不通过就报错，绝不静默输出）
# ---------------------------------------------------------------------------
chk <- list()
# 行数：2A = 2 模型 × 2 结局 × 2 对比 = 8；2B = 2 指标 × 2 结局 × 2 体量调整 × 2 对比 = 16；合计 24
chk$n_rows <- nrow(EV) == 24L
chk$hr_range <- all(EV$hr > 0.05 & EV$hr < 2)
chk$ci_order <- all(EV$lo <= EV$hr & EV$hr <= EV$hi)
# E 值恒 ≥ 1（保底：至少需要 1 倍强度的混杂）
chk$e_ge1 <- all(EV$e_point_primary >= 1 - 1e-12, EV$e_point_direct >= 1 - 1e-12)
# CI 的 E 值不超过点的 E 值
chk$e_ci_le_point <- all(EV$e_ci_primary <= EV$e_point_primary + 1e-9) &&
                     all(EV$e_ci_direct  <= EV$e_point_direct  + 1e-9)
# CI 跨 1 ⇔ E(CI) == 1
chk$cross_iff_1 <- all((EV$ci_crosses_null == 1L) == (abs(EV$e_ci_primary - 1) < 1e-12))
# 保守口径：RR 近似后 |log RR| ≤ |log HR|（HR 对 RR 的放大方向正确）
chk$rr_shrinks <- all(abs(log(EV$rr_approx)) <= abs(log(EV$hr)) + 1e-9)
# 主口径应比直接口径更保守（E 更小）
chk$primary_conservative <- all(EV$e_point_primary <= EV$e_point_direct + 1e-9)
# 锚点核对（防止上游表被静默改写）
#   ⚠️ 这三个值随 04e 的**模型口径**变化，是"上游没被悄悄改动"的哨兵：
#      2026-10-15 统一体量口径后（RCS/per-IQR/四分位三处都改用 ns(counts,4)，
#      且 per-IQR 改由 RCS 自身提取），强度侧两个锚点由
#        0.629641076652226 (peak-30, 线性体量+线性强度)
#        1.06497602671951  (MVPA,   线性体量+线性强度)
#      变为新值。这不是漂移，是有意的口径修正 —— 见 04e 头部说明。
anch <- EV[id %in% c("M1_wrist_AC_M2_Q4vQ1", "PEAK30_AC_perIQR_voladj", "MVPA_AC_perIQR_voladj")]
chk$anchor <- nrow(anch) == 3L &&
  abs(anch[id == "M1_wrist_AC_M2_Q4vQ1"]$hr - 0.48) < 1e-6 &&
  abs(anch[id == "PEAK30_AC_perIQR_voladj"]$hr - 0.78342879124404197) < 1e-9 &&
  abs(anch[id == "MVPA_AC_perIQR_voladj"]$hr - 0.68215352302951704) < 1e-9

bad <- names(chk)[!unlist(chk)]
if (length(bad)) stop("E-value 硬校验失败：", paste(bad, collapse = ", "))

EV[, e_point_primary := round(e_point_primary, 4)]
EV[, e_ci_primary    := round(e_ci_primary, 4)]
EV[, e_point_direct  := round(e_point_direct, 4)]
EV[, e_ci_direct     := round(e_ci_direct, 4)]
EV[, rr_approx       := round(rr_approx, 4)]
fwrite(EV, file.path(DIR_OUT, "Table13_evalues.csv"))

# ---------------------------------------------------------------------------
# 4. 人读报告
# ---------------------------------------------------------------------------
sink(file.path(DIR_LOGS, "evalues.txt"))
cat("===== E-value 敏感性分析报告（05f）=====\n")
cat("生成时间：", format(Sys.time()), "\n\n")
cat("方法：VanderWeele & Ding 2017, Ann Intern Med 167:268-274\n")
cat("      E = RR + sqrt(RR*(RR-1))，RR<1 时先取倒数；CI 端取靠近 1 者，跨 1 → E=1\n")
cat("主口径：先按 VanderWeele 2020, Biometrics 76:1289-1293 把 HR 近似为 RR\n")
cat("        RR = (1 - 0.5^sqrt(HR)) / (1 - 0.5^sqrt(1/HR))\n")
cat("        → 结局非罕见时更保守；对照列为直接对 HR 施加的结果\n\n")
cat("—— 全部估计 ——\n")
print(EV[, .(id, panel_group, hr, lo, hi,
             E_pt = e_point_primary, E_ci = e_ci_primary,
             E_pt_direct = e_point_direct, E_ci_direct = e_ci_direct)])
cat("\n—— 硬校验 ——\n")
for (k in names(chk)) cat(sprintf("  %-22s %s\n", k, if (isTRUE(chk[[k]])) "PASS" else "FAIL"))
cat("\n—— 关键结论 ——\n")
g <- EV[panel_group == "intensity_independent" & endsWith(id, "perIQR_voladj")]
for (i in seq_len(nrow(g)))
  cat(sprintf("  %-28s HR/CI = %.3f (%.3f, %.3f) → E(点) = %.2f，E(CI 近零点) = %.2f\n",
              g$id[i], g$hr[i], g$lo[i], g$hi[i], g$e_point_primary[i], g$e_ci_primary[i]))
sink()

pa_log(sprintf("05f 完成 -> Table13_evalues.csv（%d 行，硬校验 %d/%d PASS；%.1f s）",
               nrow(EV), sum(unlist(chk)), length(chk),
               as.numeric(difftime(Sys.time(), t0, units = "secs"))))
