# =============================================================================
# 07_fig5d_waterfall.R —— Fig 5(d) 口径分解瀑布图（fold 5.79 -> 1.00）
# -----------------------------------------------------------------------------
# 目的：把「本研究与 GBD 2023 的 LPA 归因负担差异（Global fold = 5.79）」分解为
#       两个**可命名**的口径差异 + 一个残余，终点落到 GBD 2023 现报水平：
#         (1) RR 超额风险幅度      RR̄_below 1.395 -> 1.037（对齐到 GBD 隐含水平）
#         (2) TMREL 在暴露分布中的位置  第 54.1 百分位 -> 第 85 百分位（GBD 定义）
#         (3) 残余                GBD 暴露分布 / 年龄结构 / MR-BRT 曲线形状等
#
# 为什么这个图重要（N1 决策的图形化）：
#   fold 不能当「GBD 低估 5.8 倍」写（两条 RR 曲线不可直接比较），
#   但可以当「口径分解」写：**两步对齐后 fold = 0.99，差异被完全解释**。
#   本图即是该论断的直观证据。
#
# 数据源：**只读** 97 的正式情景定级表（不重算、不覆盖任何冻结产物）
#   output/Table9_m3_scenario_summary.csv   S0_base / GBD_ALIGNED_RR / GBD_FAITHFUL
#   output/Table4_m3_decomp.csv             paf_gbd 常数 + 8 地区分情景 PAF 与 RR̄
#
# 口径：Global 2022，25 岁以上成人，8 个 cause 合计，死亡口径 PAF。
#       fold := 本研究 PAF / GBD 2023 现报 PAF（分母为全局常数，见 §12.9）。
#
# ⚠️ 图内文字**一律 ASCII**：Windows 图形设备在非 UTF-8 locale 下无法渲染中文。
# ⚠️ 主图只用 Global；8 个地区的同一分解另出补充小倍数图（by_region）。
#
# 运行：cd code && Rscript 07_fig5d_waterfall.R            # ~5 s
# 产物：
#   output/Fig5d_waterfall_decomposition.pdf / .png   主图（Global 2022）
#   output/Fig5d_waterfall_by_region.pdf     / .png   补充图（8 地区小倍数图）
#   output/Fig5d_waterfall_data.csv                   作图数据（逐段可复核）
#   output/Fig5d_waterfall_caption.md                 中英双语图注
# =============================================================================

# ---- 统一引导（勿改）--------------------------------------------------------
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
})
if (!isTRUE(getOption("PA_SETUP_DONE"))) {
  .ps <- NULL
  for (.c in c("00_setup.R", file.path(getwd(), "00_setup.R"),
               file.path(dirname(gsub("\\\\", "/", sub("^--file=", "",
                 grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))), "00_setup.R"))) {
    if (!is.null(.c) && nzchar(.c) && file.exists(.c)) { .ps <- normalizePath(.c); break }
  }
  if (is.null(.ps)) stop("未找到 00_setup.R：请 setwd() 到 code/ 目录")
  source(.ps); rm(.ps, .c)
}

suppressPackageStartupMessages({
  library(data.table); library(ggplot2); library(scales)
})
pa_log("===== 07 Fig 5(d) 口径分解瀑布图 =====")

t0  <- Sys.time()
HW  <- 0.30   # 半柱宽（x 单位）
YMAX <- 0.205 # y 轴上限（给柱外标注留空间）

# =============================================================================
# 1. 读入与完整性断言
# =============================================================================
F_T9 <- file.path(DIR_OUT, "Table9_m3_scenario_summary.csv")
F_T4 <- file.path(DIR_OUT, "Table4_m3_decomp.csv")
for (f in c(F_T9, F_T4)) {
  if (!file.exists(f)) stop("缺少 ", basename(f), "：请先运行 code/97_m3_scenarios.R")
}
t9 <- fread(F_T9, encoding = "UTF-8")
t4 <- fread(F_T4, encoding = "UTF-8")

