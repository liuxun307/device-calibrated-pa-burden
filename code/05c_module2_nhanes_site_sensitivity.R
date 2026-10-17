# =============================================================================
# 05c_module2_nhanes_site_sensitivity.R
# 路径 2 收尾：把本项目自算的两条 NHANES 曲线**受控地**接入 BoP 池，量化其影响
# =============================================================================
# 谜题与裁定（2026-10-12）
# -----------------------------------------------------------------------------
# 04b 给了两条同国家、同调查体系、同协变量定义、同百分位锚点的曲线：
#   NHANES 2003-2006 髋式（ActiGraph 7164, counts/day）
#   NHANES 2011-2014 腕式（GT3X+, MIMS/day）
# 两者在百分位轴上几乎重合 → 部位效应比值全点与 1 无差异。
#
# 但**文献侧**的部位效应（05a 的 Table5_bop_wear_site.csv，唯一可估的 LPA）给出
#   RR_hip / RR_wrist @offset 60 = 0.658 [0.496, 0.873], p = 0.0037
# 即：同百分位下髋式曲线**更陡**。两者方向不一致。
#
# 那么该不该把 NHANES 两臂写进 data/bop/rr_table.csv、让主分析吸收它？
# ⛔ 不该 —— 三条理由，必须写进 Methods：
#   ① **定位冲突**：Module 2 的立论是「池化**外部**文献队列以支持全球外推」。
#      把本项目自算的分析注入其中，等于让「外部证据」部分变成自我循环（同一批
#      NHANES 数据既定义百分位分布、又贡献 RR），大幅削弱外推声明的独立性。
#   ② **设计不可通约**：NHANES 用**单次 7 天基线测量**、随访 13–16 年；
#      池内 Ekelund2019 为 5.8 年、UKB 系为 8 年。随访越长 → 回归稀释 + 反向因果
#      越重 → 估计越向 1 衰减。NHANES 曲线整体比池化曲线平（offset 80 处
#      RR 0.509 vs 池化 0.373）正是这个机制的产物，而非"更准"。
#   ③ **权重压倒**：NHANES 每点 log-SE ≈ 0.028，EK19 约 0.058 → 固定效应意义上
#      权重约 4 倍。并入后池化曲线会被一个**设计不可比的**来源整体拽平，
#      属"设计差异驱动"而非"信息量驱动"的变动。
#
# ✅ 正确用法（本脚本实现）：把 NHANES 当作**受控敏感性池**，而非主池输入。
#   主池 data/bop/rr_table.csv **一个字节都不改** → 05a 的 Table5_* 与
#   bop_rr_draws.rds 保持 ② 的冻结状态与逐字节可复现。
#
# 三档对照
#   spec A = primary_only        原池 22 行（= 复现 05a 主分析，作为对照基准）
#   spec B = primary_plus_nhanes 原池 + NHANES 两臂 ×8 点 = 38 行
#   spec C = nhanes_only         仅 NHANES 两臂 ×8 点 = 16 行
#
# 产出
#   data/bop/rr_table_nhanes_sensitivity.csv   追加后的输入快照（审计用，非主输入）
#   output/Table7_bop_nhanes_site_sensitivity.csv  三档 × 部位效应对比
#   output/Table7_bop_nhanes_pooled_curve.csv      A vs B 的 device_pooled|total_PA 曲线
#   output/Table7_bop_nhanes_weight_share.csv      NHANES 在 B 档各组合中的权重占比
#   output/bop_rr_draws_withNHANES.rds             B 档后验（**不覆盖** bop_rr_draws.rds）
#   output/QC_bop_nhanes_sensitivity.csv           就绪度与门禁
#   logs/module2_nhanes_sensitivity.log
#
# ⚠️ 本脚本**只读** rr_table.csv；写入 extraction_log.csv 使用 append 模式，
#    以保留原文件的 BOM 与既有字节。
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
suppressPackageStartupMessages({ library(data.table); library(metafor) })
pa_log("===== 05c 路径 2 收尾：NHANES 两臂接入 BoP 池的受控敏感性 =====")

DIR_BOP <- file.path(PA_ROOT, "data", "bop")
RR_CSV  <- file.path(DIR_BOP, "rr_table.csv")
T6_CSV  <- file.path(DIR_OUT, "Table6_nhanes_hip_wrist_RR.csv")
LOG_CSV <- file.path(DIR_BOP, "extraction_log.csv")
SNAP_CSV<- file.path(DIR_BOP, "rr_table_nhanes_sensitivity.csv")

