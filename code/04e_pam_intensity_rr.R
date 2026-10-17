# =============================================================================
# 04e_pam_intensity_rr.R
# 强度指标的剂量-反应与死亡风险：NHANES 2003-2006（髋式，分钟级）
# -----------------------------------------------------------------------------
# 为什么做这个（对应 Fig 3(c)(d)）
#   主分析（Fig 3(a)(b)）用的是**体量型**暴露（腕式 MIMS/day，2011-2014）。
#   审稿人必问：体量够了，**强度**（intensity）是否携带独立信息？
#   本脚本用**已在本机的**分钟级数据（rnhanesdata PAXINTEN_C/D，髋式 ActiGraph 7164）
#   回答这个问题 —— **零下载成本**（CDC 的 PAXMIN_G/H 合计 16.3 GB，见
#   logs/_dl_paxmin.log 与 README「强度维度」节的口径说明）。
#
# 两个强度指标
#   peak30_per_day : 有效日内「活动最高 30 分钟」的 counts/min 均值（**不需要切点**）
#   mvpa_per_day   : 有效日内 counts >= 2020 cpm（Troiano 2008）的分钟数均值
#   ⚠️ 髋式 counts/min 的切点有外部验证；腕式 MIMS **没有**权威切点 ——
#      这正是本周期能提供而 2011-2014 周期不能提供的东西。
#
# 关键设计：三层模型（这是本脚本的核心，不是可选装饰）
#   M0  未调整体量：COVARS                 → 总效应（与 Fig 3(a)(b) 同构）
#   M1  **调整体量**：COVARS + ns(counts_per_day, 4) → 强度的**独立**效应
#   M2  调整体量的分类模型（四分位）→ 供 Table 与 P-trend
#   为什么必须做 M1：实测 peak-30 与 counts_per_day 的 Pearson r = 0.82
#   → 未调整的强度曲线**大部分是体量曲线的复述**；只有 M1 才回答
#     「同等总活动量下，把活动集中在少数高峰时段是否额外获益」。
#
#   ⚠️ 体量口径必须三处**完全一致**（2026-10-15 统一，此前是三个不同口径，
#      导致 MVPA 独立效应出现方向性矛盾）：
#        · RCS 曲线      : ns(counts_per_day, df = 4)
#        · per-IQR 对比  : 从**同一个 RCS 模型**做线性对比（不再另拟合线性模型）
#        · 四分位 M2     : ns(counts_per_day, df = 4)
#      统一后三者只差「强度项的函数形式（样条 / 线性对比 / 分类）」，
#      任何残余分歧都能干净地归因到函数形式本身，而不是被体量口径混淆。
#
# 口径对齐
#   COVARS / KNOTS_DF / PCT_GRID 与 04、04b **逐字一致**。
#   参照点：本脚本用**加权 12.5 百分位**（与 04b / BoP 的 ref_canon 一致）——
#   因为 TMREL 定义在总 MET-min/周上，只能唯一映射到**体量**尺度（04 的
#   mims_per_day，用绝对锚点 TMREL_MID_MIMS），无法唯一映射到 peak-30/MVPA
#   这类强度尺度，故强度侧统一退回分位口径。
#
# 产物
#   output/Table11_pam_intensity_RR.csv          曲线网格（供 Fig 3(c)(d)）
#   output/Table11_pam_intensity_quartiles.csv   四分位 HR + P-trend
#   output/QC_pam_intensity_fit.csv              样本量/事件数/拟合诊断/相关性矩阵
# =============================================================================

# ---- 统一引导 -----------------------------------------------------------------
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8"))
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
})
if (!isTRUE(getOption("PA_SETUP_DONE"))) {
  .ps <- NULL
  for (.c in c("00_setup.R", file.path(getwd(), "00_setup.R"))) {
    if (!is.null(.c) && nzchar(.c) && file.exists(.c)) { .ps <- normalizePath(.c); break }
  }
  if (is.null(.ps)) stop("未找到 00_setup.R：请 setwd() 到 code/ 目录后重试")
  source(.ps); rm(.ps, .c)
}
suppressPackageStartupMessages({
  library(data.table); library(survey); library(splines)
})
pa_log("===== 04e 强度指标（peak-30 / MVPA）剂量-反应 =====")

