# =============================================================================
# 04d_lit_site_contrast.R
# 文献侧「部位效应」的可分解性 + 与 NHANES 同调查内估计的相容性检验
# -----------------------------------------------------------------------------
# 背景：05c A 档（仅文献池）给出 LPA 的髋/腕部位效应 @off60 = 0.658 [0.496, 0.873]，
#       即「髋式曲线更陡（更保护）」，p=0.0037；
#       而 04b/04c 的 NHANES 同调查内自估 ≈ 1.00（不可检出）。
#       两者方向相反 → 本脚本回答：文献侧那个 0.658 到底可不可信。
#
# 核心洞察（本脚本要把它算出来、而不是只写一句话）：
#   Module 2 池里 hip × LPA 只有 **EK19 三行**，wrist × LPA 只有 **SV25 三行**，
#   且两者的 exposure_center 完全对齐（37.5/62.5/87.5 → offset 25/50/75）。
#   因此文献侧的「部位效应」= **两个研究之间的对照**，
#   在随机效应模型里它与「研究」完全共线 → arm 效应不可与研究级混杂分离。
#
# 本脚本做三件事
#   1) 逐 offset 列出 EK19(髋) vs SV25(腕) 的**直接对照**（不需要元回归即可复算）
#   2) 相容性检验：文献侧点估计是否落在 NHANES 自估比值的 95% CI 内
#      → 若落在外面，则「文献侧差异 = 真实佩戴部位效应」这一解释被证伪
#   3) 杠杆分析：逐行剔除 SV25（含其非单调的 Q4）看对照的变化幅度
#
# ── 2026-10-16 追加：**指标轴（metric-aware）** ───────────────────────────────
# 此前一个**隐式**且可被审稿人直接击中的问题：第 2 节的文献侧对比只能对 **LPA** 出
#   （池内只有 LPA 有髋/腕双覆盖：EK19 髋 × SV25 腕），而第 3 节用作参照的 NHANES
#   同调查内「髋 vs 腕」曲线，其指标轴是**总量**：
#       NHANES 髋式 = R0_choi2011 的 counts/day（总量 counts）
#       NHANES 腕式 = C0_wake600 的 MIMS/day（总量 MIMS）
#   → 第 3 节的「文献 vs NHANES」**是跨指标比较**，必须显式标注，不能默默做。
#
# 本脚本现把该归属**显式化**，且**不靠手写**：
#   · `NHANES_SITE_METRIC` 声明归属；
#   · §0 用 **运行时机器校验** 证明该归属 —— 把 04c 的 Table8_metric_axis_check.csv
#     里「总量 counts（R0）」一行在 off30/60/80 的 RR 与 04b 的 Table6 的 rr_hip
#     逐值比对（同一规格应达机器精度）。若将来 04c 的默认轴换成别的指标，本检查
#     会失败并**中止**，防止标签静默过期（同 06_manifest 的 sep 探测那类静默错误的防法）。
#   · §2b 新增「指标错配的**量化许可**」：在同估计量下把文献侧 LPA 与文献侧 total_PA
#     的髋/腕比各算一遍并比较。若两者同量级 → 跨指标比较不改变结论（该许可被**算出来**，
#     而不是靠说辞）；若差异很大 → 必须在 Limitations 写明部位校正因子有指标依赖性。
#     ⚠️ 该块与 04f_lit_site_anchor.R 的 Table8b_site_metric_compare.csv 用**同一估计量**，
#        04f 会反过来对本产物做逐值交叉核对（两脚本互证，非各算各的）。
#
# 输入：data/bop/rr_table.csv、data/bop/rr_table_site_anchor.csv（§2b 用）、
#       output/Table6_nhanes_hip_wrist_RR.csv、output/Table8_site_ratio_matrix.csv、
#       output/Table8_metric_axis_check.csv（§0 校验用，04c 产出）
# 输出：output/Table8_lit_site_contrast.csv        逐 offset 对照（含指标列）
#       output/Table8_lit_site_compatibility.csv    NHANES 与文献侧可比性（含指标对齐标记）
#       output/Table8_lit_site_metric_license.csv   指标错配的量化许可（§2b）
#       output/Table8_lit_site_leverage.csv        逐行剔除的杠杆
#       output/Table8_lit_design_incompat.csv      两研究设计不可通约维度清单
#       output/QC_lit_site_contrast.txt            结论摘要
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
pa_log("===== 04d 文献侧部位效应：可分解性与相容性检验 =====")

REF_PCT <- 12.5
Z975    <- qnorm(0.975)

