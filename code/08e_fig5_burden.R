# =============================================================================
# 08e_fig5_burden.R —— Fig 5：重算归因负担（投稿版；(a) + (b) + (c) + (d)）
# -----------------------------------------------------------------------------
# (a) 全球与代表国家：本研究重算 vs GBD 2023 现报（哑铃图，log10 尺度，2022）
# (b) 按 SDI 分层的低估幅度（分组柱 + fold 标注；底表 M3_BYCOUNTRY_by_sdi.csv）
# (c) 204 国 × 8 病因 fold 热图（按 SDI 排序；底表 M3_BYCOUNTRY_by_cause.csv）
#     ⚠️ 方案 §321 原定 (c) 为「归因负担占该 cause 总死亡的百分比」= PAF 热图，
#        但当前 RR 口径下 PAF 在 cause 间恒等 → 8 列全同、热图退化（已实证）。
#        故改用 fold（口径差异），理由详见下方 §2 的注释块。
# (d) 口径分解瀑布图（与 07_fig5d_waterfall.R 同一套数值，从其落盘 CSV 重绘；
#     07 是主链数据源，本脚本只做投稿版面板渲染，不重复计算）
#
# 产出：figures/panel/Fig5{a,b,c,d}_*.pdf(+png)；figures/combined/Fig5_a_d.pdf(+png)、
#       figures/combined/Fig5_a_b_c_d.pdf(+png)
# =============================================================================
t0 <- Sys.time()
source("08_fig_style.R")
pa_log("===== 08e Fig 5 重算负担 =====")

TOT <- fread(file.path(DIR_OUT, "PREVIEW_module3_s1p_totals.csv"), encoding = "UTF-8")
RR_SRC <- "pooled"   # 主分析（BoP 池化）；nhanes 来源作敏感性
YR <- 2022

# =============================================================================
# 1. (a) 哑铃图：重算 vs GBD 现报（8 地区，2022，log10）
# =============================================================================
d <- TOT[year == YR & rr_source == RR_SRC]
d[, location := fifelse(location == "United States of America", "USA", location)]
# y 轴自上而下：Global 在顶，其余按名称倒序（factor 从下往上画）
d[, location := factor(location, levels = rev(c("Global", sort(setdiff(unique(location), "Global")))))]
d[, measure := NULL]

dm <- melt(d[, .(location, measure = "Deaths",
                 ours = recomputed_deaths, gbd = gbd_deaths)],
           id.vars = c("location", "measure"), variable.name = "src", value.name = "n")
dm <- rbind(dm, melt(d[, .(location, measure = "DALYs",
                           ours = recomputed_dalys, gbd = gbd_dalys)],
                     id.vars = c("location", "measure"), variable.name = "src", value.name = "n"))
dm[, src := factor(src, levels = c("gbd", "ours"), labels = c("GBD 2023 reported", "This study"))]
dm[, measure := factor(measure, levels = c("Deaths", "DALYs"))]

# fold 标注（每地区每 measure 一个，放在两点连线中点上方）
folds <- rbind(
  d[, .(location, measure = "Deaths", ours = recomputed_deaths, gbd = gbd_deaths)],
  d[, .(location, measure = "DALYs",  ours = recomputed_dalys,  gbd = gbd_dalys)])
folds[, location := factor(location, levels = levels(dm$location))]
folds[, `:=`(xmid = 0.5 * (log10(ours) + log10(gbd)),
             flab = sprintf("x%.1f", ours / gbd))]

p_a <- ggplot(dm, aes(n, location)) +
  geom_line(aes(group = location), linewidth = 0.7, colour = "grey70") +
  geom_point(data = dm[src == "GBD 2023 reported"], aes(n, location),
             size = 1.7, shape = 18, colour = PA_COLS[["gbd"]]) +
  geom_point(data = dm[src == "This study"], aes(n, location),
             size = 2.1, shape = 16, colour = PA_COLS[["study"]]) +
  geom_text(data = folds, aes(xmid, location, label = flab),
            size = 1.95, colour = "grey25", vjust = -0.85) +
  facet_wrap(~ measure, nrow = 1, scales = "free_x") +
  scale_x_log10(labels = comma, expand = expansion(mult = c(0.06, 0.06))) +
  labs(x = sprintf("LPA-attributable burden, %d (log scale)", YR),
       y = NULL, tag = "a",
       subtitle = sprintf("Device-based recomputation vs GBD 2023 reported (%s RR source)", RR_SRC)) +
  theme_pa(7.5) +
  theme(axis.text.y = element_text(size = 6.8),
        plot.tag = element_text(size = 9, face = "bold"))

