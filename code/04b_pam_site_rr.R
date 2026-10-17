# =============================================================================
# 04b_pam_site_rr.R
# 佩戴部位效应：NHANES 髋式（2003-2006）vs 腕式（2011-2014）的 PA→死亡 RR 曲线
# -----------------------------------------------------------------------------
# 为什么这样做（而不是外推别人的曲线）
#   本研究的暴露侧是腕式设备（MIMS/day），GBD 暴露侧也是腕式，而 Module 2 现有池化
#   总量曲线只有髋式/混合佩戴部位来源。"腕式曲线能不能用髋式曲线替代" 是本方案最
#   容易被审稿人质疑的一环。最干净的答复是：**用同一个国家、同一调查体系的两套
#   实测数据，在同一套协变量定义下各估一条曲线**，然后把两者放到同一个「人群百分位」
#   轴上比较差异。
#
# 关键设计（三条，缺一不可）
#   ① 协变量定义逐字一致：两条曲线都只用
#      age, female, race(5 类), educ, pir, bmi, sbp, cur_smoke, drink_any, diabetes, cvd_hx
#      · 2011-2014 的 RIDRETH3（拆出 Asian）**折叠为 5 类**，与 2003-2006 的 RIDRETH1 对齐
#      · 因此腕式曲线在这里是**重新拟合**的，不是直接引用 Fig3 那条
#   ② 暴露量纲不同（counts/min vs MIMS）→ 不做绝对值比较，全部映射到
#      「各自人群的百分位」。参照点取 **12.5 百分位**（= 最低四分位中点），
#      与 Module 2 的 ref_canon = 12.5 完全一致 → 曲线可直接作为 BoP 池的两条新研究。
#   ③ 部位效应的不确定性：两个周期是**独立样本**，系数向量独立。
#      从各自的渐近正态 N(beta, V) 各抽 B=1000 组系数 → 得到
#      log(RR_wrist) − log(RR_hip) 的抽样分布 → 比值的 95% 区间。
#
# 输出
#   output/Table6_nhanes_hip_wrist_RR.csv  两条曲线（百分位轴）+ 部位效应比值
#   output/Table6_pam_percentile_map.csv   百分位 ↔ 暴露值 的映射（供 Fig/审稿人复核）
#   output/QC_pam_site_fit.csv             拟合诊断（样本量/事件数/系数是否收敛）
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
  library(data.table); library(survey); library(splines); library(MASS)
})
pa_log("===== 04b 佩戴部位效应：髋式(2003-2006) vs 腕式(2011-2014) =====")

REF_PCT   <- 12.5   # 参照百分位 = 最低四分位中点，与 BoP 的 ref_canon 一致
KNOTS_DF  <- 4      # RCS 自由度（与 04 一致）
N_DRAWS   <- as.integer(Sys.getenv("PA_N_DRAWS_SITE", unset = "1000"))
PCT_GRID  <- c(12.5, 22.5, 32.5, 42.5, 52.5, 62.5, 72.5, 82.5, 92.5)  # → offset 0..80
COVARS    <- c("age","female","race","educ","pir","bmi","sbp",
               "cur_smoke","drink_any","diabetes","cvd_hx")
set.seed(PA_SEED + 11L)

# ---- 加权分位数（不引第三方依赖）---------------------------------------------
wq <- function(x, w, p) {
  ok <- !is.na(x) & !is.na(w) & w > 0
  x <- x[ok]; w <- w[ok]
  o <- order(x); x <- x[o]; w <- w[o]
  cw <- cumsum(w) / sum(w)
  approx(cw, x, xout = p, rule = 2)$y
}

# =============================================================================
# 1. 两条分析集，协变量定义对齐
# =============================================================================
# --- 髋式：2003-2006 ---
hip <- as.data.table(readRDS(file.path(DIR_DERIV, "pam_2003_2006.rds")))
hip[, expo := counts_per_day]
hip[, site := "hip (ActiGraph 7164, counts/min)"]

