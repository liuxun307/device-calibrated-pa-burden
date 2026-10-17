# =============================================================================
# 97_test_module3.R —— Module 3（GBD 接入）函数级真实数据自检
# -----------------------------------------------------------------------------
# 目的：在真实 GBD 2023 暴露文件上验证 05 的新增函数，而不是只做语法检查。
#   历史教训：本项目已出现 4 次「语法全过、一跑就崩」的真实缺陷
#   （前向引用 / 残留对象 / 求值顺序 / 矩阵列名），全部靠真实数据管道才暴露。
#
# 运行：
#   Rscript 97_test_module3.R
# 依赖：data/derived/analytic.rds（由 02/03 产出）、data/gbd/ 下的 GBD 暴露 CSV
# =============================================================================

# ---- 引导（必须在 setwd 之前，否则中文路径无法解析）----
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8",
                "English_United States.utf8", "C.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
})
CODE <- dirname(gsub("\\\\", "/", sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
if (is.na(CODE) || !dir.exists(CODE)) CODE <- getwd()
setwd(CODE)

source("05_burden_calibration_paf.R")
suppressPackageStartupMessages(library(data.table))

# 加权分位（自检用）
quantile_w <- function(x, w, p) {
  keep <- w > 0
  o <- order(x[keep]); x <- x[keep][o]; w <- w[keep][o]
  cw <- cumsum(w) / sum(w)
  approx(cw, x, xout = p, rule = 2, ties = "ordered")$y
}

cat("\n########## Module 3 自检 ##########\n")

cat("\n[1] find_gbd 是否命中官方暴露文件（旧版 ^risk.*csv$ 永远匹配不到）：\n")
print(basename(gbd_expo))

cat("\n[2] read_lpa_exposure 是否剔除 All Ages(22) / Age-standardized(27)：\n")
e <- read_lpa_exposure()
if (is.null(e)) {
  cat("  !! 未读到暴露文件，跳过后续\n")
} else {
  cat("  行数:", nrow(e), " 年龄组:", paste(sort(unique(e$age_group_id)), collapse = ","), "\n")
  cat("  含 22/27 ?", any(e$age_group_id %in% c(22, 27)), "（必须为 FALSE）\n")
  cat("  measure:", paste(unique(e$measure), collapse = ","),
      "（GBD 2023 只有 continuous，无分档比例、无 SD）\n")
}

cat("\n[3] 单调化校准：\n")
g <- seq(0, MET_CAP, length.out = 500)
cat("  pred_mims 单调不减?", all(diff(pred_mims(g)) >= 0), "（必须为 TRUE）\n")
cat("  校准 R2 =", round(summary(m_cal)$r.squared, 3),
    "  残差 SD =", round(SIGMA_MIMS), "\n")

cat("\n[4] exposure_dist 分布性质（mean = 3800 MET-min/wk）：\n")
d1 <- exposure_dist(mean_met = 3800, cv = 0.6)
cat("  sum(f) =", round(sum(d1$f), 8), "（必须 = 1）\n")
cat("  MET 尺度均值 =", round(sum(d1$met * d1$f_met)), "（应 ≈ 3800）\n")
cat("  设备尺度均值 =", round(d1$mean_mims), "MIMS/day\n")
cat("  设备尺度 P2.5/P97.5 =", round(quantile_w(d1$mims, d1$f, .025)), "/",
    round(quantile_w(d1$mims, d1$f, .975)), "\n")

cat("\n[5] CV 敏感性：\n")
for (cv in EXPO_SD_GRID) {
  dd <- exposure_dist(3800, cv)
  cat(sprintf("  CV=%.2f -> 设备均值 %.0f, P2.5/P97.5 %.0f/%.0f\n",
              cv, dd$mean_mims,
              quantile_w(dd$mims, dd$f, .025), quantile_w(dd$mims, dd$f, .975)))
}

cat("\n[6] 国别异质性检验（关键：校准太弱会压缩国别差异）：\n")
if (!is.null(e)) {
  yrs <- e[year_id == 2023 & age_group_id == 10 & sex == "Male"]
  lo <- yrs[order(mean)][1]; hi <- yrs[order(-mean)][1]
  for (r in list(lo, hi)) {
    dd <- exposure_dist(r$mean, cv = 0.6)
    cat(sprintf("  %-30s self-report %5.0f MET-min/wk -> device mean %5.0f MIMS/day\n",
                substr(r$location_name, 1, 30), r$mean, dd$mean_mims))
  }
  cat("  提示：若两侧设备均值几乎相同 -> 需改用 M2 保秩映射（见 05 注释）\n")
}

cat("\n[7] PAF 恒等式（RR 恒为 1.2 -> 应为 0.2/1.2 = 0.1667）：\n")
p <- paf_from_dist(d1$f, rep(1.2, length(d1$f)))
cat("  PAF =", round(p, 6), "  期望 =", round(0.2 / 1.2, 6),
    "  一致?", isTRUE(all.equal(p, 0.2 / 1.2)), "\n")

cat("\n[8] 阻塞项防护（CV = NA 必须报错而不是硬跑）：\n")
r <- try(exposure_dist(3800, NA_real_), silent = TRUE)
cat("  是否报错:", inherits(r, "try-error"), "\n")

cat("\n[9] TMREL 口径（GBD 2023：3600–4400 MET-min/wk）：\n")
cat("  ", tmrel_lo_met, "-", tmrel_hi_met, "MET-min/wk ->",
    round(tmrel_lo_mims), "-", round(tmrel_hi_mims), "MIMS/day\n")

cat("\n########## 自检结束 ##########\n")
