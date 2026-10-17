# =============================================================================
# 04_cox_dose_response.R
# 加权 Cox + 限制性立方样条：设备测量活动量的剂量-反应曲线
# - 时间尺度：PERMTH_EXM（自 MEC 起月数）
# - 抽样设计：svycoxph（SDMVPSU 聚类 + SDMVSTRA 分层 + WTMEC4YR 权重）
# - 参照点：**绝对锚点 = GBD TMREL 的设备等效值**（TMREL_MID_MIMS，见 00_setup.R §7b）
# 输出：Fig 3 曲线、Table 2 HR 表
# =============================================================================

# ---- 统一引导（勿改）：locale 修复 + 加载 00_setup.R（提供 ROOT/DIR_*/PA_SEED）----
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
  if (is.null(.ps)) stop("未找到 00_setup.R：请 setwd() 到 code/ 目录后重试")
  source(.ps); rm(.ps, .c)
}

suppressPackageStartupMessages({
  library(data.table); library(tidyverse); library(survival); library(survey); library(splines)
})
# ROOT / DIR_DERIV / DIR_OUT 由 00_setup.R 统一提供

adm <- readRDS(file.path(DIR_DERIV, "analytic.rds"))
setDT(adm)

# ---------------------------- 0. 参数 ---------------------------------------
# 参照点口径（2026-10-15 变更）：**绝对锚点 = GBD TMREL 的设备等效值**
#   设计依据：00_完整研究方案.md §237「参照点设在 GBD TMREL 等效水平
#             —— 这是让下游 PAF 可算的关键设定」
#   数值来源：TMREL_MID_MIMS（00_setup.R §7b 单一真源；由 05 的校准回归设备等效化，
#             TMREL 3600–4400 MET-min/wk → 13,168.5–13,275.7，取中 13,222.1）
#   ⚠️ 旧版用 `REF_PCT <- 60` 占位分位（→ 13,936.5 MIMS/day），已被本改动取代。
#      下游 95（RR 来源 B，NHANES 对照臂）用绝对 HR 在人群暴露上插值，
#      故锚点变更会传导到 Module 3 的 NHANES 对照结果 —— 属于预期内的口径统一。
REF_ABS          <- c(mims_per_day = TMREL_MID_MIMS)   # 暴露名 -> 绝对锚点
REF_PCT_FALLBACK <- 60    # 仅用于未登记绝对锚点的暴露（当前无），留有显式提示
KNOTS_DF  <- 4       # RCS 自由度

# 先建结局别名列，再据此确定可用的暴露与结局集合（顺序不可颠倒）
adm[, all_cause := died]
adm[, cvd       := cvd_death]     # 03 中生成的是 cvd_death，此处给出结别名

# 只保留数据中真实存在的列（peak30 需先由 02 生成 peak30.rds 并由 03 合并）
EXPOSURES <- intersect(c("mims_per_day", "peak30"), names(adm))
OUTCOMES  <- intersect(c("all_cause", "cvd"), names(adm))
if (!length(EXPOSURES)) stop("未找到任何暴露列，请先运行 02/03。")
if (!length(OUTCOMES))  stop("未找到任何结局列，请检查死亡文件是否已合并。")
cat("可用暴露:", paste(EXPOSURES, collapse = ", "),
    "| 结局:", paste(OUTCOMES, collapse = ", "), "\n")

# ---------------------------- 1. 建模用数据 --------------------------------
# 完整案例（协变量缺失剔除；实际投稿应做多重插补）
covars <- c("age","female","race","educ","pir","bmi","sbp","cur_smoke","drink_any","diabetes","cvd_hx")
mod_dt <- adm[!is.na(surv_mo) & surv_mo > 0]
# 只按真实存在的列筛选，避免 get() 取到全局环境的同名对象而误清空数据
req <- intersect(c(EXPOSURES, covars, "WTMEC4YR"), names(mod_dt))
for (v in req) mod_dt <- mod_dt[!is.na(get(v))]
cat("建模样本:", nrow(mod_dt), " 全死因死亡:", sum(mod_dt$all_cause, na.rm = TRUE), "\n")

# 设计对象（对所有变量一次性声明）
des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC4YR,
                 nest = TRUE, data = as.data.frame(mod_dt))

# ---------- 1b. 最小充分调整集 vs 全调整（BMI/SBP 可能是部分中介） ----------
sets <- list(
  full   = covars,
  minima = setdiff(covars, c("bmi","sbp"))     # 排除代谢中介的模型
)