NEED <- c("S0_base", "GBD_ALIGNED_RR", "GBD_FAITHFUL")
miss <- setdiff(NEED, t9$scenario)
if (length(miss)) stop("情景表缺少必需情景：", paste(miss, collapse = ", "))

# GBD 现报 PAF 是全表唯一常数（fold 的分母）—— 若哪天变成按地区，
# 说明 97 的 PAF_GBD_REF 口径改过，本图的分母假设失效，必须显式知情。
PAF_GBD_ALL <- unique(t4$paf_gbd)
if (length(PAF_GBD_ALL) != 1L) {
  stop("paf_gbd 不再是全局常数（", length(PAF_GBD_ALL), " 个不同值）：",
       "瀑布图的分母假设失效，请复核 97 的 PAF_GBD_REF 口径。")
}
PAF_GBD <- PAF_GBD_ALL[1]

# Table9 的 paf_global 与 Table4 的 Global 行必须逐位一致（防两表口径漂移）
gl <- t4[location == "Global" & scenario %in% NEED,
         .(scenario, paf_t4 = paf, rrbar = rrbar_below, pct_below)]
chk <- merge(t9[scenario %in% NEED, .(scenario, paf_t9 = paf_global)], gl, by = "scenario")
chk[, d := abs(paf_t9 - paf_t4)]
if (any(chk$d > 1e-12)) {
  stop("Table9 的 paf_global 与 Table4 的 Global 行不一致（最大差 ", max(chk$d),
       "）：两表口径已漂移，拒绝作图。")
}
YEAR  <- t4$year[1]
N_LOC <- uniqueN(t4$location)

pa_log(sprintf("读入：%d 情景 × %d 地区；GBD 现报 PAF = %.10f；年 = %d",
               uniqueN(t4$scenario), N_LOC, PAF_GBD, YEAR))

# =============================================================================
# 2. 构建瀑布 ----------------------------------------------------------------
# =============================================================================
gv <- function(s) t9[scenario == s, paf_global][1]
P_OURS <- gv("S0_base")        # 本研究主结果（绝对口径 TMREL + 原 SIGMA）
P_RR   <- gv("GBD_ALIGNED_RR") # 只对齐 RR 幅度（TMREL 保持绝对口径）
P_FULL <- gv("GBD_FAITHFUL")   # 再对齐 TMREL 定义（第 85 百分位）→ 完整 GBD 口径
P_GBD  <- PAF_GBD              # GBD 2023 现报

RRB_0 <- gl[scenario == "S0_base", rrbar]         # 我们 <TMREL 者的平均 RR
RRB_1 <- gl[scenario == "GBD_ALIGNED_RR", rrbar]  # 对齐后（= GBD 隐含）
PCT_0 <- gl[scenario == "S0_base", pct_below] * 100
PCT_1 <- gl[scenario == "GBD_FAITHFUL", pct_below] * 100

SEG_LEVELS <- c("Study estimate", "RR magnitude", "TMREL definition",
                "Residual", "GBD 2023 (reported)")
SEG_COLS <- c("Study estimate"      = "#3C5488",   # 本研究主结果
              "RR magnitude"        = "#D6604D",   # 使 fold 下降
              "TMREL definition"    = "#4C9F70",   # 使 fold 上升
              "Residual"            = "#E6E6E6",   # 几乎不可见（闭合验证）
              "GBD 2023 (reported)" = "#8C8C8C")   # 外部参照

