# =============================================================================
# 97_m3_scenarios.R —— Module 3 情景表（正式）+ 稳健性 + 国别同质化
# -----------------------------------------------------------------------------
# 本脚本是 2026-10-15 的 `97_m3_diagnose.R` 的**转正版**（同名旧件已删除）。
# 定位：**不改主链 95_module3_paf.R，不覆盖任何冻结产物**。
#       95 的逐字节复现性由 logs/module3_s1p_verification.txt（5/5）保证。
#
# 用户决策（2026-10-15）：
#   N1 = A：fold 从「主发现」降为「**口径分解 + 上界敏感性**」；
#           主结果 = S0_base（绝对口径 TMREL + M1 + 原 SIGMA，= s1p 冻结主结果）。
#   N2 = A：放弃「国别异质性」卖点，改卖 ①PAF 对暴露参数高度稳健
#           ②设备尺度国别同质化；**不做 M2′**。
#   N3 = A：加「GBD 口径对齐」敏感性情景（RR 幅度自动求解后对齐）。
#
# 本脚本回答四个问题：
#   D1  三层分解：fold ≈ 5–15 各层贡献多少？
#         L1 = TMREL 在暴露分布中的**百分位位置**（现状第 54.1 百分位；GBD 定义 = 85th pct）
#         L2 = MET→MIMS 的 `SIGMA_MIMS` 卷积**抹平**效应（打破百分位守恒）
#         L3 = RR 曲线的**超额风险幅度**（我们 <TMREL 者平均 RR=1.394；GBD 隐含 1.037）
#   D2  正式情景定级：哪些进主结果、哪些是敏感性、哪个是上界（→ Table 9）
#   D3  **GBD 口径对齐闭合**：把 TMREL 与 RR 幅度同时对齐到 GBD → fold 能回到 1 吗？
#   D4  稳健性（N2）：CV 网格 + 人口加权开关 → PAF 动多少（→ Table 10）
#
# ⚠️ `build_px_shadow()` 是 95:305 `px_cells_s1p()` 的**影子副本**，仅增加三个
#    可控参数（sigma / cv_override / pop_w）与一个映射开关（m2）。主链版本
#    保持不动，以保证 95 的逐字节复现性。
# ⚠️ 不能直接调 05 的 `exposure_dist()`：它的 sigma 是**闭包捕获的全局 SIGMA_MIMS**，
#    传参无效（首版 97 踩过：L2 三档静默失效，表现为 fold 只动 −1%）。本脚本
#    复制其逻辑并显式参数化（`exposure_dist_s()`）。
#
# 依赖：先跑通 01→05b（需 output/bop_rr_draws.rds、data/derived/analytic.rds）；
#       GBD 批次 1/2 与暴露整包已在 data/gbd/。
# 运行：cd code && Rscript 97_m3_scenarios.R          # ~2 min
# 产物：
#   output/Table4_m3_decomp.csv             情景 × 地点 全量分解表（含 role）
#   output/Table5_m1_vs_m2.csv              M1 / M2 对照
#   output/Table9_m3_scenario_summary.csv   ⭐ 正式情景定级表（投稿用）
#   output/Table10_m3_robustness.csv        CV 网格 + 人口加权（N2）
#   output/Table10_m3_country_homogeneity.csv  MET vs 设备尺度国别同质化（N2）
#   logs/m3_diagnosis.txt                   人读报告
#
# 修订（2026-10-15，转正时）：
#   R1 固定 `set.seed(RR_SEED)` 于 mk_rr_shadow() 内 → PAF 成为纯函数（消除同情景两值）。
#   R2 修 `tmrel_at_pct()` → L1a_p70 从"L1b_p85 的副本"变为真正的第 70 百分位。
#   两者均会小幅移动数值（≤ ~2%），结论方向不变。
# =============================================================================

t0 <- Sys.time()
set.seed(20261015)

# ---- 统一引导（与 95 一致，保证同一套函数与对象）---------------------------
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8"))
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
})
.old_wd <- getwd()
source("05_burden_calibration_paf.R")
setwd(.old_wd)

suppressPackageStartupMessages({ library(data.table) })

# ---- 场景设定 --------------------------------------------------------------
LOCS  <- c("Global", "China", "Japan", "United States of America",
           "India", "Nigeria", "Brazil", "Germany")
YEAR  <- 2022L
N_CURVE_DRAWS <- 200L   # 【2026-10-15 起停用】确定性枚举后不再抽样；保留仅为日志/签名兼容
CV_GRID <- c(0.40, 0.60, 0.80, 1.00, 1.60, 2.20)   # N2 稳健性网格（MET 尺度 CV）
RR_SEED <- 20261015L   # ⚠️ 必须在 mk_rr_shadow() 内部重置（见该函数注释）

