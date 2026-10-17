# =============================================================================
# 08c_fig3_dose_response.R —— Fig 3：剂量-反应曲线（投稿版，6 面板）
# -----------------------------------------------------------------------------
# 行 1  (a)(b)  NHANES 2011-2014 腕式 MIMS 总量（rr_curves.csv，200 点）
# 行 2  (c)(d)  NHANES 2003-2006 髋式 **Peak-30**（counts/min）
# 行 3  (e)(f)  NHANES 2003-2006 髋式 **MVPA**（min/day，>=2020 cpm）
#
# 行 2/3 每面板画**两条**曲线：
#   实线 = M0 未调整体量     虚线 = M1 调整总活动量后（volume-adjusted）
#   —— 这是第①件补图的核心信息：MVPA 调整体量后曲线几乎平坦（HR≈1），
#      而 Peak-30 调整体量后**仍保留**剂量-反应 → 强度携带独立信息。
#
# 数据：
#   output/rr_curves.csv                    04 产出（腕式 MIMS）
#   output/Table11_pam_intensity_RR.csv     04e 产出（髋式 Peak-30 / MVPA，M0 + M1）
#   output/Table11_pam_intensity_per_IQR.csv 参考/单位换算
#
# 产出：figures/panel/Fig3{a..f}_*.pdf(+png)；figures/combined/Fig3.pdf(+png)
#       output/Fig3_dose_response.pdf(+png)（交付层镜像；04 的 2-panel 预览由此接管）
# =============================================================================
t0 <- Sys.time()
source("08_fig_style.R")
pa_log("===== 08c Fig 3 剂量-反应曲线（6 面板）=====")

f_rr  <- file.path(DIR_OUT, "rr_curves.csv")
f_int <- file.path(DIR_OUT, "Table11_pam_intensity_RR.csv")
for (f in c(f_rr, f_int)) if (!file.exists(f)) stop("缺少输入：", f)
rr  <- fread(f_rr);  stopifnot(nrow(rr) > 0)
itr <- fread(f_int, encoding = "UTF-8")

lab_oc <- c(all_cause = "All-cause mortality", cvd = "Cardiovascular mortality",
            died = "All-cause mortality",     cvd2 = "Cardiovascular mortality")
itr[, outcome2 := fifelse(outcome == "died", "all_cause", "cvd")]

# --------------------------------------------------------------- 通用画法 ----
#
#   ⚠️ xvar 必须显式传入：两份数据源的 x 列名不同 ——
#      rr_curves.csv（04）用 `x`；Table11_pam_intensity_RR.csv（04e）用 `value`
#      （真实暴露值）。原先写死 aes(x, hr)，前两个 MIMS 面板能过，
#      一进第 3 个面板（peak-30）geom_ribbon 就继承不到 x →
#      `Error in geom_ribbon(): object 'x' not found`（层 4）。
#      这里统一用 .data[[xvar]]，彻底避免列名耦合。
mk_curve <- function(d, xvar, ref_val, tag, xlab, col_main, show_lt = FALSE,
                     legend = FALSE, unit = "MIMS/day") {
  p <- ggplot(d, aes(x = .data[[xvar]], y = hr)) +
    geom_hline(yintercept = 1, linetype = "dotted", linewidth = 0.4, colour = "grey40") +
    geom_vline(xintercept = ref_val, linetype = "dashed", linewidth = 0.4, colour = "grey30") +
    annotate("text", x = ref_val, y = max(d$hi), label = sprintf("Reference\n%.0f %s", ref_val, unit),
             hjust = -0.05, vjust = 1, size = 1.9, lineheight = 0.95, colour = "grey30")
  if (show_lt) {
    p <- p +
      geom_ribbon(aes(x = .data[[xvar]], ymin = lo, ymax = hi, group = model, fill = model),
                  alpha = 0.13, colour = NA) +
      geom_line(aes(x = .data[[xvar]], y = hr, group = model, colour = model,
                    linetype = model), linewidth = 0.65) +
      scale_fill_manual(values = c(M0 = col_main, M1 = col_main), guide = "none") +
      scale_colour_manual(values = c(M0 = col_main, M1 = col_main),
                          labels = c(M0 = "Unadjusted for volume",
                                     M1 = "Adjusted for volume"),
                          name = NULL) +
      scale_linetype_manual(values = c(M0 = "solid", M1 = "22"), labels = c(M0 = "Unadjusted for volume",
                                     M1 = "Adjusted for volume"), name = NULL)
  } else {
    p <- p +
      geom_ribbon(aes(x = .data[[xvar]], ymin = lo, ymax = hi), fill = col_main,
                  alpha = 0.18, colour = NA) +
      geom_line(aes(x = .data[[xvar]], y = hr), linewidth = 0.7, colour = col_main)
  }
  p <- p +
    scale_x_continuous(labels = comma, expand = expansion(mult = c(0.01, 0.02))) +
    scale_y_continuous(expand = expansion(mult = c(0.03, 0.05))) +
    labs(x = xlab, y = "Hazard ratio (95% CI)", tag = tag) +
    theme_pa(7.5) +
    theme(plot.tag = element_text(size = 9, face = "bold"))
  if (legend) p <- p + theme(legend.position = c(0.97, 0.97),
                             legend.justification = c(1, 1),
                             legend.text = element_text(size = 5.4),
                             legend.key.height = unit(0.22, "cm"),
                             legend.background = element_rect(fill = "white",
                               colour = "grey75", linewidth = 0.2))
  else p <- p + theme(legend.position = "none")   # 图例只在 (c) 出现一次，其余隐藏
  p
}

