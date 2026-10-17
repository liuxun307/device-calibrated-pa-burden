# =============================================================================
# 04f_lit_site_anchor.R
# 文献侧部位效应：**指标稳健性**（腕式 × total_PA 的外部锚定）+ 与 NHANES 的**同指标**对照
# -----------------------------------------------------------------------------
# 命名说明：04e 已被 04e_pam_intensity_rr.R 占用，故本步取 04f；链上紧接 04d 之后
#   （依赖 04c 的 Table8_site_ratio_matrix.csv）。
# 状态变更（2026-10-16）：本步由 code/tools/site_anchor_totalPA.R **提升为正式步骤**并入主链。
#   原「只读分析、不入链」的定位已不适用 —— 其产物现被 10_captions.R 的补充表注引用，
#   与 05b/95b 当年入链的理由相同（产物被消费却留在链外会与主链不同步）。
#
# 为什么需要
#   04d 的「文献侧部位效应」只能对 **LPA** 出一个比值（EK19 髋 vs SV25 腕），
#   因为池内 total_PA 的髋侧有 EK19、腕侧为 0 行。
#   而 Module 3 的 PAF 恰恰由 `device_pooled × total_PA` 驱动 → 部位问题在主指标上无估计。
#
#   Ko2025（J Nephrol 2025）与 Inan-Eroglu2024（CEBP 2024）补上了腕侧 total_PA，
#   但**两者与池内 SV25 同属 UK Biobank 加速度计子队列** → 不得并入主池
#   （见 data/bop/20261016_入池裁定_UKB腕式总PA双源.md）。
#   它们可以在**本文件这种「跨来源直接对照」**里使用：该对照的髋侧（EK19）
#   与腕侧（Ko2025 / IE24）**互为独立队列**；UKB 重复只影响「并入池化」，
#   不影响「两来源相减」。
#
# 方法（与 04d 同口径；并对两个指标使用**同一个估计量**，使并列可比）
#   · 逐 offset 直接对照：ratio_wrist_over_hip = exp(y_wrist − y_hip)，
#     SE 为两侧 log-SE 平方和开方（>1 = 腕式 RR 更高 = 髋式更陡）
#   · 过原点斜率：b = Σ(w·off·y)/Σ(w·off²)，w = 1/se²（与主模型 `~0+mm:offset` 同构）；
#     髋/腕斜率比 = |b_hip|/|b_wrist|，CI 用对数尺度 delta
#   · **两指标并列**：LPA（EK19 髋 vs SV25 腕，均在池内）与
#     total_PA（EK19 髋 vs Ko2025 腕，腕侧来自锚点表）用同一估计量各算一遍
#   · **★ 新增（2026-10-16）指标对齐对照**：把文献侧 total_PA 的逐 offset 比值与
#     NHANES 同调查内 **total_PA**（04c 的 R0×C0）并列 —— 这是全项目**唯一指标对齐**的
#     部位对照（04d 侧因池内限制只能是跨指标）。它直接决定「髋式曲线能否用于腕式暴露侧」。
#   · **★ 新增（2026-10-16）与 04d 的交叉核对**：04d 的 §2b「量化许可」用同一估计量算了
#     LPA 与 total_PA 两套数 → 本步对同一批数**逐值复核**（两脚本互证，非各算各的）。
#
# 输入：data/bop/rr_table.csv、data/bop/rr_table_site_anchor.csv、
#       output/Table8_site_ratio_matrix.csv（04c，§6 用）、
#       output/Table5_bop_wear_site.csv（05a 的既有部位效应，作交叉核对）、
#       output/Table8_lit_site_metric_license.csv（04d，§7 交叉核对用，缺则跳过）
# 输出：output/Table8b_site_anchor_totalPA.csv          逐 offset 直接对照（total_PA）
#       output/Table8b_site_anchor_slopes.csv          过原点斜率与髋/腕比
#       output/Table8b_site_metric_compare.csv         两指标同估计量并列
#       output/Table8b_site_anchor_vs_nhanes.csv       ★ 指标对齐对照（total_PA vs NHANES total）
#       output/QC_site_anchor_license_xcheck.csv       ★ 与 04d §2b 的逐值交叉核对
#       output/QC_site_anchor_totalPA.txt              结论摘要
# ⚠️ 本步**只读**主池：不写任何主池文件、不覆盖 05a/04c/04d 的任何产物（只新增 Table8b_*）。
# =============================================================================

# ---- 统一引导（勿改）：locale 修复 + 加载 00_setup.R（提供 ROOT/DIR_*/PA_SEED）----
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
suppressPackageStartupMessages({ library(data.table) })
pa_log("===== 04f 文献侧部位效应：指标稳健性（total_PA 外部锚定）+ NHANES 同指标对照 =====")

