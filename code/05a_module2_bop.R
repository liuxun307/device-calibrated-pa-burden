# =============================================================================
# 05a_module2_bop.R
# Module 2：证据合成 —— 以「测量方法 × 佩戴部位」为协变量的 BoP 式 meta-regression
# =============================================================================
# 定位：插在 04（NHANES 剂量-反应）与 05（PAF 重算）之间。
#   04 给的是**美国 NHANES 腕式设备**的 RR 曲线；
#   Module 2 把外部队列（髋式 / 混合 / 腕式设备 + 自报）池化，显式估计
#   ①「设备 vs 自报」的方法效应、②「髋式 vs 腕式」的佩戴部位效应，
#   产出可外推全球的 **RR 曲线集**，供 05 的 Module 3 使用。
#
# 引擎说明（2026-10-16 升级为**真贝叶斯**）：
#   2026-10-12 起本机无 C++ 工具链，曾以 `metafor::rma.mv()`（REML）+ `clubSandwich` CR2
#   + `MASS::mvrnorm()` 参数自助作等效替代。2026-10-16 补装 Rtools45（`D:\rtools45`，
#   经 `~/.Renviron` 的 `RTOOLS45_HOME` 生效）并使 Stan 编译通过后，**默认引擎改为真贝叶斯**：
#       brms::brm(yi | se(sqrt(vi), sigma = FALSE) ~ 0 + mmc:offset + (1 | study))
#   其中 mmc 是 arm|metric 组合的**安全码**（brms/Stan 变量名不能含 '|'），后验抽样直接
#   充当曲线集，不再依赖参数自助的正态近似。
#   ⚠️ `sigma = FALSE` 是**刻意**的：实测 `brms::make_stancode` 确认——
#        FALSE 生成 `real sigma = 0;`，似然方差**恰为**已知抽样方差 se²，
#              与 `metafor::rma.mv(V = vi, random = ~1|study)`（方差 = vi + τ²）**严格同模型**；
#        TRUE  生成 `real<lower=0> sigma;`，额外允许未建模残差异质性，
#              实测 sigma→0 边界形成漏斗并产生 **3 次发散转移** → 不采用。
#        开关：`PA_BOP_SE_SIGMA`（默认 false）。
#       ⚠️ se(..., sigma = ) 的实参必须是**字面量 TRUE/FALSE**：传变量名会被 brms 当数据列查找
#          并报 `The following variables can neither be found in 'data' nor in 'data2'`。
#          故本脚本用 switch() 展开为 4 个字面量公式（见 fit_pool()）。
#   切换开关：`PA_BOP_ENGINE=bayes`（默认）/ `metafor`（回退；无工具链环境自检时用）。
#   两引擎的**输入表与输出契约完全一致**（文件名、列名、单位、行结构均不变）。
#   ⚠️ 版本配对（否则 Stan 编译必失败，已实测）：
#        rstan 2.32.7 必须配 **StanHeaders 2.32.x**（此处 2.32.10）；
#        装成默认的 StanHeaders 2.39.1 会在 dense_e_metric.hpp 处报编译错误。
#   ⚠️ 后验抽样使本脚本成为**确定性**脚本：固定 seed=PA_SEED，无放回等距取 N_DRAW 条
#       后验作为曲线池（n_iter ≥ N_DRAW 时），故跨运行逐字节可复现。
#
# 关键设计：
#   ① **每行相对"自身参照"锚定**：offset = exposure_center − exposure_ref_center（逐行）。
#      用全表 median(ref) 做统一锚点在四分位（ref=12.5）与三分位（ref=16.667）混排时
#      会**系统性平移**某些研究的曲线，属真错误。
#   ② **组合因子 mm = arm|metric**（显式，秩满）：旧公式 `method:offset + metric:offset`
#      在非完全交叉设计下**秩亏**，会产生 NA 系数并污染预测。
#   ③ **arm 而非 method 作主轴**（2026-10-12 第三轮，A3 腕式补齐时重构）：
#      arm ∈ {self, device_hip, device_mixed, device_wrist}。
#      动机：NHANES 暴露是**腕式**，而原池里**全部设备研究都是髋式/混合**
#      → "设备 vs 自报"的方法效应与"髋 vs 腕"的部位效应**完全共线、无法分离**。
#      补齐腕式来源后，LPA 上首次出现 hip×wrist 双覆盖 → 部位效应可估。
#   ④ **主分析限一般人群**：既往确诊 CVD 的亚组（Cao2024）人群基线风险完全不同，
#      与"腕式"特征共线 → 主分析排除，另以敏感性给出（同时报告两个数值）。
#
# 已知局限（必须写进 Methods）：
#   ① 同一研究内多分位对比共用同一参照组 → 抽样误差相关，此处按独立近似（偏乐观）；
#   ② 参照组 RR 固定为 1，未估计其不确定性（但这是**正确**的锚定）；
#   ③ 百分位刻度是**各研究自身分布内的相对位置**，不是绝对 MIMS/day；
#   ④ 自报来源的百分位推导有三种口径（见 pct_rule 列），PURE 为等份额假定（近似）；
#   ⑤ Tarp2024 与 Ekelund2019 队列高度重叠 → 设备侧两个研究**非独立**；
#      Sun2025 与 Cao2024 同属 UK Biobank → 同样非独立；
#   ⑥ 每组合仅 2–5 个对比点 → 只能拟合"过原点的单调直线"，真实剂量-反应是 **L 形**，
#      高暴露端被系统性低估。脚本用 Table5_bop_fit_diagnostic.csv 显式量化该失拟。
#   ⑦ **部位效应只在 LPA 上可估**：total_PA / MVPA 均无腕式来源 → 见 status 与
#      Table5_bop_wear_site.csv 的 note。这是**文献现状**而非代码缺陷。
#
# 输入：data/bop/rr_table.csv（抽取规范见 data/bop/README.md）
# 输出：output/Table5_bop_pooled_RR.csv           池化 RR 曲线（arm 组合 + device_pooled）
#       output/Table5_bop_method_effect.csv       方法效应（同指标内 device_pooled vs self）
#       output/Table5_bop_wear_site.csv           佩戴部位效应（同指标内 hip vs wrist）
#       output/Table5_bop_slopes.csv              各组合斜率
#       output/Table5_bop_fit_diagnostic.csv      观测点失拟诊断
#       output/Table5_bop_sensitivity_curvature.csv  共享曲率敏感性
#       output/bop_rr_draws.rds                   B 条参数自助曲线（供 Module 3）
#       output/QC_bop_status.csv                  就绪度与门禁状态
# =============================================================================

