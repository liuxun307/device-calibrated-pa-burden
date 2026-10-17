# =============================================================================
# 95_module3_paf.R
# Module 3：以**真实池化 RR 曲线**重算 LPA 归因负担（PAF）
# -----------------------------------------------------------------------------
# 本脚本取代原 95_dryrun_module3.R。RR 来源已从「NHANES all_cause 占位」升级为
# **Module 2（BoP）产出的 device_pooled 后验曲线**（1000 条，见 output/bop_rr_draws.rds）。
#
# 暴露分布的构造有两条通道（2026-10-14 起，由环境变量 PA_CV_MODE 切换）：
#   grid（默认）= S3：GBD 25+ 简单平均均值 + **假定** CV 网格 c(0.4–1.0)。
#                      冻结口径，产物 PREVIEW_module3_*.csv，逐字节可复现。
#   s1p          = S1′：**cell 级**（15 个 25+ 年龄组 × 2 性别）暴露分布，
#                      · CV 由 NHANES 自估的 SD–mean 关系查表（05 Part A5）；
#                      · 各 cell 按 **25+ 人口占比** 加权合并
#                        （05 Part A6；UN WPP 2024 或 GBD Population）。
#                      —— 同时落实了「SD 来源」与「暴露均值人口加权」两件事。
#                      产物 PREVIEW_module3_s1p_*.csv，不覆盖 grid 口径。
# 除此之外，分母（GBD 批次 2）、分子口径、RR 曲线均为真实数据。
#
# -----------------------------------------------------------------------------
# 核心方法学问题：池化曲线的锚点 ≠ PAF 的反事实
# -----------------------------------------------------------------------------
# Module 2 的曲线横轴是「相对各研究自身参照类别的百分位偏移」(offset_pts, 0–90)，
# 且按构造 RR(offset=0)=1 —— 锚在**最低四分位**（相对百分位 12.5）。
# 而 PAF 的定义要求 RR 相对**反事实（TMREL）** 为 1：
#
#     PAF = Σ_x P(x)·(RR(x) − 1) / [1 + Σ_x P(x)·(RR(x) − 1)]
#
# 直接把「锚在最低四分位」的曲线代入会把 PAF 算成负值（高活动者 RR<1）。
# 因此必须显式桥接两步（本脚本 make_rr_fun_pooled() 实现）：
#
#   ① 尺度桥接（也是「保秩映射 M2」的落地）：
#        目标人群自身百分位   p(y) = F_px(y)          （y 为 MIMS/day）
#        相对参照的偏移       off(y) = max(0, 100·p(y) − 12.5)
#      —— 用**目标人群自己的分布**定百分位，因此国别/年际异质性被完整保留
#         （这正是 dry-run 中 M1 条件均值映射被实证否决后的正确做法）。
#
#   ② 反事实重锚定（RR=1 于 TMREL 及以上）：
#        RR_abs(y) = max(1, RR_pooled(off(y)) / RR_pooled(off(TMREL)))
#      —— 除以 TMREL 处的相对风险，把「相对最低四分位」换算为「相对 TMREL」；
#         并按 GBD 惯例对 ≥TMREL 段封顶为 1（"不假设 TMREL 以上还有额外获益"）。
#         封顶可关闭（PA_RR_NOCLAMP=1）作为敏感性——两者都会报告。
#
# 全部桥接中间量落盘 output/PREVIEW_module3_rr_bridge.csv，可逐步复核。
#
# 依赖：先跑通 01→05b（需 output/bop_rr_draws.rds、output/rr_curves.csv、
#       output/analytic.rds）；GBD 批次 1/2 已在 data/gbd/
# =============================================================================

# ---- 统一引导：locale + 00_setup.R + 复用 05 的全部函数与对象 ----
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

# 复用 05：提供 pred_mims / SIGMA_MIMS / tmrel_*_mims / exposure_dist /
#          paf_from_dist / find_gbd_role / read_gbd_shards / recompute_burden / LPA_CAUSES
.old_wd <- getwd()
source("05_burden_calibration_paf.R")
setwd(.old_wd)

# -----------------------------------------------------------------------------
# 可覆盖项（2026-10-12 新增，用于**敏感性运行**而不触碰 ② 的冻结产物）
#   三个环境变量的**默认值 = 原硬编码值** → 不设变量时逐字节行为完全不变。
#   PA_RR_DRAWS     覆盖 RR 后验来源（默认 output/bop_rr_draws.rds）
#                   例：05c 产出的 bop_rr_draws_withNHANES.rds（影响力敏感性）
#   PA_PREVIEW_TAG  覆盖产物内的 tag 字段（默认 PREVIEW_RealRR_S3SD）
#   PA_OUT_PREFIX   覆盖产物文件名前缀（默认 PREVIEW_module3_）
#                   ⚠️ 不覆盖时输出文件名与内容与 ② 完全一致；覆盖后写新文件名，
#                      因此敏感性运行**不会**覆盖已验证的 5 个 PREVIEW 产物。
# -----------------------------------------------------------------------------
# CV_MODE（2026-10-14 新增）：暴露分布 CV 的来源
#   grid（默认）= S3：GBD 25+ 简单平均均值 + 假定 CV 网格 —— 原口径，逐字节不变
#   s1p          = S1′：**cell 级**（15 个 25+ 年龄组 × 2 性别）暴露分布，
#                  · 每个 cell 的 CV 由 S1′（NHANES 自估的 SD–mean 关系）查表；
#                  · 各 cell 按 **25+ 人口占比** 加权合并（见 05 的 Part A6）；
#                  · 需 data/external/owid_pop5.csv 或 data/gbd/population_25plus/。
#   ⚠️ 两种模式的产物**文件名不同**（见下），互不覆盖。
CV_MODE     <- Sys.getenv("PA_CV_MODE", unset = "grid")
if (!CV_MODE %in% c("grid", "s1p"))
  stop("PA_CV_MODE 只能是 grid | s1p，收到：", CV_MODE)

