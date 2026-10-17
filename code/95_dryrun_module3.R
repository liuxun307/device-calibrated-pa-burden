# =============================================================================
# 95_dryrun_module3.R
# Module 3（PAF 与归因负担重算）真实数据 dry-run —— 「S3 情景」
# -----------------------------------------------------------------------------
# 目的：在暴露分布 SD 来源未定稿（S1/S2/S3 待用户拍板）之前，
#       用**真实批次 2 数据（PAF 分母）+ 真实 NHANES RR 曲线**把 Module 3
#       全链路跑通一次，产出可直接查看的预览数值，证明机器不是空壳。
#
# 2026-10-12 首次运行结论（重要，写给未来的自己）：
#   ① 机器全链路可跑通（4 个 location×year × 5 个 CV = 20 组 PAF 全部算出）；
#   ② **M1 条件均值映射把国别/年际差异彻底抹平**：Global vs China、1990 vs 2022
#      四个组合的映射后设备均值全部落在 12,859–12,966 MIMS/day（相差 <0.9%），
#      而输入的自报均值差 5%（2158–2275 MET-min/wk）→ 实证坐实了「校准抹平
#      异质性」的担忧，**必须改用 M2（分位数–分位数保秩映射）**，否则 Fig5 无差异可画；
#   ③ 重算 PAF ≈ 21–22%，GBD 现报 ≈ 2–3%；差异主要来自 **RR 占位（all-cause 被
#      套用到 8 个病因）**，而非 SD——CV 0.4→1.0 仅让 PAF 从 0.212 变到 0.220（+4%）。
#      → Module 2（BoP 病因特异性 RR）才是关键路径；SD 的精确值反而是次要的。
#
# ⚠️ 本脚本产物一律标注为「DRYRUN_S3」，**不得**进入正文/图表：
#   · EXPO_CV 为**假定的**外部 CV（S3 敏感性网格），待 S1/S2 落实后替换；
#   · RR 曲线为 NHANES 的 all_cause 占位（Module 2 的 BoP 后验尚未就位）；
#   · 暴露均值按 25+ 各 5 岁组**简单平均**（未做人口加权），待正式版修正。
#
# 依赖：先跑通 01→04（需 output/rr_curves.csv）；GBD 批次1/批次2 已在 data/gbd/
# =============================================================================

# ---- 统一引导：locale + 00_setup.R + 复用 05 的全部函数与对象 ----
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8"))
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
})
if (!isTRUE(getOption("PA_SETUP_DONE"))) {
  .ps <- NULL
  for (.c in c("00_setup.R", file.path(getwd(), "00_setup.R"))) {
    if (!is.null(.c) && nzchar(.c) && file.exists(.c)) { .ps <- normalizePath(.c); break }
  }
  if (is.null(.ps)) stop("未找到 00_setup.R：请 setwd() 到 code/ 目录后重试")
  source(.ps); rm(.ps, .c)
}
suppressPackageStartupMessages({ library(data.table); library(tidyverse) })

# 复用 05：提供 adm / cal / pred_mims / SIGMA_MIMS / exposure_dist /
#          paf_from_dist / find_gbd_role / read_gbd_shards / recompute_burden / LPA_CAUSES
.old_wd <- getwd()
source("05_burden_calibration_paf.R")
setwd(.old_wd)

DRYRUN_TAG <- "DRYRUN_S3"
message("\n==================== Module 3 dry-run（", DRYRUN_TAG, "）= ====================\n")

# ---------------------------------------------------------------------------
# 1. RR 曲线（占位：NHANES all_cause）
# ---------------------------------------------------------------------------
rr_file <- file.path(DIR_OUT, "rr_curves.csv")
if (!file.exists(rr_file))
  stop("缺少 ", rr_file, " —— 请先跑通 01→04。")
rr <- fread(rr_file)
rr_all <- rr[outcome == "all_cause"][order(x)]
rr_cvd <- rr[outcome == "cvd"][order(x)]
if (!nrow(rr_all)) stop("rr_curves.csv 中没有 all_cause 曲线。")
message(sprintf("RR 占位曲线：all_cause %d 点（x %.0f–%.0f MIMS/day, HR %.2f–%.2f）%s",
                nrow(rr_all), min(rr_all$x), max(rr_all$x),
                min(rr_all$hr), max(rr_all$hr),
                if (nrow(rr_cvd)) "  + cvd" else ""))

# 从 RR 曲线构造「按 x 网格取 RR」的抽样函数（log 尺度用 95% UI 反推 SE）
make_rr_fun <- function(curve, x_ref) {
  a <- curve[order(x)]
  se_log <- (log(a$hi) - log(a$lo)) / (2 * 1.959964)
  se_log[!is.finite(se_log)] <- 0
  function() {
    hr_draw <- exp(log(a$hr) + rnorm(length(a$hr), 0, se_log))
    as.numeric(approx(a$x, hr_draw, xout = x_ref, rule = 2)$y)
  }
}