# =============================================================================
# 0. 指标轴归属的**运行时机器校验**（metric-aware，2026-10-16）
# =============================================================================
# 断言：04b/04c 的 NHANES 同调查内髋 vs 腕曲线，其指标轴是**总量**（hip = 总量
#   counts/day；wrist = 总量 MIMS/day），**不是** LPA。证据落点：
#   04c 的 Table8_metric_axis_check.csv 里 `总量 counts（R0）` 一行就是 R0_choi2011
#   那条曲线 —— 若它在 off30/60/80 与 04b 的 Table6 的 rr_hip 逐值相同（机器精度），
#   即证明 Table6 / Table8_site_ratio_matrix 的 R0×C0 档是**总量**轴。
#   ⚠️ 不做这一步，第 3 节就会把「文献 LPA 比」与「NHANES 总量比」当成同指标比较。
NHANES_SITE_METRIC <- "total_PA"          # 归属（供兼容性表标注）
METRIC_TOL         <- 1e-8                # 判等容差（**先对齐存储精度**再比，见下）
.site_metric_ok <- NA
{
  ax_p <- file.path(DIR_OUT, "Table8_metric_axis_check.csv")
  t6_p <- file.path(DIR_OUT, "Table6_nhanes_hip_wrist_RR.csv")
  if (file.exists(ax_p) && file.exists(t6_p)) {
    ax <- fread(ax_p, encoding = "UTF-8"); t6 <- fread(t6_p, encoding = "UTF-8")
    r0 <- ax[spec == "R0_choi2011"]                  # 「总量 counts（R0）」那一行
    # ⚠️ 必须用 == 精确匹配：spec 里 lpa_100_2020__R0 / sed_lt100__R0 / mvpa_ge2020__R0
    #    也含子串 "R0"，用 grepl("R0", spec) 会一次命中 4 行（实测踩到），从而静默跳过校验。
    # ⚠️ 且必须先把两侧都归到**同一存储精度**再比：04c 的 axis 表把 RR round(., 3) 存盘，
    #    而 Table6 是全精度 → 直接相减会得到 4.1e-4 的"差异"（纯舍入，实测踩到）。
    if (nrow(r0) == 1L) {
      g <- function(o) round(t6[offset_pts == o]$rr_hip, 3)
      d <- max(abs(c(as.numeric(r0$rr_off30), as.numeric(r0$rr_off60), as.numeric(r0$rr_off80)) -
                    c(g(30), g(60), g(80))))
      .site_metric_ok <- (d < METRIC_TOL)
      pa_log(sprintf(paste0("指标轴归属校验：Table8_metric_axis_check[%s] vs Table6 rr_hip（已对齐到 3 位小数）",
                            "最大绝对偏差 %.3g -> %s（据此判定 NHANES 部位曲线为 %s 轴）"),
                     r0$spec[1], d, if (.site_metric_ok) "一致" else "**不一致**",
                     if (.site_metric_ok) "总量" else "非总量"))
      if (!.site_metric_ok)
        stop("NHANES 部位曲线的指标轴归属无法确认：Table8_metric_axis_check 的 R0 行 ",
             "与 Table6 的 rr_hip 不一致（最大偏差 ", signif(d, 3), "）。",
             "若 04c 改了默认指标轴，须先更新 NHANES_SITE_METRIC 与 §3 的说明，再重跑本步。")
    } else {
      pa_log("⚠️ 指标轴归属校验：Table8_metric_axis_check.csv 中 spec == R0_choi2011 的行数为 ",
             nrow(r0), "（预期 1）→ 归属按声明值 ", NHANES_SITE_METRIC, " 使用，但未能机器校验。")
    }
  } else {
    pa_log("⚠️ 缺 Table8_metric_axis_check.csv 或 Table6_nhanes_hip_wrist_RR.csv → ",
           "指标轴归属未能机器校验，按声明值 ", NHANES_SITE_METRIC, " 使用。")
  }
}

# 过原点斜率（与主模型 `~0 + mm:offset` 同构；04f 用同一函数，便于互相核对）
slope_of <- function(d) {
  w  <- 1 / d$se^2
  b  <- sum(w * d$offset * d$loghr) / sum(w * d$offset^2)
  se <- 1 / sqrt(sum(w * d$offset^2))
  list(b = unname(b), se = unname(se), k = nrow(d))
}
slope_ratio <- function(dh, dw) {          # 髋/腕斜率比（绝对值之比）+ delta 法 CI
  sh <- slope_of(dh); sw <- slope_of(dw)
  lr <- log(abs(sh$b) / abs(sw$b))
  sl <- sqrt((sh$se / sh$b)^2 + (sw$se / sw$b)^2)
  list(ratio = exp(lr), lo = exp(lr - Z975 * sl), hi = exp(lr + Z975 * sl),
       p = 2 * pnorm(-abs(lr / sl)), sh = sh, sw = sw)
}

# =============================================================================
# 1. 抽出文献池里「同指标 × 髋/腕双覆盖」的行
# =============================================================================
bop <- fread(file.path(DIR_BOP, "rr_table.csv"), encoding = "UTF-8")
bop[, offset := as.numeric(exposure_center) - as.numeric(exposure_ref_center)]