local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
})
if (!isTRUE(getOption("PA_SETUP_DONE"))) {
  .ps <- NULL
  for (.c in c("00_setup.R", file.path(getwd(), "00_setup.R"))) {
    if (!is.null(.c) && nzchar(.c) && file.exists(.c)) { .ps <- normalizePath(.c); break }
  }
  if (is.null(.ps)) stop("未找到 00_setup.R：请 setwd() 到 code/ 目录后重试")
  source(.ps); rm(.ps, .c)
}
suppressPackageStartupMessages({ library(data.table); library(metafor) })

DIR_BOP <- file.path(PA_ROOT, "data", "bop")
dir.create(DIR_BOP, showWarnings = FALSE, recursive = TRUE)
RR_CSV  <- file.path(DIR_BOP, "rr_table.csv")
N_DRAW  <- 1000L
Z975    <- 1.959964
# 输出轴约定：把 offset（相对自身参照的百分位点）映射回绝对百分位时，
# 统一假定"参照点位于第 12.5 百分位"（=最低四分位中点，GBD/BoP 常用口径）。
# 该假定只影响输出的 exposure_pct 标签，**不影响**任何估计量。
REF_CANON   <- 12.5
OFFSET_GRID <- seq(0, 90, by = 5)
OFF_EFF     <- 60   # 方法效应 / 部位效应汇报用的偏移量（12.5 → 72.5 百分位）

# ---------------------------------------------------------------------------
# 0b. 合成引擎（配置 + 拟合）：**抽到共享模块** code/lib/pa_bop_engine.R
#     动机：05a 与 05c 必须同引擎（否则 05c 的「A 档逐值复现 05a」自检无法成立）。
#     模块提供：FORM_MAIN / FORM_CURV、fit_pool()、coef_of()、build_X()、
#               predict_from()、contrast()、device_arm_lvs()、pooled_w()
#     以及 BOP_* 开关、HAVE_BRMS、BOP_PRIORS。
# ---------------------------------------------------------------------------
local({
  .cand <- c(file.path(getwd(), "lib", "pa_bop_engine.R"),
             file.path(DIR_CODE, "lib", "pa_bop_engine.R"))
  .hit <- .cand[file.exists(.cand)]
  if (!length(.hit)) stop("未找到 lib/pa_bop_engine.R：请 setwd() 到 code/ 目录后重试")
  source(.hit[1], local = FALSE)
  message("[05a] 已加载共享引擎：", .hit[1])
})
OFF_EXTRA   <- c(25, 50, 75)  # 部位效应另报这几个偏移，看差异是否随范围变化

ARM_LEVELS <- c("self", "device_hip", "device_mixed", "device_wrist")
ARM_SITE   <- c(self = "NA", device_hip = "hip", device_mixed = "mixed", device_wrist = "wrist")
POP_LEVELS <- c("general", "clinical_subgroup")

STATUS <- list()
add_status <- function(item, status, detail = "")
  STATUS[[length(STATUS) + 1L]] <<- data.table(item = item, status = status, detail = detail)

write_status <- function(file = file.path(DIR_OUT, "QC_bop_status.csv")) {
  st <- rbindlist(STATUS)
  fwrite(st, file); st
}

fmt_ci <- function(est, lo, hi, d = 3)
  sprintf("%.*f [%.*f, %.*f]", d, est, d, lo, d, hi)

# ---------------------------------------------------------------------------
# 1. 读入 + 硬校验（不合规就停，不静默）
# ---------------------------------------------------------------------------
REQ <- c("source", "study", "design", "method", "device_type", "wear_site",
         "metric_definition", "exposure_scale", "exposure_center",
         "exposure_ref_center", "outcome", "hr", "hr_lo", "hr_hi", "population")

if (!file.exists(RR_CSV)) {
  add_status("输入表", "MISSING", paste0("未找到 ", RR_CSV))
  write_status()
  message("⛔ Module 2 未就绪：rr_table.csv 不存在。")
  message("   → 先按 data/bop/README.md 抽取外部队列 RR；Module 3 暂用 DRYRUN_S3 占位。")
  quit(save = "no", status = 0)
}

dt <- fread(RR_CSV, encoding = "UTF-8")
miss_col <- setdiff(REQ, names(dt))
if (length(miss_col)) stop("rr_table.csv 缺列：", paste(miss_col, collapse = ", "))

n_raw <- nrow(dt)
dt <- dt[!is.na(hr) & !is.na(hr_lo) & !is.na(hr_hi) & !is.na(exposure_center)]
if (n_raw != nrow(dt))
  message(sprintf("  剔除 %d 行（HR/CI/暴露中心缺失）", n_raw - nrow(dt)))