# =============================================================================
# 2. (d) 瀑布图（从 07 的落盘数据重绘为投稿 panel）
# =============================================================================
wd <- fread(file.path(DIR_OUT, "Fig5d_waterfall_data.csv"), encoding = "UTF-8")
w  <- wd[scope == "Global"]
setorder(w, step)
stopifnot(nrow(w) == 5L)
PAF_GBD <- w$paf_gbd_reported[1]

wf_bar <- data.table(
  x    = 1:5,
  seg  = factor(c("Study estimate", "RR magnitude", "TMREL definition", "Residual", "GBD 2023 (reported)"),
                levels = c("Study estimate", "RR magnitude", "TMREL definition", "Residual", "GBD 2023 (reported)")),
  v_lo = c(0, w$to_paf[2], w$to_paf[2], w$to_paf[3], 0),
  v_hi = c(w$to_paf[1], w$from_paf[2], w$to_paf[3], w$to_paf[4], w$to_paf[5]))
wf_link <- data.table(x = (1:4) + 0.30, xend = (2:5) - 0.30, y = w$to_paf[1:4])
wf_lab <- data.table(
  x  = c(1, 2, 3, 4, 5),
  y  = c(0.100, 0.098, w$to_paf[3] + 0.004, w$to_paf[4] + 0.013, w$to_paf[5] + 0.004),
  vj = c(0.5, 0.5, 0, 0, 0),
  cl = c("white", "white", "grey10", "grey10", "grey10"),
  lb = c(sprintf("%.3f\nfold %.2f", w$to_paf[1], w$fold_to[1]),
         sprintf("%.3f\nx%.2f", w$to_paf[2], w$multiplier[2]),
         sprintf("%.3f\nx%.2f", w$to_paf[3], w$multiplier[3]),
         sprintf("x%.3f", w$multiplier[4]),
         sprintf("%.3f\nfold %.2f", w$to_paf[5], w$fold_to[5])))
SEG_COLS <- c("Study estimate" = "#3C5488", "RR magnitude" = "#D6604D",
              "TMREL definition" = "#4C9F70", "Residual" = "#E6E6E6",
              "GBD 2023 (reported)" = "#8C8C8C")

p_d <- ggplot(wf_bar, aes(x = x)) +
  geom_segment(data = wf_link, aes(x = x, xend = xend, y = y, yend = y),
               linetype = "dotted", colour = "grey55", linewidth = 0.30, inherit.aes = FALSE) +
  geom_rect(aes(xmin = x - 0.30, xmax = x + 0.30, ymin = v_lo, ymax = v_hi, fill = seg),
            colour = "grey25", linewidth = 0.30) +
  geom_text(data = wf_lab, aes(x, y, label = lb, vjust = vj, colour = cl),
            size = 2.35, lineheight = 0.90, show.legend = FALSE) +
  scale_colour_identity() +
  scale_fill_manual(values = SEG_COLS, name = NULL) +
  scale_x_continuous(breaks = 1:5,
                     labels = c("This study\n(primary)", "RR\nmagnitude", "TMREL\ndefinition",
                                "Residual", "GBD 2023\n(reported)"),
                     expand = expansion(add = 0.60)) +
  scale_y_continuous(limits = c(0, 0.205), breaks = seq(0, 0.20, 0.05),
                     expand = expansion(mult = c(0, 0)),
                     labels = function(v) formatC(v, format = "f", digits = 3)) +
  labs(x = NULL, y = "PAF (attributable fraction of deaths)", tag = "d",
       subtitle = sprintf("Gap fully explained by two definitional differences (Global, %d; residual %+.2f%%)",
                          w$year[1], (w$to_paf[5] / w$to_paf[3] - 1) * 100)) +
  theme_pa(7.5) +
  theme(legend.position = "bottom",
        legend.text = element_text(size = 6.2),
        legend.key.size = unit(0.22, "cm"),
        legend.spacing.x = unit(0.08, "cm"),
        axis.text.x = element_text(size = 6.8, lineheight = 0.95),
        plot.tag = element_text(size = 9, face = "bold"))

