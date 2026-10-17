# =============================================================================
# 03d_wrist_criterion_variants.R
# 腕式（NHANES 2011-2014）**有效日判据全谱**暴露构建
# -----------------------------------------------------------------------------
# 与 03c 配对：03c 换的是髋侧的「wear 判定算法」，本脚本换的是腕侧的「有效日判据」。
# 两边一起做，才能回答「部位效应矛盾」到底是不是判定口径造成的。
#
# 现状（02 的口径）：
#   有效日 = 质量恒等式 OK 且 PAXWWMD >= 600（**清醒佩戴**分钟，来自 CDC 的 PAXPREDM）
#   暴露   = 有效日 PAXMTSD 均值（PAXMTSD = 当天「有效分钟」的 MIMS 三轴和）
# 而髋侧是「全天佩戴 >= 600 min」——
#   两边不只是**算法**不同（Choi 2011 vs PAXPREDM），**窗口语义**也不同（全天 vs 清醒）。
#
# 判据全谱（全部只用已落盘的 PAXDAY_G/H 日级文件，零下载；每人仍需 >=4 个有效日）
#   C0_wake600        : PAXWWMD >= 600                          —— 现状（基准）
#   C1_allwear600     : PAXWWMD + PAXSWMD >= 600                —— **全天佩戴**，语义向髋侧对齐
#   C2_wake720        : PAXWWMD >= 720                          —— 更严的清醒门槛
#   C3_valid600_qual  : PAXVMD >= 600 且 PAXQFD == 0            —— 改用「有效分钟总数」+ 质量
#   C4_allwear600_qual: PAXWWMD + PAXSWMD >= 600 且 PAXQFD == 0 —— 全天佩戴 + 质量
#   C5_allwear600_d6  : C1 且有效日 >= 6 天                     —— 更严的日数
#   C6_allwear600_d7  : C1 且有效日 == 7 天                     —— 最严的日数
#
# ⚠️ 已声明的局限（必须写进论文）：
#   本脚本**无法**重算腕侧的 wear 本身 —— 那需要分钟级 MIMS（PAXMIN_G/H，8.13 + 9.35 GB），
#   实测 ftp.cdc.gov 带宽仅 28.6 KB/s（→ 约 170 小时），PhysioNet 的 1440 宽表需登录。
#   因此腕侧的「有信号即佩戴」等**信号级**规则无法施加；这里只能改**日级聚合判据**
#   （清醒 vs 全天、门槛 600 vs 720、质量标记、日数），并且暴露仍沿用 PAXMTSD 口径。
#   髋侧（03c）则做到了信号级规则全谱。两侧合起来覆盖了矛盾的绝大部分可能通道。
#
# 输出
#   data/derived/wrist_criterion_variants.rds
#   output/QC_wrist_criteria.csv
#   output/QC_wrist_C0_equivalence.csv     与 02/03（analytic.rds）的 C0 等价性核验
# =============================================================================

# ---- 统一引导 -----------------------------------------------------------------
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
suppressPackageStartupMessages({ library(data.table); library(tidyverse); library(haven) })
pa_log("===== 03d 腕式有效日判据全谱（7 套）=====")

MIN_WAKE_MIN_PER_DAY <- 10 * 60
MIN_AGE              <- 25

CRITS <- c("C0_wake600", "C1_allwear600", "C2_wake720", "C3_valid600_qual",
           "C4_allwear600_qual", "C5_allwear600_d6", "C6_allwear600_d7")
rd    <- function(f) { p <- file.path(DIR_DERIV, paste0(f, ".rds")); if (file.exists(p)) readRDS(p) else NULL }

# =============================================================================
# 1. PAXDAY（G+H）→ 日级；质量校验与 02 逐字一致
# =============================================================================
day_list <- lapply(c("G", "H"), function(cy) {
  f <- file.path(DIR_RAW, sprintf("PAXDAY_%s.xpt", cy))
  if (!file.exists(f)) stop("缺少 ", f, "：请先运行 01_fetch_data.R")
  as.data.table(haven::read_xpt(f))
})
DAY <- rbindlist(day_list, use.names = TRUE, fill = TRUE)