bad <- dt[hr_lo <= 0 | hr <= 0 | hr_lo > hr | hr > hr_hi]
if (nrow(bad))
  stop("以下行 HR/CI 不合法（须 0 < hr_lo <= hr <= hr_hi）：\n  ",
       paste(bad$row_id, collapse = "\n  "))

if (any(!as.character(dt$population) %in% POP_LEVELS))
  stop("population 列取值非法（须 ∈ {", paste(POP_LEVELS, collapse = ", "), "}）：\n  ",
       paste(unique(setdiff(as.character(dt$population), POP_LEVELS)), collapse = ", "))

dt[, `:=`(
  yi = log(hr),
  vi = ((log(hr_hi) - log(hr_lo)) / (2 * Z975))^2)]

# --- arm 派生（方法 × 佩戴部位）---
dt[, arm := fcase(
  method == "self",                          "self",
  method == "device" & wear_site == "hip",   "device_hip",
  method == "device" & wear_site == "wrist", "device_wrist",
  method == "device" & wear_site == "mixed", "device_mixed",
  default = NA_character_)]
if (anyNA(dt$arm))
  stop("以下行无法归入 arm（检查 method / wear_site）：\n  ",
       paste(dt[is.na(arm), row_id], collapse = "\n  "))

dt[, method := factor(method, levels = c("self", "device"))]
dt[, metric_definition := factor(metric_definition)]
dt[, arm := factor(arm, levels = ARM_LEVELS)]
dt[, population := factor(population, levels = POP_LEVELS)]
dt[, exposure_center := as.numeric(exposure_center)]
dt[, exposure_ref_center := as.numeric(exposure_ref_center)]

# ---------------------------------------------------------------------------
# ⚠️ 关键锚点（逐行）：表内每行都是"相对**该研究自身**最低活跃类别的对比"
#    → 按构造 RR(自身参照) = 1，故 offset 必须**逐行**用该行自己的 ref 计算。
#    同时强制过原点（`~ 0 + ...:offset`）避免外推出"越不活跃风险越低"的错误形状。
# ---------------------------------------------------------------------------
if (any(!is.finite(dt$exposure_ref_center)))
  stop("exposure_ref_center 存在缺失/非有限值，无法逐行锚定参照点。")
if (any(dt$exposure_center < dt$exposure_ref_center))
  stop("存在 exposure_center < exposure_ref_center 的行：",
       paste(dt[exposure_center < exposure_ref_center, row_id], collapse = ", "))
dt[, offset := exposure_center - exposure_ref_center]

ref_tab <- unique(dt[, .(study, exposure_ref_center, pct_rule)])
add_status("参照组锚点（逐行）", "OK",
           sprintf("各研究参照百分位：%s",
                   paste(sprintf("%s=%.2f", ref_tab$study, ref_tab$exposure_ref_center),
                         collapse = "; ")))
if (uniqueN(dt$pct_rule) > 1L || any(dt$pct_rule == "equal_share_assumption")) {
  add_status("百分位推导口径", "WARN",
             sprintf("含 %d 个等份额**假定**来源 → 须做敏感性：%s",
                     uniqueN(dt[pct_rule == "equal_share_assumption", source]),
                     paste(sort(unique(dt$pct_rule)), collapse = " / ")))
} else {
  add_status("百分位推导口径", "OK", paste(sort(unique(dt$pct_rule)), collapse = " / "))
}

n_study_all <- uniqueN(dt$study)
add_status("输入表", "OK",
           sprintf("%d 行 / %d 来源 / %d 研究 / arm %s",
                   nrow(dt), uniqueN(dt$source), n_study_all,
                   paste(sort(unique(as.character(dt$arm))), collapse = " + ")))

if (!nrow(dt)) {
  add_status("输入表", "EMPTY", "过滤后无可用行")
  write_status()
  message("⛔ Module 2 未就绪：rr_table.csv 过滤后无有效行。")
  quit(save = "no", status = 0)
}

# ---------------------------------------------------------------------------
# 2. 拟合引擎：**已抽取**到 code/lib/pa_bop_engine.R（见本节上方的 source 调用）。
#    本文件不再内联定义 fit_pool/coef_of/build_X/predict_from/contrast/
#    device_arm_lvs/pooled_w，以免 05a 与 05c 两份实现漂移。
# ---------------------------------------------------------------------------

metrics <- sort(unique(as.character(dt$metric_definition)))

# --- 主分析：一般人群（排除既往 CVD 亚组） ---
dt_main <- dt[population == "general"]
if (!nrow(dt_main)) stop("population=='general' 子集为空：请检查输入表。")
dt_sens <- dt   # 敏感性：纳入全部人群

fp <- fit_pool(dt_main, "main_general_population")
fpS <- fit_pool(dt_sens, "sensitivity_all_populations")

add_status("拟合", "OK",
           sprintf("主分析 %s（%d 行 / %d 研究 / %d 组合）",
                   fp$fit_mode, fp$n_rows, fp$n_study, length(fp$combos)))