Z975 <- qnorm(0.975)
OFFS <- c(25, 50, 60, 75)   # 与 05a Table5_bop_wear_site 的汇报点一致

# =============================================================================
# 1. 读入两侧 + 独立性守卫
# =============================================================================
hip  <- fread(file.path(DIR_BOP, "rr_table.csv"), encoding = "UTF-8")
anch <- fread(file.path(DIR_BOP, "rr_table_site_anchor.csv"), encoding = "UTF-8")

# ---- 守卫（任何一条失败都必须中止，不得静默出数）------------------------------
# ① 锚点行必须全部标记为「非池化」——否则本步就是把 UKB 重复当成新证据；
# ② 锚点行不得与主池 row_id 重叠；
# ③ 锚点 study 不得与主池 study 重叠 —— 「两来源相减」的前提是两侧互为**独立队列**。
#    主池无 cohort_cluster 列，故用 study 名做等价判据（锚点 = Ko2025_UKB_wrist /
#    InanEroglu2024_UKB_wrist；池内 UKB 行 = UKB_wrist_general / UKB_wrist_CVD）。
# ④ 锚点只允许一般人群、只允许腕式（否则「部位」对照失去意义）。
stopifnot(all(anch$pool_role == "site_anchor_NONPOOLED"))
stopifnot(!any(anch$row_id %in% hip$row_id))
if (any(anch$study %in% hip$study))
  stop("锚点 study 与主池 study 撞车 → 「两来源相减」前提被破坏：",
       paste(intersect(anch$study, hip$study), collapse = ", "))
if (any(anch$population != "general"))
  stop("锚点表存在 population != general 的行：", paste(anch[population != "general", row_id], collapse = ", "))
if (any(anch$wear_site != "wrist"))
  stop("锚点表存在非腕式行：", paste(anch[wear_site != "wrist", row_id], collapse = ", "))

prep <- function(d) {
  d <- d[method == "device" & population == "general" & !is.na(hr) & !is.na(exposure_center)]
  d[, offset := as.numeric(exposure_center) - as.numeric(exposure_ref_center)]
  d[, `:=`(loghr = log(as.numeric(hr)),
           se = (log(as.numeric(hr_hi)) - log(as.numeric(hr_lo))) / (2 * Z975))]
  d[]
}
hip  <- prep(hip)
anch <- prep(anch)

slope_of <- function(d) {
  w  <- 1 / d$se^2
  b  <- sum(w * d$offset * d$loghr) / sum(w * d$offset^2)
  se <- 1 / sqrt(sum(w * d$offset^2))
  list(b = unname(b), se = unname(se), k = nrow(d))
}

# =============================================================================
# 2. 逐 offset 直接对照（同 04d 口径）
# =============================================================================
direct <- list()
for (md in "total_PA") {
  h <- hip[metric_definition == md & wear_site == "hip"]
  w <- anch[metric_definition == md]
  for (of in sort(unique(h$offset))) {
    hh <- h[offset == of]; ww <- w[offset == of]
    if (!nrow(hh) || !nrow(ww)) next
    wm   <- function(x) { iv <- 1 / x$se^2; sum(iv * x$loghr) / sum(iv) }
    se_w <- function(x) 1 / sqrt(sum(1 / x$se^2))
    lh <- wm(hh); lw <- wm(ww)
    se <- sqrt(se_w(hh)^2 + se_w(ww)^2)
    direct[[length(direct) + 1L]] <- data.table(
      metric_definition = md, offset = of,
      hip_studies = paste(sort(unique(hh$study)), collapse = " | "),
      wrist_studies = paste(sort(unique(ww$study)), collapse = " | "),
      rr_hip = exp(lh), rr_wrist = exp(lw),
      ratio_wrist_over_hip = exp(lw - lh),
      ratio_lo = exp(lw - lh - Z975 * se),
      ratio_hi = exp(lw - lh + Z975 * se),
      hip_over_wrist    = exp(lh - lw),
      hip_over_wrist_lo = exp(lh - lw - Z975 * se),
      hip_over_wrist_hi = exp(lh - lw + Z975 * se),
      p_value = 2 * pnorm(-abs((lw - lh) / se)))
  }
}
D <- rbindlist(direct)