#' 把四个情景值组装成瀑布图数据
#' @return list(bar = 柱子, link = 连接虚线, lab = 文字标注, band = 误差棒, seg = 逐段明细)
build_wf <- function(p_ours, p_rr, p_full, p_gbd, p_ours_lo = NA, p_ours_hi = NA) {
  bar <- data.table(
    x    = 1:5,
    seg  = factor(SEG_LEVELS, levels = SEG_LEVELS),
    v_lo = c(0,      min(p_rr, p_ours), min(p_full, p_rr), min(p_gbd, p_full), 0),
    v_hi = c(p_ours, max(p_rr, p_ours), max(p_full, p_rr), max(p_gbd, p_full), p_gbd)
  )
  bar[, endp := c(p_ours, p_rr, p_full, p_gbd, p_gbd)]   # 每根柱的「到达水平」
  bar[, fold := endp / p_gbd]

  # 连接虚线：每根柱的到达水平水平延伸到下一根柱的边缘
  link <- data.table(x = (1:4) + HW, xend = (2:5) - HW,
                     y = c(p_ours, p_rr, p_full, p_gbd))

  # 文字标注：大柱（1/2）放柱内白字，小柱（3/4/5）放柱外上方黑字
  lab <- data.table(
    x     = c(1, 2, 3, 4, 5),
    y     = c(0.100, 0.098, p_full + 0.004, p_gbd + 0.013, p_gbd + 0.004),
    vj    = c(0.5, 0.5, 0, 0, 0),
    col   = c("white", "white", "grey10", "grey10", "grey10"),
    label = c(
      sprintf("%.3f\nfold %.2f",   p_ours, p_ours / p_gbd),
      sprintf("%.3f\nx%.2f",       p_rr,   p_rr   / p_ours),
      sprintf("%.3f\nx%.2f",       p_full, p_full / p_rr),
      sprintf("x%.3f",             p_gbd  / p_full),
      sprintf("%.3f\nfold %.2f",   p_gbd,  p_gbd  / p_gbd))
  )
  band <- if (is.finite(p_ours_lo) && is.finite(p_ours_hi)) {
    data.table(x = 1, lo = p_ours_lo, hi = p_ours_hi)
  }
  seg <- data.table(
    step       = c("1 Study estimate", "2 Change: RR magnitude",
                   "3 Change: TMREL definition", "4 Residual", "5 GBD 2023 reported"),
    from_paf   = c(NA, p_ours, p_rr, p_full, NA),
    to_paf     = c(p_ours, p_rr, p_full, p_gbd, p_gbd),
    delta_paf  = c(NA, p_rr - p_ours, p_full - p_rr, p_gbd - p_full, NA),
    fold_from  = c(NA, p_ours / p_gbd, p_rr / p_gbd, p_full / p_gbd, NA),
    fold_to    = c(p_ours / p_gbd, p_rr / p_gbd, p_full / p_gbd, 1, 1),
    multiplier = c(NA, p_rr / p_ours, p_full / p_rr, p_gbd / p_full, NA)
  )
  list(bar = bar, link = link, lab = lab, band = band, seg = seg)
}

XLAB <- c("This study\n(primary)", "RR\nmagnitude", "TMREL\ndefinition",
          "Residual", "GBD 2023\n(reported)")

# 8 个地区 fold 范围 → 换算回 PAF（仅用于第一根柱的误差棒）
LO <- t9[scenario == "S0_base", fold_min][1] * PAF_GBD
HI <- t9[scenario == "S0_base", fold_max][1] * PAF_GBD

L <- build_wf(P_OURS, P_RR, P_FULL, P_GBD, p_ours_lo = LO, p_ours_hi = HI)

#' 画瀑布（Global 与各地区共用）
draw_wf <- function(d, base_size = 8, show_band = TRUE) {
  p <- ggplot(d$bar, aes(x = x)) +
    geom_segment(data = d$link, aes(x = x, xend = xend, y = y, yend = y),
                 linetype = "dotted", colour = "grey55", linewidth = 0.30,
                 inherit.aes = FALSE) +
    geom_rect(aes(xmin = x - HW, xmax = x + HW, ymin = v_lo, ymax = v_hi, fill = seg),
              colour = "grey25", linewidth = 0.30) +
    scale_fill_manual(values = SEG_COLS, drop = FALSE) +
    scale_x_continuous(breaks = 1:5, labels = XLAB, expand = expansion(add = 0.60)) +
    scale_y_continuous(limits = c(0, YMAX), breaks = seq(0, 0.20, 0.05),
                       expand = expansion(mult = c(0, 0)),
                       labels = function(v) formatC(v, format = "f", digits = 3)) +
    labs(x = NULL, y = "PAF (attributable fraction of deaths)") +
    theme_classic(base_size = base_size) +
    theme(axis.text.x  = element_text(size = base_size - 1, lineheight = 0.95, colour = "grey15"),
          axis.ticks.x = element_blank(),
          legend.position = "bottom",
          legend.title = element_blank(),
          legend.text  = element_text(size = base_size - 2),
          legend.key.size = unit(0.22, "cm"),
          legend.margin = margin(0, 0, 0, 0),
          legend.spacing.x = unit(0.10, "cm"),
          plot.margin = margin(6, 8, 3, 6))
  if (show_band && !is.null(d$band)) {
    p <- p + geom_errorbar(data = d$band, aes(x = x, ymin = lo, ymax = hi),
                           width = 0.15, colour = "grey10", linewidth = 0.45,
                           inherit.aes = FALSE)
  }
  p + geom_text(data = d$lab, aes(x = x, y = y, label = label, vjust = vj, colour = col),
                size = base_size * 0.31, lineheight = 0.90, show.legend = FALSE) +
    scale_colour_identity()
}

