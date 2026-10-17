# =============================================================================
# 08d_fig4_calibration.R —— Fig 4：自报 <-> 设备校准（核心创新图）
# -----------------------------------------------------------------------------
# (a) 自报 MET-min/wk 与设备 MIMS/day 的校准：散点 + 单调化校准曲线 + TMREL 区间
# (b) 「低体力活动」患病率：自报口径（校准前）vs 设备口径（校准后），按年龄 x 性别
# (c) 报告偏倚：自报分类各组的设备活动量加权均值（自报高估的直观量化）
#
# 数据：data/derived/analytic.rds；校准模型与 05 Part A1 完全同式（就地重拟合，
#       ~2 s，避免 source 整个 05）；关键量与 Table4 主链值做一致性对照并落 QC。
# 产出：figures/panel/Fig4{a,b,c}_*.pdf(+png)；figures/combined/Fig4.pdf(+png)
#       output/QC_08d_calibration_check.csv
# =============================================================================
t0 <- Sys.time()
source("08_fig_style.R")
pa_log("===== 08d Fig 4 校准 =====")

adm <- readRDS(file.path(DIR_DERIV, "analytic.rds")); setDT(adm)

# =============================================================================
# 1. 校准模型（与 05 Part A1 同式：ns(met,3) + age*female；cummax 强制单调）
# =============================================================================
cal <- adm[!is.na(met_min_wk) & !is.na(mims_per_day) & RIDAGEYR >= 25]
m_cal <- lm(mims_per_day ~ splines::ns(met_min_wk, 3) + age * female, data = cal)
r2    <- summary(m_cal)$r.squared
sig   <- sd(residuals(m_cal))

MET_CAP  <- max(cal$met_min_wk, na.rm = TRUE) * 1.5
MET_ANCH <- seq(0, MET_CAP, length.out = 2000)
.pm_raw  <- function(met) {
  nd <- data.frame(met_min_wk = met, age = median(cal$age), female = 0)
  as.numeric(predict(m_cal, newdata = nd))
}
.pm_mono  <- cummax(.pm_raw(MET_ANCH))
pred_mims <- function(met) approx(MET_ANCH, .pm_mono, xout = met, rule = 2)$y

tmrel_lo_mims <- pred_mims(3600); tmrel_hi_mims <- pred_mims(4400)
TMREL_MID <- (tmrel_lo_mims + tmrel_hi_mims) / 2

# 与主链（97 -> Table4）对照：口径漂移必须显式可见
t4 <- fread(file.path(DIR_OUT, "Table4_m3_decomp.csv"), encoding = "UTF-8")
tmrel_main <- t4[location == "Global" & scenario == "S0_base", tmrel_mims][1]
qc <- data.table(
  item = c("calib_R2", "resid_SD", "n_cal", "tmrel_lo_mims", "tmrel_hi_mims",
           "tmrel_mid_08d", "tmrel_mid_Table4", "abs_diff"),
  value_08d   = c(r2, sig, nrow(cal), tmrel_lo_mims, tmrel_hi_mims, TMREL_MID, NA, NA),
  value_chain = c(NA, NA, NA, NA, NA, NA, tmrel_main, abs(TMREL_MID - tmrel_main)))
fwrite(qc, file.path(DIR_OUT, "QC_08d_calibration_check.csv"), bom = TRUE)
if (abs(TMREL_MID - tmrel_main) > 50) {
  warning(sprintf("校准中点 %.0f 与主链 %.0f 差 %.0f MIMS（>50），请核对 05 是否已改模型式",
                  TMREL_MID, tmrel_main, abs(TMREL_MID - tmrel_main)))
}
pa_log(sprintf("校准 R2=%.3f 残差SD=%.0f TMREL设备等效 %.0f-%.0f（中点 %.0f vs 主链 %.0f）",
               r2, sig, tmrel_lo_mims, tmrel_hi_mims, TMREL_MID, tmrel_main))

# =============================================================================
# 2. (a) 散点 + 校准曲线
# =============================================================================
set.seed(20261015)
pts <- cal[sample(.N, min(1400, .N)), .(met = met_min_wk, mims = mims_per_day)]
curve_dt <- data.table(met = seq(0, 22000, length.out = 400))
curve_dt[, mims := pred_mims(met)]

p_a <- ggplot() +
  geom_point(data = pts, aes(met, mims), size = 0.32, alpha = 0.22,
             colour = "grey45", shape = 16) +
  geom_line(data = curve_dt, aes(met, mims), linewidth = 0.75, colour = PA_COLS[["device"]]) +
  geom_rect(aes(xmin = 3600, xmax = 4400, ymin = -Inf, ymax = Inf),
            fill = PA_COLS[["reported"]], alpha = 0.14, colour = NA) +
  geom_segment(aes(x = 3600, xend = 4400, y = tmrel_lo_mims, yend = tmrel_hi_mims),
               linewidth = 0.7, colour = PA_COLS[["reported"]], linetype = "dashed") +
  annotate("text", x = 900, y = 26500, hjust = 0, vjust = 1, size = 2.1,
           colour = "grey30", lineheight = 0.95,
           label = sprintf("TMREL 3600-4400\n-> %.0f-%.0f MIMS/day", tmrel_lo_mims, tmrel_hi_mims)) +
  annotate("text", x = 21000, y = min(pts$mims), hjust = 1, vjust = 0, size = 2.3,
           colour = "grey15", label = sprintf("Calibration R^2 = %.2f; residual SD = %.0f", r2, sig)) +
  coord_cartesian(xlim = c(0, 22000)) +
  scale_x_continuous(labels = comma, expand = expansion(mult = c(0, 0.02))) +
  scale_y_continuous(labels = comma, expand = expansion(mult = c(0.03, 0.05))) +
  labs(x = "Self-reported activity (MET-min/week)", y = "Device-measured activity (MIMS/day)",
       tag = "a", subtitle = "Individuals (grey) vs monotone calibration curve (blue)") +
  theme_pa(7.5) +
  theme(plot.tag = element_text(size = 9, face = "bold"))