DAY[, qc_sum_ok   := (PAXWWMD + PAXSWMD + PAXNWMD + PAXUMD) == PAXVMD]
DAY[, qc_range_ok := PAXVMD <= PAXTMD & PAXTMD <= 1440 & PAXVMD >= 0]
DAY[, allwear_min := PAXWWMD + PAXSWMD]
qc_sum <- data.table(
  n_rows              = nrow(DAY),
  pct_sum_violation   = round(100 * mean(!DAY$qc_sum_ok,   na.rm = TRUE), 3),
  pct_range_violation = round(100 * mean(!DAY$qc_range_ok, na.rm = TRUE), 3),
  pct_missing_PAXMTSD = round(100 * mean(is.na(DAY$PAXMTSD)), 3))
print(qc_sum)

base_ok <- DAY$qc_sum_ok & DAY$qc_range_ok          # 两套判据共用的硬前提

CRIT_DEF <- list(
  C0_wake600         = list(day = !is.na(DAY$PAXWWMD) & DAY$PAXWWMD >= MIN_WAKE_MIN_PER_DAY,           min_d = 4L),
  C1_allwear600      = list(day = !is.na(DAY$allwear_min) & DAY$allwear_min >= MIN_WAKE_MIN_PER_DAY,    min_d = 4L),
  C2_wake720         = list(day = !is.na(DAY$PAXWWMD) & DAY$PAXWWMD >= 720,                             min_d = 4L),
  C3_valid600_qual   = list(day = !is.na(DAY$PAXVMD) & DAY$PAXVMD >= MIN_WAKE_MIN_PER_DAY & DAY$PAXQFD == 0, min_d = 4L),
  C4_allwear600_qual = list(day = !is.na(DAY$allwear_min) & DAY$allwear_min >= MIN_WAKE_MIN_PER_DAY & DAY$PAXQFD == 0, min_d = 4L),
  C5_allwear600_d6   = list(day = !is.na(DAY$allwear_min) & DAY$allwear_min >= MIN_WAKE_MIN_PER_DAY,    min_d = 6L),
  C6_allwear600_d7   = list(day = !is.na(DAY$allwear_min) & DAY$allwear_min >= MIN_WAKE_MIN_PER_DAY,    min_d = 7L)
)

EXPO <- list(); qc_list <- list()
for (cn in CRITS) {
  d  <- CRIT_DEF[[cn]]$day & base_ok
  md <- CRIT_DEF[[cn]]$min_d
  per <- DAY[d, .(n_valid_days = .N, mims_per_day = mean(PAXMTSD, na.rm = TRUE),
                  wake_min_per_day    = mean(PAXWWMD,   na.rm = TRUE),
                  allwear_min_per_day = mean(allwear_min, na.rm = TRUE),
                  nw_min_per_day      = mean(PAXNWMD,   na.rm = TRUE)), by = SEQN]
  # 日数门槛：C6 要求恰好 7 日，其余要求 >= md
  per <- if (cn == "C6_allwear600_d7") per[n_valid_days == md] else per[n_valid_days >= md]
  per[, criterion := cn]
  EXPO[[cn]] <- per
  qc_list[[cn]] <- data.table(criterion = cn, min_valid_days = md,
                              n_valid_day = sum(d), n_people = nrow(per),
                              median_mims_day  = round(median(per$mims_per_day, na.rm = TRUE)),
                              median_wake_min  = round(median(per$wake_min_per_day, na.rm = TRUE)))
  pa_log(sprintf("[%s] 有效日 %d；纳入 %d 人；MIMS/day 中位数 %.0f",
                 cn, sum(d), nrow(per), median(per$mims_per_day, na.rm = TRUE)))
}
QC <- rbindlist(qc_list)
fwrite(QC, file.path(DIR_OUT, "QC_wrist_criteria.csv"))