# ---------------------------------------------------- (a)(b) 腕式 MIMS -------
# 参照点 = 04 的**绝对锚点**（GBD TMREL 设备等效值），直接读 04 落盘的台账。
#   ⚠️ 不要用 `which.min(abs(hr-1))` 反推锚点：04 的 x 网格是 1–99 分位的 200 点
#      **线性采样**，绝对锚点未必落在格点上 —— 实测锚点 13,222.07 的最近格点
#      HR = 1.0027（偏移约 0.27%），会把参照线挪走、与 HR=1 的交点错开。
#   ℹ️ 口径变更记录：锚点原为占位分位 P60（→13,936.5），2026-10-15 回填为
#      TMREL 3600–4400 MET-min/wk 的设备等效中点（→13,222.07），见
#      00_setup.R §7b 与 05 的一致性断言。
anchor_f <- file.path(DIR_OUT, "Table2_reference_anchor.csv")
if (!file.exists(anchor_f)) stop("缺少 ", anchor_f, "（请先跑 04）")
anc <- fread(anchor_f, encoding = "UTF-8")
anc <- anc[exposure == "mims_per_day"]
if (nrow(anc) != 1L) stop("Table2_reference_anchor.csv 中 mims_per_day 应为唯一 1 行")
ref_mims_val <- anc$ref_val[1]
oc_m <- unique(rr$outcome)
if (!is.finite(ref_mims_val) || ref_mims_val < min(rr$x) || ref_mims_val > max(rr$x))
  stop(sprintf("参照锚点 %.1f 落在 rr_curves 的 x 范围 [%.1f, %.1f] 之外",
               ref_mims_val, min(rr$x), max(rr$x)))
pa_log(sprintf("  MIMS 参照锚点 = %.1f MIMS/day（来源：%s）",
               ref_mims_val, anc$source[1]))
p_mims <- lapply(seq_along(oc_m), function(i) {
  d  <- rr[outcome == oc_m[i]]
  mk_curve(d, "x", ref_mims_val, tag = letters[i],
           xlab = "Device-measured activity (MIMS/day)",
           col_main = PA_COLS[["device"]], unit = "MIMS/day")
})
names(p_mims) <- oc_m

# ------------------------------------------- (c)-(f) 髋式 Peak-30 / MVPA -----
IT <- list(
  peak30 = list(x = "peak30_per_day", lab = "Peak-30", short = "peak30",
                unit = "counts/min",
                xlab = "Peak-30 activity (counts/min)",
                col  = PA_COLS[["hip"]]),
  mvpa   = list(x = "mvpa_per_day", lab = "MVPA", short = "mvpa",
                unit = "min/day",
                xlab = "MVPA (min/day, >= 2020 counts/min)",
                col  = PA_COLS[["reported"]]))

panels <- list(); idx <- 3L
for (nm in names(IT)) {
  it <- IT[[nm]]
  d  <- itr[exposure == it$x]
  if (!nrow(d)) stop("Table11 缺少暴露：", it$x)
  for (oc in c("all_cause", "cvd")) {
    dd <- d[outcome2 == oc]
    if (!nrow(dd)) stop("Table11 缺少结局：", it$x, " x ", oc)
    dd[, model := fifelse(volume_adjusted, "M1", "M0")]
    dd[, model := factor(model, levels = c("M0", "M1"))]
    if (dd[, .N, by = .(model, pct)][N > 1L, .N] > 0L)
      stop("Table11 同模型百分位重复：", it$x, " x ", oc)
    rf <- unique(dd$ref_value)
    if (length(rf) != 1L) stop("参考值不唯一：", it$x, " x ", oc)
    # 参考值只在 pct==12.5 处给出（两模型相同）→ HR 应为 1
    chk <- dd[pct == 12.5]
    if (nrow(chk) != 2L || any(abs(chk$hr - 1) > 1e-6))
      stop("pct=12.5 处 HR 不为 1（", it$x, " x ", oc, "），参照点口径有误")
    panels[[paste0(nm, "_", oc)]] <-
      mk_curve(dd, "value", rf, tag = letters[idx], xlab = it$xlab, col_main = it$col,
               show_lt = TRUE, legend = (nm == "peak30" && oc == "all_cause"),
               unit = it$unit)
    idx <- idx + 1L
  }
}

