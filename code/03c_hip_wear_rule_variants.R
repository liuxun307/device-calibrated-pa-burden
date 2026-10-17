# =============================================================================
# 03c_hip_wear_rule_variants.R
# 髋式（NHANES 2003-2006）**同一套分钟级 counts** 上的 wear 判定规则全谱暴露构建
# -----------------------------------------------------------------------------
# 为什么要做（对应「佩戴部位效应矛盾」的敏感性）：
#   04b 得到「部位效应在总量轴上不可检出」（腕/髋比值 ≈ 1.00，9 点里 8 点 CI 含 1），
#   而文献池（EK19 髋式 LPA 3 行 vs SV25 腕式 LPA 3 行）给出髋式更陡
#   （hip/wrist @off60 = 0.658 [0.496, 0.873], p=0.0037）。两者方向相反。
#
#   最可疑的解释之一是：**两波的 wear 判定算法不同**
#     髋式 2003-2006 : rnhanesdata 的 Flags_C/D = process_flags()
#                      → 即 Choi et al. 2011 算法（window=90, tol=2, tol_upper=99）
#     腕式 2011-2014 : CDC 官方 PAXPREDM（机器学习预测 wake/sleep/nonwear）
#   甚至窗口语义也不同：髋式是「全天佩戴 ≥600 min」（含睡眠），
#   腕式是「清醒佩戴 PAXWWMD ≥600 min」。
#
#   髋侧的好处是：**我们有未掩码的分钟级原始 counts**（rnhanesdata 的 PAXINTEN_C/D
#   宽表，每人恰 7 行 × 1440 分钟，已由 01c 与原始 xpt 逐人核对一致）。
#   → 可以在同一份数据上把 wear 规则换掉，看曲线跟着动多少。
#   如果曲线对规则极不敏感，则「算法差异」不足以解释 0.658 vs 1.00 的鸿沟。
#
# 五套规则（全部在**同一份** PAXINTEN 分钟矩阵上计算，只换 wear 判定）
#   R0_choi2011       : wear = Flags==1                    —— rnhanesdata 原产物（基准，即 04b 用的）
#   R1_anydata        : wear = counts 非缺失               —— 完全不剔除非佩戴（最宽松的界）
#   R2_signal_gt0     : wear = counts > 0                  —— 「有信号即佩戴」
#   R3_no_zero_run60  : wear = 非缺失 且 不落在「连续 ≥60 min 全零」段内
#                          —— Troiano 风格长零段剔除（Choi 与 R2 之间的中间点）
#   R4_awake_signal   : wear = R2 且 分钟落在 06:00-23:59 —— 窗口语义向腕侧「清醒佩戴」对齐
#
#   ⚠️ 实测修正（勿凭直觉写论文）：五个规则在**严格度**上并非对称分布。
#      髋式 counts 在静坐/静立时**大量恰为 0**（而腕式 MIMS 极少恰为 0），
#      所以 R2/R4 不是「最接近腕侧」，而是**比 Choi 更严**的一端：
#        R1（1440 min 全算佩戴）
#          ⊃ R0（Choi 2011，856 min）
#            ≈ R3（长零段剔除，862 min）
#              ⊃ R2（counts>0，731 min）
#                ⊃ R4（counts>0 且 06:00-23:59，720 min）
#      实测纳入人数：R1 7,289 / R0 5,890 / R3 5,918 / R2 2,999 / R4 2,708
#      → 本脚本给出的是「严格度单调递增的 5 点」，正好可当作敏感性区间来看。
#
# 有效日：该规则下的 wear 分钟 >= 600 min/天，且 PAXCAL==1 & PAXSTAT==1；每人 >=4 个有效日
# 暴露  ：该规则下 wear 分钟的 counts 累加 → 日均值（**体量型**，与 MIMS/day 同构）
# 附带  ：在 R0 的 wear 集合上再算 3 个体量型强度带暴露（用于「指标轴」检验）
#         sed_lt100 / lpa_100_2020 / mvpa_ge2020（Troiano 2007 切点，仅作轴向对照）
#
# 输出
#   data/derived/pam_hip_wearvariants.rds  各规则暴露 + 与 03b 同源的协变量/死亡/设计变量
#   output/QC_hip_wear_rules.csv           各规则样本量/佩戴/暴露分位数
#   output/QC_hip_wear_R0_equivalence.csv  与 03b（pam_2003_2006.rds）的 R0 等价性核验
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
suppressPackageStartupMessages({ library(data.table); library(tidyverse) })
pa_log("===== 03c 髋式 wear 判定规则全谱（5 套）=====")

