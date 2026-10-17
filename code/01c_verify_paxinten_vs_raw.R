# =============================================================================
# 01c_verify_paxinten_vs_raw.R
# 一致性核验：rnhanesdata 的 PAXINTEN_C/D 是否忠实等于原始 xpt 的分钟计数
# -----------------------------------------------------------------------------
# 为什么必须做这一步
#   Module 3 与「佩戴部位效应」两条链路的髋式暴露，都不是从原始 ZIP 现场算的，
#   而是用 rnhanesdata 已处理好的 1440+ 宽表（PAXINTEN_C/D）+ wear 标志（Flags_C/D）。
#   这属于**外部衍生数据**，必须证明它与我们手上的原始下载件一致，否则
#   「原始数据 + 分析代码 + 过程可复现」这条硬要求就断了。
#
# 核验口径（最强的可得形式：全文件、全部受试者，不是抽样）
#   对每个 SEQN，比较两个量：
#     · 原始 xpt      ：该 SEQN 全部分钟行的 (a) 行数 n_min_raw，(b) 计数总和 sum_raw
#     · PAXINTEN 宽表 ：该 SEQN 的 1440 列中 (a) 非 NA 格数 n_ok_mat，(b) na.rm 后的总和
#   两者应当逐人完全相等（浮点按 1e-6 相对容差比）。
#
# ⚠️ 关键结构事实（2026-10-12 首次运行踩到，务必牢记）
#   rnhanesdata 的 PAXINTEN_* / Flags_* 是 **受试者-日** 表：同一个 SEQN 占 **多行**
#   （每人恰 7 行 × 1440 列，对应 7 个测量日），而不是「一人一行」。
#   原始 xpt 同理：一人 10080 行 = 7 天 × 1440 分钟。
#   → 因此两侧都必须**先按 SEQN 汇总**再比；若只 merge(by="SEQN")，data.table 会把
#     宽表的 7 行展开成 7 条匹配，或用 match 只取第 1 行 → 必然报「不一致」的假阳性。
#     首次运行正是如此：SEQN 31128 原始 10080 分钟 / 2,421,730 计数，
#     宽表单行 1440 分钟 / 377,456 计数 —— 但宽表 7 行加总 = 2,421,730，逐值相等。
#
# 说明：只读 SEQN 与 PAXINTEN 两列（col_select），把内存从 ~4.6 GB 降到 ~1.2 GB。
# =============================================================================

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
suppressPackageStartupMessages({ library(data.table); library(haven) })
pa_log("===== 01c 核验：PAXINTEN 宽表 vs 原始 xpt =====")

XPT_DIR <- file.path(PA_ROOT, "data", "scratch", "pam_extracted")
RNH_DIR <- file.path(DIR_RAW, "rnhanesdata_ref")
rows <- list()

