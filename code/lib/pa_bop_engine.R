# =============================================================================
# lib/pa_bop_engine.R
# Module 2 合成引擎（**共享**）
# -----------------------------------------------------------------------------
# 为什么必须是共享模块：
#   05a_module2_bop.R 与 05c_module2_nhanes_site_sensitivity.R 必须使用**同一引擎、
#   同一先验、同一随机会话设置**。否则
#     ① 论文会出现两套池化口径（Methods 无法自洽：一处写贝叶斯、一处实际是 REML）；
#     ② 05c 的「A 档逐值复现 05a 主产物（< 1e-6）」自检无法成立——A 档的数据
#        就等于 05a 的 dt_main（一般人群），只有同引擎 + 同 seed 才可能逐值一致。
#
# 调用方（脚本）须已在 globalenv 中定义：
#   PA_ROOT / DIR_CODE / DIR_OUT / PA_SEED   （来自 00_setup.R）
#   Z975 / OFF_EFF / ARM_LEVELS
# 本模块被 source() 时自行计算：
#   BOP_ENGINE / BOP_CHAINS / BOP_ITER / BOP_CORES(_REQ) / BOP_ADAPT /
#   BOP_SE_SIGMA / HAVE_BRMS / BOP_PRIORS
# 对外提供：
#   FORM_MAIN / FORM_CURV、fit_pool()、coef_of()、coef_label()、build_X()、predict_from()、
#   contrast()、device_arm_lvs()、pooled_w()
# -----------------------------------------------------------------------------
# 引擎说明（2026-10-16 升级为**真贝叶斯**）：
#   2026-10-12 起本机无 C++ 工具链，曾以 metafor::rma.mv()（REML）+ clubSandwich CR2
#   + MASS::mvrnorm() 参数自助作等效替代。2026-10-16 补装 Rtools45（D://rtools45，
#   经 ~/.Renviron 的 RTOOLS45_HOME 生效）并使 Stan 编译通过后，**默认引擎改为真贝叶斯**：
#       brms::brm(yi | se(sqrt(vi), sigma = FALSE) ~ 0 + mmc:offset + (1 | study))
#   其中 mmc 是 arm|metric 组合的**安全码**（brms/Stan 变量名不能含 '|'），后验抽样直接
#   充当曲线集，不再依赖参数自助的正态近似。
#   ⚠️ sigma = FALSE 是刻意的：实测 brms::make_stancode 确认，FALSE 生成 real sigma = 0;，
#      似然方差恰为已知抽样方差 se²，与 rma.mv(V = vi, random = ~1|study)（方差 = vi + τ²）
#      **严格同模型**；TRUE 会额外引入未建模残差异质性，且在 sigma→0 边界形成漏斗
#      （实测 3 次发散转移）→ 不采用。开关：PA_BOP_SE_SIGMA（默认 false）。
#   ⚠️ se(..., sigma = ) 的实参必须是**字面量 TRUE/FALSE**：传变量名会被 brms 当数据列查找
#      并报 "The following variables can neither be found in 'data' nor in 'data2'"。
#      故用 switch() 展开为 4 个字面量公式（见 fit_pool()）。
#   切换开关：PA_BOP_ENGINE=bayes（默认）/ metafor（回退；无工具链环境自检时用）。
#   两引擎的**输入表与输出契约完全一致**（文件名、列名、单位、行结构均不变）。
#   ⚠️ 版本配对（否则 Stan 编译必失败，已实测）：
#        rstan 2.32.7 必须配 **StanHeaders 2.32.x**（此处 2.32.10）；
#        装成默认的 StanHeaders 2.39.1 会在 dense_e_metric.hpp 处报编译错误。
#   ⚠️ 后验抽样使本引擎成为**确定性**的：固定 seed = PA_SEED，无放回等距取 N_DRAW 条
#       后验作为曲线池（n_iter ≥ N_DRAW 时），故跨运行逐字节可复现。
# =============================================================================

