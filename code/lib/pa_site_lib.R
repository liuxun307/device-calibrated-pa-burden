# =============================================================================
# lib/pa_site_lib.R  —— 佩戴部位效应（hip vs wrist）曲线拟合的**唯一实现**
# -----------------------------------------------------------------------------
# 为什么单独抽出来：
#   04b（基准）、04c（wear 规则敏感性）、04d（文献侧脆弱性）必须用**逐字同一套**
#   拟合代码，否则「曲线差异」可能来自代码而非 data/rule。抽到这里 = 单一真源。
#
#   ⚠️ 04b 里仍保留一份**内联副本**（为保护已冻结产物的大字节稳定性，不重构它）。
#      04c 会跑一个等价性 QC：用本库在 (R0 × C0) 档复现 04b 的 Table6，
#      要求最大绝对偏差达机器精度 → 证明「敏感性用的就是基准那套拟合」。
#
# 依赖：调用方须已 source("00_setup.R")（提供 PA_SEED / DIR_* / pa_log）
# 需要的包：data.table, survey, splines, MASS
# =============================================================================

PA_SITE_LIB_VERSION <- "2026-10-12"

# ---- 加权分位数（不引第三方依赖）--------------------------------------------
# 与 04b 内联实现逐字一致。rule=2 表示超出范围时取端点（曲线需要外推到网格边缘）。
wq <- function(x, w, p) {
  ok <- !is.na(x) & !is.na(w) & w > 0
  x <- x[ok]; w <- w[ok]
  o <- order(x); x <- x[o]; w <- w[o]
  cw <- cumsum(w) / sum(w)
  approx(cw, x, xout = p, rule = 2)$y
}

# ---- 单条曲线拟合 -----------------------------------------------------------
# dt        : data.table，含 expo 列、COVARS、权重列、surv_mo、died、SDMVPSU、SDMVSTRA
# expo_col  : 暴露列名
# label     : 打印用标签
# 返回      : list(beta, V, Dmat, loghr, expo_grid, ref_val, n, n_death, knots, pct)
fit_site_curve <- function(dt, expo_col, label,
                           covars   = PA_SITE_COVARS,
                           ref_pct  = 12.5,
                           knots_df = 4,
                           pct_grid = PA_SITE_PCT_GRID,
                           weight_col = "WTMEC4YR",
                           min_n = 200L, min_death = 50L) {
  md <- copy(dt)
  # ⚠️ 用 md[[expo_col]] 而不是 get(expo_col)：把「按名字取列」写成显式索引，
  #    不依赖 data.table 的 j 环境里是否把列绑成了同名变量（避免隐式解析坑）。
  md[, expo := as.numeric(md[[expo_col]])]
  md <- md[!is.na(surv_mo) & surv_mo > 0]
  for (v in c("expo", covars, weight_col)) md <- md[!is.na(get(v))]
  # 因子型协变量不能有未用到的水平（否则 svycoxph 报错）
  for (v in covars) if (is.factor(md[[v]])) md[[v]] <- droplevels(md[[v]])

  n_death <- sum(md$died == 1, na.rm = TRUE)
  cat(sprintf("\n[%s] 建模样本 %d 人 | 死亡 %d\n", label, nrow(md), n_death))
  if (nrow(md) < min_n || n_death < min_death)
    stop(label, "：样本或事件过少（n=", nrow(md), ", 死亡=", n_death, "）")

  d  <- md$expo
  kn <- quantile(d, probs = seq(0, 1, length.out = knots_df + 1)[-c(1, knots_df + 1)], na.rm = TRUE)
  B  <- splines::ns(d, knots = kn, Boundary.knots = range(d))

  ref_val <- wq(d, md[[weight_col]], ref_pct / 100)   # 参照点 = 加权 ref_pct 百分位
  Bref    <- predict(B, ref_val)

  dd <- as.data.frame(md)
  for (j in seq_len(ncol(B))) dd[[paste0("s", j)]] <- B[, j]
  des <- survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = as.formula(paste0("~", weight_col)),
                           nest = TRUE, data = dd)
  f <- as.formula(sprintf("Surv(surv_mo, died) ~ %s + %s",
                          paste(paste0("s", 1:ncol(B)), collapse = " + "),
                          paste(covars, collapse = " + ")))
  m  <- survey::svycoxph(f, design = des)

  sn   <- paste0("s", 1:ncol(B))
  beta <- coef(m)[sn]
  V    <- vcov(m)[sn, sn, drop = FALSE]
  if (anyNA(beta)) stop(label, "：样条系数含 NA（可能共线/事件不足）")

  # 百分位网格 → 该人群加权分位暴露值 → 样条基（与参照基相减）
  grid_expo <- wq(d, md[[weight_col]], pct_grid / 100)
  Bg   <- predict(B, grid_expo)
  Dmat <- Bg - matrix(Bref, nrow(Bg), ncol(Bg), byrow = TRUE)

  list(label = label, n = nrow(md), n_death = n_death,
       beta = beta, V = V, Dmat = Dmat, pct = pct_grid,
       expo_grid = grid_expo, ref_val = ref_val,
       loghr = as.numeric(Dmat %*% beta), knots = kn)
}

# ---- 系数抽样 → log-HR 抽样分布 --------------------------------------------
# ⚠️ 每个「曲线规格」用**独立且钉死**的 seed：既保证 hip / wrist 两臂独立，
#    又保证任何人任何时候跑都得到同一条抽样序列（可逐字节复现）。
draw_loghr <- function(fit, n_draws, seed) {
  set.seed(seed)
  B <- MASS::mvrnorm(n_draws, mu = fit$beta, Sigma = fit$V)
  B %*% t(fit$Dmat)          # n_draws × n_pct
}

# ---- 两条独立曲线 → 部位效应比值（wrist / hip）-----------------------------
# 两波是**独立样本** → 系数向量独立 → log(RR_wrist) − log(RR_hip) 的抽样分布
site_ratio <- function(fit_ref, fit_alt, n_draws = 1000L, seed_ref, seed_alt) {
  LR <- draw_loghr(fit_ref, n_draws, seed_ref)
  LA <- draw_loghr(fit_alt, n_draws, seed_alt)
  DIFF <- LA - LR
  q <- function(x, p) as.numeric(quantile(x, p, na.rm = TRUE))
  data.table(
    pct     = fit_ref$pct,
    offset  = fit_ref$pct - fit_ref$pct[1],          # 参照档为 0
    rr_ref  = exp(fit_ref$loghr),
    rr_alt  = exp(fit_alt$loghr),
    rr_ratio_alt_over_ref = exp(colMeans(DIFF)),
    ratio_lo = exp(apply(DIFF, 2, q, p = 0.025)),
    ratio_hi = exp(apply(DIFF, 2, q, p = 0.975)),
    p_value  = apply(DIFF, 2, function(v) 2 * min(mean(v > 0), mean(v < 0)))
  )
}

# ---- 共享常量 ---------------------------------------------------------------
PA_SITE_COVARS   <- c("age","female","race","educ","pir","bmi","sbp",
                      "cur_smoke","drink_any","diabetes","cvd_hx")
PA_SITE_PCT_GRID <- c(12.5, 22.5, 32.5, 42.5, 52.5, 62.5, 72.5, 82.5, 92.5)  # → offset 0..80
PA_SITE_REF_PCT  <- 12.5   # = BoP 的 ref_canon（最低四分位中点）