# =============================================================================
# 3. 过原点斜率（每来源），以及髋/腕斜率比
# =============================================================================
srcs <- rbindlist(lapply(split(anch[metric_definition == "total_PA"],
                               anch[metric_definition == "total_PA"]$study), function(d) {
  s <- slope_of(d)
  data.table(study = d$study[1], k_rows = s$k, slope_logrr_per_pct = s$b, se = s$se)
}))
hs <- slope_of(hip[metric_definition == "total_PA" & wear_site == "hip"])
SRC <- rbind(data.table(study = "Ekelund2019_harmonised(hip)", k_rows = hs$k,
                        slope_logrr_per_pct = hs$b, se = hs$se), srcs)
SRC[, rr_at_off60 := exp(slope_logrr_per_pct * 60)]
# ⚠️ 部位效应 = **斜率绝对值之比**（不是斜率差、也不是「偏移 1 处的 RR 比」）。
#    两侧斜率均为负；比值 CI 用对数尺度 delta：SE[log(|b_h|/|b_w|)]
#    = sqrt((se_h/b_h)^2 + (se_w/b_w)^2)（取绝对值后符号被消掉，可直接用带符号斜率）。
# ⚠️ 但**斜率比不可跨指标外推**：腕侧斜率在分母上，腕侧越平该比值越被放大。
#    跨指标比较的正确判据是「共同 offset 处的腕/髋比值」（见 §5 与 04d §2b）。
SRC[, abs_slope := abs(slope_logrr_per_pct)]
SRC[, hip_over_wrist := abs(hs$b) / abs_slope]
SRC[, se_logratio := sqrt((hs$se / hs$b)^2 + (se / slope_logrr_per_pct)^2)]
SRC[, hip_over_wrist_lo := hip_over_wrist * exp(-Z975 * se_logratio)]
SRC[, hip_over_wrist_hi := hip_over_wrist * exp(Z975 * se_logratio)]
SRC[, p_slope_ratio := 2 * pnorm(-abs(log(hip_over_wrist) / se_logratio))]
SRC[1, `:=`(hip_over_wrist = 1, hip_over_wrist_lo = NA_real_, hip_over_wrist_hi = NA_real_,
            se_logratio = NA_real_, p_slope_ratio = NA_real_)]

# =============================================================================
# 4. 两指标**同估计量**并列（本步的核心产出之一）
# =============================================================================
#   ⚠️ 腕侧来源必须分档报：Ko2025 与 EK19 的 offset 网格完全重合（参照同为 12.5 →
#      25/50/75），是最干净的对齐；IE24 的 offset 是 33.33/66.67（参照 16.67），
#      杠杆不同 → 只作旁证，另出一行，不与 Ko 混成一个数。
cmp_one <- function(md, wsrc, label) {
  hh <- hip[metric_definition == md & wear_site == "hip"]
  # ⚠️ 分派必须用 as.character() 去掉属性：wsrc 可能是 structure("anchor", studies = ...)，
  #    此时 identical(wsrc, "anchor") 为 FALSE（属性不同），会静默走错分支。
  wlab <- as.character(wsrc)[1]
  ww <- if (wlab == "anchor") anch[metric_definition == md] else
        hip[metric_definition == md & wear_site == "wrist"]
  if (!is.null(attr(wsrc, "studies"))) ww <- ww[study %in% attr(wsrc, "studies")]
  if (!nrow(hh) || !nrow(ww)) return(NULL)
  sh <- slope_of(hh); sw <- slope_of(ww)
  lr <- log(abs(sh$b) / abs(sw$b))
  sl <- sqrt((sh$se / sh$b)^2 + (sw$se / sw$b)^2)
  # 共同 offset 处腕/髋比值的**直接估计**（对数尺度 SE = 两侧 log-SE 平方和开方）
  base <- data.table(
    metric_definition = md, wrist_source = label,
    hip_studies = paste(sort(unique(hh$study)), collapse = " | "),
    wrist_studies = paste(sort(unique(ww$study)), collapse = " | "),
    offset_grid_wrist = paste(sort(unique(round(ww$offset, 2))), collapse = "/"),
    offset_grid_matched = identical(sort(unique(round(hh$offset, 2))), sort(unique(round(ww$offset, 2)))),
    k_rows_hip = sh$k, k_rows_wrist = sw$k,
    slope_hip = sh$b, slope_wrist = sw$b,
    se_slope_hip = sh$se, se_slope_wrist = sw$se,
    slope_ratio_hip_over_wrist = exp(lr),
    slope_ratio_lo = exp(lr - Z975 * sl),
    slope_ratio_hi = exp(lr + Z975 * sl),
    p_slope_ratio = 2 * pnorm(-abs(lr / sl)))
  for (of in OFFS) {
    base[, (sprintf("hip_over_wrist_at_off%d", of)) := exp((sh$b - sw$b) * of)]
    base[, (sprintf("wrist_over_hip_at_off%d", of)) := exp((sw$b - sh$b) * of)]
  }
  for (of in OFFS) {
    h1 <- hh[offset == of]; w1 <- ww[offset == of]
    if (nrow(h1) && nrow(w1)) {
      se <- sqrt(mean(h1$se)^2 + mean(w1$se)^2)
      base[, (sprintf("direct_wrist_over_hip_at_off%d", of)) := exp(mean(w1$loghr) - mean(h1$loghr))]
      base[, (sprintf("direct_lo_at_off%d", of)) := exp(mean(w1$loghr) - mean(h1$loghr) - Z975 * se)]
      base[, (sprintf("direct_hi_at_off%d", of)) := exp(mean(w1$loghr) - mean(h1$loghr) + Z975 * se)]
    } else {
      base[, (sprintf("direct_wrist_over_hip_at_off%d", of)) := NA_real_]
      base[, (sprintf("direct_lo_at_off%d", of)) := NA_real_]
      base[, (sprintf("direct_hi_at_off%d", of)) := NA_real_]
    }
  }
  base
}
CMP <- rbindlist(list(
  cmp_one("total_PA", structure("anchor", studies = "Ko2025_UKB_wrist"),
          "Ko2025 锚点（UKB；offset 与 EK19 完全对齐）"),
  cmp_one("total_PA", "anchor",
          "Ko2025 + Inan-Eroglu2024 合并（旁证；offset 网格不同）"),
  cmp_one("LPA", "pool", "Sun2025 池内（UKB）")), fill = TRUE)

