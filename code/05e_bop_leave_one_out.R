# =============================================================================
# 05e_bop_leave_one_out.R
# Module 2 池化队列的**留一法**（leave-one-study-out）与它对 Module 3 归因负担的影响
# -----------------------------------------------------------------------------
# 为什么必须做
#   `data/bop/rr_table.csv` 的主分析（population == "general"）只有 **21 行 / 5 篇研究**：
#     Ekelund2019 (device, hip,  9 行, total_PA/LPA/MVPA)
#     Tarp2024    (device, mixed, 2 行, total_PA)
#     Moore2012   (self,         5 行, MVPA)
#     PURE2017    (self,         2 行, total_PA)
#     Sun2025     (device, wrist, 3 行, LPA)
#   而 Module 3 消费的是 `curve_role == "device_pooled" & metric == "total_PA"`
#   —— 按 `pooled_w()` 的构造，它 = device_hip|total_PA + device_mixed|total_PA
#      → **只有 Ekelund2019 与 Tarp2024 两篇研究**在支撑整条设备总量曲线。
#   ⇒ 剔除任一篇都会让该曲线只剩一篇研究。这是本方案最大的外部效度风险，
#     必须用留一法把「不确定性有多大」明确量化并写进敏感性分析（Fig 6 面板）。
#
# 做法
#   对每篇研究 s：用 21 行中 study != s 的子集**重拟合** rmeta 多水平随机效应
#   （与 05a 的 `fit_pool()` 完全同算法）→ 重建 device_pooled 曲线 → 重算 PAF
#   与归因负担。基准（不剔除）用**完全相同的代码路径**在同脚本内计算，
#   以保证 LOO 与基准之间是可比的（不使用 95 的 RNG 流）。
#
# 零侵入保证
#   本脚本 `source()` 05 与 05a 以复用其函数与对象（与 97 的既有做法一致）。
#   05a 会重写它自己的产物 —— 这些产物是**确定性**的（内部 set.seed(PA_SEED)），
#   运行前后做 md5 校验（logs/_md5_before_05e.txt / _after），若不一致则硬失败。
#
# 产物
#   output/Table12_bop_loo_RR.csv     每情景：保留的研究/臂、斜率、offset60 处 RR、SE
#   output/Table12_m3_loo_paf.csv     每情景 × 地区年：PAF、归因死亡、fold
#   logs/bop_loo.txt                  人读报告
# =============================================================================

t0 <- Sys.time()
set.seed(20261015)

# ---- 统一引导（与 95/97 一致，保证同一套函数与对象）-------------------------
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8"))
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
})
.old_wd <- getwd()
source("05_burden_calibration_paf.R")     # 校准 / S1′ / 人口权重 / paf_from_dist / GBD 读入
source("05a_module2_bop.R")               # 池化拟合：fp / dt_main / fit_pool / pooled_w / 常量
setwd(.old_wd)

suppressPackageStartupMessages({ library(data.table); library(MASS); library(metafor) })
pa_log("===== 05e Module 2 留一法（leave-one-study-out）=====")

# ---- 从 95_module3_paf.R 借用的 5 个对象（逐字复制定义，使本脚本自包含）------
#   这 4 行在 95 里定义（201/202/284/288 行），05 与 05a 都不提供：
#     b2  = 批次 2「Cause 总负担」= PAF 分母
#     b1  = 批次 1「LPA 归因负担」= GBD 现报值（用于 fold 对比）
#     expo= LPA 暴露包（各 location × 年份 × 年龄 × 性别的 mean MET）
#     GBD_AGE_25PLUS = 25+ 的 15 个 GBD age_group_id
#   第 5 行 TMREL_MID_MIMS 同样只在 95 定义（101 行），但 make_rr_fun_pooled()
#   的影子副本要消费它。
b2 <- read_gbd_shards(find_gbd_role("cause_totals"), "cause_totals")
b1 <- read_gbd_shards(find_gbd_role("lpa_attributable"), "attributable")
if (is.null(b2)) stop("未识别到批次 2（Cause 总负担）文件，PAF 分母缺失。")
if (is.null(b1)) warning("未识别到批次 1（LPA 归因负担）文件，无法做『GBD 现报 vs 重算』对比。")
expo <- read_lpa_exposure(gbd_expo)
if (is.null(expo)) stop("未读到 LPA 暴露包。")
GBD_AGE_25PLUS <- as.integer(names(SD_GBD_AGE2IDX))
TMREL_MID_MIMS <- mean(c(tmrel_lo_mims, tmrel_hi_mims))
message(sprintf("TMREL 设备等效（取中）：%.0f MIMS/day（区间 %.0f–%.0f）",
                TMREL_MID_MIMS, tmrel_lo_mims, tmrel_hi_mims))