# 宽表：SEQN × 判据
EXPO_W <- Reduce(function(a, b) merge(a, b, by = "SEQN", all = TRUE),
                 lapply(CRITS, function(cn) {
                   p <- EXPO[[cn]][, .(SEQN, n_valid_days, mims_per_day, wake_min_per_day,
                                       allwear_min_per_day, nw_min_per_day)]
                   setnames(p, c("n_valid_days","mims_per_day","wake_min_per_day",
                                 "allwear_min_per_day","nw_min_per_day"),
                               paste0(c("n_valid_days__","mims_per_day__","wake_min_per_day__",
                                        "allwear_min_per_day__","nw_min_per_day__"), cn))
                   p
                 }))
EXPO_W <- merge(EXPO_W, unique(DAY[, .(SEQN)]), by = "SEQN", all.y = TRUE)   # 保留全部有 PAXDAY 记录者

# =============================================================================
# 2. 协变量（与 03 逐字同源，但基表 = 全部有 PAXDAY 记录者，而非已被 C0 筛过的子集）
# =============================================================================
demo <- rbindlist(list(rd("DEMO_G"), rd("DEMO_H")), use.names = TRUE, fill = TRUE)
demo <- demo[, .(SEQN, RIDAGEYR, RIAGENDR, RIDRETH3, DMDEDUC2, INDFMPIR,
                 WTMEC2YR, SDMVPSU, SDMVSTRA)]
demo[, WTMEC4YR := WTMEC2YR / 2]

bmx  <- rbindlist(list(rd("BMX_G"), rd("BMX_H")), use.names = TRUE, fill = TRUE)[, .(SEQN, BMXBMI, BMXWAIST)]
bpx_raw <- rbindlist(list(rd("BPX_G"), rd("BPX_H")), use.names = TRUE, fill = TRUE)
bpx  <- bpx_raw[, .(SEQN, sbp = rowMeans(.SD, na.rm = TRUE)),
                .SDcols = intersect(c("BPXSY1","BPXSY2","BPXSY3","BPXSY4"), names(bpx_raw))]
bpx[is.nan(sbp), sbp := NA_real_]
smq  <- rbindlist(list(rd("SMQ_G"), rd("SMQ_H")), use.names = TRUE, fill = TRUE)[, .(SEQN, SMQ020, SMQ040)]
alq  <- rbindlist(list(rd("ALQ_G"), rd("ALQ_H")), use.names = TRUE, fill = TRUE)[, .(SEQN, ALQ101)]
diq  <- rbindlist(list(rd("DIQ_G"), rd("DIQ_H")), use.names = TRUE, fill = TRUE)[, .(SEQN, DIQ010)]
mcq  <- rbindlist(list(rd("MCQ_G"), rd("MCQ_H")), use.names = TRUE, fill = TRUE)[
  , .(SEQN, MCQ160B, MCQ160D, MCQ160E, MCQ160F)]

mort <- rd("MORT_2011_2014")
if (is.null(mort)) stop("缺少 data/derived/MORT_2011_2014.rds：请先运行 01_fetch_data.R")
setDT(mort)
mort <- mort[is.na(ELIGSTAT) | ELIGSTAT == 1]
mort <- mort[, .(SEQN, MORTSTAT, UCOD_LEADING, PERMTH_EXM)]
mort[, `:=`(died = fifelse(MORTSTAT == 1, 1L, 0L), surv_mo = as.numeric(PERMTH_EXM))]
mort <- unique(mort, by = "SEQN")

adm <- Reduce(function(a, b) merge(a, b, by = "SEQN", all.x = TRUE),
              list(EXPO_W, demo, bmx, bpx, smq, alq, diq, mcq, mort))