# ---------------------------------------------------------------------------
# 0b. 合成引擎配置（2026-10-16；见文件头「引擎说明」）
#   不变量：无论哪个引擎，fp$b / fp$V / fp$post 的**列名与顺序必须一致**，
#   因为 build_X() / pooled_w() / draws 矩阵乘法全部按 names(fp$b) 对齐。
# ---------------------------------------------------------------------------
BOP_ENGINE <- Sys.getenv("PA_BOP_ENGINE", unset = "bayes")
BOP_CHAINS <- as.integer(Sys.getenv("PA_BOP_CHAINS", unset = "4"))
BOP_ITER   <- as.integer(Sys.getenv("PA_BOP_ITER",   unset = "2000"))
BOP_CORES_REQ <- as.integer(Sys.getenv("PA_BOP_CORES", unset = "4"))
BOP_ADAPT  <- as.numeric(Sys.getenv("PA_BOP_ADAPT_DELTA", unset = "0.99"))
# ---------------------------------------------------------------------------
# ⚠️ Windows + 非 ASCII（中文）项目路径 → rstan 并行链**必然挂死**，须强制串行。
#   机制：rstan 的 `cores > 1` 在 Windows 上走 `parallel::makeCluster(type="PSOCK")`，
#         由主进程 `system2()` 拉起 worker 子进程，命令行里带项目 cwd。
#         本项目已把 `LC_CTYPE` 设为 UTF-8（否则 R 读不了中文路径），此组合下
#         R 无法把中文路径转成本地编码传给子进程 → worker 起不来，`sampling()` 静默挂死。
#         **这正是本项目 `code/README.md` 坑 3 的同一根因**（当时只作用于 `system2` 调用）。
#   实测（2026-10-16，路径 `E:/WorkBuddy/.../范式A_低体力活动_加速度计`）：
#         cores = 4 → 主模型 12 分钟零进展（无新文件、无输出），必须 kill；
#         cores = 1 → 同一模型 2.1 分钟完成；核对产物与 cores=4 在 ASCII 路径下的结果一致。
#   故：路径含非 ASCII 字符时**强制 cores = 1**（仅影响墙钟时间，不影响后验——
#       每条链的种子由 seed + chain_id 决定，与 cores 无关）。
#   想强制指定可设 PA_BOP_CORES；设 1 则任何路径都串行。
# ---------------------------------------------------------------------------
BOP_ASCII_PATH <- !grepl("[^ -~]", PA_ROOT)
BOP_CORES <- if (.Platform$OS.type == "windows" && !BOP_ASCII_PATH) 1L else BOP_CORES_REQ
HAVE_BRMS  <- identical(BOP_ENGINE, "bayes") &&
              requireNamespace("brms",  quietly = TRUE) &&
              requireNamespace("rstan", quietly = TRUE)
# ⚠️ se(..., sigma=) 的确切语义（**实测生成的 Stan 代码得出**，勿凭记忆）：
#     sigma = FALSE → 代码里是 `real sigma = 0;`，似然方差 = se2 = vi（恰为已知抽样方差）
#                     → 即"固定效应（已知 SE）meta 分析"，与 metafor 的
#                       rma.mv(yi, V=vi, random=~1|study)（方差 = vi + τ²）**严格同模型**。
#     sigma = TRUE  → 代码里是 `real<lower=0> sigma;`，似然方差 = sigma² + se²
#                     → 额外允许"未建模的组内残差异质性"。会显著加宽区间，
#                       且 sigma→0 边界形成漏斗 → 实测出现发散转移。
#   故**默认 sigma = FALSE**（同一模型换估计方法，最干净）。
#   需要"额外残差异质性"的稳健性版本时设 PA_BOP_SE_SIGMA=TRUE。
BOP_SE_SIGMA <- tolower(Sys.getenv("PA_BOP_SE_SIGMA", unset = "false")) == "true"
# 先验（弱信息，须写进 Methods）：
#   斜率 b（每 1 个百分位点的 log-HR）~ Normal(0, 0.5)
#   研究间随机截距 SD                    ~ Student-t(3, 0, 2.5)（brms 默认值，此处显式声明）
#   注：已知抽样误差由 se(sqrt(vi), sigma = FALSE) **固定**，故不估 sigma。
BOP_PRIORS <- if (HAVE_BRMS) {
  tryCatch(
    brms::prior(normal(0, 0.5), class = "b") +
      brms::prior(student_t(3, 0, 2.5), class = "sd", group = "study"),
    error = function(e) brms::prior(normal(0, 0.5), class = "b"))
} else NULL
# =============================================================================
# 拟合引擎主体（原 05a_module2_bop.R 第 2 节，逐字抽取）
#   不变量：无论哪个引擎，fp$b / fp$V / fp$post 的**列名与顺序必须一致**，
#   因为 build_X() / pooled_w() / draws 矩阵乘法全部按 names(fp$b) 对齐。
# =============================================================================
# ---------------------------------------------------------------------------
# 2. 拟合引擎（可对不同数据子集复用 → 主分析 / 敏感性）
# ---------------------------------------------------------------------------
FORM_MAIN <- ~ 0 + mm:offset

