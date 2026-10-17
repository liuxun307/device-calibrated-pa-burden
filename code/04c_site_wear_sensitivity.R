# =============================================================================
# 04c_site_wear_sensitivity.R
# 「佩戴部位效应矛盾」的 wear/判据敏感性：髋侧规则 × 腕侧判据 → 部位效应比值矩阵
# -----------------------------------------------------------------------------
# 要裁决的矛盾
#   NHANES 自估（04b，同一调查体系内对照）：腕/髋比值 ≈ 1.00（9 点里 8 点 CI 含 1）
#   文献池自估（05c A 档，EK19 髋 LPA vs SV25 腕 LPA）：hip/wrist @off60 = 0.658
#                                                        [0.496, 0.873], p=0.0037
#   两者方向相反 → 必须查清是「真实部位效应」还是「口径假象」。
#
# 本脚本查的口径通道（此前未被排除的最大嫌疑）
#   ① 髋侧 wear 判定算法：03c 用同一份未掩码分钟 counts 换 5 套规则
#   ② 腕侧有效日判据与窗口语义：03d 换 7 套判据（含「全天佩戴」向髋侧对齐）
#   ③ 指标轴：髋侧总量 vs 髋侧轻强度体量（Troiano 100-2020 counts/min 带）
#
# 关键设计
#   · 所有曲线都用 lib/pa_site_lib.R 的**同一套拟合**（加权 Cox + 自然样条 + 同一组协变量）
#   · 参照点 = 各自人群**加权 12.5 百分位**（= BoP 的 ref_canon），只在百分位轴上比较
#   · 两波是独立样本 → 系数独立抽样 → log(RR_wrist) − log(RR_hip) 的抽样分布给 CI
#   · 每个曲线规格用**独立且钉死**的随机种子 → 逐字节可复现
#   · 强制等价性核验：(R0 × C0) 必须复现 04b 的 Table6
#
# 输出
#   output/Table8_hip_wear_rule_curves.csv     髋侧 5 规则（+3 体量带）曲线
#   output/Table8_wrist_criterion_curves.csv   腕侧 7 判据曲线
#   output/Table8_site_ratio_matrix.csv        5×7 比值矩阵（长表，逐百分位）
#   output/Table8_site_ratio_summary.csv       关键档位摘录（off30/60/80）
#   output/Table8_metric_axis_check.csv        指标轴对照（总量 vs LPA 体量）
#   output/QC_site_wear_sensitivity.csv        各档样本量/事件数/参照点/直方图诊断
#   output/QC_site_R0C0_equivalence.csv        与 04b Table6 的等价性核验
# =============================================================================

# ---- 统一引导 -----------------------------------------------------------------
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
  if (is.null(.ps)) stop("未找到 00_setup.R：请 setwd() 到 code/ 目录后重试")
  source(.ps); rm(.ps, .c)
}
suppressPackageStartupMessages({ library(data.table); library(survey); library(splines); library(MASS) })
source(file.path("lib", "pa_site_lib.R"))
pa_log("===== 04c 部位效应 wear/判据敏感性（矩阵式）=====")
pa_log("lib 版本：", PA_SITE_LIB_VERSION)

N_DRAWS  <- as.integer(Sys.getenv("PA_N_DRAWS_SITE", unset = "1000"))
COVARS   <- PA_SITE_COVARS
PCT_GRID <- PA_SITE_PCT_GRID
REF_PCT  <- PA_SITE_REF_PCT

# =============================================================================
# 1. 载入两侧变体数据集，协变量定义对齐
# =============================================================================
HIP_RULES  <- c("R0_choi2011", "R1_anydata", "R2_signal_gt0", "R3_no_zero_run60", "R4_awake_signal")
WRI_CRITS  <- c("C0_wake600", "C1_allwear600", "C2_wake720", "C3_valid600_qual",
                "C4_allwear600_qual", "C5_allwear600_d6", "C6_allwear600_d7")
HIP_BANDS  <- c("sed_lt100__R0", "lpa_100_2020__R0", "mvpa_ge2020__R0")
HIP_UNIT   <- "counts/day（体量型）"
WRI_UNIT   <- "MIMS/day（体量型）"

hip <- as.data.table(readRDS(file.path(DIR_DERIV, "pam_hip_wearvariants.rds")))
wri <- as.data.table(readRDS(file.path(DIR_DERIV, "wrist_criterion_variants.rds")))

# 腕侧 RIDRETH3（拆出 Asian）→ 折叠为 5 类，与髋侧 RIDRETH1 对齐（与 04b 同一映射）
RIDRETH3_TO_5 <- c(`1`="Mexican American", `2`="Other Hispanic", `3`="NH White",
                   `4`="NH Black", `5`="Other", `6`="Other", `7`="Other")
