# =============================================================================
# 08f_fig6_sensitivity.R —— Fig 6：敏感性分析三面板
# -----------------------------------------------------------------------------
# (a) 情景森林图      ：12 个 Module 3 情景的 Global fold + 8 地区范围（Table9）
# (b) 留一法（LOO）   ：逐篇剔除外部队列后的 fold 摆动（Table12_m3_loo_paf /
#                       Table12_bop_loo_RR）—— 检验"整条设备总量曲线只由
#                       Ekelund2019 + Tarp2024 两篇支撑"这一外部效度风险有多大
# (c) E-value         ：结论需多强的未测混杂才能被推翻（Table13_evalues，
#                       由 05f_evalues.R 产出；主口径 = HR→RR 近似后的保守值）
#
# 三个面板回答的是三个**不同**的问题，缺一不可：
#   (a) 口径选择带来的不确定性（我们自己的建模选择）
#   (b) 外部证据构成带来的不确定性（别人的研究取舍）
#   (c) 未测混杂带来的不确定性（观察性设计的固有上限）
#
# 产出：figures/panel/Fig6{a,b,c}_*.pdf(+png)；figures/combined/Fig6.pdf(+png)
# =============================================================================
t0 <- Sys.time()
source("08_fig_style.R")
pa_log("===== 08f Fig 6 敏感性分析（a 情景 / b 留一法 / c E-value）=====")

# ---------------------------------------------------------------------------
# 数据
# ---------------------------------------------------------------------------
t9  <- fread(file.path(DIR_OUT, "Table9_m3_scenario_summary.csv"), encoding = "UTF-8")
loo <- fread(file.path(DIR_OUT, "Table12_m3_loo_paf.csv"),      encoding = "UTF-8")
looR<- fread(file.path(DIR_OUT, "Table12_bop_loo_RR.csv"),      encoding = "UTF-8")
ev  <- fread(file.path(DIR_OUT, "Table13_evalues.csv"),         encoding = "UTF-8")

# ===========================================================================
# Panel (a) 情景森林图
# ===========================================================================
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
miss <- t9[is.na(lab), scenario]
if (length(miss)) stop("情景缺少英文标签映射：", paste(miss, collapse = ", "))

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
save_panel(p6a, "Fig6a_scenario_forest", 5.6, 4.2)

# ===========================================================================
# Panel (b) 留一法（leave-one-study-out）
# ===========================================================================
# 每情景：Global fold（点）+ 4 个地区 fold 的 min–max（横线）
looR[, dropped_study := as.character(dropped_study)]
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
# 排序：基准在最上，其后为"支撑设备曲线的两篇"（按 |摆动| 降序），再其余
base_fold <- B[scenario == "BASE_all"]$fold_global
B[, swing_pct := 100 * (fold_global / base_fold - 1)]
B[, grp := fifelse(scenario == "BASE_all", "Base",
                   fifelse(supported_arm, "single_arm", "other"))]
B[, a_swing := abs(swing_pct)]           # setorder 不接受表达式，先落列
B[, grp_rank := match(grp, c("Base", "single_arm", "other"))]
setorder(B, grp_rank, -a_swing)
# y 轴顺序（显式，不依赖行序）：ggplot 把 levels[1] 画在**最底**，
# 故"期望自上而下"的顺序需 rev() 后作为 levels。
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
  scale_x_continuous(expand = expansion(mult = c(0.06, 0.16))) +
  labs(x = "Fold: recomputed / GBD 2023 reported attributable deaths (Global 2022)",
       y = NULL, tag = "b",
       subtitle = "Leave-one-study-out; bars = range across the four study locations") +
  theme_pa(7.5) +
  theme(axis.text.y = element_text(size = 6.2),
        plot.tag = element_text(size = 9, face = "bold"))
save_panel(p6b, "Fig6b_leave_one_out", 5.6, 3.0)

# ===========================================================================
# Panel (c) E-value
# ===========================================================================
# 选 8 行：腕式总量（Model 2，4 行）+ 强度-体量独立（每 IQR，4 行）
EV <- ev[(panel_group == "volume_wrist" & model == "Model 2 (fully adjusted)") |
         (panel_group == "intensity_independent" & contrast == "per IQR")]
if (nrow(EV) != 8L) stop("E-value 面板应为 8 行，实得 ", nrow(EV))

ev_lab <- c(
  M1_wrist_AC_M2_Q4vQ1       = "Total PA (wrist), Q4 vs Q1 - all-cause",
  M1_wrist_CVD_M2_Q4vQ1      = "Total PA (wrist), Q4 vs Q1 - CVD",
  M1_wrist_AC_M2_perIQR      = "Total PA (wrist), per IQR - all-cause",
  M1_wrist_CVD_M2_perIQR     = "Total PA (wrist), per IQR - CVD",
  PEAK30_AC_perIQR_voladj    = "Peak-30 (vol-adj), per IQR - all-cause",
  PEAK30_CVD_perIQR_voladj   = "Peak-30 (vol-adj), per IQR - CVD",
  MVPA_AC_perIQR_voladj      = "MVPA (vol-adj), per IQR - all-cause",
  MVPA_CVD_perIQR_voladj     = "MVPA (vol-adj), per IQR - CVD")
EV[, lab := unname(ev_lab[id])]
if (anyNA(EV$lab)) stop("E-value 面板缺少标签：", paste(EV[is.na(lab)]$id, collapse = ", "))
# y 轴自上而下：总量 4 行、Peak-30 2 行、MVPA 2 行
ord <- c("M1_wrist_AC_M2_Q4vQ1", "M1_wrist_AC_M2_perIQR",
         "M1_wrist_CVD_M2_Q4vQ1", "M1_wrist_CVD_M2_perIQR",
         "PEAK30_AC_perIQR_voladj", "PEAK30_CVD_perIQR_voladj",
         "MVPA_AC_perIQR_voladj", "MVPA_CVD_perIQR_voladj")