REF_PCT  <- 12.5   # 与 04 / 04b / BoP 的 ref_canon 一致
KNOTS_DF <- 4      # RCS 自由度，与 04 / 04b 一致
COVARS   <- c("age","female","race","educ","pir","bmi","sbp",
              "cur_smoke","drink_any","diabetes","cvd_hx")
PCT_GRID <- c(12.5, 22.5, 32.5, 42.5, 52.5, 62.5, 72.5, 82.5, 92.5)
Z975 <- 1.959964

# 暴露清单：主 = peak30 与 MVPA(2020)；敏感性 = MVPA(1952, Freedson) 与 VPA
EXPO_LIST <- c(peak30_per_day   = "Peak-30 (counts/min)",
               mvpa_per_day     = "MVPA >= 2020 cpm (min/day)",
               mvpa1952_per_day = "MVPA >= 1952 cpm (min/day)",
               vpa_per_day      = "VPA >= 5999 cpm (min/day)")

# ---- 加权分位数（与 04b 同实现）---------------------------------------------
wq <- function(x, w, p) {
  ok <- !is.na(x) & !is.na(w) & w > 0
  x <- x[ok]; w <- w[ok]
  o <- order(x); x <- x[o]; w <- w[o]
  approx(cumsum(w) / sum(w), x, xout = p, rule = 2)$y
}

# =============================================================================
# 1. 分析集
# =============================================================================
d <- as.data.table(readRDS(file.path(DIR_DERIV, "pam_2003_2006.rds")))
# CVD 死亡：UCOD_LEADING 1 = 心脏病，5 = 脑血管病（NHANES LMF 公开版编码）
d[, cvd := ifelse(is.na(died), NA_integer_,
           ifelse(died == 1L,
                  ifelse(is.na(UCOD_LEADING), NA_integer_,
                         as.integer(UCOD_LEADING %in% c(1L, 5L))),
                  0L))]
cat(sprintf("分析集 %d 人 | 全因死亡 %d | CVD 死亡 %d（UCOD 缺失 %d 例已从 CVD 分析剔除）\n",
            nrow(d), sum(d$died == 1, na.rm = TRUE), sum(d$cvd == 1, na.rm = TRUE),
            sum(is.na(d$cvd))))

# --- 硬校验：强度指标必须全部重建成功，否则静默丢样本 ---
for (v in names(EXPO_LIST)) {
  if (!v %in% names(d)) stop("缺少强度指标列：", v, "（请先跑通 03b 新增版本）")
  if (anyNA(d[[v]])) warning(sprintf("%s 有 %d 个缺失（已剔除）", v, sum(is.na(d[[v]]))))
}

# --- 相关性矩阵：判断「强度是否只是体量的复述」（这是 M1 存在的理由）---
cormat <- cor(d[, .(peak30_per_day, mvpa_per_day, vpa_per_day, counts_per_day)],
              use = "pairwise.complete.obs")
cat("\n--- 相关性矩阵（Pearson）---\n"); print(round(cormat, 3))
corsp <- cor(d[, .(peak30_per_day, mvpa_per_day, vpa_per_day, counts_per_day)],
             method = "spearman", use = "pairwise.complete.obs")
cat("--- Spearman ---\n"); print(round(corsp, 3))

