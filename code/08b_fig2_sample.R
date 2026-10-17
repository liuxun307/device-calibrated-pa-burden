# =============================================================================
# 08b_fig2_sample.R —— Fig 2：样本流程 + 自报/设备活动量对比
# -----------------------------------------------------------------------------
# (a) 样本筛选流程图（NHANES 2011–2014 加速度计 → 建模集）
# (b) 自报（MET-min/wk）与设备（MIMS/day）活动量分布（加权密度，各自尺度 + 阈值线 + 达标比例）
# (c) 自报 LPA 分类 × 设备活动量四分位 的加权交叉热图（行百分比）
#
# 数据：data/derived/{accel_daily,analytic}.rds；阈值取自 05 校准（TMREL 设备等效）
# 产出：figures/panel/Fig2{a,b,c}_*.pdf(+png)；figures/combined/Fig2.pdf(+png)
#       output/Fig2a_flow_numbers.csv（node / n / deaths / cvd_deaths）
#         ★ 2026-10-16 新增 deaths 列：为图注的「两段式样本口径」提供落盘来源。
#           两段 = ① 设备样本（年龄 ≥ 25、有效加速度计；= Table 1 的描述对象）
#                  ② 多变量 Cox 分析集（完整协变量 + 有效随访；= Table 2 的拟合样本）
#           两者此前都被称作 "modelling sample"，属口径混淆；10_captions.R 现将
#           两段各自的 N 与死亡数分别陈述，**数值一律从本产物读取，不得手写**。
#         ★ 2026-10-16 再新增 cvd_deaths 列：Results R1 / Discussion L4 需引用
#           「Cox 分析集中 207 例心血管死亡」，该值此前**无任何产物来源**
#           （只存在于诊断脚本的控制台输出）→ 现与 deaths 同口径一并落盘，
#           并纳入 10_captions.R 的跨脚本自检（08b ↔ 09 独立推导，逐值比对）。
# 运行：cd code && Rscript 08b_fig2_sample.R            # ~10 s
# =============================================================================
t0 <- Sys.time()
source("08_fig_style.R")
pa_log("===== 08b Fig 2 样本与暴露分布 =====")

adm <- readRDS(file.path(DIR_DERIV, "analytic.rds")); setDT(adm)
acc <- readRDS(file.path(DIR_DERIV, "accel_daily.rds"))

# =============================================================================
# 1. 流程图数字（全部动态计算，不硬编码）
# =============================================================================
# ① 原始：PAXDAY（G/H）有记录的**唯一参与者**（PAXDAY 是人-日级，必须去重 SEQN）
raw_n <- {
  s <- integer(0)
  for (cy in c("G", "H")) {
    f <- file.path(DIR_RAW, sprintf("PAXDAY_%s.xpt", cy))
    if (file.exists(f)) s <- c(s, haven::read_xpt(f, col_select = "SEQN")$SEQN)
  }
  length(unique(s))
}
n_valid <- nrow(acc)                 # 有效日判据后
n_age25 <- nrow(adm)                 # 年龄 >= 25

# 建模集：04 的口径（完整案例 + 有效随访）
b <- copy(adm)[!is.na(surv_mo) & surv_mo > 0]
covars <- c("age","female","race","educ","pir","bmi","sbp","cur_smoke","drink_any","diabetes","cvd_hx")
for (v in c("mims_per_day", intersect(covars, names(b)), "WTMEC4YR")) b <- b[!is.na(get(v))]
n_model <- nrow(b)

# ---- 两段式样本的死亡数（2026-10-16 新增）-----------------------------------
# 为何需要：Table 1 描述的是「完整协变量限制之前」的设备样本（n = n_age25），
#   而 Table 2 的 Cox 模型跑在完整案例集（n = n_model）上。图注统一改为两段式
#   表述后，两段各自的死亡数都必须有**产物来源**（禁止在 10_captions.R 里手写）。
# 口径：died 为 0/1 死亡指示（analytic.rds 自带）；此处只做未加权计数求和，
#   与 Table 1 的 `Deaths` 行同口径（09_tables.R 亦用 sum(all_cause) 未加权计数）。
if (!"died" %in% names(adm)) stop("analytic.rds 缺少 died 列：无法给出两段式样本的死亡数")
n_deaths_age25 <- sum(adm$died, na.rm = TRUE)   # ① 设备样本（= Table 1 的 Overall deaths）
n_deaths_model <- sum(b$died,   na.rm = TRUE)   # ② 多变量 Cox 分析集