N_DRAW      <- 1000L
Z975        <- 1.959964
REF_CANON   <- 12.5
OFFSET_GRID <- seq(0, 90, by = 5)
OFF_EFF     <- 60
OFF_EXTRA   <- c(25, 50, 75)
ARM_LEVELS  <- c("self", "device_hip", "device_mixed", "device_wrist")
POP_LEVELS  <- c("general", "clinical_subgroup")

# ---------------------------------------------------------------------------
# 共享合成引擎（关键，2026-10-16）
#   本脚本的三档 A/B/C **必须与 05a 用同一引擎**，否则：
#     ① Methods 无法自洽（一处贝叶斯、一处 REML）；
#     ② 下面第 5 节「A 档逐值复现 05a 主产物（< 1e-6）」的自检不可能成立——
#        A 档的数据就是 05a 的 dt_main，只有同引擎 + 同 seed 才可能逐值一致。
#   模块提供 fit_pool() 及 coef_of/build_X/predict_from/contrast/
#   device_arm_lvs/pooled_w，并自行读 PA_BOP_ENGINE / PA_BOP_SE_SIGMA 等开关。
# ---------------------------------------------------------------------------
local({
  .cand <- c(file.path(getwd(), "lib", "pa_bop_engine.R"),
             file.path(DIR_CODE, "lib", "pa_bop_engine.R"))
  .hit <- .cand[file.exists(.cand)]
  if (!length(.hit)) stop("未找到 lib/pa_bop_engine.R：请 setwd() 到 code/ 目录后重试")
  source(.hit[1], local = FALSE)
  pa_log(sprintf("[05c] 已加载共享引擎：%s", .hit[1]))
  pa_log(sprintf("[05c] 引擎=%s（HAVE_BRMS=%s，cores=%d/%d，seed=%d）",
                 BOP_ENGINE, HAVE_BRMS, BOP_CORES, BOP_CORES_REQ, PA_SEED))
})

if (!file.exists(RR_CSV)) stop("缺少 ", RR_CSV, " —— 请先跑通 05a。")
if (!file.exists(T6_CSV)) stop("缺少 ", T6_CSV, " —— 请先跑通 04b。")

# ---------------------------------------------------------------------------
# 1. 构造 NHANES 两臂的行（按 rr_table.csv 的同一 schema）
# ---------------------------------------------------------------------------
t6 <- fread(T6_CSV, encoding = "UTF-8")
stopifnot(all(c("pct","offset_pts","expo_hip","expo_wrist",
                "rr_hip","rr_hip_lo","rr_hip_hi",
                "rr_wrist","rr_wrist_lo","rr_wrist_hi") %in% names(t6)))

# 参照点（pct=12.5, offset=0）按构造 RR=1，不入表（与池内其它研究一致：只放对比点）
t6c <- t6[offset_pts > 0]

# 样本量与事件数直接取自 04b 的拟合诊断（避免两处硬编码漂移）
diag_p <- file.path(DIR_OUT, "QC_pam_site_fit.csv")
if (!file.exists(diag_p)) stop("缺少 ", diag_p, " —— 请先跑通 04b。")
dg <- fread(diag_p, encoding = "UTF-8")
gv <- function(k) as.numeric(dg[item == k, value][1])
N_HIP <- gv("建模样本(髋式)"); D_HIP <- gv("死亡(髋式)")
N_WRI <- gv("建模样本(腕式)"); D_WRI <- gv("死亡(腕式)")

# 描述性协变量：在 04b 的同一建样子集上复算（同过滤规则，逐字照抄 04b）
subset_of <- function(dt, expo_col) {
  md <- dt[!is.na(surv_mo) & surv_mo > 0]
  for (v in c(expo_col, "age","female","race","educ","pir","bmi","sbp",
              "cur_smoke","drink_any","diabetes","cvd_hx","WTMEC4YR"))
    md <- md[!is.na(get(v))]
  md
}
hip_d <- as.data.table(readRDS(file.path(DIR_DERIV, "pam_2003_2006.rds")))
hip_d[, expo := counts_per_day]
wri_d <- as.data.table(readRDS(file.path(DIR_DERIV, "analytic.rds")))
wri_d[, expo := mims_per_day]
md_hip <- subset_of(hip_d, "expo"); md_wri <- subset_of(wri_d, "expo")
stopifnot(nrow(md_hip) == N_HIP, nrow(md_wri) == N_WRI)   # 与 04b 对齐的自校验

wmean_age <- function(md) sum(md$age * md$WTMEC4YR, na.rm = TRUE) / sum(md$WTMEC4YR, na.rm = TRUE)
med_fu    <- function(md) median(md$surv_mo, na.rm = TRUE) / 12
AGE_HIP <- wmean_age(md_hip); FU_HIP <- med_fu(md_hip)
AGE_WRI <- wmean_age(md_wri); FU_WRI <- med_fu(md_wri)