# =============================================================================
# 2. 拟合函数
# =============================================================================
# 一次拟合一条曲线；`adj_volume = TRUE` 时把总活动量作为**自然样条**同时纳入
# （用样条而非线性是为了避免"体量-死亡非线性"残差泄漏到强度系数里）
fit_curve <- function(dt, expo, outcome, adj_volume, label) {
  md <- copy(dt[!is.na(get(expo)) & !is.na(surv_mo) & surv_mo > 0])
  md <- md[!is.na(get(outcome))]
  if (adj_volume) md <- md[!is.na(counts_per_day)]
  for (v in c(COVARS, "WTMEC4YR", "SDMVPSU", "SDMVSTRA")) md <- md[!is.na(get(v))]
  if (!nrow(md)) stop(label, "：样本为空")

  nev <- sum(md[[outcome]] == 1, na.rm = TRUE)
  cat(sprintf("\n[%s] n = %d | 事件 %d\n", label, nrow(md), nev))
  if (nrow(md) < 200 || nev < 50) stop(label, "：样本或事件过少，结果不可靠")

  x  <- md[[expo]]
  kn <- quantile(x, probs = seq(0, 1, length.out = KNOTS_DF + 1)[-c(1, KNOTS_DF + 1)],
                 na.rm = TRUE)
  B  <- ns(x, knots = kn, Boundary.knots = range(x))
  ref_val <- wq(x, md$WTMEC4YR, REF_PCT / 100)
  Bref    <- predict(B, ref_val)

  dd <- as.data.frame(md)
  for (j in seq_len(ncol(B))) dd[[paste0("s", j)]] <- B[, j]
  if (adj_volume) {
    Bv <- ns(md$counts_per_day, df = KNOTS_DF)
    for (j in seq_len(ncol(Bv))) dd[[paste0("v", j)]] <- Bv[, j]
  }
  des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC4YR,
                   nest = TRUE, data = dd)
  # ⚠️ 必须 collapse：直接 paste(paste0("s",1:4), ...) 会得到长度 4 的字符向量，
  #    as.formula 只取第一个 → 同时 vcov() 按名取 s1..s4 会 "subscript out of bounds"。
  rhs <- paste(c(paste0("s", 1:ncol(B)), COVARS,
                 if (adj_volume) paste0("v", 1:ncol(B))), collapse = " + ")
  f <- as.formula(sprintf("Surv(surv_mo, %s) ~ %s", outcome, rhs))
  m <- svycoxph(f, design = des)
  beta <- coef(m)[paste0("s", 1:ncol(B))]
  V    <- vcov(m)[paste0("s", 1:ncol(B)), paste0("s", 1:ncol(B)), drop = FALSE]
  if (anyNA(beta)) stop(label, "：样条系数含 NA（设计矩阵秩亏）")

  grid  <- wq(x, md$WTMEC4YR, PCT_GRID / 100)
  Bg    <- predict(B, grid)
  Dmat  <- Bg - matrix(Bref, nrow(Bg), ncol(Bg), byrow = TRUE)
  loghr <- as.numeric(Dmat %*% beta)
  se    <- sqrt(rowSums((Dmat %*% V) * Dmat))

  # ---- per-IQR 对比：直接从**同一个 RCS 模型**提取（单一模型、单一数字）------
  #   旧做法（2026-10-15 前）：另拟合一个 log-linear 模型
  #     Surv ~ expo + COVARS + counts_per_day
  #   它既与曲线**不是同一模型**（强度指数线性 vs 样条），**体量口径也不同**
  #   （线性 vs 4 df 样条）→ 对本研究最关键的 MVPA 给出方向性矛盾：
  #     曲线（样条体量）HR(55.5 vs 2.7 min) = 0.47 (0.27, 0.82) **显著**
  #     per-IQR（线性体量）                  = 1.06 (0.84, 1.34) **无效**
  #   二者并列引用会被审稿人直接抓住（同一问题两个相反答案）。
  #   现改为对**曲线本身**做线性对比：HR(ref + IQR) / HR(ref)，delta 法给 CI。
  #   定义与 log-linear 的 exp(beta × IQR) 完全对应，只是不做指数线性约束。
  iqr  <- diff(wq(x, md$WTMEC4YR, c(.25, .75)))
  x_hi <- ref_val + iqr
  if (x_hi > max(x)) {
    # 不外推：超出观测上界时显式告警并记 NA，绝不静默给数
    warning(sprintf("%s：ref+IQR = %.1f 超出观测上界 %.1f → per-IQR 对比不可估",
                    label, x_hi, max(x)))
    lin <- c(estimate = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
             iqr = iqr)
  } else {
    D     <- as.numeric(predict(B, x_hi) - Bref)   # 1×p 对比向量
    lh    <- sum(D * beta)
    se_lh <- sqrt(as.numeric(t(D) %*% V %*% D))
    lin <- c(estimate = exp(lh),
             lo = exp(lh - Z975 * se_lh),
             hi = exp(lh + Z975 * se_lh),
             p = 2 * pnorm(-abs(lh / se_lh)), iqr = iqr)
  }

  list(n = nrow(md), n_event = nev, pct = PCT_GRID, value = grid,
       hr = exp(loghr), lo = exp(loghr - Z975 * se), hi = exp(loghr + Z975 * se),
       ref_val = ref_val, knots = kn, lin = lin, expo = expo, outcome = outcome,
       adj_volume = adj_volume, label = label)
}