# ---- 心血管死亡数（2026-10-16 追加）----------------------------------------
# 为何需要：Results R1 与 Discussion L4 都要引用「Cox 分析集中 207 例心血管死亡」，
#   该值此前**没有任何产物来源**（只在诊断脚本 code/tools/_probe_m21_numbers.R 的
#   控制台输出里），违反本方案「正文数字一律有产物来源」的硬性标准。
# 口径：cvd_death 为 0/1 心血管死亡指示（analytic.rds 自带，= UCOD_LEADING 1 或 5）；
#   仅作未加权计数求和，与 died 同口径。
if (!"cvd_death" %in% names(adm)) stop("analytic.rds 缺少 cvd_death 列：无法给出心血管死亡数")
n_cvd_age25 <- sum(adm$cvd_death, na.rm = TRUE)   # ① 设备样本的 CVD 死亡
n_cvd_model <- sum(b$cvd_death,   na.rm = TRUE)   # ② 多变量 Cox 分析集的 CVD 死亡

ex <- c(sprintf("Excluded (n = %s):\n<4 valid days or\n<10 h/day wear", fmt_n(raw_n - n_valid)),
        sprintf("Excluded (n = %s):\naged < 25 years", fmt_n(n_valid - n_age25)),
        sprintf("Excluded (n = %s):\nmissing covariates\nor follow-up", fmt_n(n_age25 - n_model)))

nodes <- data.table(
  y = c(4, 3, 2, 1),
  lab = c(sprintf("NHANES 2011-2014\naccelerometry participants\n(N = %s)", fmt_n(raw_n)),
          sprintf("Valid accelerometry\n(>=4 valid days,\n>=10 h/day wear)\nN = %s", fmt_n(n_valid)),
          sprintf("Adults aged >= 25 years\nN = %s", fmt_n(n_age25)),
          sprintf("Complete covariates\nand follow-up\nN = %s", fmt_n(n_model))))
nodes[, `:=`(xmin = 0, xmax = 2.6, ym = y, y0 = y - 0.29, y1 = y + 0.29)]
excl <- data.table(y = c(3.5, 2.5, 1.5), lab = ex,
                   xmin = 2.95, xmax = 5.5, y0 = c(3.5,2.5,1.5) - 0.235, y1 = c(3.5,2.5,1.5) + 0.235)
arr_v <- data.table(x = 1.3, y = c(3.71, 2.71, 1.71), yend = c(3.29, 2.29, 1.29))
arr_h <- data.table(x = 2.6, xend = 2.95, y = c(3.5, 2.5, 1.5))

p_a <- ggplot() +
  geom_rect(data = nodes, aes(xmin = xmin, xmax = xmax, ymin = y0, ymax = y1),
            fill = "white", colour = "grey20", linewidth = 0.4) +
  geom_rect(data = excl, aes(xmin = xmin, xmax = xmax, ymin = y0, ymax = y1),
            fill = "grey96", colour = "grey45", linewidth = 0.35, linetype = "dashed") +
  geom_segment(data = arr_v, aes(x = x, xend = x, y = y, yend = yend),
               arrow = arrow(length = unit(0.07, "cm"), type = "closed"),
               linewidth = 0.4, colour = "grey25") +
  geom_segment(data = arr_h, aes(x = x, xend = xend, y = y, yend = y),
               arrow = arrow(length = unit(0.07, "cm"), type = "closed"),
               linewidth = 0.35, colour = "grey45", linetype = "dashed") +
  geom_text(data = nodes, aes(x = (xmin + xmax) / 2, y = ym, label = lab),
            size = 2.35, lineheight = 1.0, colour = "grey10") +
  geom_text(data = excl, aes(x = (xmin + xmax) / 2, y = (y0 + y1) / 2, label = lab),
            size = 2.05, lineheight = 1.0, colour = "grey35") +
  scale_x_continuous(limits = c(-0.1, 5.6)) +
  scale_y_continuous(limits = c(0.5, 4.5)) +
  labs(tag = "a", subtitle = "Participant flow") +
  theme_void(base_size = 7) +
  theme(plot.subtitle = element_text(size = 7.5, face = "bold", hjust = 0, colour = "grey10"),
        plot.tag = element_text(size = 9, face = "bold"),
        plot.margin = margin(2, 2, 2, 2))

# =============================================================================
# 2. (b) 活动量分布（加权密度，各自尺度）
# =============================================================================
TMREL_MIMS <- {
  t4 <- fread(file.path(DIR_OUT, "Table4_m3_decomp.csv"), encoding = "UTF-8")
  t4[location == "Global" & scenario == "S0_base", tmrel_mims][1]
}
GUIDE_MET <- 600