mk_rows <- function(site) {
  if (site == "hip") {
    d <- data.table(pct = t6c$pct, expo = t6c$expo_hip,
                    hr = t6c$rr_hip, lo = t6c$rr_hip_lo, hi = t6c$rr_hip_hi)
    list(src = "NHANES_own_2003_2006_hip", study = "NHANES_own_2003_2006_hip",
         dev = "ActiGraph 7164 (uniaxial, hip)", ws = "hip",
         unit = "counts/day", n = N_HIP, d = D_HIP, age = AGE_HIP, fu = FU_HIP, d2 = d)
  } else {
    d <- data.table(pct = t6c$pct, expo = t6c$expo_wrist,
                    hr = t6c$rr_wrist, lo = t6c$rr_wrist_lo, hi = t6c$rr_wrist_hi)
    list(src = "NHANES_own_2011_2014_wrist", study = "NHANES_own_2011_2014_wrist",
         dev = "ActiGraph GT3X+ (triaxial, MIMS)", ws = "wrist",
         unit = "MIMS/day", n = N_WRI, d = D_WRI, age = AGE_WRI, fu = FU_WRI, d2 = d)
  }
}

NHN <- rbindlist(lapply(c("hip", "wrist"), function(s) {
  z <- mk_rows(s)
  z$d2[, `:=`(
    row_id              = sprintf("%s_P%g", sub("^NHANES_own_", "NH", z$src), pct),
    source              = z$src,
    study               = z$study,
    design              = "own_analysis_svycox_ns",
    method              = "device",
    device_type         = z$dev,
    wear_site           = z$ws,
    metric_definition   = "total_PA",
    exposure_scale      = "pct_weighted_quantile",
    exposure_center     = pct,
    exposure_ref_center = REF_CANON,
    exposure_orig_unit  = z$unit,
    exposure_orig_lo    = round(expo, 1),
    exposure_orig_hi    = NA_real_,
    category_n          = nrow(t6c),
    pct_rule            = "imposed_weighted_quantile_grid",
    outcome             = "all_cause",
    n_total             = z$n,
    n_cases             = z$d,
    hr = hr, hr_lo = lo, hr_hi = hi,
    sex = "mixed",
    mean_age = round(z$age, 1),
    followup_y = round(z$fu, 1),
    region = "US",
    population = "general",
    pmid = NA_character_,
    doi  = NA_character_,
    notes = sprintf(paste0(
      "【本项目自算，非文献抽取】NHANES %s，svycoxph + 自然样条(4 df) + 全套协变量；",
      "暴露 = 有效日日均总活动量（%s）；百分位为**人群加权分位**，参照 = 12.5 百分位",
      "（= 最低四分位中点，与 BoP ref_canon 一致）→ 可与池内研究同轴比较；",
      "⚠️ 设计差异：单次 7 天基线测量、随访中位 %.1f 年（池内 EK19 为 5.8 年）→ ",
      "回归稀释与反向因果更重，曲线整体向 1 衰减；⚠️ 权重远大于池内研究（log-SE ≈ 0.028 ",
      "vs 0.058）→ 并入后会把池化曲线整体拽平，属设计差异驱动。故仅作敏感性，不入主池。",
      "口径差异：2003-2006 的 wear 判定用 rnhanesdata Flags（Choi et al. 2011 算法），",
      "2011-2014 用 CDC 官方 PAXPREDM → 同类判定的不同实现，须在局限中声明。"),
      ifelse(z$ws == "hip", "2003-2006（髋式）", "2011-2014（腕式）"),
      z$unit, z$fu))]
}))

pa_log(sprintf("NHANES 两臂：%d 行（髋式 n=%d/%d 死亡，腕式 n=%d/%d 死亡）",
               nrow(NHN), N_HIP, D_HIP, N_WRI, D_WRI))

# ---------------------------------------------------------------------------
# 2. 三档数据
# ---------------------------------------------------------------------------
dt0 <- fread(RR_CSV, encoding = "UTF-8")
dt0[, .spec_src := "primary"]
NHN[,  .spec_src := "nhanes"]

# 主池与 NHANES 行的列对齐（NHN 多一列 .spec_src；缺列由 rbind(fill=TRUE) 补齐）
NHN[, .spec_src := "nhanes"]

SPECS <- list(
  A_primary_only        = copy(dt0),
  B_primary_plus_nhanes = rbind(dt0, NHN, use.names = TRUE, fill = TRUE),
  C_nhanes_only         = copy(NHN))

# 审计快照（追加后输入的可读版本；**不是**主输入）
fwrite(SPECS$B_primary_plus_nhanes, SNAP_CSV)