# =============================================================================
# 3. 跑全部组合
# =============================================================================
combos <- rbindlist(lapply(names(EXPO_LIST), function(ex) data.table(
  expo = ex, label = unname(EXPO_LIST[ex]),
  outcome = c("died", "cvd", "died", "cvd"),
  adj_volume = c(TRUE, TRUE, FALSE, FALSE))))
# 主面板（Fig 3c/d）= peak-30 与 MVPA 的「调整体量后」曲线；其余为敏感性

fits <- list(); fit_fail <- list()
for (i in seq_len(nrow(combos))) {
  cb <- combos[i]
  oc_lab <- ifelse(cb$outcome == "died", "all_cause", "cvd")
  lb <- sprintf("%s | %s | %s", cb$label, oc_lab,
                ifelse(cb$adj_volume, "volume-adjusted", "unadjusted"))
  key <- paste(cb$expo, oc_lab, ifelse(cb$adj_volume, "Vadj", "raw"), sep = "|")
  r <- tryCatch(fit_curve(d, cb$expo, cb$outcome, cb$adj_volume, lb),
                error = function(e) e)
  if (inherits(r, "error")) {
    fit_fail[[key]] <- conditionMessage(r)
    message("  ⛔ 不可估：", lb, " → ", conditionMessage(r))
  } else fits[[key]] <- r
}
if (length(fit_fail)) {
  cat("\n--- 不可估的组合（须在正文/附录显式声明，不能静默丢弃）---\n")
  for (k in names(fit_fail)) cat(sprintf("  %-40s %s\n", k, fit_fail[[k]]))
  # VPA 不可估的机理：中位数为 0 min/day（高度零膨胀）→ 样条基近奇异
  vpa_zero <- mean(d$vpa_per_day == 0, na.rm = TRUE)
  cat(sprintf("  · VPA(>=5999 cpm) 中零值占比 %.1f%%、加权中位数 %.0f min/day → 不适合做样条 RCS\n",
              100 * vpa_zero, wq(d$vpa_per_day, d$WTMEC4YR, .5)))
}

# --- 曲线网格 ---
curve_tab <- rbindlist(lapply(fits, function(f) data.table(
  exposure = f$expo, outcome = f$outcome,
  volume_adjusted = f$adj_volume,
  exposure_label = EXPO_LIST[[f$expo]],
  n = f$n, n_event = f$n_event,
  pct = f$pct, value = f$value, hr = f$hr, lo = f$lo, hi = f$hi,
  ref_value = f$ref_val)))
fwrite(curve_tab, file.path(DIR_OUT, "Table11_pam_intensity_RR.csv"))

# --- per-IQR 汇总 ---
lin_tab <- rbindlist(lapply(fits, function(f) data.table(
  exposure = f$expo, exposure_label = EXPO_LIST[[f$expo]], outcome = f$outcome,
  volume_adjusted = f$adj_volume, n = f$n, n_event = f$n_event,
  iqr = f$lin[["iqr"]], hr_per_iqr = f$lin[["estimate"]],
  lo = f$lin[["lo"]], hi = f$lin[["hi"]], p = f$lin[["p"]],
  ref_value = f$ref_val)))