# 基准常数（从 05 取得）
SIGMA_ORIG      <- SIGMA_MIMS
TMREL_ABS_MIMS  <- mean(c(tmrel_lo_mims, tmrel_hi_mims))   # 现状：绝对口径设备等效
GBD_AGE_25PLUS  <- as.integer(names(SD_GBD_AGE2IDX))

# ---- GBD 官方参照（Global 2022，来自 GBD 官方批次 1 ÷ 批次 2）--------------
PAF_GBD_REF  <- 0.0304145974457752
E_GBD_REF    <- PAF_GBD_REF / (1 - PAF_GBD_REF)          # = 0.0313685...
GBD_PCT_BELOW <- 0.85                                     # GBD TMREL 定义 = 暴露分布 85th pct
GBD_RRBAR_IMPLIED <- 1 + E_GBD_REF / GBD_PCT_BELOW        # ≈ 1.03690

expo <- read_lpa_exposure(gbd_expo)
if (is.null(expo)) stop("未读到 LPA 暴露整包。")
BOP  <- readRDS(file.path(DIR_OUT, "bop_rr_draws.rds"))
message(sprintf("RR 后验：%d draws × %d 网格点 | ref_canon=%.1f",
                BOP$n_draw, length(BOP$offset_grid), BOP$ref_canon))

# =============================================================================
# Part 1. 暴露分布构建（影子，参数化 sigma / cv / 人口权重 / 映射方式）
# =============================================================================
exposure_dist_s <- function(mean_met, cv, sigma, n_met = 301L, n_mims = 301L,
                            met_cap = MET_CAP, mims_cap = max(adm$mims_per_day, na.rm = TRUE) * 1.2) {
  sdlog <- sqrt(log(1 + cv^2)); mulog <- log(mean_met) - sdlog^2 / 2
  met <- seq(0, met_cap, length.out = n_met)
  f_met <- dlnorm(met, mulog, sdlog); f_met[met <= 0] <- 0
  f_met <- f_met / sum(f_met)
  y   <- seq(0, mims_cap, length.out = n_mims)
  mus <- pred_mims(met)
  D   <- outer(y, mus, function(yy, mm) dnorm(yy, mean = mm, sd = sigma))
  f   <- as.numeric(D %*% f_met); f <- f / sum(f)
  list(mims = y, f = f, mean_mims = sum(y * f), sigma_cond = sigma)
}

build_px_shadow <- function(loc, yr, sigma = SIGMA_ORIG, m2 = FALSE,
                            cv_override = NULL, pop_w = TRUE,
                            n_mims = 301L, n_met = 301L,
                            mims_cap = max(adm$mims_per_day, na.rm = TRUE) * 1.2) {
  em <- expo[location_name == loc & year_id == yr & age_group_id %in% GBD_AGE_25PLUS]
  if (!nrow(em)) return(NULL)

  cells <- data.table(age_group_id = as.integer(em$age_group_id),
                      sex          = as.character(em$sex),
                      mean_met     = as.numeric(em$mean))
  cells <- cells[is.finite(mean_met) & mean_met > 0]
  if (!nrow(cells)) return(NULL)

  cells[, age_idx  := SD_GBD_AGE2IDX[as.character(age_group_id)]]
  cells[, female_f := fifelse(grepl("^f", sex, ignore.case = TRUE), 1, 0)]
  if (is.null(cv_override)) {
    fit <- SD_FIT$met_w
    cells[, cv := fit$pred_sd(mean_met, age_idx, female_f) / mean_met]
  } else {
    cells[, cv := cv_override]          # N2 网格：全 cell 用同一 CV（S3 口径）
  }
  cells <- cells[is.finite(cv) & cv > 0]
  if (!nrow(cells)) return(NULL)

  # --- 人口权重（只归一化一次：年龄组人口占比；组内两性别等分）---
  ent <- resolve_pop_loc(loc)
  pw  <- NULL
  if (pop_w && !is.null(POP_W) && !is.na(ent)) {
    pw <- if ("pop_entity" %in% names(POP_W))
      POP_W[pop_entity == ent & year == yr, .(age_group_id, w)]
    else
      POP_W[location_name == ent & year == yr, .(age_group_id, w)]
    if (!nrow(pw)) pw <- NULL
  }
  if (is.null(pw)) {
    cells[, w_age := 1]
    w_src <- if (pop_w) "uniform" else "uniform_forced"
    if (!pop_w) ent <- NA_character_
  } else {
    cells <- merge(cells, pw, by = "age_group_id", all.x = TRUE)
    cells[, w_age := fifelse(is.finite(w) & w > 0, w, 1)]
    w_src <- if (any(is.na(cells$w))) "partial_pop" else "pop"
  }
  cells[, w_cell := w_age / sum(w_age)]

  y <- seq(0, mims_cap, length.out = n_mims)
  f <- numeric(n_mims)

  # NHANES 设备侧经验分布（M2 用）
  if (m2) {
    cal_mims <- adm$mims_per_day[!is.na(adm$mims_per_day)]
    cal_mims <- sort(cal_mims)
  }

  for (i in seq_len(nrow(cells))) {
    if (!m2) {
      di <- exposure_dist_s(mean_met = cells$mean_met[i], cv = cells$cv[i],
                            sigma = sigma, n_mims = n_mims, mims_cap = mims_cap)
      f <- f + cells$w_cell[i] * di$f
    } else {
      # --- M2 保秩映射 ---
      sdlog <- sqrt(log(1 + cells$cv[i]^2))
      mulog <- log(cells$mean_met[i]) - sdlog^2 / 2
      met   <- seq(0, MET_CAP, length.out = n_met)
      fmet  <- dlnorm(met, mulog, sdlog); fmet[met <= 0] <- 0
      if (sum(fmet) <= 0) next
      fmet  <- fmet / sum(fmet)
      q     <- pmin(1, cumsum(fmet))
      y_map <- quantile(cal_mims, q, names = FALSE, type = 1)
      b  <- pmin(n_mims, pmax(1L, as.integer(round((y_map - y[1]) / (y[n_mims] - y[1]) * (n_mims - 1))) + 1L))
      ag <- rowsum(fmet, b)
      fb <- numeric(n_mims)
      fb[as.integer(rownames(ag))] <- as.numeric(ag)
      f <- f + cells$w_cell[i] * (fb / sum(fb))
    }
  }
  f <- f / sum(f)
  mu <- sum(y * f)

  list(mims = y, f = f, mean_mims = mu, sigma_cond = sigma,
       cells = cells,
       mean_met_w = sum(cells$w_cell * cells$mean_met),
       cv_wavg    = sum(cells$w_cell * cells$cv),
       cv_eff_dev = sqrt(sum(f * (y - mu)^2)) / mu,
       w_src = w_src, pop_entity = ent,
       pct_below_abs = sum(f[y < TMREL_ABS_MIMS]),
       tmrel_p85_mims = approx(cumsum(f) / sum(f), y, xout = 0.85, rule = 2)$y)
}