# ---------------------------------------------------------------------------
# 3. 拟合引擎（**与 05a 同一实现**，见上方 lib/pa_bop_engine.R 的 source）
#    FORM_MAIN / FORM_CURV / fit_pool 等均由共享模块提供，本脚本不再重复定义。
# ---------------------------------------------------------------------------

prep <- function(d, tag) {
  d <- copy(d)
  d <- d[!is.na(hr) & !is.na(hr_lo) & !is.na(hr_hi) & !is.na(exposure_center)]
  # ⚠️ 与 05a 主分析同规则：只保留一般人群 —— 否则 Cao2024（既往 CVD 亚组）会进入
  #    REML 的 tau^2 估计，使 A 档**无法**逐值复现 05a。这是 A 档作为对照基准的前提。
  n0 <- nrow(d)
  d <- d[population == "general"]
  if (n0 != nrow(d))
    pa_log(sprintf("[%s] 剔除非一般人群 %d 行（与 05a 主分析同规则）", tag, n0 - nrow(d)))
  if (!nrow(d)) stop(tag, "：过滤后无可用行")
  bad <- d[hr_lo <= 0 | hr <= 0 | hr_lo > hr | hr > hr_hi]
  if (nrow(bad)) stop(tag, "：HR/CI 不合法：", paste(bad$row_id, collapse = ", "))
  if (any(d$exposure_center <= d$exposure_ref_center))
    stop(tag, "：存在 exposure_center <= exposure_ref_center 的行")
  d[, arm := fcase(
    method == "self",                          "self",
    method == "device" & wear_site == "hip",   "device_hip",
    method == "device" & wear_site == "wrist", "device_wrist",
    method == "device" & wear_site == "mixed", "device_mixed",
    default = NA_character_)]
  if (anyNA(d$arm)) stop(tag, "：无法归入 arm：", paste(d[is.na(arm), row_id], collapse = ", "))
  d[, `:=`(yi = log(hr), vi = ((log(hr_hi) - log(hr_lo)) / (2 * Z975))^2,
           offset = exposure_center - exposure_ref_center)]
  d[, metric_definition := factor(metric_definition)]
  d[, arm := factor(arm, levels = ARM_LEVELS)]
  d[, mm := droplevels(factor(paste(as.character(arm), as.character(metric_definition), sep = "|")))]
  d
}

# 拟合：**转为薄封装**，实体在 lib/pa_bop_engine.R 的 fit_pool()
#   （原实为 metafor::rma.mv(REML)；2026-10-16 起与 05a 统一走真贝叶斯。
#    保留 fit_spec 这个名字与返回契约，使下游零改动。）
fit_spec <- function(dat, tag) fit_pool(prep(dat, tag), tag)

# ⚠️ 以下 coef_of / contrast / predict_from / device_arm_lvs / pooled_w
#    原为 05c 自带的 metafor 版实现，**已删除**，统一由 lib/pa_bop_engine.R 提供：
#      · 其 coef_of 会读 fp$alias（brms 的安全码项名无法靠 "arm|metric" 子串反查）；
#      · contrast / predict_from 在贝叶斯路径下改用后验分位（与 05a 同口径）。
# 预测 device_pooled 曲线（逆方差合并设备各臂）
pooled_curve <- function(fp, md, grid) {
  W <- pooled_w(fp, md); if (is.null(W)) return(NULL)
  nms <- names(W); w <- unlist(W)
  X <- matrix(0, nrow = length(grid), ncol = length(fp$b),
              dimnames = list(NULL, names(fp$b)))
  for (i in seq_along(nms)) X[, nms[i]] <- w[i] * grid
  pr <- predict_from(fp, X)
  # 区间口径与 05a 一致：贝叶斯路径取后验分位（pr$lo/hi），metafor 路径退回 Wald
  lo <- if (!is.null(pr$lo)) exp(pr$lo) else exp(pr$eta - Z975 * pr$se)
  hi <- if (!is.null(pr$hi)) exp(pr$hi) else exp(pr$eta + Z975 * pr$se)
  list(X = X, rr = exp(pr$eta), lo = lo, hi = hi, nms = nms, w = w)
}

FIT <- lapply(names(SPECS), function(s) {
  fp <- fit_spec(SPECS[[s]], s)
  pa_log(sprintf("[%s] %d 行 / %d 研究 / 组合 %s",
                 s, fp$n_rows, fp$n_study, paste(fp$combos, collapse = " + ")))
  fp
})
names(FIT) <- names(SPECS)