fwrite(lin_tab, file.path(DIR_OUT, "Table11_pam_intensity_per_IQR.csv"))

# =============================================================================
# 4. 四分位分类模型（Table + P-trend）
# =============================================================================
qrows <- list()
for (ex in names(EXPO_LIST)) {
  for (oc in c("died", "cvd")) {
    for (adj in c(FALSE, TRUE)) {
      md <- copy(d[!is.na(get(ex)) & !is.na(surv_mo) & surv_mo > 0 & !is.na(get(oc))])
      if (adj) md <- md[!is.na(counts_per_day)]
      for (v in c(COVARS, "WTMEC4YR", "SDMVPSU", "SDMVSTRA")) md <- md[!is.na(get(v))]
      qs <- quantile(md[[ex]], probs = 0:4/4, na.rm = TRUE)
      if (length(unique(qs)) < 5L) { message("  ", ex, " 分位点重复，跳过四分位模型"); next }
      md[, qx := cut(get(ex), breaks = qs, include.lowest = TRUE, labels = paste0("Q", 1:4))]
      md[, qxn := as.integer(qx)]
      # ⚠️ 不要用 I(qx=='Q2') 这类写法：R 反解出的系数名用的是**双引号**
      #    （I(qx == "Q2")TRUE），用单引号做名字匹配会静默匹配不到 → 四分位表空表。
      #    改为显式哑变量列，名字 q2/q3/q4 确定无疑。
      for (q in 2:4) md[[paste0("q", q)]] <- as.integer(md$qx == paste0("Q", q))
      if (anyNA(md$q2) || anyNA(md$q3) || anyNA(md$q4)) next
      # ---- 体量调整口径与曲线**一致**：4 df 自然样条（2026-10-15 统一）--------
      #   旧版此处用线性 counts_per_day，而 fit_curve 用 ns(counts_per_day, 4)
      #   → 同一篇论文里 RCS 曲线与四分位表对"独立效应"给出相反结论
      #     （MVPA 体量调整后：曲线 0.47 显著 vs 四分位 0.76 / P-trend 0.47 平坦）。
      #   现统一为样条，使三种参数化只差「强度项的函数形式」，体量口径恒定。
      #   ⚠️ 必须建在 md 上（而非 dd）：下方 des 与 des2 各自 svydesign，
      #      二者都必须能看到 v1..v4，否则 P-trend 那步会 object not found。
      if (adj) {
        Bv <- ns(md$counts_per_day, df = KNOTS_DF)
        for (j in seq_len(ncol(Bv))) md[[paste0("v", j)]] <- Bv[, j]
      }
      dd <- as.data.frame(md)
      des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC4YR,
                       nest = TRUE, data = dd)
      cov_rhs <- paste(c(COVARS, if (adj) paste0("v", 1:KNOTS_DF)), collapse = " + ")
      m <- svycoxph(as.formula(sprintf("Surv(surv_mo, %s) ~ q2 + q3 + q4 + %s",
                                       oc, cov_rhs)), design = des)
      cf <- coef(m); sf <- sqrt(diag(vcov(m)))
      for (q in 2:4) {
        nm <- paste0("q", q)
        if (!nm %in% names(cf)) next
        qrows[[length(qrows) + 1L]] <- data.table(
          exposure = ex, exposure_label = EXPO_LIST[[ex]], outcome = oc,
          volume_adjusted = adj, quartile = paste0("Q", q),
          hr = exp(cf[[nm]]), lo = exp(cf[[nm]] - Z975 * sf[[nm]]),
          hi = exp(cf[[nm]] + Z975 * sf[[nm]]),
          p = 2 * pnorm(-abs(cf[[nm]] / sf[[nm]])),
          q_range = sprintf("%.0f-%.0f", qs[q], qs[q + 1]), n = nrow(md))
      }
      # P-trend：四分位中位数作为连续变量
      md[, qmed := qs[as.integer(qx)]]
      des2 <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC4YR,
                        nest = TRUE, data = as.data.frame(md))
      mt <- svycoxph(as.formula(sprintf("Surv(surv_mo, %s) ~ qmed + %s", oc, cov_rhs)),
                     design = des2)
      cft <- coef(mt); sft <- sqrt(diag(vcov(mt)))
      qrows[[length(qrows) + 1L]] <- data.table(
        exposure = ex, exposure_label = EXPO_LIST[[ex]], outcome = oc,
        volume_adjusted = adj, quartile = "P for trend",
        hr = NA_real_, lo = NA_real_, hi = NA_real_,
        p = 2 * pnorm(-abs(cft[["qmed"]] / sft[["qmed"]])),
        q_range = NA_character_, n = nrow(md))
    }
  }
}
qtab <- rbindlist(qrows)
fwrite(qtab, file.path(DIR_OUT, "Table11_pam_intensity_quartiles.csv"))