adm <- adm[RIDAGEYR >= MIN_AGE]
adm[, `:=`(
  age       = RIDAGEYR,
  female    = fifelse(RIAGENDR == 2, 1L, 0L),
  race      = factor(RIDRETH3),
  educ      = { e <- DMDEDUC2; e[e %in% c(7, 9)] <- NA; factor(e) },
  pir       = INDFMPIR,
  bmi       = BMXBMI,
  cur_smoke = fifelse(!is.na(SMQ020) & SMQ020 == 1 & !is.na(SMQ040) & SMQ040 %in% c(1, 2), 1L, 0L),
  drink_any = fifelse(!is.na(ALQ101) & ALQ101 == 1, 1L, 0L),
  diabetes  = fifelse(!is.na(DIQ010) & DIQ010 == 1, 1L, 0L),
  cvd_hx    = fifelse(rowSums(.SD == 1, na.rm = TRUE) > 0, 1L, 0L)
), .SDcols = intersect(c("MCQ160B","MCQ160D","MCQ160E","MCQ160F"), names(adm))]
adm[, site := "wrist"]
saveRDS(adm, file.path(DIR_DERIV, "wrist_criterion_variants.rds"))

# =============================================================================
# 3. 等价性核验：C0 必须与 02/03 的 analytic.rds 逐值一致
# =============================================================================
eq_rows <- list()
an <- rd("analytic")
if (!is.null(an)) {
  b <- as.data.table(an)[, .(SEQN, n0 = n_valid_days, m0 = mims_per_day)]
  a <- adm[!is.na(mims_per_day__C0_wake600),
           .(SEQN, n1 = n_valid_days__C0_wake600, m1 = mims_per_day__C0_wake600)]
  m <- merge(b, a, by = "SEQN")
  relmax <- function(x, y) {
    ok <- !is.na(x) & !is.na(y); if (!any(ok)) return(NA_real_)
    max(abs(x[ok] - y[ok]) / pmax(1, abs(y[ok])))
  }
  d_n <- relmax(m$n1, m$n0); d_m <- relmax(m$m1, m$m0)
  verdict <- if (nrow(m) > 0 && d_n < 1e-10 && d_m < 1e-10 &&
                 !any(!b$SEQN %in% a$SEQN) && !any(!a$SEQN %in% b$SEQN))
    "PASS：C0 与 analytic.rds 逐值一致（相对偏差 < 1e-10）" else "*** 需检查：C0 与 analytic.rds 存在差异 ***"
  eq_rows <- list(data.table(
    item = c("analytic.rds 人数","本脚本 C0 人数","两侧共有 SEQN","仅 analytic 有","仅本脚本有",
             "n_valid_days 最大相对偏差","mims_per_day 最大相对偏差"),
    value = c(nrow(b), nrow(a), nrow(m), sum(!b$SEQN %in% a$SEQN), sum(!a$SEQN %in% b$SEQN), d_n, d_m)),
    data.table(item = "结论", value = verdict))
  pa_log("C0 等价性：", verdict)
} else {
  eq_rows <- list(data.table(item = "结论", value = "跳过（analytic.rds 不存在，请先跑 03）"))
}
fwrite(rbindlist(eq_rows), file.path(DIR_OUT, "QC_wrist_C0_equivalence.csv"))

cat("\n===== 腕式判据全谱：分析集规模 =====\n")
show <- rbindlist(lapply(CRITS, function(cn) {
  v <- adm[!is.na(get(paste0("mims_per_day__", cn)))]
  data.table(criterion = cn, n = nrow(v), death = sum(v$died == 1, na.rm = TRUE),
             median_mims_day = round(median(v[[paste0("mims_per_day__", cn)]], na.rm = TRUE)))
}))
print(show)
fwrite(show, file.path(DIR_OUT, "QC_wrist_criteria_analytic.csv"))
fwrite(qc_sum, file.path(DIR_OUT, "QC_wrist_day_qc.csv"))

pa_log("03d 完成 -> data/derived/wrist_criterion_variants.rds（", nrow(adm), " 行）")