# --- 腕式：2011-2014（重新拟合，把 RIDRETH3 折叠为 5 类）---
wri <- as.data.table(readRDS(file.path(DIR_DERIV, "analytic.rds")))
RIDRETH3_TO_5 <- c(`1`="Mexican American", `2`="Other Hispanic", `3`="NH White",
                   `4`="NH Black", `5`="Other", `6`="Other", `7`="Other")
wri[, race5 := factor(RIDRETH3_TO_5[as.character(as.integer(as.character(race)))],
                      levels = c("Mexican American","Other Hispanic","NH White",
                                 "NH Black","Other"))]
wri[, race := race5]
wri[, expo := mims_per_day]
wri[, site := "wrist (GT3X+, MIMS/day)"]

for (nm in c("hip","wri")) {
  d <- get(nm)
  need <- c("expo", COVARS, "WTMEC4YR", "SDMVPSU", "SDMVSTRA", "surv_mo", "died")
  miss <- setdiff(need, names(d))
  # 2003-2006 的年龄列名不同（无 RIDAGEYR 别名问题：已在 03b 生成 age）
  if (length(miss)) {
    if ("age" %in% miss && "RIDAGEYR" %in% names(d)) d[, age := RIDAGEYR]
    miss <- setdiff(need, names(d))
  }
  if (length(miss)) stop(nm, " 缺少字段: ", paste(miss, collapse = ", "))
  assign(nm, d)
}

# =============================================================================
# 2. 拟合函数（svycoxph + 自然样条，参照点可指定）
# =============================================================================
fit_curve <- function(dt, label) {
  md <- dt[!is.na(surv_mo) & surv_mo > 0]
  for (v in c("expo", COVARS, "WTMEC4YR")) md <- md[!is.na(get(v))]
  md <- copy(md)
  cat(sprintf("\n[%s] 建模样本 %d 人 | 死亡 %d\n", label, nrow(md), sum(md$died == 1, na.rm = TRUE)))
  if (nrow(md) < 200 || sum(md$died == 1, na.rm = TRUE) < 50) stop(label, "：样本或事件过少")

  d  <- md$expo
  kn <- quantile(d, probs = seq(0, 1, length.out = KNOTS_DF + 1)[-c(1, KNOTS_DF + 1)], na.rm = TRUE)
  B  <- ns(d, knots = kn, Boundary.knots = range(d))

  ref_val <- wq(d, md$WTMEC4YR, REF_PCT / 100)     # 参照点：加权 12.5 百分位
  Bref    <- predict(B, ref_val)

  dd <- as.data.frame(md)
  for (j in seq_len(ncol(B))) dd[[paste0("s", j)]] <- B[, j]
  des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC4YR,
                   nest = TRUE, data = dd)
  f <- as.formula(sprintf("Surv(surv_mo, died) ~ %s + %s",
                          paste(paste0("s", 1:ncol(B)), collapse = " + "),
                          paste(COVARS, collapse = " + ")))
  m  <- svycoxph(f, design = des)
  beta <- coef(m)[paste0("s", 1:ncol(B))]
  V    <- vcov(m)[paste0("s", 1:ncol(B)), paste0("s", 1:ncol(B)), drop = FALSE]

  # 百分位网格 → 对应暴露值 → 样条基
  grid_mims <- wq(d, md$WTMEC4YR, PCT_GRID / 100)
  Bg   <- predict(B, grid_mims)
  Dmat <- Bg - matrix(Bref, nrow(Bg), ncol(Bg), byrow = TRUE)

  loghr <- as.numeric(Dmat %*% beta)
  list(label = label, n = nrow(md), n_death = sum(md$died == 1, na.rm = TRUE),
       beta = beta, V = V, Dmat = Dmat, pct = PCT_GRID, expo = grid_mims,
       ref_val = ref_val, loghr = loghr, knots = kn, fit = m)
}

FIT_HIP <- fit_curve(hip, "NHANES 2003-2006 髋式")
FIT_WRI <- fit_curve(wri, "NHANES 2011-2014 腕式")