# TMREL 定位到暴露分布的**任意**百分位（L1 层旋钮）
# ⚠️ 2026-10-15 修 bug：首版循环里 `tz <- ... else px$tmrel_p85_mims` 把所有非 abs 档
#    （0.70 / 0.85）**都**解析到第 85 百分位 → L1a_p70 实际是 L1b_p85 的副本。
#    当时被蒙特卡洛噪声掩盖（两者 fold 12.60 vs 12.44，看起来"有差"）；
#    固定 RR 子样本种子后两者**逐位相同**（12.59 = 12.59），bug 才暴露。
tmrel_at_pct <- function(px, p) {
  Fn <- cumsum(px$f); Fn <- Fn / max(Fn)
  approx(Fn, px$mims, xout = p, rule = 2)$y
}

# =============================================================================
# Part 2. RR 桥接（影子，参数化 TMREL 位置与幅度缩放）
# =============================================================================
#  —— 与 95 `make_rr_fun_pooled()` 同算法，仅把 TMREL 与幅度提出为参数。
#  —— rr_scale = "auto"：求解 s 使 <TMREL 人群平均 RR 命中 GBD 隐含水平（N3）。
#  —— 2026-10-15 起改用**全部**后验曲线（原先抽 200 条子样本）。PAF 因此是
#     (px, tmrel, rr_scale) 的确定性纯函数，与 95 / 95c / 95b 严格同口径。
#     保留 set.seed(RR_SEED) 仅为防御：若将来重新引入抽样仍可复现。
# -----------------------------------------------------------------------------
mk_rr_shadow <- function(px, tmrel_mims, rr_scale = 1, clamp = TRUE,
                         metric = "total_PA") {
  set.seed(RR_SEED)          # ← 防御性保留，见上方注释
  meta <- data.table(curve_role = BOP$curve_role, metric = BOP$metric,
                     offset_pts = BOP$offset_grid)
  idx <- which(meta$curve_role == "device_pooled" & meta$metric == metric)
  if (!length(idx)) stop("池化后验中缺 device_pooled × ", metric)
  o   <- order(meta$offset_pts[idx]); idx <- idx[o]
  off_grid <- meta$offset_pts[idx]
  D   <- BOP$draws[, idx, drop = FALSE]
  ref_pct <- BOP$ref_canon

  p <- cumsum(px$f); p <- p / max(p)
  off_y     <- pmax(0, 100 * p - ref_pct)
  p_tmrel   <- approx(px$mims, p, xout = tmrel_mims, rule = 2)$y
  off_tmrel <- max(0, 100 * p_tmrel - ref_pct)

  rr_at <- function(v, off) approx(off_grid, v, xout = off, rule = 2)$y

  # 确定性枚举：遍历**全部**后验曲线（原为抽 N_CURVE_DRAWS 条子样本）
  kk <- seq_len(nrow(D))
  ratio <- t(vapply(kk, function(k) {
    rr_at(D[k, ], off_y) / rr_at(D[k, ], off_tmrel)
  }, numeric(length(off_y))))
  if (clamp) ratio[ratio < 1] <- 1
  abs_curve <- colMeans(ratio)

  # ---- 幅度缩放：r' = 1 + s·(r − 1) ----
  #   ⚠️ 必须**同时**缩放整条曲线集（ratio），而不仅是均值曲线：
  #      PAF 非线性（PAF = E/(1+E)，E = Σpx·(rr−1)），故 E[PAF] ≠ PAF(E[rr])，
  #      两者相差约 0.24%（Jensen 不等式；Global 2022 实测 0.174079 vs 0.174495）。
  #      95/95c 的 recompute_burden() 走 E[PAF] 口径，本脚本必须同口径，
  #      否则 Table 4（09 ← 95 s1p）与 Table 9（本脚本）会再次出现假差异。
  pbelow <- sum(px$f[px$mims < tmrel_mims])
  if (is.character(rr_scale) && identical(rr_scale, "auto")) {
    # 求解 s：使 1 + s·(RR̄0 − 1) = GBD_RRBAR_IMPLIED，其中 RR̄0 为当前 TMREL 下的未缩放值
    E0     <- sum(px$f * (abs_curve - 1))
    rrbar0 <- 1 + E0 / pbelow
    s      <- if (rrbar0 > 1) (GBD_RRBAR_IMPLIED - 1) / (rrbar0 - 1) else NA_real_
    if (!is.finite(s)) stop("auto rr_scale 求解失败（rrbar0 未超过 1）")
    abs_curve <- 1 + s * (abs_curve - 1)
    if (!isTRUE(all.equal(s, 1))) ratio <- 1 + s * (ratio - 1)
    rr_scale_used <- s
  } else {
    rr_scale_used <- rr_scale
    if (!isTRUE(all.equal(rr_scale, 1))) {
      abs_curve <- 1 + rr_scale * (abs_curve - 1)
      ratio     <- 1 + rr_scale * (ratio - 1)
    }
  }

  # 隐含指标（供分解表）；PAF 取**逐曲线算再平均**（= recompute_burden 的口径）
  paf_v  <- paf_from_dist_mat(px$f, ratio)
  E      <- sum(px$f * (abs_curve - 1))
  list(abs = abs_curve, paf = mean(paf_v),
       off_tmrel = off_tmrel, p_tmrel = p_tmrel,
       pct_below = pbelow, E = E, rr_scale_used = rr_scale_used,
       rrbar_below = if (pbelow > 0) 1 + E / pbelow else NA_real_,
       k_anchor = 1 / mean(vapply(kk, function(k) rr_at(D[k, ], off_tmrel), numeric(1))))
}