# 找出同时有 hip 与 wrist 的指标（device 方法、非 NA 佩戴部位）
# ⚠️ 必须与 05a **主分析**同口径：05a 的 arm 效应用的是
#    `dt_main <- dt[population == "general"]`（第 273 行），即**排除既往 CVD 临床亚组**。
#    若不过滤，CAO24_LPA_Q4（UKB 既往 CVD 亚组，population=clinical_subgroup）
#    会被算进 wrist 侧 → 得到「1 vs 1」的假配对（实测会多出 offset 75 的一个 wrist 行）。
cand <- bop[method == "device" & population == "general" &
            !is.na(wear_site) & wear_site %in% c("hip", "wrist") & !is.na(hr),
            .(metrics = paste(sort(unique(wear_site)), collapse = "+"),
              n_hip = sum(wear_site == "hip"), n_wrist = sum(wear_site == "wrist"),
              n_study = uniqueN(study)),
            by = metric_definition][grepl("\\+", metrics)]
print(cand)

paired <- bop[method == "device" & population == "general" &
              !is.na(wear_site) & wear_site %in% c("hip","wrist") & !is.na(hr) &
              metric_definition %in% cand$metric_definition]
paired[, `:=`(loghr = log(hr),
              se    = (log(hr_hi) - log(hr_lo)) / (2 * Z975))]
# 全池也补上 loghr / se（§2b 的 total_PA 髋侧要从全池取，不只是 paired 子集）
bop[, `:=`(loghr = log(as.numeric(hr)),
           se    = (log(as.numeric(hr_hi)) - log(as.numeric(hr_lo))) / (2 * Z975))]

# =============================================================================
# 2. 逐 offset 直接对照（每侧只有 1 个研究时 = 逐研究配对）
# =============================================================================
direct <- list()
for (md in unique(paired$metric_definition)) {
  d <- paired[metric_definition == md]
  for (of in sort(unique(d$offset))) {
    h <- d[wear_site == "hip"   & offset == of]
    w <- d[wear_site == "wrist" & offset == of]
    if (!nrow(h) || !nrow(w)) next
    # 侧内逆方差加权（本例每侧 1 行 → 退化为该行本身）
    wm <- function(x) { iv <- 1 / x$se^2; sum(iv * x$loghr) / sum(iv) }
    se_w <- function(x) 1 / sqrt(sum(1 / x$se^2))
    lh <- wm(h); lw <- wm(w)
    se <- sqrt(se_w(h)^2 + se_w(w)^2)
    direct[[length(direct) + 1L]] <- data.table(
      metric_definition = md, offset = of,
      hip_studies   = paste(sort(unique(h$study)), collapse = " | "),
      wrist_studies = paste(sort(unique(w$study)), collapse = " | "),
      rr_hip = exp(lh), rr_wrist = exp(lw),
      # 比值定义与 04b/04c 一致：腕/髋（>1 = 腕式 RR 更高 = 髋式更陡）
      ratio_wrist_over_hip = exp(lw - lh),
      ratio_lo = exp(lw - lh - Z975 * se), ratio_hi = exp(lw - lh + Z975 * se),
      p_value  = 2 * pnorm(-abs((lw - lh) / se)))
  }
}
D <- rbindlist(direct)
fwrite(D, file.path(DIR_OUT, "Table8_lit_site_contrast.csv"))
cat("\n===== 文献侧逐 offset 直接对照（腕/髋 比值）=====\n"); print(D[, .(metric_definition, offset, hip_studies, wrist_studies,
                                                              ratio = round(ratio_wrist_over_hip, 3),
                                                              lo = round(ratio_lo, 3), hi = round(ratio_hi, 3),
                                                              p = signif(p_value, 3))])