PREVIEW_TAG <- Sys.getenv("PA_PREVIEW_TAG",
                          unset = if (CV_MODE == "s1p") "PREVIEW_RealRR_S1pSD"
                                  else "PREVIEW_RealRR_S3SD")
OUT_PREFIX  <- Sys.getenv("PA_OUT_PREFIX",
                          unset = if (CV_MODE == "s1p") "PREVIEW_module3_s1p_"
                                  else "PREVIEW_module3_")
N_DRAWS     <- as.integer(Sys.getenv("PA_N_DRAWS", unset = "400"))
message("\n=========== Module 3 PAF 预览（", PREVIEW_TAG,
        " | CV_MODE=", CV_MODE, " | RR 桥接=确定性枚举（全部后验曲线））===========\n")

TMREL_MID_MIMS <- mean(c(tmrel_lo_mims, tmrel_hi_mims))
message(sprintf("TMREL 设备等效（取中）：%.0f MIMS/day（区间 %.0f–%.0f）",
                TMREL_MID_MIMS, tmrel_lo_mims, tmrel_hi_mims))

# ---------------------------------------------------------------------------
# 1. RR 来源 A：真实池化曲线（Module 2 → device_pooled）
# ---------------------------------------------------------------------------
rds_file <- Sys.getenv("PA_RR_DRAWS", unset = "")
if (!nzchar(rds_file)) rds_file <- file.path(DIR_OUT, "bop_rr_draws.rds")
if (!file.exists(rds_file)) stop("缺少 ", rds_file, " —— 请先跑通 05a_module2_bop.R（或 05c）。")
message("RR 后验来源：", basename(rds_file))
BOP <- readRDS(rds_file)
message(sprintf("池化后验：%d 条 × %d 网格点（fit_mode=%s, seed=%s）",
                BOP$n_draw, length(BOP$offset_grid), BOP$fit_mode, BOP$seed))

# qc: 曲线集必须含 device_pooled × total_PA（MIMS/day 是总量型指标）
BOP_META <- data.table(curve_role = BOP$curve_role, metric = BOP$metric,
                       offset_pts = BOP$offset_grid)
DP_IDX <- which(BOP_META$curve_role == "device_pooled" & BOP_META$metric == "total_PA")
if (!length(DP_IDX))
  stop("bop_rr_draws.rds 中没有 curve_role=='device_pooled' & metric=='total_PA' 的曲线。")
message(sprintf("device_pooled × total_PA：%d 个 offset 点（%g–%g）",
                length(DP_IDX), min(BOP_META$offset_pts[DP_IDX]), max(BOP_META$offset_pts[DP_IDX])))