add_status("合成引擎", if (HAVE_BRMS) "OK" else "WARN",
           if (HAVE_BRMS)
             sprintf(paste0("brms %s / rstan %s / StanHeaders %s；",
                            "%d chains × %d iter（warmup %d），cores=%d%s，seed=%d；",
                            "先验：b ~ N(0, 0.5)、sd(study) ~ t(3, 0, 2.5)；",
                            "抽样方差 = se²（se(sqrt(vi), sigma=%s)，%s）；Rtools45=%s"),
                     as.character(packageVersion("brms")),
                     as.character(packageVersion("rstan")),
                     as.character(packageVersion("StanHeaders")),
                     BOP_CHAINS, BOP_ITER, floor(BOP_ITER / 2), BOP_CORES,
                     if (BOP_CORES != BOP_CORES_REQ)
                       sprintf("（已由 %d 自动降级：中文路径下 rstan 并行链会挂死）", BOP_CORES_REQ) else "",
                     PA_SEED,
                     BOP_SE_SIGMA,
                     if (BOP_SE_SIGMA) "含额外残差异质性 sigma²" else "固定，与 rma.mv(V=vi) 同模型",
                     Sys.getenv("RTOOLS45_HOME"))
           else sprintf(paste0("metafor %s（REML + mvrnorm 参数自助）；",
                               "brms/rstan 不可用或 PA_BOP_ENGINE=%s"),
                        as.character(packageVersion("metafor")), BOP_ENGINE))
if (HAVE_BRMS) {
  diag_ok <- !is.na(fp$ndiv) && fp$ndiv == 0 &&
             (is.na(fp$rhat_max) || fp$rhat_max < 1.01)
  add_status("后验诊断", if (diag_ok) "OK" else "WARN",
             sprintf(paste0("主分析：发散转移 %s 次；斜率参数 max Rhat = %s；",
                            "后验抽样 %d 条（曲线池取 %d）；adapt_delta = %.2f"),
                     ifelse(is.na(fp$ndiv), "NA", format(fp$ndiv, scientific = FALSE)),
                     ifelse(is.na(fp$rhat_max), "NA", sprintf("%.4f", fp$rhat_max)),
                     nrow(fp$post), N_DRAW, BOP_ADAPT))
}
add_status("研究数", if (fp$n_study >= 3L) "OK" else "WARN",
           sprintf("%d 个研究（含方法学协变量的模型建议 ≥3）", fp$n_study))

has_self <- "self" %in% as.character(fp$dat$arm)
has_dev  <- any(grepl("^device", as.character(fp$dat$arm)))
add_status("方法覆盖", if (has_self && has_dev) "OK" else "WARN",
           paste0("主分析 arm：", paste(sort(unique(as.character(fp$dat$arm))), collapse = ", "),
                  if (!has_self) "；缺 self 组 → 无法估计方法效应" else ""))

arms_by_metric <- dt_main[, .(arms = paste(sort(unique(as.character(arm))), collapse = "+"),
                              n_rows = .N), by = metric_definition]
site_ok <- arms_by_metric[grepl("device_hip", arms) & grepl("device_wrist", arms), metric_definition]
add_status("佩戴部位覆盖",
           if (length(site_ok)) "OK" else "WARN",
           if (length(site_ok))
             sprintf("hip 与 wrist 均有覆盖的指标：%s；其余指标因**文献缺腕式来源**无法估部位效应",
                     paste(as.character(site_ok), collapse = ", "))
           else "无任何指标同时含髋式与腕式 → 部位效应不可估")

cat("\n===== Module 2 meta-regression（主分析：一般人群）=====\n")
print(summary(fp$fit))
cat("\n--- 各指标 arm 覆盖 ---\n"); print(arms_by_metric)
if (!is.null(fp$cr)) { cat("\n--- 聚类稳健检验（CR2 @ study，仅 metafor 路径）---\n"); print(fp$cr) }
if (!is.null(fp$fit$tau2)) {
  cat(sprintf("\ntau^2 = %s\n", paste(signif(fp$fit$tau2, 4), collapse = ", ")))
} else if (inherits(fp$fit, "brmsfit")) {
  cat("\n--- 组间（study）随机截距的后验 SD ---\n")
  print(brms::VarCorr(fp$fit))
  cat(sprintf("\n后验抽样：%d 条 × %d 个参数（曲线池取其中 %d 条）\n",
              nrow(fp$post), ncol(fp$post), N_DRAW))
}

# ---------------------------------------------------------------------------
# 3. 预测网格：arm 组合曲线 + 设备合并（device_pooled）曲线
# ---------------------------------------------------------------------------
combos <- fp$combos
newd <- CJ(mm = combos, offset_pts = OFFSET_GRID)
newd[, mm := factor(mm, levels = combos)]
newd[, offset := as.numeric(offset_pts)]
newd[, arm := sub("\\|.*$", "", as.character(mm))]
newd[, metric_definition := factor(sub("^.*\\|", "", as.character(mm)),
                                   levels = levels(dt$metric_definition))]
newd[, exposure_pct := offset_pts + REF_CANON]

Xc <- build_X(fp, as.character(newd$mm), newd$offset)
pc <- predict_from(fp, Xc)

tab_c <- data.table(
  curve_role        = "arm_specific",
  arm               = as.character(newd$arm),
  method            = ifelse(grepl("^device", as.character(newd$arm)), "device", "self"),
  wear_site         = unname(ARM_SITE[as.character(newd$arm)]),
  metric_definition = as.character(newd$metric_definition),
  mm                = as.character(newd$mm),
  offset_pts        = as.numeric(newd$offset_pts),
  exposure_pct      = as.numeric(newd$exposure_pct),
  rr    = exp(pc$eta),
  rr_lo = exp(pc$lo),
  rr_hi = exp(pc$hi))