# ---------------------------- 2. 曲线估计函数 -------------------------------
fit_rr_curve <- function(expo, outcome, covs, ref_val) {
  d <- mod_dt[[expo]]
  kn <- quantile(d, probs = seq(0, 1, length.out = KNOTS_DF + 1)[-c(1, KNOTS_DF + 1)], na.rm = TRUE)

  # 手动构造样条基，便于做参照点对比
  B  <- ns(d, knots = kn, Boundary.knots = range(d))
  Bref <- predict(B, ref_val)   # 参照点的基值

  dd <- as.data.frame(mod_dt)
  for (j in seq_len(ncol(B))) dd[[paste0("s", j)]] <- B[, j]
  dd$Bref <- NULL
  dd$.expo <- d

  des2 <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC4YR,
                    nest = TRUE, data = dd)

  f <- as.formula(sprintf("Surv(surv_mo, %s) ~ %s + %s",
                          outcome, paste(paste0("s", 1:ncol(B)), collapse = " + "),
                          paste(covs, collapse = " + ")))
  m <- svycoxph(f, design = des2)
  beta <- coef(m)[paste0("s", 1:ncol(B))]
  V    <- vcov(m)[paste0("s", 1:ncol(B)), paste0("s", 1:ncol(B)), drop = FALSE]

  grid <- seq(quantile(d, .01, na.rm = TRUE), quantile(d, .99, na.rm = TRUE), length.out = 200)
  Bg   <- predict(B, grid)
  logHR <- (Bg - matrix(Bref, nrow(Bg), ncol(Bg), byrow = TRUE)) %*% beta
  se    <- sqrt(pmax(diag((Bg - matrix(Bref, nrow(Bg), ncol(Bg), byrow = TRUE)) %*% V %*%
                            t(Bg - matrix(Bref, nrow(Bg), ncol(Bg), byrow = TRUE))), 0))

  # 注意：logHR 是矩阵（200x1），直接塞进 data.table 会把列名变成 hr.V1/lo.V1/hi.V1，
  # 必须显式 as.numeric() 拉平为向量。
  data.table(exposure = expo, outcome = outcome, x = as.numeric(grid),
             hr = as.numeric(exp(logHR)),
             lo = as.numeric(exp(logHR - 1.96 * se)),
             hi = as.numeric(exp(logHR + 1.96 * se)))
}

# ---------------------------- 3. 跑全部组合 ---------------------------------
res <- list(); k <- 0
ref_used <- data.table()   # 锚点台账（供审计；08c 的 Fig3_reference_points.csv 同源）
for (expo in EXPOSURES) {
  rng <- range(mod_dt[[expo]], na.rm = TRUE)
  if (expo %in% names(REF_ABS)) {
    ref_val <- unname(REF_ABS[[expo]])
    if (ref_val < rng[1] || ref_val > rng[2])
      stop(sprintf("参照锚点 %.1f 超出 %s 的观测范围 [%.1f, %.1f]",
                   ref_val, expo, rng[1], rng[2]))
    ref_src <- "TMREL_MID_MIMS (00_setup.R §7b)"
  } else {
    ref_val <- quantile(mod_dt[[expo]], REF_PCT_FALLBACK / 100, na.rm = TRUE)
    ref_src <- sprintf("fallback: P%.1f 分位（该暴露未登记绝对锚点）", REF_PCT_FALLBACK)
    message("  ⚠ ", expo, " 未登记绝对锚点 → ", ref_src)
  }
  ref_used <- rbind(ref_used, data.table(exposure = expo, ref_val = ref_val,
                                         source = ref_src))
  for (oc in OUTCOMES) {
    if (sum(mod_dt[[oc]], na.rm = TRUE) < 30) {
      message("跳过 ", expo, " x ", oc, "（事件数 < 30）"); next
    }
    k <- k + 1
    res[[k]] <- fit_rr_curve(expo, oc, sets$full, ref_val)
    message("完成: ", expo, " x ", oc, " (参照值=", round(ref_val, 1), ")")
  }
}
rr <- rbindlist(res)
if (!nrow(rr)) {
  warning("未得到任何 RR 曲线（可能是事件数不足或暴露列缺失），跳过 Fig3 与 Table2。")
} else {
  fwrite(rr, file.path(DIR_OUT, "rr_curves.csv"))

  # ---------------------------- 4. 图（Fig 3 初版，逐图导出 PDF） -------------
  p <- ggplot(rr, aes(x, hr, color = outcome, fill = outcome)) +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = .2, color = NA) +
    geom_line(linewidth = .8) +
    geom_hline(yintercept = 1, linetype = 2) +
    facet_wrap(~ exposure, scales = "free_x") +
    # 图内标签一律用 ASCII：Windows 图形设备在非 UTF-8 locale 下无法渲染中文字符
    labs(x = "Device-measured activity (MIMS/day or Peak-30 units)", y = "Hazard ratio (95% CI)") +
    theme_classic(base_size = 8) +
    theme(legend.position = "top")
  ggsave(file.path(DIR_OUT, "Fig3_dose_response.pdf"), p, width = 7, height = 3.2)
  ggsave(file.path(DIR_OUT, "Fig3_dose_response.png"), p, width = 7, height = 3.2, dpi = 300)

  # ---------------------------- 5. Table 2：分类 HR --------------------------
  tab2 <- mod_dt[, .(n = .N, deaths = sum(all_cause)), by = mims_q4]
  tab2[, hr_row := paste0(n, " / ", deaths)]
  fwrite(tab2, file.path(DIR_OUT, "Table2_quartile_HK.csv"))

  # ---------------------------- 5b. 参照锚点台账（审计用） -------------------
  fwrite(ref_used, file.path(DIR_OUT, "Table2_reference_anchor.csv"), bom = TRUE)
}

# ---------------------------- 6. 敏感性分析（示例骨架） --------------------
# 见 00_完整研究方案.md 第 6.7 节 9 项；每项改写有效日/切点/协变量集后重跑本脚本。
message("04 完成 -> output/rr_curves.csv + Fig3_dose_response.pdf")
