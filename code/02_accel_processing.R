# =============================================================================
# 02_accel_processing.R
# 加速度计清洗与暴露指标构建
# 核心规则（已对照 CDC Codebook 核实）：
#   PAXPREDM : 1=Wake wear, 2=Sleep wear, 3=Non wear, 4=Unknown
#   PAXQFM   : 分钟数据质量标记计数, 0=有效
#   PAXMTSM  : 分钟级 MIMS 三轴和; -0.01 = 无法计算
#   PAXMTSD  : 日级 MIMS 三轴和（仅有效分钟累加）
#   PAXWWMD/PAXSWMD/PAXNWMD/PAXUMD : 日级 有效 清醒/睡眠/未佩戴/未知 分钟
#   PAXVMD   : 日级 有效分钟总数 ; PAXTMD : 日级 有数据分钟总数
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
  library(data.table); library(tidyverse); library(haven)
})
# ROOT / DIR_RAW / DIR_DERIV / DIR_OUT 由 00_setup.R 统一提供

# ---------------------------- 参数：有效日判据（改这里做敏感性分析） ---------
PARAMS <- list(
  min_wake_min_per_day = 10 * 60,  # 主分析 10 h 清醒佩戴
  min_valid_days       = 4,        # 至少 4 个有效日
  min_age              = 25        # 与 GBD LPA 覆盖人群对齐
)

# =============================================================================
# Part A. 日级文件处理（主路径，体积小）
# =============================================================================
load_day <- function(cycle) {
  f <- file.path(DIR_RAW, sprintf("PAXDAY_%s.xpt", cycle))
  if (!file.exists(f)) return(NULL)
  as.data.table(haven::read_xpt(f))
}

day_list <- lapply(c("G", "H"), load_day)
day <- rbindlist(day_list, use.names = TRUE, fill = TRUE)

# ---- A1. 质控恒等式校验（第一道闸） ----------------------------------------
# 恒等于: PAXVMD == PAXWWMD + PAXSWMD + PAXNWMD + PAXUMD
#         且 PAXVMD <= PAXTMD <= 1440
day[, qc_sum_ok   := (PAXWWMD + PAXSWMD + PAXNWMD + PAXUMD) == PAXVMD]
day[, qc_range_ok := PAXVMD <= PAXTMD & PAXTMD <= 1440 & PAXVMD >= 0]

qc_report <- day[, .(
  n_rows                = .N,
  pct_sum_violation     = round(100 * mean(!qc_sum_ok,   na.rm = TRUE), 3),
  pct_range_violation   = round(100 * mean(!qc_range_ok, na.rm = TRUE), 3),
  pct_missing_PAXMTSD   = round(100 * mean(is.na(PAXMTSD)), 3)
)]
fwrite(qc_report, file.path(DIR_OUT, "QC_day_level.csv"))
print(qc_report)

# ---- A2. 有效日判定（清醒佩戴 >= 10 h/天） ---------------------------------
day[, valid_day := qc_sum_ok & qc_range_ok &
      !is.na(PAXWWMD) & PAXWWMD >= PARAMS$min_wake_min_per_day]

# ---- A3. 每人聚合 ----------------------------------------------------------
# 平均每日 MIMS（仅有效日）——主暴露，体量型，规避 MIMS 无切点问题
per <- day[valid_day == TRUE, .(
  n_valid_days      = .N,
  mims_per_day      = mean(PAXMTSD, na.rm = TRUE),          # 主暴露 (MIMS/day)
  wake_min_per_day  = mean(PAXWWMD, na.rm = TRUE),
  nw_min_per_day    = mean(PAXNWMD, na.rm = TRUE)
), by = SEQN]

per <- per[n_valid_days >= PARAMS$min_valid_days]
message("有效样本（有 >= ", PARAMS$min_valid_days, " 个有效日）：", nrow(per), " 人")

saveRDS(per, file.path(DIR_DERIV, "accel_daily.rds"))

# =============================================================================
# Part B. 分钟级文件处理（仅当需要 MVPA 时长 / Peak-30 时运行）
# =============================================================================
# PAXMIN 巨大，三种做法，任选其一：
#   B1（推荐）读 PhysioNet 1440 宽表：
#      nhanes_1440_PAXMTSM.csv.xz  -> 每行 = 1 人 1 天, 1440 列 = 每分钟 MIMS
#   B2 data.table::fread 直接读 xpt 转 csv（仍需 ~8-16 GB 内存）
#   B3 分块读 xpt（下方函数，最稳但慢）

# ---- B3. 分块读 PAXMIN（只保留 >=25 岁的 SEQN，且只留必要列） --------------
read_paxmin_chunked <- function(cycle, keep_seqn, keep_cols =
                                c("SEQN","PAXDAYM","PAXMTSM","PAXPREDM","PAXQFM"),
                                chunk_rows = 5e6) {
  f <- file.path(DIR_RAW, sprintf("PAXMIN_%s.xpt", cycle))
  if (!file.exists(f)) return(NULL)
  con <- file(f, "rb")
  on.exit(close(con))
  out <- vector("list", 0); i <- 0
  repeat {
    i <- i + 1
    ch <- try(haven::read_xpt(con, n_max = chunk_rows), silent = TRUE)
    if (inherits(ch, "try-error") || nrow(ch) == 0) break
    setDT(ch)
    ch <- ch[SEQN %in% keep_seqn, ..keep_cols]
    out[[i]] <- ch
  }
  rbindlist(out, use.names = TRUE, fill = TRUE)
}

# ---- B4. 分钟级清洗 + 指标 --------------------------------------------------
# 清洗规则：PAXMTSM == -0.01 | PAXPREDM == 3 | PAXQFM != 0  -> 置缺失
# 清醒佩戴分钟：PAXPREDM == 1 且 PAXQFM == 0
build_minute_metrics <- function(min_dt, mvpa_threshold = NULL) {
  setDT(min_dt)
  min_dt[, clean_mims := fifelse(
    is.na(PAXMTSM) | PAXMTSM == -0.01 | PAXPREDM == 3 | PAXQFM != 0,
    NA_real_, PAXMTSM)]
  min_dt[, is_wake_valid := PAXPREDM == 1 & PAXQFM == 0]

  res <- list()

  # (1) MVPA 分钟数/天（需切点；无权威切点时按敏感性分析给多套）
  if (!is.null(mvpa_threshold)) {
    mvpa <- min_dt[is_wake_valid == TRUE & !is.na(clean_mims) & clean_mims >= mvpa_threshold,
                   .(mvpa_min = .N), by = .(SEQN, PAXDAYM)]
    res$mvpa <- mvpa
  }

  # (2) Peak-30：日内活动最高的连续 30 分钟均值（最能代表 MVPA，无需切点）
  peak <- min_dt[is_wake_valid == TRUE & !is.na(clean_mims),
                 .(peak30 = {
                   v <- sort(clean_mims, decreasing = TRUE)
                   if (length(v) >= 30) mean(v[1:30]) else NA_real_
                 }), by = .(SEQN, PAXDAYM)]
  res$peak30 <- peak

  res
}

# 用法示例（需先准备好 keep_seqn = 年龄>=25 的 SEQN 向量）：
# minG <- read_paxmin_chunked("G", keep_seqn); minH <- read_paxmin_chunked("H", keep_seqn)
# mm   <- build_minute_metrics(rbindlist(list(minG, minH)),
#                              mvpa_threshold = 4096)   # 切点仅作敏感性分析！
# 注意：MIMS 目前无外部验证的 MVPA 切点，主分析请用 mims_per_day 与 peak30。

message("02 完成：日级暴露已生成 -> data/derived/accel_daily.rds")