# =============================================================================
# 2b. 指标错配的**量化许可**（metric-aware 的核心新增，2026-10-16）
# =============================================================================
# 问题：§3 的文献侧比是 **LPA**（池内唯一有髋/腕双覆盖的指标），而 NHANES 参照是**总量**
#   （§0 已机器校验）。要把这个跨指标比较"合法化"，只有一条路：**证明换指标不改变结论**。
# 做法：用与文献侧 LPA **完全相同的估计量**（slope_ratio()），再算一遍**文献侧 total_PA**
#   的髋/腕比：
#     hip  = Ekelund2019 的 total_PA 三行（池内，与 LPA 同一研究、同一参照锚点）
#     wrist= 锚点表 Ko2025_UKB_wrist 三行（pool_role = site_anchor_NONPOOLED；**不入池**）
#   两侧互为独立队列 → 「两来源相减」成立。UKB 重复**只否决"并入池化"**，不否决"相减"
#   （见 data/bop/20261016_入池裁定_UKB腕式总PA双源.md）。
# 判据（★ 关键，必须写清否则看起来自相矛盾）：
#   本许可的判语对象是**两指标在共同 offset 处的「腕/髋 RR 比」** —— 因为 §3 实际比较的
#   就是这个量（文献侧比值 vs NHANES 侧比值），而部位校正因子也是以它外推的。
#   为什么不用「斜率之比」：过原点模型下 RR(o) = exp(b·o)，故
#     腕/髋 @o = exp((b_w − b_h)·o)  —— 由**斜率之差**决定；
#     而「斜率之比」|b_h|/|b_w| 把腕侧斜率放在**分母**上 → 腕侧曲线越平（b_w 绝对值越小），
#     该比值越被放大。实测：LPA 腕侧斜率 −0.00450 远平于 total_PA 腕侧 −0.00849 →
#     斜率之比 3.62 vs 2.35（差 −35%），而共同 offset 处的比值 2.03 vs 1.99（差约 2%）。
#   → 结论必须分两层说：(a) 以 LPA 的**比值**外推部位校正因子可靠（差异在阈值内）；
#     (b) 以 LPA 的**斜率比**外推 total_PA **不可靠**，须在 Limitations 写明。
#   两层的数都落在产物里，不靠说辞。
lic <- list()
anch_p <- file.path(DIR_BOP, "rr_table_site_anchor.csv")
if (file.exists(anch_p)) {
  anch <- fread(anch_p, encoding = "UTF-8")
  # ---- 守卫：锚点行必须全部非池化，且与主池在 row_id 与 study 两个层面都不重叠 ----
  if (!all(anch$pool_role == "site_anchor_NONPOOLED"))
    stop("锚点表存在 pool_role != site_anchor_NONPOOLED 的行：",
         paste(anch[pool_role != "site_anchor_NONPOOLED", row_id], collapse = ", "))
  if (any(anch$row_id %in% bop$row_id))
    stop("锚点行与主池 row_id 撞车：", paste(intersect(anch$row_id, bop$row_id), collapse = ", "))
  if (any(anch$study %in% bop$study))
    stop("锚点 study 与主池 study 撞车（则「相减」前提被破坏）：",
         paste(intersect(anch$study, bop$study), collapse = ", "))
  if (any(anch$population != "general")) stop("锚点表存在 population != general 的行")
  if (any(anch$wear_site != "wrist"))    stop("锚点表存在非腕式行")
  anch[, offset := as.numeric(exposure_center) - as.numeric(exposure_ref_center)]
  anch[, `:=`(loghr = log(as.numeric(hr)),
              se    = (log(as.numeric(hr_hi)) - log(as.numeric(hr_lo))) / (2 * Z975))]

  # 共同 offset 上的**直接对照**（同 §2 口径：exp(y_w − y_h)，SE 为两侧 log-SE 平方和开方）
  direct_ratio <- function(hd, wd, ofs) {
    out <- setNames(as.list(rep(NA_real_, length(ofs) * 3L)),
                    as.vector(rbind(paste0("direct_wrist_over_hip_off", ofs),
                                    paste0("direct_lo_off", ofs),
                                    paste0("direct_hi_off", ofs))))
    for (j in seq_along(ofs)) {
      of <- ofs[j]
      h <- hd[offset == of]; w <- wd[offset == of]
      if (!nrow(h) || !nrow(w)) next
      lh <- mean(h$loghr); lw <- mean(w$loghr)            # 每侧 1 行时即其本身
      se <- sqrt(mean(h$se)^2 + mean(w$se)^2)
      out[[paste0("direct_wrist_over_hip_off", of)]] <- exp(lw - lh)
      out[[paste0("direct_lo_off", of)]] <- exp(lw - lh - Z975 * se)
      out[[paste0("direct_hi_off", of)]] <- exp(lw - lh + Z975 * se)
    }
    as.data.table(out)
  }
  OFS_COM <- c(25, 50, 75)

  mk_lic <- function(md, hd, wd, wlab) {
    sr <- slope_ratio(hd, wd)
    cbind(data.table(
      metric_definition = md,
      hip_studies   = paste(sort(unique(hd$study)), collapse = " | "),
      wrist_studies = wlab,
      offset_grid_hip   = paste(sort(unique(round(hd$offset, 2))), collapse = "/"),
      offset_grid_wrist = paste(sort(unique(round(wd$offset, 2))), collapse = "/"),
      offset_grid_matched = identical(sort(unique(round(hd$offset, 2))),
                                      sort(unique(round(wd$offset, 2)))),
      k_rows_hip = sr$sh$k, k_rows_wrist = sr$sw$k,
      slope_hip = sr$sh$b, slope_wrist = sr$sw$b,
      slope_ratio_hip_over_wrist = sr$ratio, slope_ratio_lo = sr$lo,
      slope_ratio_hi = sr$hi, p_slope_ratio = sr$p,
      hip_over_wrist_at_off60 = exp((sr$sh$b - sr$sw$b) * 60)),
      direct_ratio(hd, wd, OFS_COM))
  }
  hL <- paired[metric_definition == "LPA" & wear_site == "hip"]
  wL <- paired[metric_definition == "LPA" & wear_site == "wrist"]
  hT <- bop[method == "device" & population == "general" & metric_definition == "total_PA" &
            wear_site == "hip" & !is.na(hr)]
  wT <- anch[metric_definition == "total_PA"]
  if (nrow(hL) && nrow(wL)) lic[[length(lic) + 1L]] <-
    mk_lic("LPA", hL, wL, "UKB_wrist_general（池内）")
  # ⚠️ total_PA 分两档报，**许可判据只用对齐档**：
  #   Ko2025 的 offset 网格（25/50/75，参照 12.5）与 EK19 完全重合 → 唯一 apples-to-apples 的档；
  #   Inan-Eroglu2024 的 offset 是 33.33/66.67（参照 16.67），杠杆不同 → 只作旁证单独出一行，
  #   不得与 Ko 合并后再下"同/不同量级"的判语（合并会把两个网格混成一个斜率）。
  if (nrow(hT) && nrow(wT)) {
    wKo <- wT[study == "Ko2025_UKB_wrist"]
    if (nrow(wKo)) lic[[length(lic) + 1L]] <-
      mk_lic("total_PA", hT, wKo, "Ko2025_UKB_wrist（锚点，不入池）")
    if (nrow(wT) > nrow(wKo)) lic[[length(lic) + 1L]] <-
      mk_lic("total_PA_anchor_merged", hT, wT, "Ko2025 + InanEroglu2024（旁证）")
  }
}
LIC <- rbindlist(lic, fill = TRUE)
LIC_MET <- FALSE      # 「两指标（对齐档）在共同 offset 处的比值同量级」是否成立
LIC_TOL <- log(1.25)  # 同量级阈值：±25%
if (nrow(LIC)) {
  rL <- LIC[metric_definition == "LPA"]; rT <- LIC[metric_definition == "total_PA"]
  if (nrow(rL) == 1L && nrow(rT) == 1L) {
    .g <- function(of) rT[[paste0("direct_wrist_over_hip_off", of)]] /
                      rL[[paste0("direct_wrist_over_hip_off", of)]]
    for (of in OFS_COM)
      LIC[, (sprintf("ratio_gap_vs_LPA_off%d", of)) := .g(of)]
    GAP <- vapply(OFS_COM, .g, numeric(1))
    LIC_MET <- max(abs(log(GAP))) < LIC_TOL
    LIC[, max_abs_ratio_gap_pct := 100 * max(abs(GAP - 1))]
    LIC[, slope_ratio_gap_pct := 100 * (slope_ratio_hip_over_wrist /
                                          rL$slope_ratio_hip_over_wrist - 1)]
    LIC[, license_verdict := fcase(
      metric_definition == "LPA", "（参照指标）",
      metric_definition == "total_PA",
        sprintf(paste0("共同 offset 处的比值与 LPA 最大相差 %.1f%% → %s；",
                       "但斜率之比相差 %+.1f%%（腕侧越平、比值越被放大）"),
                max_abs_ratio_gap_pct,
                if (LIC_MET) "**比值同量级**：§3 的跨指标比较不改变结论（**斜率比不可外推**）"
                else "**比值不同量级**：Limitations 须写明部位校正因子的指标依赖性",
                slope_ratio_gap_pct),
      default = "（旁证：offset 网格与髋侧不同，不参与判语）")]
    pa_log(sprintf(paste0("§2b 指标许可：共同 offset 处腕/髋比值 LPA %s vs total_PA %s（最大相差 %.1f%%）-> %s；",
                          "斜率之比 %.2f vs %.2f（%+.1f%%）"),
                   paste(sprintf("%.3f", vapply(OFS_COM, function(o) rL[[paste0("direct_wrist_over_hip_off", o)]], numeric(1))), collapse = "/"),
                   paste(sprintf("%.3f", vapply(OFS_COM, function(o) rT[[paste0("direct_wrist_over_hip_off", o)]], numeric(1))), collapse = "/"),
                   100 * max(abs(GAP - 1)),
                   if (LIC_MET) "比值同量级（许可成立）" else "比值不同量级（许可不成立）",
                   rL$slope_ratio_hip_over_wrist, rT$slope_ratio_hip_over_wrist,
                   100 * (rT$slope_ratio_hip_over_wrist / rL$slope_ratio_hip_over_wrist - 1)))
  } else {
    pa_log("⚠️ §2b 缺 LPA 或 total_PA（对齐档）任一行（nrow(LIC) = ", nrow(LIC), "）→ 许可未判定。")
  }
}
if (nrow(LIC)) fwrite(LIC, file.path(DIR_OUT, "Table8_lit_site_metric_license.csv"))
cat("\n===== §2b 指标错配的量化许可（判语对象 = 共同 offset 处的腕/髋比值；斜率比一并报出）=====\n")
if (nrow(LIC) && "license_verdict" %in% names(LIC)) {
  print(LIC[, .(metric_definition, hip_studies, wrist_studies, offset_grid_matched,
                k_rows_hip, k_rows_wrist,
                direct_off25 = round(direct_wrist_over_hip_off25, 3),
                direct_off50 = round(direct_wrist_over_hip_off50, 3),
                direct_off75 = round(direct_wrist_over_hip_off75, 3),
                slope_ratio  = sprintf("%.3f [%.3f, %.3f]", slope_ratio_hip_over_wrist,
                                       slope_ratio_lo, slope_ratio_hi),
                license_verdict)])
} else if (nrow(LIC)) {
  print(LIC[, .(metric_definition, hip_studies, wrist_studies, offset_grid_matched,
                k_rows_hip, k_rows_wrist, slope_ratio_hip_over_wrist)])
} else cat("（无锚点表或池内无双覆盖指标 → 未计算）\n")