for (w in c("C", "D")) {
  xpt <- file.path(XPT_DIR, paste0("paxraw_", tolower(w), ".xpt"))
  rda <- file.path(RNH_DIR, paste0("PAXINTEN_", w, ".rda"))
  if (!file.exists(xpt) || !file.exists(rda)) {
    pa_log("跳过 ", w, "：缺 ", basename(xpt), " 或 ", basename(rda), level = "WARN"); next
  }

  t0 <- Sys.time()
  pa_log("[", w, "] 读取原始 xpt（仅 SEQN + PAXINTEN 两列）...")
  raw <- read_xpt(xpt, col_select = c("SEQN", "PAXINTEN"))
  setDT(raw)
  pa_log(sprintf("[%s] 原始行数 %s，用时 %.1f 分钟",
                 w, format(nrow(raw), big.mark = ","),
                 as.numeric(difftime(Sys.time(), t0, units = "mins"))))

  agg <- raw[, .(n_min_raw = .N, sum_raw = sum(PAXINTEN, na.rm = TRUE)), by = SEQN]
  n_subj_raw <- nrow(agg)
  rows_per_subj_raw <- raw[, .N, by = SEQN]$N
  pa_log(sprintf("[%s] 原始：%s 行 / %s 人；每人行数 min=%d max=%d（应 = 7×1440 = 10080）",
                 w, format(nrow(raw), big.mark = ","), format(n_subj_raw, big.mark = ","),
                 min(rows_per_subj_raw), max(rows_per_subj_raw)))
  rm(raw, rows_per_subj_raw); gc(verbose = FALSE)

  pa_log("[", w, "] 读取 PAXINTEN 宽表...")
  e <- new.env(); load(rda, envir = e)
  it <- setDT(get(paste0("PAXINTEN_", w), envir = e))
  mn <- paste0("MIN", 1:1440)
  Im <- as.matrix(it[, ..mn])
  agg2 <- data.table(
    SEQN      = it$SEQN,
    n_ok_mat  = rowSums(!is.na(Im)),
    sum_mat   = rowSums(Im, na.rm = TRUE))
  rm(Im); gc(verbose = FALSE)

  # ⚠️ 必须先按 SEQN 汇总（每人 7 个日行）——见文首「关键结构事实」
  rows_per_subj_wide <- agg2[, .N, by = SEQN]$N
  agg2 <- agg2[, .(n_ok_mat = sum(n_ok_mat), sum_mat = sum(sum_mat)), by = SEQN]
  pa_log(sprintf("[%s] 宽表：%s 日行 / %s 人（合并后）；每人日行数 min=%d max=%d",
                 w, format(sum(rows_per_subj_wide), big.mark = ","),
                 format(nrow(agg2), big.mark = ","),
                 min(rows_per_subj_wide), max(rows_per_subj_wide)))
  rm(rows_per_subj_wide); gc(verbose = FALSE)

  m <- merge(agg, agg2, by = "SEQN", all = TRUE)
  m[, `:=`(d_n   = n_min_raw - n_ok_mat,
           d_sum = sum_raw - sum_mat)]
  tol <- 1e-6
  m[, ok_n := is.na(d_n) | d_n == 0]
  m[, ok_s := is.na(d_sum) | abs(d_sum) <= tol * pmax(1, abs(sum_raw))]
  m[, ok   := ok_n & ok_s]

  n_tot <- nrow(m); n_ok <- sum(m$ok)
  n_bad_n <- sum(!m$ok_n); n_bad_s <- sum(!m$ok_s)
  pa_log(sprintf("[%s] 逐人核验：%d / %d 人完全一致（行数不符 %d，总和不符 %d）",
                 w, n_ok, n_tot, n_bad_n, n_bad_s))
  if (n_bad_n || n_bad_s) {
    cat("\n--- 不一致示例（最多 10 条）---\n")
    print(head(m[!(ok)], 10))
  }
  cat(sprintf("\n[%s] 全文件汇总：原始非NA分钟 %s | 宽表非NA格 %s 分钟 | 计数总和 原始 %.0f vs 宽表 %.0f\n",
              w, format(sum(m$n_min_raw, na.rm = TRUE), big.mark = ","),
              format(sum(m$n_ok_mat,  na.rm = TRUE), big.mark = ","),
              sum(m$sum_raw, na.rm = TRUE), sum(m$sum_mat, na.rm = TRUE)))

  rows[[w]] <- data.table(
    wave = w,
    n_subjects = n_tot, n_subj_raw = n_subj_raw, n_identical = n_ok,
    mismatch_minutes = n_bad_n, mismatch_sums = n_bad_s,
    raw_total_counts  = sum(m$sum_raw, na.rm = TRUE),
    wide_total_counts = sum(m$sum_mat, na.rm = TRUE))
}

if (length(rows)) {
  VER <- rbindlist(rows, use.names = TRUE, fill = TRUE)
  VER[, verdict := fifelse(n_identical == n_subjects,
                           "PASS 全文件逐人完全一致", "CHECK 存在不一致")]
  fwrite(VER, file.path(DIR_OUT, "QC_paxinten_vs_raw.csv"))
  cat("\n===== 核验结论 =====\n"); print(VER)
  pa_log("01c 完成 -> output/QC_paxinten_vs_raw.csv")
}