# ---------------------------------------------------------------------------
# 2. GBD 分母（批次2）与 GBD 现报归因值（批次1）
# ---------------------------------------------------------------------------
b2 <- read_gbd_shards(find_gbd_role("cause_totals"), "cause_totals")
b1 <- read_gbd_shards(find_gbd_role("lpa_attributable"), "attributable")
if (is.null(b2)) stop("未识别到批次 2（Cause 总负担）文件，PAF 分母缺失。")
if (is.null(b1)) warning("未识别到批次 1（LPA 归因负担）文件，将无法做『GBD 现报 vs 重算』对比。")

short_meas <- function(x) fifelse(grepl("DALY", x, ignore.case = TRUE), "dalys", "deaths")

build_wide <- function(d, loc, yr, suffix) {
  dd <- d[location_name == loc & year == yr]
  if (!nrow(dd)) return(NULL)
  dd <- dd[, .(cause_name, meas = short_meas(measure_name), val)]
  w <- dcast(dd, cause_name ~ meas, value.var = "val")
  setnames(w, c("deaths", "dalys"),
           c(paste0("deaths_", suffix), paste0("dalys_", suffix)), skip_absent = TRUE)
  w
}

# ---------------------------------------------------------------------------
# 3. 暴露分布（真实 GBD 均值 + 假定 CV）
# ---------------------------------------------------------------------------
expo <- read_lpa_exposure(gbd_expo)
if (is.null(expo)) stop("未读到暴露包。")

pop_mean_met <- function(loc, yr) {
  em <- expo[location_name == loc & year_id == yr]
  if (!nrow(em)) return(NA_real_)
  if ("sex" %in% names(em)) {
    eb <- em[sex %in% c("Both", "both")]
    if (nrow(eb)) em <- eb else em <- em[sex %in% c("Male", "Female")]
  }
  mean(em$mean, na.rm = TRUE)   # 25+ 各 5 岁组简单平均（正式版改人口加权）
}

# ---------------------------------------------------------------------------
# 4. 主循环：location × year × CV 网格
# ---------------------------------------------------------------------------
LOCS  <- c("Global", "China")
YEARS <- c(1990, 2022)
CVS   <- EXPO_SD_GRID            # c(0.40, 0.50, 0.60, 0.80, 1.00)
CV_MAIN <- 0.60                  # 预览主情景

# 参照点（04 中 RR 曲线 = 1 的 x）—— 自适应推断，避免硬编码
REF_X <- rr_all$x[which.min(abs(rr_all$hr - 1))]
message(sprintf("RR 参照点（HR≈1）推断为 %.0f MIMS/day", REF_X))

# 暴露分布诊断：解释 PAF 量级
diag_px <- function(px, loc, yr, cv) {
  rr_pt <- approx(rr_all$x, rr_all$hr, xout = px$mims, rule = 2)$y
  mu    <- px$mean_mims
  sdv   <- sqrt(sum(px$f * (px$mims - mu)^2))
  data.table(location = loc, year = yr, cv = cv,
             mean_mims = mu, sd_mims = sdv,
             median_mims = px$mims[which.min(abs(cumsum(px$f) - 0.5))],
             pct_below_ref = sum(px$f[px$mims < REF_X]),
             mean_rr = sum(px$f * rr_pt),
             implied_paf = { n <- sum(px$f * (rr_pt - 1)); n / (1 + n) })
}