d1 <- adm[!is.na(met_min_wk), .(v = met_min_wk, w = WTMEC4YR)]
d2 <- adm[!is.na(mims_per_day), .(v = mims_per_day, w = WTMEC4YR)]
dens <- function(v, w, from, to, n = 512) {
  de <- density(v, weights = w / sum(w), from = from, to = to, n = n, na.rm = TRUE)
  data.table(x = de$x, y = de$y)
}
# 自报用 log10(x+1) 尺度（右偏严重且含 0），设备用线性尺度
b1 <- dens(log10(d1$v + 1), d1$w, 0, log10(max(d1$v) + 1))
b2 <- dens(d2$v, d2$w, min(d2$v), max(d2$v))
rate_sr <- wmean(d1$v >= GUIDE_MET, d1$w) * 100
rate_dv <- wmean(d2$v <  TMREL_MIMS, d2$w) * 100

mk_dens <- function(d, xlab, cut, cutlab, note, colour, tag) {
  rng <- diff(range(d$x))
  ggplot(d, aes(x, y)) +
    geom_area(fill = colour, alpha = 0.28, colour = NA) +
    geom_line(linewidth = 0.55, colour = colour) +
    geom_vline(xintercept = cut, linetype = "dashed", linewidth = 0.4, colour = "grey25") +
    geom_text(data = data.frame(x = cut + 0.02 * rng, y = max(d$y) * 0.97, lab = cutlab),
              aes(x, y, label = lab), hjust = 0, vjust = 1, size = 2.05, colour = "grey30") +
    scale_x_continuous(expand = expansion(mult = c(0, 0.02))) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
    labs(x = xlab, y = "Weighted density", tag = tag, subtitle = note) +
    theme_pa(7.5) +
    theme(plot.subtitle = element_text(size = 7.2, colour = "grey20", hjust = 0),
          plot.tag = element_text(size = 9, face = "bold"))
}
p_b1 <- mk_dens(b1, expression("Self-reported activity, log"[10]*"(MET-min/week + 1)"),
                log10(GUIDE_MET + 1), "600 MET-min/wk",
                sprintf("Meets WHO guideline (weighted): %.1f%%", rate_sr), PA_COLS[["reported"]], "b")
p_b2 <- mk_dens(b2, "Device-measured activity (MIMS/day)",
                TMREL_MIMS, "TMREL",
                sprintf("Below TMREL (weighted): %.1f%%", rate_dv), PA_COLS[["device"]], NULL)

# =============================================================================
# 3. (c) 自报分类 × 设备四分位（加权行百分比）
# =============================================================================
ct <- adm[!is.na(lpa_gbd_cat) & !is.na(mims_q4),
          .(n = .N, wsum = sum(WTMEC4YR, na.rm = TRUE)),
          by = .(sr = lpa_gbd_cat, dev = mims_q4)]
lv_sr <- intersect(c("inactive", "low", "moderate", "high"), unique(ct$sr))
ct[, sr := factor(sr, levels = lv_sr)]
ct[, dev := factor(dev, levels = paste0("Q", 1:4))]
ct[, pct := 100 * wsum / sum(wsum), by = sr]           # 行百分比（加权）
ct[, nlab := ifelse(pct >= 6, sprintf("%.1f%%\n(%s)", pct, fmt_n(n)), sprintf("%.1f%%", pct))]

lab_sr <- c(inactive = "Inactive\n(0 MET-min/wk)", low = "Low\n(1-599)", moderate = "Moderate\n(600-1199)", high = "High\n(>=1200)")

p_c <- ggplot(ct, aes(dev, sr, fill = pct)) +
  geom_tile(colour = "white", linewidth = 0.6) +
  geom_text(aes(label = nlab), size = 2.15, lineheight = 0.92, colour = "grey10") +
  scale_fill_gradient(low = "#F0F6FB", high = "#0B4F6C", guide = "none") +
  scale_y_discrete(labels = lab_sr) +
  labs(x = "Device-measured activity quartile (MIMS/day)", y = "Self-reported activity",
       tag = "c", subtitle = "Row percentages (weighted)") +
  theme_pa(7.5) +
  theme(axis.text.x = element_text(size = 6.6),
        axis.text.y = element_text(size = 6.6, lineheight = 0.95),
        plot.subtitle = element_text(size = 6.8),
        plot.tag = element_text(size = 9, face = "bold"))

# =============================================================================
# 4. 导出：每个 panel 独立 PDF + 拼合整图
# =============================================================================
save_panel(p_a,  "Fig2a_screening_flow",              3.4, 3.3)
save_panel(p_b1, "Fig2b1_reported_density",           3.4, 2.7)
save_panel(p_b2, "Fig2b2_device_density",             3.4, 2.7)
save_panel(p_c,  "Fig2c_reported_vs_device_crosstab", 3.6, 2.9)