# 期望自上而下：腕式总量 4 行 → Peak-30 2 行 → MVPA 2 行（levels 需 rev）
want_top2bot_c <- unname(ev_lab[ord])
stopifnot(length(want_top2bot_c) == nrow(EV), all(want_top2bot_c %in% EV$lab))
EV[, lab := factor(lab, levels = rev(want_top2bot_c))]
EV[, grp := ifelse(grepl("^PEAK30", id), "peak30",
                   ifelse(grepl("^MVPA", id), "mvpa", "volume"))]
EV_COLS <- c(volume = PA_COLS[["device"]], peak30 = PA_COLS[["hip"]], mvpa = "grey50")

p6c <- ggplot(EV, aes(x = e_point_primary, y = lab, colour = grp)) +
  geom_vline(xintercept = 1, linetype = "dashed", linewidth = 0.45, colour = "grey30") +
  geom_segment(aes(x = e_ci_primary, xend = e_point_primary, yend = lab),
               linewidth = 0.5, show.legend = FALSE) +
  geom_point(aes(x = e_ci_primary), size = 1.3, shape = 124, show.legend = FALSE) +
  geom_point(size = 2.0, shape = 16, show.legend = FALSE) +
  geom_text(aes(label = sprintf("%.2f", e_point_primary)), vjust = -1.0, size = 2.0,
            colour = "grey15") +
  scale_colour_manual(values = EV_COLS, guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0.08, 0.16))) +
  labs(x = "E-value: minimum confounder association strength to explain away the HR",
       y = NULL, tag = "c",
       subtitle = "E-value (dot) and its CI-based bound (vertical notch); HR -> RR approximated") +
  theme_pa(7.5) +
  theme(axis.text.y = element_text(size = 6.0),
        plot.tag = element_text(size = 9, face = "bold"))
save_panel(p6c, "Fig6c_evalue", 5.6, 2.6)

# ===========================================================================
# 拼合整图
# ===========================================================================
p6 <- p6a | (p6b / p6c)
save_combined(p6, "Fig6", 11.2, 6.3)

# ---- 交付层镜像（与 07_fig5d_waterfall.R 同惯例）：figures/ -> output/ --------
#   figures/panel|combined 是 panel-by-panel 的可编辑版本；output/ 是
#   98 的 KEY_OUT 跟踪的**交付产物**。字节级复制（cairo_pdf 的字节由 E 层豁免）。
for (nm in c("Fig6a_scenario_forest", "Fig6b_leave_one_out", "Fig6c_evalue"))
  for (ex in c("pdf", "png"))
    if (!file.copy(file.path(FIG_PANEL, paste0(nm, ".", ex)),
                   file.path(DIR_OUT, paste0(nm, ".", ex)), overwrite = TRUE))
      stop("交付层镜像失败：", nm, ".", ex)
for (ex in c("pdf", "png"))
  if (!file.copy(file.path(FIG_COMBINED, paste0("Fig6.", ex)),
                 file.path(DIR_OUT, paste0("Fig6.", ex)), overwrite = TRUE))
    stop("交付层镜像失败：Fig6.", ex)
pa_log("  交付层镜像 -> output/Fig6{a,b,c,_}*.pdf|png")

# ===========================================================================
# 控制台摘要
# ===========================================================================
cat("\n--- Fig 6(a) 情景（Global 2022）---\n")
print(t9[order(role), .(scenario, role, fold = round(fold_global, 2),
                        band = sprintf("%.2f-%.2f", fold_min, fold_max))])
cat("\n--- Fig 6(b) 留一法（Global 2022）---\n")
print(B[order(lab), .(scenario, n_loc, rr60 = round(rr60, 3),
                      fold = round(fold_global, 3),
                      swing_pct = round(swing_pct, 1),
                      band = sprintf("%.2f-%.2f", fold_min, fold_max))])
cat("\n--- Fig 6(c) E-value ---\n")
print(EV[order(lab), .(id, hr = round(hr, 3), E_point = e_point_primary,
                       E_ci = e_ci_primary, E_point_direct = e_point_direct)])

cat("\n—— 结论 ——\n")
cat(sprintf("(b) 剔除 Ekelund2019 → fold %.2f（%+.0f%%）；剔除 Tarp2024 → fold %.2f（%+.0f%%）。\n",
            B[scenario == "DROP_Ekelund2019_harmonised"]$fold_global,
            B[scenario == "DROP_Ekelund2019_harmonised"]$swing_pct,
            B[scenario == "DROP_Tarp2024_harmonised"]$fold_global,
            B[scenario == "DROP_Tarp2024_harmonised"]$swing_pct))
mx <- B[scenario != "BASE_all"][which.max(abs(swing_pct))]
cat(sprintf("    最大摆动 = %.1f%%（%s）→ 结论方向不变，但幅度依赖设备曲线的两篇来源。\n",
            mx$swing_pct, mx$scenario))
cat(sprintf("(c) 最强证据的 E 值：%s = %.2f（CI 界 %.2f）。\n",
            EV[which.max(e_point_primary)]$id, max(EV$e_point_primary),
            EV[which.max(e_point_primary)]$e_ci_primary))
cat(sprintf("    MVPA 体量调整后 CI 跨 1 → E(CI) = 1，即无需任何未测混杂即可解释。\n"))

cat(sprintf("用时 %.1f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
pa_log("08f 完成 -> figures/panel/Fig6{a,b,c}_*.pdf + figures/combined/Fig6.pdf")