tot_rows <- list(); cause_rows <- list(); diag_rows <- list()
for (loc in LOCS) for (yr in YEARS) {
  mt  <- pop_mean_met(loc, yr)
  w2  <- build_wide(b2, loc, yr, "total")
  if (is.null(w2) || !is.finite(mt)) {
    message(sprintf("  跳过 %s %d（分母或暴露均值缺失）", loc, yr)); next
  }
  # 保证 recompute_burden 需要的列齐备
  for (cc in c("deaths_total", "dalys_total"))
    if (!cc %in% names(w2)) w2[, (cc) := NA_real_]

  for (cv in CVS) {
    px  <- exposure_dist(mean_met = mt, cv = cv)
    rrf <- make_rr_fun(rr_all, px$mims)
    res <- recompute_burden(px$f, rrf, gbd_dt = w2,
                            causes = LPA_CAUSES, n_draws = 400)
    res[, `:=`(location = loc, year = yr, cv = cv, tag = DRYRUN_TAG)]
    cause_rows[[length(cause_rows) + 1L]] <- res
    diag_rows[[length(diag_rows) + 1L]]   <- diag_px(px, loc, yr, cv)
  }
  # 主情景下与 GBD 现报值对比
  px  <- exposure_dist(mean_met = mt, cv = CV_MAIN)
  rrf <- make_rr_fun(rr_all, px$mims)
  res <- recompute_burden(px$f, rrf, gbd_dt = w2, causes = LPA_CAUSES, n_draws = 400)
  w1  <- if (!is.null(b1)) build_wide(b1, loc, yr, "gbd") else NULL

  tot <- data.table(
    location = loc, year = yr, mean_met_wk = mt,
    total_deaths = sum(w2$deaths_total, na.rm = TRUE),
    total_dalys  = sum(w2$dalys_total,  na.rm = TRUE),
    recomputed_deaths = sum(res$deaths_attrib, na.rm = TRUE),
    recomputed_dalys  = sum(res$dalys_attrib,  na.rm = TRUE))
  tot[, `:=`(
    paf_deaths = recomputed_deaths / total_deaths,
    paf_dalys  = recomputed_dalys  / total_dalys)]
  if (!is.null(w1)) {
    tot[, `:=`(gbd_deaths = sum(w1$deaths_gbd, na.rm = TRUE),
               gbd_dalys  = sum(w1$dalys_gbd,  na.rm = TRUE))]
    tot[, `:=`(gbd_paf_deaths = gbd_deaths / total_deaths,
               gbd_paf_dalys  = gbd_dalys  / total_dalys,
               diff_deaths_pct = 100 * (recomputed_deaths / gbd_deaths - 1),
               diff_dalys_pct  = 100 * (recomputed_dalys  / gbd_dalys  - 1))]
  }
  tot[, tag := DRYRUN_TAG]
  tot_rows[[length(tot_rows) + 1L]] <- tot
}

TOT   <- rbindlist(tot_rows, fill = TRUE)
CAUSE <- rbindlist(cause_rows, fill = TRUE)
DIAG  <- rbindlist(diag_rows, fill = TRUE)

# ---------------------------------------------------------------------------
# 5. 落盘 + 打印
# ---------------------------------------------------------------------------
fwrite(TOT,   file.path(DIR_OUT, "DRYRUN_module3_totals.csv"))
fwrite(CAUSE, file.path(DIR_OUT, "DRYRUN_module3_by_cause.csv"))
fwrite(DIAG,  file.path(DIR_OUT, "DRYRUN_module3_exposure_diag.csv"))

cat("\n--- [D] 暴露分布诊断（解释 PAF 量级）---\n")
print(DIAG[, .(location, year, cv,
               mean_mims = round(mean_mims), sd_mims = round(sd_mims),
               median_mims = round(median_mims),
               pct_below_ref = round(pct_below_ref, 3),
               mean_rr = round(mean_rr, 3),
               implied_paf = round(implied_paf, 3))])

cat("\n--- [A] 总量：重算 vs GBD 现报（主情景 CV=", CV_MAIN, "；RR=", "NHANES all_cause 占位）---\n", sep = "")
print(TOT[, .(location, year, mean_met_wk = round(mean_met_wk),
              PAF_recalc = round(paf_deaths, 4), PAF_GBD = round(gbd_paf_deaths, 4),
              deaths_recalc = round(recomputed_deaths),
              deaths_GBD = round(gbd_deaths),
              diff_pct = round(diff_deaths_pct, 1))])

cat("\n--- [B] CV 敏感性（归因死亡总数的变化）---\n")
print(dcast(CAUSE[, .(deaths = sum(deaths_attrib, na.rm = TRUE)),
                  by = .(location, year, cv)],
            location + year ~ cv, value.var = "deaths")[
  , lapply(.SD, function(x) if (is.numeric(x)) round(x) else x)])

cat("\n--- [C] 分病因（", LOCS[1], " ", YEARS[length(YEARS)], "，CV=", CV_MAIN, "）---\n", sep = "")
print(CAUSE[location == LOCS[1] & year == YEARS[length(YEARS)] & abs(cv - CV_MAIN) < 1e-9,
            .(cause, deaths = round(deaths_attrib),
              deaths_lo = round(deaths_lo), deaths_hi = round(deaths_hi))])

cat("\n================================================================\n")
cat("⚠️  以上全部为 ", DRYRUN_TAG, " 预览：\n", sep = "")
cat("   · EXPO_CV 为假定值（S3 网格），待 S1（Capstone 附录）/ S2（IHME 索取）落实后替换；\n")
cat("   · RR 为 NHANES all_cause 占位，待 Module 2（BoP 池化）后验替换；\n")
cat("   · 暴露均值未做人口加权；全部结果不得进入正文/图表。\n")
cat("产物：output/DRYRUN_module3_totals.csv、output/DRYRUN_module3_by_cause.csv\n")