# 曲率敏感性用：额外加一个**预计算数值列** off2。
#   为什么不用 I(offset^2)：brms 会把该表达式改写成难以预测的项名，
#   而用现成数值列，项名就是确定的 "off2"，两引擎下都好定位。
#   ⚠️ 列的定义是 **(offset / OFF_EFF)^2**，不是 offset^2！见 fit_pool() 内注释。
FORM_CURV <- ~ 0 + mm:offset + off2

fit_pool <- function(dat, tag, curvature = FALSE) {
  d <- copy(dat)
  d[, mm := factor(paste(as.character(arm), as.character(metric_definition), sep = "|"))]
  d[, mm := droplevels(mm)]
  combos <- levels(d$mm)
  # ---------------------------------------------------------------------------
  # 曲率列**按 OFF_EFF 标准化**：off2 = (offset / OFF_EFF)^2，取值范围 ~[0.05, 2]。
  #
  # ⚠️ 这里**不能**直接用 offset^2（2026-10-16 实测）：原因不是模型错，而是**采样器条件数**。
  #    · 原始 offset^2 量级达 7.2e3，其系数自然量级 ~4e-5，与斜率（~1e-2）相差 3 个数量级；
  #    · 同时 off2 与 self|MVPA 斜率列**加权共线**——Moore2012 的 1/vi 权重（3.3e3–7.8e3）
  #      比其余行（41–738）高一个数量级，加权相关 r = 0.78，后验相关达 −0.91；
  #    · 两者叠加 → NUTS 在一条量级极端的近平脊上无法在 1000 步 warmup 内适应
  #      → 实测 **max Rhat = 3.61、发散 0 次但链根本没收敛**，
  #        斜率后验 SD 被虚增到 REML 标准误的 30–82 倍（如 device_hip|LPA 0.160 vs 0.0019），
  #        MVPA 方法效应 RR 的 97.5% 分位被推到 88674（真值 ~1.0）。
  #    · 改为 (offset/OFF_EFF)^2 后：系数与斜率**同量级**（~0.14 vs ~0.01），
  #      且默认先验 b ~ N(0, 0.5) 恰好变成"在 offset=OFF_EFF 处 |log-RR 曲率贡献| < 0.98"的
  #      **温和正则**（原始尺度下该先验等于平先验，形同虚设）。
  #    · 修后实测：max Rhat = 1.011、发散 0 次、固定部分残差 0.319（< 主分析 0.399，方向正确），
  #      曲率系数换算回每百分位² = 3.76e-05，与 metafor REML 的 3.88e-05 吻合到 3 位有效数字。
  #    · 本列只是**线性重标**，不改变任何模型的似然；两引擎与主分析的对比权重（曲率项权重为 0）均不变。
  # ---------------------------------------------------------------------------
  d[, off2 := (offset / OFF_EFF)^2]

  alias <- NULL; post <- NULL; cr <- NULL; fit <- NULL
  ndiv <- NA_real_; rhat_max <- NA_real_
  fit_mode <- NA_character_

  if (HAVE_BRMS) {
    # --- 真贝叶斯路径（brms + rstan，Windows 走 Rtools45 编译）---
    #     安全码：brms/Stan 变量名不能含 '|' → k01..kNN，并保留 labels(combos) 作对照
    codes <- sprintf("k%02d", seq_along(combos))
    d[, mmc := factor(codes[as.integer(mm)], levels = codes)]
    # ⚠️ se(..., sigma = ) 的实参必须是**字面量 TRUE/FALSE**：
    #    实测若传变量（如 sigma = BOP_SE_SIGMA），brms 会去 data 里找该名并报
    #    `The following variables can neither be found in 'data' nor in 'data2'`。
    #    故用 switch 展开为 4 个字面量公式，避免元编程。
    form <- switch(paste0(if (curvature) "curv" else "main", "_", BOP_SE_SIGMA),
      "main_FALSE" = yi | se(sqrt(vi), sigma = FALSE) ~ 0 + mmc:offset + (1 | study),
      "main_TRUE"  = yi | se(sqrt(vi), sigma = TRUE)  ~ 0 + mmc:offset + (1 | study),
      "curv_FALSE" = yi | se(sqrt(vi), sigma = FALSE) ~ 0 + mmc:offset + off2 + (1 | study),
      "curv_TRUE"  = yi | se(sqrt(vi), sigma = TRUE)  ~ 0 + mmc:offset + off2 + (1 | study),
      stop("[", tag, "] 未知公式组合：curvature=", curvature, ", sigma=", BOP_SE_SIGMA))

    # 进度用 message()（走 **stderr**，不缓冲；cat() 走 stdout 会被块缓冲，
    # 使 10 分钟的贝叶斯跑批在日志里"看起来卡死"。2026-10-16 实测教训。）
    message(sprintf("[%s] 开始贝叶斯拟合：%d 行 / %d 研究 / %d 组合 / %d chains x %d iter / cores=%d",
                    tag, nrow(d), uniqueN(d$study), length(combos),
                    BOP_CHAINS, BOP_ITER, BOP_CORES))
    .t0 <- Sys.time()
    fit <- brms::brm(
      formula = form, data = d, prior = BOP_PRIORS,
      chains = BOP_CHAINS, iter = BOP_ITER, warmup = floor(BOP_ITER / 2),
      cores = BOP_CORES, seed = PA_SEED, backend = "rstan",
      refresh = 0, silent = 2, open_progress = FALSE,
      control = list(adapt_delta = BOP_ADAPT, max_treedepth = 12))
    message(sprintf("[%s] 拟合完成，耗时 %.1f 分钟", tag,
                    as.numeric(difftime(Sys.time(), .t0, units = "mins"))))

    fe <- brms::fixef(fit)                     # 行名 = 项名，如 cmbk01:offset（**无** b_ 前缀）
    pa <- as.matrix(fit)                       # 列名 = 参数名，如 b_cmbk01:offset（**有** b_ 前缀）
    tname <- vapply(seq_along(combos), function(j) {
      hit <- rownames(fe)[grepl(paste0(codes[j], ":offset"), rownames(fe), fixed = TRUE)]
      if (length(hit) != 1L)
        stop("[", tag, "] 无法唯一定位组合 '", combos[j], "' 的后验系数（命中 ",
             length(hit), " 个；可用项名：", paste(rownames(fe), collapse = ", "), "）")
      paste0("b_", hit)                        # 统一用 as.matrix 的列名作参数名
    }, "")
    # 后验抽样矩阵：按 combos 顺序取斜率列；曲率模型再接上曲率列。
    # ⚠️ 曲率列名必须**动态定位**：brms 会把项名拼成 b_<term>，不能硬编码 "b_off2"。
    qname <- character(0)
    if (curvature) {
      qr <- rownames(fe)[!grepl(":offset$", rownames(fe))]
      if (length(qr) != 1L)
        stop("[", tag, "] 曲率模型的非斜率项不唯一（命中 ",
             length(qr), " 个：", paste(qr, collapse = ", "), "）")
      qname <- paste0("b_", qr)
    }
    cols <- c(tname, qname)
    miss <- setdiff(cols, colnames(pa))
    if (length(miss))
      stop("[", tag, "] 后验抽样矩阵缺列：", paste(miss, collapse = ", "),
           "；实际含 b_ 的列：", paste(grep("^b_", colnames(pa), value = TRUE), collapse = ", "))
    post <- pa[, cols, drop = FALSE]
    colnames(post) <- cols
    b <- colMeans(post)
    V <- cov(post)
    alias <- setNames(tname, combos)
    # 后验诊断（发散转移 / Rhat / ESS）——发散 > 0 时后验不可信，须报 WARN
    ndiv <- tryCatch({
      np <- brms::nuts_params(fit)
      as.numeric(sum(np$Value[np$Parameter == "divergent__"], na.rm = TRUE))
    }, error = function(e) NA_real_)
    rh <- tryCatch(brms::rhat(fit), error = function(e) NULL)
    # Rhat 取**全部被追踪的系数**（含曲率项；曲率项恰是主分析里最易不收敛的那个）
    rhat_max <- if (is.null(rh)) NA_real_ else max(rh[names(rh) %in% cols], na.rm = TRUE)
    fit_mode <- sprintf("bayesian_multilevel_meta_regression(brms %s/rstan %s; %d chains x %d iter)",
                        as.character(packageVersion("brms")),
                        as.character(packageVersion("rstan")), BOP_CHAINS, BOP_ITER)
  } else {
    # --- 回退路径：metafor REML（无 C++ 工具链时的等效实现）---
    if (identical(BOP_ENGINE, "bayes"))
      warning("PA_BOP_ENGINE=bayes 但 brms/rstan 不可用 → 回退 metafor。", call. = FALSE)
    fit <- tryCatch(
      rma.mv(yi = yi, V = vi, mods = if (curvature) FORM_CURV else FORM_MAIN,
             random = ~ 1 | study, data = d, method = "REML"),
      error = function(e) {
        message("  [", tag, "] rma.mv 失败：", conditionMessage(e)); NULL })
    if (is.null(fit)) {
      fit_mode <- "meta_regression_fallback"
      fit <- rma(yi = yi, vi = vi, mods = if (curvature) FORM_CURV else FORM_MAIN,
                 data = d, method = "REML")
    } else fit_mode <- "multilevel_random_effects(metafor REML)"
    b <- coef(fit); V <- vcov(fit)
    cr <- NULL
    if (uniqueN(d$study) >= 4L && requireNamespace("clubSandwich", quietly = TRUE))
      cr <- tryCatch(clubSandwich::coef_test(fit, vcov = "CR2", cluster = d$study),
                     error = function(e) NULL)
  }

  if (anyNA(b))
    stop("[", tag, "] 模型存在 NA 系数（设计矩阵秩亏）：",
         paste(names(b)[is.na(b)], collapse = ", "))
  V <- (V + t(V)) / 2
  list(dat = d, tag = tag, combos = combos, b = b, V = V, post = post, alias = alias,
       fit = fit, fit_mode = fit_mode, cr = cr, curvature = curvature,
       curv_scale = if (curvature) OFF_EFF else NA_real_,
       ndiv = ndiv, rhat_max = rhat_max,
       n_study = uniqueN(d$study), n_rows = nrow(d), n_source = uniqueN(d$source))
}