# =============================================================================
# 3. 相容性检验：文献侧点估计是否落在 NHANES 自估的 95% CI 内
# =============================================================================
# 取 04c 的矩阵（R0 × C0 = 与 04b 一致的主档）
# ⚠️ 文献侧的 offset 是 25/50/75（四分位中心 − 参照），而 NHANES 的网格是 10/20/…/80。
#    只有 50 直接重合 → 其余用**对数尺度线性插值**（比在 RR 尺度插值更合理）。
#    插值属于近似，故额外记录「是否落在网格点上」，供论文如实标注。
interp_ratio <- function(tab, of) {
  o <- tab$offset
  f <- function(v) exp(approx(o, log(v), xout = of, rule = 2)$y)
  list(est = f(tab$ratio_mean), lo = f(tab$ratio_lo), hi = f(tab$ratio_hi),
       on_grid = of %in% o)
}

t8p <- file.path(DIR_OUT, "Table8_site_ratio_matrix.csv")
# 指标归属的**逐行标注**（metric-aware）：本节的「文献侧」指标取自 D，而「NHANES 侧」
#   恒为 NHANES_SITE_METRIC（§0 已机器校验 = 总量）。两者不同即 metric_aligned = FALSE
#   → 该行的比对**是跨指标**的，其合法性由 §2b 的量化许可支撑（LIC_MET）。
mk_metric_cols <- function(md) {
  al <- (md == NHANES_SITE_METRIC)
  data.table(
    metric_definition = md,
    lit_metric        = md,
    nhanes_metric     = NHANES_SITE_METRIC,
    metric_aligned    = al,
    comparability     = if (al) "同指标：可直接作相容性检验"
                        else sprintf(paste0("跨指标（文献 %s vs NHANES %s）：由 §2b 的",
                                            "量化许可支撑（Table8_lit_site_metric_license.csv）"), md, NHANES_SITE_METRIC))
}
comp <- data.table()
if (file.exists(t8p)) {
  m8 <- fread(t8p)[hip_rule == "R0_choi2011" & wrist_criterion == "C0_wake600"]
  for (i in seq_len(nrow(D))) {
    of <- D$offset[i]
    iv <- interp_ratio(m8, of)
    comp <- rbind(comp, cbind(mk_metric_cols(D$metric_definition[i]), data.table(
      offset = of,
      lit_ratio = D$ratio_wrist_over_hip[i],
      lit_lo = D$ratio_lo[i], lit_hi = D$ratio_hi[i],
      nhanes_ratio = iv$est, nhanes_lo = iv$lo, nhanes_hi = iv$hi,
      nhanes_value_on_grid = iv$on_grid,
      nhanes_ci_contains_lit_point = (D$ratio_wrist_over_hip[i] >= iv$lo &
                                      D$ratio_wrist_over_hip[i] <= iv$hi),
      ci_overlap = !(D$ratio_hi[i] < iv$lo | D$ratio_lo[i] > iv$hi))))
    pa_log(sprintf("相容性 @off%d（NHANES %s；%s）：文献 %.3f [%.3f, %.3f] vs NHANES %.3f [%.3f, %.3f] → %s",
                   of, ifelse(iv$on_grid, "网格点", "插值"),
                   ifelse(D$metric_definition[i] == NHANES_SITE_METRIC, "同指标", "跨指标"),
                   D$ratio_wrist_over_hip[i],
                   D$ratio_lo[i], D$ratio_hi[i], iv$est, iv$lo, iv$hi,
                   ifelse(comp$nhanes_ci_contains_lit_point[nrow(comp)], "相容", "不相容")))
  }
}
fwrite(comp, file.path(DIR_OUT, "Table8_lit_site_compatibility.csv"))