# 两指标（对齐档）在共同 offset 处的比值差异 —— **跨指标许可的判据**
OFS_COM <- c(25, 50, 75)
GAP <- NULL
if (nrow(CMP)) {
  rL <- CMP[metric_definition == "LPA"]
  rT <- CMP[metric_definition == "total_PA" & grepl("Ko2025 锚点", wrist_source)]
  if (nrow(rL) == 1L && nrow(rT) == 1L) {
    GAP <- vapply(OFS_COM, function(of)
      rT[[sprintf("direct_wrist_over_hip_at_off%d", of)]] /
      rL[[sprintf("direct_wrist_over_hip_at_off%d", of)]], numeric(1))
    CMP[, ratio_gap_vs_LPA_at_off25 := direct_wrist_over_hip_at_off25 /
          rL$direct_wrist_over_hip_at_off25]
    CMP[, ratio_gap_vs_LPA_at_off50 := direct_wrist_over_hip_at_off50 /
          rL$direct_wrist_over_hip_at_off50]
    CMP[, ratio_gap_vs_LPA_at_off75 := direct_wrist_over_hip_at_off75 /
          rL$direct_wrist_over_hip_at_off75]
    CMP[, slope_ratio_gap_vs_LPA := slope_ratio_hip_over_wrist / rL$slope_ratio_hip_over_wrist]
    pa_log(sprintf(paste0("§4 两指标并列：共同 offset（25/50/75）处腕/髋比值 LPA %s vs total_PA(Ko) %s ",
                          "→ 最大相差 %.1f%%；斜率之比 %.2f vs %.2f（%+.1f%%）"),
                   paste(sprintf("%.3f", c(rL$direct_wrist_over_hip_at_off25,
                                           rL$direct_wrist_over_hip_at_off50,
                                           rL$direct_wrist_over_hip_at_off75)), collapse = "/"),
                   paste(sprintf("%.3f", c(rT$direct_wrist_over_hip_at_off25,
                                           rT$direct_wrist_over_hip_at_off50,
                                           rT$direct_wrist_over_hip_at_off75)), collapse = "/"),
                   100 * max(abs(GAP - 1)),
                   rL$slope_ratio_hip_over_wrist, rT$slope_ratio_hip_over_wrist,
                   100 * (rT$slope_ratio_hip_over_wrist / rL$slope_ratio_hip_over_wrist - 1)))
  }
}