# =============================================================================
# 3. 主图（Global 2022）-------------------------------------------------------
# =============================================================================
p_main <- draw_wf(L, base_size = 8) +
  labs(subtitle = sprintf("Global, %d; adults aged 25+; eight causes combined", YEAR)) +
  theme(plot.subtitle = element_text(size = 6.6, colour = "grey35",
                                     margin = margin(b = 2)))

ggsave(file.path(DIR_OUT, "Fig5d_waterfall_decomposition.pdf"), p_main,
       width = 4.6, height = 3.6, device = cairo_pdf)
ggsave(file.path(DIR_OUT, "Fig5d_waterfall_decomposition.png"), p_main,
       width = 4.6, height = 3.6, dpi = 300)

# =============================================================================
# 4. 补充图：8 个地区同一分解（小倍数图）--------------------------------------
# =============================================================================
piv <- dcast(t4[scenario %in% NEED & location != "Global"],
             location ~ scenario, value.var = "paf")
setnames(piv, "S0_base", "p_ours")
setnames(piv, "GBD_ALIGNED_RR", "p_rr")
setnames(piv, "GBD_FAITHFUL", "p_full")
piv[, loc_lab := fifelse(location == "United States of America", "USA", location)]
piv <- piv[order(p_ours)]

reg_lst <- list(bar = rbindlist(lapply(seq_len(nrow(piv)), function(i) {
                  d <- build_wf(piv$p_ours[i], piv$p_rr[i], piv$p_full[i], PAF_GBD)
                  d$bar[, location := piv$loc_lab[i]][]
                })),
                link = rbindlist(lapply(seq_len(nrow(piv)), function(i) {
                  d <- build_wf(piv$p_ours[i], piv$p_rr[i], piv$p_full[i], PAF_GBD)
                  d$link[, location := piv$loc_lab[i]][]
                })))

reg <- reg_lst$bar; reg_lnk <- reg_lst$link
# 显示名：长地名缩短（仅显示层，不改数据）
reg[, location := fifelse(location == "United States of America", "USA", location)]
reg_lnk[, location := fifelse(location == "United States of America", "USA", location)]
reg[, location := factor(location, levels = piv$loc_lab)]
reg_lnk[, location := factor(location, levels = piv$loc_lab)]

p_reg <- ggplot(reg, aes(x = x)) +
  geom_segment(data = reg_lnk, aes(x = x, xend = xend, y = y, yend = y),
               linetype = "dotted", colour = "grey55", linewidth = 0.25,
               inherit.aes = FALSE) +
  geom_rect(aes(xmin = x - HW, xmax = x + HW, ymin = v_lo, ymax = v_hi, fill = seg),
            colour = "grey25", linewidth = 0.25) +
  geom_hline(yintercept = PAF_GBD, linetype = "dashed", colour = "grey35", linewidth = 0.3) +
  facet_wrap(~ location, ncol = 4) +
  scale_fill_manual(values = SEG_COLS, drop = FALSE, guide = "none") +
  scale_x_continuous(breaks = 1:5, labels = c("S", "RR", "TM", "Res", "GBD"),
                     expand = expansion(add = 0.45)) +
  scale_y_continuous(limits = c(0, 0.21), breaks = seq(0, 0.20, 0.05),
                     expand = expansion(mult = c(0, 0)),
                     labels = function(v) formatC(v, format = "f", digits = 2)) +
  labs(x = paste0("S = study estimate | RR = align RR magnitude | TM = align TMREL to 85th pct\n",
                  "Res = residual | GBD = GBD 2023 reported"),
       y = "PAF (deaths)") +
  theme_classic(base_size = 7) +
  theme(axis.text.x = element_text(size = 6, colour = "grey20"),
        axis.ticks.x = element_blank(),
        axis.title.x = element_text(size = 6, colour = "grey35"),
        strip.background = element_blank(),
        strip.text = element_text(size = 7, face = "bold"),
        panel.spacing = unit(0.55, "lines"),
        plot.margin = margin(5, 6, 4, 5))