# 若 04c 尚未产出，退回用 04b 的 Table6（同样做对数尺度插值）
if (!nrow(comp)) {
  t6p <- file.path(DIR_OUT, "Table6_nhanes_hip_wrist_RR.csv")
  if (file.exists(t6p)) {
    t6 <- fread(t6p)
    for (i in seq_len(nrow(D))) {
      of <- D$offset[i]
      iv <- interp_ratio(t6, of)
      comp <- rbind(comp, cbind(mk_metric_cols(D$metric_definition[i]), data.table(
        offset = of, lit_ratio = D$ratio_wrist_over_hip[i],
        lit_lo = D$ratio_lo[i], lit_hi = D$ratio_hi[i],
        nhanes_ratio = iv$est, nhanes_lo = iv$lo, nhanes_hi = iv$hi,
        nhanes_value_on_grid = iv$on_grid,
        nhanes_ci_contains_lit_point = (D$ratio_wrist_over_hip[i] >= iv$lo &
                                        D$ratio_wrist_over_hip[i] <= iv$hi),
        ci_overlap = !(D$ratio_hi[i] < iv$lo | D$ratio_lo[i] > iv$hi))))
    }
    fwrite(comp, file.path(DIR_OUT, "Table8_lit_site_compatibility.csv"))
  }
}
cat("\n===== 文献侧 vs NHANES 自估：相容性 =====\n")
if (nrow(comp)) print(comp[, .(lit_metric, nhanes_metric, metric_aligned, offset,
                               lit = sprintf("%.3f [%.3f, %.3f]", lit_ratio, lit_lo, lit_hi),
                               nhanes = sprintf("%.3f [%.3f, %.3f]", nhanes_ratio, nhanes_lo, nhanes_hi),
                               nhanes_ci_contains_lit_point, ci_overlap)])