# --- 设备合并曲线（供 Module 3 直接消费：每个指标恰好一条设备曲线）---
tab_dp <- rbindlist(lapply(metrics, function(md) {
  W <- pooled_w(fp, md); if (is.null(W)) return(NULL)
  nms <- names(W); w <- unlist(W)
  X <- matrix(0, nrow = length(OFFSET_GRID), ncol = length(fp$b),
              dimnames = list(NULL, names(fp$b)))
  for (i in seq_along(nms)) X[, nms[i]] <- w[i] * OFFSET_GRID
  pr <- predict_from(fp, X)
  data.table(curve_role = "device_pooled", arm = "device_pooled", method = "device",
             wear_site = "pooled", metric_definition = md, mm = "device_pooled",
             offset_pts = OFFSET_GRID, exposure_pct = OFFSET_GRID + REF_CANON,
             rr = exp(pr$eta), rr_lo = exp(pr$lo),
             rr_hi = exp(pr$hi))
}))
if (!nrow(tab_dp))
  tab_dp <- tab_c[0][, `:=`(curve_role = character(0))]

pooled <- rbind(tab_c, tab_dp, fill = TRUE)
fwrite(pooled, file.path(DIR_OUT, "Table5_bop_pooled_RR.csv"))

# --- 各 arm 组合斜率 ---
slopes <- rbindlist(lapply(combos, function(lv) {
  nm <- coef_of(fp, lv); i <- match(nm, names(fp$b))
  data.table(mm = lv, arm = sub("\\|.*$", "", lv),
             method = ifelse(grepl("^device", lv), "device", "self"),
             wear_site = unname(ARM_SITE[sub("\\|.*$", "", lv)]),
             metric_definition = sub("^.*\\|", "", lv),
             n_rows = nrow(fp$dat[mm == lv]),
             slope_per_pctpt = fp$b[i],
             se = sqrt(diag(fp$V))[i],
             rr_at_off60 = exp(fp$b[i] * OFF_EFF))
}))
slopes[, `:=`(slope_lo = slope_per_pctpt - Z975 * se,
              slope_hi = slope_per_pctpt + Z975 * se)]
fwrite(slopes, file.path(DIR_OUT, "Table5_bop_slopes.csv"))

# --- 拟合优度自检：在**观测的对比点**上比对预测 vs 观测（让失拟可见）---
mx <- NA_real_
Xobs <- build_X(fp, as.character(fp$dat$mm), fp$dat$offset)
fd <- data.table(
  row_id = fp$dat$row_id, source = fp$dat$source, arm = as.character(fp$dat$arm),
  mm = as.character(fp$dat$mm), population = as.character(fp$dat$population),
  offset = fp$dat$offset, logrr_obs = fp$dat$yi,
  logrr_pred = as.numeric(Xobs %*% fp$b))
fd[, `:=`(rr_obs = exp(logrr_obs), rr_pred = exp(logrr_pred),
          resid = logrr_obs - logrr_pred)]
fwrite(fd, file.path(DIR_OUT, "Table5_bop_fit_diagnostic.csv"))
mx <- max(abs(fd$resid), na.rm = TRUE)
add_status("拟合优度", if (mx < 0.15) "OK" else "WARN",
           sprintf("观测点最大 |log 残差| = %.3f（RR 因子 %.2f）→ Table5_bop_fit_diagnostic.csv",
                   mx, exp(mx)))
cat("\n--- 拟合优度（观测对比点）---\n")
print(fd[, .(row_id, arm, offset = round(offset, 2), rr_obs = round(rr_obs, 3),
             rr_pred = round(rr_pred, 3), resid = round(resid, 3))])

# ---------------------------------------------------------------------------
# 4. 曲线池 → B 条曲线（arm 组合 + device_pooled，供 Module 3 当"后验"）
#    贝叶斯路径：**直接取后验抽样**。n_iter ≥ N_DRAW 时用等距无放回 → 确定性、
#                不依赖 RNG 流，跨运行逐字节可复现（固定 seed 亦有）。
#    metafor 路径：退回 mvrnorm 参数自助（正态近似）。
# ---------------------------------------------------------------------------
if (!is.null(fp$post)) {
  P <- fp$post
  idx <- if (nrow(P) >= N_DRAW)
    round(seq(1, nrow(P), length.out = N_DRAW))
  else
    sample.int(nrow(P), N_DRAW, replace = TRUE)
  draws <- P[idx, , drop = FALSE]
  rownames(draws) <- NULL
  stopifnot(identical(colnames(draws), names(fp$b)))
  cat(sprintf("\n曲线池：%d 条%s后验抽样（后验共 %d 条，%s）\n",
              nrow(draws), if (is.null(fp$alias)) "参数自助" else " ",
              nrow(P), if (nrow(P) >= N_DRAW) "等距无放回" else "有放回重抽"))
} else {
  Vs <- (fp$V + t(fp$V)) / 2
  set.seed(PA_SEED)
  draws <- tryCatch(MASS::mvrnorm(N_DRAW, mu = fp$b, Sigma = Vs),
                    error = function(e) {
                      message("mvrnorm 失败（", conditionMessage(e), "）→ 改用对角近似")
                      MASS::mvrnorm(N_DRAW, mu = fp$b, Sigma = diag(pmax(diag(Vs), 0)))
                    })
}

meta_all <- rbind(
  tab_c[, .(curve_role, arm, method, wear_site, metric_definition, mm,
            offset_pts, exposure_pct)],
  tab_dp[, .(curve_role, arm, method, wear_site, metric_definition, mm,
             offset_pts, exposure_pct)],
  fill = TRUE)
X_all <- rbind(Xc, do.call(rbind, lapply(metrics, function(md) {
  W <- pooled_w(fp, md); if (is.null(W)) return(NULL)
  nms <- names(W); w <- unlist(W)
  X <- matrix(0, nrow = length(OFFSET_GRID), ncol = length(fp$b),
              dimnames = list(NULL, names(fp$b)))
  for (i in seq_along(nms)) X[, nms[i]] <- w[i] * OFFSET_GRID
  X
})))
rr_draw <- exp(draws %*% t(X_all))