# ---------------------------------------------------------------------------
# 4. 部位效应：三档对比（同指标内 hip vs wrist）
# ---------------------------------------------------------------------------
site_rows <- function(fp, md) {
  lv_h <- paste0("device_hip|", md); lv_w <- paste0("device_wrist|", md)
  if (!all(c(lv_h, lv_w) %in% fp$combos)) return(NULL)
  wh <- coef_of(fp, lv_h); ww <- coef_of(fp, lv_w)
  ct <- contrast(fp, setNames(c(1, -1), c(wh, ww)))
  rbindlist(lapply(unique(c(OFF_EFF, OFF_EXTRA)), function(of) {
    data.table(
      metric_definition = md,
      offset_pts = of,
      slope_hip   = fp$b[wh],
      slope_wrist = fp$b[ww],
      slope_diff_hip_minus_wrist = ct$est,
      n_rows_hip   = fp$dat[arm == "device_hip"   & metric_definition == md, .N],
      n_rows_wrist = fp$dat[arm == "device_wrist" & metric_definition == md, .N],
      rr_ratio_hip_over_wrist = exp(ct$est * of),
      # 区间口径与 05a 的 5b 一致：贝叶斯路径取后验分位（ct$lo/hi），metafor 路径退回 Wald
      rr_ratio_lo = if (!is.null(ct$lo)) exp(ct$lo * of) else exp(ct$est * of - Z975 * of * ct$se),
      rr_ratio_hi = if (!is.null(ct$hi)) exp(ct$hi * of) else exp(ct$est * of + Z975 * of * ct$se),
      p_diff = ct$p)
  }))
}

SITE <- rbindlist(lapply(names(FIT), function(s) {
  fp <- FIT[[s]]
  mds <- sort(unique(as.character(fp$dat$metric_definition)))
  r <- rbindlist(lapply(mds, function(md) site_rows(fp, md)), use.names = TRUE, fill = TRUE)
  if (!nrow(r)) return(NULL)
  r[, `:=`(spec = s, n_study = fp$n_study, n_rows = fp$n_rows)]
  r
}), use.names = TRUE, fill = TRUE)
setcolorder(SITE, c("spec","n_study","n_rows","metric_definition"))
SITE[, note := "比值 = 髋式 RR ÷ 腕式 RR（同指标、同相对百分位；>1 表示髋式更陡）"]
fwrite(SITE, file.path(DIR_OUT, "Table7_bop_nhanes_site_sensitivity.csv"))

# ---------------------------------------------------------------------------
# 5. device_pooled × total_PA 曲线：A vs B（Module 3 的实际输入）
# ---------------------------------------------------------------------------
gd <- OFFSET_GRID
curA <- pooled_curve(FIT$A_primary_only, "total_PA", gd)
curB <- pooled_curve(FIT$B_primary_plus_nhanes, "total_PA", gd)
curC <- pooled_curve(FIT$C_nhanes_only, "total_PA", gd)
if (is.null(curA) || is.null(curB)) stop("device_pooled × total_PA 曲线缺失")

CMP <- data.table(
  offset_pts = gd,
  pct = gd + REF_CANON,
  rr_A_primary = curA$rr, A_lo = curA$lo, A_hi = curA$hi,
  rr_B_plus_nhanes = curB$rr, B_lo = curB$lo, B_hi = curB$hi,
  rr_C_nhanes_only = if (is.null(curC)) NA_real_ else curC$rr)
CMP[, `:=`(B_over_A = rr_B_plus_nhanes / rr_A_primary,
           C_over_A = rr_C_nhanes_only / rr_A_primary)]
fwrite(CMP, file.path(DIR_OUT, "Table7_bop_nhanes_pooled_curve.csv"))

# --- 自校验：A 档必须逐值复现 05a 的主产物（否则"对照基准"不成立）---
#     ⚠️ 该检查**以同引擎为前提**：A 档数据 = 05a 的 dt_main（一般人群），
#        同引擎 + 同 seed 才能逐值一致。若引擎被拆成两套（如 05a 贝叶斯、05c REML），
#        本检查必然失败——这正是 2026-10-16 把引擎抽到 lib/pa_bop_engine.R 的直接原因。
t5 <- fread(file.path(DIR_OUT, "Table5_bop_pooled_RR.csv"), encoding = "UTF-8")
t5d <- t5[curve_role == "device_pooled" & metric_definition == "total_PA"][order(offset_pts)]
if (!nrow(t5d)) stop("Table5_bop_pooled_RR.csv 中缺 device_pooled × total_PA")
REF_RR <- approx(t5d$offset_pts, t5d$rr, xout = gd, rule = 2)$y
A_MAXD <- max(abs(CMP$rr_A_primary - REF_RR))
pa_log(sprintf("A 档 vs 05a 主产物：device_pooled×total_PA 最大绝对偏差 %.3e → %s",
               A_MAXD, if (A_MAXD < 1e-6) "复现通过" else "⚠️ 未复现"))