wri[, race := factor(RIDRETH3_TO_5[as.character(as.integer(as.character(RIDRETH3)))],
                     levels = c("Mexican American","Other Hispanic","NH White","NH Black","Other"))]

# =============================================================================
# 2. 拟合：髋侧规则 / 体量带 / 腕侧判据
# =============================================================================
fits_hip <- list(); fits_wri <- list(); qc <- list()

for (i in seq_along(HIP_RULES)) {
  r  <- HIP_RULES[i]
  col <- paste0("counts_per_day__", r)
  ft <- fit_site_curve(hip, col, sprintf("NHANES 2003-2006 髋式 [%s]", r),
                       covars = COVARS, ref_pct = REF_PCT, pct_grid = PCT_GRID)
  ft$draws <- draw_loghr(ft, N_DRAWS, PA_SEED + 100L + i)      # 种子：钉死、各规则独立
  ft$rule <- r; ft$unit <- HIP_UNIT
  fits_hip[[r]] <- ft
  qc[[paste0("hip_", r)]] <- data.table(
    side = "hip", spec = r, n = ft$n, n_death = ft$n_death,
    ref_expo = round(ft$ref_val, 1), p95_expo = round(ft$expo_grid[9], 1), unit = HIP_UNIT,
    n_draws = N_DRAWS, seed = PA_SEED + 100L + i)
}

# 髋侧体量带（指标轴检验；仅在 R0 的 wear 集合上，人群与 R0 完全相同）
for (k in seq_along(HIP_BANDS)) {
  b  <- HIP_BANDS[k]
  ft <- fit_site_curve(hip, b, sprintf("NHANES 2003-2006 髋式 [%s 体量带]", b),
                       covars = COVARS, ref_pct = REF_PCT, pct_grid = PCT_GRID)
  ft$draws <- draw_loghr(ft, N_DRAWS, PA_SEED + 150L + k)
  ft$rule <- b; ft$unit <- "counts/day（体量型，限该强度带）"
  fits_hip[[b]] <- ft
  qc[[paste0("hip_", b)]] <- data.table(
    side = "hip", spec = b, n = ft$n, n_death = ft$n_death,
    ref_expo = round(ft$ref_val, 1), p95_expo = round(ft$expo_grid[9], 1),
    unit = ft$unit, n_draws = N_DRAWS, seed = PA_SEED + 150L + k)
}

for (j in seq_along(WRI_CRITS)) {
  cn  <- WRI_CRITS[j]
  col <- paste0("mims_per_day__", cn)
  ft  <- fit_site_curve(wri, col, sprintf("NHANES 2011-2014 腕式 [%s]", cn),
                        covars = COVARS, ref_pct = REF_PCT, pct_grid = PCT_GRID)
  ft$draws <- draw_loghr(ft, N_DRAWS, PA_SEED + 200L + j)
  ft$rule <- cn; ft$unit <- WRI_UNIT
  fits_wri[[cn]] <- ft
  qc[[paste0("wri_", cn)]] <- data.table(
    side = "wrist", spec = cn, n = ft$n, n_death = ft$n_death,
    ref_expo = round(ft$ref_val, 1), p95_expo = round(ft$expo_grid[9], 1),
    unit = WRI_UNIT, n_draws = N_DRAWS, seed = PA_SEED + 200L + j)
}

# ---- 曲线表 ------------------------------------------------------------------
curve_rows <- function(fits, side) rbindlist(lapply(fits, function(ft) {
  q <- function(x, p) as.numeric(quantile(x, p, na.rm = TRUE))
  data.table(
    side = side, spec = ft$rule, n = ft$n, n_death = ft$n_death,
    pct = ft$pct, offset = ft$pct - REF_PCT,
    exposure = round(ft$expo_grid, 1), unit = ft$unit,
    rr = exp(ft$loghr),
    rr_lo = exp(apply(ft$draws, 2, q, p = 0.025)),
    rr_hi = exp(apply(ft$draws, 2, q, p = 0.975)))
}))
fwrite(curve_rows(fits_hip, "hip"),   file.path(DIR_OUT, "Table8_hip_wear_rule_curves.csv"))
fwrite(curve_rows(fits_wri, "wrist"), file.path(DIR_OUT, "Table8_wrist_criterion_curves.csv"))