# 拼合：左列 (a) 跨两行；(b) 的两个子图竖排在中列；(c) 跨两行在最右
fig2 <- p_a + p_b1 + p_b2 + p_c +
  plot_layout(design = "ABC\nADC", widths = c(1.30, 1.00, 1.12))
save_combined(fig2, "Fig2", 7.2, 3.9)

# =============================================================================
# 5. 数据表落盘（可复核）
# =============================================================================
fwrite(ct[, .(sr, dev, n, wsum, pct)], file.path(DIR_OUT, "Fig2c_crosstab_weighted.csv"), bom = TRUE)

# ★ 2026-10-16 新增：为 Results R2 引用的两个「总体暴露摘要」比例提供独立产物来源。
#   此前 61.7%（自报达指南）与 51.1%（设备低于 TMREL）只打印在控制台，
#   不满足「正文每个引用数字都有落盘出处」的最严口径；
#   交叉表派生的 67.0% / 23.4% / 29.2% 已可由 Fig2c_crosstab_weighted.csv 直接复算，故不重复落盘。
if (!nrow(d1) || !nrow(d2)) stop("Fig2(b) 暴露摘要：自报或设备有效值行数为 0，无法计算加权比例")
w_sr <- sum(d1$w, na.rm = TRUE)   # 自报比例判定的加权基数
w_dv <- sum(d2$w, na.rm = TRUE)   # 设备比例判定的加权基数
if (!is.finite(rate_sr) || !is.finite(rate_dv)) stop("Fig2(b) 暴露摘要：加权比例非有限值")
fwrite(data.table(
  metric         = c("Meets WHO guideline (self-reported, weighted)",
                     "Below TMREL (device-measured, weighted)"),
  pct_weighted   = c(round(rate_sr, 4), round(rate_dv, 4)),
  n_unweighted   = c(nrow(d1), nrow(d2)),
  w_sum          = c(round(w_sr, 2), round(w_dv, 2)),
  threshold      = c(GUIDE_MET, TMREL_MIMS),
  threshold_unit = c("MET-min/wk", "MIMS/day")),
  file.path(DIR_OUT, "Fig2b_exposure_summary.csv"), bom = TRUE)

fwrite(data.table(
  node   = c("PAXDAY records", "Valid accelerometry", "Aged >= 25", "Modelling sample"),
  n      = c(raw_n, n_valid, n_age25, n_model),
  # deaths 仅对两个「分析样本」有定义：前置两个节点是记录/筛查计数，
  # 尚未限定到有死亡随访链接的人群 → 写 NA（不写 0，避免被误读为「无死亡」）。
  deaths = c(NA_integer_, NA_integer_, n_deaths_age25, n_deaths_model),
  # ★ 2026-10-16 新增 cvd_deaths 列：为 Results R1 / Discussion L4 引用的
  #   「Cox 分析集中 207 例心血管死亡」提供产物来源（此前该值无落盘出处）。
  #   口径同 deaths：仅对两个分析样本有定义，未加权计数。
  cvd_deaths = c(NA_integer_, NA_integer_, n_cvd_age25, n_cvd_model)),
  file.path(DIR_OUT, "Fig2a_flow_numbers.csv"), bom = TRUE)

cat("\n--- Fig 2 关键数字 ---\n")
cat(sprintf("流程：%s -> %s -> %s -> %s\n", fmt_n(raw_n), fmt_n(n_valid), fmt_n(n_age25), fmt_n(n_model)))
cat(sprintf("两段式样本口径：① 设备样本（年龄 >= 25）%s 人 / %s 例死亡（含心血管 %s 例）；② 多变量 Cox 分析集（完整协变量 + 有效随访）%s 人 / %s 例死亡（含心血管 %s 例）\n",
            fmt_n(n_age25), fmt_n(n_deaths_age25), fmt_n(n_cvd_age25),
            fmt_n(n_model), fmt_n(n_deaths_model), fmt_n(n_cvd_model)))
cat(sprintf("自报达指南（>=600 MET-min/wk，加权）：%.1f%%\n", rate_sr))
cat(sprintf("设备低于 TMREL（%.0f MIMS/day，加权）：%.1f%%\n", TMREL_MIMS, rate_dv))
cat(sprintf("用时 %.1f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
pa_log("08b 完成 -> figures/panel/Fig2*.pdf + figures/combined/Fig2.pdf")