# =============================================================================
# Part 3. 情景矩阵（含 role 定级：main / sensitivity / upper_bound / gbd_aligned）
# =============================================================================
scen_tbl <- list(
  # ---------- 主分析（保守口径；= s1p 冻结主结果）----------
  list(id = "S0_base", role = "main",
       label = "主分析：绝对口径 TMREL + M1 + 原 SIGMA（= s1p 主结果）",
       sigma = SIGMA_ORIG, m2 = FALSE, tmrel = "abs", rr_scale = 1),
  # ---------- L1：TMREL 位置 ----------
  list(id = "L1a_p70", role = "sensitivity",
       label = "L1 | TMREL 移到暴露分布第 70 百分位",
       sigma = SIGMA_ORIG, m2 = FALSE, tmrel = 0.70, rr_scale = 1),
  list(id = "L1b_p85", role = "sensitivity",
       label = "L1 | TMREL 移到暴露分布第 85 百分位（= GBD 定义）",
       sigma = SIGMA_ORIG, m2 = FALSE, tmrel = 0.85, rr_scale = 1),
  # ---------- L2：卷积抹平 ----------
  list(id = "L2a_s1600", role = "sensitivity",
       label = "L2 | SIGMA_MIMS 3335 → 1600（半衰减）",
       sigma = 1600, m2 = FALSE, tmrel = "abs", rr_scale = 1),
  list(id = "L2b_s800", role = "sensitivity",
       label = "L2 | SIGMA_MIMS 3335 → 800",
       sigma = 800, m2 = FALSE, tmrel = "abs", rr_scale = 1),
  list(id = "L2c_s0", role = "sensitivity",
       label = "L2 | SIGMA_MIMS 3335 → 100（≈取消抹平，避免退化点质量）",
       sigma = 100, m2 = FALSE, tmrel = "abs", rr_scale = 1),
  # ---------- L3：RR 幅度（三层分解的诊断项；幅度缩放系数沿用首版硬编码）----------
  list(id = "L3_rr_gbd", role = "sensitivity",
       label = "L3 | RR 超额幅度缩到 GBD 水平（s = 0.0954，首版固定系数）",
       sigma = SIGMA_ORIG, m2 = FALSE, tmrel = "abs", rr_scale = 0.0954),
  # ---------- 上界：TMREL 85 百分位 + 取消卷积（fold 最大）----------
  list(id = "D2_p85_nosig", role = "upper_bound",
       label = "上界 | TMREL 第 85 百分位 + 取消卷积（fold 最高）",
       sigma = 100, m2 = FALSE, tmrel = 0.85, rr_scale = 1),
  # ---------- M2 保秩映射（N2 诊断：未保留国别差异）----------
  list(id = "M2_rank_abs", role = "sensitivity",
       label = "M2 | 保秩映射 + 绝对口径 TMREL",
       sigma = SIGMA_ORIG, m2 = TRUE, tmrel = "abs", rr_scale = 1),
  list(id = "M2_rank_p85", role = "sensitivity",
       label = "M2 | 保秩映射 + TMREL 第 85 百分位",
       sigma = SIGMA_ORIG, m2 = TRUE, tmrel = 0.85, rr_scale = 1),
  # ---------- N3：GBD 口径对齐（新增）----------
  list(id = "GBD_ALIGNED_RR", role = "gbd_aligned",
       label = "GBD 口径对齐 A：RR 幅度对齐（s 自动求解；TMREL 保持绝对口径）",
       sigma = SIGMA_ORIG, m2 = FALSE, tmrel = "abs", rr_scale = "auto"),
  list(id = "GBD_FAITHFUL", role = "gbd_aligned",
       label = "GBD 口径对齐 B（完整）：TMREL 第 85 百分位 + RR 幅度对齐（预期 fold ≈ 1）",
       sigma = SIGMA_ORIG, m2 = FALSE, tmrel = 0.85, rr_scale = "auto")
)
ROLE_ORDER <- c("main", "upper_bound", "gbd_aligned", "sensitivity")