MIN_WEAR_MIN_PER_DAY <- 10 * 60   # 有效日：佩戴 >= 600 min（与 02/03b 一致）
MIN_VALID_DAYS       <- 4         # 每人至少 4 个有效日（与 02/03b 一致）
MIN_AGE              <- 25        # 与 GBD LPA 覆盖一致（与 03/03b 一致）
CHUNK_ROWS           <- 4000L     # 分块行数（每块 ~46 MB，避免整矩阵派生量爆内存）

RULES <- c("R0_choi2011", "R1_anydata", "R2_signal_gt0", "R3_no_zero_run60", "R4_awake_signal")
BANDS <- c("sed_lt100", "lpa_100_2020", "mvpa_ge2020")

DIR_RNH <- file.path(DIR_RAW, "rnhanesdata_ref")
rd      <- function(f) { p <- file.path(DIR_DERIV, paste0(f, ".rds")); if (file.exists(p)) readRDS(p) else NULL }

# =============================================================================
# 0. 工具函数
# =============================================================================
# 分钟序号 → 一天中的小时（MIN1 = 00:00-00:59 → hour 0）
HOUR_OF_MIN  <- ((1:1440) - 1L) %/% 60L
AWAKE_MASK   <- HOUR_OF_MIN >= 6L          # 06:00-23:59（腕式"清醒佩戴"的窗口代理）

#' 判断每个分钟是否落在「连续 >= runlen 分钟全零」的段内
#' @param M 数值矩阵（行 = subject-day，列 = 1440 分钟；NA 表示无数据，不参与零段）
#' 实现：行内累计零计数 → 以 i 结尾的长度 w 窗是否全零 → 前向 w 窗和 > 0 即被覆盖
long_zero_run <- function(M, runlen = 60L) {
  n <- ncol(M); w <- as.integer(runlen)
  stopifnot(n > w)
  z  <- !is.na(M) & M == 0
  cz <- t(apply(z, 1L, cumsum))                       # 行内累计零个数
  idx <- (w + 1L):n
  W <- matrix(FALSE, nrow(cz), n)
  W[, idx] <- cz[, idx, drop = FALSE] - cz[, idx - w, drop = FALSE] == w
  # 前向 w 窗和：g[k] = sum_{i>=k} W[i]  →  sum_{i=k}^{k+w-1} W[i]
  g   <- t(apply(W, 1L, function(v) rev(cumsum(rev(as.integer(v))))))
  fwd <- g
  fwd[, 1:(n - w)] <- g[, 1:(n - w)] - g[, (1 + w):n]
  fwd > 0
}