pa_log(sprintf("  引擎：本脚本 A 档 = %s；05a 主产物 = %s",
               FIT$A_primary_only$fit_mode,
               { .q <- tryCatch(fread(file.path(DIR_OUT, "QC_bop_status.csv")),
                                error = function(e) NULL)
                 if (is.null(.q) || !"拟合" %in% .q$item) "未记录"
                 else sub("（.*$", "", .q$detail[.q$item == "拟合"][1]) }))

# ---------------------------------------------------------------------------
# 6. NHANES 在 B 档各设备组合中的权重占比（说明"拽平"的机制）
# ---------------------------------------------------------------------------
WSH <- rbindlist(lapply(setdiff(unique(as.character(FIT$B_primary_plus_nhanes$dat$arm)), "self"),
  function(a) {
    md <- "total_PA"; lv <- paste0(a, "|", md)
    if (!(lv %in% FIT$B_primary_plus_nhanes$combos)) return(NULL)
    d <- FIT$B_primary_plus_nhanes$dat[mm == lv]
    d[, wfix := 1 / vi]
    data.table(arm = a, metric_definition = md, n_rows = nrow(d),
               n_rows_nhanes = d[grepl("^NHANES_own", study), .N],
               wfix_total = sum(d$wfix),
               wfix_nhanes_share = d[grepl("^NHANES_own", study), sum(wfix)] / sum(d$wfix),
               slope_B = FIT$B_primary_plus_nhanes$b[[coef_of(FIT$B_primary_plus_nhanes, lv)]])
  }), use.names = TRUE, fill = TRUE)
fwrite(WSH, file.path(DIR_OUT, "Table7_bop_nhanes_weight_share.csv"))

# ---------------------------------------------------------------------------
# 7. B 档曲线集 → 供 Module 3 做"影响力"敏感性（不覆盖主产物）
#    曲线池来源与 05a 第 4 节**同规则**：贝叶斯路径直接取后验抽样（确定性），
#    metafor 路径退回 mvrnorm 参数自助。
# ---------------------------------------------------------------------------
fpB <- FIT$B_primary_plus_nhanes
if (!is.null(fpB$post)) {
  P <- fpB$post
  idx <- if (nrow(P) >= N_DRAW) round(seq(1, nrow(P), length.out = N_DRAW))
         else sample.int(nrow(P), N_DRAW, replace = TRUE)
  drB <- P[idx, , drop = FALSE]
  rownames(drB) <- NULL
  stopifnot(identical(colnames(drB), names(fpB$b)))
} else {
  VsB <- (fpB$V + t(fpB$V)) / 2
  set.seed(PA_SEED)   # 与 05a 同种子 → A/B 差异只来自数据，不来自随机流
  drB <- MASS::mvrnorm(N_DRAW, mu = fpB$b, Sigma = VsB)
}

metaB <- rbindlist(lapply(fpB$combos, function(lv) {
  data.table(curve_role = "arm_specific", mm = lv, arm = sub("\\|.*$", "", lv),
             metric = sub("^.*\\|", "", lv), offset_pts = gd)
}), use.names = TRUE, fill = TRUE)
metaB[, method := ifelse(grepl("^device", arm), "device", "self")]
metaB[, wear_site := unname(c(self="NA", device_hip="hip", device_mixed="mixed",
                              device_wrist="wrist")[arm])]
metaB[, exposure_pct := offset_pts + REF_CANON]

dpB <- rbindlist(lapply(sort(unique(as.character(fpB$dat$metric_definition))), function(md) {
  W <- pooled_w(fpB, md); if (is.null(W)) return(NULL)
  data.table(curve_role = "device_pooled", mm = "device_pooled", arm = "device_pooled",
             metric = md, offset_pts = gd, method = "device", wear_site = "pooled",
             exposure_pct = gd + REF_CANON)
}), use.names = TRUE, fill = TRUE)
metaB <- rbind(metaB, dpB, use.names = TRUE, fill = TRUE)

Xall <- rbind(
  do.call(rbind, lapply(fpB$combos, function(lv) {
    X <- matrix(0, nrow = length(gd), ncol = length(fpB$b), dimnames = list(NULL, names(fpB$b)))
    X[, coef_of(fpB, lv)] <- gd
    X
  })),
  do.call(rbind, lapply(sort(unique(as.character(fpB$dat$metric_definition))), function(md) {
    W <- pooled_w(fpB, md); if (is.null(W)) return(NULL)
    nms <- names(W); w <- unlist(W)
    X <- matrix(0, nrow = length(gd), ncol = length(fpB$b), dimnames = list(NULL, names(fpB$b)))
    for (i in seq_along(nms)) X[, nms[i]] <- w[i] * gd
    X
  })))
