# =============================================================================
# 95b_paf_impact_compare.R
# 路径 2 影响力敏感性：把「文献池 A」与「文献池 + NHANES 两臂 B」的两套 PAF 并列
# =============================================================================
# 为什么要单列一个脚本
#   05c 产出的 bop_rr_draws_withNHANES.rds 必须喂给 95_module3_paf.R 才会产生 B 档 PAF。
#   95 的输出文件名可用 PA_OUT_PREFIX 覆盖，但**同一进程只能产出档**，所以 A/B 两档必然
#   来自两次独立运行。本脚本负责：
#     ① 若 B 档产物缺失 → 自动以 PA_RR_DRAWS/PA_OUT_PREFIX/PA_PREVIEW_TAG 跑一次 95；
#     ② 【可选】以 PA_VERIFY_DEFAULT=1 触发「默认参数 + 仅换前缀」的再跑一遍，
#        用 md5 证明新增的环境变量覆盖**没有**改变默认行为（相对 ② 的冻结产物）；
#     ③ 逐格比较 A vs B 的 PAF / 归因死亡 / 相对 GBD 倍数，并分病因对照。
#
# ⚠️ 本脚本**只读** 95 的产物，不改动 PREVIEW_module3_*（② 的冻结产物）。
#
# 输入
#   output/PREVIEW_module3_totals.csv / by_cause.csv      A 档（= 主链 95 的正常产物）
#   output/PREVIEW_NHANES_s1p_*.csv                       B 档（本脚本按需生成，前缀见 P_B）
#   output/VERIFY_default_*.csv                           行为不变性证据（可选，见 ②）
#   ⚠️ 2026-10-16 更正：B 档前缀是 PREVIEW_NHANES_**s1p**_（= P_B）。
#      旧文档写的 PREVIEW_NHANES_totals.csv / by_cause.csv（无 s1p）是 10-12 旧命名遗留的
#      **陈旧孤儿文件**，已无人生成；`output/` 里若还留着它们，不要当作 B 档产物引用。
# 输出
#   output/Table7_bop_nhanes_paf_impact.csv               逐 location×year×rr_source 对照
#   output/Table7_bop_nhanes_paf_impact_by_cause.csv      分病因对照（Global 2022，cv=0.6）
#   output/QC_95_env_override_invariance.csv              行为不变性 md5 核验记录
#   logs/95b_paf_impact_compare.log                       运行日志
#
# 用法
#   cd code
#   Rscript 95b_paf_impact_compare.R                 # 复用已有 B 档（无则生成）
#   Rscript 95b_paf_impact_compare.R --force         # 强制重跑 B 档
#   PA_VERIFY_DEFAULT=1 Rscript 95b_paf_impact_compare.R   # 额外做行为不变性再验证（+约 12 min）
#
# ⚠️ 本脚本**不在** 00_run_all.R 的 ALL_STEPS 里：它需要把 95 跑两遍（约 25 min），
#    属按需触发的敏感性分析，而非每次全流程的必需步骤。
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
suppressPackageStartupMessages({ library(data.table) })
pa_log("===== 95b 路径 2 影响力敏感性：A（文献池）vs B（文献池 + NHANES）=====")

args     <- commandArgs(TRUE)
FORCE    <- "--force" %in% args
VERIFY   <- identical(Sys.getenv("PA_VERIFY_DEFAULT", unset = ""), "1")
CV_MAIN  <- 0.6

# A 档必须与主分析轨一致（s1p = S1′，人口加权 cell 级暴露分布）。
# ⚠️ 2026-10-15 修正：原先 P_A = "PREVIEW_module3_" 读的是 **grid 轨**（S3 网格 +
#    未人口加权），而 09 / 95c / 97 都读 s1p 轨 → 自检表出现 1.7% 的**跨轨假差异**，
#    当时误判为 Monte Carlo 噪声。口径不同不是噪声，必须同轨比较。
P_A <- "PREVIEW_module3_s1p_"
P_B <- "PREVIEW_NHANES_s1p_"
P_V <- "VERIFY_default_"
TAG_B <- "PREVIEW_NHANESpool_RealRR_S1pSD"
LOG95 <- file.path(DIR_LOGS, "95b_step95.log")

