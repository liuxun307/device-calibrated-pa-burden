# =============================================================================
# 03b_pam_exposure_2003_2006.R
# 构建 NHANES 2003-2006（髋式）分析数据集：暴露 + 协变量 + 死亡
# -----------------------------------------------------------------------------
# 目的：与 2011-2014（腕式）用**同一套协变量定义**各估一条 PA→死亡 RR 曲线，
#       两条曲线放到同一「人群百分位」轴上 → 直接得到 hip vs wrist 佩戴部位效应。
#
# 暴露口径（关键：必须与 02/03 对 2011-2014 的口径可比）
#   2011-2014: mims_per_day = 有效日 PAXMTSD 的均值（PAXMTSD = 日级 MIMS 三轴和
#              = 当天有效分钟累加）→ **体量型**暴露；有效日 = 清醒佩戴 >= 10 h
#   2003-2006: counts_per_day = 有效日 (戴表分钟 counts 之和) 的均值 → 同为**体量型**
#   两者单位不同（counts/min vs MIMS）→ 不比较绝对值，而是各自映射到**人群百分位**
#   有效日判据两边一致：佩戴 >= 600 min
#   wear 标志来源：rnhanesdata 的 Flags_C/D（= process_flags()，方法学见 PMC7012355），
#   与 2011-2014 用 CDC 官方 PAXPREDM 属于**不同算法的同类判定** —— 这是本子分析
#   已知的口径差异，写进局限；后续可用 2011-2014 分钟级数据做同算法敏感性分析。
#
# ⚠️ 2003-2006 **没有**成人 GPAQ 自报模块（PAQ_C/D 只有 PAD0xx 系列），
#    故该周期无法做自报×设备的个体内校准 —— 本曲线为**纯设备曲线**，正合本子分析所需。
#
# ⚠️ 种族变量：2003-2006 只有 RIDRETH1（5 类：1 MA / 2 Other Hispanic / 3 NH White /
#    4 NH Black / 5 Other），2011-2014 用 RIDRETH3（额外拆出 Asian）。
#    本脚本输出 race5（5 类）；04b 会把 2011-2014 的 RIDRETH3 也折叠成同一 5 类后**重新拟合**，
#    以保证两条曲线的协变量定义逐字一致。
#
# 输出
#   data/derived/pam_2003_2006.rds     分析数据集（暴露+协变量+死亡+设计变量）
#   output/QC_pam_2003_2006.csv        逐步人数/质量指标
#
# 2026-10-15 新增（强度维度，为 Fig 3(c)(d) 提供零下载成本的数据来源）
#   峰值强度 peak30_per_day  = 有效日内「活动最高 30 分钟」counts/min 均值的平均
#     · 选它的理由：**不需要切点**，且是 PAM 文献的标准强度指标
#     · 本周期（髋式 counts/min）与 2011-2014（腕式 MIMS）量纲不同 → 不作绝对值比较，
#       Fig 3(c) 的横轴按各自人群百分位或原始 counts/min 单独呈现
#   MVPA 分钟 mvpa_per_day  = 有效日内 counts >= 2020 cpm（Troiano 2008）的分钟数均值
#     · 附带 mvpa1952_per_day（Freedson 1998）与 vpa_per_day（>= 5999）作敏感性
#     · ⚠️ 该切点**只在髋式 counts/min 下成立**，不可迁到腕式 MIMS
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
pa_log("===== 03b 构建 NHANES 2003-2006（髋式）分析数据集 =====")

# ---- 参数（与 02 保持一致）----------------------------------------------------
MIN_WEAR_MIN_PER_DAY <- 10 * 60   # 有效日：佩戴 >= 600 min
MIN_VALID_DAYS       <- 4         # 每人至少 4 个有效日

# ---- 参数：强度指标（2026-10-15 新增）----------------------------------------
# 2003-2006 为髋式 ActiGraph 7164，counts/min 有**外部验证的切点** —— 这是本周期
# 相对腕式 MIMS 的一个实质优势（MIMS 至今没有权威 MVPA 切点，见 02 脚本 B4 注）。
#   2020 = Troiano 2008 中强度切点（NHANES 惯用口径）→ **主口径**
#   1952 = Freedson 1998 中强度切点（敏感性）
#   5999 = Troiano 2008 高强度切点
MVPA_CUTS <- c(`1952` = 1952, `2020` = 2020, `5999` = 5999)
MVPA_MAIN <- "2020"
PEAK_N    <- 30L                  # peak-30：日内活动最高 30 分钟的均值

DIR_RNH <- file.path(DIR_RAW, "rnhanesdata_ref")
rd      <- function(f) { p <- file.path(DIR_DERIV, paste0(f, ".rds")); if (file.exists(p)) readRDS(p) else NULL }