allp <- c(p_mims, panels)
# 期望顺序：(a) mims all-cause, (b) mims cvd, (c) peak30 all-cause,
#           (d) peak30 cvd, (e) mvpa all-cause, (f) mvpa cvd
ord <- c("all_cause", "cvd", "peak30_all_cause", "peak30_cvd",
         "mvpa_all_cause", "mvpa_cvd")
stopifnot(length(allp) == 6L, all(ord %in% names(allp)))

# 单 panel 独立导出（panel-by-panel，供手动重组）
nm_of <- c(all_cause = "mims_all_cause", cvd = "mims_cvd",
           peak30_all_cause = "peak30_all_cause", peak30_cvd = "peak30_cvd",
           mvpa_all_cause = "mvpa_all_cause", mvpa_cvd = "mvpa_cvd")
for (k in ord) save_panel(allp[[k]], sprintf("Fig3%s_%s", letters[match(k, ord)], nm_of[[k]]),
                          3.5, 2.9)

# 拼合 3 行 × 2 列
fig3 <- patchwork::wrap_plots(allp[ord], nrow = 3, byrow = TRUE)
save_combined(fig3, "Fig3", 7.2, 8.8)

# ---- 交付层镜像（与 07/08f 同惯例）-----------------------------------------
#   04 的 output/Fig3_dose_response.* 是 2-panel 预览；本脚本的 6-panel 投稿版
#   从此**接管**该文件名（08c 在 00_run_all 中位于 04 之后）。
for (ex in c("pdf", "png"))
  if (!file.copy(file.path(FIG_COMBINED, paste0("Fig3.", ex)),
                 file.path(DIR_OUT, paste0("Fig3_dose_response.", ex)), overwrite = TRUE))
    stop("交付层镜像失败：Fig3.", ex)
for (k in ord) {
  nmf <- sprintf("Fig3%s_%s", letters[match(k, ord)], nm_of[[k]])
  for (ex in c("pdf", "png"))
    if (!file.copy(file.path(FIG_PANEL, paste0(nmf, ".", ex)),
                   file.path(DIR_OUT, paste0(nmf, ".", ex)), overwrite = TRUE))
      stop("交付层镜像失败：", nmf, ".", ex)
}
pa_log("  交付层镜像 -> output/Fig3*_*.pdf|png + output/Fig3_dose_response.pdf|png")

# 参照点落盘（方法学核对；绝对锚点与分位口径分别标注来源）
rp <- rbindlist(list(
  data.table(exposure = "mims_per_day", outcome = oc_m, ref_val = ref_mims_val,
             source = anc$source[1]),
  itr[pct == 12.5, .(exposure, outcome2, ref_val = ref_value)][
    , `:=`(source = "04e: 加权 12.5 百分位（与 04b / BoP ref_canon 一致）")][
    , outcome := outcome2][, outcome2 := NULL]
), use.names = TRUE)
fwrite(unique(rp), file.path(DIR_OUT, "Fig3_reference_points.csv"), bom = TRUE)

cat("\n--- Fig 3 关键数字 ---\n")
cat("参照点：\n"); print(unique(rp)[order(exposure, outcome),
                                     .(exposure, outcome, ref_val = round(ref_val, 1))])
cat("\n每 IQR 的 M0 vs M1（Table11_per_IQR）已由 04e 落盘，此处仅复核方向：\n")
pi <- fread(file.path(DIR_OUT, "Table11_pam_intensity_per_IQR.csv"), encoding = "UTF-8")
print(pi[, .(exposure, outcome, volume_adjusted,
             HR = round(hr_per_iqr, 3),
             CI = sprintf("(%.2f, %.2f)", lo, hi))][order(exposure, outcome, -volume_adjusted)])
cat(sprintf("用时 %.1f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
pa_log("08c 完成 -> figures/panel/Fig3{a..f}_*.pdf + figures/combined/Fig3.pdf")