# =============================================================================
# 1. 逐周期：在同一份分钟矩阵上算 5 套规则 + 3 个体量带
# =============================================================================
row_parts <- list()
for (w in c("C", "D")) {
  it_p <- file.path(DIR_RNH, paste0("PAXINTEN_", w, ".rda"))
  fl_p <- file.path(DIR_RNH, paste0("Flags_",    w, ".rda"))
  if (!file.exists(it_p) || !file.exists(fl_p))
    stop("缺少 rnhanesdata 参考数据：请先运行 01b_fetch_pam_2003_2006.R")
  e1 <- new.env(); load(it_p, envir = e1)
  e2 <- new.env(); load(fl_p, envir = e2)
  it <- setDT(get(paste0("PAXINTEN_", w), envir = e1))
  fl <- setDT(get(paste0("Flags_",    w), envir = e2))

  # 结构一致性硬校验（逐行相乘的前提）
  stopifnot(identical(dim(it), dim(fl)),
            identical(names(it), names(fl)),
            identical(it$SEQN,    fl$SEQN),
            identical(it$PAXCAL,  fl$PAXCAL),
            identical(it$PAXSTAT, fl$PAXSTAT))

  mn <- paste0("MIN", 1:1440)
  Im <- as.matrix(it[, ..mn]); Fm <- as.matrix(fl[, ..mn])
  n  <- nrow(Im)
  pa_log(sprintf("[%s] 分钟矩阵 %d × %d（%.0f MB/份）", w, n, ncol(Im),
                 as.numeric(object.size(Im)) / 1024^2))

  nch  <- ceiling(n / CHUNK_ROWS)
  outs <- vector("list", nch)
  for (k in seq_len(nch)) {
    rows <- ((k - 1L) * CHUNK_ROWS + 1L):min(k * CHUNK_ROWS, n)
    C <- Im[rows, , drop = FALSE]
    F <- Fm[rows, , drop = FALSE]
    has_data <- !is.na(C)

    masks <- list(
      R0_choi2011      = (F == 1) & !is.na(F),
      R1_anydata       = has_data,
      R2_signal_gt0    = has_data & C > 0,
      R3_no_zero_run60 = has_data & !long_zero_run(C, 60L),
      R4_awake_signal  = has_data & C > 0 & matrix(AWAKE_MASK, nrow(C), 1440L, byrow = TRUE)
    )

    res <- data.table(SEQN = it$SEQN[rows], PAXCAL = it$PAXCAL[rows],
                      PAXSTAT = it$PAXSTAT[rows], wave = w)
    for (r in RULES) {
      m <- masks[[r]]
      res[[paste0("wear_min__",  r)]]   <- rowSums(m, na.rm = TRUE)
      res[[paste0("counts_day__", r)]]  <- rowSums(C * m, na.rm = TRUE)
    }
    # 体量带（仅在 R0 的 wear 集合上，供「指标轴」对照）
    m0 <- masks[["R0_choi2011"]]; C0 <- C * m0
    res[["sed_lt100__R0"]]     <- rowSums(C0 * (C0 > 0   & C0 < 100),  na.rm = TRUE)
    res[["lpa_100_2020__R0"]]  <- rowSums(C0 * (C0 >= 100 & C0 < 2020), na.rm = TRUE)
    res[["mvpa_ge2020__R0"]]   <- rowSums(C0 * (C0 >= 2020),            na.rm = TRUE)
    outs[[k]] <- res
    rm(C, F, masks, m0, C0); gc(verbose = FALSE)
  }
  row_parts[[w]] <- rbindlist(outs, use.names = TRUE, fill = TRUE)
  rm(Im, Fm, it, fl, outs); gc(verbose = FALSE)
}
DAY <- rbindlist(row_parts, use.names = TRUE, fill = TRUE)

# 有效日 + 每人聚合
for (r in RULES) {
  wm <- paste0("wear_min__",  r); cd <- paste0("counts_day__", r)
  DAY[[paste0("valid__", r)]] <- !is.na(DAY[[wm]]) & DAY[[wm]] >= MIN_WEAR_MIN_PER_DAY &
                                 DAY$PAXCAL == 1 & DAY$PAXSTAT == 1
}

EXPO <- list()
for (r in RULES) {
  v  <- paste0("valid__", r); wm <- paste0("wear_min__", r); cd <- paste0("counts_day__", r)
  per <- DAY[get(v) == TRUE, .(
    n_valid_days = .N,
    counts_per_day = mean(get(cd), na.rm = TRUE),
    wear_mean_min  = mean(get(wm), na.rm = TRUE)), by = SEQN]
  per <- per[n_valid_days >= MIN_VALID_DAYS]
  setnames(per, c("n_valid_days", "counts_per_day", "wear_mean_min"),
                c(paste0("n_valid_days__",  r),
                  paste0("counts_per_day__", r),
                  paste0("wear_mean_min__",  r)))
  EXPO[[r]] <- per
}
# R0 的体量带（用同一批有效人、同一批有效日）
per0_band <- DAY[get(paste0("valid__R0_choi2011")) == TRUE, .(
  sed_lt100__R0    = mean(sed_lt100__R0,    na.rm = TRUE),
  lpa_100_2020__R0 = mean(lpa_100_2020__R0, na.rm = TRUE),
  mvpa_ge2020__R0  = mean(mvpa_ge2020__R0,  na.rm = TRUE)), by = SEQN]
EXPO[["band"]] <- per0_band