ggsave(file.path(DIR_OUT, "Fig5d_waterfall_by_region.pdf"), p_reg,
       width = 7.2, height = 4.0, device = cairo_pdf)
ggsave(file.path(DIR_OUT, "Fig5d_waterfall_by_region.png"), p_reg,
       width = 7.2, height = 4.0, dpi = 300)

# =============================================================================
# 5. 作图数据落盘（可复核）----------------------------------------------------
# =============================================================================
out <- rbind(
  L$seg[, .(scope = "Global", step, from_paf, to_paf, delta_paf,
            fold_from, fold_to, multiplier)],
  rbindlist(lapply(seq_len(nrow(piv)), function(i) {
    d <- build_wf(piv$p_ours[i], piv$p_rr[i], piv$p_full[i], PAF_GBD)
    d$seg[, .(scope = piv$location[i], step, from_paf, to_paf, delta_paf,
              fold_from, fold_to, multiplier)]
  }))
)
out[, `:=`(year = YEAR,
           source = "Table9_m3_scenario_summary.csv + Table4_m3_decomp.csv (97_m3_scenarios.R)",
           paf_gbd_reported = PAF_GBD)]
setcolorder(out, c("scope", "year", "step", "from_paf", "to_paf", "delta_paf",
                   "fold_from", "fold_to", "multiplier", "paf_gbd_reported", "source"))
fwrite(out, file.path(DIR_OUT, "Fig5d_waterfall_data.csv"), bom = TRUE)