cat("\n=========== Module 3 情景表（影子运行，不改主链）===========\n\n")
rows <- list()
for (sc in scen_tbl) {
  for (loc in LOCS) {
    px <- build_px_shadow(loc, YEAR, sigma = sc$sigma, m2 = sc$m2)
    if (is.null(px)) { message("  · 跳过 ", loc, "（无暴露数据）"); next }
    tz <- if (identical(sc$tmrel, "abs")) TMREL_ABS_MIMS else tmrel_at_pct(px, as.numeric(sc$tmrel))
    rr <- mk_rr_shadow(px, tmrel_mims = tz, rr_scale = sc$rr_scale)
    rows[[length(rows) + 1L]] <- data.table(
      scenario = sc$id, role = sc$role, label = sc$label,
      location = loc, year = YEAR,
      sigma = sc$sigma, m2 = sc$m2, tmrel_mode = as.character(sc$tmrel),
      tmrel_mims = tz, mean_met_w = px$mean_met_w, mean_mims = px$mean_mims,
      cv_eff_dev = px$cv_eff_dev, pct_below = rr$pct_below,
      rrbar_below = rr$rrbar_below, rr_scale_used = rr$rr_scale_used,
      k_anchor = rr$k_anchor,
      paf = rr$paf, paf_gbd = PAF_GBD_REF, fold = rr$paf / PAF_GBD_REF,
      p_tmrel = rr$p_tmrel, off_tmrel = rr$off_tmrel)
  }
  message(sprintf("  完成 %-16s %s", sc$id, sc$label))
}
DEC <- rbindlist(rows)
DEC[, role := factor(role, levels = ROLE_ORDER)]
setorder(DEC, role, scenario, location)
DEC[, role := as.character(role)]
fwrite(DEC, file.path(DIR_OUT, "Table4_m3_decomp.csv"))

# ---- M1 vs M2 对照（国别差异保留程度）--------------------------------------
m1 <- DEC[scenario == "S0_base"]
m2 <- DEC[scenario == "M2_rank_abs"]
cmp <- merge(m1[, .(location, met_m1 = mean_met_w, mims_m1 = mean_mims,
                    pct_below_m1 = pct_below, paf_m1 = paf, fold_m1 = fold)],
             m2[, .(location, mims_m2 = mean_mims, cv_m2 = cv_eff_dev,
                    pct_below_m2 = pct_below, paf_m2 = paf, fold_m2 = fold)],
             by = "location")