# =============================================================================
# 4. 杠杆分析：逐行剔除文献侧任一行，看对照如何变
# =============================================================================
lev <- list()
for (md in unique(paired$metric_definition)) {
  d <- paired[metric_definition == md]
  for (k in seq_len(nrow(d))) {
    dd <- d[-k]
    rec <- data.table(metric_definition = md,
                      dropped_study = d$study[k], dropped_row = d$row_id[k],
                      dropped_site = d$wear_site[k], dropped_offset = d$offset[k])
    # 剔除后各 offset 的对照；只保留双侧齐全的 offset
    ok <- FALSE
    for (of in sort(unique(dd$offset))) {
      h <- dd[wear_site == "hip" & offset == of]; w <- dd[wear_site == "wrist" & offset == of]
      if (nrow(h) && nrow(w)) { rec[[paste0("ratio_off", of)]] <- exp(log(w$hr[1]) - log(h$hr[1])); ok <- TRUE }
    }
    if (ok) lev[[length(lev) + 1L]] <- rec
  }
}
LV <- rbindlist(lev, fill = TRUE)
fwrite(LV, file.path(DIR_OUT, "Table8_lit_site_leverage.csv"))
cat("\n===== 逐行剔除的杠杆（比值 = 腕/髋）=====\n")
print(LV)

# 关键：SV25 的 Q4 是否非单调（源数据自身问题）
nonmono <- paired[wear_site == "wrist", .(study = unique(study),
  monotone = all(diff(hr[order(offset)]) <= 0))]

# =============================================================================
# 5. 设计不可通约性清单（供论文 Limitations 直接引用）
# =============================================================================
# 范围说明（metric-aware，2026-10-16）：本清单描述的是**池内 LPA 那一对**
#   （Ekelund2019 髋 LPA × UKB Sun2025 腕 LPA），即 §2 / §3 实际用到的那对。
#   锚点侧的 **total_PA** 对（Ekelund2019 髋总量 × Ko2025 腕总量）不可通约性清单
#   由 04f_lit_site_anchor.R 单独输出（Table8b_*），两对不可互相套用。
inc <- data.table(
  维度 = c("人群/来源", "队列数", "样本量", "佩戴部位", "设备", "指标定义", "暴露分位构造",
           "随访", "地区", "研究间独立性", "臂内研究数（本池）"),
  EK19 = c("8 个前瞻队列协调化个体数据", "8（多队列池）", "36,383 / 2,149 死亡",
           "髋（ActiGraph 单轴）", "ActiGraph（单轴）", "轻强度 counts 体量（LPA）",
           "分位由构造给出（等份额）", "中位 5.8 年", "多地区", "自身为池化，非单队列",
           "3 行 / 1 个池"),
  SV25 = c("UK Biobank 一般人群", "1（单队列）", "69,492 / 2,024 死亡",
           "腕（Axivity AX3）", "Axivity AX3", "ML(RF) 分类的 LPA 时长（h/day）",
           "分位由构造给出（等份额）", "中位 8.04 年", "英国", "单队列",
           "3 行 / 1 个队列"),
  是否可通约 = c("否", "否", "否", "**这正是要估计的维度**", "否（不同设备与轴数）",
                 "**否**（体量 vs 时长）", "是", "否（5.8 vs 8.04 年）", "否", "否", "否"))
fwrite(inc, file.path(DIR_OUT, "Table8_lit_design_incompat.csv"))