# =============================================================================
# 2. (b) 按 SDI 分层的低估幅度  +  (c) 204 国 × 8 病因 fold 热图
# -----------------------------------------------------------------------------
# 底表（由 95c_module3_bycountry.R 产出，205 location）：
#   output/M3_BYCOUNTRY_by_sdi.csv      → (b)
#   output/M3_BYCOUNTRY_by_cause.csv    → (c)
#
# ⚠️ 为什么 (c) 画的是 **fold** 而不是方案 §321 原定的「归因负担占该 cause 总死亡的百分比」：
#    05 的 recompute_burden() 对 8 个病因共用同一条 RR 曲线（device_pooled × total_PA，
#    见 05 第 718 行：paf 的计算**不依赖 cause**）→ 逐病因 PAF 在 cause 之间恒等，
#    「204 国 × 8 病因」的 PAF 热图会有 8 列完全相同（退化）。
#    已实证：每个 location 的 paf_deaths_c 唯一值个数 = 1。
#    改用 fold = 本研究 / GBD 现报：其分子含 PAF（cause 恒定）而分母是 GBD 的
#    病因特异 PAF → fold 随 cause 变化（实测同国跨病因可差 5–16 倍），热图非退化，
#    且与 (d) 瀑布图的「口径差异」叙事一脉相承。
#    ⛔ 因此 (c) 不能解读为「病因特异 RR 差异」，只能解读为「与 GBD 现报的
#       定义口径差异在哪些病因上最大」。
# =============================================================================
BC_SDI   <- file.path(DIR_OUT, "M3_BYCOUNTRY_by_sdi.csv")
BC_CAUSE <- file.path(DIR_OUT, "M3_BYCOUNTRY_by_cause.csv")
p_b <- p_c <- NULL
n_bc <- 0L