LOO_LOCS  <- c("Global", "China", "United States of America", "Nigeria")
LOO_YEARS <- c(2022)
LOO_SEED  <- as.integer(Sys.getenv("PA_LOO_SEED", unset = "20261015"))

# ---------------------------------------------------------------------------
# 1. 基准情景（与 LOO 完全同代码路径）
# ---------------------------------------------------------------------------
# 复刻 05a 的 device_pooled 曲线构造（05a:338-350 + 409-417），
# 但把结果包成 `make_rr_fun_pooled()` 能吃的 BOP 形状（仅 device_pooled × total_PA）。
build_dp_bop <- function(fps, metric = "total_PA", seed = LOO_SEED, tag = "") {
  W <- pooled_w(fps, metric)
  if (is.null(W) || !length(W)) return(NULL)
  nms <- names(W); w <- unlist(W)
  X <- matrix(0, nrow = length(OFFSET_GRID), ncol = length(fps$b),
              dimnames = list(NULL, names(fps$b)))
  for (i in seq_along(nms)) X[, nms[i]] <- w[i] * OFFSET_GRID
  Vs <- (fps$V + t(fps$V)) / 2
  set.seed(seed)
  dr <- tryCatch(MASS::mvrnorm(N_DRAW, mu = fps$b, Sigma = Vs),
                 error = function(e)
                   MASS::mvrnorm(N_DRAW, mu = fps$b, Sigma = diag(pmax(diag(Vs), 0))))
  rr <- exp(dr %*% t(X))
  n  <- length(OFFSET_GRID)
  list(offset_grid = as.numeric(OFFSET_GRID), pct_grid = as.numeric(OFFSET_GRID) + REF_CANON,
       ref_canon = REF_CANON,
       arm = rep("device_pooled", n), method = rep("device", n),
       wear_site = rep("pooled", n), curve_role = rep("device_pooled", n),
       metric = rep(metric, n), mm = rep("device_pooled", n),
       draws = rr, seed = seed, n_draw = N_DRAW, fit_mode = fps$fit_mode,
       note = paste0("05e 影子构造：device_pooled × ", metric,
                     "（逆方差合并 device 臂）；tag=", tag,
                     "；臂=", paste(nms, collapse = "+")))
}

# —— 95 的两个函数影子副本（逐字复制，仅便于本脚本自包含；主链版本不动）——
pop_mean_met <- function(loc, yr) {
  em <- expo[location_name == loc & year_id == yr]
  if (!nrow(em)) return(NA_real_)
  if ("sex" %in% names(em)) {
    eb <- em[sex %in% c("Both", "both")]
    if (nrow(eb)) em <- eb else em <- em[sex %in% c("Male", "Female")]
  }
  mean(em$mean, na.rm = TRUE)
}

px_cells_s1p <- function(loc, yr, fit = SD_FIT$met_w, n_mims = 301,
                         mims_cap = max(adm$mims_per_day, na.rm = TRUE) * 1.2) {
  em <- expo[location_name == loc & year_id == yr & age_group_id %in% GBD_AGE_25PLUS]
  if (!nrow(em)) return(NULL)
  cells <- data.table(age_group_id = as.integer(em$age_group_id),
                      sex = as.character(em$sex), mean_met = as.numeric(em$mean))
  cells <- cells[is.finite(mean_met) & mean_met > 0]
  if (!nrow(cells)) return(NULL)
  cells[, age_idx := SD_GBD_AGE2IDX[as.character(age_group_id)]]
  cells[, female_f := fifelse(grepl("^f", sex, ignore.case = TRUE), 1, 0)]
  cells[, cv := fit$pred_sd(mean_met, age_idx, female_f) / mean_met]
  cells <- cells[is.finite(cv) & cv > 0]
  if (!nrow(cells)) return(NULL)
  ent <- resolve_pop_loc(loc); pw <- NULL
  if (!is.null(POP_W) && !is.na(ent)) {
    pw <- if ("pop_entity" %in% names(POP_W))
      POP_W[pop_entity == ent & year == yr, .(age_group_id, w)]
    else POP_W[location_name == ent & year == yr, .(age_group_id, w)]
    if (!nrow(pw)) pw <- NULL
  }
  if (is.null(pw)) { cells[, w_age := 1]; w_src <- "uniform"; ent <- NA_character_
  } else {
    cells <- merge(cells, pw, by = "age_group_id", all.x = TRUE)
    cells[, w_age := fifelse(is.finite(w) & w > 0, w, 1)]
    w_src <- if (any(is.na(cells$w))) "partial_pop" else "pop"
  }
  cells[, w_cell := w_age / sum(w_age)]
  y <- seq(0, mims_cap, length.out = n_mims); f <- numeric(n_mims)
  for (i in seq_len(nrow(cells))) {
    di <- exposure_dist(mean_met = cells$mean_met[i], cv = cells$cv[i],
                        n_mims = n_mims, mims_cap = mims_cap)
    f <- f + cells$w_cell[i] * di$f
  }
  f <- f / sum(f); mu <- sum(y * f)
  list(mims = y, f = f, mean_mims = mu, sigma_cond = SIGMA_MIMS, cells = cells,
       mean_met_w = sum(cells$w_cell * cells$mean_met),
       cv_wavg = sum(cells$w_cell * cells$cv),
       cv_eff_dev = sqrt(sum(f * (y - mu)^2)) / mu,
       w_src = w_src, pop_entity = ent)
}