saveRDS(list(offset_grid = as.numeric(meta_all$offset_pts),
             pct_grid    = as.numeric(meta_all$exposure_pct),
             ref_canon   = REF_CANON,
             arm         = as.character(meta_all$arm),
             method      = as.character(meta_all$method),
             wear_site   = as.character(meta_all$wear_site),
             curve_role  = as.character(meta_all$curve_role),
             metric      = as.character(meta_all$metric_definition),
             mm          = as.character(meta_all$mm),
             draws       = rr_draw,
             seed = PA_SEED, n_draw = N_DRAW, fit_mode = fp$fit_mode,
             engine      = if (is.null(fp$alias)) "metafor_REML_parametric_bootstrap"
                           else "brms_rstan_posterior",
             posterior   = !is.null(fp$post),
             n_post      = if (is.null(fp$post)) NA_integer_ else nrow(fp$post),
             chains      = if (is.null(fp$post)) NA_integer_ else BOP_CHAINS,
             iter        = if (is.null(fp$post)) NA_integer_ else BOP_ITER,
             prior_note  = paste0("b ~ Normal(0, 0.5)；sd(study) ~ Student-t(3, 0, 2.5)；",
                                  "抽样方差 = se² + 组间 τ²（se(sqrt(vi), sigma=", BOP_SE_SIGMA, ")）"),
             note = paste0("x 轴 = offset（相对**该研究自身参照类别**的百分位点），",
                           "RR(offset=0) 恒为 1。pct_grid = offset + ", REF_CANON,
                           " 为**约定**映射（假定参照位于第 12.5 百分位），非估计量。",
                           "curve_role=='device_pooled' 是供 Module 3 直接使用的**唯一设备曲线**",
                           "（跨佩戴部位逆方差合并）；arm_specific 行是各臂明细。",
                           "Module 3 需用 NHANES 分布做分位→MIMS 映射。")),
        file.path(DIR_OUT, "bop_rr_draws.rds"))
add_status("RR 曲线集", "OK",
           sprintf("%d 条 × %d 行（arm 组合 %d + 设备合并 %d）→ bop_rr_draws.rds",
                   N_DRAW, nrow(meta_all), nrow(tab_c), nrow(tab_dp)))

# ---------------------------------------------------------------------------
# 5a. 方法效应（**同指标内** device_pooled vs self）
#     比值 = RR_dev(off) / RR_self(off) = exp((Σw_k b_k − b_self) · off)
#     注意：device 侧现由多个 arm 组成 → 用逆方差权重合并（权重视为固定，
#     不传播权重自身的不确定性 → SE 略偏乐观，Methods 须声明）。
# ---------------------------------------------------------------------------
me <- rbindlist(lapply(metrics, function(md) {
  lv_s <- paste0("self|", md)
  if (!(lv_s %in% combos)) return(NULL)
  W <- pooled_w(fp, md); if (is.null(W)) return(NULL)
  w <- setNames(unlist(W), names(W))
  w[coef_of(fp, lv_s)] <- -1
  ct <- contrast(fp, w)
  d  <- ct$est
  data.table(
    metric_definition = md,
    # ⚠️ 必须用 coef_label() 把系数名翻回对外标签：贝叶斯路径下 names(W) 是 brms 安全码
    #    （b_mmckNN:offset），直接 sub("\\|.*$","") 不起作用 → 会把内部标识写进论文附表。
    arms_device = paste(sub("\\|.*$", "",
                            vapply(names(W), function(cn) coef_label(fp, cn), "")),
                        collapse = "+"),
    n_rows_device = sum(fp$dat[grepl("^device", as.character(arm)) &
                                 metric_definition == md, .N]),
    n_rows_self = fp$dat[arm == "self" & metric_definition == md, .N],
    slope_device_pooled = sum(unlist(W) * fp$b[names(W)]),
    slope_self = fp$b[coef_of(fp, lv_s)], slope_diff = d,
    rr_ratio_at_off60 = exp(d * OFF_EFF),
    rr_ratio_lo = exp(ct$lo * OFF_EFF),
    rr_ratio_hi = exp(ct$hi * OFF_EFF),
    p_diff = ct$p,
    note = sprintf("offset=0 时 RR 均为 1；offset=%d 处 device（跨部位合并）的 RR ÷ self 的 RR", OFF_EFF))
}))
if (!nrow(me)) {
  me <- data.table(metric_definition = NA_character_, arms_device = NA_character_,
                   n_rows_device = NA_integer_, n_rows_self = NA_integer_,
                   slope_device_pooled = NA_real_, slope_self = NA_real_,
                   slope_diff = NA_real_, rr_ratio_at_off60 = NA_real_,
                   rr_ratio_lo = NA_real_, rr_ratio_hi = NA_real_,
                   p_diff = NA_real_, note = NA_character_)
  add_status("方法效应", "MISSING", "池中缺 self 组或两方法无同指标 → 无法估计")
} else {
  add_status("方法效应", "OK",
             sprintf("同指标内 device vs self：%s",
                     paste(sprintf("%s RR 比 %.3f [%.3f, %.3f] @off%d", me$metric_definition,
                                   me$rr_ratio_at_off60, me$rr_ratio_lo, me$rr_ratio_hi, OFF_EFF),
                           collapse = "; ")))
}
fwrite(me, file.path(DIR_OUT, "Table5_bop_method_effect.csv"))