# =============================================================================
# 3. 部位效应比值矩阵（ref = 髋式，alt = 腕式；比值 = 腕式 / 髋式）
# =============================================================================
ratio_one <- function(fh, fw, tag_h, tag_w) {
  DH <- fh$draws; DW <- fw$draws
  DIFF <- DW - DH
  q <- function(x, p) as.numeric(quantile(x, p, na.rm = TRUE))
  data.table(
    hip_rule = tag_h, wrist_criterion = tag_w,
    pct = fh$pct, offset = fh$pct - REF_PCT,
    n_hip = fh$n, n_death_hip = fh$n_death,
    n_wrist = fw$n, n_death_wrist = fw$n_death,
    rr_hip = exp(fh$loghr), rr_wrist = exp(fw$loghr),
    # 逐字节确定的「插入式」比值（点估计，不含抽样）
    ratio_plugin = exp(fw$loghr - fh$loghr),
    # 抽样分布均值 + 95% 区间（两臂独立）
    ratio_mean = exp(colMeans(DIFF)),
    ratio_lo   = exp(apply(DIFF, 2, q, p = 0.025)),
    ratio_hi   = exp(apply(DIFF, 2, q, p = 0.975)),
    p_value    = apply(DIFF, 2, function(v) 2 * min(mean(v > 0), mean(v < 0))))
}

MAT <- rbindlist(lapply(HIP_RULES, function(r) rbindlist(lapply(WRI_CRITS, function(cn)
  ratio_one(fits_hip[[r]], fits_wri[[cn]], r, cn)))))
fwrite(MAT, file.path(DIR_OUT, "Table8_site_ratio_matrix.csv"))

# ---- 关键档位摘录 -------------------------------------------------------------
KEY_OFF <- c(30, 60, 80)
SUM_KEY <- MAT[offset %in% KEY_OFF, .(hip_rule, wrist_criterion, offset,
                                     ratio_plugin = round(ratio_plugin, 3),
                                     ratio_mean = round(ratio_mean, 3),
                                     lo = round(ratio_lo, 3), hi = round(ratio_hi, 3),
                                     p = signif(p_value, 3),
                                     n_hip, n_wrist)]
fwrite(SUM_KEY, file.path(DIR_OUT, "Table8_site_ratio_summary.csv"))

# =============================================================================
# 4. 指标轴对照（髋侧总量 vs 髋侧轻强度体量）
# =============================================================================
rel <- function(f, off) exp(f$loghr[f$pct - REF_PCT == off])
axis_dt <- data.table(
  metric = c("总量 counts（R0）", "轻强度体量 LPA 100-2020", "静坐体量 <100", "MVPA 体量 >=2020"),
  spec   = c("R0_choi2011", "lpa_100_2020__R0", "sed_lt100__R0", "mvpa_ge2020__R0"))
axis_dt[, `:=`(
  rr_off30 = round(sapply(spec, function(s) rel(fits_hip[[s]], 30)), 3),
  rr_off60 = round(sapply(spec, function(s) rel(fits_hip[[s]], 60)), 3),
  rr_off80 = round(sapply(spec, function(s) rel(fits_hip[[s]], 80)), 3))]
axis_dt[, 降幅_off80_vs_off30 := round(rr_off80 / rr_off30, 3)]
fwrite(axis_dt, file.path(DIR_OUT, "Table8_metric_axis_check.csv"))

# =============================================================================
# 5. 等价性核验：(R0 × C0) 必须复现 04b 的 Table6
# =============================================================================
t6p <- file.path(DIR_OUT, "Table6_nhanes_hip_wrist_RR.csv")
eq_rows <- list()
if (file.exists(t6p)) {
  t6 <- fread(t6p)
  m  <- MAT[hip_rule == "R0_choi2011" & wrist_criterion == "C0_wake600"]
  # ⚠️ 比什么要想清楚：
  #   · rr_hip / rr_wrist 是 exp(loghr)，**不含抽样** → 必须逐值相同（机器精度）
  #   · Table6 的 rr_ratio_wr_hip = exp(colMeans(DIFF)) 是**抽样均值**，与本脚本的
  #     ratio_mean 同估量但不同随机流 → 只允许「蒙特卡洛误差」量级的差异
  #   · 本脚本额外给的 ratio_plugin = exp(loghr_wrist − loghr_hip) 是确定量，
  #     应与 Table6 的 exp(log(rr_wrist) − log(rr_hip)) **逐值相同**
  d_hip <- max(abs(m$rr_hip   - t6$rr_hip))
  d_wri <- max(abs(m$rr_wrist - t6$rr_wrist))
  d_plg <- max(abs(m$ratio_plugin - exp(log(t6$rr_wrist) - log(t6$rr_hip))))
  d_mc  <- max(abs(m$ratio_mean   - t6$rr_ratio_wr_hip))
  grid_ok <- identical(sort(m$pct), sort(t6$pct))
  ok <- grid_ok && d_hip < 1e-10 && d_wri < 1e-10 && d_plg < 1e-10
  chk <- data.table(
    item = c("Table6 pct 网格一致", "rr_hip 最大绝对偏差", "rr_wrist 最大绝对偏差",
             "插入式比值最大绝对偏差", "抽样均值比值最大绝对偏差（蒙特卡洛，非误差）",
             "抽样均值比值是否在 MC 容差内（<0.05）", "结论"),
    value = c(as.character(grid_ok), signif(d_hip, 3), signif(d_wri, 3), signif(d_plg, 3),
              signif(d_mc, 3), as.character(d_mc < 0.05),
              if (ok && d_mc < 0.05)
                "PASS：R0×C0 与 04b Table6 同源（点估计达机器精度，比值差 = 蒙特卡洛噪声）"
              else "*** 需检查：与 04b Table6 不一致 ***"))
  eq_rows <- list(chk)
  pa_log("R0×C0 等价性：", chk$value[7], "｜rr_hip 偏差 ", signif(d_hip, 3),
         "，rr_wrist 偏差 ", signif(d_wri, 3), "，插入式比值偏差 ", signif(d_plg, 3),
         "，抽样均值比值差 ", signif(d_mc, 3), "（MC 噪声）")
} else {
  eq_rows <- list(data.table(item = "结论", value = "跳过（Table6 不存在，请先跑 04b）"))
}
fwrite(rbindlist(eq_rows), file.path(DIR_OUT, "QC_site_R0C0_equivalence.csv"))