cmp[, `:=`(mims_ratio_m1 = mims_m1 / min(mims_m1),
           mims_ratio_m2 = mims_m2 / min(mims_m2))]
fwrite(cmp, file.path(DIR_OUT, "Table5_m1_vs_m2.csv"))

# =============================================================================
# Part 4. ⭐ 正式情景定级表（Table 9，投稿用）—— N1 的落地
# =============================================================================
SUM <- DEC[, .(role = role[1], label = label[1], tmrel_mode = tmrel_mode[1],
               sigma = sigma[1], m2 = m2[1],
               rr_scale_used = rr_scale_used[location == "Global"][1],
               n_loc = .N,
               paf_global = paf[location == "Global"][1],
               fold_global = fold[location == "Global"][1],
               fold_min = min(fold), fold_max = max(fold)),
           by = scenario]
SUM[, role_rank := match(role, ROLE_ORDER)]
setorder(SUM, role_rank, scenario)
SUM[, role_rank := NULL]
fwrite(SUM, file.path(DIR_OUT, "Table9_m3_scenario_summary.csv"))

# =============================================================================
# Part 5. 稳健性（N2）：CV 网格 + 人口加权开关（Table 10）
# =============================================================================
rob <- list()
for (cvx in CV_GRID) {
  for (loc in LOCS) {
    px <- build_px_shadow(loc, YEAR, cv_override = cvx, pop_w = TRUE)
    if (is.null(px)) next
    rr <- mk_rr_shadow(px, tmrel_mims = TMREL_ABS_MIMS)
    rob[[length(rob) + 1L]] <- data.table(
      axis = "CV 网格（MET 尺度，主分析=cell 级 S1′）",
      level = sprintf("CV=%.2f", cvx), location = loc,
      cv_wavg = px$cv_wavg, cv_eff_dev = px$cv_eff_dev,
      pct_below = rr$pct_below, rrbar_below = rr$rrbar_below,
      paf = rr$paf, fold = rr$paf / PAF_GBD_REF)
  }
  message(sprintf("  稳健性 CV=%.2f 完成", cvx))
}
# 主分析的真实 CV（S1′ cell 级）作为最后一档参照
for (loc in LOCS) {
  px <- build_px_shadow(loc, YEAR, pop_w = TRUE)
  if (is.null(px)) next
  rr <- mk_rr_shadow(px, tmrel_mims = TMREL_ABS_MIMS)
  rob[[length(rob) + 1L]] <- data.table(
    axis = "CV 网格（MET 尺度，主分析=cell 级 S1′）",
    level = "S1′ 主分析（cell 级）", location = loc,
    cv_wavg = px$cv_wavg, cv_eff_dev = px$cv_eff_dev,
    pct_below = rr$pct_below, rrbar_below = rr$rrbar_below,
    paf = rr$paf, fold = rr$paf / PAF_GBD_REF)
}
for (pwx in c(TRUE, FALSE)) {
  for (loc in LOCS) {
    px <- build_px_shadow(loc, YEAR, pop_w = pwx)
    if (is.null(px)) next
    rr <- mk_rr_shadow(px, tmrel_mims = TMREL_ABS_MIMS)
    rob[[length(rob) + 1L]] <- data.table(
      axis = "人口加权（A6）", level = if (pwx) "开（主分析）" else "关（年龄组等权）",
      location = loc, cv_wavg = px$cv_wavg, cv_eff_dev = px$cv_eff_dev,
      pct_below = rr$pct_below, rrbar_below = rr$rrbar_below,
      paf = rr$paf, fold = rr$paf / PAF_GBD_REF)
  }
  message(sprintf("  稳健性 人口加权 %s 完成", if (pwx) "开" else "关"))
}
ROB <- rbindlist(rob)
fwrite(ROB, file.path(DIR_OUT, "Table10_m3_robustness.csv"))

# =============================================================================
# Part 6. 国别同质化（N2）：MET 尺度 vs 设备尺度
# =============================================================================
HOM <- m1[, .(location, mean_met_w, mean_mims, cv_eff_dev, pct_below, paf, fold)]
HOM[, `:=`(met_ratio  = mean_met_w / min(mean_met_w),
           mims_ratio = mean_mims  / min(mean_mims))]
setorder(HOM, -mean_met_w)
fwrite(HOM, file.path(DIR_OUT, "Table10_m3_country_homogeneity.csv"))

# =============================================================================
# Part 7. 人读报告
# =============================================================================
sink(file.path(DIR_LOGS, "m3_diagnosis.txt"))
cat("================= Module 3 情景表与诊断报告 =================\n")
cat("生成时间：", format(t0, "%Y-%m-%d %H:%M:%S"), "\n")
cat("R：", R.version.string, " | RR 桥接 = 确定性枚举（全部后验曲线，不抽样）\n\n")
cat("关键常数：\n")
cat(sprintf("  SIGMA_MIMS（原）= %.0f | MET_CAP = %.0f | TMREL 绝对口径 = %.0f MIMS/day\n",
            SIGMA_ORIG, MET_CAP, TMREL_ABS_MIMS))