make_rr_fun_pooled <- function(BOP, px, metric = "total_PA", clamp = TRUE,
                               n_curve_draws = 200L, compute_curve = TRUE) {
  meta <- data.table(curve_role = BOP$curve_role, metric = BOP$metric,
                     offset_pts = BOP$offset_grid)
  idx <- which(meta$curve_role == "device_pooled" & meta$metric == metric)
  if (!length(idx)) stop("池化后验中缺 device_pooled × ", metric)
  o <- order(meta$offset_pts[idx]); idx <- idx[o]; off_grid <- meta$offset_pts[idx]
  D <- BOP$draws[, idx, drop = FALSE]; ref_pct <- BOP$ref_canon
  p <- cumsum(px$f); p <- p / max(p)
  off_y <- pmax(0, 100 * p - ref_pct)
  p_tmrel <- approx(px$mims, p, xout = TMREL_MID_MIMS, rule = 2)$y
  off_tmrel <- max(0, 100 * p_tmrel - ref_pct)
  rr_at <- function(v, off) approx(off_grid, v, xout = off, rule = 2)$y
  fun <- function() {
    v <- D[sample.int(nrow(D), 1L), ]
    r <- rr_at(v, off_y) / rr_at(v, off_tmrel)
    if (clamp) r[r < 1] <- 1
    r
  }
  mean_curve <- NULL
  if (compute_curve) {
    kk <- if (nrow(D) > n_curve_draws) sample.int(nrow(D), n_curve_draws) else seq_len(nrow(D))
    ratio <- t(vapply(kk, function(k) rr_at(D[k, ], off_y) / rr_at(D[k, ], off_tmrel),
                      numeric(length(off_y))))
    if (clamp) ratio[ratio < 1] <- 1
    mean_curve <- list(abs = colMeans(ratio))
  }
  list(fun = fun, mean_curve = mean_curve,
       info = list(off_tmrel = off_tmrel, p_tmrel = p_tmrel))
}

# 分母 / 归因值宽表（影子副本，与 95 的 build_wide 同实现）
short_meas <- function(x) fifelse(grepl("DALY", x, ignore.case = TRUE), "dalys", "deaths")
build_wide <- function(d, loc, yr, suffix) {
  dd <- d[location_name == loc & year == yr]
  if (!nrow(dd)) return(NULL)
  dd <- dd[, .(cause_name, meas = short_meas(measure_name), val)]
  dd <- dd[, .(val = sum(val, na.rm = TRUE)), by = .(cause_name, meas)]
  w <- dcast(dd, cause_name ~ meas, value.var = "val")
  setnames(w, c("deaths", "dalys"),
           c(paste0("deaths_", suffix), paste0("dalys_", suffix)), skip_absent = TRUE)
  w
}

# ---------------------------------------------------------------------------
# 2. LOO 拟合
# ---------------------------------------------------------------------------
studies <- sort(unique(as.character(dt_main$study)))
cat("\n主分析（general）研究数：", length(studies), " | 行数：", nrow(dt_main), "\n")
cat("研究：", paste(studies, collapse = ", "), "\n\n")

arms_of <- function(d) {
  tb <- d[, .N, by = .(arm = as.character(arm), metric_definition = as.character(metric_definition))]
  paste(sprintf("%s|%s(n=%d)", tb$arm, tb$metric_definition, tb$N), collapse = "; ")
}