# =============================================================================
# 5. ★ 指标对齐对照：文献侧 total_PA vs NHANES 同调查内 total_PA
# =============================================================================
# 为什么这一步最关键：04d 的「文献 vs NHANES」只能是**跨指标**（池内文献侧只有 LPA），
#   而 NHANES 参照的轴是 total_PA。**只有把锚点（total_PA）接进来，才能做同指标对照** ——
#   这也是判断「髋式曲线能否用于腕式暴露侧」的唯一干净证据。
# ⚠️ 归属为 total_PA 由 04d §0 机器校验（Table8_metric_axis_check 的 R0 行 ≡ Table6 的
#    rr_hip）；04f 运行时 04d 已在链上先跑，故此处直接复用其结论并在 QC 中复述。
NHANES_METRIC <- "total_PA"
interp_ratio <- function(tab, of) {
  o <- tab$offset
  f <- function(v) exp(approx(o, log(v), xout = of, rule = 2)$y)
  list(est = f(tab$ratio_mean), lo = f(tab$ratio_lo), hi = f(tab$ratio_hi),
       on_grid = of %in% o)
}
NH <- data.table()
t8p <- file.path(DIR_OUT, "Table8_site_ratio_matrix.csv")
if (file.exists(t8p)) {
  m8 <- fread(t8p)[hip_rule == "R0_choi2011" & wrist_criterion == "C0_wake600"]
  for (i in seq_len(nrow(D))) {
    of <- D$offset[i]
    iv <- interp_ratio(m8, of)         # 与 04d §3 同一口径（对数尺度插值）
    NH <- rbind(NH, data.table(
      metric_definition = "total_PA",
      lit_metric = "total_PA", nhanes_metric = NHANES_METRIC,
      metric_aligned = identical("total_PA", NHANES_METRIC),
      offset = of,
      lit_ratio = D$ratio_wrist_over_hip[i], lit_lo = D$ratio_lo[i], lit_hi = D$ratio_hi[i],
      nhanes_ratio = iv$est, nhanes_lo = iv$lo, nhanes_hi = iv$hi,
      nhanes_value_on_grid = iv$on_grid,
      nhanes_ci_contains_lit_point = (D$ratio_wrist_over_hip[i] >= iv$lo &
                                      D$ratio_wrist_over_hip[i] <= iv$hi),
      ci_overlap = !(D$ratio_hi[i] < iv$lo | D$ratio_lo[i] > iv$hi)))
  }
}
if (nrow(NH)) {
  pa_log(sprintf("§5 指标对齐对照（total_PA vs NHANES total）：%s",
                 paste(sprintf("off%d 文献 %.2f [%.2f, %.2f] vs NHANES %.2f [%.2f, %.2f] → %s",
                               NH$offset, NH$lit_ratio, NH$lit_lo, NH$lit_hi,
                               NH$nhanes_ratio, NH$nhanes_lo, NH$nhanes_hi,
                               ifelse(NH$nhanes_ci_contains_lit_point, "相容", "**不相容**")),
                       collapse = "；")))
} else {
  pa_log("⚠️ 缺 Table8_site_ratio_matrix.csv → 指标对齐对照未计算。")
}

# =============================================================================
# 6. ★ 与 04d §2b 的交叉核对（两脚本用同一估计量算同一批数，应逐值一致）
# =============================================================================
# 设计意图：04d 的「量化许可」与 04f 的「两指标并列」在数学上是同一件事，只是落点不同。
#   若两脚本给出的数不一致 → 必有一侧的读入/筛选/口径分叉。这里逐值比对并落盘证据。
xc <- list()
add_xc <- function(item, v4d, v4f, tol = 1e-8) {
  d <- if (is.numeric(v4d) && is.numeric(v4f) && length(v4d) == 1L && length(v4f) == 1L)
    abs(v4d - v4f) else NA_real_
  xc[[length(xc) + 1L]] <<- data.table(
    item = item, value_04d = v4d, value_04f = v4f, abs_dev = d,
    status = if (is.na(d)) "SKIP（缺一侧）" else if (d < tol) "PASS" else "FAIL")
}
lic_p <- file.path(DIR_OUT, "Table8_lit_site_metric_license.csv")
if (file.exists(lic_p) && nrow(CMP)) {
  lic <- fread(lic_p, encoding = "UTF-8")
  .lL <- lic[metric_definition == "LPA"]
  .lT <- lic[metric_definition == "total_PA"]
  .cL <- CMP[metric_definition == "LPA"]
  .cT <- CMP[metric_definition == "total_PA" & grepl("Ko2025 锚点", wrist_source)]
  add_xc("LPA 髋侧斜率（池内 EK19）",
         if (nrow(.lL)) .lL$slope_hip else NA_real_, if (nrow(.cL)) .cL$slope_hip else NA_real_)
  add_xc("LPA 腕侧斜率（池内 SV25）",
         if (nrow(.lL)) .lL$slope_wrist else NA_real_, if (nrow(.cL)) .cL$slope_wrist else NA_real_)
  add_xc("LPA 斜率比（髋/腕）",
         if (nrow(.lL)) .lL$slope_ratio_hip_over_wrist else NA_real_,
         if (nrow(.cL)) .cL$slope_ratio_hip_over_wrist else NA_real_)
  add_xc("total_PA 髋侧斜率（池内 EK19）",
         if (nrow(.lT)) .lT$slope_hip else NA_real_, if (nrow(.cT)) .cT$slope_hip else NA_real_)
  add_xc("total_PA 腕侧斜率（锚点 Ko2025）",
         if (nrow(.lT)) .lT$slope_wrist else NA_real_, if (nrow(.cT)) .cT$slope_wrist else NA_real_)
  add_xc("total_PA 斜率比（髋/腕）",
         if (nrow(.lT)) .lT$slope_ratio_hip_over_wrist else NA_real_,
         if (nrow(.cT)) .cT$slope_ratio_hip_over_wrist else NA_real_)
  for (of in OFS_COM) {
    add_xc(sprintf("total_PA 直接比值 @off%d", of),
           if (nrow(.lT)) .lT[[sprintf("direct_wrist_over_hip_off%d", of)]] else NA_real_,
           if (nrow(.cT)) .cT[[sprintf("direct_wrist_over_hip_at_off%d", of)]] else NA_real_)
  }
} else {
  xc[[1L]] <- data.table(item = "与 04d 的交叉核对", value_04d = NA_real_, value_04f = NA_real_,
                         abs_dev = NA_real_,
                         status = if (!file.exists(lic_p)) "SKIP（04d 产物缺失，请先跑 04d）"
                                  else "SKIP（本步 CMP 为空）")
}
XC <- rbindlist(xc, fill = TRUE)
n_xc_fail <- sum(XC$status == "FAIL")
if (n_xc_fail > 0L) {
  cat("\n===== 与 04d §2b 的交叉核对 =====\n"); print(XC)
  stop("与 04d 的交叉核对有 ", n_xc_fail, " 项 FAIL —— 两脚本口径已分叉，修好再入链。")
}