# ---------------------------------------------------------------------------
# 5b. 佩戴部位效应（**同指标内** device_hip vs device_wrist）—— 本轮新增
#     动机：NHANES 暴露是腕式，而主分析前的设备证据全部来自髋式/混合
#     → 「设备 vs 自报」把**佩戴部位**差异一起吞掉了。补齐腕式来源后，
#       在 LPA 上首次可把部位效应单独估出来，从而给"髋式曲线能否外推到腕式
#       暴露分布"这一关键问题一个**定量上界**。
# ---------------------------------------------------------------------------
site_rows <- function(d, tag, md_use = metrics) {
  out <- list()
  for (md in md_use) {
    lv_h <- paste0("device_hip|", md); lv_w <- paste0("device_wrist|", md)
    if (!all(c(lv_h, lv_w) %in% d$combos)) next
    wh <- coef_of(d, lv_h); ww <- coef_of(d, lv_w)
    ct <- contrast(d, setNames(c(1, -1), c(wh, ww)))
    n_hip <- d$dat[grepl("device_hip", as.character(arm)) & metric_definition == md, .N]
    n_wri <- d$dat[grepl("device_wrist", as.character(arm)) & metric_definition == md, .N]
    for (of in unique(c(OFF_EFF, OFF_EXTRA))) {
      out[[length(out) + 1L]] <- data.table(
        spec = tag, metric_definition = md,
        slope_hip = d$b[wh], slope_wrist = d$b[ww],
        slope_diff_hip_minus_wrist = ct$est,
        n_rows_hip = n_hip, n_rows_wrist = n_wri,
        offset_pts = of,
        rr_ratio_hip_over_wrist = exp(ct$est * of),
        rr_ratio_lo = exp(ct$lo * of),
        rr_ratio_hi = exp(ct$hi * of),
        p_diff = ct$p,
        note = "比值 = 髋式 RR ÷ 腕式 RR（同一指标、同一相对百分位）")
    }
  }
  if (!length(out)) return(data.table())
  rbindlist(out, fill = TRUE)
}
site_tab <- rbind(site_rows(fp, "main_general_population"),
                  site_rows(fpS, "sensitivity_all_populations"),
                  fill = TRUE)
if (!nrow(site_tab)) {
  site_tab <- data.table(spec = NA_character_, metric_definition = NA_character_)
  add_status("佩戴部位效应", "MISSING",
             "无指标同时含髋式与腕式设备来源 → 部位效应不可估")
} else {
  head_site <- site_tab[spec == "main_general_population" &
                          offset_pts == OFF_EFF]
  add_status("佩戴部位效应", "OK",
             sprintf("同指标内 hip vs wrist（主分析）：%s",
                     paste(sprintf("%s 髋/腕 RR 比 %.3f [%.3f, %.3f], p=%.4f",
                                   head_site$metric_definition,
                                   head_site$rr_ratio_hip_over_wrist,
                                   head_site$rr_ratio_lo, head_site$rr_ratio_hi,
                                   head_site$p_diff), collapse = "; ")))
}
fwrite(site_tab, file.path(DIR_OUT, "Table5_bop_wear_site.csv"))

# ---------------------------------------------------------------------------
# 5c. 敏感性：加入**共享曲率项**（标准化列 (offset/OFF_EFF)^2，见 fit_pool() 注释）
#     动机：真实剂量-反应是 L 形（前段陡、后段平），"过原点单调直线"在 Ekelund2019
#     的观测点上留下系统性失拟。共享曲率是唯一在 2 点组合（Tarp/PURE）下仍可识别的
#     最小修正。本块只做**稳健性对照**，不替换主分析。
#     ⚠️ 2026-10-16 修：曲率列原先直接用 offset^2 → 贝叶斯后验 max Rhat = 3.61（未收敛），
#        方法效应 RR 的 97.5% 分位虚高到 88674。改为标准化列后 Rhat = 1.011、残差 0.319
#        （< 主分析 0.399），且与 metafor REML 逐位吻合。详见 fit_pool() 内的完整记录。
# ---------------------------------------------------------------------------
curv_ok  <- FALSE
conv_ok  <- TRUE      # 曲率模型的**收敛**门禁（贝叶斯路径才真正生效）
curv <- tryCatch({
  # 走同一个 fit_pool()（curvature=TRUE）→ 引擎、先验、抽样设置与主分析完全一致，
  # 避免"主分析贝叶斯、稳健性却用 REML"的口径分裂。
  fp2 <- fit_pool(dt_main, "curvature_main_general_population", curvature = TRUE)
  b2  <- fp2$b; V2 <- fp2$V
  qn  <- names(b2)[!grepl(":offset$", names(b2))]
  if (length(qn) != 1L) stop("曲率模型的非斜率系数不唯一（", length(qn), " 个）")
  qn  <- qn[1]
  bayes2 <- !is.null(fp2$post)
  conv_ok <- if (!bayes2) TRUE else
    (!is.na(fp2$ndiv) && fp2$ndiv == 0 &&
       (is.na(fp2$rhat_max) || fp2$rhat_max < 1.02))
  add_status("曲率模型后验诊断",
             if (!bayes2) "—" else if (conv_ok) "OK" else "WARN",
             if (!bayes2) "非贝叶斯引擎（metafor REML），无后验诊断可查"
             else sprintf("共享曲率模型：发散转移 %s 次；全部系数 max Rhat = %s（阈值 1.02）",
                          ifelse(is.na(fp2$ndiv), "NA", format(fp2$ndiv, scientific = FALSE)),
                          ifelse(is.na(fp2$rhat_max), "NA", sprintf("%.4f", fp2$rhat_max))))
  X2o <- build_X(fp2, as.character(fp2$dat$mm), fp2$dat$offset, curvature = TRUE)
  r2  <- fp2$dat$yi - as.numeric(X2o %*% b2)
  rows <- rbindlist(lapply(metrics, function(md) {
    lv_s <- paste0("self|", md)
    lvs  <- device_arm_lvs(fp2, md)
    if (!length(lvs) || !(lv_s %in% combos)) return(NULL)
    W <- pooled_w(fp2, md); if (is.null(W)) return(NULL)
    w <- setNames(unlist(W), names(W))
    w[coef_of(fp2, lv_s)] <- -1
    ct <- contrast(fp2, w)
    data.table(metric_definition = md,
               # 曲率项有两套等价刻度，同时给出以便审稿人核对：
               #   · curvature_logrr_at_off60 = 标准化列的系数，**直接就是** offset=OFF_EFF 处的 log-RR 曲率贡献；
               #   · curvature_per_pct2        = 换算回"每百分位²"的原始系数（可与 metafor 输出直接对账）。
               curvature_logrr_at_off60 = b2[[qn]],
               curvature_per_pct2 = b2[[qn]] / (fp2$curv_scale^2),
               max_abs_logresid_fixed = max(abs(r2)),
               rr_ratio_at_off60 = exp(ct$est * OFF_EFF),
               rr_ratio_lo = exp(ct$lo * OFF_EFF),
               rr_ratio_hi = exp(ct$hi * OFF_EFF))
  }))
  if (!nrow(rows)) stop("曲率模型无可用对比行")
  rows[, spec := "linear_plus_shared_curvature"]
  add_status("曲率模型引擎", "OK", fp2$fit_mode)
  curv_ok <- TRUE
  rows
}, error = function(e) { message("曲率敏感性不可用：", conditionMessage(e)); NULL })