# =============================================================================
# 5. QC
# =============================================================================
qc <- data.table(
  item = c("分析集人数", "全因死亡", "CVD 死亡（UCOD 1/5）", "UCOD 缺失（CVD 分析剔除）",
           "peak-30 与总量 Pearson r", "peak-30 与总量 Spearman r",
           "MVPA 与总量 Pearson r", "MVPA 与总量 Spearman r",
           "peak-30 加权中位数", "MVPA 加权中位数"),
  value = c(nrow(d), sum(d$died == 1, na.rm = TRUE), sum(d$cvd == 1, na.rm = TRUE),
            sum(d$died == 1 & is.na(d$UCOD_LEADING)),
            round(cormat["peak30_per_day", "counts_per_day"], 3),
            round(corsp["peak30_per_day", "counts_per_day"], 3),
            round(cormat["mvpa_per_day", "counts_per_day"], 3),
            round(corsp["mvpa_per_day", "counts_per_day"], 3),
            round(wq(d$peak30_per_day, d$WTMEC4YR, .5), 0),
            round(wq(d$mvpa_per_day, d$WTMEC4YR, .5), 0)),
  note = c("", "", "", "died==1 但 UCOD_LEADING 缺失者不进 CVD 模型",
           "0.82 → 强度曲线大部分是体量曲线的复述，必须做 volume-adjusted",
           "同上（秩相关）", "", "", "counts/min", "min/day"))
fwrite(qc, file.path(DIR_OUT, "QC_pam_intensity_fit.csv"))

# =============================================================================
# 6. 报告
# =============================================================================
cat("\n===== 强度指标的 per-IQR 风险比 =====\n")
print(lin_tab[order(exposure, outcome, -volume_adjusted),
              .(exposure, outcome, volume_adjusted, n, n_event,
                hr_per_iqr = sprintf("%.2f (%.2f, %.2f)", hr_per_iqr, lo, hi),
                p = signif(p, 2))])

cat("\n===== 主面板（Fig 3(c)(d)）关键结论 =====\n")
for (ex in c("peak30_per_day", "mvpa_per_day")) {
  a <- lin_tab[exposure == ex & outcome == "died" & volume_adjusted == FALSE]
  b <- lin_tab[exposure == ex & outcome == "died" & volume_adjusted == TRUE]
  cat(sprintf("%-18s 未调整体量: %.2f (%.2f, %.2f) p=%.3g\n", ex, a$hr_per_iqr, a$lo, a$hi, a$p))
  cat(sprintf("%-18s 调整体量后: %.2f (%.2f, %.2f) p=%.3g  ← 是否独立于体量\n",
              "", b$hr_per_iqr, b$lo, b$hi, b$p))
}

cat("\n--- 四分位（主：peak-30 / MVPA，调整体量）---\n")
print(qtab[volume_adjusted == TRUE & exposure %in% c("peak30_per_day", "mvpa_per_day")],
      nrows = 40)
pa_log("04e 完成 -> Table11_pam_intensity_RR.csv / _quartiles.csv / _per_IQR.csv + QC")