# =============================================================================
# 6. QC 汇总
# =============================================================================
QC <- rbindlist(qc)
# 佩戴/暴露分布诊断：两波是否可比（判据差异最直接的可见后果就在分布上）
dist_row <- function(side, spec, v, unit = "min/day") {
  v <- v[!is.na(v)]
  data.table(side = side, spec = spec, n = NA_integer_, n_death = NA_integer_,
             ref_expo = NA_real_, p95_expo = NA_real_, unit = unit,
             n_draws = NA_integer_, seed = NA_integer_,
             dist_p25 = round(quantile(v, .25)), dist_med = round(median(v)),
             dist_p75 = round(quantile(v, .75)))
}
QC <- rbind(QC,
  dist_row("hip",   "佩戴分钟（R0 Choi 全天）",     hip$wear_mean_min__R0_choi2011),
  dist_row("wrist", "清醒佩戴分钟（C0 wake600）",   wri$wake_min_per_day__C0_wake600),
  dist_row("wrist", "全天佩戴分钟（C1 allwear600）", wri$allwear_min_per_day__C1_allwear600),
  dist_row("hip",   "counts/day（R0）",            hip$counts_per_day__R0_choi2011, "counts/day"),
  dist_row("hip",   "counts/day（R2 信号>0）",      hip$counts_per_day__R2_signal_gt0, "counts/day"),
  dist_row("wrist", "MIMS/day（C0）",              wri$mims_per_day__C0_wake600, "MIMS/day"),
  dist_row("wrist", "MIMS/day（C1 全天佩戴）",      wri$mims_per_day__C1_allwear600, "MIMS/day"),
  fill = TRUE)
fwrite(QC, file.path(DIR_OUT, "QC_site_wear_sensitivity.csv"))

# =============================================================================
# 7. 读数打印
# =============================================================================
cat("\n========== A. 髋侧 wear 规则：曲线随规则的变化（总量轴，参照 = 12.5 百分位）==========\n")
print(dcast(curve_rows(fits_hip[HIP_RULES], "hip")[offset %in% c(30, 60, 80)],
            offset ~ spec, value.var = "rr"),
      digits = 4)

cat("\n========== B. 腕侧判据：曲线随判据的变化 ==========\n")
print(dcast(curve_rows(fits_wri, "wrist")[offset %in% c(30, 60, 80)],
            offset ~ spec, value.var = "rr"),
      digits = 4)

cat("\n========== C. 部位效应比值（腕/髋）关键档 ==========\n")
print(dcast(SUM_KEY[offset == 60], hip_rule ~ wrist_criterion,
            value.var = "ratio_plugin"), digits = 3)
cat("\n  （上表 = offset 60 处「腕式 RR ÷ 髋式 RR」；1.00 = 无部位效应）\n")

cat("\n========== D. 指标轴对照（髋侧，同一人群）==========\n")
print(axis_dt)

cat("\n========== E. 全部 35 个组合 @offset60 的范围 ==========\n")
s <- MAT[offset == 60]
cat(sprintf("  ratio_plugin 范围: %.3f ~ %.3f（中位 %.3f）\n", min(s$ratio_plugin), max(s$ratio_plugin), median(s$ratio_plugin)))
cat(sprintf("  其中 95%%CI 不含 1 的组合数: %d / %d\n", sum(s$p_value < 0.05), nrow(s)))
cat(sprintf("  其中 CI 完全在 1 以上的组合数: %d；完全在 1 以下的组合数: %d\n",
            sum(s$ratio_lo > 1), sum(s$ratio_hi < 1)))

pa_log("04c 完成 -> Table8_* 系列（矩阵 35 组合 × 9 档位）")