stopifnot(nrow(Xall) == nrow(metaB))
RRS <- exp(drB %*% t(Xall))

saveRDS(list(offset_grid = as.numeric(metaB$offset_pts),
             pct_grid = as.numeric(metaB$exposure_pct),
             ref_canon = REF_CANON,
             arm = as.character(metaB$arm), method = as.character(metaB$method),
             wear_site = as.character(metaB$wear_site),
             curve_role = as.character(metaB$curve_role),
             metric = as.character(metaB$metric), mm = as.character(metaB$mm),
             draws = RRS, seed = PA_SEED, n_draw = N_DRAW,
             fit_mode = fpB$fit_mode,
             note = paste0("【敏感性专用，非主产物】池 = 22 行外部文献 + 16 行本项目自算 NHANES",
                           "（2003-2006 髋式 / 2011-2014 腕式，metric=total_PA）。",
                           "结构、轴与 bop_rr_draws.rds 完全一致，可直接喂给 95_module3_paf.R",
                           "（PA_RR_DRAWS=...）做影响力分析。⚠️ 并入了设计不可比的来源",
                           "（随访 13-16 年 vs 池内 5-8 年）→ 仅用于稳健性，不作主结果。")),
        file.path(DIR_OUT, "bop_rr_draws_withNHANES.rds"))

# ---------------------------------------------------------------------------
# 8. 留痕：extraction_log.csv 追加（append 保留原文件 BOM 与字节）
# ---------------------------------------------------------------------------
LOG_NEW <- NHN[, .(date_utc = format(Sys.time(), "%Y-%m-%d", tz = "UTC"),
                   row_id, source,
                   paper_table = "本项目 04b 产出（Table6_nhanes_hip_wrist_RR.csv）",
                   model_adjustment = "age+female+race5+educ+pir+bmi+sbp+cur_smoke+drink_any+diabetes+cvd_hx",
                   ci_type = "95CI（svycoxph 设计校正）",
                   referent_group = "各自人群加权 12.5 百分位",
                   converted = "no", extracted_by = "本项目自算（04b）",
                   verified_by = "待人工复核；数值与输出逐值一致（05c 硬校验）",
                   pct_derivation = "人群加权分位（自实现 wq）",
                   note = notes)]
# 与既有列对齐
LOG_OLD <- fread(LOG_CSV, encoding = "UTF-8", fill = TRUE, sep = ",")   # sep 必须显式给，见 06_manifest.R 的说明
for (cc in setdiff(names(LOG_OLD), names(LOG_NEW))) LOG_NEW[, (cc) := NA]
setcolorder(LOG_NEW, names(LOG_OLD))
# ⚠️ 幂等：本脚本会被 00_run_all.R 反复调用，若每次都 append，extraction_log.csv
#    会不断变长 → manifest 指纹每次漂移 → 98 的 E 层报假 WARN。故先查重再写。
have <- LOG_NEW$row_id %in% LOG_OLD$row_id
if (all(have)) {
  pa_log("extraction_log.csv 已含全部 ", nrow(LOG_NEW), " 条 NHANES 留痕 → 跳过（幂等）")
} else if (any(have)) {
  stop("extraction_log.csv 部分已含 NHANES 留痕（", sum(have), "/", nrow(LOG_NEW),
       "）→ 状态不一致，请人工核对，勿自动追加")
} else {
  # ⚠️ 不能写 `..names(LOG_OLD)`：`..` 前缀只对**裸符号**生效，套函数即报
  #    "could not find function '..names'"。用 with = FALSE 显式选列。
  fwrite(LOG_NEW[, names(LOG_OLD), with = FALSE], LOG_CSV, append = TRUE, col.names = FALSE)
  pa_log("extraction_log.csv 追加 ", nrow(LOG_NEW), " 条 NHANES 留痕")
}