# 把「相对百分位」后验桥接到 MIMS/day 尺度，并按 TMREL 重锚定
make_rr_fun_pooled <- function(BOP, px, metric = "total_PA",
                               clamp = TRUE, n_curve_draws = 200L,
                               compute_curve = TRUE) {
  meta <- data.table(curve_role = BOP$curve_role, metric = BOP$metric,
                     offset_pts = BOP$offset_grid)
  idx <- which(meta$curve_role == "device_pooled" & meta$metric == metric)
  if (!length(idx)) stop("池化后验中缺 device_pooled × ", metric)
  o   <- order(meta$offset_pts[idx])
  idx <- idx[o]; off_grid <- meta$offset_pts[idx]
  D   <- BOP$draws[, idx, drop = FALSE]            # n_draw × n_off
  ref_pct <- BOP$ref_canon

  # ① 尺度桥接：目标人群百分位 → 相对参照的偏移
  p <- cumsum(px$f); p <- p / max(p)
  off_y <- pmax(0, 100 * p - ref_pct)

  # TMREL 在该人群分布中的百分位（同样的尺度桥接）
  p_tmrel  <- approx(px$mims, p, xout = TMREL_MID_MIMS, rule = 2)$y
  off_tmrel <- max(0, 100 * p_tmrel - ref_pct)

  rr_at <- function(v, off) approx(off_grid, v, xout = off, rule = 2)$y

  # ---- 确定性枚举器（2026-10-15 起为默认路径）--------------------------------
  #   fun() 返回 n_curve × n_off 矩阵，**每一行是一条后验 RR 曲线**（MIMS/day 尺度，
  #   已按 TMREL 重锚定，必要时已 clamp）。首次调用时一次算好并缓存（记忆化）。
  #   为什么枚举而不是抽样：PAF 是 RR 后验的**期望**，枚举全部曲线得到确定性量
  #   （方差 0）——既在方法论上更正确，也让 95 / 95c / 95b 三处产物严格一致。
  #   旧版「有放回抽 1 条 × N 次取均值」是 MC 近似，四处最大相差 1.55%
  #   （见 10_captions.R 的口径一致性自检表）。枚举还更快：每组合 1 次矩阵运算
  #   取代 N 次逐条插值（95c 实测由 ~17 min 显著下降）。
  mat_cache <- NULL
  fun <- function() {
    if (is.null(mat_cache)) {
      M <- t(vapply(seq_len(nrow(D)), function(k) {
        rr_at(D[k, ], off_y) / rr_at(D[k, ], off_tmrel)
      }, numeric(length(off_y))))
      # ⚠️ 不要写 pmax(1, M) —— pmax 会**丢掉矩阵的 dim 属性**（R 陷阱），
      #    导致后续 %*% 静默算错。统一用就地逻辑索引赋值。
      if (clamp) M[M < 1] <- 1
      mat_cache <<- M
    }
    mat_cache
  }

  # 兼容入口：需要旧「单次随机抽样」行为时用（干跑 / 探针脚本）。
  fun_draw <- function() {
    v <- D[sample.int(nrow(D), 1L), ]
    r <- rr_at(v, off_y) / rr_at(v, off_tmrel)
    if (clamp) r[r < 1] <- 1
    r
  }

  # 后验均值曲线（供审计表用；改用**全部**曲线求平均，不再抽 n_curve_draws 条）
  #   —— 仅诊断需要，主路径用 compute_curve = FALSE 跳过（省 ~1000×2 次插值）
  mean_curve <- NULL
  if (compute_curve) {
    pre_mat <- t(vapply(seq_len(nrow(D)), function(k) rr_at(D[k, ], off_y), numeric(length(off_y))))
    ratio   <- t(vapply(seq_len(nrow(D)), function(k) {
      rr_at(D[k, ], off_y) / rr_at(D[k, ], off_tmrel)
    }, numeric(length(off_y))))
    if (clamp) ratio[ratio < 1] <- 1
    mean_curve <- list(pre = colMeans(pre_mat), abs = colMeans(ratio))
  }

  # n_curve_draws 参数保留仅为签名兼容（确定性路径已不再抽样）
  list(fun = fun, fun_draw = fun_draw, n_curve = nrow(D), mean_curve = mean_curve,
       info = list(curve_role = "device_pooled", metric = metric, clamp = clamp,
                   off_grid = off_grid, ref_pct = ref_pct,
                   p_tmrel = p_tmrel, off_tmrel = off_tmrel,
                   tmrel_mims = TMREL_MID_MIMS))
}

# ---------------------------------------------------------------------------
# 2. RR 来源 B：NHANES all_cause 曲线（对照臂，复现原 dry-run 口径）
# ---------------------------------------------------------------------------
rr_file <- file.path(DIR_OUT, "rr_curves.csv")
if (!file.exists(rr_file)) stop("缺少 ", rr_file, " —— 请先跑通 01→04。")
RR_NH <- fread(rr_file)
rr_all <- RR_NH[outcome == "all_cause"][order(x)]
if (!nrow(rr_all)) stop("rr_curves.csv 中没有 all_cause 曲线。")

# NHANES 对照臂：rr_curves.csv 的 all_cause 曲线只给点估计与 CI，没有后验 draw，
# 故按 log-HR 的正态近似**枚举** n_curve 条曲线（固定种子 → 跨运行可复现），
# 与 pooled 臂同构：返回矩阵 → recompute_burden() 走确定性路径，
# 区间 = 这 n_curve 条曲线 PAF 的 2.5% / 97.5% 分位（不再依赖全局 RNG 流）。
make_rr_fun_nhanes <- function(curve, x_ref, n_curve = 200L, seed = PA_SEED) {
  a <- curve[order(x)]
  se_log <- (log(a$hi) - log(a$lo)) / (2 * 1.959964)
  se_log[!is.finite(se_log)] <- 0
  # 就地种种子并还原全局 RNG 状态，避免污染调用方的随机流
  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
    get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit({
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
        rm(".Random.seed", envir = .GlobalEnv)
    } else assign(".Random.seed", old_seed, envir = .GlobalEnv)
  }, add = TRUE)
  set.seed(seed)
  M <- t(vapply(seq_len(n_curve), function(k) {
    hr_draw <- exp(log(a$hr) + rnorm(length(a$hr), 0, se_log))
    as.numeric(approx(a$x, hr_draw, xout = x_ref, rule = 2)$y)
  }, numeric(length(x_ref))))
  function() M
}

# ---------------------------------------------------------------------------
# 3. GBD 分母（批次 2）与 GBD 现报归因值（批次 1）
# ---------------------------------------------------------------------------
b2 <- read_gbd_shards(find_gbd_role("cause_totals"), "cause_totals")
b1 <- read_gbd_shards(find_gbd_role("lpa_attributable"), "attributable")
if (is.null(b2)) stop("未识别到批次 2（Cause 总负担）文件，PAF 分母缺失。")
if (is.null(b1)) warning("未识别到批次 1（LPA 归因负担）文件，将无法做『GBD 现报 vs 重算』对比。")