# =============================================================================
# 3. (b) LPA 患病率：自报口径 vs 设备口径（按年龄 x 性别，加权）
# =============================================================================
adm[, agegrp := cut(age, breaks = c(24, 39, 59, Inf), labels = c("25-39", "40-59", "60+"))]
prev <- adm[!is.na(agegrp) & !is.na(female),
            .(prev_sr  = wmean(met_min_wk < 4000, WTMEC4YR) * 100,       # 自报口径（TMREL 中点 4000）
              prev_dev = wmean(mims_per_day < TMREL_MID, WTMEC4YR) * 100, # 设备口径
              n = .N),
            by = .(agegrp, female)]
prev[, sex := factor(ifelse(female == 1, "Women", "Men"), levels = c("Men", "Women"))]
pv <- prev[, .(agegrp, sex, prev_sr, prev_dev)]
setnames(pv, c("prev_sr", "prev_dev"), c("Self-reported", "Device-measured"))
pl <- melt(pv, id.vars = c("agegrp", "sex"), variable.name = "metric", value.name = "pct")

p_b <- ggplot(pl, aes(agegrp, pct, fill = metric)) +
  geom_col(position = position_dodge(0.72), width = 0.66,
           colour = "grey25", linewidth = 0.25) +
  geom_text(aes(label = sprintf("%.0f", pct)),
            position = position_dodge(0.72), vjust = -0.35, size = 2.0, colour = "grey20") +
  facet_wrap(~ sex, nrow = 1) +
  scale_fill_manual(values = c("Self-reported" = PA_COLS[["reported"]],
                               "Device-measured" = PA_COLS[["device"]]),
                    guide = "none") +
  scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 25), expand = expansion(mult = c(0, 0))) +
  labs(x = "Age group (years)", y = "Prevalence of low physical activity (%)",
       tag = "b", subtitle = "Self-reported vs device-calibrated definition") +
  theme_pa(7.5) +
  theme(plot.tag = element_text(size = 9, face = "bold"))

# =============================================================================
# 4. (c) 报告偏倚：自报分类各组的设备活动量（加权均值）
# =============================================================================
sr_lv <- c("inactive", "low", "moderate", "high")
bias <- adm[!is.na(lpa_gbd_cat) & !is.na(mims_per_day),
            .(mims_mean = wmean(mims_per_day, WTMEC4YR),
              n = .N), by = lpa_gbd_cat]
bias[, lpa_gbd_cat := factor(lpa_gbd_cat, levels = sr_lv)]
bias[, lab := sprintf("%.0f\n(%s)", mims_mean, fmt_n(n))]

p_c <- ggplot(bias, aes(lpa_gbd_cat, mims_mean, fill = lpa_gbd_cat)) +
  geom_col(width = 0.62, colour = "grey25", linewidth = 0.25,
           fill = PA_COLS[["reported"]], alpha = 0.85) +
  geom_text(aes(label = lab), vjust = -0.18, size = 2.0, lineheight = 0.95, colour = "grey20") +
  geom_hline(yintercept = TMREL_MID, linetype = "dashed", linewidth = 0.4, colour = "grey30") +
  annotate("text", x = 0.55, y = max(bias$mims_mean) * 1.16, hjust = 0, size = 2.0,
           colour = "grey30", label = "dashed: TMREL (device-equivalent)") +
  scale_y_continuous(limits = c(0, max(bias$mims_mean) * 1.24), labels = comma,
                     expand = expansion(mult = c(0, 0))) +
  scale_x_discrete(labels = c("Inactive\n(0)", "Low\n(1-599)", "Moderate\n(600-1199)", "High\n(>=1200)")) +
  labs(x = "Self-reported activity category (MET-min/week)",
       y = "Device-measured activity (MIMS/day)",
       tag = "c", subtitle = "Weighted mean by self-reported group") +
  theme_pa(7.5) +
  theme(plot.tag = element_text(size = 9, face = "bold"))

# =============================================================================
# 5. 导出
# =============================================================================
save_panel(p_a, "Fig4a_calibration_scatter", 3.4, 3.0)
save_panel(p_b, "Fig4b_lpa_prevalence",      3.5, 3.0)
save_panel(p_c, "Fig4c_reporting_bias",      3.4, 3.0)
fig4 <- (p_a | p_b | p_c) + plot_layout(nrow = 1)
save_combined(fig4, "Fig4", 10.4, 3.2)

cat("\n--- Fig 4 关键数字 ---\n")
print(prev[, .(sex, agegrp, self_reported = round(prev_sr, 1), device = round(prev_dev, 1), n)])
cat(sprintf("报告偏倚（自报 inactive vs high 的设备均值差）：%.0f vs %.0f MIMS/day\n",
            bias[lpa_gbd_cat == "inactive", mims_mean], bias[lpa_gbd_cat == "high", mims_mean]))
cat(sprintf("校准对照：08d 中点 %.0f vs 主链 %.0f（差 %.0f MIMS）\n",
            TMREL_MID, tmrel_main, abs(TMREL_MID - tmrel_main)))
cat(sprintf("用时 %.1f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
pa_log("08d 完成 -> figures/panel/Fig4*.pdf + figures/combined/Fig4.pdf")