f <- function(prefix, what) file.path(DIR_OUT, paste0(prefix, what, ".csv"))

# ---------------------------------------------------------------------------
# 1. 按需生成 B 档（A 档由主链的 95 产出）
# ---------------------------------------------------------------------------
run95 <- function(prefix, tag, draws = NA_character_) {
  rs <- file.path(R.home("bin"), "Rscript.exe")
  if (!file.exists(rs)) rs <- file.path(R.home("bin"), "x64", "Rscript.exe")
  if (!file.exists(rs)) rs <- file.path(R.home("bin"), "Rscript")
  old <- Sys.getenv(c("PA_OUT_PREFIX", "PA_PREVIEW_TAG", "PA_RR_DRAWS", "PA_CV_MODE"), unset = NA)
  # ⚠️ 必须与 A 档同轨（s1p）：否则 A/B 对比混入 CV 口径差异
  Sys.setenv(PA_OUT_PREFIX = prefix, PA_PREVIEW_TAG = tag, PA_CV_MODE = "s1p")
  if (is.na(draws)) Sys.unsetenv("PA_RR_DRAWS") else Sys.setenv(PA_RR_DRAWS = draws)
  old_wd <- getwd(); setwd(DIR_CODE)
  st <- system2(rs, "95_module3_paf.R", stdout = LOG95, stderr = LOG95, wait = TRUE)
  setwd(old_wd)
  for (k in names(old)) if (is.na(old[k])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(setNames(old[k], k)))
  invisible(st)
}