# ---------------------------------------------------------------------------
# 年龄口径守卫（2026-10-14 · D2 方案 B 落地）
#   LPA 的暴露定义只覆盖 **25 岁以上**（Capstone appendix 2, p.375），
#   故 PAF 的**分母**必须是 25+ 的 cause 总负担，才能与分子（归因值）同口径。
#
#   历史坑（已实测）：
#     · 旧版分母用 `All ages`（含 0–24 岁），而 0–24 岁不产生任何归因
#       → PAF 被**系统性低估**（D2 缺口）。
#     · D2 改拉 25+ 分母后，分母每 cause 有 15 个五岁组；若仍用旧的
#       build_wide()（只按 location×year 过滤、**不聚合年龄**），则同键 15 行重复，
#       `dcast` 无 fun.aggregate → **静默退化为计数**（产出垃圾且不报错）。
#     · 若新旧两份分母文件并存，`All ages` 与 `Σ25+` 都会被计入 → 分母翻倍。
#       （注意：`96` 的「分片互斥」检查**查不出**这一条，因为 age_name 不同、键不重叠。
#         现已改为硬断言，并在 `05`/`96` 双双排除 `_archive_*` 目录。）
#
#   本段做两件事：
#     (1) 断言分母**不含** `All ages` / `Age-standardized`（一旦出现立即 stop）；
#     (2) build_wide() 对年龄组**求和**后再 dcast。
# ---------------------------------------------------------------------------
AGE_ALL_PAT <- "^all ages$"
AGE_STD_PAT <- "^age[- ]standardized$"