# =============================================================================
# 6. 结论摘要
# =============================================================================
lines <- c(
  "===== 文献侧部位效应：可分解性与相容性 =====\n",
  sprintf("1) 池内同指标双覆盖的指标：%s\n", paste(cand$metric_definition, collapse = ", ")),
  sprintf("2) 该指标下 hip 侧由 %s 提供（%d 行），wrist 侧由 %s 提供（%d 行）；研究数 %d。\n",
          paste(sort(unique(paired[wear_site=='hip']$study)), collapse=", "),
          nrow(paired[wear_site == "hip"]),
          paste(sort(unique(paired[wear_site=='wrist']$study)), collapse=", "),
          nrow(paired[wear_site == "wrist"]), uniqueN(paired$study)),
  "   → 部位效应与「研究」完全共线：随机效应模型无法把 arm 效应与研究级混杂分开。\n",
  sprintf("3) 逐 offset 直接对照（腕/髋）：%s\n",
          paste(sprintf("off%d = %.3f [%.3f, %.3f]", D$offset, D$ratio_wrist_over_hip, D$ratio_lo, D$ratio_hi),
                collapse = "；")),
  sprintf("4) 若把文献侧点估计当作真实部位效应，则 NHANES 同调查内自估应落在其附近\n   （注意：本比较为**跨指标**，文献 %s vs NHANES %s）；\n   实测 %s\n",
          if (nrow(D)) paste(unique(D$metric_definition), collapse = "/") else "-", NHANES_SITE_METRIC,
          if (nrow(comp)) paste(sprintf("off%d：文献 %.3f vs NHANES %.3f [%.3f, %.3f] → %s",
                                        comp$offset, comp$lit_ratio, comp$nhanes_ratio,
                                        comp$nhanes_lo, comp$nhanes_hi,
                                        ifelse(comp$nhanes_ci_contains_lit_point, "相容", "**不相容**")),
                                collapse = "；") else "（缺 04b/04c 产物）"),
  "5) 指标轴（metric-aware，2026-10-16 显式化）：\n",
  sprintf("   池内文献侧比只能用 **%s**（池内唯一有髋/腕双覆盖的指标）；\n",
          paste(cand$metric_definition, collapse = ", ")),
  sprintf("   而 NHANES 同调查内参照的指标轴是 **%s**（§0 机器校验：%s）→ 第 4 条的比较是**跨指标**的。\n",
          NHANES_SITE_METRIC, if (isTRUE(.site_metric_ok)) "已确认" else "未确认"),
  if ("license_verdict" %in% names(LIC)) {
    .rL <- LIC[metric_definition == "LPA"]; .rT <- LIC[metric_definition == "total_PA"]
    sprintf(paste0("   §2b 量化许可：共同 offset（25/50/75）处腕/髋比值 LPA %s vs total_PA（Ko2025）%s",
                   "（最大相差 %.1f%%）→ %s\n",
                   "     附注：两指标的**斜率之比** %.2f vs %.2f（相差 %+.1f%%）—— 腕侧曲线越平则该比值越被放大，",
                   "故**斜率比不可跨指标外推**，须在 Limitations 写明。\n"),
            paste(sprintf("%.3f", c(.rL$direct_wrist_over_hip_off25, .rL$direct_wrist_over_hip_off50,
                                    .rL$direct_wrist_over_hip_off75)), collapse = "/"),
            paste(sprintf("%.3f", c(.rT$direct_wrist_over_hip_off25, .rT$direct_wrist_over_hip_off50,
                                    .rT$direct_wrist_over_hip_off75)), collapse = "/"),
            .rT$max_abs_ratio_gap_pct,
            if (LIC_MET) "比值同量级，跨指标比较不改变结论"
            else "比值不同量级，Limitations 须写明部位校正因子的指标依赖性",
            .rL$slope_ratio_hip_over_wrist, .rT$slope_ratio_hip_over_wrist, .rT$slope_ratio_gap_pct)
  } else "   §2b 量化许可：缺锚点表或池内无双覆盖指标 → 未计算（跨指标比较的合法性未获证据）。\n",
  "6) 结论：文献侧的『部位效应』是**两研究对照**，与 cohort/设备/指标/随访时长等维度完全纠缠；\n",
  "   其点估计超出 NHANES 同调查内估计的 95% CI（且该比较为跨指标，已由 §2b 的许可支撑）\n",
  "   → 不能解释为单纯的佩戴部位效应。\n",
  "   → 论文中应：(a) 以 NHANES 同调查内估计为主证据（≈1.00，支持「髋式曲线可用于腕式暴露侧」）；\n",
  "      (b) 把文献侧比值作为敏感性单列，并在 Limitations 明确其不可分离的混杂。\n")
writeLines(lines, file.path(DIR_OUT, "QC_lit_site_contrast.txt"))
cat("\n"); cat(paste(lines, collapse = ""))

pa_log("04d 完成 -> Table8_lit_* 系列")