b_missing <- !file.exists(f(P_B, "totals")) || !file.exists(f(P_B, "by_cause"))
if (b_missing || FORCE) {
  pa_log("生成 B 档（RR 后验 = bop_rr_draws_withNHANES.rds，前缀 ", P_B, "）...")
  draws_b <- file.path(DIR_OUT, "bop_rr_draws_withNHANES.rds")
  if (!file.exists(draws_b)) stop("缺少 ", draws_b, " —— 请先跑通 05c_module2_nhanes_site_sensitivity.R")
  t0 <- Sys.time()
  st <- run95(P_B, TAG_B, draws_b)
  pa_log(sprintf("B 档完成（exit=%s），用时 %.1f 分钟",
                 st, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  if (!identical(as.integer(st), 0L)) stop("B 档 95 运行失败，见 ", LOG95)
} else {
  pa_log("复用已有 B 档产物（如需重算加 --force）")
}
if (!file.exists(f(P_A, "totals"))) stop("缺少 ", f(P_A, "totals"), " —— 请先跑通主链的 95_module3_paf.R")

# ---------------------------------------------------------------------------
# 2. 【严格 opt-in】行为不变性验证
#    默认参数 + 仅换输出前缀 → 必须与 ② 的冻结件逐字节一致。
#    刻意**不**自动触发：新克隆若自动跑这一轮会白白多花约 12 min。
#    已在 VERIFY_default_* 里的结果会被复用并复核（不重跑）。
# ---------------------------------------------------------------------------
INV <- data.table()
if (VERIFY && !file.exists(f(P_V, "totals"))) {
  pa_log("行为不变性验证：以默认参数（不设 PA_RR_DRAWS）+ 前缀 ", P_V, " 再跑一遍 95 ...")
  t0 <- Sys.time()
  st <- run95(P_V, "PREVIEW_RealRR_S3SD")
  pa_log(sprintf("验证轮完成（exit=%s），用时 %.1f 分钟", st,
                 as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
ART <- paste0(c("totals", "by_cause", "exposure_diag", "rr_source_compare", "rr_bridge"), ".csv")
if (file.exists(f(P_V, "totals"))) {
  for (w in ART) {
    a <- f(P_A, w); b <- f(P_V, w)
    INV <- rbind(INV, data.table(
      artifact   = paste0(P_A, w),
      md5_frozen = if (file.exists(a)) tools::md5sum(a)[[1]] else NA_character_,
      md5_rerun  = if (file.exists(b)) tools::md5sum(b)[[1]] else NA_character_))
  }
  INV[, identical := fifelse(!is.na(md5_frozen) & !is.na(md5_rerun) & md5_frozen == md5_rerun,
                             "IDENTICAL", "DIFFERENT")]
} else {
  INV <- data.table(artifact = paste0(P_A, ART), md5_frozen = NA_character_,
                    md5_rerun = NA_character_, identical = "NOT_RUN")
}
# 内容确定（不含时间戳）→ 可在多次运行间逐字节复现
fwrite(INV, file.path(DIR_OUT, "QC_95_env_override_invariance.csv"))
cat("\n===== 行为不变性核验（默认参数 vs 冻结产物）=====\n"); print(INV[, .(artifact, identical)])
if (all(INV$identical == "NOT_RUN")) {
  pa_log("行为不变性：未运行（如需要：PA_VERIFY_DEFAULT=1 Rscript 95b_paf_impact_compare.R）", level = "WARN")
} else {
  pa_log(sprintf("行为不变性：%d/%d 逐字节一致 → %s",
                 sum(INV$identical == "IDENTICAL"), nrow(INV),
                 if (all(INV$identical == "IDENTICAL")) "默认行为未改变" else "⚠️ 默认行为已改变"))
}

# ---------------------------------------------------------------------------
# 3. A vs B 逐格对照
# ---------------------------------------------------------------------------
A <- fread(f(P_A, "totals"), encoding = "UTF-8")
B <- fread(f(P_B, "totals"), encoding = "UTF-8")
if (!"cv" %in% names(A)) A[, cv := NA_real_]
if (!"cv" %in% names(B)) B[, cv := NA_real_]
K <- c("location", "year", "rr_source")
m <- merge(
  A[, c(K, "recomputed_deaths", "paf_deaths", "gbd_deaths", "gbd_paf_deaths"), with = FALSE],
  B[, c(K, "recomputed_deaths", "paf_deaths"), with = FALSE],
  by = K, suffixes = c("_A", "_B"))
m[, `:=`(fold_A = recomputed_deaths_A / gbd_deaths,
         fold_B = recomputed_deaths_B / gbd_deaths,
         paf_drop_pct    = 100 * (paf_deaths_B - paf_deaths_A) / paf_deaths_A,
         deaths_drop_pct = 100 * (recomputed_deaths_B - recomputed_deaths_A) / recomputed_deaths_A)]

cat("\n=== 按 rr_source 分层的 PAF 相对变化（B 相对 A）===\n")
print(m[, .(n = .N, n_loc = uniqueN(location),
            paf_A_med = round(median(paf_deaths_A), 4), paf_B_med = round(median(paf_deaths_B), 4),
            drop_min = round(min(paf_drop_pct), 1), drop_med = round(median(paf_drop_pct), 1),
            drop_max = round(max(paf_drop_pct), 1),
            fold_A_med = round(median(fold_A), 2), fold_B_med = round(median(fold_B), 2)),
        by = rr_source])

cat("\n=== Global（rr_source = pooled）===\n")
print(m[location == "Global" & rr_source == "pooled"][order(year),
      .(year, paf_A = round(paf_deaths_A, 4), paf_B = round(paf_deaths_B, 4),
        deaths_A = round(recomputed_deaths_A), deaths_B = round(recomputed_deaths_B),
        drop_pct = round(paf_drop_pct, 1),
        fold_A = round(fold_A, 2), fold_B = round(fold_B, 2), gbd_deaths = round(gbd_deaths))])

cat("\n=== 8 个 location × 2022（rr_source = pooled）===\n")
print(m[year == 2022 & rr_source == "pooled"][order(-fold_A),
      .(location, paf_A = round(paf_deaths_A, 4), paf_B = round(paf_deaths_B, 4),
        drop_pct = round(paf_drop_pct, 1), fold_A = round(fold_A, 2), fold_B = round(fold_B, 2))])

# --- 分病因（主情景，rr_source = pooled）---
#   ⚠️ 主情景的定位方式随轨道不同：
#     · s1p 轨（现行 A/B 档）：主情景由 `is_main == TRUE` 标记，`cv` 列存的是该 location 的
#       人口加权 cv（Global ≈ 1.61），**不等于**网格值 0.6 → 若仍用 cv 比对会一行都取不到
#       （2026-10-15 实测：报「cv=0.6 的 Global 2022 行未对齐」并静默跳过整张分病因表）。
#     · grid 轨（旧口径）：cv 即网格值，主情景 = CV_MAIN。
pick_main <- function(D) {
  d <- D[location == "Global" & year == 2022 & rr_source == "pooled"]
  if (!nrow(d)) return(d)
  if ("is_main" %in% names(d) && any(d$is_main, na.rm = TRUE)) return(d[is_main == TRUE])
  d[abs(cv - CV_MAIN) < 1e-9]
}
CA <- fread(f(P_A, "by_cause"), encoding = "UTF-8")
CB <- fread(f(P_B, "by_cause"), encoding = "UTF-8")
a2 <- pick_main(CA)
b2 <- pick_main(CB)
if (nrow(a2) && nrow(a2) == nrow(b2)) {
  setorder(a2, -deaths_attrib)
  b2 <- b2[match(a2$cause, cause)]
  CAUSE <- data.table(cause = a2$cause,
                      deaths_A = round(a2$deaths_attrib), deaths_A_lo = round(a2$deaths_lo),
                      deaths_A_hi = round(a2$deaths_hi),
                      deaths_B = round(b2$deaths_attrib), deaths_B_lo = round(b2$deaths_lo),
                      deaths_B_hi = round(b2$deaths_hi))
  CAUSE[, drop_pct := round(100 * (deaths_B - deaths_A) / deaths_A, 1)]
  cat(sprintf("\n=== 分病因（Global 2022，rr_source=pooled，cv=%.4f）===\n",
              if ("cv" %in% names(a2)) a2$cv[1] else CV_MAIN))
  print(CAUSE)
  fwrite(CAUSE, file.path(DIR_OUT, "Table7_bop_nhanes_paf_impact_by_cause.csv"))
} else {
  pa_log("分病因对照跳过：Global 2022 pooled 主情景行未对齐", level = "WARN")
}

out <- m[, .(location, year, rr_source,
             paf_A = paf_deaths_A, paf_B = paf_deaths_B,
             deaths_A = recomputed_deaths_A, deaths_B = recomputed_deaths_B,
             gbd_deaths, gbd_paf_deaths, fold_A, fold_B, paf_drop_pct, deaths_drop_pct)]
fwrite(out, file.path(DIR_OUT, "Table7_bop_nhanes_paf_impact.csv"))

g22 <- m[location == "Global" & year == 2022 & rr_source == "pooled"]
cat("\n================================================================\n")
if (nrow(g22))
  cat(sprintf("结论：Global 2022，rr_source=pooled ——\n  A（文献池）  PAF=%.4f  归因死亡=%s  相对 GBD %.2f 倍\n  B（+NHANES） PAF=%.4f  归因死亡=%s  相对 GBD %.2f 倍\n  → PAF 相对变化 %+.1f%%；但**最保守池下仍为 GBD 现报值的 %.1f 倍**\n",
              g22$paf_deaths_A, format(round(g22$recomputed_deaths_A), big.mark = ","), g22$fold_A,
              g22$paf_deaths_B, format(round(g22$recomputed_deaths_B), big.mark = ","), g22$fold_B,
              g22$paf_drop_pct, g22$fold_B))
cat("================================================================\n")
pa_log("95b 完成 -> Table7_bop_nhanes_paf_impact{,_by_cause}.csv")