# ---------------------------------------------------------------------------
# 9. 状态与报告
# ---------------------------------------------------------------------------
SITE_MAIN <- SITE[offset_pts == OFF_EFF]
st <- rbindlist(list(
  data.table(item = "主池是否被修改", status = "OK",
             detail = sprintf("%s 未被本脚本写入；主分析 Table5_* 与 bop_rr_draws.rds 保持冻结", basename(RR_CSV))),
  data.table(item = "敏感性池规模", status = "OK",
             detail = sprintf("A=%d 行/%d 研究；B=%d 行/%d 研究；C=%d 行/%d 研究",
                              FIT$A_primary_only$n_rows, FIT$A_primary_only$n_study,
                              FIT$B_primary_plus_nhanes$n_rows, FIT$B_primary_plus_nhanes$n_study,
                              FIT$C_nhanes_only$n_rows, FIT$C_nhanes_only$n_study)),
  data.table(item = "A 档复现 05a（对照基准）",
             status = if (A_MAXD < 1e-6) "PASS" else "FAIL",
             detail = sprintf(paste0("A 档 device_pooled×total_PA @off80 RR=%.6f vs 05a 主产物 %.6f；",
                                     "最大绝对偏差 %.3e；引擎 A=%s（同引擎是逐值复现的前提）"),
                              CMP[offset_pts == 80, rr_A_primary], REF_RR[gd == 80], A_MAXD,
                              FIT$A_primary_only$fit_mode)),
  data.table(item = "total_PA 部位效应（B 档首次可估）",
             status = "OK",
             detail = sprintf("RR_hip/RR_wrist @off%d = %.3f [%.3f, %.3f], p=%.4f",
                              OFF_EFF,
                              SITE_MAIN[spec == "B_primary_plus_nhanes" & metric_definition == "total_PA", rr_ratio_hip_over_wrist],
                              SITE_MAIN[spec == "B_primary_plus_nhanes" & metric_definition == "total_PA", rr_ratio_lo],
                              SITE_MAIN[spec == "B_primary_plus_nhanes" & metric_definition == "total_PA", rr_ratio_hi],
                              SITE_MAIN[spec == "B_primary_plus_nhanes" & metric_definition == "total_PA", p_diff])),
  data.table(item = "LPA 部位效应（A 档=文献侧基准）", status = "OK",
             detail = sprintf("RR_hip/RR_wrist @off%d = %.3f [%.3f, %.3f], p=%.4f",
                              OFF_EFF,
                              SITE_MAIN[spec == "A_primary_only" & metric_definition == "LPA", rr_ratio_hip_over_wrist],
                              SITE_MAIN[spec == "A_primary_only" & metric_definition == "LPA", rr_ratio_lo],
                              SITE_MAIN[spec == "A_primary_only" & metric_definition == "LPA", rr_ratio_hi],
                              SITE_MAIN[spec == "A_primary_only" & metric_definition == "LPA", p_diff])),
  data.table(item = "并入 NHANES 对池化曲线的影响", status = "OK",
             detail = sprintf("@off80 RR: A=%.4f → B=%.4f（比值 %.3f）；@off60 A=%.4f → B=%.4f（比值 %.3f）",
                              CMP[offset_pts == 80, rr_A_primary], CMP[offset_pts == 80, rr_B_plus_nhanes],
                              CMP[offset_pts == 80, B_over_A],
                              CMP[offset_pts == 60, rr_A_primary], CMP[offset_pts == 60, rr_B_plus_nhanes],
                              CMP[offset_pts == 60, B_over_A])),
  data.table(item = "NHANES 在 B 档设备臂的固定效应权重占比", status = "OK",
             detail = paste(sprintf("%s=%.0f%%", WSH$arm, 100 * WSH$wfix_nhanes_share), collapse = "; ")),
  data.table(item = "用途声明", status = "WARN",
             detail = paste0("NHANES 两臂**不得**并入主分析池：① 破坏 Module 2 的「外部文献」定位；",
                             "② 随访 13-16 年 vs 池内 5-8 年，设计不可通约（衰减更强）；",
                             "③ 权重约 4 倍 → 曲线被设计差异而非信息量拽平。仅作敏感性。"))))
fwrite(st, file.path(DIR_OUT, "QC_bop_nhanes_sensitivity.csv"))

cat("\n===== A 档 vs B 档：device_pooled × total_PA（Module 3 的实际输入）=====\n")
print(CMP[offset_pts %in% c(0, 10, 20, 30, 40, 50, 60, 70, 80),
          .(offset_pts, rr_A = round(rr_A_primary, 4), rr_B = round(rr_B_plus_nhanes, 4),
            B_over_A = round(B_over_A, 3), rr_C_nhanes = round(rr_C_nhanes_only, 4))])
cat("\n===== 部位效应（髋 ÷ 腕，@offset 60）=====\n")
print(SITE_MAIN[, .(spec, metric_definition, n_rows_hip, n_rows_wrist,
                    ratio = round(rr_ratio_hip_over_wrist, 3),
                    lo = round(rr_ratio_lo, 3), hi = round(rr_ratio_hi, 3),
                    p = signif(p_diff, 3))])
cat("\n===== NHANES 权重占比（B 档设备臂）=====\n"); print(WSH)
cat("\n===== 状态 =====\n"); print(st)
pa_log("05c 完成 -> Table7_bop_nhanes_{site_sensitivity,pooled_curve,weight_share}.csv + bop_rr_draws_withNHANES.rds")
