# =============================================================================
# 08a_fig1_design.R —— Fig 1：研究设计与三模块分析流程（对标 JAMA 铅论文 Fig 1）
# -----------------------------------------------------------------------------
# 纯绘制（无统计计算）；样本量等数字动态读取，避免流程图与数据漂移。
# 产出：figures/panel/Fig1_study_design.pdf(+png)；figures/combined/Fig1.pdf(+png)
# =============================================================================
t0 <- Sys.time()
source("08_fig_style.R")
pa_log("===== 08a Fig 1 研究设计流程图 =====")

# ---- 动态数字（防流程图与数据脱节；口径与 04 建模集 / 08b Fig2a 完全一致）----
adm <- readRDS(file.path(DIR_DERIV, "analytic.rds"))
b <- copy(adm)[!is.na(surv_mo) & surv_mo > 0]
covars1 <- c("age","female","race","educ","pir","bmi","sbp","cur_smoke","drink_any","diabetes","cvd_hx")
for (v in c("mims_per_day", intersect(covars1, names(b)), "WTMEC4YR")) b <- b[!is.na(get(v))]
n_mod <- nrow(b)
n_dth <- sum(b$died, na.rm = TRUE)
t7 <- tryCatch(fread(file.path(DIR_OUT, "Table7_bop_nhanes_site_sensitivity.csv"), encoding = "UTF-8"),
               error = function(e) NULL)
n_study <- if (is.null(t7)) 5 else t7$spec[1] %||% 5
n_study <- if (is.null(t7)) 5 else unique(t7$n_study)[1]
n_rows  <- if (is.null(t7)) 21 else unique(t7$n_rows)[1]

# ---- 版面 -------------------------------------------------------------------
# 三列：数据源(y=8) -> 模块(y=5) -> 输出(y=2，跨全宽)
CW <- 3.1; CX <- c(1.75, 5.45, 9.15)   # 列中心；x 范围 0-10.9
BX <- function(c) c - CW / 2
box <- data.table(
  x0 = c(BX(CX[1]), BX(CX[2]), BX(CX[3]), BX(CX[1]), BX(CX[2]), BX(CX[3]), 0.7),
  x1 = c(BX(CX[1]) + CW, BX(CX[2]) + CW, BX(CX[3]) + CW,
         BX(CX[1]) + CW, BX(CX[2]) + CW, BX(CX[3]) + CW, 10.2),
  y0 = c(7.3, 7.3, 7.3, 4.15, 4.15, 4.15, 1.35),
  y1 = c(8.8, 8.8, 8.8, 5.95, 5.95, 5.95, 2.5),
  fill = c(rep("grey96", 3), rep("#EAF1F8", 3), "#F3F7F3"),
  lb = c(
    sprintf("NHANES 2011-2014\nDevice-measured activity (MIMS/day)\n+ mortality linkage\n(n = %s adults; %s deaths)", fmt_n(n_mod), fmt_n(n_dth)),
    sprintf("External cohorts (Burden of Proof)\nSelf-reported and device-measured\n(%d studies; %d cohort-specific curves)", n_study, n_rows),
    sprintf("GBD 2023\nExposure distributions +\nattributable burden\n(8 locations; 1990 and 2022)"),
    sprintf("Module 1\nDevice-based dose-response\nWeighted Cox + restricted\ncubic splines\n-> device-scale RR curve\n-> report-to-device calibration"),
    sprintf("Module 2\nPooled RR across cohorts\nMeta-regression with measurement\nmethod as covariate\n-> pooled device-scale RR"),
    sprintf("Module 3\nBurden recomputation\nGBD exposure -> device scale\n-> PAF and attributable\nburden, 1990-2022"),
    sprintf("Recomputed LPA-attributable burden vs GBD 2023 reported\n+ definitional decomposition (TMREL definition / RR magnitude / residual)")))
box[, kind := c(rep("data", 3), rep("module", 3), "output")]
box[, xc := (x0 + x1) / 2][, yc := (y0 + y1) / 2]

arr_v <- data.table(x = CX, y = 7.3, yend = 5.95)
# M1 -> M3：从 M1 底部绕行（框间空隙太窄，直穿会压 Module 2 框）
arr_m13 <- data.table(x = c(CX[1], CX[1], CX[3]), xend = c(CX[1], CX[3], CX[3]),
                      y = c(4.15, 3.55, 3.55), yend = c(3.55, 3.55, 4.15))
arr_m23 <- data.table(x = BX(CX[2]) + CW, xend = BX(CX[3]), y = 5.35, yend = 5.35)
arr_o <- data.table(x = CX[3], y = 4.15, yend = 2.5)

COL_BOX <- c(data = "grey88", module = "#B9CFE4", output = "#BFDCC0")
p1 <- ggplot(box, aes(xc, yc)) +
  geom_rect(aes(xmin = x0, xmax = x1, ymin = y0, ymax = y1, fill = kind),
            colour = "grey20", linewidth = 0.45) +
  geom_text(aes(label = lb), size = 2.25, lineheight = 1.05, colour = "grey10") +
  geom_segment(data = arr_v, aes(x = x, xend = x, y = y, yend = yend),
               arrow = arrow(length = unit(0.09, "cm"), type = "closed"),
               linewidth = 0.5, colour = "grey30", inherit.aes = FALSE) +
  geom_segment(data = arr_m13, aes(x = x, xend = xend, y = y, yend = yend),
               arrow = arrow(length = unit(0.09, "cm"), type = "closed"),
               linewidth = 0.5, colour = "grey30", inherit.aes = FALSE) +
  geom_segment(data = arr_m23, aes(x = x, xend = xend, y = y, yend = yend),
               arrow = arrow(length = unit(0.09, "cm"), type = "closed"),
               linewidth = 0.5, colour = "grey30", inherit.aes = FALSE) +
  geom_segment(data = arr_o, aes(x = x, xend = x, y = y, yend = yend),
               arrow = arrow(length = unit(0.09, "cm"), type = "closed"),
               linewidth = 0.5, colour = "grey30", inherit.aes = FALSE) +
  scale_fill_manual(values = COL_BOX, guide = "none") +
  scale_x_continuous(limits = c(0, 10.9), expand = expansion(mult = c(0, 0))) +
  scale_y_continuous(limits = c(1, 9.3), expand = expansion(mult = c(0, 0))) +
  annotate("text", x = c(CX[1], CX[2], CX[3]), y = 9.1,
           label = c("Device-measured anchor", "Pooled external evidence", "Target population"), size = 2.4,
           fontface = "bold", colour = "grey25") +
  theme_void(base_size = 7) +
  theme(plot.margin = margin(3, 3, 3, 3))

save_panel(p1, "Fig1_study_design", 7.2, 3.9)
save_combined(p1, "Fig1", 7.2, 3.9)

cat(sprintf("流程图数字：n = %s, deaths = %s, 外部队列 %d 研究 %d 条曲线\n",
            fmt_n(n_mod), fmt_n(n_dth), n_study, n_rows))
cat(sprintf("用时 %.1f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
pa_log("08a 完成 -> figures/panel/Fig1_study_design.pdf + figures/combined/Fig1.pdf")