qc_rows <- list()
qc_add <- function(step, wave, n, note = "") {
  qc_rows[[length(qc_rows) + 1L]] <<- data.table(step = step, wave = wave, n = n, note = note)
}

# =============================================================================
# 1. 暴露：由 PAXINTEN + Flags 逐周期算「日均总 counts（体量型）」
# =============================================================================
EXPO <- list()
for (w in c("C", "D")) {
  it_p <- file.path(DIR_RNH, paste0("PAXINTEN_", w, ".rda"))
  fl_p <- file.path(DIR_RNH, paste0("Flags_", w, ".rda"))
  if (!file.exists(it_p) || !file.exists(fl_p))
    stop("缺少 rnhanesdata 参考数据：请先运行 01b_fetch_pam_2003_2006.R")
  e1 <- new.env(); load(it_p, envir = e1)
  e2 <- new.env(); load(fl_p, envir = e2)
  it <- setDT(get(paste0("PAXINTEN_", w), envir = e1))
  fl <- setDT(get(paste0("Flags_", w),    envir = e2))

  # --- 结构一致性硬校验：逐行相乘的前提是行序与标识列完全一致 ---
  stopifnot(identical(dim(it), dim(fl)),
            identical(names(it), names(fl)),
            identical(it$SEQN, fl$SEQN),
            identical(it$PAXCAL, fl$PAXCAL),
            identical(it$PAXSTAT, fl$PAXSTAT),
            identical(it$WEEKDAY, fl$WEEKDAY))
  qc_add("原始 subject-day", w, nrow(it))

  mn <- paste0("MIN", 1:1440)
  Im <- as.matrix(it[, ..mn]); Fm <- as.matrix(fl[, ..mn])
  # Flags 里的 NA 标记「该分钟无数据」；PAXINTEN 的 NA 与之逐格对齐（已在 01b 核过）
  wear_min   <- rowSums(Fm, na.rm = TRUE)
  counts_day <- rowSums(Im * Fm, na.rm = TRUE)   # 仅计入佩戴分钟（非佩戴分钟 counts 恒为 0）

  # ---- 强度指标（2026-10-15 新增）：peak-30 与 MVPA 分钟 ----------------------
  # 只保留「佩戴且非缺失」的分钟；其余置 NA → 既不参与 top-30 排序也不计入 MVPA。
  W <- Im
  W[is.na(Fm) | Fm != 1] <- NA_real_
  if (anyNA(Im) && !anyNA(W)) stop("掩码失效：Im 有缺失但 W 无缺失，检查 Flags 口径")
  # peak-30：日内活动最高 30 分钟的均值（标准定义，不要求时间上连续）
  pk30 <- apply(W, 1L, function(v) {
    v <- v[!is.na(v)]
    if (length(v) < PEAK_N) return(NA_real_)
    mean(sort.int(v, decreasing = TRUE)[seq_len(PEAK_N)])
  })
  # 硬校验：peak-30 必 >= 佩戴时段均值（top-30 不可能低于整体均值）
  chk_mean <- rowSums(W, na.rm = TRUE) / pmax(rowSums(!is.na(W)), 1)
  bad <- which(!is.na(pk30) & pk30 < chk_mean - 1e-6)
  if (length(bad)) stop("peak-30 小于佩戴均值，排序口径有误（行 ", bad[1], "）")
  # MVPA 分钟数（多切点敏感性的三个口径）
  mv <- vapply(MVPA_CUTS, function(th) rowSums(W >= th, na.rm = TRUE), numeric(nrow(W)))

  day <- data.table(SEQN = it$SEQN, PAXCAL = it$PAXCAL, PAXSTAT = it$PAXSTAT,
                    SDDSRVYR = it$SDDSRVYR, wear_min = wear_min, counts_day = counts_day,
                    peak30 = pk30)
  for (k in names(MVPA_CUTS)) day[[paste0("mvpa_", k)]] <- mv[, k]
  day[, valid_day := !is.na(wear_min) & wear_min >= MIN_WEAR_MIN_PER_DAY &
                      PAXCAL == 1 & PAXSTAT == 1]
  qc_add("有效 subject-day（佩戴>=600min 且校准/可靠）", w, sum(day$valid_day))
  # MVPA 分钟数不可能超过佩戴分钟数（硬校验，防切点/掩码错位）
  stopifnot(all(day[[paste0("mvpa_", MVPA_MAIN)]] <= day$wear_min + 1e-9, na.rm = TRUE))

  per <- day[valid_day == TRUE, .(
    n_valid_days   = .N,
    counts_per_day = mean(counts_day, na.rm = TRUE),
    wear_mean_min  = mean(wear_min,  na.rm = TRUE),
    peak30_per_day = mean(peak30, na.rm = TRUE),
    mvpa_per_day   = mean(get(paste0("mvpa_", MVPA_MAIN)), na.rm = TRUE),
    mvpa1952_per_day = mean(mvpa_1952, na.rm = TRUE),
    vpa_per_day      = mean(mvpa_5999, na.rm = TRUE)), by = SEQN]
  # 全为 NA 的日会让 mean 返回 NaN → 归回 NA（不参与建模）
  for (cc in c("peak30_per_day", "mvpa_per_day", "mvpa1952_per_day", "vpa_per_day"))
    per[is.nan(get(cc)), (cc) := NA_real_]
  qc_add(sprintf("有效日 peak-30 中位数（佩戴足 %d 分钟的日）", PEAK_N), w,
         round(median(day[valid_day == TRUE, peak30], na.rm = TRUE)),
         "counts/min")
  qc_add(sprintf("有效日 MVPA(>=%s cpm) 分钟中位数", MVPA_MAIN), w,
         round(median(day[valid_day == TRUE, get(paste0("mvpa_", MVPA_MAIN))], na.rm = TRUE)),
         "min/day")
  qc_add(sprintf("有>=%d有效日者", MIN_VALID_DAYS), w,
         sum(per$n_valid_days >= MIN_VALID_DAYS))
  per <- per[n_valid_days >= MIN_VALID_DAYS]
  per[, wave := w]
  EXPO[[w]] <- per
  pa_log(sprintf("[%s] 有效日 %d / %d subject-day；纳入 %d 人；counts/day 中位数 %.0f；peak-30 中位数 %.0f；MVPA(%s) 中位数 %.0f min",
                 w, sum(day$valid_day), nrow(day), nrow(per), median(per$counts_per_day),
                 median(per$peak30_per_day, na.rm = TRUE), MVPA_MAIN,
                 median(per$mvpa_per_day, na.rm = TRUE)))
  rm(Im, Fm, W, mv, pk30, chk_mean, day, it, fl); gc(verbose = FALSE)
}
EXPO <- rbindlist(EXPO, use.names = TRUE, fill = TRUE)