# =============================================================================
# 7. 落盘
# =============================================================================
fwrite(D,   file.path(DIR_OUT, "Table8b_site_anchor_totalPA.csv"))
fwrite(SRC, file.path(DIR_OUT, "Table8b_site_anchor_slopes.csv"))
fwrite(CMP, file.path(DIR_OUT, "Table8b_site_metric_compare.csv"))
fwrite(NH,  file.path(DIR_OUT, "Table8b_site_anchor_vs_nhanes.csv"))
fwrite(XC,  file.path(DIR_OUT, "QC_site_anchor_license_xcheck.csv"))

# =============================================================================
# 8. 与 05a 的既有部位效应交叉核对
# =============================================================================
lpa_txt <- "(未找到 Table5_bop_wear_site.csv)"
lpa_p <- file.path(DIR_OUT, "Table5_bop_wear_site.csv")
if (file.exists(lpa_p)) {
  L <- fread(lpa_p, encoding = "UTF-8")
  # 列名（勿凭印象写）：spec / metric_definition / slope_hip / slope_wrist /
  #   slope_diff_hip_minus_wrist / n_rows_hip / n_rows_wrist / offset_pts /
  #   rr_ratio_hip_over_wrist / rr_ratio_lo / rr_ratio_hi / p_diff / note
  sel <- L[spec == "main_general_population" & metric_definition == "LPA"][order(offset_pts)]
  if (nrow(sel)) lpa_txt <- paste0(
    "LPA（主池模型，05a Table5_bop_wear_site，spec=main_general_population）：",
    paste(sprintf("髋/腕 @off%g = %.3f [%.3f, %.3f]", sel$offset_pts,
                  sel$rr_ratio_hip_over_wrist, sel$rr_ratio_lo, sel$rr_ratio_hi), collapse = "；"),
    sprintf("（p = %.4f）", sel$p_diff[1]))
}