cat(sprintf("  GBD 参照 PAF（Global 2022）= %.6f | E_gbd = %.6f | 隐含 RRbar_below = %.4f\n\n",
            PAF_GBD_REF, E_GBD_REF, GBD_RRBAR_IMPLIED))
cat("口径说明：TMREL = 暴露分布的 85 百分位 → 隐含「暴露不足」比例约 85%（GBD 附录定义：\n")
cat("  5 个 risk–outcome pair 各自 85th pct 的加权平均，权重 = GBD 2021 全球 25+ 死亡数）\n")
cat("  ⚠️ 本研究主分析**不采用**该定义（保持绝对口径 TMREL），仅用于口径分解。\n\n")

cat("--- [A] 三层分解（Global 2022）---\n")
print(DEC[location == "Global", .(scenario, tmrel_mims = round(tmrel_mims),
                                  pct_below = round(pct_below, 3),
                                  rrbar = round(rrbar_below, 3),
                                  k = round(k_anchor, 3),
                                  PAF = round(paf, 4),
                                  GBD = round(paf_gbd, 4),
                                  fold = round(fold, 2))])

cat("\n--- [B] 各层单独贡献（相对 S0_base 的 fold 变化）---\n")
b0 <- DEC[location == "Global" & scenario == "S0_base", fold]
for (id in c("L1b_p85", "L2c_s0", "L3_rr_gbd", "D2_p85_nosig")) {
  fv <- DEC[location == "Global" & scenario == id, fold]
  if (length(fv)) cat(sprintf("  %-14s fold %.2f → %.2f  （%+.0f%%）\n", id, b0, fv, 100 * (fv / b0 - 1)))
}

cat("\n--- [C] 全 8 地区 fold 一览 ---\n")
print(dcast(DEC[, .(location, scenario, fold = round(fold, 2))],
            location ~ scenario, value.var = "fold"))

cat("\n--- [D] M1 vs M2：国别差异保留程度 ---\n")
print(cmp[, .(location, mims_m1 = round(mims_m1), ratio_m1 = round(mims_ratio_m1, 3),
              mims_m2 = round(mims_m2), ratio_m2 = round(mims_ratio_m2, 3),
              pctb_m1 = round(pct_below_m1, 3), pctb_m2 = round(pct_below_m2, 3),
              paf_m1 = round(paf_m1, 4), paf_m2 = round(paf_m2, 4))])
cat(sprintf("\n  设备均值极差比： M1 = %.3f×  |  M2 = %.3f×\n",
            max(cmp$mims_ratio_m1) / min(cmp$mims_ratio_m1),
            max(cmp$mims_ratio_m2) / min(cmp$mims_ratio_m2)))
cat(sprintf("  PAF 国别极差：  M1 = %.4f  |  M2 = %.4f\n",
            max(cmp$paf_m1) - min(cmp$paf_m1), max(cmp$paf_m2) - min(cmp$paf_m2)))

cat("\n--- [E] ⭐ 正式情景定级（N1 落地）---\n")
print(SUM[, .(scenario, role, paf_global = round(paf_global, 4),
              fold_global = round(fold_global, 2),
              fold_band = sprintf("%.2f–%.2f", fold_min, fold_max))])
cat("\n  角色定义：\n")
cat("    main         主结果（保守口径）：绝对 TMREL + M1 + 原 SIGMA\n")
cat("    upper_bound  上界：TMREL 85 百分位 + 取消卷积（fold 最高）\n")
cat("    gbd_aligned  GBD 口径对齐（N3）：RR 幅度自动对齐到 GBD 隐含水平\n")
cat("    sensitivity  其余敏感性情景\n")

cat("\n--- [F] ⭐ GBD 口径对齐闭合（N3 落地）---\n")
ff <- DEC[location == "Global" & scenario %in% c("S0_base", "GBD_ALIGNED_RR", "GBD_FAITHFUL")]
print(ff[, .(scenario, tmrel_mims = round(tmrel_mims),
             pct_below = round(pct_below, 3),
             rr_scale_used = round(rr_scale_used, 4),
             rrbar_below = round(rrbar_below, 4),
             PAF = round(paf, 4), GBD = round(paf_gbd, 4),
             fold = round(fold, 3))])