scen <- list()
# ⚠️ note 必须显式给出（哪怕是 ""）：data.table(note = NULL) 会**静默丢列**，
#    导致 BASE_all 只有 10 列而 DROP_* 有 11 列 → rbindlist 报 "inconsistent columns"。
scen[["BASE_all"]] <- list(fps = fp, dropped = NA_character_, note = "")
for (s in studies) {
  d <- dt_main[study != s]
  if (uniqueN(d$study) < 2L) {
    message("  跳过剔除 ", s, "：剩余研究数 < 2，模型不可识别")
    scen[[paste0("DROP_", s)]] <- list(fps = NULL, dropped = s,
                                       note = "剩余研究数 < 2 → 不可估计")
    next
  }
  fps <- tryCatch(fit_pool(d, paste0("LOO_drop_", s)),
                  error = function(e) { message("  剔除 ", s, " 拟合失败：", conditionMessage(e)); NULL })
  scen[[paste0("DROP_", s)]] <- list(fps = fps, dropped = s,
                                     note = if (is.null(fps)) "拟合失败" else "")
}

rr_rows <- list()
for (k in names(scen)) {
  sc <- scen[[k]]
  nt <- if (is.null(sc$note)) "" else as.character(sc$note)   # NULL 防御（同上）
  if (is.null(sc$fps)) {
    rr_rows[[k]] <- data.table(scenario = k, dropped_study = sc$dropped,
                               n_study = NA_integer_, n_rows = NA_integer_,
                               arms_kept = NA_character_, dev_arms_kept = NA_character_,
                               rr_at_off60 = NA_real_, log_rr = NA_real_, se_log_rr = NA_real_,
                               paf_global_2022 = NA_real_, note = nt)
    next
  }
  fps <- sc$fps
  dk <- dt_main[if (is.na(sc$dropped)) TRUE else study != sc$dropped]
  W <- pooled_w(fps, "total_PA")
  # offset 60 处的 RR 与其 SE（线性组合）
  rr60 <- NA_real_; se60 <- NA_real_
  if (!is.null(W)) {
    cc <- setNames(numeric(length(fps$b)), names(fps$b))
    for (nm in names(W)) cc[[nm]] <- unlist(W)[[nm]] * OFF_EFF
    rr60 <- exp(sum(cc * fps$b))
    se60 <- sqrt(max(as.numeric(t(cc) %*% fps$V %*% cc), 0))
  }
  # Global 2022 的 PAF（device_pooled 曲线 + 冻结的 s1p 暴露分布）
  pxg <- px_cells_s1p("Global", 2022)
  pafg <- NA_real_
  if (!is.null(pxg) && !is.null(W)) {
    bopx <- build_dp_bop(fps, "total_PA", seed = LOO_SEED, tag = k)
    if (!is.null(bopx)) {
      set.seed(LOO_SEED)
      br <- make_rr_fun_pooled(bopx, pxg, metric = "total_PA", clamp = TRUE)
      pafg <- paf_from_dist(pxg$f, br$mean_curve$abs)
    }
  }
  rr_rows[[k]] <- data.table(
    scenario = k, dropped_study = sc$dropped,
    n_study = fps$n_study, n_rows = fps$n_rows,
    arms_kept = arms_of(dk),
    # ⚠️ 同 05a 的 arms_device：贝叶斯路径下 names(W) 是 brms 安全码，必须经 coef_label()
    #    翻回 "arm|metric" 标签再取 arm 名，否则 Table12 会泄漏引擎内部标识。
    dev_arms_kept = if (is.null(W)) "无 device×total_PA 臂" else
      paste(sub("\\|.*$", "", vapply(names(W), function(cn) coef_label(fps, cn), "")),
            collapse = "+"),
    rr_at_off60 = rr60, log_rr = log(rr60), se_log_rr = se60,
    paf_global_2022 = pafg, note = nt)
}
RR_TAB <- rbindlist(rr_rows)
fwrite(RR_TAB, file.path(DIR_OUT, "Table12_bop_loo_RR.csv"))

cat("\n===== 留一法：device_pooled × total_PA 曲线 =====\n")
print(RR_TAB[, .(scenario, dropped_study, n_study, n_rows,
                 dev_arms_kept = substr(dev_arms_kept, 1, 58),
                 rr60 = round(rr_at_off60, 3), se = round(se_log_rr, 3),
                 paf = round(paf_global_2022, 4))])

