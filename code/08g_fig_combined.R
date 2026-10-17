# =============================================================================
# 08g_fig_combined.R —— 备选拼版（面板数受限时用）【独立版，不依赖 08c/08f 执行】
#
# 背景：eClinicalMedicine ≤6 按编号计（Fig 1–6 已合规）。但部分编辑按「面板」计：
#       Fig 3 现为 6 面板、Fig 6 现为 3 面板。本脚本产出两份**备选合并版**：
#         Fig3_combined_4panels : (a)(b) MIMS 两面板；(c)(e)→髋式·全因 1 面板、
#                                 (d)(f)→髋式·CVD 1 面板（百分位轴）
#         Fig6_combined_2panels : (a) 情景森林 | (b) 留一森林 左右双列
#                                 （(c) E 值下沉——头条读数 3.78 已在正文 R6 可查）
#
# ⚠️ 方法说明（Fig 3 合并面板）：Peak-30（counts/min）与 MVPA（min/day）绝对单位
#    不同，不能共绝对 x 轴；两曲线共享同一百分位网格（Table11 pct 12.5–87.5，9 档），
#    与 Module 2 池的协调轴一致，故用「暴露分布百分位」作 x 轴——与正文 2.1
#    「不以同一尺度计量，故池在百分位轴协调」互证。
#
# 设计说明：**不 source 08c/08f**（它们会重写 figures/ 下同名 PDF；若用户正打开
#   Fig6.pdf，cairo_pdf 写入失败会使整个脚本中断）。本脚本只读数据、只写新文件名。
#
# 产物：figures/combined/Fig3_combined_4panels.pdf(+png)
#       figures/combined/Fig6_combined_2panels.pdf(+png)
#   不镜像到 output/（不进 manifest，避免扰动 98 校验）。
# =============================================================================
t0 <- Sys.time()
source("08_fig_style.R")
pa_log("===== 08g 备选拼版（Fig3 4 面板 / Fig6 2 面板）=====")

suppressPackageStartupMessages({ library(data.table) })
comma <- scales::comma

# ===========================================================================
# Part 1 —— Fig 6 合并版（2 面板）：数据与画法取自 08f 的 (a)(b) 段
# ===========================================================================
t9   <- fread(file.path(DIR_OUT, "Table9_m3_scenario_summary.csv"),  encoding = "UTF-8")
loo  <- fread(file.path(DIR_OUT, "Table12_m3_loo_paf.csv"),          encoding = "UTF-8")
looR <- fread(file.path(DIR_OUT, "Table12_bop_loo_RR.csv"),          encoding = "UTF-8")

lab_en <- c(
  S0_base         = "Primary analysis (device-scale RR, absolute TMREL)",
  D2_p85_nosig    = "Upper bound: TMREL at 85th pct + no calibration convolution",
  GBD_ALIGNED_RR  = "GBD-aligned: RR magnitude only",
  GBD_FAITHFUL    = "GBD-aligned: full (TMREL definition + RR magnitude)",
  L1a_p70         = "Sensitivity: TMREL at 70th percentile",
  L1b_p85         = "Sensitivity: TMREL at 85th percentile (GBD definition)",
  L2a_s1600       = "Sensitivity: convolution sigma 3335 -> 1600",
  L2b_s800        = "Sensitivity: convolution sigma 3335 -> 800",
  L2c_s0          = "Sensitivity: sigma -> 100 (~no convolution)",
  L3_rr_gbd       = "Sensitivity: RR magnitude scaled to GBD level",
  M2_rank_abs     = "Sensitivity: rank-preserving mapping (absolute TMREL)",
  M2_rank_p85     = "Sensitivity: rank-preserving mapping (85th pct TMREL)")
t9[, lab := unname(lab_en[scenario])]
if (anyNA(t9$lab)) stop("情景缺少英文标签映射：", paste(t9[is.na(lab)]$scenario, collapse = ", "))
t9[, role := factor(role, levels = c("main", "upper_bound", "gbd_aligned", "sensitivity"))]
t9[, lab := factor(lab, levels = rev(lab))]
ROLE_COLS <- c(main = PA_COLS[["study"]], upper_bound = PA_COLS[["up"]],
               gbd_aligned = PA_COLS[["down"]], sensitivity = "grey55")