# =============================================================================
# 3. 部位效应：独立样本系数抽样 → 比值分布
# =============================================================================
draw_loghr <- function(fit) {
  B <- MASS::mvrnorm(N_DRAWS, mu = fit$beta, Sigma = fit$V)
  B %*% t(fit$Dmat)          # N_DRAWS × n_pct
}
LH_HIP <- draw_loghr(FIT_HIP)
LH_WRI <- draw_loghr(FIT_WRI)
DIFF   <- LH_WRI - LH_HIP    # log(RR_wrist) − log(RR_hip)

q <- function(x, p) as.numeric(quantile(x, p, na.rm = TRUE))
res <- data.table(
  pct      = FIT_HIP$pct,
  offset_pts = FIT_HIP$pct - REF_PCT,
  expo_hip   = round(FIT_HIP$expo, 1),
  expo_wrist = round(FIT_WRI$expo, 1),
  rr_hip     = exp(FIT_HIP$loghr),
  rr_hip_lo  = exp(apply(LH_HIP, 2, q, p = 0.025)),
  rr_hip_hi  = exp(apply(LH_HIP, 2, q, p = 0.975)),
  rr_wrist    = exp(FIT_WRI$loghr),
  rr_wrist_lo = exp(apply(LH_WRI, 2, q, p = 0.025)),
  rr_wrist_hi = exp(apply(LH_WRI, 2, q, p = 0.975)),
  rr_ratio_wr_hip = exp(colMeans(DIFF)),
  ratio_lo        = exp(apply(DIFF, 2, q, p = 0.025)),
  ratio_hi        = exp(apply(DIFF, 2, q, p = 0.975))
)

fwrite(res, file.path(DIR_OUT, "Table6_nhanes_hip_wrist_RR.csv"))

# 百分位映射表（审稿人复核用）
map <- rbind(
  data.table(wave = "2003-2006 (hip)", pct = FIT_HIP$pct, exposure = FIT_HIP$expo,
             unit = "counts/day", ref_pct_value = FIT_HIP$ref_val),
  data.table(wave = "2011-2014 (wrist)", pct = FIT_WRI$pct, exposure = FIT_WRI$expo,
             unit = "MIMS/day", ref_pct_value = FIT_WRI$ref_val)
)
fwrite(map, file.path(DIR_OUT, "Table6_pam_percentile_map.csv"))

# 拟合诊断
diag <- data.table(
  item = c("建模样本(髋式)","死亡(髋式)","建模样本(腕式)","死亡(腕式)",
           "参照点暴露(髋式)","参照点暴露(腕式)","抽样次数",
           "部位效应 92.5 百分位比值","部位效应 95%CI 下界","部位效应 95%CI 上界"),
  value = c(FIT_HIP$n, FIT_HIP$n_death, FIT_WRI$n, FIT_WRI$n_death,
            round(FIT_HIP$ref_val, 1), round(FIT_WRI$ref_val, 1), N_DRAWS,
            round(res$rr_ratio_wr_hip[res$pct == 92.5], 3),
            round(res$ratio_lo[res$pct == 92.5], 3),
            round(res$ratio_hi[res$pct == 92.5], 3)))
fwrite(diag, file.path(DIR_OUT, "QC_pam_site_fit.csv"))

cat("\n===== 两条曲线（参照点 = 各自人群 12.5 百分位）=====\n")
print(res[, .(pct, offset_pts, expo_hip, rr_hip = round(rr_hip,3),
              rr_wrist = round(rr_wrist,3),
              rr_wrist_over_hip = round(rr_ratio_wr_hip,3),
              ratio_lo = round(ratio_lo,3), ratio_hi = round(ratio_hi,3))])
cat("\n读数：rr_wrist_over_hip 显著 < 1 表示「同一人群中相同活动百分位下，
腕式测得的 RR 低于髋式」→ 髋式曲线在总量轴上会**高估**低活动者的风险。\n")
pa_log("04b 完成 -> output/Table6_nhanes_hip_wrist_RR.csv")