EXPO_W <- Reduce(function(a, b) merge(a, b, by = "SEQN", all = TRUE), EXPO)

qc_rule <- rbindlist(lapply(RULES, function(r) data.table(
  rule = r,
  n_valid_day        = sum(DAY[[paste0("valid__", r)]]),
  n_people_ge4days   = nrow(EXPO[[r]]),
  median_wear_min    = round(median(EXPO[[r]][[paste0("wear_mean_min__", r)]])),
  median_counts_day  = round(median(EXPO[[r]][[paste0("counts_per_day__", r)]])))))
fwrite(qc_rule, file.path(DIR_OUT, "QC_hip_wear_rules.csv"))
print(qc_rule)

# =============================================================================
# 2. 协变量 / 死亡 / 设计变量（与 03b **逐字同源**）
# =============================================================================
parts <- list()
for (w in c("C", "D")) {
  demo <- rd(paste0("DEMO_", w)); bmx <- rd(paste0("BMX_", w)); bpx <- rd(paste0("BPX_", w))
  smq  <- rd(paste0("SMQ_",  w)); alq <- rd(paste0("ALQ_", w)); diq <- rd(paste0("DIQ_", w))
  mcq  <- rd(paste0("MCQ_",  w))
  if (any(vapply(list(demo, bmx, bpx, smq, alq, diq, mcq), is.null, logical(1))))
    stop("缺少周期 ", w, " 的协变量组件 rds：请先运行 01_fetch_data.R")

  dm <- as.data.table(demo)[, .(SEQN, RIDAGEYR, RIAGENDR, race5 = RIDRETH1,
                                DMDEDUC2, INDFMPIR, WTMEC2YR, SDMVPSU, SDMVSTRA)]
  bpd <- as.data.table(bpx)
  sbp <- bpd[, .(SEQN, sbp = rowMeans(.SD, na.rm = TRUE)),
             .SDcols = intersect(c("BPXSY1","BPXSY2","BPXSY3","BPXSY4"), names(bpd))]
  sbp[is.nan(sbp), sbp := NA_real_]
  bmxd <- as.data.table(bmx)[, .(SEQN, bmi = BMXBMI)]
  smqd <- as.data.table(smq)[, .(SEQN, SMQ020, SMQ040)]
  alqd <- as.data.table(alq)[, .(SEQN, ALQ101)]
  diqd <- as.data.table(diq)[, .(SEQN, DIQ010)]
  mcqd <- as.data.table(mcq)[, .(SEQN, MCQ160B, MCQ160D, MCQ160E, MCQ160F)]
  cv <- Reduce(function(a, b) merge(a, b, by = "SEQN", all.x = TRUE),
               list(dm, bmxd, sbp, smqd, alqd, diqd, mcqd))
  cv[, wave := w]
  parts[[w]] <- cv
}
CV <- rbindlist(parts, use.names = TRUE, fill = TRUE)

mort <- rd("MORT_2003_2006")
if (is.null(mort)) stop("缺少 data/derived/MORT_2003_2006.rds：请先运行 01_fetch_data.R")
mort <- as.data.table(mort)
mort <- mort[is.na(ELIGSTAT) | ELIGSTAT == 1]
mort <- mort[, .(SEQN, MORTSTAT, PERMTH_EXM, UCOD_LEADING)]
mort[, `:=`(died = fifelse(MORTSTAT == 1, 1L, 0L), surv_mo = as.numeric(PERMTH_EXM))]
mort <- unique(mort, by = "SEQN")

adm <- merge(CV, EXPO_W, by = "SEQN", all.x = TRUE)   # 以协变量为基表（暴露可能缺 → 该规则下不入模）
adm <- merge(adm, mort, by = "SEQN", all.x = TRUE)
adm[, WTMEC4YR := WTMEC2YR / 2]