p6a <- ggplot(t9, aes(x = fold_global, y = lab, colour = role)) +
  geom_vline(xintercept = 1, linetype = "dashed", linewidth = 0.45, colour = "grey30") +
  geom_errorbarh(aes(xmin = fold_min, xmax = fold_max),
                 height = 0.22, linewidth = 0.45, show.legend = FALSE) +
  geom_point(size = 1.9, shape = 16, show.legend = FALSE) +
  geom_text(aes(label = sprintf("%.2f", fold_global)), vjust = -0.95, size = 2.0,
            colour = "grey15") +
  annotate("text", x = 1, y = 5.6, label = "fold = 1\n(GBD 2023 reported)",
           size = 2.0, colour = "grey30", hjust = -0.06, lineheight = 0.95) +
  scale_x_log10(breaks = c(0.5, 1, 2, 5, 10), expand = expansion(mult = c(0.05, 0.10))) +
  scale_colour_manual(values = ROLE_COLS, guide = "none") +
  labs(x = "Fold: recomputed / GBD 2023 reported attributable deaths (log scale)",
       y = NULL, tag = "a",
       subtitle = "Scenario forest: Global 2022; ranges span the eight study locations") +
  theme_pa(7.5) +
  theme(axis.text.y = element_text(size = 6.6),
        plot.tag = element_text(size = 9, face = "bold"))

# ---- (b) 留一法 ----
lab_drop <- c(
  BASE_all                      = "Base: all 5 studies",
  DROP_Ekelund2019_harmonised   = "minus Ekelund2019 (hip; anchors device curve)",
  DROP_Tarp2024_harmonised      = "minus Tarp2024 (mixed; anchors device curve)",
  DROP_UKB_wrist_general        = "minus UKB (wrist)",
  DROP_Moore2012_nci_pool       = "minus Moore2012 (self-report)",
  DROP_PURE2017_17countries     = "minus PURE2017 (self-report)")
agg <- loo[, .(fold_min = min(fold, na.rm = TRUE), fold_max = max(fold, na.rm = TRUE),
               n_loc = .N), by = scenario]
glo <- loo[location == "Global", .(scenario, fold_global = fold, paf_global = paf)]
B   <- merge(glo, agg, by = "scenario")
B   <- merge(B, looR[, .(scenario, rr60 = rr_at_off60)], by = "scenario")
B[, supported_arm := scenario %in% c("DROP_Ekelund2019_harmonised",
                                     "DROP_Tarp2024_harmonised")]
B[, lab := unname(lab_drop[scenario])]
if (anyNA(B$lab)) stop("LOO 情景缺少英文标签：", paste(B[is.na(lab)]$scenario, collapse = ", "))
base_fold <- B[scenario == "BASE_all"]$fold_global
B[, swing_pct := 100 * (fold_global / base_fold - 1)]
B[, grp := fifelse(scenario == "BASE_all", "Base",
                   fifelse(supported_arm, "single_arm", "other"))]
B[, a_swing := abs(swing_pct)]
B[, grp_rank := match(grp, c("Base", "single_arm", "other"))]
setorder(B, grp_rank, -a_swing)
want_top2bot <- c("Base: all 5 studies",
                  "minus Ekelund2019 (hip; anchors device curve)",
                  "minus Tarp2024 (mixed; anchors device curve)",
                  "minus PURE2017 (self-report)",
                  "minus UKB (wrist)",
                  "minus Moore2012 (self-report)")
stopifnot(all(want_top2bot %in% B$lab), length(want_top2bot) == nrow(B))
B[, lab := factor(lab, levels = rev(want_top2bot))]
B_COLS <- c(Base = PA_COLS[["study"]], single_arm = PA_COLS[["up"]], other = "grey55")

p6b <- ggplot(B, aes(x = fold_global, y = lab, colour = grp)) +
  geom_vline(xintercept = 1, linetype = "dashed", linewidth = 0.45, colour = "grey30") +
  geom_vline(xintercept = base_fold, linetype = "dotted", linewidth = 0.45,
             colour = PA_COLS[["study"]]) +
  geom_errorbarh(aes(xmin = fold_min, xmax = fold_max), height = 0.20,
                 linewidth = 0.45, colour = "grey60", show.legend = FALSE) +
  geom_point(size = 2.0, shape = 16, show.legend = FALSE) +
  geom_text(aes(label = sprintf("%.2f  (%+.0f%%)", fold_global, swing_pct)),
            vjust = -1.05, size = 1.95, colour = "grey15") +
  scale_colour_manual(values = B_COLS, guide = "none") +
  labs(x = "Fold: recomputed / GBD 2023 reported attributable deaths",
       y = NULL, tag = "b",
       subtitle = "Leave-one-study-out: effect of dropping each contributing study") +
  theme_pa(7.5) +
  theme(axis.text.y = element_text(size = 6.6),
        plot.tag = element_text(size = 9, face = "bold"))

save_combined(p6a | p6b, "Fig6_combined_2panels", 11.2, 4.4)
pa_log("Fig6_combined_2panels 完成")

# ===========================================================================
# Part 2 —— Fig 3 合并版（4 面板）
# ===========================================================================
rr  <- fread(file.path(DIR_OUT, "rr_curves.csv"))
itr <- fread(file.path(DIR_OUT, "Table11_pam_intensity_RR.csv"), encoding = "UTF-8")
itr[, outcome2 := fifelse(outcome == "died", "all_cause", "cvd")]
ref_mims <- fread(file.path(DIR_OUT, "Table2_reference_anchor.csv"), encoding = "UTF-8")
ref_mims <- ref_mims[exposure == "mims_per_day"]$ref_val[1]