me_main <- copy(me)[, spec := "linear_through_origin_main"]
if (curv_ok) {
  sens <- rbind(
    me_main[!is.na(metric_definition),
            .(spec, metric_definition, slope_device_pooled, slope_self,
              rr_ratio_at_off60, rr_ratio_lo, rr_ratio_hi,
              curvature_logrr_at_off60 = NA_real_, curvature_per_pct2 = NA_real_,
              max_abs_logresid_fixed = NA_real_)],
    curv[, .(spec, metric_definition,
             slope_device_pooled = NA_real_, slope_self = NA_real_,
             rr_ratio_at_off60, rr_ratio_lo, rr_ratio_hi,
             curvature_logrr_at_off60, curvature_per_pct2, max_abs_logresid_fixed)],
    fill = TRUE)
} else {
  sens <- me_main[!is.na(metric_definition),
                  .(spec, metric_definition, slope_device_pooled, slope_self,
                    rr_ratio_at_off60, rr_ratio_lo, rr_ratio_hi)]
}
fwrite(sens, file.path(DIR_OUT, "Table5_bop_sensitivity_curvature.csv"))
add_status("曲率敏感性",
           if (!curv_ok) "WARN"
           else if (conv_ok && max(abs(curv$max_abs_logresid_fixed)) < mx) "OK" else "WARN",
           if (!curv_ok) "曲率项不可识别 → 仅报主分析"
           else sprintf(paste0("共享曲率后固定部分最大 |log 残差| %.3f（主分析 %.3f → %s）；",
                               "曲率项量级 %.3f/off60（= %.2e 每百分位²）；收敛=%s → ",
                               "Table5_bop_sensitivity_curvature.csv"),
                        max(abs(curv$max_abs_logresid_fixed)), mx,
                        ifelse(max(abs(curv$max_abs_logresid_fixed)) < mx, "失拟减小，方向正确", "失拟反增，须查"),
                        max(abs(curv$curvature_logrr_at_off60)),
                        max(abs(curv$curvature_per_pct2)),
                        ifelse(conv_ok, "是", "否（详见「曲率模型后验诊断」）")))

# ---------------------------------------------------------------------------
# 6. 就绪度门禁
# ---------------------------------------------------------------------------
ready <- (fp$n_study >= 3L) && has_self && has_dev
add_status("Module 3 可用性", if (ready) "READY" else "NOT_READY",
           if (ready) "可替换 DRYRUN_S3 占位曲线（用 curve_role=='device_pooled' 行）"
           else "仍为占位阶段：Module 3 继续用 DRYRUN_S3，并在局限性中声明")
add_status("临床亚组隔离",
           if (any(as.character(dt$population) == "clinical_subgroup")) "OK" else "—",
           sprintf("主分析限一般人群（%d 行）；另纳入临床亚组 %d 行作敏感性（spec=%s）",
                   nrow(dt_main),
                   nrow(dt[population == "clinical_subgroup"]),
                   "sensitivity_all_populations"))

st <- write_status()
cat("\n===== Module 2 状态 =====\n"); print(st)
cat("\n各 arm 组合斜率（每 1 个百分位点）：\n"); print(slopes)
cat("\n方法效应：\n"); print(me)
cat("\n佩戴部位效应：\n"); print(site_tab)
cat("\n产物：Table5_bop_pooled_RR.csv | Table5_bop_method_effect.csv |",
    "Table5_bop_wear_site.csv | Table5_bop_slopes.csv | bop_rr_draws.rds | QC_bop_status.csv\n")
if (!ready)
  cat("\n⚠️ 当前为**试点池**（研究数或方法覆盖不足）。",
      "完整 Module 2 需按 data/bop/README.md 补齐外部队列。\n", sep = "")