if (!file.exists(BC_SDI) || !file.exists(BC_CAUSE)) {
  cat("\n[08e] 跳过 (b)(c)：未找到逐国产物（请先跑 95c_module3_bycountry.R）\n")
} else {
  QUINT_LV <- c("Low SDI", "Low-middle SDI", "Middle SDI", "High-middle SDI", "High SDI")
  # 国家名紧凑化（仅影响显示，不影响数据）
  LOC_SHORT <- c(
    "United States of America"                = "USA",
    "United Kingdom of Great Britain and Northern Ireland" = "UK",
    "Taiwan"                                  = "Taiwan, China",
    "Taiwan (Province of China)"              = "Taiwan, China",
    "Democratic People's Republic of Korea"   = "DPR Korea",
    "Republic of Korea"                       = "South Korea",
    "Lao People's Democratic Republic"        = "Lao PDR",
    "Democratic Republic of the Congo"        = "DR Congo",
    "United Republic of Tanzania"             = "Tanzania",
    "Bolivia (Plurinational State of)"         = "Bolivia",
    "Iran (Islamic Republic of)"              = "Iran",
    "Syrian Arab Republic"                    = "Syria",
    "Viet Nam"                                = "Vietnam",
    "Russian Federation"                      = "Russia",
    "Czechia"                                 = "Czechia",
    "T\u00fcrkiye"                            = "Turkiye")
  loc_short <- function(x) { y <- LOC_SHORT[x]; ifelse(is.na(y), x, unname(y)) }

  # ---------------------------------------------------------------- (b) ------
  bs <- fread(BC_SDI, encoding = "UTF-8")
  bs <- bs[rr_source == "pooled" & year == YR & !is.na(quintile)]
  bs[, quintile := factor(quintile, levels = QUINT_LV)]
  setorder(bs, quintile)
  bm <- melt(bs[, .(quintile, n_country, fold_deaths,
                    ours = paf_recomputed_deaths, gbd = paf_gbd_deaths)],
             id.vars = c("quintile", "n_country", "fold_deaths"),
             variable.name = "src", value.name = "paf")
  bm[, src := factor(src, levels = c("gbd", "ours"),
                     labels = c("GBD 2023 reported", "This study"))]

  lab_b <- bs[, .(quintile, fold_deaths,
                  ylab = pmax(paf_recomputed_deaths, paf_gbd_deaths))]
  # n 并入 x 轴刻度标签（之前画在 y=0.004 会压在 GBD 灰色柱上看不清）
  xl_b <- bs[, .(quintile, n_country)][!duplicated(quintile)]
  xl_b[, lab := sprintf("%s\n(n=%d)", as.character(quintile), n_country)]

  p_b <- ggplot(bm, aes(quintile, paf, fill = src)) +
    geom_col(position = position_dodge(width = 0.74), width = 0.66,
             colour = "grey25", linewidth = 0.25) +
    geom_text(data = lab_b, aes(x = quintile, y = ylab,
                                label = sprintf("x%.1f", fold_deaths)),
              inherit.aes = FALSE, vjust = -0.55, size = 2.0, colour = "grey20") +
    scale_x_discrete(breaks = xl_b$quintile, labels = xl_b$lab) +
    scale_fill_manual(values = c("This study" = PA_COLS[["study"]],
                                 "GBD 2023 reported" = PA_COLS[["gbd"]]), name = NULL) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.16)),
                       labels = function(v) formatC(v, format = "f", digits = 2)) +
    labs(x = NULL, y = "PAF (attributable fraction of deaths)", tag = "b",
         subtitle = sprintf("Gap by SDI quintile (%d; %s RR source)", YR, RR_SRC)) +
    theme_pa(7.5) +
    theme(legend.position = "bottom",
          legend.text = element_text(size = 6.2),
          legend.key.size = unit(0.22, "cm"),
          legend.spacing.x = unit(0.08, "cm"),
          axis.text.x = element_text(size = 6.0, lineheight = 0.92),
          plot.tag = element_text(size = 9, face = "bold"))

  # ---------------------------------------------------------------- (c) ------
  bc <- fread(BC_CAUSE, encoding = "UTF-8")
  bc <- bc[is_main == TRUE & rr_source == RR_SRC & year == YR & location != "Global"]
  bc[!is.finite(fold_deaths_c), fold_deaths_c := NA_real_]

  # 病因顺序：按 Global 总归因死亡降序（信息量优先，非字母序）
  g_ref <- fread(BC_CAUSE, encoding = "UTF-8")[
    is_main == TRUE & rr_source == RR_SRC & year == YR & location == "Global"]
  setorder(g_ref, -deaths_attrib)
  CAUSE_LV <- g_ref$cause

  # 国家顺序：SDI 五分位（官方切点复算）→ 组内 2022 SDI 降序
  ord <- unique(bc[order(quintile_ord, -sdi_2022), .(location, quintile)])
  ord[, xpos := .I]
  bc  <- merge(bc, ord[, .(location, xpos)], by = "location")
  bc[, cause := factor(cause, levels = CAUSE_LV)]
  # 病因名按 ~26 字符折行（"Lower extremity peripheral arterial disease" 太长）
  wrap26 <- function(s) vapply(strwrap(s, width = 26, simplify = FALSE),
                               paste, character(1), collapse = "\n")
  bc[, cause_lab := factor(wrap26(as.character(cause)),
                           levels = wrap26(CAUSE_LV))]

  # 五分位分组中心 + 边界
  ctr <- ord[, .(xc = mean(xpos), n = .N), by = .(quintile)]
  ctr[, quintile := factor(quintile, levels = QUINT_LV)]
  setorder(ctr, quintile)
  ctr[, lab := sprintf("%s\n(n=%d)", as.character(quintile), n)]
  bnd <- ord[, .(xb = max(xpos)), by = quintile][xb < nrow(ord)]$xb
  bc[, log10_fold := log10(fold_deaths_c)]
  # 色阶上界取 |log10(fold)| 的 98 分位（实测 ≈1.64 → fold≈44），超出部分 squish。
  #   ⚠️ 用**单侧**色阶而非以 fold=1 为中心的对称色阶：实测全部 1632 个
  #      国家×病因组合的 fold 都 ≥ 1.10（从不低于 1），对称色阶会有一半色域无数据、
  #      把主体压在白色附近。白色 = 与 GBD 现报无口径差异，越红差异越大。
  lim <- as.numeric(quantile(abs(bc$log10_fold), 0.98, na.rm = TRUE))
  n_clip <- sum(abs(bc$log10_fold) > lim, na.rm = TRUE)

  p_c <- ggplot(bc, aes(xpos, cause_lab, fill = log10(fold_deaths_c))) +
    geom_tile(colour = NA) +
    geom_vline(xintercept = bnd + 0.5, linewidth = 0.22, colour = "grey85") +
    scale_fill_gradientn(colours = c("#F7F7F7", "#FDDBC7", "#F4A582",
                                     "#D6604D", "#B2182B", "#67001F"),
                         values = scales::rescale(c(0, 0.25, 0.45, 0.65, 0.85, 1)),
                         limits = c(0, lim), oob = scales::squish,
                         breaks = log10(c(1, 2, 5, 10, 20, 40)),
                         labels = c("1", "2", "5", "10", "20", "40"),
                         name = "This study /\nGBD 2023", na.value = "grey90") +
    scale_x_continuous(breaks = ctr$xc, labels = ctr$lab,
                       expand = expansion(mult = c(0.001, 0.001))) +
    labs(x = NULL, y = NULL, tag = "c",
         subtitle = sprintf("Fold (this study vs GBD 2023) by country and cause (%d; %d countries, %d causes; %s RR source)",
                            YR, nrow(ord), length(CAUSE_LV), RR_SRC),
         caption = sprintf("Colour scale clipped at fold = %.0f (%d of %d tiles, %.1f%%); all folds exceed 1.",
                           10^lim, n_clip, nrow(bc), 100 * n_clip / nrow(bc))) +
    theme_pa(7.5) +
    theme(axis.text.x = element_text(size = 5.2, lineheight = 0.9),
          axis.text.y = element_text(size = 4.8, lineheight = 0.88),
          axis.ticks = element_blank(),
          legend.position = "right",
          legend.key.width = unit(0.22, "cm"),
          legend.key.height = unit(0.85, "cm"),
          legend.text = element_text(size = 5.6),
          legend.title = element_text(size = 5.8),
          panel.grid = element_blank(),
          plot.caption = element_text(size = 4.6, colour = "grey40", hjust = 0),
          plot.tag = element_text(size = 9, face = "bold"))

  n_bc <- nrow(ord)
  cat(sprintf("\n[08e] (b)(c) 底表就位：SDI 组 %d 个，国家 %d 个，病因 %d 个\n",
              nrow(bs), nrow(ord), length(CAUSE_LV)))
  cat(sprintf("      (c) fold 范围 %.2f–%.2f；色阶上界 fold=%.0f（截断 %d/%d = %.1f%%）\n",
              min(bc$fold_deaths_c, na.rm = TRUE), max(bc$fold_deaths_c, na.rm = TRUE),
              10^lim, n_clip, nrow(bc), 100 * n_clip / nrow(bc)))
}