# 唯一命中的系数名。
#   · brms 路径：项名是安全码形式（cmbk01:offset），无法靠 "arm|metric" 子串反查
#     → 用 fp$alias 这张「对外标签 → 项名」对照表直接查（O(1)，且与引擎无关）。
#   · metafor 路径：alias = NULL，退回子串匹配（rma/rma.mv 对象没有 terms 分量）。
coef_of <- function(fp, lv) {
  if (!is.null(fp$alias) && lv %in% names(fp$alias)) return(unname(fp$alias[[lv]]))
  hit <- names(fp$b)[grepl(lv, names(fp$b), fixed = TRUE)]
  if (length(hit) != 1L)
    stop("无法唯一定位组合系数 '", lv, "'（命中 ", length(hit), " 个）")
  hit
}

# 系数名 → **对外标签**（形如 "arm|metric"）。
#   ⚠️ 报告/表格里**绝不能**直接用系数名（`names(fp$b)`）：贝叶斯路径下它是 brms 的
#      安全码（`b_mmck02:offset`），写进 Table5/Table12 会把引擎内部标识泄漏给读者。
#      2026-10-16 实测踩到：05a 的 arms_device、05e 的 dev_arms_kept 两列均被污染。
#   · 贝叶斯路径：用 fp$alias（标签 → 项名）**反向查表**，O(1) 且与引擎无关；
#   · metafor 路径：fp$alias 为 NULL，系数名本身就是标签，原样返回。
coef_label <- function(fp, cn) {
  if (!is.null(fp$alias)) {
    hit <- names(fp$alias)[fp$alias == cn]
    if (length(hit)) return(hit[1])
  }
  cn
}