# =============================================================================
# 9. 结论摘要落盘（★ 无时间戳：本文件参与 06/98 的跨运行指纹比对，
#    写入 Sys.time() 会让 E 层每次都报一条"数据漂移"的假差异）
# =============================================================================
out <- file.path(DIR_OUT, "QC_site_anchor_totalPA.txt")
con <- file(out, "w", encoding = "UTF-8")
wl <- function(...) cat(..., "\n", file = con, sep = "")
wl("===== 文献侧部位效应：指标稳健性（total_PA 外部锚定）=====")
wl("（本文件为流水线产物，无时间戳，以保证逐字节可复现）")
wl("")
wl("【设计定位】")
wl("  髋侧来源：Ekelund2019（8 队列协调化，髋式 ActiGraph；与已冻结主池同一行）")
wl("  腕侧来源：Ko2025（UKB，n=65088，完全校正 Model 3）")
wl("            Inan-Eroglu2024（UKB，n=79988）—— 与 EK19 互为独立队列")
wl("  ⚠️ 腕侧两来源均与池内 Sun2025 同属 UKB 加速度计子队列 → 仅作外部锚定，不并入主池")
wl("     （裁定依据：data/bop/20261016_入池裁定_UKB腕式总PA双源.md）")
wl("")
wl("【逐 offset 直接对照（腕/髋；>1 = 腕式 RR 更高、髋式更陡）】")
for (i in seq_len(nrow(D)))
  wl(sprintf("  offset %5.2f : 髋 %.3f vs 腕 %.3f -> 腕/髋 %.3f [%.3f, %.3f]  髋/腕 %.3f [%.3f, %.3f]  p = %.3g",
             D$offset[i], D$rr_hip[i], D$rr_wrist[i], D$ratio_wrist_over_hip[i],
             D$ratio_lo[i], D$ratio_hi[i], D$hip_over_wrist[i],
             D$hip_over_wrist_lo[i], D$hip_over_wrist_hi[i], D$p_value[i]))
wl("")
wl("【过原点斜率（每百分位点的 log-RR）与「髋式陡 / 腕式陡」倍数】")
for (i in seq_len(nrow(SRC)))
  wl(sprintf("  %-28s 行数 %2d  斜率 %+.5f (SE %.5f)  RR@off60 %.3f  髋/腕斜率比 %s",
             SRC$study[i], SRC$k_rows[i], SRC$slope_logrr_per_pct[i], SRC$se[i], SRC$rr_at_off60[i],
             if (i == 1L) "（参照侧 = 1）" else sprintf("%.3f [%.3f, %.3f], p = %.3g",
                                                       SRC$hip_over_wrist[i], SRC$hip_over_wrist_lo[i],
                                                       SRC$hip_over_wrist_hi[i], SRC$p_slope_ratio[i])))
wl("  （髋/腕斜率比 = 2 表示同百分位下髋式曲线的 log-RR 陡 2 倍，即髋式 RR 更低）")
wl("  ⚠️ 该比值**不可跨指标外推**：腕侧斜率在分母上，腕侧越平比值越被放大。")
wl("     跨指标的正确判据是「共同 offset 处的腕/髋比值」，见下条与 04d §2b。")
wl("")
wl("【★ 两指标同估计量并列（回答「部位效应是否指标依赖」）】")
for (i in seq_len(nrow(CMP))) {
  wl(sprintf("  %-9s 腕侧来源=%s（offset %s%s）", CMP$metric_definition[i], CMP$wrist_source[i],
             CMP$offset_grid_wrist[i], ifelse(CMP$offset_grid_matched[i], "，与髋侧对齐", "，网格不同")))
  wl(sprintf("            斜率 髋 %+.5f vs 腕 %+.5f -> 髋/腕斜率比 %.3f [%.3f, %.3f], p = %.3g",
             CMP$slope_hip[i], CMP$slope_wrist[i], CMP$slope_ratio_hip_over_wrist[i],
             CMP$slope_ratio_lo[i], CMP$slope_ratio_hi[i], CMP$p_slope_ratio[i]))
  wl(sprintf("            直接比值（腕/髋）：@25 %.3f [%.3f, %.3f]  @50 %.3f [%.3f, %.3f]  @75 %.3f [%.3f, %.3f]",
             CMP$direct_wrist_over_hip_at_off25[i], CMP$direct_lo_at_off25[i], CMP$direct_hi_at_off25[i],
             CMP$direct_wrist_over_hip_at_off50[i], CMP$direct_lo_at_off50[i], CMP$direct_hi_at_off50[i],
             CMP$direct_wrist_over_hip_at_off75[i], CMP$direct_lo_at_off75[i], CMP$direct_hi_at_off75[i]))
}
if (!is.null(GAP)) {
  wl(sprintf("  → 两指标（对齐档）在共同 offset 处的比值最大相差 %.1f%%；斜率之比相差 %+.1f%%。",
             100 * max(abs(GAP - 1)),
             100 * (CMP[metric_definition == "total_PA" & grepl("Ko2025 锚点", wrist_source)]$slope_ratio_gap_vs_LPA - 1)))
  wl("     读法：比值差异小 -> 以 LPA 的**比值**外推 total_PA 的部位校正因子可辩护；")
  wl("            斜率比差异大 -> 以 LPA 的**斜率比**外推不可辩护，须在 Limitations 写明。")
}
wl("")
wl("【★ 指标对齐对照：文献侧 total_PA vs NHANES 同调查内 total_PA（本项目唯一同指标部位对照）】")
if (nrow(NH)) {
  for (i in seq_len(nrow(NH)))
    wl(sprintf("  offset %5.2f（NHANES %s）：文献 %.3f [%.3f, %.3f] vs NHANES %.3f [%.3f, %.3f] -> %s（区间重叠 %s）",
               NH$offset[i], ifelse(NH$nhanes_value_on_grid[i], "网格点", "插值"),
               NH$lit_ratio[i], NH$lit_lo[i], NH$lit_hi[i],
               NH$nhanes_ratio[i], NH$nhanes_lo[i], NH$nhanes_hi[i],
               ifelse(NH$nhanes_ci_contains_lit_point[i], "文献点估计落在 NHANES 区间内", "**不相容**"),
               ifelse(NH$ci_overlap[i], "是", "否")))
  wl("  读法：本对照**指标完全对齐**，故其结论可直接支撑「髋式曲线能否用于腕式暴露侧」。")
  wl("        与 04d 的跨指标比较结论一致/不一致都要在正文如实报告（两处口径不同，不可互替）。")
} else wl("  （缺 04c 的 Table8_site_ratio_matrix.csv → 未计算）")
wl("")
wl("【与 04d §2b 的交叉核对（两脚本互证）】")
for (i in seq_len(nrow(XC)))
  wl(sprintf("  %-40s 04d = %s  04f = %s  偏差 %s  %s",
             XC$item[i], format(XC$value_04d[i], digits = 8), format(XC$value_04f[i], digits = 8),
             ifelse(is.na(XC$abs_dev[i]), "-", format(XC$abs_dev[i], digits = 3)), XC$status[i]))