# =============================================================================
# 3. 导出
# =============================================================================
save_panel(p_a, "Fig5a_recomputed_vs_gbd", 4.8, 3.2)
save_panel(p_d, "Fig5d_waterfall_decomposition", 4.6, 3.6)
fig5ad <- p_a / p_d
save_combined(fig5ad, "Fig5_a_d", 7.2, 7.0)

if (!is.null(p_b) && !is.null(p_c)) {
  save_panel(p_b, "Fig5b_gap_by_sdi", 3.9, 3.2)
  save_panel(p_c, "Fig5c_fold_heatmap_country_cause", 7.4, 3.7)
  fig5all <- (p_a | p_b) / p_c / p_d +
    plot_layout(heights = c(1, 1.0, 1.05))
  save_combined(fig5all, "Fig5_a_b_c_d", 8.4, 10.6)
}

cat(sprintf("\n--- Fig 5(a) 关键数字（%d, %s RR）---\n", YR, RR_SRC))
print(d[, .(location,
            deaths_ours = fmt_n(recomputed_deaths), deaths_gbd = fmt_n(gbd_deaths),
            fold_deaths = round(recomputed_deaths / gbd_deaths, 1),
            fold_dalys  = round(recomputed_dalys / gbd_dalys, 1))])
cat(sprintf("(b)(c) %s\n",
            if (n_bc > 0L) sprintf("已产出（%d 国 × %d 病因）", n_bc, 8L)
            else "跳过（缺 95c 逐国产物）"))
cat(sprintf("用时 %.1f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
pa_log("08e 完成 -> figures/panel/Fig5{a,b,c,d}*.pdf + figures/combined/Fig5_a_d.pdf, Fig5_a_b_c_d.pdf")