derive_covars <- function(d) {
  d[, `:=`(
    age       = RIDAGEYR,
    female    = fifelse(RIAGENDR == 2, 1L, 0L),
    race      = factor(race5, levels = 1:5,
                       labels = c("Mexican American","Other Hispanic","NH White","NH Black","Other")),
    educ      = { e <- DMDEDUC2; e[e %in% c(7, 9)] <- NA; factor(e) },
    pir       = INDFMPIR,
    bmi       = bmi,
    cur_smoke = fifelse(!is.na(SMQ020) & SMQ020 == 1 & !is.na(SMQ040) & SMQ040 %in% c(1, 2), 1L, 0L),
    drink_any = fifelse(!is.na(ALQ101) & ALQ101 == 1, 1L, 0L),
    diabetes  = fifelse(!is.na(DIQ010) & DIQ010 == 1, 1L, 0L),
    cvd_hx    = fifelse(rowSums(.SD == 1, na.rm = TRUE) > 0, 1L, 0L)
  ), .SDcols = intersect(c("MCQ160B","MCQ160D","MCQ160E","MCQ160F"), names(d))]
  d
}
adm <- derive_covars(adm)
adm <- adm[RIDAGEYR >= MIN_AGE]
adm[, site := "hip"]
saveRDS(adm, file.path(DIR_DERIV, "pam_hip_wearvariants.rds"))

# =============================================================================
# 3. 等价性核验：本脚本的 R0 必须与 03b 的产物**逐值一致**
#    （证明敏感性用的暴露与主分析同源，不是重写出来的另一套）
# =============================================================================
base <- rd("pam_2003_2006")
eq_rows <- list()
if (!is.null(base)) {
  b <- as.data.table(base)[, .(SEQN, n0 = n_valid_days, c0 = counts_per_day, w0 = wear_mean_min)]
  a <- adm[!is.na(counts_per_day__R0_choi2011),
           .(SEQN, n1 = n_valid_days__R0_choi2011,
             c1 = counts_per_day__R0_choi2011, w1 = wear_mean_min__R0_choi2011)]
  m <- merge(b, a, by = "SEQN")
  relmax <- function(x, y) {
    ok <- !is.na(x) & !is.na(y)
    if (!any(ok)) return(NA_real_)
    max(abs(x[ok] - y[ok]) / pmax(1, abs(y[ok])))
  }
  eq_rows <- list(data.table(
    item = c("03b 人数", "本脚本 R0 人数", "两侧共有 SEQN", "仅 03b 有", "仅本脚本有",
             "n_valid_days 最大相对偏差", "counts_per_day 最大相对偏差", "wear_min 最大相对偏差"),
    value = c(nrow(b), nrow(a), nrow(m),
              sum(!b$SEQN %in% a$SEQN), sum(!a$SEQN %in% b$SEQN),
              relmax(m$n1, m$n0), relmax(m$c1, m$c0), relmax(m$w1, m$w0))))
  verdict <- if (nrow(m) > 0 && relmax(m$c1, m$c0) < 1e-10 &&
                 !any(!b$SEQN %in% a$SEQN) && !any(!a$SEQN %in% b$SEQN))
    "PASS：R0 与 03b 逐值一致（相对偏差 < 1e-10）" else "*** 需检查：R0 与 03b 存在差异 ***"
  eq_rows[[2]] <- data.table(item = "结论", value = verdict)
  pa_log("R0 等价性：", verdict)
} else {
  eq_rows <- list(data.table(item = "结论", value = "跳过（pam_2003_2006.rds 不存在，请先跑 03b）"))
}
fwrite(rbindlist(eq_rows), file.path(DIR_OUT, "QC_hip_wear_R0_equivalence.csv"))

# =============================================================================
# 4. 汇总打印
# =============================================================================
cat("\n===== 髋式 wear 规则全谱：暴露分布 =====\n")
show <- rbindlist(lapply(RULES, function(r) {
  v <- adm[!is.na(get(paste0("counts_per_day__", r)))]
  q <- quantile(v[[paste0("counts_per_day__", r)]], c(.25, .5, .75))
  data.table(rule = r, n = nrow(v), death = sum(v$died == 1, na.rm = TRUE),
             wear_med = round(median(v[[paste0("wear_mean_min__", r)]])),
             counts_p25 = round(q[1]), counts_med = round(q[2]), counts_p75 = round(q[3]))
}))
print(show)
fwrite(show, file.path(DIR_OUT, "QC_hip_wear_rules_analytic.csv"))

pa_log("03c 完成 -> data/derived/pam_hip_wearvariants.rds（", nrow(adm), " 行）")