# =============================================================================
# 6. 图注（中英双语）----------------------------------------------------------
# =============================================================================
RESID_PCT <- (P_GBD / P_FULL - 1) * 100
cap <- c(
  "### Fig 5(d). Decomposition of the gap between device-based and GBD 2023 LPA-attributable burden",
  "",
  sprintf(paste0("**English.** Waterfall decomposition of the ratio (*fold*) between the primary ",
    "device-based estimate and the burden reported by GBD 2023 for low physical activity ",
    "(Global, %d; adults aged 25+; eight causes combined; deaths). Bars show the ",
    "population-attributable fraction (PAF) under successively aligned definitions. Starting from ",
    "the primary estimate (PAF = %.3f; fold = %.2f), aligning the excess-risk amplitude of the ",
    "pooled relative-risk curve to the level implied by the official GBD PAF (mean RR below the ",
    "TMREL, %.2f -> %.2f) lowers the estimate to PAF = %.3f (fold = %.2f); further moving the ",
    "theoretical minimum-risk exposure level (TMREL) from the absolute threshold used here ",
    "(%.1fth percentile of the population exposure distribution) to the GBD definition (85th ",
    "percentile) raises it to PAF = %.3f (fold = %.2f). The residual discrepancy is x%.3f ",
    "(%.1f%%), i.e. the two named definitional differences fully account for the gap. The whisker ",
    "on the first bar shows the range across the eight study locations; the last bar indicates the ",
    "PAF reported by GBD 2023."),
    YEAR, P_OURS, P_OURS / PAF_GBD, RRB_0, RRB_1, P_RR, P_RR / PAF_GBD,
    PCT_0, P_FULL, P_FULL / PAF_GBD, P_GBD / P_FULL, RESID_PCT),
  "",
  sprintf(paste0("**中文.** 本研究基于设备测量的主估计与 GBD 2023 低体力活动归因负担之比值（fold）",
    "的瀑布分解（全球，%d 年；25 岁以上成人；8 个 cause 合计；死亡口径）。纵轴为归因分数（PAF）。",
    "自本研究主结果（PAF = %.3f；fold = %.2f）出发，先将池化相对风险曲线的超额风险幅度对齐至官方 ",
    "PAF 反算的隐含水平（TMREL 之下人群的平均 RR：%.2f → %.2f），估计值降至 PAF = %.3f",
    "（fold = %.2f）；再将理论最低风险暴露水平（TMREL）由本文采用的绝对阈值（人群暴露分布第 %.1f ",
    "百分位）移至 GBD 定义（第 85 百分位），估计值升至 PAF = %.3f（fold = %.2f）。残余差异仅 ",
    "x%.3f（%.1f%%），即上述两项可命名的口径差异已完全解释该差距。首柱误差棒为 8 个研究地区的范围；",
    "末柱为 GBD 2023 现报值。"),
    YEAR, P_OURS, P_OURS / PAF_GBD, RRB_0, RRB_1, P_RR, P_RR / PAF_GBD,
    PCT_0, P_FULL, P_FULL / PAF_GBD, P_GBD / P_FULL, RESID_PCT),
  "",
  "**Notes / 说明**",
  "",
  sprintf("- Vertical axis / 纵轴：PAF（归因死亡分数），Global %d，男女合计，25 岁以上。", YEAR),
  sprintf("- *fold* = PAF(本研究) / PAF(GBD 2023 现报) = PAF / %.4f；分母为全局常数。", PAF_GBD),
  paste0("- 'RR magnitude' = 把池化设备测量曲线的超额风险幅度对齐到官方 PAF 反算的隐含水平；",
         "'TMREL definition' = 把 TMREL 移到人群暴露分布第 85 百分位（GBD 定义）。"),
  sprintf("- 残余柱（Residual）按设计几乎不可见：两项可命名的口径差异之后，差距已不足 1%%（实测 %.2f%%）。", RESID_PCT),
  paste0("- 数据源：`output/Table9_m3_scenario_summary.csv` + `output/Table4_m3_decomp.csv`",
         "（由 `code/97_m3_scenarios.R` 产出）；绘图脚本 `code/07_fig5d_waterfall.R`；",
         "逐段数值见 `output/Fig5d_waterfall_data.csv`。"),
  sprintf("- 补充图 `Fig5d_waterfall_by_region` 给出 8 个地区同一分解（GBD_FAITHFUL 的 fold band %.3f–%.3f）。",
          t9[scenario == "GBD_FAITHFUL", fold_min], t9[scenario == "GBD_FAITHFUL", fold_max])
)
writeLines(cap, file.path(DIR_OUT, "Fig5d_waterfall_caption.md"), useBytes = TRUE)

# =============================================================================
# 7. 控制台摘要 ---------------------------------------------------------------
# =============================================================================
cat("\n--- Fig 5(d) 口径分解（Global 2022，PAF 尺度）---\n")
print(L$seg[, .(step,
                PAF   = round(to_paf, 4),
                delta = round(delta_paf, 4),
                fold  = round(fold_to, 4),
                x     = round(multiplier, 4))])
cat(sprintf("\n闭合检验：fold 从 %.2f 降到 %.3f（残余 %+.2f%%；8 地区 band %.3f–%.3f）\n",
            P_OURS / PAF_GBD, P_FULL / PAF_GBD, RESID_PCT,
            t9[scenario == "GBD_FAITHFUL", fold_min], t9[scenario == "GBD_FAITHFUL", fold_max]))
cat("产物：Fig5d_waterfall_decomposition.pdf/.png、Fig5d_waterfall_by_region.pdf/.png、\n      Fig5d_waterfall_data.csv、Fig5d_waterfall_caption.md\n")
cat(sprintf("用时 %.1f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
pa_log("07 完成 -> output/Fig5d_waterfall_*")