# ---------------------------------------------------------------------------
# 3. LOO 对归因负担的影响（4 个地区 × 2022）
# ---------------------------------------------------------------------------
gbd_rows <- list()
for (k in names(scen)) {
  sc <- scen[[k]]
  # 没有可用曲线时，PAF 记为 NA（分母仍列出，便于读者看到覆盖面）
  for (loc in LOO_LOCS) for (yr in LOO_YEARS) {
    px <- px_cells_s1p(loc, yr)
    w2 <- build_wide(b2, loc, yr, "total")
    w1 <- build_wide(b1, loc, yr, "attrib")
    if (is.null(px) || is.null(w2)) next
    paf <- NA_real_
    if (!is.null(sc$fps)) {
      bopx <- build_dp_bop(sc$fps, "total_PA", seed = LOO_SEED, tag = k)
      if (!is.null(bopx)) {
        set.seed(LOO_SEED)
        br <- make_rr_fun_pooled(bopx, px, metric = "total_PA", clamp = TRUE)
        paf <- paf_from_dist(px$f, br$mean_curve$abs)
      }
    }
    tot <- merge(w2, if (!is.null(w1)) w1 else w2[, .(cause_name)], by = "cause_name", all.x = TRUE)
    tot[, rec_d := paf * deaths_total]
    gbd_rows[[length(gbd_rows) + 1L]] <- data.table(
      scenario = k, dropped_study = sc$dropped, location = loc, year = yr,
      n_cause = nrow(tot), paf = paf,
      denominator_deaths = sum(tot$deaths_total, na.rm = TRUE),
      recomputed_deaths = if (is.na(paf)) NA_real_ else sum(tot$rec_d, na.rm = TRUE),
      gbd_attrib_deaths = if ("deaths_attrib" %in% names(tot)) sum(tot$deaths_attrib, na.rm = TRUE) else NA_real_)
  }
}
PAF_TAB <- rbindlist(gbd_rows)
PAF_TAB[, fold := recomputed_deaths / gbd_attrib_deaths]
fwrite(PAF_TAB, file.path(DIR_OUT, "Table12_m3_loo_paf.csv"))

# ---------------------------------------------------------------------------
# 4. 人读报告
# ---------------------------------------------------------------------------
sink(file.path(DIR_LOGS, "bop_loo.txt"))
cat("===== Module 2 留一法报告（05e）=====\n")
cat("生成时间：", format(Sys.time()), "\n\n")
cat("主分析池：", nrow(dt_main), "行 /", length(studies), "篇研究\n")
cat("研究：", paste(studies, collapse = ", "), "\n\n")
cat("—— 关键前提 ——\n")
cat("Module 3 消费的是 curve_role='device_pooled' & metric='total_PA'，\n")
cat("它 = device_hip|total_PA + device_mixed|total_PA 的逆方差合并。\n")
cat("即：整条设备总量曲线由 **Ekelund2019(hip)** 与 **Tarp2024(mixed)** 两篇支撑。\n\n")
cat("—— 逐情景 ——\n")
print(RR_TAB[, .(scenario, dropped_study, n_study, n_rows, dev_arms_kept,
                 rr60 = round(rr_at_off60, 4), se = round(se_log_rr, 4),
                 paf = round(paf_global_2022, 4))])
cat("\n—— LOO 对归因负担的影响（2022）——\n")
print(PAF_TAB[order(location, scenario),
              .(location, scenario, paf = round(paf, 4),
                rec_m = round(recomputed_deaths / 1e3, 1),
                gbd_m = round(gbd_attrib_deaths / 1e3, 1),
                fold = round(fold, 3))])
base <- PAF_TAB[scenario == "BASE_all"]
loo  <- PAF_TAB[scenario != "BASE_all" & !is.na(fold)]
if (nrow(loo)) {
  cat("\n—— 相对基准的 fold 摆动 ——\n")
  loo <- merge(loo, base[, .(location, fold_base = fold)], by = "location")
  print(loo[order(location, scenario),
            .(location, scenario, fold_base = round(fold_base, 3),
              fold_loo = round(fold, 3), swing_pct = round(100 * (fold / fold_base - 1), 1))])
}
sink()
pa_log(sprintf("05e 完成 -> Table12_bop_loo_RR.csv / Table12_m3_loo_paf.csv / logs/bop_loo.txt（%.1f s）",
               as.numeric(difftime(Sys.time(), t0, units = "secs"))))

cat("\n--- 留一法 fold 摆动（Global 2022）---\n")
print(PAF_TAB[location == "Global"][order(scenario),
                                    .(scenario, paf = round(paf, 4), fold = round(fold, 3))])