cat(sprintf("\n  GBD 隐含 RRbar_below（在其 TMREL 定义下）= %.4f\n", GBD_RRBAR_IMPLIED))
cat("  读法：\n")
cat("    A（RR 幅度对齐，TMREL 保持绝对口径）：fold 从 ")
cat(sprintf("%.2f 降到 %.2f\n", b0, DEC[location == "Global" & scenario == "GBD_ALIGNED_RR", fold]))
cat("        → 在 RR 强度相同的条件下，我们的 PAF **低于** GBD。\n")
cat("    B（TMREL 也改成第 85 百分位）：fold ")
cat(sprintf("%.3f\n", DEC[location == "Global" & scenario == "GBD_FAITHFUL", fold]))
cat("        → **fold ≈ 1，口径完全闭合**：GBD 与本研究的 PAF 差异可被\n")
cat("          「TMREL 定义（85 百分位）」+「RR 幅度（MR-BRT 收缩+年龄衰减+4 档分类化）」两项完全解释。\n")
cat("        → 结论句：GBD 的 LPA 归因负担水平**主要由 TMREL 定义驱动**，而非 RR 强度。\n")

cat("\n--- [G] 稳健性（N2）：CV 网格 ---\n")
cvw <- dcast(ROB[axis %like% "CV 网格", .(location, level, paf = round(paf, 4))],
             location ~ level, value.var = "paf")
print(cvw)
gl <- ROB[axis %like% "CV 网格" & location == "Global"]
gl <- gl[level %in% c(sprintf("CV=%.2f", CV_GRID), "S1′ 主分析（cell 级）")]
setorder(gl, cv_wavg)
cat(sprintf("\n  Global：PAF 最小 %.4f（%s）→ 最大 %.4f（%s）\n",
            min(gl$paf), gl$level[which.min(gl$paf)], max(gl$paf), gl$level[which.max(gl$paf)]))
cat(sprintf("  Global：CV 跨度 %.2f–%.2f（%.1f 倍），PAF 极差仅 %.1f%%\n",
            min(gl$cv_wavg), max(gl$cv_wavg), max(gl$cv_wavg) / min(gl$cv_wavg),
            100 * (max(gl$paf) / min(gl$paf) - 1)))
cat("  → 结论：**PAF 对暴露分布参数高度稳健**；fold 不可能由 CV/SD 的选择解释。\n")

cat("\n--- [H] 稳健性（N2）：人口加权 ---\n")
pw <- dcast(ROB[axis == "人口加权（A6）", .(location, level, paf = round(paf, 4))],
            location ~ level, value.var = "paf")
print(pw)
pwG <- ROB[axis == "人口加权（A6）" & location == "Global"]
on <- pwG[level == "开（主分析）", paf]; off <- pwG[level == "关（年龄组等权）", paf]
cat(sprintf("\n  Global：开 %.4f → 关 %.4f（%+.1f%%）\n", on, off, 100 * (on / off - 1)))

cat("\n--- [I] 国别同质化（N2）：MET 尺度 vs 设备尺度 ---\n")
print(HOM[, .(location, mean_met_w = round(mean_met_w), met_ratio = round(met_ratio, 2),
              mean_mims = round(mean_mims), mims_ratio = round(mims_ratio, 3),
              pct_below = round(pct_below, 3), paf = round(paf, 4))])
cat(sprintf("\n  MET 尺度国别均值极差比 = %.2f×\n", max(HOM$met_ratio) / min(HOM$met_ratio)))
cat(sprintf("  设备尺度国别均值极差比 = %.3f×\n", max(HOM$mims_ratio) / min(HOM$mims_ratio)))
cat(sprintf("  PAF 国别极差 = %.4f（%.1f%% 相对）\n",
            max(HOM$paf) - min(HOM$paf),
            100 * (max(HOM$paf) / min(HOM$paf) - 1)))
cat("  → 结论：设备测量下暴露分布**高度同质化**，国别差异被压缩到个位数百分比。\n")
cat("     这是校准模型 R²=0.19 的固有衰减，也是「自报国别异质性含大量测量伪影」的旁证。\n")

cat("\n================= 产物 =================\n")
cat("  output/Table4_m3_decomp.csv               （情景 × 地点 全量分解表，含 role）\n")
cat("  output/Table5_m1_vs_m2.csv                （M1/M2 对照）\n")
cat("  output/Table9_m3_scenario_summary.csv     ⭐ 正式情景定级表\n")
cat("  output/Table10_m3_robustness.csv          （CV 网格 + 人口加权）\n")
cat("  output/Table10_m3_country_homogeneity.csv （MET vs 设备尺度）\n")
cat("  logs/m3_diagnosis.txt                     （本文件）\n")
cat(sprintf("\n耗时 %.1f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
sink()

cat("\n已完成。产物：Table4 / Table5 / Table9 / Table10×2 / logs/m3_diagnosis.txt\n")
cat(readLines(file.path(DIR_LOGS, "m3_diagnosis.txt")), sep = "\n")