# 显式设计矩阵：与后验抽样共用（避免 API 版本差异）
#   curvature = TRUE 时额外填入曲率列（唯一的非 ":offset" 系数）
build_X <- function(fp, mm_chr, offset, curvature = FALSE) {
  X <- matrix(0, nrow = length(mm_chr), ncol = length(fp$b),
              dimnames = list(NULL, names(fp$b)))
  for (k in seq_along(mm_chr)) X[k, coef_of(fp, mm_chr[k])] <- offset[k]
  if (curvature) {
    qn <- names(fp$b)[!grepl(":offset$", names(fp$b))]
    if (length(qn) != 1L)
      stop("曲率模型应有且仅有一个非斜率系数，实得 ", length(qn),
           "：", paste(qn, collapse = ", "))
    # ⚠️ 必须与 fit_pool() 内的定义**完全一致**：(offset/OFF_EFF)^2。
    #    用 fp$curv_scale 回读（而非再次引用全局 OFF_EFF），避免两处定义漂移。
    cs <- if (is.null(fp$curv_scale) || !is.finite(fp$curv_scale)) OFF_EFF else fp$curv_scale
    X[, qn] <- (offset / cs)^2
  }
  X
}

# 预测：点估计恒为 X %*% E[b]（两种引擎下 rr 列逐值可比，05c 的 A 档复现自检依赖此性质）；
#       区间在贝叶斯路径下取**线性预测子的后验分位**（比 delta 法更忠实），
#       metafor 路径下退回 Wald 区间。
predict_from <- function(fp, X) {
  se <- sqrt(rowSums((X %*% fp$V) * X)); se[!is.finite(se)] <- NA_real_
  if (!is.null(fp$post)) {
    E  <- fp$post %*% t(X)                      # n_iter × nrow(X)
    lo <- apply(E, 2L, stats::quantile, probs = 0.025, names = FALSE)
    hi <- apply(E, 2L, stats::quantile, probs = 0.975, names = FALSE)
    return(list(eta = colMeans(E), se = se, lo = lo, hi = hi, posterior = TRUE))
  }
  eta <- as.numeric(X %*% fp$b)
  list(eta = eta, se = se, lo = eta - Z975 * se, hi = eta + Z975 * se, posterior = FALSE)
}