# ---- (a)(b) MIMS 两面板（画法同 08c 的 mk_curve 单曲线分支）----------------
mk_mims <- function(oc, tag) {
  d <- rr[outcome == oc]
  ggplot(d, aes(x = x, y = hr)) +
    geom_hline(yintercept = 1, linetype = "dotted", linewidth = 0.4, colour = "grey40") +
    geom_vline(xintercept = ref_mims, linetype = "dashed", linewidth = 0.4, colour = "grey30") +
    annotate("text", x = ref_mims, y = max(d$hi),
             label = sprintf("Reference\n%.0f MIMS/day", ref_mims),
             hjust = -0.05, vjust = 1, size = 1.9, lineheight = 0.95, colour = "grey30") +
    geom_ribbon(aes(ymin = lo, ymax = hi), fill = PA_COLS[["device"]],
                alpha = 0.18, colour = NA) +
    geom_line(linewidth = 0.7, colour = PA_COLS[["device"]]) +
    scale_x_continuous(labels = comma, expand = expansion(mult = c(0.01, 0.02))) +
    scale_y_continuous(expand = expansion(mult = c(0.03, 0.05))) +
    labs(x = "Device-measured activity (MIMS/day)", y = "Hazard ratio (95% CI)", tag = tag) +
    theme_pa(7.5) +
    theme(plot.tag = element_text(size = 9, face = "bold"))
}
pa2 <- mk_mims("all_cause", "a")
pb2 <- mk_mims("cvd",       "b")

# ---- (c)(d) 髋式合并面板（百分位轴）---------------------------------------
mk_hip_combined <- function(oc, tag, legend = FALSE) {
  d <- itr[outcome2 == oc]
  stopifnot(nrow(d) > 0)
  d[, model := factor(fifelse(volume_adjusted, "M1", "M0"), levels = c("M0", "M1"))]
  d[, expo  := factor(
        fifelse(exposure == "peak30_per_day",
                "Peak-30 (counts/min)", "MVPA (min/day)"),
        levels = c("Peak-30 (counts/min)", "MVPA (min/day)"))]
  p <- ggplot(d, aes(x = pct, y = hr,
                     colour = expo, linetype = model,
                     group = interaction(expo, model))) +
    geom_hline(yintercept = 1, linetype = "dotted", linewidth = 0.4, colour = "grey40") +
    geom_vline(xintercept = 12.5, linetype = "dashed", linewidth = 0.4, colour = "grey30") +
    annotate("text", x = 12.5, y = max(d$hi), label = "Reference\n(12.5th pct)",
             hjust = -0.05, vjust = 1, size = 1.9, lineheight = 0.95, colour = "grey30") +
    geom_ribbon(aes(ymin = lo, ymax = hi, fill = expo), alpha = 0.10, colour = NA) +
    geom_line(linewidth = 0.6) +
    scale_colour_manual(values = c("Peak-30 (counts/min)" = PA_COLS[["hip"]],
                                   "MVPA (min/day)"       = PA_COLS[["reported"]]),
                        name = NULL) +
    scale_fill_manual(values = c("Peak-30 (counts/min)" = PA_COLS[["hip"]],
                                 "MVPA (min/day)"       = PA_COLS[["reported"]]),
                      guide = "none") +
    scale_linetype_manual(values = c(M0 = "solid", M1 = "22"),
                          labels = c(M0 = "Unadjusted for volume",
                                     M1 = "Adjusted for volume"),
                          name = NULL) +
    scale_x_continuous(breaks = c(12.5, 37.5, 62.5, 87.5),
                       labels = comma,
                       expand = expansion(mult = c(0.01, 0.02))) +
    scale_y_continuous(expand = expansion(mult = c(0.03, 0.05))) +
    labs(x = "Percentile of the exposure distribution",
         y = "Hazard ratio (95% CI)", tag = tag) +
    theme_pa(7.5) +
    theme(plot.tag = element_text(size = 9, face = "bold"))
  if (legend) p <- p + theme(legend.position = c(0.97, 0.97),
                             legend.justification = c(1, 1),
                             legend.text = element_text(size = 5.4),
                             legend.key.height = unit(0.22, "cm"),
                             legend.background = element_rect(fill = "white",
                               colour = "grey75", linewidth = 0.2))
  else p <- p + theme(legend.position = "none")
  p
}
pc <- mk_hip_combined("all_cause", "c", legend = TRUE)
pd <- mk_hip_combined("cvd",       "d")

fig3c4 <- (pa2 | pb2) / (pc | pd)
save_combined(fig3c4, "Fig3_combined_4panels", 8.6, 6.6)
pa_log("Fig3_combined_4panels 完成")

pa_log("08g 完成（%.1f s）—— 备选拼版已写入 figures/combined/（不镜像 output/）",
       as.numeric(difftime(Sys.time(), t0, units = "secs")))