wl("")
wl("【交叉核对：05a 主池模型给出的 LPA 部位效应（独立估计路径）】")
wl("  ", lpa_txt)
wl("")
wl("【读法】")
wl("  · 两指标若给出**同向且量级接近**的髋/腕比 -> 部位效应不是某个指标的偶然产物，")
wl("    用 LPA 比值去讨论 total_PA 的部位偏倚方向即可被支持；")
wl("  · 若差异很大 -> 必须在 Limitations 写明「部位校正因子具有指标依赖性」。")
wl("")
wl("【与 04d 的分工（勿混用）】")
wl("  04d：池内文献侧（**LPA**）× NHANES 同调查内 → **跨指标**比较，合法性由 04d §2b 量化许可支撑。")
wl("  04f：锚点文献侧（**total_PA**）× NHANES 同调查内 → **同指标**比较（本文件 §5）。")
close(con)

D[, ratio := sprintf("%.3f (%.3f-%.3f)", ratio_wrist_over_hip, ratio_lo, ratio_hi)]
cat("\n===== 逐 offset 直接对照（腕/髋）=====\n")
print(D[, .(metric_definition, offset, hip_studies, wrist_studies, rr_hip, rr_wrist, ratio, p_value)])
cat("\n===== 过原点斜率 =====\n")
print(SRC[, .(study, k_rows, slope_logrr_per_pct, se, rr_at_off60,
              ratio_hw = sprintf("%.3f [%.3f, %.3f]", hip_over_wrist, hip_over_wrist_lo, hip_over_wrist_hi))])
cat("\n===== 两指标同估计量并列 =====\n")
print(CMP[, .(metric_definition, wrist_studies, slope_hip, slope_wrist,
              ratio = sprintf("%.3f [%.3f, %.3f]", slope_ratio_hip_over_wrist, slope_ratio_lo, slope_ratio_hi),
              d25 = round(direct_wrist_over_hip_at_off25, 3), d50 = round(direct_wrist_over_hip_at_off50, 3),
              d75 = round(direct_wrist_over_hip_at_off75, 3))])
cat("\n===== 指标对齐对照（total_PA vs NHANES total）=====\n")
if (nrow(NH)) print(NH[, .(offset, lit = sprintf("%.3f [%.3f, %.3f]", lit_ratio, lit_lo, lit_hi),
                           nhanes = sprintf("%.3f [%.3f, %.3f]", nhanes_ratio, nhanes_lo, nhanes_hi),
                           nhanes_ci_contains_lit_point, ci_overlap)]) else cat("（未计算）\n")
cat("\n===== 与 04d 的交叉核对 =====\n"); print(XC)
cat("\n===== 05a 既有 LPA 部位效应（交叉核对）=====\n", lpa_txt, "\n")
pa_log("04f 完成。输出：Table8b_site_anchor_totalPA.csv / _slopes.csv / _metric_compare.csv / _vs_nhanes.csv + QC_site_anchor_totalPA.txt + QC_site_anchor_license_xcheck.csv")