# 线性组合（对比）：w 为"系数名 → 权重"
#   贝叶斯路径：p = 双侧**后验尾概率** 2·min(P(Δ>0), P(Δ<0))；区间 = 后验 2.5/97.5 分位
#   metafor 路径：p = Wald 正态近似；区间 = ±1.96·SE
contrast <- function(fp, w) {
  cc <- setNames(numeric(length(fp$b)), names(fp$b))
  cc[names(w)] <- w
  est <- sum(cc * fp$b)
  se  <- sqrt(max(as.numeric(t(cc) %*% fp$V %*% cc), 0))
  if (!is.null(fp$post)) {
    dr <- as.numeric(fp$post %*% cc)
    q  <- unname(stats::quantile(dr, c(0.025, 0.975)))
    return(list(est = est, se = se, p = 2 * min(mean(dr > 0), mean(dr < 0)),
                lo = q[1], hi = q[2], posterior = TRUE))
  }
  list(est = est, se = se, p = 2 * pnorm(-abs(est / se)),
       lo = est - Z975 * se, hi = est + Z975 * se, posterior = FALSE)
}
# 同一指标下的设备臂（用于"设备合并"曲线）
device_arm_lvs <- function(fp, md) {
  lvs <- paste0(ARM_LEVELS[grepl("^device", ARM_LEVELS)], "|", md)
  lvs[lvs %in% fp$combos]
}
# 设备臂的逆方差权重（跨佩戴部位合并 → device_pooled 曲线）
pooled_w <- function(fp, md) {
  lvs <- device_arm_lvs(fp, md)
  if (!length(lvs)) return(NULL)
  nms <- vapply(lvs, function(l) coef_of(fp, l), "")
  ses <- sqrt(diag(fp$V))[nms]
  w   <- 1 / ses^2
  setNames(as.list(w / sum(w)), nms)
}