# =============================================================================
# 2. 协变量（与 03 对 2011-2014 的定义逐字对齐）
# =============================================================================
parts <- list()
for (w in c("C", "D")) {
  demo <- rd(paste0("DEMO_", w))
  bmx  <- rd(paste0("BMX_",  w))
  bpx  <- rd(paste0("BPX_",  w))
  smq  <- rd(paste0("SMQ_",  w))
  alq  <- rd(paste0("ALQ_",  w))
  diq  <- rd(paste0("DIQ_",  w))
  mcq  <- rd(paste0("MCQ_",  w))
  if (any(vapply(list(demo, bmx, bpx, smq, alq, diq, mcq), is.null, logical(1))))
    stop("缺少周期 ", w, " 的协变量组件 rds：请先运行 01_fetch_data.R")

  dm <- as.data.table(demo)[, .(SEQN, RIDAGEYR, RIAGENDR,
                                race5 = RIDRETH1,          # ⚠️ 5 类口径，见文件头说明
                                DMDEDUC2, INDFMPIR,
                                WTMEC2YR, SDMVPSU, SDMVSTRA)]
  # 血压：与 03 一致，取 BPXSY1-4 行均值
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

# =============================================================================
# 3. 死亡链接（2003-2006，与 2011-2014 同为 NCHS 2019 版公开链接文件）
# =============================================================================
mort <- rd("MORT_2003_2006")
if (is.null(mort)) stop("缺少 data/derived/MORT_2003_2006.rds：请先运行 01_fetch_data.R")
mort <- as.data.table(mort)
mort <- mort[is.na(ELIGSTAT) | ELIGSTAT == 1]      # 仅保留符合链接资格者（与 03 一致）
mort <- mort[, .(SEQN, MORTSTAT, PERMTH_EXM, UCOD_LEADING)]
mort[, `:=`(died    = fifelse(MORTSTAT == 1, 1L, 0L),
            surv_mo = as.numeric(PERMTH_EXM))]
mort <- unique(mort, by = "SEQN")

# =============================================================================
# 4. 合并 + 派生协变量（定义与 03 逐字一致）
# =============================================================================
adm <- merge(EXPO, CV, by = c("SEQN", "wave"), all.x = TRUE)
adm <- merge(adm, mort, by = "SEQN", all.x = TRUE)
adm[, WTMEC4YR := WTMEC2YR / 2]        # C+D 合并 → 4 年权重（与 G+H 的做法一致）

adm <- adm[RIDAGEYR >= 25]             # 与 GBD LPA 覆盖一致（与 03 一致）

adm[, `:=`(
  age       = RIDAGEYR,
  female    = fifelse(RIAGENDR == 2, 1L, 0L),
  race      = factor(race5, levels = 1:5,
                     labels = c("Mexican American","Other Hispanic","NH White",
                                "NH Black","Other")),
  educ      = { e <- DMDEDUC2; e[e %in% c(7, 9)] <- NA; factor(e) },
  pir       = INDFMPIR,
  bmi       = bmi,
  cur_smoke = fifelse(!is.na(SMQ020) & SMQ020 == 1 & !is.na(SMQ040) & SMQ040 %in% c(1, 2), 1L, 0L),
  drink_any = fifelse(!is.na(ALQ101) & ALQ101 == 1, 1L, 0L),
  diabetes  = fifelse(!is.na(DIQ010) & DIQ010 == 1, 1L, 0L),
  cvd_hx    = fifelse(rowSums(.SD == 1, na.rm = TRUE) > 0, 1L, 0L)
), .SDcols = intersect(c("MCQ160B","MCQ160D","MCQ160E","MCQ160F"), names(adm))]

adm[, counts_q4 := cut(counts_per_day, breaks = quantile(counts_per_day, probs = 0:4/4, na.rm = TRUE),
                       include.lowest = TRUE, labels = paste0("Q", 1:4))]
# 强度指标四分位（2026-10-15 新增）——与 counts_q4 同法，用于 Table 1 分组与 Cox 分类模型
for (vv in c("peak30_per_day", "mvpa_per_day")) {
  qv <- quantile(adm[[vv]], probs = 0:4/4, na.rm = TRUE)
  adm[[paste0(vv, "_q4")]] <- cut(adm[[vv]], breaks = qv, include.lowest = TRUE,
                                  labels = paste0("Q", 1:4))
}
adm[, site := "hip"]                   # 髋式（ActiGraph 7164）

saveRDS(adm, file.path(DIR_DERIV, "pam_2003_2006.rds"))

# =============================================================================
# 5. QC
# =============================================================================
qc_add("合并后（C+D，去掉年龄<25）", "C+D", nrow(adm))
qc_add("其中有死亡随访且 surv_mo>0", "C+D", adm[!is.na(surv_mo) & surv_mo > 0, .N])
qc_add("全因死亡数", "C+D", sum(adm$died == 1, na.rm = TRUE))
QC <- rbindlist(qc_rows)
QC <- rbind(QC, data.table(step = "counts_per_day 中位数(P25,P75)", wave = "C+D", n = NA_real_,
                           note = sprintf("%.0f (%.0f, %.0f)",
                                          median(adm$counts_per_day),
                                          quantile(adm$counts_per_day, .25),
                                          quantile(adm$counts_per_day, .75))))
QC <- rbind(QC, data.table(step = "佩戴分钟 中位数", wave = "C+D",
                           n = round(median(adm$wear_mean_min)),
                           note = "min/day"))
for (vv in c("peak30_per_day", "mvpa_per_day", "mvpa1952_per_day", "vpa_per_day")) {
  x <- adm[[vv]]
  QC <- rbind(QC, data.table(step = paste0(vv, " 中位数(P25,P75)"), wave = "C+D",
                             n = sum(!is.na(x)),
                             note = sprintf("%.1f (%.1f, %.1f)",
                                            median(x, na.rm = TRUE),
                                            quantile(x, .25, na.rm = TRUE),
                                            quantile(x, .75, na.rm = TRUE))))
}
fwrite(QC, file.path(DIR_OUT, "QC_pam_2003_2006.csv"))

cat("\n--- 2003-2006（髋式）分析集 ---\n")
cat("人数:", nrow(adm), " | 全因死亡:", sum(adm$died == 1, na.rm = TRUE), "\n")
cat("分周期: "); print(adm[, .N, by = wave])
cat("counts_per_day 分位:\n"); print(round(quantile(adm$counts_per_day, c(0,.25,.5,.75,1))))
cat("peak30_per_day 分位:\n"); print(round(quantile(adm$peak30_per_day, c(0,.25,.5,.75,1), na.rm = TRUE)))
cat("mvpa_per_day 分位:\n");   print(round(quantile(adm$mvpa_per_day,   c(0,.25,.5,.75,1), na.rm = TRUE)))
cat("peak-30 与总 counts 的相关系数(Pearson/Spearman):",
    round(cor(adm$peak30_per_day, adm$counts_per_day, use = "complete.obs"), 3), "/",
    round(cor(adm$peak30_per_day, adm$counts_per_day, method = "spearman", use = "complete.obs"), 3), "\n")
cat("MVPA 与总 counts 的相关系数(Pearson/Spearman):",
    round(cor(adm$mvpa_per_day, adm$counts_per_day, use = "complete.obs"), 3), "/",
    round(cor(adm$mvpa_per_day, adm$counts_per_day, method = "spearman", use = "complete.obs"), 3), "\n")
print(QC)
pa_log("03b 完成 -> data/derived/pam_2003_2006.rds")