assert_denominator_age <- function(d) {
  if (is.null(d) || !"age_name" %in% names(d)) return(invisible(TRUE))
  au  <- unique(as.character(d$age_name))
  bad <- au[grepl(AGE_ALL_PAT, au, ignore.case = TRUE) |
              grepl(AGE_STD_PAT, au, ignore.case = TRUE)]
  if (length(bad)) {
    stop(sprintf(paste0(
      "PAF 分母（批次 2）中出现了非 25+ 的年龄口径：%s\n",
      "  · `All ages` 含 0–24 岁，与「LPA 仅覆盖 25+」不匹配 → PAF 被系统性低估；\n",
      "  · 若与 25+ 五岁组并存，更会让分母被**重复计入**（≈ 翻倍）。\n",
      "  处置：把退役版本移入 data/gbd/_archive_*（05/96 均已自动忽略该目录），\n",
      "        只保留 25+ 五岁组分母；或改回 All ages 口径并同步修改分子。"),
      paste(bad, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}
assert_denominator_age(b2)

# 分子侧说明（不是断言，仅登记）：批次 1（归因值）用 `All ages` 是**正确**的 ——
# 因 LPA 在 0–24 岁无归因，故其 All ages 合计 ≡ 25+ 的归因合计，与 25+ 分母同口径。
if (!is.null(b1) && "age_name" %in% names(b1)) {
  au1 <- unique(as.character(b1$age_name))
  if (!any(grepl(AGE_ALL_PAT, au1, ignore.case = TRUE)))
    warning(sprintf(paste0("批次 1（归因值）的 age_name = %s，非预期的 `All ages`；",
                           "请确认其合计口径与 25+ 分母一致。"),
                    paste(au1, collapse = ", ")), call. = FALSE)
}

short_meas <- function(x) fifelse(grepl("DALY", x, ignore.case = TRUE), "dalys", "deaths")

# 把某 location×year 的分母/归因值整理成 cause × {deaths, dalys} 宽表。
#   2026-10-14：新增「按 cause × measure **求和**」一步 —— 25+ 分母每个 cause 有
#   15 个五岁组，必须先求和成该 cause 的 25+ 合计，否则 dcast 会因同键重复而
#   静默退化为计数。对批次 1（单 `All ages` 组）求和是恒等变换，无副作用。
build_wide <- function(d, loc, yr, suffix) {
  dd <- d[location_name == loc & year == yr]
  if (!nrow(dd)) return(NULL)
  dd <- dd[, .(cause_name, meas = short_meas(measure_name), val)]
  dd <- dd[, .(val = sum(val, na.rm = TRUE)), by = .(cause_name, meas)]
  w  <- dcast(dd, cause_name ~ meas, value.var = "val")
  setnames(w, c("deaths", "dalys"),
           c(paste0("deaths_", suffix), paste0("dalys_", suffix)), skip_absent = TRUE)
  w
}

# ---------------------------------------------------------------------------
# 4. 暴露分布：两条通道（2026-10-14 改造）
# ---------------------------------------------------------------------------
#   grid（默认）：GBD 25+ 各 5 岁组的**简单平均** + S3 的 CV 网格
#                 —— 保留原口径，与已冻结产物逐字节一致
#   s1p         ：**cell 级**（15 个 25+ 年龄组 × 2 性别）各建一条设备尺度
#                 分布，再按 25+ 人口占比加权合并：
#                 · CV  来自 S1′（05 的 Part A5：NHANES 自估的 SD–mean 关系）
#                 · 权重 来自 A6 的人口表（UN WPP 2024 / 或 GBD Population）
#                 —— 这一步同时落实了「SD 来源（S1′）」与「暴露均值人口加权」
# ---------------------------------------------------------------------------
expo <- read_lpa_exposure(gbd_expo)
if (is.null(expo)) stop("未读到暴露包。")

# 25+ 的 15 个 GBD age_group_id（与 05 的 SD_GBD_AGE2IDX 同源）
GBD_AGE_25PLUS <- as.integer(names(SD_GBD_AGE2IDX))

# grid 通道用的简单平均（保留原实现，勿改 —— 逐字节复现依赖它）
pop_mean_met <- function(loc, yr) {
  em <- expo[location_name == loc & year_id == yr]
  if (!nrow(em)) return(NA_real_)
  if ("sex" %in% names(em)) {
    eb <- em[sex %in% c("Both", "both")]
    if (nrow(eb)) em <- eb
    else em <- em[sex %in% c("Male", "Female")]
  }
  mean(em$mean, na.rm = TRUE)
}

# s1p 通道：cell 级分布 + 人口加权合并
#   返回结构与 exposure_dist() 兼容（mims / f / mean_mims / sigma_cond），
#   另附 cells（逐 cell 明细，供审计）与 cv_wavg（加权平均 CV，作标签用）。
px_cells_s1p <- function(loc, yr, fit = SD_FIT$met_w,
                         n_mims = 301,
                         mims_cap = max(adm$mims_per_day, na.rm = TRUE) * 1.2) {
  em <- expo[location_name == loc & year_id == yr &
               age_group_id %in% GBD_AGE_25PLUS]
  if (!nrow(em)) return(NULL)

  cells <- data.table(age_group_id = as.integer(em$age_group_id),
                      sex          = as.character(em$sex),
                      mean_met     = as.numeric(em$mean))
  cells <- cells[is.finite(mean_met) & mean_met > 0]
  if (!nrow(cells)) return(NULL)

  cells[, age_idx  := SD_GBD_AGE2IDX[as.character(age_group_id)]]
  cells[, female_f := fifelse(grepl("^f", sex, ignore.case = TRUE), 1, 0)]
  cells[, cv       := fit$pred_sd(mean_met, age_idx, female_f) / mean_met]
  cells <- cells[is.finite(cv) & cv > 0]
  if (!nrow(cells)) return(NULL)

  # --- 人口权重（按年龄；性别在两 cell 之间等分，与 pop_mean_met 的两性口径一致）---
  ent <- resolve_pop_loc(loc)
  pw  <- NULL
  if (!is.null(POP_W) && !is.na(ent)) {
    pw <- if ("pop_entity" %in% names(POP_W))
      POP_W[pop_entity == ent & year == yr, .(age_group_id, w)]
    else
      POP_W[location_name == ent & year == yr, .(age_group_id, w)]
    if (!nrow(pw)) pw <- NULL
  }
  if (is.null(pw)) {
    # 无人口表 -> 均匀（每个 cell 等权）
    cells[, w_age := 1]
    w_src <- "uniform"
    ent   <- NA_character_
  } else {
    cells <- merge(cells, pw, by = "age_group_id", all.x = TRUE)
    # 年龄权重 = 该年龄组的人口占比；组内两性别等分（与 pop_mean_met 的两性口径一致）
    #   ⚠️ 这里**只能归一化一次**。若先按 age_group_id 组内归一再全局归一，
    #      组内的年龄信息会被抹掉 -> w_cell 退化为常数 1/(组数×2) = 均匀权重。
    cells[, w_age := fifelse(is.finite(w) & w > 0, w, 1)]
    w_src <- if (any(is.na(cells$w))) "partial_pop" else "pop"
  }
  cells[, w_cell := w_age / sum(w_age)]

  # --- 合并 cell 级设备尺度分布 ---
  y <- seq(0, mims_cap, length.out = n_mims)
  f <- numeric(n_mims)
  for (i in seq_len(nrow(cells))) {
    di <- exposure_dist(mean_met = cells$mean_met[i], cv = cells$cv[i],
                        n_mims = n_mims, mims_cap = mims_cap)
    f <- f + cells$w_cell[i] * di$f
  }
  f <- f / sum(f)
  mu <- sum(y * f)

  list(mims = y, f = f, mean_mims = mu, sigma_cond = SIGMA_MIMS,
       cells = cells,
       mean_met_w = sum(cells$w_cell * cells$mean_met),
       cv_wavg    = sum(cells$w_cell * cells$cv),
       cv_eff_dev = sqrt(sum(f * (y - mu)^2)) / mu,
       w_src = w_src, pop_entity = ent)
}

# 统一入口：grid 用 (简单平均均值, cv)；s1p 忽略 cv（CV 由 cell 级查表决定）
build_px <- function(loc, yr, cv) {
  if (CV_MODE == "s1p") {
    px_cells_s1p(loc, yr)
  } else {
    mt <- pop_mean_met(loc, yr)
    if (!is.finite(mt)) return(NULL)
    exposure_dist(mean_met = mt, cv = cv)
  }
}

# ---------------------------------------------------------------------------
# 5. 主循环：location × year × CV × RR 来源
# ---------------------------------------------------------------------------
NOCLAMP <- identical(Sys.getenv("PA_RR_NOCLAMP", unset = ""), "1")

# TMREL 在给定人群分布中的偏移（独立小函数，避免为取一个数而建整条曲线）
tmrel_off <- function(px, ref_pct = BOP$ref_canon) {
  p <- cumsum(px$f); p <- p / max(p)
  pmax(0, 100 * approx(px$mims, p, xout = TMREL_MID_MIMS, rule = 2)$y - ref_pct)
}

# 显式固定本段抽样的随机流：
#   upstream（00_setup 的 set.seed + 05 内部的 RNG 消耗）虽已确定，但一旦有人
#   改动 05 的抽样次数，本脚本的后验抽样序列会随之漂移 —— 那样「同代码同数据」
#   就不再给出同结果。这里把种子独立钉死，使 95 自包含、可逐字节复现。
set.seed(PA_SEED + 3L)

# ---------------------------------------------------------------------------
# 【复用开关】PA_M3_HELPERS_ONLY=1
#   置 1 时：本脚本只定义到此处为止的全部函数与数据对象
#            （BOP / b1 / b2 / expo / make_rr_fun_pooled / make_rr_fun_nhanes /
#              build_wide / pop_mean_met / px_cells_s1p / build_px / tmrel_off /
#              NOCLAMP / TMREL_MID_MIMS / CV_MODE / N_DRAWS …），
#            并**跳过** 8 地区主循环与 5 个产物的落盘。
#   用途：供 95c_module3_bycountry.R（205 国逐国版）复用同一套桥接逻辑，
#         避免把 ~200 行口径敏感的代码复制成第二份而长期漂移。
#   默认（未设该变量）：行为与加入本开关前**逐字节一致**（已用 5 个产物 md5 验证）。
# ---------------------------------------------------------------------------
if (identical(Sys.getenv("PA_M3_HELPERS_ONLY", unset = ""), "1")) {
  message("[95] PA_M3_HELPERS_ONLY=1：仅加载 helpers，跳过 8 地区主循环与落盘。")
} else {

LOCS  <- c("Global", "China", "Japan", "United States of America",
           "India", "Nigeria", "Brazil", "Germany")
YEARS <- c(1990, 2022)
CVS     <- if (CV_MODE == "s1p") 1 else EXPO_SD_GRID   # s1p：CV 由 cell 级查表决定，跑一次即可
CV_MAIN <- 0.60                  # grid 模式的预览主情景（s1p 模式下不参与筛选）
SRC_MAIN <- "pooled"             # 主分析 RR 来源

tot_rows <- list(); cause_rows <- list(); diag_rows <- list()
bridge_rows <- list(); cmp_rows <- list()

skipped <- character(0)

for (loc in LOCS) for (yr in YEARS) {
  mt <- pop_mean_met(loc, yr)
  w2 <- build_wide(b2, loc, yr, "total")
  if (is.null(w2) || !is.finite(mt)) {
    skipped <- c(skipped, sprintf("%s %d", loc, yr)); next
  }
  for (cc in c("deaths_total", "dalys_total"))
    if (!cc %in% names(w2)) w2[, (cc) := NA_real_]

  for (cv in CVS) {
    px <- build_px(loc, yr, cv)
    if (is.null(px)) { skipped <- c(skipped, sprintf("%s %d (px 构造失败)", loc, yr)); next }

    # 情景标签：grid 用网格值；s1p 用该 location×year 的加权平均 CV（有实际含义）
    cv_lab  <- if (CV_MODE == "s1p") px$cv_wavg else cv
    is_main <- if (CV_MODE == "s1p") TRUE else abs(cv - CV_MAIN) < 1e-9
    mt_lab  <- if (!is.null(px$mean_met_w)) px$mean_met_w else mt

    for (src in c("pooled", "nhanes")) {
      if (src == "pooled") {
        br  <- make_rr_fun_pooled(BOP, px, metric = "total_PA",
                                  clamp = !NOCLAMP, compute_curve = FALSE)
        rrf <- br$fun
      } else {
        rrf <- make_rr_fun_nhanes(rr_all, px$mims)
      }
      res <- recompute_burden(px$f, rrf, gbd_dt = w2,
                              causes = LPA_CAUSES, n_draws = N_DRAWS)
      res[, `:=`(location = loc, year = yr, cv = cv_lab, cv_mode = CV_MODE,
                 is_main = is_main, rr_source = src, tag = PREVIEW_TAG)]
      cause_rows[[length(cause_rows) + 1L]] <- res
    }

    # --- 暴露分布 + RR 桥接诊断（主来源）---
    br <- make_rr_fun_pooled(BOP, px, metric = "total_PA", clamp = !NOCLAMP)
    mu  <- sum(px$mims * px$f)
    sdv <- sqrt(sum(px$f * (px$mims - mu)^2))
    p   <- cumsum(px$f); p <- p / max(p)
    # ⚠️ 与 recompute_burden() 同口径：**逐曲线算 PAF 再平均**（E[PAF]）。
    #    若写成 paf_from_dist(px$f, br$mean_curve$abs)（即 PAF(E[rr])），
    #    因 PAF 非线性会系统性偏高约 0.24%（Global 2022：0.174495 vs 0.174079）。
    implied_paf_pooled <- mean(paf_from_dist_mat(px$f, br$fun()))
    implied_paf_nh     <- paf_from_dist(px$f, approx(rr_all$x, rr_all$hr, xout = px$mims, rule = 2)$y)
    diag_rows[[length(diag_rows) + 1L]] <- data.table(
      location = loc, year = yr, cv = cv_lab, cv_mode = CV_MODE,
      mean_met_wk = mt_lab, mean_mims = mu, sd_mims = sdv,
      cv_wavg_met = if (!is.null(px$cv_wavg))    px$cv_wavg    else NA_real_,
      cv_eff_dev  = if (!is.null(px$cv_eff_dev)) px$cv_eff_dev else sdv / mu,
      pop_w_src   = if (!is.null(px$w_src))      px$w_src      else "n/a",
      pop_entity  = if (!is.null(px$pop_entity)) px$pop_entity else NA_character_,
      median_mims = px$mims[which.min(abs(p - 0.5))],
      pct_below_tmrel = sum(px$f[px$mims < TMREL_MID_MIMS]),
      p_tmrel = br$info$p_tmrel, off_tmrel = br$info$off_tmrel,
      implied_paf_pooled = implied_paf_pooled,
      implied_paf_nhanes = implied_paf_nh,
      clamp = !NOCLAMP)
  }
  # --- 主情景：各来源的总量与 GBD 现报对比 ---
  px <- build_px(loc, yr, CV_MAIN)
  if (is.null(px)) next
  mt_lab      <- if (!is.null(px$mean_met_w)) px$mean_met_w else mt
  cv_main_lab <- if (CV_MODE == "s1p") px$cv_wavg else CV_MAIN
  w1 <- if (!is.null(b1)) build_wide(b1, loc, yr, "gbd") else NULL
  for (src in c("pooled", "nhanes")) {
    cr <- rbindlist(cause_rows)[location == loc & year == yr &
                                  (is_main) & rr_source == src]
    tot <- data.table(
      location = loc, year = yr, rr_source = src, cv_mode = CV_MODE,
      cv_main = cv_main_lab, mean_met_wk = mt_lab,
      total_deaths = sum(w2$deaths_total, na.rm = TRUE),
      total_dalys  = sum(w2$dalys_total,  na.rm = TRUE),
      recomputed_deaths = sum(cr$deaths_attrib, na.rm = TRUE),
      recomputed_dalys  = sum(cr$dalys_attrib,  na.rm = TRUE))
    tot[, `:=`(paf_deaths = recomputed_deaths / total_deaths,
               paf_dalys  = recomputed_dalys  / total_dalys)]
    if (!is.null(w1)) {
      tot[, `:=`(gbd_deaths = sum(w1$deaths_gbd, na.rm = TRUE),
                 gbd_dalys  = sum(w1$dalys_gbd,  na.rm = TRUE))]
      tot[, `:=`(gbd_paf_deaths = gbd_deaths / total_deaths,
                 gbd_paf_dalys  = gbd_dalys  / total_dalys,
                 diff_deaths_pct = 100 * (recomputed_deaths / gbd_deaths - 1),
                 diff_dalys_pct  = 100 * (recomputed_dalys  / gbd_dalys  - 1))]
    }
    tot[, tag := PREVIEW_TAG]
    tot_rows[[length(tot_rows) + 1L]] <- tot
    cmp_rows[[length(cmp_rows) + 1L]] <- copy(tot)[, `:=`(
      pct_below_tmrel = sum(px$f[px$mims < TMREL_MID_MIMS]),
      off_tmrel = tmrel_off(px))]
  }
}

TOT   <- rbindlist(tot_rows, fill = TRUE)
CAUSE <- rbindlist(cause_rows, fill = TRUE)
DIAG  <- rbindlist(diag_rows, fill = TRUE)
CMP   <- rbindlist(cmp_rows, fill = TRUE)

# ---------------------------------------------------------------------------
# 6. RR 桥接审计表（以 Global 2022 @ CV_MAIN 为例，逐点展示五列）
# ---------------------------------------------------------------------------
px_ref <- build_px("Global", 2022, CV_MAIN)
if (is.null(px_ref)) stop("BRIDGE：Global 2022 的暴露分布构造失败")
cv_ref <- if (CV_MODE == "s1p") px_ref$cv_wavg else CV_MAIN
br_ref <- make_rr_fun_pooled(BOP, px_ref, metric = "total_PA", clamp = !NOCLAMP)
p_ref  <- cumsum(px_ref$f); p_ref <- p_ref / max(p_ref)
q_probe <- c(0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
iy <- vapply(q_probe, function(q) which.min(abs(p_ref - q)), integer(1))
BRIDGE <- data.table(
  location = "Global", year = 2022, cv = cv_ref, cv_mode = CV_MODE,
  target_pct = 100 * p_ref[iy],
  mims_per_day = round(px_ref$mims[iy]),
  off_y = round(pmax(0, 100 * p_ref[iy] - br_ref$info$ref_pct), 2),
  rr_pooled_relQ1 = round(br_ref$mean_curve$pre[iy], 3),
  rr_abs_anchored = round(br_ref$mean_curve$abs[iy], 3),
  above_tmrel = px_ref$mims[iy] >= TMREL_MID_MIMS)

# ---------------------------------------------------------------------------
# 7. 落盘
# ---------------------------------------------------------------------------
fwrite(TOT,    file.path(DIR_OUT, paste0(OUT_PREFIX, "totals.csv")))
fwrite(CAUSE,  file.path(DIR_OUT, paste0(OUT_PREFIX, "by_cause.csv")))
fwrite(DIAG,   file.path(DIR_OUT, paste0(OUT_PREFIX, "exposure_diag.csv")))
fwrite(CMP,    file.path(DIR_OUT, paste0(OUT_PREFIX, "rr_source_compare.csv")))
fwrite(BRIDGE, file.path(DIR_OUT, paste0(OUT_PREFIX, "rr_bridge.csv")))

# ---------------------------------------------------------------------------
# 8. 打印
# ---------------------------------------------------------------------------
if (length(skipped)) cat("\n[跳过] ", paste(skipped, collapse = "; "), "\n", sep = "")

cat("\n--- [B1] RR 桥接审计（Global 2022 @ CV=", CV_MAIN, "）：池化曲线如何落到 MIMS/day ---\n", sep = "")
print(BRIDGE)

cat("\n--- [B2] 暴露分布诊断 ---\n")
print(DIAG[, .(location, year, cv,
               mean_mims = round(mean_mims), sd_mims = round(sd_mims),
               pct_below_tmrel = round(pct_below_tmrel, 3),
               p_tmrel = round(p_tmrel, 3), off_tmrel = round(off_tmrel, 1),
               paf_pooled = round(implied_paf_pooled, 4),
               paf_nhanes = round(implied_paf_nhanes, 4))])

cat("\n--- [A] RR 来源对照（主情景 CV=", CV_MAIN, "，clamp=", !NOCLAMP, "）---\n", sep = "")
print(CMP[order(year, location, rr_source),
          .(location, year, rr_source,
            mean_met_wk = round(mean_met_wk),
            pct_below_tmrel = round(pct_below_tmrel, 3),
            PAF_recalc = round(paf_deaths, 4),
            deaths_recalc = round(recomputed_deaths),
            PAF_GBD = round(gbd_paf_deaths, 4),
            deaths_GBD = round(gbd_deaths),
            fold = round(recomputed_deaths / gbd_deaths, 2))])

if (CV_MODE == "grid") {
  cat("\n--- [C] CV 敏感性（RR=", SRC_MAIN, "，归因死亡总数）---\n", sep = "")
  print(dcast(CAUSE[rr_source == SRC_MAIN,
                    .(deaths = sum(deaths_attrib, na.rm = TRUE)),
                    by = .(location, year, cv)],
              location + year ~ cv, value.var = "deaths")[
    , lapply(.SD, function(x) if (is.numeric(x)) round(x) else x)])
} else {
  cat("\n--- [C] CV 来源 = S1'（cell 级查表 + 人口加权），无固定 CV 网格 ---\n")
  print(CAUSE[rr_source == SRC_MAIN,
              .(cv_met = round(cv[1], 3),
                deaths = round(sum(deaths_attrib, na.rm = TRUE))),
              by = .(location, year)][order(year, location)])
}

cat("\n--- [D] 分病因（RR=", SRC_MAIN, "，Global 2022，cv=",
    if (CV_MODE == "s1p") "S1'" else CV_MAIN, "）---\n", sep = "")
print(CAUSE[rr_source == SRC_MAIN & location == "Global" & year == 2022 & (is_main),
            .(cause, deaths = round(deaths_attrib),
              deaths_lo = round(deaths_lo), deaths_hi = round(deaths_hi))])

cat("\n================================================================\n")
cat("本表为 ", PREVIEW_TAG, "：RR 与分母均为真实数据。\n", sep = "")
if (CV_MODE == "s1p") {
  cat("  · 暴露分布 = **cell 级**（15 个 25+ 年龄组 × 2 性别）按人口占比加权合并；\n")
  cat("  · 每个 cell 的 CV 由 S1' 查表（NHANES 自估 SD–mean 关系，05 Part A5）；\n")
  cat("  · 人口权重来源 = ", POP_SRC, "；非均匀权重时暴露均值已做人口加权。\n", sep = "")
} else {
  cat("  · 敏感性双轨：暴露分布 CV 走 S3 网格，主情景 ", CV_MAIN, "（S1′ 为主分析）。\n", sep = "")
  cat("  · 本轨暴露均值仍用 25+ 各 5 岁组简单平均（未人口加权），仅作对照。\n")
}
cat("  · RR 来源 = Module 2 池化 device_pooled × total_PA（1000 条后验）\n")
cat("  · 桥接：目标人群百分位 → offset → 以 TMREL 重锚定 + ≥TMREL 封顶\n")
cat("产物：", OUT_PREFIX, "{totals,by_cause,exposure_diag,rr_source_compare,rr_bridge}.csv\n", sep = "")

}  # ← 结束 PA_M3_HELPERS_ONLY 的 else 分支（见 §5 开头的复用开关）
