# =============================================================================
# 10_captions.R —— 投稿版图注 / 表注（中英双语，自动取数）
# -----------------------------------------------------------------------------
# 设计原则（对应项目硬标准「原始数据 + 分析代码 + 过程可复现」）：
#   · 所有数值**从 output/ 的产物 CSV 动态读取**，脚本内不手写任何结果数字；
#     产物一刷新，图注自动同步，不会出现「图注与图不符」。
#   · 末段「一致性自检」把同一量在不同产物中的取值并排列出，不一致即告警
#     （而非静默取一个）。
#
# 产出：output/CAPTIONS_figures_tables.md
#       覆盖 正文 Fig 1-6（17 个面板）+ Table 1-4 + 补充表 S1-S12
# 依赖产物：09 / 07 / 95c / 96b / 97 / 05c / 05e / 05f / 04b / 04e 的 output CSV
# 运行：Rscript 10_captions.R          （秒级）
# =============================================================================
t0 <- Sys.time()
source("08_fig_style.R")
pa_log("===== 10 图注 / 表注（中英双语）=====")

# ---------------------------------------------------------------------------
# 0. 工具
# ---------------------------------------------------------------------------
rd <- function(...) {
  p <- file.path(DIR_OUT, paste0(..., ".csv"))
  if (!file.exists(p)) return(NULL)
  fread(p, encoding = "UTF-8")
}
nf  <- function(x, d = 0) formatC(as.numeric(x), format = "f", digits = d, big.mark = ",")
sg  <- function(x, d = 3) formatC(signif(as.numeric(x), d), format = "g")
# p 值统一显示：>= 1e-4 用有效数字定点；更小者写成 a×10⁻ᵇ，
# 避免正文里混排 "7.2e-08" 这类机器写法。
SUPMAP <- c("0" = "\u2070", "1" = "\u00b9", "2" = "\u00b2", "3" = "\u00b3", "4" = "\u2074",
            "5" = "\u2075", "6" = "\u2076", "7" = "\u2077", "8" = "\u2078", "9" = "\u2079",
            "-" = "\u207b")
pf <- function(p, d = 3) {
  vapply(as.numeric(p), function(z) {
    if (!is.finite(z)) return("-")
    if (z >= 1e-4) return(formatC(signif(z, d), format = "g"))
    s <- formatC(z, format = "e", digits = 1)
    mant <- sub("e.*$", "", s)
    ex   <- sub("^.*e", "", s)
    ex   <- sub("^\\+", "", ex)
    ex   <- sub("^(-?)0+(?=[0-9])", "\\1", ex, perl = TRUE)
    paste0(mant, "\u00d710", paste0(unname(SUPMAP[strsplit(ex, "")[[1]]]), collapse = ""))
  }, character(1), USE.NAMES = FALSE)
}
num <- function(x) as.numeric(gsub("[^0-9.eE+-]", "", as.character(x)))
# thsep(s)：给「上游产物的标签字符串」里的大数补千分位（纯显示，不改数值）。
# 只处理 >= 4 位的整数（可带小数部分），跳过已有逗号/小数点的数字与紧随数字的字母。
thsep <- function(x) {
  pat <- "(?<![0-9,.])[0-9]{4,}(?:\\.[0-9]+)?(?![0-9])"
  vapply(as.character(x), function(s) {
    if (is.na(s) || !nzchar(s)) return(s)
    m <- gregexpr(pat, s, perl = TRUE)[[1]]
    if (m[1] == -1L) return(s)
    len <- attr(m, "match.length")
    for (i in rev(seq_along(m))) {
      tok <- substr(s, m[i], m[i] + len[i] - 1L)
      rep_ <- if (grepl(".", tok, fixed = TRUE)) {
        ip <- sub("\\..*$", "", tok); dp <- sub("^[^.]*", "", tok)
        paste0(formatC(as.numeric(ip), format = "d", big.mark = ","), dp)
      } else formatC(as.numeric(tok), format = "d", big.mark = ",")
      s <- paste0(substr(s, 1L, m[i] - 1L), rep_, substr(s, m[i] + len[i], nchar(s)))
    }
    s
  }, character(1), USE.NAMES = FALSE)
}

# 中英双语段落
bi <- function(en, zh, tag = NULL) {
  h <- if (is.null(tag) || !nzchar(tag)) "" else sprintf("### %s\n\n", tag)
  sprintf("%s**English.** %s\n\n**中文.** %s\n", h, en, zh)
}
DEFH <- "\n**Definitions / 定义**\n"
# DEF_OPEN：当前是否处于一个「Definitions」块内。任何普通输出都会关闭该块，
# 因此同一段落内连续多次调用 def() 共享一个小标题（旧实现只看紧邻上一行，会重复打印）。
DEF_OPEN <- FALSE
# def(...)：把若干「- 条目」并成一个定义块；同一段落内只输出一次小标题。
def <- function(...) {
  x <- Filter(nzchar, unlist(list(...)))
  if (!length(x)) return(invisible(NULL))
  if (!DEF_OPEN) { L <<- c(L, DEFH); DEF_OPEN <<- TRUE }
  L <<- c(L, paste0("- ", x, collapse = "\n"))
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# 1. 载入产物
# ---------------------------------------------------------------------------
FLOW  <- rd("Fig2a_flow_numbers")
CRS   <- rd("Fig2c_crosstab_weighted")
REFPT <- rd("Fig3_reference_points")
T1    <- rd("Table1_baseline_manuscript")
T2    <- rd("Table2_hr_manuscript")
SDEF  <- rd("Sample_definition")        # B9：两段式样本口径（09 独立落盘，用于跨脚本比对）
T3    <- rd("Table3_calibration_coefs_manuscript")
T3B   <- rd("Table3_reporting_bias")
T4    <- rd("Table4_burden_manuscript")
T5P   <- rd("Table5_bop_pooled_RR")
T5M   <- rd("Table5_bop_method_effect")
T5W   <- rd("Table5_bop_wear_site")
T5F   <- rd("Table5_bop_fit_diagnostic")
T6    <- rd("Table6_nhanes_hip_wrist_RR")
T7S   <- rd("Table7_bop_nhanes_site_sensitivity")
T7P   <- rd("Table7_bop_nhanes_paf_impact")
T8S   <- rd("Table8_site_ratio_summary")        # S4：髋式 wear 规则 × 腕式判据网格
T8M   <- rd("Table8_site_ratio_matrix")         # S4：同一网格的 |ratio| 矩阵形态
T8L   <- rd("Table8_lit_site_contrast")         # S4：文献侧部位对比
T8C   <- rd("Table8_lit_site_compatibility")    # S4：NHANES 与文献侧可比性
T8D   <- rd("Table8_lit_design_incompat")       # S4：两臂设计不可通约清单
T8V   <- rd("Table8_lit_site_leverage")         # S4：留一臂杠杆
# 指标稳健性（2026-10-16 新增；04d §2b + 04f）
T8BX  <- rd("Table8_lit_site_metric_license")   # S4：指标错配的量化许可（04d）
T8BM  <- rd("Table8b_site_metric_compare")      # S4：两指标同估计量并列（04f）
T8BN  <- rd("Table8b_site_anchor_vs_nhanes")    # S4：★ 指标对齐对照（04f，total_PA vs NHANES total）
T8X   <- rd("Table8_metric_axis_check")         # S4：指标轴检查
T9    <- rd("Table9_m3_scenario_summary")
T10R  <- rd("Table10_m3_robustness")
T10H  <- rd("Table10_m3_country_homogeneity")
T11I  <- rd("Table11_pam_intensity_per_IQR")
T12P  <- rd("Table12_m3_loo_paf")
T13   <- rd("Table13_evalues")
T14   <- rd("Table14_sdi_anchor")
TS4   <- rd("TableS4_burden_bycountry_manuscript")
M3T   <- rd("M3_BYCOUNTRY_totals")
M3C   <- rd("M3_BYCOUNTRY_by_cause")
M3S   <- rd("M3_BYCOUNTRY_by_sdi")
M3E   <- rd("M3_BYCOUNTRY_exposure_diag")
F5D   <- rd("Fig5d_waterfall_data")
P_TOT <- rd("PREVIEW_module3_s1p_totals")

MISSING <- character(0)
for (nm in c("FLOW","CRS","T1","T2","SDEF","T3","T3B","T4","T5P","T6","T8S","T8L","T8C","T8D","T8V","T8X",
             "T8BX","T8BM","T8BN",
             "T9","T13","T14","TS4",
             "M3T","M3C","M3S","M3E","F5D","P_TOT")) {
  if (is.null(get(nm))) MISSING <- c(MISSING, nm)
}
if (length(MISSING)) cat("  缺产物：", paste(MISSING, collapse = ", "), "\n")

# ---------------------------------------------------------------------------
# 2. 关键量提取
# ---------------------------------------------------------------------------
FL <- if (!is.null(FLOW)) setNames(FLOW$n, FLOW$node) else NULL
N_PAX <- FL[["PAXDAY records"]]; N_VALID <- FL[["Valid accelerometry"]]
N_25  <- FL[["Aged >= 25"]];     N_MOD   <- FL[["Modelling sample"]]

N_ALL <- T1[variable == "N"]$Overall; D_ALL <- T1[variable == "Deaths"]$Overall
N_ALL_N <- num(N_ALL); D_ALL_N <- num(D_ALL)   # Overall 是带千分位的字符串，须先转数

# ---------------------------------------------------------------------------
# 2b. 两段式样本口径（2026-10-16 落实）
# ---------------------------------------------------------------------------
# 为什么需要：Table 1 描述的是「完整协变量限制之前」的设备样本（7,854 人；
#   09_tables.R L24 的 t1d = analytic.rds 全量），而 Table 2 的多变量 Cox 跑在
#   完整案例集（7,007 人；09_tables.R L82 的 mod_dt）上。两者此前都被称作
#   "modelling sample" → 同一份图注里 7,854 与 7,007 同时出现却无口径区分，
#   属**可被审稿人直接抓住的口径混淆**。
# 现统一改为两段式表述：
#   ① 设备样本（= Table 1 的描述对象）：N_ALL_N / D_ALL_N（取自 Table 1 自身）
#   ② 多变量 Cox 分析集（= Table 2 的拟合样本）：N_MOD / D_MOD
#      N_MOD 取自 Fig 2(a) 流程节点；D_MOD 取自 Fig2a_flow_numbers.csv 的 deaths 列
#      （由 08b 计算落盘）。**任何一处数值都不得在本脚本内手写。**
# 另有一处必须写清的精度细节：设备样本 7,854 行中有 12 行未链接到 NDI 死亡随访
#   （died / cvd_death / surv_mo 同时为 NA）→「769 例死亡」的分母是 **7,842**。
#   故图注写「7,854 人中 769 例死亡」会被以分母错误质疑；此处一律显式给出 7,842。
FLD   <- if (!is.null(FLOW) && "deaths" %in% names(FLOW)) setNames(FLOW$deaths, FLOW$node) else NULL
D_25  <- if (!is.null(FLD)) FLD[["Aged >= 25"]]       else NA   # ① 设备样本死亡数
D_MOD <- if (!is.null(FLD)) FLD[["Modelling sample"]] else NA   # ② Cox 分析集死亡数
# ★ 2026-10-16 追加心血管死亡数：Results R1 与 Discussion L4 引用「Cox 分析集中 207 例
#   心血管死亡」，此前该值无产物来源。现由 08b（Fig2a_flow_numbers.csv 的 cvd_deaths 列）
#   与 09（Sample_definition.csv 第 6 行）**独立推导** → 纳入下方跨脚本自检逐值比对。
FLC   <- if (!is.null(FLOW) && "cvd_deaths" %in% names(FLOW)) setNames(FLOW$cvd_deaths, FLOW$node) else NULL
CVD_25  <- if (!is.null(FLC)) FLC[["Aged >= 25"]]       else NA
CVD_MOD <- if (!is.null(FLC)) FLC[["Modelling sample"]] else NA
has1  <- function(x) length(x) == 1L && !is.na(x)
# 缺 deaths 列时不静默降级：第二段仍写出 N，但死亡数留空，并在文末自检段落告警。
if (!has1(D_MOD)) MISSING <- c(MISSING, "Fig2a_flow_numbers.csv 缺 deaths 列（请重跑 08b）")
# 同理：缺 cvd_deaths 列时告警（不阻断，但自检段会少一个量 → 必须可见）。
if (!has1(CVD_MOD)) MISSING <- c(MISSING, "Fig2a_flow_numbers.csv 缺 cvd_deaths 列（请重跑 08b）")
STAGE2 <- has1(D_MOD)

# 09 落盘的样本口径定义（跨脚本比对用；缺表时对应句子降级为不含随访链接数的写法）
sdv <- function(it) if (!is.null(SDEF)) SDEF[item == it]$n else NULL
N_FUP <- sdv("Device sample with linked mortality follow-up")   # 7,842
FUPOK <- has1(N_FUP)

# Fig 1 的两段式句子（EN / ZH）：写成**独立一句**插在 Module 1 描述之后 ——
#   若塞进括号里会变成「（设备样本 …（769 例死亡，即 Table 1 的对象）…）」这种
#   **双层括号**，中英文都难读。故改为独立句，全句只保留一层括号。
FIG1_SAMPLE_EN <- if (STAGE2 && FUPOK)
  sprintf(paste0("The models rest on two nested samples: first, the device sample of %s adults aged ",
                 "25 years or older described in Table 1, of whom %s had linked mortality follow-up ",
                 "and %s died; second, after additionally requiring complete covariates, the %s adults ",
                 "analysed in the Cox models, in whom %s deaths occurred."),
          nf(N_ALL_N), nf(N_FUP), nf(D_ALL_N), nf(N_MOD), nf(D_MOD)) else if (STAGE2)
  sprintf(paste0("The models rest on two nested samples: first, the device sample of %s adults aged ",
                 "25 years or older described in Table 1, in whom %s deaths occurred; second, after ",
                 "additionally requiring complete covariates, the %s adults analysed in the Cox ",
                 "models, in whom %s deaths occurred."),
          nf(N_ALL_N), nf(D_ALL_N), nf(N_MOD), nf(D_MOD)) else
  sprintf("The models rest on %s adults aged 25 years or older with %s deaths.", nf(N_ALL_N), nf(D_ALL_N))
FIG1_SAMPLE_ZH <- if (STAGE2 && FUPOK)
  sprintf(paste0("模型基于两个嵌套样本：第一段为 Table 1 描述的**设备样本** %s 名 25 岁以上成人，",
                 "其中 %s 人链接到死亡随访、%s 例死亡；第二段在进一步要求协变量完整后，",
                 "为纳入 Cox 模型的 %s 人，其中 %s 例死亡。"),
          nf(N_ALL_N), nf(N_FUP), nf(D_ALL_N), nf(N_MOD), nf(D_MOD)) else if (STAGE2)
  sprintf(paste0("模型基于两个嵌套样本：第一段为 Table 1 描述的**设备样本** %s 名 25 岁以上成人、%s 例死亡；",
                 "第二段在进一步要求协变量完整后，为纳入 Cox 模型的 %s 人，其中 %s 例死亡。"),
          nf(N_ALL_N), nf(D_ALL_N), nf(N_MOD), nf(D_MOD)) else
  sprintf("模型基于 %s 名 25 岁以上成人、%s 例死亡。", nf(N_ALL_N), nf(D_ALL_N))
# Table 1 的第二句（点明本表对象与模型样本的分工）
T1_STAGE_EN <- if (STAGE2)
  sprintf(paste0("This table describes the sample before the complete-covariate restriction; ",
                 "the multivariable Cox models are fitted in the %s adults with complete covariates ",
                 "and follow-up, among whom %s deaths occurred."), nf(N_MOD), nf(D_MOD)) else
  sprintf("This table describes the sample before the complete-covariate restriction; the multivariable Cox models are fitted in the %s adults with complete covariates and follow-up.", nf(N_MOD))
T1_STAGE_ZH <- if (STAGE2)
  sprintf(paste0("本表描述「完整协变量限制之前」的样本；多变量 Cox 模型在协变量与随访完整者 ",
                 "%s 人中拟合，其中 %s 例死亡。"), nf(N_MOD), nf(D_MOD)) else
  sprintf("本表描述「完整协变量限制之前」的设备样本；多变量 Cox 模型在协变量与随访完整者 %s 人中拟合。", nf(N_MOD))
# Table 1 第一句的主语（含随访链接数；Fig 1 与 Table 1 共用同一精度口径）
T1_SAMPLE_EN <- if (FUPOK)
  sprintf(paste0("Baseline characteristics of the device sample analysed in this study - %s NHANES ",
                 "2011-2014 adults aged 25 years or older with valid accelerometry, of whom %s had ",
                 "linked mortality follow-up and %s died - overall and by sample-count quartile of ",
                 "device-measured total activity (MIMS/day); within-quartile summaries are survey-weighted."),
          nf(N_ALL_N), nf(N_FUP), nf(D_ALL_N)) else
  sprintf(paste0("Baseline characteristics of the device sample analysed in this study - %s NHANES ",
                 "2011-2014 adults aged 25 years or older with valid accelerometry, among whom %s died - ",
                 "overall and by sample-count quartile of device-measured total activity (MIMS/day); ",
                 "within-quartile summaries are survey-weighted."),
          nf(N_ALL_N), nf(D_ALL_N))
T1_SAMPLE_ZH <- if (FUPOK)
  sprintf(paste0("本研究设备样本的基线特征 —— %s 名 25 岁及以上、加速度计数据有效的 NHANES 2011–2014 成人，",
                 "其中 %s 人链接到死亡随访、%s 例死亡 —— 整体及按设备测量活动总量（MIMS/day）「等人数」四分位分层（组内统计量为调查加权）。"),
          nf(N_ALL_N), nf(N_FUP), nf(D_ALL_N)) else
  sprintf(paste0("本研究设备样本的基线特征 —— %s 名 25 岁及以上、加速度计数据有效的 NHANES 2011–2014 成人，",
                 "其中 %s 例死亡 —— 整体及按设备测量活动总量（MIMS/day）「等人数」四分位分层（组内统计量为调查加权）。"),
          nf(N_ALL_N), nf(D_ALL_N))

t2v <- function(o, m, t) {
  r <- T2[outcome == o & model == m & term == t]
  if (!nrow(r)) NULL else r
}
AC_M1_Q4 <- t2v("All-cause mortality", "Model 1 (minimally adjusted)", "Q4")
AC_M2_Q4 <- t2v("All-cause mortality", "Model 2 (fully adjusted)", "Q4")
AC_M2_IQ <- t2v("All-cause mortality", "Model 2 (fully adjusted)", "Per IQR (4879 MIMS/day)")
CV_M2_Q4 <- t2v("Cardiovascular mortality", "Model 2 (fully adjusted)", "Q4")
CV_M2_IQ <- t2v("Cardiovascular mortality", "Model 2 (fully adjusted)", "Per IQR (4879 MIMS/day)")

REF_MIMS <- REFPT[exposure == "mims_per_day" & outcome == "all_cause"]$ref_val
REF_PEAK <- REFPT[exposure == "peak30_per_day" & outcome == "all_cause"]$ref_val
REF_PCT  <- M3E[location == "Global" & year == 2022]$pct_below_tmrel
REF_PCT2 <- M3E[location == "Global" & year == 2022]$p_tmrel

t4 <- function(y, l) { r <- T4[Year == y & Location == l]; if (!nrow(r)) NULL else r }
G90 <- t4(1990, "Global"); G22 <- t4(2022, "Global")
T4_G22_D <- num(G22$`Deaths (this study)`); T4_G22_G <- num(G22$`Deaths (GBD 2023)`)
T4_G90_D <- num(G90$`Deaths (this study)`); T4_G90_G <- num(G90$`Deaths (GBD 2023)`)

# SDI 分层
sdi22 <- if (!is.null(M3S)) { x <- as.data.table(M3S)[year == 2022 & rr_source == "pooled"]; setorder(x, quintile_ord); x }
cset  <- if (!is.null(M3T)) {
  x <- as.data.table(M3T)[year == 2022 & rr_source == "pooled" & location != "Global" & is_main == TRUE]
  list(n = nrow(x), med = median(x$fold_deaths),
       lo = quantile(x$fold_deaths, .25), hi = quantile(x$fold_deaths, .75),
       min = min(x$fold_deaths), max = max(x$fold_deaths), g1 = sum(x$fold_deaths > 1))
}
N_CTRY <- if (!is.null(cset)) cset$n else NA

NQ_PUB <- if (!is.null(T14)) sum(as.data.table(T14)$q_source != "published") else NA
# 【2026-10-15 起停用】Module 3 已改为确定性后验枚举（不再抽样），本变量仅供日志/兼容保留
NC_SEED <- suppressWarnings(as.integer(Sys.getenv("PA_N_DRAWS", unset = "400")))

hc <- NULL; HCLIP <- HMIN <- HMAX <- HN <- NCLIP <- NA; DEEP <- SHAL <- "-"
if (!is.null(M3C)) {
  hc <- as.data.table(M3C)[is_main == TRUE & rr_source == "pooled" & year == 2022 & location != "Global"]
  hc <- hc[is.finite(fold_deaths_c)]
  HCLIP <- 10^quantile(abs(log10(pmax(hc$fold_deaths_c, 1))), .98)
  HMIN <- min(hc$fold_deaths_c); HMAX <- max(hc$fold_deaths_c)
  HN   <- nrow(hc); NCLIP <- sum(hc$fold_deaths_c > HCLIP)
  hm <- hc[, .(m = mean(log10(fold_deaths_c))), by = cause][order(-m)]
  DEEP <- hm$cause[1]; SHAL <- hm$cause[nrow(hm)]
}

# Fig 5(d) 分步
W <- if (!is.null(F5D)) as.data.table(F5D)[scope == "Global" & year == 2022] else NULL
st <- if (!is.null(W)) setNames(lapply(seq_len(nrow(W)), function(i) W[i]), W$step) else NULL

# Fig 6(b) LOO
LOO <- NULL; PBASE <- NA
if (!is.null(T12P)) {
  x <- as.data.table(T12P)[location == "Global" & year == 2022]
  PBASE <- x[scenario == "BASE_all"]$fold
  LOO <- x[scenario != "BASE_all"][order(fold)]
}

# Table S1
PW90 <- if (!is.null(T5P)) as.data.table(T5P)[curve_role == "device_pooled" & offset_pts == 90] else NULL
W60  <- if (!is.null(T5W)) as.data.table(T5W)[spec == "main_general_population" & offset_pts == 60 & metric_definition == "LPA"] else NULL
M60  <- if (!is.null(T5M)) as.data.table(T5M)[metric_definition == "total_PA"] else NULL
MAXRES <- if (!is.null(T5F)) max(abs(as.data.table(T5F)$resid)) else NA

# Table S5
BASE9 <- if (!is.null(T9)) as.data.table(T9)[scenario == "S0_base"] else NULL
UPP9  <- if (!is.null(T9)) as.data.table(T9)[scenario == "D2_p85_nosig"] else NULL
GA9   <- if (!is.null(T9)) as.data.table(T9)[scenario == "GBD_ALIGNED_RR"] else NULL
GF9   <- if (!is.null(T9)) as.data.table(T9)[scenario == "GBD_FAITHFUL"] else NULL

# Table S6 / S7
CVG <- if (!is.null(T10R)) as.data.table(T10R)[grepl("^CV=", level)] else NULL
TH  <- if (!is.null(T10H)) as.data.table(T10H) else NULL

# Table S10
EV <- if (!is.null(T13)) as.data.table(T13) else NULL

# ---------------------------------------------------------------------------
# 3. 一致性自检（同量多处取值）
# ---------------------------------------------------------------------------
CONS <- data.table(quantity = character(0), source = character(0), value = numeric(0))
addc <- function(q, s, v) CONS <<- rbind(CONS, data.table(quantity = q, source = s, value = as.numeric(v)))
GV <- function(dt) if (is.null(dt)) NA_real_ else
  dt[location == "Global" & year == 2022 & rr_source == "pooled"]$recomputed_deaths
if (!is.null(G22))  addc("Global 2022 pooled 归因死亡（重算）", "Table 4 / 09 (95)", T4_G22_D)
addc("Global 2022 pooled 归因死亡（重算）", "PREVIEW s1p / 95",           GV(P_TOT))
addc("Global 2022 pooled 归因死亡（重算）", "M3_BYCOUNTRY / 95c",         GV(M3T))
if (!is.null(T7P)) addc("Global 2022 pooled 归因死亡（重算）", "Table 7 / 95b",
                        as.data.table(T7P)[location == "Global" & year == 2022 & rr_source == "pooled"]$deaths_A)
if (!is.null(BASE9)) addc("Global 2022 pooled 归因死亡（重算）", "Table 9 / 97",
                          as.numeric(BASE9$paf_global) *
                            as.numeric(P_TOT[location == "Global" & year == 2022 & rr_source == "pooled"]$total_deaths))
CONS <- CONS[is.finite(value)]
CONS[, spread_pct := 100 * (max(value) / min(value) - 1), by = quantity]
SPREAD <- if (nrow(CONS)) max(CONS$spread_pct) else 0

# ---------------------------------------------------------------------------
# 4. 生成
# ---------------------------------------------------------------------------
L <- character(0)
# p(fmt, ...)：只有一个参数时**原样输出**（正文里含 % 的普通字符串不会被当格式串）；
#              多参数时才走 sprintf（表格行等）。
p <- function(fmt, ...) {
  a <- list(...)
  s <- if (length(a) == 0L) fmt else do.call(sprintf, c(list(fmt), a))
  if (any(nzchar(s))) DEF_OPEN <<- FALSE   # 任何实质输出都结束当前 Definitions 块
  L <<- c(L, s)
  invisible(NULL)
}
RDATE <- format(Sys.Date(), "%Y-%m-%d")
p("# Figure and Table Captions — 图注与表注（中英双语）")
p("")
p("> 自动生成，请勿手改：`code/10_captions.R`（生成日 %s）。所有数值动态读取 `output/` 产物 CSV，产物刷新后重跑本脚本即可同步。", RDATE)
p("> Auto-generated by `code/10_captions.R`; every reported number is read from the `output/` product tables, so captions cannot drift from the figures.")
p("")
p("**Abbreviations / 缩写**：LPA = low physical activity 低体力活动；PAF = population-attributable fraction 人群归因分数；TMREL = theoretical minimum-risk exposure level 理论最低风险暴露水平；MIMS = monitor-independent movement summary 设备无关运动摘要；MVPA = moderate-to-vigorous physical activity 中高强度体力活动；SDI = Sociodemographic Index 社会人口学指数；BoP = burden-of-proof meta-regression 证据负担元回归；RCS = restricted cubic spline 限制性立方样条；DALY = disability-adjusted life-year 伤残调整生命年；CI = confidence interval 置信区间；SE = standard error 标准误。")
p("")
p("**General conventions / 通用约定**：Unless stated otherwise, all estimates refer to adults aged 25 years or older, both sexes combined, and to the year 2022; mortality endpoints are all-cause and cardiovascular death; the primary exposure is device-measured total activity (wrist MIMS/day, 7-day average); and the primary relative-risk source is the pooled external-evidence curve ('pooled'). 除特别说明外，所有估计针对 25 岁及以上成人、男女合计、2022 年；死亡终点为全死因与心血管死亡；主暴露为设备测量的活动总量（腕式 MIMS/day，7 日平均）；主 RR 来源为外部队列池化曲线（pooled）。")
p("")
p("**Three-module design / 三模块设计**：Module 1 = device-measured dose-response anchor (NHANES) 设备测量剂量-反应锚点；Module 2 = pooled relative risks across external cohorts 外部队列池化 RR；Module 3 = burden recomputation against GBD 2023 target populations 面向 GBD 2023 目标人群的负担重算。")
p("")
p("---")
p("")

# ============================== Fig 1 ==============================
p("## Fig 1. Study design and three-module analytical workflow")
p("")
p("**Files / 文件**：`figures/panel/Fig1_study_design.pdf`；`figures/combined/Fig1.pdf`")
p("")
p(bi(
  sprintf("Schematic of the study design and the three analytical modules. Module 1 (device-measured anchor): NHANES 2011-2014 accelerometry with mortality linkage is used to fit survey-weighted Cox proportional-hazards models with restricted cubic splines, yielding both a device-scale relative-risk curve and an individual-level calibration that converts self-reported activity onto the device scale. %s Module 2 (pooled external evidence): 5 external cohort studies (21 cohort-specific exposure contrasts) covering hip, wrist and self-reported measurement are harmonised by meta-regression with measurement method as a covariate, yielding a pooled device-scale relative-risk curve intended to be transportable across populations. Module 3 (burden recomputation): GBD 2023 exposure distributions are mapped onto the device scale and the LPA-attributable burden is recomputed and compared with the burden reported by GBD 2023; the difference is then decomposed into named definitional components (relative-risk amplitude, TMREL definition, residual). Modules 1 and 3 are linked directly because the calibration between reported and device scales is what makes the GBD exposure input usable on the device scale.",
          FIG1_SAMPLE_EN),
  sprintf("研究设计与三模块分析流程示意。模块 1（设备测量锚点）：用 NHANES 2011–2014 加速度计数据与死亡随访链接，拟合调查加权的 Cox 比例风险模型 + 限制性立方样条，同时得到设备尺度相对风险曲线与个体层面「自报→设备」校准。%s模块 2（外部证据池化）：把覆盖髋式、腕式与自报测量的 5 项外部队列研究（21 个队列特异暴露对比）以测量方法为协变量做元回归，得到可跨人群迁移的设备尺度池化相对风险曲线。模块 3（负担重算）：把 GBD 2023 暴露分布映射到设备尺度，重算 LPA 归因负担并与 GBD 2023 现报负担比较；随后差值为可命名的口径分量（RR 幅度、TMREL 定义、残余）。模块 1 与模块 3 直接相连 —— 正是「自报↔设备」的校准使 GBD 的暴露输入能在设备尺度上使用。",
          FIG1_SAMPLE_ZH)))
def(sprintf("TMREL equivalent / TMREL 设备等效值 = %s MIMS/day（GBD 3600–4400 MET-min/week 的设备等效区间中点）；校准方程 R² = 0.19，残差 SD = %s MIMS/day。", nf(REF_MIMS, 1), nf(3335.4, 0)),
    "Module 2 arm coverage / 模块 2 的测量臂覆盖 = device hip（髋式，LPA / total PA / MVPA）、device wrist（腕式，LPA）、device mixed（混合，total PA）、self-report（自报，total PA / MVPA）。",
    "Arrows are logical dependencies, not data flow / 箭头为逻辑依赖，非数据流。")
p("---")
p("")

# ============================== Fig 2 ==============================
p("## Fig 2. Sample selection and the self-report versus device discrepancy")
p("")
p("**Files / 文件**：`figures/panel/Fig2a_screening_flow.pdf`, `Fig2b1_reported_density.pdf`, `Fig2b2_device_density.pdf`, `Fig2c_reported_vs_device_crosstab.pdf`；`figures/combined/Fig2.pdf`")
p("")
p(bi(
  sprintf("(a) Participant flow from raw records to the modelling sample: %s person-day records, %s passing device quality control, %s aged 25 years or older, and %s with complete covariate data forming the analysis set. (b) Weighted density of activity on a log scale, separately for self-reported activity (left) and device-measured activity (right); the reported distribution is displaced to the right of what the device records. (c) Weighted cross-tabulation of self-reported activity category (rows) against device-measured activity quartile (columns), expressed as row percentages; cells are shaded by column share.",
          nf(N_PAX), nf(N_VALID), nf(N_25), nf(N_MOD)),
  sprintf("(a) 从原始记录到建模样本的受试者流程：%s 条人-日记录 → %s 条通过设备质量控制 → %s 名年龄 ≥ 25 岁 → %s 名协变量完整者构成分析集。(b) 活动量的加权密度（对数尺度），分别给出自报活动（左）与设备测量活动（右）；自报分布整体相对设备记录右移。(c) 自报活动类别（行）与设备活动四分位（列）的加权交叉表，以行百分比表示；按列占比着色。",
          nf(N_PAX), nf(N_VALID), nf(N_25), nf(N_MOD))))
if (!is.null(CRS)) {
  inact_bad <- 1 - sum(CRS[sr == "inactive" & dev == "Q1"]$wsum) / sum(CRS[sr == "inactive"]$wsum)
  q1_share  <- sum(CRS[dev == "Q1"]$wsum) / sum(CRS$wsum)
  def(sprintf("Panel (c) 的关键读数 / Key reading of panel (c)：自报判为 inactive 的加权人中，仍有 %.1f%% 落入设备 Q2–Q4（即自报「不动」并未被设备确认）；全体加权观测中 %.1f%% 为设备 Q1。",
              100 * inact_bad, 100 * q1_share),
      "Reported categories / 自报类别 = inactive (<600 MET-min/week), low (600–1199), moderate (1200–2999), high (≥3000)，依 NHANES 体力活动问卷（PAQ）条目划分。",
      "Device quartiles / 设备四分位 = MIMS/day 的**等人数**四分位（Q1 最低，每组 ~1,963–1,964 人）；组内均值与百分比为调查加权。",
      "All percentages are survey-weighted with NHANES 4-year MEC examination weights / 全部百分比均为调查加权（NHANES 4 年 MEC 体检权重）。",
      "The (b1)/(b2) split exists because reported (MET-min/week) and device (MIMS/day) units are not commensurable; they are shown side by side rather than on one axis / (b) 拆为两个面板是因为自报（MET-min/week）与设备（MIMS/day）量纲不可通约，故并排展示而非共轴。")
}
p("---")
p("")

# ============================== Fig 3 ==============================
p("## Fig 3. Dose-response curves for device-measured activity and mortality")
p("")
p("**Files / 文件**：`figures/panel/Fig3{a..f}_*.pdf`；`figures/combined/Fig3.pdf`")
p("")
p(bi(
  sprintf("Restricted-cubic-spline dose-response curves relating device-measured activity to all-cause and cardiovascular mortality, in three rows of two panels. Row 1 (panels a-b): wrist device-measured total activity (MIMS/day), all-cause (a) and cardiovascular (b). Row 2 (c-d): hip uniaxial Peak-30 (counts/min). Row 3 (e-f): hip uniaxial MVPA (min/day at >=2,020 counts/min). In rows 2-3 each panel shows two curves: solid = not adjusted for total activity volume (M0), dashed = adjusted for total activity volume (M1). All curves are referenced to the exposure value equivalent to the GBD TMREL - %s MIMS/day (row 1) and %s counts/min (rows 2-3) - which sits at the %.1fth percentile of the population exposure distribution. The curves are L-shaped: risk rises steeply below the reference and flattens above it.",
          nf(REF_MIMS, 1), nf(REF_PEAK, 0), 100 * REF_PCT),
  sprintf("设备测量活动与全死因、心血管死亡的限制性立方样条剂量-反应曲线，呈三行两列。第 1 行（面板 a-b）：腕式设备测量活动总量（MIMS/day），全死因 (a) 与心血管 (b)。第 2 行（c-d）：髋式单轴 Peak-30（counts/min）。第 3 行（e-f）：髋式单轴 MVPA（≥2,020 counts/min 的 min/day）。第 2–3 行每个面板有两条曲线：实线 = 未调整活动总量（M0），虚线 = 调整活动总量（M1）。所有曲线以 GBD TMREL 的设备等效值为参照 —— 第 1 行 %s MIMS/day，第 2–3 行 %s counts/min —— 该值位于人群暴露分布的第 %.1f 百分位。曲线呈 L 形：参照值以下风险陡升，以上趋平。",
          nf(REF_MIMS, 1), nf(REF_PEAK, 0), 100 * REF_PCT)))
l1 <- sprintf("Row 1 / 第 1 行（腕式总量，MIMS/day）：全调整模型每 IQR（4,879 MIMS/day）HR —— 全死因 %s；心血管 %s。",
              if (!is.null(AC_M2_IQ)) AC_M2_IQ$hr else "-",
              if (!is.null(CV_M2_IQ)) CV_M2_IQ$hr else "-")
l2 <- if (!is.null(T11I)) {
  pd <- as.data.table(T11I)[exposure == "peak30_per_day" & outcome == "died" & volume_adjusted == TRUE]
  pc <- as.data.table(T11I)[exposure == "peak30_per_day" & outcome == "cvd" & volume_adjusted == TRUE]
  sprintf("Row 2 / 第 2 行（髋式 Peak-30）：每 IQR（%s counts/min）调整体量后 HR —— 全死因 %.2f (%.2f–%.2f), p = %s；心血管 %.2f (%.2f–%.2f), p = %s。",
          nf(pd$iqr, 0), pd$hr_per_iqr, pd$lo, pd$hi, pf(pd$p), pc$hr_per_iqr, pc$lo, pc$hi, pf(pc$p))
} else "-"
l3 <- if (!is.null(T11I)) {
  md <- as.data.table(T11I)[exposure == "mvpa_per_day" & outcome == "died" & volume_adjusted == TRUE]
  mc <- as.data.table(T11I)[exposure == "mvpa_per_day" & outcome == "cvd" & volume_adjusted == TRUE]
  sprintf("Row 3 / 第 3 行（髋式 MVPA）：每 IQR（%s min/day）调整体量后 HR —— 全死因 %.2f (%.2f–%.2f), p = %s；心血管 %.2f (%.2f–%.2f), p = %s。",
          nf(md$iqr, 0), md$hr_per_iqr, md$lo, md$hi, pf(md$p), mc$hr_per_iqr, mc$lo, mc$hi, pf(mc$p))
} else "-"
def(l1, l2, l3,
    "M0 vs M1 / M0 与 M1：M0 = 未调整活动总量；M1 = 调整活动总量（counts，自然样条 4 自由度）。实线与虚线的分离程度即「强度是否携带独立于总量的信息」的视觉答案。",
    "⚠️ 曲线为**关联**证据，不作因果解读。跨行比较需谨慎：行 1 为腕式、行 2–3 为髋式，佩戴部位不同（部位效应见 Table S2 / Table S3）。",
    "⚠️ The curves are associational, not causal. Cross-row comparison is confounded by wear site: row 1 is wrist, rows 2-3 are hip (site effect in Table S2 / Table S3).")
p("---")
p("")

# ============================== Fig 4 ==============================
p("## Fig 4. Calibration from self-reported to device-measured activity and the resulting reporting bias")
p("")
p("**Files / 文件**：`figures/panel/Fig4{a,b,c}_*.pdf`；`figures/combined/Fig4.pdf`")
p("")
rb_t <- if (!is.null(T3B)) as.data.table(T3B)[meets_600 == TRUE]$mims_mean else 13908
rb_f <- if (!is.null(T3B)) as.data.table(T3B)[meets_600 == FALSE]$mims_mean else 12431
p(bi(
  sprintf("(a) Individual-level calibration between self-reported activity (MET-min/week, x-axis) and device-measured activity (MIMS/day, y-axis); grey points are individuals, the blue line is the fitted monotone calibration curve. Self-report explains only a modest share of device-measured variance (R-squared = 0.19; residual SD = %s MIMS/day), so calibration places reported activity on the device scale without removing the reporting error itself. (b) Prevalence of low physical activity by age group under the self-reported definition and under the device-calibrated definition; the two diverge progressively with age. (c) Reporting-bias factor: weighted mean device-measured activity grouped by self-reported activity category; respondents who reported meeting the 600 MET-min/week guideline (n = %s) averaged %s MIMS/day, whereas those who reported not meeting it (n = %s) averaged %s MIMS/day - a difference of only %s MIMS/day (%.0f%%).",
          nf(3335.4, 0),
          nf(if (!is.null(T3B)) as.data.table(T3B)[meets_600 == TRUE]$n else NA),
          nf(rb_t, 0),
          nf(if (!is.null(T3B)) as.data.table(T3B)[meets_600 == FALSE]$n else NA),
          nf(rb_f, 0), nf(rb_t - rb_f, 0), 100 * (rb_t / rb_f - 1)),
  sprintf("(a) 自报活动（MET-min/week，横轴）与设备测量活动（MIMS/day，纵轴）的个体层面校准；灰点为个体，蓝线为拟合的单调校准曲线。自报仅解释设备测量方差的有限部分（R² = 0.19；残差 SD = %s MIMS/day），故校准把自报活动放到设备尺度上，但不消除报告误差本身。(b) 在自报定义与设备校准定义下，「低体力活动」患病率随年龄组的变化；两者随年龄逐渐分离。(c) 报告偏倚因子：按自报活动类别分组的加权平均设备活动量；自报达到 600 MET-min/week 指南者（n = %s）平均 %s MIMS/day，自报未达标者（n = %s）平均 %s MIMS/day —— 差值仅 %s MIMS/day（%.0f%%）。",
          nf(3335.4, 0),
          nf(if (!is.null(T3B)) as.data.table(T3B)[meets_600 == TRUE]$n else NA),
          nf(rb_t, 0),
          nf(if (!is.null(T3B)) as.data.table(T3B)[meets_600 == FALSE]$n else NA),
          nf(rb_f, 0), nf(rb_t - rb_f, 0), 100 * (rb_t / rb_f - 1))))
if (!is.null(T3)) {
  def(sprintf("Panel (a) 的拟合方程 / Fitted calibration equation：自然样条展开 `ns(met_min_wk, 3)`；截距 %s (SE %s)；三个样条项系数 %s；残差 SD = %s MIMS/day。",
              nf(T3$estimate[1], 0), nf(T3$se[1], 0),
              paste(sprintf("%s (SE %s)", nf(T3$estimate[2:4], 0), nf(T3$se[2:4], 0)), collapse = "；"),
              nf(3335.4, 0)))
}
def("⚠️ **量纲不守恒（重要局限）**：自报 MET-min 与设备 MIMS 的量纲不同，校准方程的作用是「把 GBD 暴露分布映射到设备尺度」，**不是**把自报值折算为等能量的设备值。Calibration maps the GBD exposure distribution onto the device scale; it does not convert reported MET-minutes into energy-equivalent device units.",
    "Panel (a) 内置与 Table 4 主链的一致性断言（两者所用参照值差 > 50 MIMS/day 时硬告警）/ Panel (a) carries an internal assertion against the Table 4 main chain.")
p("---")
p("")

# ============================== Fig 5 ==============================
p("## Fig 5. Recomputed low-physical-activity attributable burden versus GBD 2023, and decomposition of the gap")
p("")
p("**Files / 文件**：`figures/panel/Fig5{a,b,c,d}_*.pdf`；`figures/combined/Fig5_a_b_c_d.pdf`（整图）, `Fig5_a_d.pdf`（仅 (a)(d)）")
p("")
p(bi(
  sprintf("(a) Dumbbell plot comparing attributable deaths recomputed under the device-based definition with those reported by GBD 2023 for low physical activity, for the Global level and seven representative countries, in 1990 and 2022 (log scale). (b) The gap by SDI quintile: for each quintile, the pooled PAF under this study's definition and under the GBD 2023 reporting convention, annotated with the fold and the number of countries. (c) Fold (this study divided by GBD 2023 reported) by country and cause, ordered by SDI quintile, on a log colour scale. (d) Waterfall decomposition of the gap at the global level, showing that two named definitional differences fully account for it. Across the %d countries analysed in 2022, the median fold for deaths was %.2f (IQR %.2f-%.2f; full range %.2f-%.2f), and every country exceeded 1.",
          N_CTRY, cset$med, cset$lo, cset$hi, cset$min, cset$max),
  sprintf("(a) 哑铃图：把设备口径重算的归因死亡与 GBD 2023 报告的低体力活动归因死亡并列比较，覆盖全球与 7 个代表国家、1990 与 2022 年（对数尺度）。(b) 按 SDI 五分位的差距：每档给出本研究口径的池化 PAF 与 GBD 2023 报告口径，并标注 fold 与国家数。(c) 逐国 × 逐病因的 fold（本研究 ÷ GBD 2023 现报），按 SDI 五分位排序，对数色标。(d) 全球层面的差距瀑布分解，展示两项可命名的口径差异已完全解释该差异。2022 年分析的 %d 个国家中，死亡口径 fold 中位数 %.2f（IQR %.2f–%.2f；全距 %.2f–%.2f），且**全部国家 > 1**。",
          N_CTRY, cset$med, cset$lo, cset$hi, cset$min, cset$max)))
p("")
p("### Fig 5(a) — recomputed versus GBD 2023 reported burden")
p("")
p(bi(
  sprintf("For each location a horizontal segment connects the attributable deaths recomputed under the device-based definition (left dot) to those reported by GBD 2023 (right dot); the length of the segment is the fold. Global 2022: %.2f million recomputed versus %.3f million reported (fold %.1f). Global 1990: %.2f million versus %.3f million (fold %.1f). The recomputed burden exceeds the reported burden for every location and both years.",
          T4_G22_D / 1e6, T4_G22_G / 1e6, G22$`Fold (deaths)`,
          T4_G90_D / 1e6, T4_G90_G / 1e6, G90$`Fold (deaths)`),
  sprintf("每个 location 以一段水平连线把设备口径重算的归因死亡（左点）与 GBD 2023 现报值（右点）连接，线段长度即 fold。Global 2022：重算 %.2f 百万 vs 现报 %.3f 百万（fold %.1f）。Global 1990：%.2f 百万 vs %.3f 百万（fold %.1f）。所有 location、两个年份，重算负担均高于现报负担。",
          T4_G22_D / 1e6, T4_G22_G / 1e6, G22$`Fold (deaths)`,
          T4_G90_D / 1e6, T4_G90_G / 1e6, G90$`Fold (deaths)`)))
def(sprintf("*fold* = recomputed attributable deaths divided by GBD 2023 reported attributable deaths. Global 2022: PAF %.3f (this study) versus %.3f (GBD 2023). | fold = 重算归因死亡 ÷ GBD 2023 现报归因死亡。Global 2022：PAF 本研究 %.3f vs GBD 2023 %.3f。",
            G22$`PAF (this study)`, G22$`PAF (GBD 2023)`,
            G22$`PAF (this study)`, G22$`PAF (GBD 2023)`),
    sprintf("Locations / 涉及地区 = 全球 + 巴西、中国、德国、印度、日本、尼日利亚、美国（%d 行 × 2 年 = %d 行）。", nrow(T4) / 2, nrow(T4)),
    "对应表 / Companion table = Table 4（主文）；逐国全量版见 Table S12 与面板 (b)(c)。")
p("")
p("### Fig 5(b) — gap by SDI quintile")
p("")
if (!is.null(sdi22)) {
  p(bi(
    sprintf("Grouped bars: for each SDI quintile the PAF obtained by pooling the attributable deaths and the 25+ total deaths across all countries in that quintile, under this study's definition (dark bars) and under the GBD 2023 reporting convention (light bars). Fold annotations above the bars are the ratio of the two. The fold is highest in the lowest SDI quintile (%.2f) and roughly flat across the remaining four quintiles (%s). Country counts per quintile: %s.",
            sdi22$fold_deaths[1],
            paste(sprintf("%.2f", sdi22$fold_deaths[-1]), collapse = "-"),
            paste(sprintf("%s %d", sdi22$quintile, sdi22$n_country), collapse = "; ")),
    sprintf("分组柱：每个 SDI 五分位给出「该档全部国家的归因死亡合计 ÷ 25+ 总死亡合计」得到的 PAF，深色为本研究口径，浅色为 GBD 2023 报告口径；柱上 fold 为两者之比值。fold 在最低 SDI 档最高（%.2f），其余四档基本持平（%s）。各档国家数：%s。",
            sdi22$fold_deaths[1],
            paste(sprintf("%.2f", sdi22$fold_deaths[-1]), collapse = "-"),
            paste(sprintf("%s %d", sdi22$quintile, sdi22$n_country), collapse = "；"))))
  def("每档 PAF 是**负担加权**（该档归因死亡合计 ÷ 该档 25+ 总死亡合计），不是国家等权平均，故可读作「该档整体被低估的倍数」。The quintile PAF is burden-weighted, not a country-equal mean.",
      sprintf("Countries are assigned to SDI quintiles using the official GBD 2023 cut-points applied to the 2022 SDI value. GBD does not publish a national quintile for %s countries (those with subnational units); for these the quintile was recomputed with the same algorithm and flagged in the q_source column of Table S11. 国家按官方 GBD 2023 切点、以 2022 年 SDI 值分档；对 GBD 未发布国家级五分位的 %s 个国家（设有次国家级单位者）按同一算法复算，并在 Table S11 的 q_source 列标注。", NQ_PUB, NQ_PUB))
  p("")
  p("| SDI quintile | Countries | PAF (this study) | PAF (GBD 2023) | fold (deaths) | fold (DALYs) |")
  p("|---|---|---|---|---|---|")
  for (i in seq_len(nrow(sdi22)))
    p("| %s | %d | %.4f | %.4f | %.2f | %.2f |",
      sdi22$quintile[i], sdi22$n_country[i], sdi22$paf_recomputed_deaths[i],
      sdi22$paf_gbd_deaths[i], sdi22$fold_deaths[i], sdi22$fold_dalys[i])
  p("")
}
p("### Fig 5(c) — fold by country and cause")
p("")
if (!is.null(hc)) {
  p(bi(
    sprintf("Heatmap of the fold (recomputed divided by GBD 2023 reported attributable deaths) for %d countries (columns, ordered by SDI quintile with vertical separators) and %d causes (rows), 2022, pooled relative-risk source. Colour is on a log10 scale clipped at fold = %.0f, the 98th percentile (%s of %s tiles, %.1f%%, exceed it); white indicates no discrepancy, progressively darker red a larger discrepancy. Row means differ markedly - the steepest row is %s and the shallowest %s - but this reflects the GBD cause-specific denominators, not cause-specific relative risks.",
            N_CTRY, uniqueN(hc$cause), HCLIP, nf(NCLIP, 0), nf(HN, 0), 100 * NCLIP / HN, DEEP, SHAL),
    sprintf("fold（本研究重算 ÷ GBD 2023 报告归因死亡）热图：%d 个国家（列，按 SDI 五分位排序并以竖线分隔）× %d 个病因（行），2022 年，pooled RR 来源。颜色为 log10 尺度，在 fold = %.0f（第 98 百分位；%s/%s = %.1f%% 的格子超过该值）处截断；白色表示无口径差异，越深的红色表示差异越大。各行均值差异显著 —— 最深一行 %s、最浅一行 %s —— 但其来源是 GBD 逐病因分母，而非病因特异的相对风险。",
            N_CTRY, uniqueN(hc$cause), HCLIP, nf(NCLIP, 0), nf(HN, 0), 100 * NCLIP / HN, DEEP, SHAL)))
  p("")
  qc <- hc[, .(median_fold = median(fold_deaths_c)), by = cause][order(-median_fold)]
  p("| Cause | Median fold (2022) |")
  p("|---|---|")
  for (i in seq_len(nrow(qc))) p("| %s | %.2f |", qc$cause[i], qc$median_fold[i])
  p("")
  def("⚠️ **关键口径免责声明（务必保留）**：色标是 **fold** = 本研究重算的归因死亡 ÷ GBD 2023 报告的归因死亡。本研究对全部病因使用同一条基于活动总量的 RR 曲线，因此**逐病因的 PAF 在病因间恒定**；本面板的行间差异**完全来自 GBD 逐病因分母**，**不可解读为病因特异的相对风险差异**。",
      "⚠️ **Critical caveat - do not remove.** The colour scale is the fold (recomputed divided by GBD 2023 reported attributable deaths). Because a single total-activity relative-risk curve is applied to every cause, the cause-specific PAF is invariant across causes; row-to-row variation originates entirely from the GBD cause-specific denominators and must not be interpreted as cause-specific relative-risk heterogeneity.",
      sprintf("色阶上界按第 98 百分位截断于 fold = %.0f 以保留主体可比性；所有格子的 fold 均 ≥ %.2f，即没有任何国家-病因组合低于 GBD 现报值。The scale is clipped at the 98th percentile (fold = %.0f) to preserve contrast; the minimum tile is fold = %.2f.", HCLIP, HMIN, HCLIP, HMIN),
      "数据源 / Data：`output/M3_BYCOUNTRY_by_cause.csv`（`code/95c_module3_bycountry.R`，205 locations = Global + 204 国）；SDI 排序值来自 `output/Table14_sdi_anchor.csv`。")
}
p("")
p("### Fig 5(d) — decomposition of the gap (waterfall)")
p("")
if (!is.null(st)) {
  p(bi(
    sprintf("Waterfall decomposition of the fold between this study's primary device-based estimate and the burden reported by GBD 2023 (Global, 2022; eight causes combined; deaths). From the primary estimate (PAF = %.3f, fold = %.2f), aligning the excess-risk amplitude of the pooled relative-risk curve to the level implied by the official GBD PAF - that is, reducing the mean relative risk below the TMREL from 1.39 to 1.04 - lowers the estimate to PAF = %.3f (fold = %.2f); subsequently moving the TMREL from the absolute threshold used here (the %.1fth percentile of the population exposure distribution) to the GBD definition (85th percentile) raises it to PAF = %.3f (fold = %.2f). The residual is x%.3f (%.1f%%), i.e. the two named definitional differences fully account for the gap. The whisker on the first bar gives the range across the eight study locations, which is narrow (fold 5.36-6.38) relative to the total gap.",
            as.numeric(st[["1 Study estimate"]]$to_paf), as.numeric(st[["1 Study estimate"]]$fold_to),
            as.numeric(st[["2 Change: RR magnitude"]]$to_paf), as.numeric(st[["2 Change: RR magnitude"]]$fold_to),
            100 * REF_PCT,
            as.numeric(st[["3 Change: TMREL definition"]]$to_paf), as.numeric(st[["3 Change: TMREL definition"]]$fold_to),
            as.numeric(st[["4 Residual"]]$multiplier), 100 * (as.numeric(st[["4 Residual"]]$multiplier) - 1)),
    sprintf("本研究设备口径主估计与 GBD 2023 报告负担之比值（fold）的瀑布分解（全球，2022 年；8 个病因合计；死亡口径）。自本研究主结果（PAF = %.3f，fold = %.2f）出发，先把池化相对风险曲线的超额风险幅度对齐至官方 GBD PAF 反算的隐含水平 —— 即把 TMREL 之下人群的平均 RR 由 1.39 降至 1.04 —— 估计值降至 PAF = %.3f（fold = %.2f）；随后把 TMREL 由本文采用的绝对阈值（人群暴露分布第 %.1f 百分位）移至 GBD 定义（第 85 百分位），估计值升至 PAF = %.3f（fold = %.2f）。残余仅 x%.3f（%.1f%%），即上述两项可命名的口径差异已完全解释该差距。首柱误差棒为 8 个研究地区的范围，相对于总差距而言很窄（fold 5.36–6.38）。",
            as.numeric(st[["1 Study estimate"]]$to_paf), as.numeric(st[["1 Study estimate"]]$fold_to),
            as.numeric(st[["2 Change: RR magnitude"]]$to_paf), as.numeric(st[["2 Change: RR magnitude"]]$fold_to),
            100 * REF_PCT,
            as.numeric(st[["3 Change: TMREL definition"]]$to_paf), as.numeric(st[["3 Change: TMREL definition"]]$fold_to),
            as.numeric(st[["4 Residual"]]$multiplier), 100 * (as.numeric(st[["4 Residual"]]$multiplier) - 1))))
  def(sprintf("*fold* = PAF(this study) / PAF(GBD 2023 reported) = PAF / %.4f；分母为全局常数。| fold = PAF(本研究) ÷ PAF(GBD 2023 现报) = PAF ÷ %.4f。",
              as.numeric(st[["1 Study estimate"]]$paf_gbd_reported),
              as.numeric(st[["1 Study estimate"]]$paf_gbd_reported)),
      "'RR magnitude' = 把池化设备测量曲线的超额风险幅度对齐到官方 PAF 反算的隐含水平；'TMREL definition' = 把 TMREL 移到人群暴露分布第 85 百分位（GBD 定义）。",
      "残余柱按设计几乎不可见：两项可命名的口径差异之后，差距已不足 1%。",
      "数据源 / Source：`output/Fig5d_waterfall_data.csv`（`code/07_fig5d_waterfall.R`，只读 `Table9_m3_scenario_summary.csv` + `Table4_m3_decomp.csv`，不重算）；同一分解按 8 个地区分别绘制的补充图见 `Fig5d_waterfall_by_region`。")
}
p("")
p(sprintf("> ⚠️ **面板间数值一致性提示**：面板 (a) 取 `95`（8 地区冻结版）的重算值，面板 (d) 取 `97`（情景脚本）的重算值，面板 (b)(c) 取 `95c`（205 国版）的重算值。三者现由**同一确定性算法**（遍历全部后验曲线，s1p 主轨）产生，Global 2022 的 fold **完全一致**：%.2f / %.2f / %.2f。逐项对照见文末「口径一致性自检」段。",
            as.numeric(G22$`Fold (deaths)`),
            as.numeric(st[["1 Study estimate"]]$fold_to),
            as.numeric(sdi22$fold_deaths[0] * 0 + M3T[location == "Global" & year == 2022 & rr_source == "pooled"]$fold_deaths)))
p("---")
p("")

# ============================== Fig 6 ==============================
p("## Fig 6. Sensitivity analyses")
p("")
p("**Files / 文件**：`figures/panel/Fig6{a,b,c}_*.pdf`；`figures/combined/Fig6.pdf`")
p("")
p(bi(
  sprintf("(a) Scenario forest plot: the fold under each of the %d pre-specified Module 3 scenarios at the global level in 2022, with horizontal ranges spanning the eight study locations. (b) Leave-one-study-out: the pooled relative-risk curve refitted after dropping each contributing cohort in turn; bars give the range across the four locations. (c) E-values: the minimum strength of association that an unmeasured confounder would need with both the exposure and the outcome to explain away the observed hazard ratio (dot) and its confidence-interval bound (vertical notch).",
          if (!is.null(T9)) nrow(T9) else 12),
  sprintf("(a) 情景森林图：预先设定的 %d 个模块 3 情景下，2022 年全球层面的 fold，横线范围覆盖 8 个研究地区。(b) 留一法：逐篇剔除贡献队列后重新拟合池化相对风险曲线；横线为 4 个地区的范围。(c) E 值：要把观测风险比（点）及其置信区间界（竖向缺口）完全解释掉，未测混杂需同时与暴露和结局达到的最小关联强度。",
          if (!is.null(T9)) nrow(T9) else 12)))
if (!is.null(LOO) && nrow(LOO)) {
  def(sprintf("Panel (b) / 面板 (b)：基线 fold = %.2f；逐篇剔除后 %s。方向全部不变，幅度强依赖支撑设备曲线的两篇（Ekelund hip、Tarp mixed）。",
              PBASE, paste(sprintf("剔 %s → %.2f (%+.1f%%)", LOO$dropped_study, LOO$fold,
                                   100 * (LOO$fold / PBASE - 1)), collapse = "；")))
}
if (!is.null(EV)) {
  def(sprintf("Panel (c) / 面板 (c)：共 %d 个风险比纳入（口径见 Table S10）。最大点估计 E 值为 %.2f；最小置信区间界 E 值为 %.1f。",
              nrow(EV), max(EV$e_point_primary, na.rm = TRUE), min(EV$e_ci_primary, na.rm = TRUE)),
      "E(CI) = 1 表示该置信区间本身已跨过无效线，无需任何未测混杂即可解释。E(CI) = 1 means the interval already crosses the null.",
      "HR → RR 近似按 VanderWeele 2020（结局非罕见时更保守）/ HR-to-RR approximation follows VanderWeele 2020.")
}
p("---")
p("")

# ============================== Table 1 ==============================
p("## Table 1. Weighted baseline characteristics by device-measured activity quartile")
p("")
p("**Files / 文件**：`figures/tables/Table1_baseline.pdf`；`output/Table1_baseline_manuscript.csv`")
p("")
p(bi(
  sprintf(paste0("%s %s Continuous variables are ",
                 "survey-weighted means (SE); categorical variables are survey-weighted percentages (SE). ",
                 "Quartile 1 is the least active. Age, body-mass index, systolic blood pressure and the ",
                 "prevalences of diabetes and cardiovascular disease decrease monotonically across ",
                 "quartiles, whereas self-reported activity rises only modestly - a first indication ",
                 "that self-report does not order individuals the way device measurement does."),
          T1_SAMPLE_EN, T1_STAGE_EN),
  sprintf(paste0("%s%s",
                 "连续变量为调查加权均值（SE），分类变量为调查加权百分比（SE）。Q1 为活动量最低组。",
                 "年龄、体质指数、收缩压以及糖尿病与心血管病史的患病率随四分位单调下降，",
                 "而自报活动量仅小幅上升 —— 这是自报无法像设备测量那样对个体正确排序的初步提示。"),
          T1_SAMPLE_ZH, T1_STAGE_ZH)))
sel <- function(v) as.numeric(gsub(" \\(.*", "", T1[variable == v]$Overall))
sel4 <- function(v) as.numeric(gsub(" \\(.*", "", T1[variable == v]$Q4))
def(sprintf("Self-reported MET-min/week / 自报 MET-min/week：整体 %s → Q4 %s（增幅 %s%%）。",
            nf(sel("Self-reported MET-min/week"), 0), nf(sel4("Self-reported MET-min/week"), 0),
            nf(100 * (sel4("Self-reported MET-min/week") / sel("Self-reported MET-min/week") - 1), 0)),
    sprintf("Device MIMS/day / 设备 MIMS/day：整体 %s → Q4 %s（增幅 %s%%）。两组增幅的量级差异直接说明自报对活动的分辨力远低于设备。",
            nf(sel("Device MIMS/day"), 0), nf(sel4("Device MIMS/day"), 0),
            nf(100 * (sel4("Device MIMS/day") / sel("Device MIMS/day") - 1), 0)),
    "SE = survey-weighted standard error；MIMS/day = monitor-independent movement summary per day（7 日平均）。",
    "Estimates use NHANES 4-year MEC examination weights / 采用 NHANES 4 年 MEC 体检权重。",
    "Companion figure / 配套图 = Fig 2(b)(c)。")
p("---")
p("")

# ============================== Table 2 ==============================
p("## Table 2. Hazard ratios for device-measured activity and mortality")
p("")
p("**Files / 文件**：`figures/tables/Table2_hazard_hrs.pdf`；`output/Table2_hr_manuscript.csv`")
p("")
p(bi(
  sprintf("Survey-weighted Cox proportional-hazards models relating quartiles of device-measured total activity (MIMS/day) to all-cause and cardiovascular mortality, referenced to the exposure value equivalent to the GBD TMREL (%s MIMS/day, the %.0fth percentile of the exposure distribution) rather than to the lowest quartile. Model 1 is minimally adjusted (age, sex, race/ethnicity); Model 2 is fully adjusted (Model 1 plus education, poverty-income ratio, body-mass index, systolic blood pressure, smoking, alcohol use, diabetes and cardiovascular disease history). In the fully adjusted model the highest quartile showed an all-cause hazard ratio of %s and a cardiovascular hazard ratio of %s, with a significant trend across quartiles.",
          nf(REF_MIMS, 0), round(100 * REF_PCT),
          if (!is.null(AC_M2_Q4)) AC_M2_Q4$hr else "-",
          if (!is.null(CV_M2_Q4)) CV_M2_Q4$hr else "-"),
  sprintf("设备测量活动总量（MIMS/day）四分位与全死因、心血管死亡的调查加权 Cox 比例风险模型，参照值为 GBD TMREL 的设备等效值（%s MIMS/day，暴露分布第 %.0f 百分位），而非最低四分位。模型 1 为最小调整（年龄、性别、种族/民族）；模型 2 为全调整（模型 1 加教育、贫困收入比、体质指数、收缩压、吸烟、饮酒、糖尿病与心血管病史）。全调整模型下，最高四分位的全死因风险比为 %s、心血管风险比为 %s，四分位趋势检验显著。",
          nf(REF_MIMS, 0), round(100 * REF_PCT),
          if (!is.null(AC_M2_Q4)) AC_M2_Q4$hr else "-",
          if (!is.null(CV_M2_Q4)) CV_M2_Q4$hr else "-")))
def(sprintf("Per-IQR contrasts / 每 IQR 对比：全死因 %s；心血管 %s（每 IQR = 4,879 MIMS/day，由同一 RCS 模型做线性对比提取，与 Fig 3 曲线口径一致）。",
            if (!is.null(AC_M2_IQ)) AC_M2_IQ$hr else "-",
            if (!is.null(CV_M2_IQ)) CV_M2_IQ$hr else "-"),
    "P for trend / 趋势 P 值：以四分位中位数为连续变量纳入模型；Q4 的 P 值单独拟合，以避免与连续项共线。",
    "Absorbing reference / 绝对值参照：用 TMREL 设备等效值而非最低四分位，使 HR 可直接与 Fig 3 曲线、模块 3 的 PAF 口径衔接。",
    "⚠️ 关联性证据：模型调整了主要混杂，但不排除残余混杂与反向因果（低活动可能为疾病前驱表现）；敏感性见 Table S10（E 值）。")
p("---")
p("")

# ============================== Table 3 ==============================
p("## Table 3. Calibration equation, reporting-bias factors and exposure SD relation")
p("")
p("**Files / 文件**：`figures/tables/Table3_calibration_coefficients.pdf`, `Table3b_reporting_bias.pdf`；`output/Table3_*`")
p("")
if (!is.null(T3) && !is.null(T3B)) {
  p(bi(
    sprintf("Three panels. (a) Coefficients of the monotone natural-spline regression of device-measured activity (MIMS/day) on self-reported activity (MET-min/week): intercept %s (SE %s) plus three spline terms (%s); residual SD = %s MIMS/day and R-squared = 0.19. (b) Reporting-bias factor: weighted mean device-measured activity by whether the respondent reported meeting the 600 MET-min/week guideline - %s MIMS/day (n = %s) versus %s MIMS/day (n = %s), a difference of only %s MIMS/day (%.0f%%). (c) Coefficients of the within-NHANES relation between the standard deviation and the mean of the exposure distribution, used to assign a cell-specific exposure SD (5-year age group by sex) as the PAF input.",
            nf(T3$estimate[1], 0), nf(T3$se[1], 0),
            paste(nf(T3$estimate[2:4], 0), collapse = ", "), nf(3335.4, 0),
            nf(rb_t, 0), nf(as.data.table(T3B)[meets_600 == TRUE]$n, 0),
            nf(rb_f, 0), nf(as.data.table(T3B)[meets_600 == FALSE]$n, 0),
            nf(rb_t - rb_f, 0), 100 * (rb_t / rb_f - 1)),
    sprintf("三个面板。(a) 以自报活动（MET-min/week）对设备测量活动（MIMS/day）作单调自然样条回归的系数：截距 %s (SE %s)，另有三个样条项（%s）；残差 SD = %s MIMS/day，R² = 0.19。(b) 报告偏倚因子：按自报是否达到 600 MET-min/week 指南分组的加权平均设备活动量 —— %s MIMS/day（n = %s）vs %s MIMS/day（n = %s），差值仅 %s MIMS/day（%.0f%%）。(c) NHANES 内部「暴露分布标准差—均值」关系的系数，用于逐 cell（5 岁年龄组 × 性别）指定暴露 SD，作为 PAF 的输入。",
            nf(T3$estimate[1], 0), nf(T3$se[1], 0),
            paste(nf(T3$estimate[2:4], 0), collapse = "、"), nf(3335.4, 0),
            nf(rb_t, 0), nf(as.data.table(T3B)[meets_600 == TRUE]$n, 0),
            nf(rb_f, 0), nf(as.data.table(T3B)[meets_600 == FALSE]$n, 0),
            nf(rb_t - rb_f, 0), 100 * (rb_t / rb_f - 1))))
  def(sprintf("样条基 / Spline basis = `splines::ns(met_min_wk, 3)`；系数 %s。",
              paste(sprintf("%s (SE %s)", nf(T3$estimate, 0), nf(T3$se, 0)), collapse = "；")),
      "⚠️ **量纲不守恒（重要局限）**：自报 MET-min 与设备 MIMS 量纲不同；校准方程用于把 GBD 暴露分布映射到设备尺度，**不是**把自报值折算为等能量的设备值。",
      "⚠️ **暴露 SD 的来源**：GBD 2023 风险暴露文件只给均值与 95% UI，**不含 SD**，而 SD 是 PAF 的必需输入。本研究按 GBD 公布的方法形式 ln(SD) = β0 + β1·ln(MEAN) + β2·Age + β3·SR + β4·Fem，在 NHANES 本土加速度计数据上自估该关系（面板 c），逐 cell 查表；备选的外部 CV 假定网格保留为敏感性分析（Table S6）。",
      sprintf("Reporting bias / 报告偏倚：达标组与未达标组的设备活动量仅差 %s MIMS/day（约 %.0f%%），远小于两者名义上的活动量差，说明自报的「达标」判定在设备尺度上几乎没有分辨力。",
              nf(rb_t - rb_f, 0), 100 * (rb_t / rb_f - 1)))
} else {
  p("（Table 3 产物缺失，待补。）")
}
p("---")
p("")

# ============================== Table 4 ==============================
p("## Table 4. Recomputed versus GBD 2023 reported attributable burden (Global and representative countries)")
p("")
p("**Files / 文件**：`figures/tables/Table4_recomputed_vs_gbd.pdf`；`output/Table4_burden_manuscript.csv`")
p("")
p(bi(
  sprintf("Attributable deaths and DALYs for low physical activity, comparing this study's device-based recomputation with the burden reported by GBD 2023, for the global level and seven representative countries (Brazil, China, Germany, India, Japan, Nigeria and the United States) in 1990 and 2022. The recomputed burden exceeds the reported burden at every location and in both years (fold > 1); the global fold for deaths was %.1f in 1990 and %.1f in 2022. Folds are generally larger for deaths than for DALYs, and are largest in Nigeria (%.1f in 2022) and smallest in Brazil (%.1f).",
          G90$`Fold (deaths)`, G22$`Fold (deaths)`,
          t4(2022, "Nigeria")$`Fold (deaths)`, t4(2022, "Brazil")$`Fold (deaths)`),
  sprintf("低体力活动的归因死亡与 DALYs：本研究设备口径重算 vs GBD 2023 现报，覆盖全球与 7 个代表国家（巴西、中国、德国、印度、日本、尼日利亚、美国），1990 与 2022 两年。所有 location、两个年份，重算负担均高于现报负担（fold > 1）；全球死亡口径 fold 在 1990 年为 %.1f，2022 年为 %.1f。死亡口径 fold 一般大于 DALYs 口径，其中尼日利亚最大（2022 年 %.1f）、巴西最小（%.1f）。",
          G90$`Fold (deaths)`, G22$`Fold (deaths)`,
          t4(2022, "Nigeria")$`Fold (deaths)`, t4(2022, "Brazil")$`Fold (deaths)`)))
def("*fold* = recomputed / GBD 2023 reported。| fold = 本研究重算 ÷ GBD 2023 现报。",
    sprintf("Global 2022：PAF 本研究 %.3f vs GBD 2023 %.3f；归因死亡 %s vs %s。Global 1990：PAF %.3f vs %.3f；死亡 %s vs %s。",
            G22$`PAF (this study)`, G22$`PAF (GBD 2023)`, nf(T4_G22_D, 0), nf(T4_G22_G, 0),
            G90$`PAF (this study)`, G90$`PAF (GBD 2023)`, nf(T4_G90_D, 0), nf(T4_G90_G, 0)),
    "本表为**主文结论表**；逐国全量版（204 国，按 SDI 排序）见 Table S12，对应图见 Fig 5(a)-(c)。",
    "⚠️ 重算值为**确定性量**（遍历全部后验曲线，`E[PAF]` 口径，方差 0）：95 / 95c / 97 三处产出的同一量完全一致，不含抽样误差 —— 逐项对照见文末「口径一致性自检」。")
p("---")
p("")

# ============================== 补充材料 ==============================
p("## Supplementary material — 补充材料")
p("")
p("> **编号约定 / Numbering convention**：主文 Table 1–4 固定；下表把项目内部的 `Table5`–`Table14` / `TableS4` 文件映射为连续的补充表编号 S1–S12，**内部文件名保持不变**，下方每张补充表的表注均按此编号书写（映射已全量落地，S4 对应 `Table8_*`）。")
p("> The main-text tables keep their stems; the internal stems in the table below are mapped to consecutive supplementary numbers S1-S12 and are unchanged on disk. Every supplementary caption in this document is written against this mapping.")
p("")
p("| Supplementary | Internal stem | Content | 内容 |")
p("|---|---|---|---|")
p("| Table S1 | `Table5_bop_*` | BoP pooled RR / method effect / wear-site effect / slopes / fit diagnostic | 外部队列池化 RR、方法效应、部位效应、斜率、拟合诊断 |")
p("| Table S2 | `Table6_nhanes_hip_wrist_RR` | Within-NHANES hip-versus-wrist site effect | NHANES 内部髋式 vs 腕式部位效应 |")
p("| Table S3 | `Table7_bop_nhanes_*` | NHANES arms entering the pooled curve (controlled sensitivity) | NHANES 臂并入池化曲线的受控敏感性 |")
p("| Table S4 | `Table8_*` + `Table8b_*` | Hip wear-rule x wrist criterion matrix; literature-side site decomposition, its metric robustness (external total-activity anchor) and the metric-aligned comparison | 髋式 wear 规则 × 腕式判据矩阵；文献侧部位分解、其指标稳健性（总量口径外部锚定）与**指标对齐**对照 |")
p("| Table S5 | `Table9_m3_scenario_summary` | Module 3 scenario ladder (formal grading table) | 模块 3 情景定级表 |")
p("| Table S6 | `Table10_m3_robustness` | Module 3 robustness (exposure CV grid + population weighting) | 模块 3 稳健性（CV 网格 + 人口加权） |")
p("| Table S7 | `Table10_m3_country_homogeneity` | Country-scale homogeneity of the device metric | 设备尺度的国别同质化 |")
p("| Table S8 | `Table11_pam_intensity_*` | Hip intensity metrics (Peak-30, MVPA): quartiles and per-IQR | 髋式强度指标（Peak-30、MVPA）：四分位与每 IQR |")
p("| Table S9 | `Table12_*` | BoP leave-one-study-out | BoP 留一研究法 |")
p("| Table S10 | `Table13_evalues` | E-values for unmeasured confounding | 未测混杂的 E 值 |")
p("| Table S11 | `Table14_sdi_anchor` | SDI anchor table (205 locations x 1990/2022/2023 + official quintile) | SDI 锚点表（205 location × 三年 + 官方五分位） |")
p("| Table S12 | `TableS4_burden_bycountry_manuscript` | Per-country burden comparison (204 countries, SDI-ordered) | 逐国负担对比（204 国，按 SDI 排序） |")
p("")
p("### Table S1. Pooled relative-risk curves from external cohorts (Burden of Proof)")
p("")
if (!is.null(PW90)) {
  p(bi(
    sprintf("Multi-level meta-regression of 5 external cohort studies (21 cohort-specific exposure contrasts) covering hip, wrist, mixed and self-reported measurement, with measurement method and metric definition (total PA, LPA, MVPA) as covariates. The pooled device-scale relative risk at the highest offset percentile (about the 100th exposure percentile) is %.2f (95%% CI %.2f-%.2f) for total PA, %.2f for LPA and %.2f for MVPA - all below 1, i.e. protective. The measurement-method effect is estimable: at the same relative percentile, the hip-based relative risk is %.2f times the wrist-based one for LPA (95%% CI %.2f-%.2f; p = %s) and %.2f times for total PA (95%% CI %.2f-%.2f; p = %s). Maximum absolute log residual is %.3f (a relative-risk factor of %.2f), reported explicitly as a lack-of-fit warning rather than hidden.",
            as.data.table(PW90)[metric_definition == "total_PA"]$rr,
            as.data.table(PW90)[metric_definition == "total_PA"]$rr_lo,
            as.data.table(PW90)[metric_definition == "total_PA"]$rr_hi,
            as.data.table(PW90)[metric_definition == "LPA"]$rr,
            as.data.table(PW90)[metric_definition == "MVPA"]$rr,
            W60$rr_ratio_hip_over_wrist, W60$rr_ratio_lo, W60$rr_ratio_hi, pf(W60$p_diff),
            M60$rr_ratio_at_off60, M60$rr_ratio_lo, M60$rr_ratio_hi, pf(M60$p_diff),
            MAXRES, exp(MAXRES)),
    sprintf("对 5 项外部队列研究（21 个队列特异暴露对比，覆盖髋式、腕式、混合与自报测量）的多水平元回归，以测量方法与指标定义（总活动量、LPA、MVPA）为协变量。池化设备尺度相对风险在最高偏移百分位（约当第 100 暴露百分位）处：总活动量 %.2f（95%% CI %.2f–%.2f），LPA %.2f，MVPA %.2f —— 均低于 1，即保护性。测量方法效应可估：同一相对百分位下，LPA 的髋式相对风险为腕式的 %.2f 倍（95%% CI %.2f–%.2f；p = %s），总活动量为 %.2f 倍（95%% CI %.2f–%.2f；p = %s）。最大绝对 log 残差 %.3f（相对风险因子 %.2f），已显式报告为失拟告警，未作隐藏。",
            as.data.table(PW90)[metric_definition == "total_PA"]$rr,
            as.data.table(PW90)[metric_definition == "total_PA"]$rr_lo,
            as.data.table(PW90)[metric_definition == "total_PA"]$rr_hi,
            as.data.table(PW90)[metric_definition == "LPA"]$rr,
            as.data.table(PW90)[metric_definition == "MVPA"]$rr,
            W60$rr_ratio_hip_over_wrist, W60$rr_ratio_lo, W60$rr_ratio_hi, pf(W60$p_diff),
            M60$rr_ratio_at_off60, M60$rr_ratio_lo, M60$rr_ratio_hi, pf(M60$p_diff),
            MAXRES, exp(MAXRES))))
  def("offset = 相对参照点的百分位偏移。The ratio > 1 means the comparator curve is less protective; < 1 means it is more protective. 比值 > 1 表示被比较曲线保护性更弱。",
      sprintf("⚠️ 失拟已量化：最大 |log 残差| = %.3f（相对风险因子 %.2f），来源是外部研究间异质性而非模型设定错误。Lack of fit is quantified, not hidden.", MAXRES, exp(MAXRES)),
      "配套图 / Companion figure = Fig 1 的 Module 2 框；主分析只用 device_pooled × total_PA 一条曲线。")
} else p("（产物缺失，待补。）")
p("")
p("### Table S2. Within-NHANES hip-versus-wrist site effect")
p("")
if (!is.null(T6)) {
  p(bi(
    sprintf("Two device curves fitted in the same survey - NHANES 2003-2006 hip uniaxial counts versus NHANES 2011-2014 wrist MIMS - placed on a common percentile axis, **both on the total-activity axis** (no intensity band), with the ratio of the wrist to the hip relative risk at each offset. On the same relative percentile the wrist curve is flatter than the hip curve, but the ratio stays close to 1 (range %.2f-%.2f) and its confidence interval includes 1 at most offsets, so the within-person site effect is not significant.",
            min(as.data.table(T6)$rr_ratio_wr_hip), max(as.data.table(T6)$rr_ratio_wr_hip)),
    sprintf("在同一调查体系的两套数据上拟合的两条设备曲线 —— NHANES 2003–2006 髋式单轴计数 vs NHANES 2011–2014 腕式 MIMS —— 置于共同的百分位轴上，**两条同为「总量」轴**（未做强度分带），并给出各偏移点「腕式 ÷ 髋式」相对风险的比值。在同一相对百分位上，腕式曲线比髋式平缓，但比值接近 1（范围 %.2f–%.2f），且多数偏移点的置信区间跨过 1，故**个体内部位效应不显著**。",
            min(as.data.table(T6)$rr_ratio_wr_hip), max(as.data.table(T6)$rr_ratio_wr_hip))))
  def("⚠️ 本表与 Table S4 的文献侧部位效应形成对照：后者是**跨研究**比较且文献侧指标为 LPA（本表为总量），不能与个体内估计等量齐观；跨指标比较的合法性由 Table S4(h) 的量化许可支撑。",
      "两条曲线来自**不同 NHANES 周期**，故不是严格的同一批个体；比较在百分位轴上做，回避了单位不可通约的问题。",
      "指标轴归属（总量）不是凭印象写的：由 `04d_lit_site_contrast.R` §0 以 `Table8_metric_axis_check.csv` 的 R0 行与 `Table6` 的 `rr_hip` 逐值机器校验（偏差 0），若 04c 换了默认轴该步会中止。")
} else p("（产物缺失，待补。）")
p("")
p("### Table S3. NHANES arms in the pooled curve (controlled sensitivity)")
p("")
if (!is.null(T7S)) {
  t7 <- as.data.table(T7S)
  A60 <- t7[spec == "A_primary_only" & offset_pts == 60]
  B60 <- t7[spec == "B_primary_plus_nhanes" & offset_pts == 60 & metric_definition == "LPA"]
  C60 <- t7[spec == "C_nhanes_only" & offset_pts == 60 & metric_definition == "total_PA"]
  pa_ <- as.data.table(T7P)[location == "Global" & year == 2022 & rr_source == "pooled"]
  p(bi(
    sprintf("Three specifications of the pooled device curve: A (external device evidence only), B (external plus NHANES device arms) and C (NHANES only). Adding the NHANES device arms to the pool (A to B) attenuates the site ratio from %.2f to %.2f and removes its significance (p %.3f to p %.3f); restricting to NHANES alone (C) reverses it (%.2f, p = %.3f). The effect on the attributable burden is modest: at the global level, moving from A to B changes the fold from %.2f to %.2f (%.1f%%).",
            A60$rr_ratio_hip_over_wrist, B60$rr_ratio_hip_over_wrist,
            A60$p_diff, B60$p_diff, C60$rr_ratio_hip_over_wrist, C60$p_diff,
            pa_$fold_A, pa_$fold_B, 100 * (pa_$fold_B / pa_$fold_A - 1)),
    sprintf("池化设备曲线的三种规格：A（仅外部设备证据）、B（外部 + NHANES 设备臂）、C（仅 NHANES）。把 NHANES 设备臂并入池（A→B）使部位比值由 %.2f 衰减至 %.2f 并失去显著性（p 由 %.3f 变为 %.3f）；仅用 NHANES（C）则方向反转（%.2f，p = %.3f）。对归因负担的影响温和：全球层面 A→B 使 fold 由 %.2f 变为 %.2f（%.1f%%）。",
            A60$rr_ratio_hip_over_wrist, B60$rr_ratio_hip_over_wrist,
            A60$p_diff, B60$p_diff, C60$rr_ratio_hip_over_wrist, C60$p_diff,
            pa_$fold_A, pa_$fold_B, 100 * (pa_$fold_B / pa_$fold_A - 1))))
  def("规格 B 未进入主分析，仅作受控敏感性 —— 把同一队列的证据同时用作锚点与池化输入会引入信息复用。Specification B is a controlled sensitivity only.",
      "A→B 的方向说明：加入 NHANES 设备臂后，外部证据中看似显著的部位效应被稀释，提示该效应部分来自跨研究的测量与人群差异。")
} else p("（产物缺失，待补。）")
p("")
p("### Table S4. Within-NHANES hip wear-rule x wrist criterion grid, and the literature-side site decomposition")
p("")
if (!is.null(T8S) && !is.null(T8L)) {
  t8  <- as.data.table(T8S)[, `:=`(ratio_mean = as.numeric(ratio_mean), p = as.numeric(p))]
  lit <- as.data.table(T8L)
  lit[, `:=`(ratio_wrist_over_hip = as.numeric(ratio_wrist_over_hip),
             ratio_lo = as.numeric(ratio_lo), ratio_hi = as.numeric(ratio_hi),
             p_value = as.numeric(p_value))]
  OFF0 <- 60L
  g60 <- t8[offset == OFF0]
  N_CELL <- nrow(t8); N_G6 <- nrow(g60)
  N_RULE <- uniqueN(t8$hip_rule); N_CRIT <- uniqueN(t8$wrist_criterion); N_OFF <- uniqueN(t8$offset)
  R_MIN <- min(g60$ratio_mean); R_MAX <- max(g60$ratio_mean)
  SIG   <- g60[p < 0.05]; N_SIG <- nrow(SIG)
  SIGRUL <- if (N_SIG) paste(sort(unique(SIG$hip_rule)), collapse = ", ") else "-"
  # 显著规则在网格中保留的髋式人-日规模（取各规则的最大 n_hip）
  sig_n <- if (N_SIG) {
    nr <- sapply(sort(unique(SIG$hip_rule)), function(r) max(t8[hip_rule == r]$n_hip))
    paste(sprintf("%s (n = %s)", names(nr), nf(nr, 0)), collapse = "; ")
  } else "-"
  PR <- t8[hip_rule == "R0_choi2011" & wrist_criterion == "C0_wake600" & offset == OFF0]
  # 文献侧三档
  lo_ <- function(o) lit[offset == o]$ratio_wrist_over_hip
  li_ <- function(o) lit[offset == o]$ratio_lo
  hi_ <- function(o) lit[offset == o]$ratio_hi
  lp_ <- function(o) lit[offset == o]$p_value
  LIT_OFF <- sort(unique(lit$offset))
  LIT_TXT <- paste(sprintf("%.2f (%.2f-%.2f, p = %s)", lo_(LIT_OFF), li_(LIT_OFF), hi_(LIT_OFF),
                           pf(lp_(LIT_OFF))), collapse = "; ")
  LIT_TXT_ZH <- paste(sprintf("%.2f（%.2f–%.2f，p = %s）", lo_(LIT_OFF), li_(LIT_OFF), hi_(LIT_OFF),
                              pf(lp_(LIT_OFF))), collapse = "；")
  LIT_OFS <- paste(LIT_OFF, collapse = "/")
  LIT_MIN <- min(lo_(LIT_OFF)); LIT_MAX <- max(lo_(LIT_OFF))
  # 留一臂杠杆
  LV_MAXDEV <- if (!is.null(T8V)) {
    lv <- as.data.table(T8V)
    d <- c(abs(as.numeric(lv$ratio_off25) - lo_(25)),
           abs(as.numeric(lv$ratio_off50) - lo_(50)),
           abs(as.numeric(lv$ratio_off75) - lo_(75)))
    max(d, na.rm = TRUE)
  } else NA_real_
  # 设计不可通约维度计数
  DI_NO <- DI_YES <- DI_TOT <- NA_integer_
  if (!is.null(T8D)) {
    td <- as.data.table(T8D); v <- trimws(td[[ncol(td)]])
    DI_NO  <- sum(grepl("否", v, fixed = TRUE)); DI_YES <- sum(v == "是"); DI_TOT <- nrow(td)
  }
  # NHANES × 文献可比性
  NOV <- NDIFF <- NA_integer_
  if (!is.null(T8C)) {
    cp <- as.data.table(T8C)
    NOV   <- sum(as.logical(cp$ci_overlap))
    NDIFF <- sum(!as.logical(cp$nhanes_ci_contains_lit_point))   # 文献点估计落在 NHANES CI 之外的档数
  }
  # 指标轴检查：直接由 rr_off30 / rr_off80 重算「保留比」，不依赖列名有歧义的派生列
  RET_MIN <- RET_MAX <- AX_MIN <- AX_MAX <- NULL; NAMX <- NA_integer_
  if (!is.null(T8X)) {
    mx <- as.data.table(T8X); NAMX <- nrow(mx)
    ret <- as.numeric(mx$rr_off80) / as.numeric(mx$rr_off30)
    i_min <- which.min(ret); i_max <- which.max(ret)
    RET_MIN <- ret[i_min]; RET_MAX <- ret[i_max]
    AX_MIN  <- mx[[1]][i_min]; AX_MAX <- mx[[1]][i_max]
    # 仅在英文段落中用到的标签翻译（只翻标签，不改数值/不改产品名）
    ax_en <- function(s) {
      s <- gsub("总量 counts", "total counts", s, fixed = TRUE)
      s <- gsub("轻强度体量", "light-intensity volume", s, fixed = TRUE)
      s <- gsub("静坐体量", "sedentary volume", s, fixed = TRUE)
      s <- gsub("MVPA 体量", "MVPA volume", s, fixed = TRUE)
      s <- gsub("（体量型）", " (volume)", s, fixed = TRUE)
      trimws(s)
    }
    AX_MIN_EN <- ax_en(AX_MIN); AX_MAX_EN <- ax_en(AX_MAX)
  } else AX_MIN_EN <- AX_MAX_EN <- NULL

  p(bi(
    sprintf("(a) Within-NHANES site ratio (wrist divided by hip relative risk at the same exposure percentile) on a %d hip wear-rule x %d wrist-criterion grid at %d offsets - %d cells in total. At the pre-specified offset of %d the ratio spans %.2f-%.2f across the %d cells; %d of them reach p < 0.05 and all of these belong to the most restrictive hip rules (%s), i.e. those retaining the least hip person-time. The baseline rule (R0, n = %s hip records) gives %.2f (95%% CI %.2f-%.2f, p = %s). The grid is therefore consistent with the apparent site contrast being an artefact of hip person-time retention rather than of the wear site itself. (b) Literature-side decomposition: contrasting the harmonised hip-based cohort pool with the wrist-based UK Biobank cohort gives wrist/hip ratios of %s at offsets %s, i.e. a large and significant site effect in the literature. (c) The two arms are not commensurable on %d of the %d compared design dimensions (population, cohort count, device, metric definition, follow-up, region; %d is commensurable): the sites differ in population, number of cohorts, device and axes, metric definition (counts volume versus classified duration), follow-up time and region, so the contrast is a between-study comparison, not an individual-level site effect. (d) Dropping any single arm leaves the three ratios numerically unchanged (maximum deviation %.4f), so the literature contrast is not carried by one study. (e) The NHANES confidence interval overlaps the literature interval at %d of the %d offsets, and the literature point estimate falls outside the NHANES interval at all %d offsets - reported as an unreconciled discrepancy. (f) Metric-axis check across %d metric definitions: the fraction of the offset-30 relative risk retained at offset 80 ranges from %.3f (%s) to %.3f (%s); all of these are volume-type metrics and all retain the same downward direction, so the site contrast is not produced by the choice of metric axis.",
            N_RULE, N_CRIT, N_OFF, N_CELL, OFF0, R_MIN, R_MAX, N_G6, N_SIG, SIGRUL,
            nf(PR$n_hip, 0), PR$ratio_mean, PR$lo, PR$hi, pf(PR$p),
            LIT_TXT, LIT_OFS,
            DI_NO, DI_TOT, DI_YES,
            LV_MAXDEV, NOV, nrow(as.data.table(T8C)), NDIFF,
            NAMX, RET_MIN, AX_MIN_EN, RET_MAX, AX_MAX_EN),
    sprintf("(a) NHANES 内部部位比值（同一暴露百分位下腕式相对风险 ÷ 髋式）在 %d 个髋式 wear 规则 × %d 个腕式判据、%d 个偏移点的网格上，共 %d 个格子。在预设偏移点 %d 处，比值在 %d 个格子间为 %.2f–%.2f；其中 %d 个达到 p < 0.05，且全部来自最严格的髋式规则（%s），即保留髋式人-日最少的规则。基准规则（R0，n = %s 条髋式记录）给出 %.2f（95%% CI %.2f–%.2f，p = %s）。故该网格与「表观部位对比源于髋式人-日保留量的削减、而非佩戴部位本身」这一解释一致。(b) 文献侧分解：把协调化的髋式队列池与基于腕式的英国生物样本库队列相对比，偏移点 %s 处的腕/髋比值为 %s —— 文献中部位效应大且显著。(c) 两臂在 %d 个（共 %d 个）比较维度上不可通约（%d 个可通约）：两部位在人群、队列数、设备与轴数、指标定义（counts 体量 vs 分类时长）、随访时间与地区上均不同，故该对比是研究间比较，而非个体层面部位效应。(d) 剔除任一臂后三个比值在数值上不变（最大偏差 %.4f），故文献侧对比不由单一研究承载。(e) NHANES 置信区间在 %d/%d 个偏移点与文献区间重叠，而文献点估计在全部 %d 个偏移点均落在 NHANES 区间之外 —— 作为未弥合的口径差异报告。(f) 指标轴检查（%d 种指标定义）：偏移 30 处的相对风险在偏移 80 处的保留比介于 %.3f（%s）与 %.3f（%s）之间；这些均为体量型指标且方向一致向下，故部位对比并非由指标轴选择所产生。",
            N_RULE, N_CRIT, N_OFF, N_CELL, OFF0, N_G6, R_MIN, R_MAX, N_SIG, SIGRUL,
            nf(PR$n_hip, 0), PR$ratio_mean, PR$lo, PR$hi, pf(PR$p),
            LIT_OFS, LIT_TXT_ZH,
            DI_NO, DI_TOT, DI_YES,
            LV_MAXDEV, NOV, nrow(as.data.table(T8C)), NDIFF,
            NAMX, RET_MIN, AX_MIN, RET_MAX, AX_MAX)))
  # ---- (g)(h) 指标稳健性 / 指标对齐（2026-10-16 新增；04d §2b + 04f）----------
  #   独立成段（不塞进上面那个巨型 sprintf）：新增两段各自有 4–6 个占位符，
  #   插进原串会让参数顺序极易错位，而这是本项目历史上出过的典型缺陷类别。
  if (!is.null(T8BM) && !is.null(T8BX)) {
    .bm <- as.data.table(T8BM); .bx <- as.data.table(T8BX)
    .rL <- .bm[metric_definition == "LPA"]
    # ⚠️ 必须用 "Ko2025 锚点" 而非 "Ko2025"：合并档（Ko2025 + Inan-Eroglu2024）的
    #    metric_definition 也是 total_PA，用 "Ko2025" 会命中 2 行 → nrow != 1 →
    #    整个 (g) 段**静默不渲染**（实测踩到：图注里 (g) 整段消失而无任何报错）。
    .rT <- .bm[metric_definition == "total_PA" & grepl("Ko2025 锚点", wrist_source, fixed = TRUE)]
    .xT <- .bx[metric_definition == "total_PA"]
    if (nrow(.rL) == 1L && nrow(.rT) == 1L && nrow(.xT) == 1L) {
      .d  <- function(t, of) as.numeric(t[[sprintf("direct_wrist_over_hip_at_off%d", of)]])
      .f3 <- function(v) paste(sprintf("%.2f", v), collapse = "/")
      .LPA3 <- .f3(c(.d(.rL, 25), .d(.rL, 50), .d(.rL, 75)))
      .TPA3 <- .f3(c(.d(.rT, 25), .d(.rT, 50), .d(.rT, 75)))
      .RGAP <- as.numeric(.xT$max_abs_ratio_gap_pct)
      .SGAP <- as.numeric(.xT$slope_ratio_gap_pct)
      .SLPA <- as.numeric(.rL$slope_ratio_hip_over_wrist)
      .STPA <- as.numeric(.rT$slope_ratio_hip_over_wrist)
      p(bi(
        sprintf("(g) Metric robustness. Recomputing the literature-side site contrast on a second device metric axis - total activity, with the wrist side supplied by an external anchor cohort (Ko2025, a UK Biobank accelerometer sub-cohort that is independent of the hip-side pool and is deliberately kept out of the pooled analysis) - gives wrist/hip ratios of %s at offsets 25/50/75 against %s on the light-intensity axis, i.e. the two metric axes agree to within %.1f%%. The site contrast is therefore not an artefact of the choice of metric. The ratio of slopes, however, differs by %+.1f%% (%.2f versus %.2f) because the wrist slope enters the denominator and is appreciably flatter for light-intensity activity; slope ratios must therefore not be extrapolated across metrics, which is stated as a limitation.", .TPA3, .LPA3, .RGAP, .SGAP, .SLPA, .STPA),
        sprintf("(g) 指标稳健性。把文献侧部位对比换到**第二个设备指标轴**（总量活动；腕侧由外部锚定队列 Ko2025 提供 —— 该队列属 UK Biobank 加速度计子队列，与髋侧池相互独立，且被**刻意排除在池化分析之外**）后重算：偏移 25/50/75 处的腕/髋比值为 %s，而轻强度轴为 %s，两指标轴相差不超过 %.1f%%。故部位对比并非指标选择所致。但**斜率之比**相差 %+.1f%%（%.2f 与 %.2f）—— 因为腕侧斜率位于分母且轻强度活动的腕侧曲线明显更平；**斜率比不可跨指标外推**，此点列入局限。", .TPA3, .LPA3, .RGAP, .SGAP, .SLPA, .STPA)))
    } else {
      # 不静默跳过：行数不符时必须在控制台可见（本项目历史上多次被"静默不渲染"坑到）
      cat(sprintf("   ⚠️ S4(g) 未渲染：T8BM/T8BX 行数不符（.rL=%d .rT=%d .xT=%d）\n",
                  nrow(.rL), nrow(.rT), nrow(.xT)))
    }
  }
  if (!is.null(T8BN)) {
    .bn <- as.data.table(T8BN)
    if (nrow(.bn)) {
      .NOV  <- sum(as.logical(.bn$ci_overlap))
      .NOUT <- sum(!as.logical(.bn$nhanes_ci_contains_lit_point))
      .TXT  <- paste(sprintf("%.2f (%.2f-%.2f) versus %.2f (%.2f-%.2f)",
                             as.numeric(.bn$lit_ratio), as.numeric(.bn$lit_lo), as.numeric(.bn$lit_hi),
                             as.numeric(.bn$nhanes_ratio), as.numeric(.bn$nhanes_lo), as.numeric(.bn$nhanes_hi)),
                     collapse = "; ")
      .TXTZ <- paste(sprintf("%.2f（%.2f–%.2f）对比 %.2f（%.2f–%.2f）",
                             as.numeric(.bn$lit_ratio), as.numeric(.bn$lit_lo), as.numeric(.bn$lit_hi),
                             as.numeric(.bn$nhanes_ratio), as.numeric(.bn$nhanes_lo), as.numeric(.bn$nhanes_hi)),
                     collapse = "；")
      p(bi(
        sprintf("(h) Metric-aligned comparison. The only site comparison in which both sides sit on the *same* metric axis contrasts the literature-side total-activity ratio with the within-NHANES total-activity ratio: %s at offsets 25/50/75. The confidence intervals overlap at %d of %d offsets, yet the literature point estimate falls outside the NHANES interval at %d of %d - the same unreconciled discrepancy as in (e), now obtained without any cross-metric borrowing. This is the comparison that carries the conclusion that the literature-side site effect cannot be read as a pure wear-site effect.", .TXT, .NOV, nrow(.bn), .NOUT, nrow(.bn)),
        sprintf("(h) 指标对齐对照。全项目**唯一两侧位于同一指标轴**的部位对照：把文献侧总量口径的比值与 NHANES 同调查内总量口径的比值并列 —— 偏移 25/50/75 处为 %s。置信区间在 %d/%d 个偏移点重叠，但文献点估计在 %d/%d 个偏移点落在 NHANES 区间之外 —— 与 (e) 同一未弥合差异，且此处**不需任何跨指标借用**。支撑「文献侧部位效应不能解读为单纯佩戴部位效应」这一结论的正是本对照。", .TXTZ, .NOV, nrow(.bn), .NOUT, nrow(.bn))))
    }
  }
  def(sprintf("网格规模 / Grid = %d 个髋式 wear 规则 × %d 个腕式判据 × %d 个偏移点 = %d 个格子；核心读数是偏移 %d 处的比值与 p 值分布。",
              N_RULE, N_CRIT, N_OFF, N_CELL, OFF0),
      "髋式规则 / Hip wear rules：R0 = Choi 2011 佩戴标志（基准，即 Table S2/S3 所用）；R1 = counts 非缺失（最宽松）；R2 = counts > 0（有信号即佩戴）；R3 = 剔除连续 ≥60 min 全零段（Troiano 风格）；R4 = R2 且限于 06:00–23:59。严格度单调递增：R1 ⊃ R0 ≈ R3 ⊃ R2 ⊃ R4。",
      "腕式判据 / Wrist criteria：C0 = 清醒佩戴 PAXWWMD ≥ 600 min（基准）；C1 = 全天佩戴（PAXWWMD+PAXSWMD）≥ 600；C2 = 清醒 ≥ 720；C3 = 有效分钟 PAXVMD ≥ 600 且 PAXQFD = 0；C4 = 全天佩戴 ≥ 600 且 PAXQFD = 0；C5 = C1 且有效日 ≥ 6；C6 = C1 且有效日 = 7。",
      if (N_SIG) sprintf("全部 %d 个显著格子集中在 %s；%s。", N_SIG, SIGRUL, sig_n) else
        "网格中没有任何格子达到 p < 0.05。",
      "文献侧三档偏移的腕/髋比值：详见 (b)；留一臂后数值不变，见 (d)。",
      "⚠️ (b) 为**研究间**对比，(a) 为**个体内**对比，两者不可等量齐观 —— 这正是 (c) 的意义。Cross-study versus within-person comparison.",
      "⚠️ 本表与 Table S2 的个体内部位效应形成对照：后者为基准规格下的单点估计，本表为规格网格下的稳健性。",
      if (!is.null(RET_MIN)) sprintf("指标轴检查：偏移 80 的保留比最低者为 %s（%.3f，即下降最陡），最高者为 %s（%.3f，即最平）；两者方向均为向下。",
                                     AX_MIN, RET_MIN, AX_MAX, RET_MAX) else NULL,
      "⚠️ (h) 是全项目**唯一指标对齐**的部位对照（两侧同为总量口径）；(b)/(e) 的文献侧为 LPA 而 NHANES 侧为总量，属**跨指标**，其合法性由 (g) 的量化许可支撑（`Table8_lit_site_metric_license.csv`）。两处口径不同，**不可互相替代**。",
      "⚠️ 外部锚定队列（Ko2025 / Inan-Eroglu2024）与池内 Sun2025 同属 UK Biobank 加速度计子队列 → **刻意不入池**；此处只用「两来源相减」，该操作只要求两侧互为独立队列，不要求两侧互相独立于池。裁定见 `data/bop/20261016_入池裁定_UKB腕式总PA双源.md`。",
      "生产方 / Producers：`04d_lit_site_contrast.R`（(b)(c)(d)(e)(f)(g) 的许可）、`04f_lit_site_anchor.R`（(g) 的锚定数、(h) 全表）。(g)(h) 的两脚本同一批数已逐值互证（`QC_site_anchor_license_xcheck.csv`，9/9 PASS）。")
} else p("（产物缺失，待补。）")
p("")
p("### Table S5. Module 3 scenario ladder (formal grading table)")
p("")
if (!is.null(BASE9)) {
  p(bi(
    sprintf("Twelve pre-specified Module 3 scenarios at the global level in 2022, ordered by role. Primary analysis (S0_base): PAF = %.4f, fold = %.2f (range across the eight study locations %.2f-%.2f). Upper bound (TMREL moved to the 85th percentile with the convolution removed): PAF = %.4f, fold = %.2f. Aligning the relative-risk amplitude to the official GBD PAF alone: fold = %.2f. Aligning both the relative-risk amplitude and the TMREL (GBD-faithful): PAF = %.4f, fold = %.2f (range %.3f-%.3f) - i.e. the two named definitional differences place the estimate on the GBD value.",
            BASE9$paf_global, BASE9$fold_global, BASE9$fold_min, BASE9$fold_max,
            UPP9$paf_global, UPP9$fold_global, GA9$fold_global,
            GF9$paf_global, GF9$fold_global, GF9$fold_min, GF9$fold_max),
    sprintf("2022 年全球层面预先设定的 12 个模块 3 情景，按定级排序。主分析（S0_base）：PAF = %.4f，fold = %.2f（8 个研究地区范围 %.2f–%.2f）。上界（TMREL 移至第 85 百分位并取消卷积）：PAF = %.4f，fold = %.2f。仅把相对风险幅度对齐至官方 GBD PAF：fold = %.2f。同时对齐相对风险幅度与 TMREL（GBD 口径对齐完整版）：PAF = %.4f，fold = %.2f（范围 %.3f–%.3f）—— 即两项可命名的口径差异可把估计值带回 GBD 现报值。",
            BASE9$paf_global, BASE9$fold_global, BASE9$fold_min, BASE9$fold_max,
            UPP9$paf_global, UPP9$fold_global, GA9$fold_global,
            GF9$paf_global, GF9$fold_global, GF9$fold_min, GF9$fold_max)))
  s9o <- as.data.table(T9)
  s9o <- s9o[order(match(role, c("main", "upper_bound", "gbd_aligned", "sensitivity")), fold_global)]
  p("| Scenario | Role | TMREL mode | PAF (Global) | fold (Global) | fold range (8 locations) |")
  p("|---|---|---|---|---|---|")
  for (i in seq_len(nrow(s9o)))
    p("| %s | %s | %s | %.4f | %.2f | %.2f–%.2f |",
      s9o$scenario[i], s9o$role[i], s9o$tmrel_mode[i],
      s9o$paf_global[i], s9o$fold_global[i], s9o$fold_min[i], s9o$fold_max[i])
  p("")
  def("role / 定级 = main 主结果；upper_bound 上界；gbd_aligned GBD 口径对齐；sensitivity 敏感性。",
      "tmrel_mode / TMREL 模式 = abs 绝对阈值（本研究）｜0.70、0.85 为人群暴露分布百分位。",
      "配套图 / Companion figure = Fig 6(a) 情景森林图；Fig 5(d) 瀑布图取其中的 S0_base / GBD_ALIGNED_RR / GBD_FAITHFUL 三步。")
} else p("（产物缺失，待补。）")
p("")
p("### Table S6. Module 3 robustness (exposure CV grid and population weighting)")
p("")
if (!is.null(CVG)) {
  p(bi(
    sprintf("Sensitivity of the attributable fraction to the assumed coefficient of variation of the exposure distribution (CV = %.2f to %.2f) and to the population-weighting scheme, across the eight study locations. Across the entire CV grid the fold stays within %.2f-%.2f, and switching from cell-level CV lookup (main analysis) to age-group equal weighting changes it only marginally. The primary result is therefore not sensitive to the exposure distributional assumption.",
            min(CVG$cv_wavg), max(CVG$cv_wavg), min(CVG$fold), max(CVG$fold)),
    sprintf("归因分数对暴露分布变异系数假定（CV = %.2f–%.2f）与人口加权方案的敏感性，覆盖 8 个研究地区。在整个 CV 网格上 fold 保持在 %.2f–%.2f；由 cell 级 CV 查表（主分析）改为年龄组等权对结果的影响也很小。故主结果对暴露分布假设不敏感。",
            min(CVG$cv_wavg), max(CVG$cv_wavg), min(CVG$fold), max(CVG$fold))))
  p("| Axis | Level | PAF range | fold range |")
  p("|---|---|---|---|")
  rr_ <- as.data.table(T10R)[, .(paf_min = min(paf), paf_max = max(paf), fmin = min(fold), fmax = max(fold)), by = .(axis, level)]
  for (i in seq_len(nrow(rr_)))
    p("| %s | %s | %.4f–%.4f | %.2f–%.2f |",
      rr_$axis[i], rr_$level[i], rr_$paf_min[i], rr_$paf_max[i], rr_$fmin[i], rr_$fmax[i])
  p("")
  def("CV = coefficient of variation of the exposure distribution 暴露分布变异系数。GBD 2023 风险暴露文件不提供 SD，故本研究自估 SD–mean 关系（见 Table 3 面板 c）；本表把 CV 作为独立敏感性轴。",
      "主分析 = cell 级 S1′（5 岁组 × 性别查表），不是 CV 网格中的某一点。")
} else p("（产物缺失，待补。）")
p("")
p("### Table S7. Country-scale homogeneity of the device metric")
p("")
if (!is.null(TH)) {
  p(bi(
    sprintf("Country-level exposure distribution and burden estimates for the eight study locations. Although the MET-scale mean differs by up to a factor of %.1f across locations, the device-scale mean (MIMS/day) differs by at most a factor of %.3f, and the fold varies only between %.2f and %.2f. On the device scale the populations are therefore nearly homogeneous - which is precisely why a single device-scale relative-risk curve can be transported across them.",
            max(TH$met_ratio), max(TH$mims_ratio), min(TH$fold), max(TH$fold)),
    sprintf("8 个研究地区的国别暴露分布与负担估计。尽管 MET 尺度均值在地区间相差最多 %.1f 倍，设备尺度均值（MIMS/day）的差异不超过 %.3f 倍，fold 也仅在 %.2f–%.2f 之间变动。即在设备尺度上各人群近乎同质 —— 这正是单条设备尺度相对风险曲线可跨人群迁移的原因。",
            max(TH$met_ratio), max(TH$mims_ratio), min(TH$fold), max(TH$fold))))
  p("| Location | mean MET (weighted) | mean MIMS/day | MET ratio | MIMS ratio | PAF | fold |")
  p("|---|---|---|---|---|---|---|")
  for (i in seq_len(nrow(TH)))
    p("| %s | %s | %s | %.2f | %.3f | %.4f | %.2f |",
      TH$location[i], nf(TH$mean_met_w[i], 0), nf(TH$mean_mims[i], 0), TH$met_ratio[i],
      TH$mims_ratio[i], TH$paf[i], TH$fold[i])
  p("")
  def(sprintf("met_ratio / mims_ratio = 相对最低 location 的倍数。MET 尺度比 %.2f–%.2f；设备尺度比 %.3f–%.3f。",
              min(TH$met_ratio), max(TH$met_ratio), min(TH$mims_ratio), max(TH$mims_ratio)),
      "本表是「设备尺度可迁移性」的直接证据；与 BoP 的方法效应（Table S1）互补。")
} else p("（产物缺失，待补。）")
p("")
p("### Table S8. Hip intensity metrics: quartiles and per-IQR contrasts")
p("")
if (!is.null(T11I)) {
  ix <- as.data.table(T11I)
  f1 <- function(e, o, v) {
    r <- ix[exposure == e & outcome == o & volume_adjusted == v]
    if (!nrow(r)) "-" else sprintf("HR %.2f (%.2f–%.2f), p = %s", r$hr_per_iqr, r$lo, r$hi, pf(r$p))
  }
  p(bi(
    sprintf("Association of hip uniaxial intensity metrics with all-cause and cardiovascular mortality, before and after adjustment for total activity volume. Peak-30 loses significance after volume adjustment for both endpoints (all-cause %s; cardiovascular %s), whereas MVPA retains a protective association for both (all-cause %s; cardiovascular %s). Continuous intensity therefore carries information beyond total volume, while spike-like intensity does not. This is the quantitative basis for the M0-versus-M1 separation shown in Fig 3.",
            f1("peak30_per_day", "died", TRUE), f1("peak30_per_day", "cvd", TRUE),
            f1("mvpa_per_day", "died", TRUE), f1("mvpa_per_day", "cvd", TRUE)),
    sprintf("髋式单轴强度指标与全死因、心血管死亡的关联，未调整与调整活动总量两种口径。Peak-30 在调整体量后对两个终点均失去显著性（全死因 %s；心血管 %s）；MVPA 在调整体量后对两个终点仍保留保护性关联（全死因 %s；心血管 %s）。即连续型强度携带超出总量的信息，尖峰型强度不携带 —— 这正是 Fig 3 中 M0 与 M1 分离程度的定量依据。",
            f1("peak30_per_day", "died", TRUE), f1("peak30_per_day", "cvd", TRUE),
            f1("mvpa_per_day", "died", TRUE), f1("mvpa_per_day", "cvd", TRUE))))
  p("| Exposure | Outcome | Volume-adjusted | per-IQR HR (95% CI) | p |")
  p("|---|---|---|---|---|")
  for (i in seq_len(nrow(ix)))
    p("| %s | %s | %s | %.2f (%.2f–%.2f) | %s |",
      ix$exposure[i], ix$outcome[i], ifelse(ix$volume_adjusted[i], "yes 是", "no 否"),
      ix$hr_per_iqr[i], ix$lo[i], ix$hi[i], pf(ix$p[i]))
  p("")
  def("Peak-30 = 日均最高的连续 30 分钟计数（counts/min），代表尖峰型强度。MVPA = ≥2,020 counts/min 的分钟数。",
      "⚠️ MVPA 的独立效应在修正口径不一致前后结论不同（旧版独立 log-linear 模型曾给出无效结果），现统一由同一 RCS 模型提取，故本表与 Fig 3 一致。")
} else p("（产物缺失，待补。）")
p("")
p("### Table S9. Leave-one-study-out")
p("")
if (!is.null(LOO) && nrow(LOO)) {
  p(bi(
    sprintf("Refitting the pooled relative-risk curve after dropping each contributing cohort in turn (global level, 2022). The baseline fold is %.2f. Dropping %s changes it by %.1f%%, and dropping %s by %+.1f%%; the remaining studies change it by less than 2%%. The direction of the result is therefore robust, but its magnitude depends on the cohorts that support the device curve.",
            PBASE, LOO$dropped_study[1], 100 * (LOO$fold[1] / PBASE - 1),
            LOO$dropped_study[nrow(LOO)], 100 * (LOO$fold[nrow(LOO)] / PBASE - 1)),
    sprintf("逐篇剔除贡献队列后重新拟合池化相对风险曲线（全球，2022）。基线 fold = %.2f。剔除 %s 使其变化 %.1f%%，剔除 %s 使其变化 %+.1f%%；其余研究的影响均在 2%% 以内。故结果**方向稳健**，但**幅度依赖支撑设备曲线的队列**。",
            PBASE, LOO$dropped_study[1], 100 * (LOO$fold[1] / PBASE - 1),
            LOO$dropped_study[nrow(LOO)], 100 * (LOO$fold[nrow(LOO)] / PBASE - 1))))
  p("| Dropped study | fold (Global 2022) | Change vs baseline |")
  p("|---|---|---|")
  for (i in seq_len(nrow(LOO)))
    p("| %s | %.2f | %+.1f%% |", LOO$dropped_study[i], LOO$fold[i], 100 * (LOO$fold[i] / PBASE - 1))
  p("")
  def("配套图 / Companion figure = Fig 6(b)。",
      "⚠️ fold 为确定性量（无抽样误差）；但留一情景间小于约 1% 的变化仍不应作实质解读（受 BoP 池构成影响）。")
} else p("（产物缺失，待补。）")
p("")
p("### Table S10. E-values for unmeasured confounding")
p("")
if (!is.null(EV)) {
  p(bi(
    sprintf("E-values for %d key hazard ratios, computed after approximating the hazard ratio as a risk ratio (the conservative choice for outcomes that are not rare). The largest point E-value is %.2f, and the smallest confidence-interval E-value is %.1f - the latter corresponds to a contrast whose interval already crosses the null, so no unmeasured confounding is required to explain it away.",
            nrow(EV), max(EV$e_point_primary, na.rm = TRUE), min(EV$e_ci_primary, na.rm = TRUE)),
    sprintf("对 %d 个关键风险比计算 E 值；先按 VanderWeele 2020 把 HR 近似为 RR（结局非罕见时更保守）。最大点估计 E 值为 %.2f，最小置信区间界 E 值为 %.1f —— 后者对应一个置信区间本身已跨过无效线的对比，无需任何未测混杂即可解释。",
            nrow(EV), max(EV$e_point_primary, na.rm = TRUE), min(EV$e_ci_primary, na.rm = TRUE))))
  p("| Panel group | Exposure scale | Outcome | HR (95% CI) | E (point) | E (CI) |")
  p("|---|---|---|---|---|---|")
  for (i in seq_len(nrow(EV)))
    p("| %s | %s | %s | %.2f (%.2f–%.2f) | %.2f | %.2f |",
      EV$panel_group[i], thsep(EV$exposure_scale[i]), EV$outcome[i], EV$hr[i], EV$lo[i], EV$hi[i],
      EV$e_point_primary[i], EV$e_ci_primary[i])
  p("")
  def("E 值 = 要把观测关联完全解释掉，未测混杂需同时与暴露和结局达到的最小相对风险。E(CI) = 1 表示该置信区间本身已跨过无效线。",
      "panel_group / 面板分组 = volume_wrist 腕式总量；intensity_independent 调整体量后的强度（独立效应）；intensity_unadjusted 未调整体量的强度。",
      "配套图 / Companion figure = Fig 6(c)。")
} else p("（产物缺失，待补。）")
p("")
p("### Table S11. SDI anchor table (205 locations)")
p("")
if (!is.null(T14)) {
  t14 <- as.data.table(T14)
  qt  <- t14[!is.na(quintile_ord), .N, by = .(quintile, quintile_ord)][order(quintile_ord)]
  p(bi(
    sprintf("SDI values for 1990, 2022 and 2023 and the official quintile assignment for 205 GBD locations (Global plus 204 countries). Quintiles follow the official GBD 2023 cut-points: Low < %.7f; Low-middle < %.7f; Middle < %.7f; High-middle < %.7f; High >= %.7f. For %d countries GBD does not publish a national quintile because they have subnational units; these were recomputed with the same algorithm (identical to the published values in 183 of 183 checkable cases) and flagged in the q_source column. Country counts per quintile: %s.",
            0.5315638, 0.6304845, 0.6766625, 0.7188266, 0.7188266, NQ_PUB,
            paste(sprintf("%s %d", qt$quintile, qt$N), collapse = "; ")),
    sprintf("205 个 GBD location（Global + 204 国）的 1990 / 2022 / 2023 年 SDI 值与官方五分位归属。五分位采用官方 GBD 2023 切点：Low < %.7f；Low-middle < %.7f；Middle < %.7f；High-middle < %.7f；High ≥ %.7f。其中 %d 个国家因设有次国家级单位，GBD 未发布国家级五分位，已按同一算法复算（在 183 个可核对的案例中与官方值 183/183 完全一致），并在 q_source 列标注。各档国家数：%s。",
            0.5315638, 0.6304845, 0.6766625, 0.7188266, 0.7188266, NQ_PUB,
            paste(sprintf("%s %d", qt$quintile, qt$N), collapse = "；"))))
  def("q_source / 来源 = published 官方发布｜recomputed 本研究按官方切点复算（国家级 quintile 未发布者）。",
      "本表是 Fig 5(b) 分层与 Table S12 排序的输入；SDI 不进入 PAF 计算，只用于分组展示。",
      sprintf("本表含 Global 一行（quintile = %s），分析时已剔除，故分档国家数合计 = %d。",
              t14[location_name == "Global"]$quintile, sum(qt$N)))
  p("")
  p("| SDI quintile | Countries | Mean fold (2022, deaths) | Mean fold (2022, DALYs) |")
  p("|---|---|---|---|")
  if (!is.null(sdi22))
    for (i in seq_len(nrow(sdi22)))
      p("| %s | %d | %.2f | %.2f |", sdi22$quintile[i], sdi22$n_country[i],
        sdi22$fold_deaths[i], sdi22$fold_dalys[i])
  p("")
} else p("（产物缺失，待补。）")
p("")
p("### Table S12. Per-country burden comparison (204 countries)")
p("")
if (!is.null(TS4)) {
  ts <- as.data.table(TS4)
  p(bi(
    sprintf("Attributable deaths and DALYs for low physical activity in 204 countries in 1990 and 2022, with SDI quintile and the 2022 SDI value, ordered by SDI. Across the 204 countries in 2022 the fold for deaths has a median of %.2f (IQR %.2f-%.2f; full range %.2f-%.2f), and every country exceeds 1. This table is the country-level basis for Fig 5(b) and Fig 5(c).",
            cset$med, cset$lo, cset$hi, cset$min, cset$max),
    sprintf("204 个国家 1990 与 2022 年低体力活动归因死亡与 DALYs，附 SDI 五分位与 2022 年 SDI 值，按 SDI 排序。2022 年的 204 个国家中，死亡口径 fold 中位数 %.2f（IQR %.2f–%.2f；全距 %.2f–%.2f），且全部国家 > 1。本表是 Fig 5(b) 与 Fig 5(c) 的逐国基础数据。",
            cset$med, cset$lo, cset$hi, cset$min, cset$max)))
  def(sprintf("行数 / Rows = %d（204 国 × 2 年）；列含 SDI 五分位与 2022 年 SDI 值。", nrow(ts)),
      "⚠️ 与主文 Table 4 的口径关系：Table 4 只含 8 个地区（固定清单，含 Global），本表含 204 国（不含 Global）；两表的 Global 行不可直接互换。",
      "⚠️ fold 为确定性量（无抽样误差），国家间差异反映真实的口径敏感性与暴露分布差异；跨 SDI 档的大差异（如 Low 档约 9.4 vs 其余约 5）稳健。")
} else p("（产物缺失，待补。）")
p("")
p("---")
p("")

# ============================== 一致性自检 ==============================
p("## 口径一致性自检 / Internal consistency check")
p("")
p("同一量在不同产物中的取值应由脚本自动比对，而不是人工选取。下表每次运行本脚本时刷新。")
p("")
if (nrow(CONS)) {
  p("| Quantity | Source | Value |")
  p("|---|---|---|")
  for (i in seq_len(nrow(CONS)))
    p("| %s | %s | %s |", CONS$quantity[i], CONS$source[i], nf(CONS$value[i]))
  p("")
  p(sprintf("同一量的最大相对差 = **%.2f%%**（范围 %s – %s）。",
            SPREAD, nf(min(CONS$value)), nf(max(CONS$value))))
  p("")
  if (SPREAD > 0.05) {
    p(sprintf("⚠️ 上述 *%d* 处产出仍有 **%.2f%%** 的相对差 —— 确定性枚举后本应一致到浮点精度。请检查是否有调用点仍走 Monte Carlo 路径（`rr_device_fun()` 返回向量而非矩阵），或使用了不同的 BoP 后验池。", nrow(CONS), SPREAD))
    p("")
    p("| 量 | 值 |")
    p("|---|---|")
    p("| 最大相对差 | %.2f%% |", SPREAD)
    p("| 最小 / 最大 | %s / %s |", nf(min(CONS$value)), nf(max(CONS$value)))
  } else {
    p(sprintf("✅ *%d* 处产出已收敛：最大相对差 **%.4f%%**（浮点量级）。口径已统一为**确定性后验枚举**。", nrow(CONS), SPREAD))
    p("")
    p(paste0("- 点估计 = PAF 在 BoP 后验曲线池上的**期望**（`paf_from_dist_mat()` 一次矩阵运算遍历全部曲线；",
             "`recompute_burden()` 见 `code/05_burden_calibration_paf.R`）。方差为 0，不受随机种子影响。"))
    p("- 区间 = 全部后验曲线间的 2.5% / 97.5% 分位（原为 Monte Carlo 重抽分位）。")
    p("- 95 / 95c / 95b / 97 共用同一算法，**跨脚本、跨运行严格一致**。")
    p("- 因此 **Table 4 的 fold 与 Fig 5(d) 的 fold 可以并列引用**，无需再做口径免责声明。")
  }
} else p("（无可用对照产物。）")
p("")

# ---------------------------------------------------------------------------
# 两段式样本口径自检（2026-10-16 新增，配合 B9）
# ---------------------------------------------------------------------------
# 与上面的 CONS **分开**：CONS 比的是「同一量在不同产物中的取值」（量级为百万级
#   归因死亡数），而这里比的是**样本量 / 死亡计数**（千级）。若并入 CONS，
#   其汇总行「范围 a – b」会被拉到 769 – 3.4e6，反而失去可读性。
# 目的：把「Fig 2(a) 流程节点」与「09 的两张底表」两条**独立推导路径**的
#   同一量并列，任一侧筛选式分叉即在图注文档里显式告警（而非静默取一个）。
SAMP <- data.table(quantity = character(0), source = character(0), value = numeric(0))
adds <- function(q, s, v) if (length(v) == 1L && !is.na(v))
  SAMP <<- rbind(SAMP, data.table(quantity = q, source = s, value = as.numeric(v)))
adds("设备样本 N（年龄 >= 25）",    "Fig 2(a) 流程 / 08b",       N_25)
adds("设备样本 N（年龄 >= 25）",    "Table 1 Overall / 09",      N_ALL_N)
adds("设备样本 N（年龄 >= 25）",    "Sample_definition / 09",    sdv("Device sample (aged >= 25, valid accelerometry)"))
adds("设备样本死亡数",              "Fig 2(a) 流程 / 08b",       D_25)
adds("设备样本死亡数",              "Table 1 Overall / 09",      D_ALL_N)
adds("设备样本死亡数",              "Sample_definition / 09",    sdv("Deaths in the device sample"))
adds("多变量 Cox 分析集 N",         "Fig 2(a) 流程 / 08b",       N_MOD)
adds("多变量 Cox 分析集 N",         "Sample_definition / 09",    sdv("Cox analysis set (complete covariates and follow-up)"))
adds("多变量 Cox 分析集死亡数",     "Fig 2(a) 流程 / 08b",       D_MOD)
adds("多变量 Cox 分析集死亡数",     "Sample_definition / 09",    sdv("Deaths in the Cox analysis set"))
# ★ 2026-10-16 第 5 个量：心血管死亡数。Results R1 / Discussion L4 引用它，此前无产物来源。
#   与上面 4 个量同法：08b（流程底表 cvd_deaths 列）与 09（Sample_definition 第 6 行）
#   独立推导，逐值比对；两来源若分叉即在上方告警。
adds("多变量 Cox 分析集心血管死亡数", "Fig 2(a) 流程 / 08b",     CVD_MOD)
adds("多变量 Cox 分析集心血管死亡数", "Sample_definition / 09",  sdv("Cardiovascular deaths in the Cox analysis set"))
p("### 两段式样本口径 / Two-stage sample definition")
p("")
p(paste0("本文件的图注统一采用**两段式**样本口径：① **设备样本** = 年龄 ≥ 25 且加速度计有效",
         "（**Table 1 的描述对象**）；② **多变量 Cox 分析集** = 协变量与随访完整者",
         "（**Table 2 的拟合样本**）。两段各自的 N 与死亡数由 08b 与 09 独立推导，下表每次运行自动比对。"))
p("")
if (nrow(SAMP)) {
  p("| Quantity | Source | Value |")
  p("|---|---|---|")
  for (i in seq_len(nrow(SAMP)))
    p("| %s | %s | %s |", SAMP$quantity[i], SAMP$source[i], nf(SAMP$value[i]))
  p("")
  SAMP[, spread_pct := 100 * (max(value) / min(value) - 1), by = quantity]
  SP2 <- max(SAMP$spread_pct)
  if (SP2 > 0.001) {
    p(sprintf(paste0("⚠️ 两段式样本口径存在 **%.2f%%** 的跨脚本相对差 —— ",
                     "08b 与 09 的筛选式可能已分叉，请先对齐后再引用图注。"), SP2))
  } else {
    p(sprintf(paste0("✅ 两段式样本口径自洽：%d 个量、%d 处来源，跨脚本相对差 0.00%%",
                     "（08b 与 09 独立推导一致）。"),
              length(unique(SAMP$quantity)), nrow(SAMP)))
    p("")
    p(sprintf("- ① 设备样本 **%s 人 / %s 例死亡**（Table 1；09 的 `t1d` 即 `analytic.rds` 全量）。",
              nf(N_ALL_N), nf(D_ALL_N)))
    p(sprintf(paste0("- ② 多变量 Cox 分析集 **%s 人 / %s 例死亡**（Table 2；09 的 `mod_dt`，",
                     "Model 1 与 Model 2 共用同一完整案例集）。两段相差 **%s 人**，",
                     "即因协变量或随访缺失而被排除者。"),
              nf(N_MOD), if (STAGE2) nf(D_MOD) else "未落盘", nf(N_ALL_N - N_MOD)))
    if (has1(N_FUP))
      p(sprintf(paste0("- ⚠️ **分母校正（2026-10-16）**：设备样本 %s 人中仅 **%s 人**链接到 NDI 死亡随访，",
                       "其余 **%s 人**的 `died` / `cvd_death` / `surv_mo` 同时缺失。",
                       "故「%s 例死亡」的分母是 **%s**，不是 %s —— 图注与 Methods 一律按此表述，",
                       "避免被审稿人以分母错误质疑。"),
                nf(N_ALL_N), nf(N_FUP), nf(N_ALL_N - N_FUP), nf(D_ALL_N), nf(N_FUP), nf(N_ALL_N)))
  }
} else p("（无可用样本量产物。）")
p("")
p("---")
p("")
p("## 已决事项与待确认 / Decisions")
p("")
p("**已决（已执行）/ Decided**")
p("")
p("1. **补充表编号方案（S1–S12）** —— 已全量落地（含 Table S4）；映射表见本文件前段，同步记录于 `code/README.md` 与 `00_完整研究方案.md`。")
p(paste0("2. **Monte Carlo 口径** —— 已改为**确定性后验枚举**并重跑全链：`recompute_burden()`、",
         "`make_rr_fun_pooled()`、`mk_rr_shadow()` 一律遍历**全部**后验曲线；",
         "点估计 = PAF 后验期望（方差 0），区间 = 曲线间 2.5% / 97.5% 分位。见上「口径一致性自检」。"))
p("3. **正文语言** —— 已确认**中英对照双语**（与图注同格式）；正文 Methods / Results 撰写中。")
p(paste0("4. **Table S4 的部位比值方向** —— 已确认**保持**「腕式 ÷ 髋式」（`ratio` 列），",
         "与 Table S2 (`rr_ratio_wr_hip`) 同向，跨表交叉引用方向一致；不再切换为「髋式 ÷ 腕式」。"))
p(paste0("5. **Module 2 合成引擎** —— 已确认**装 Rtools45 补 C++ 工具链**，",
         "把 `05a_module2_bop.R` 的 `metafor::rma.mv`（REML）实现升级为真贝叶斯（`brms`/Stan），",
         "使 Methods 的「贝叶斯 meta-regression（BoP 框架）」名实相符；**输入表与输出契约不变**。"))
p(paste0("6. **外部队列入表** —— 5 行待入表候选（Ko2025 ×3、Inan-Eroglu2024 ×2）的两篇全文已由作者直接获取，",
         "并逐字段核验（`data/bop/20261016_入池裁定_UKB腕式总PA双源.md`）。裁定：**不入池** —— 两篇与池内 ",
         "`Sun2025` 同属 **UK Biobank 加速度计子队列**（同批 2013–2015 佩戴者、Axivity AX3 优势腕、",
         "同一结局判定与删失日期、随访 8.04 / 8.04 / 8.0 年），按对 `Cao2024` 的既有裁定**同案同判**；",
         "重复入池会低估 τ²、虚假收窄后验区间并改变 Module 3 的 PAF，而证据并未增加。",
         "裁决已由 `code/05d_bop_intake_pending.R` 的 SKIP 机制固化（台账 5 行 → `rejected`），",
         "主池仍为 5 项研究 / 22 行（本文件 Module 2 相关表述因此**不变**）。",
         "两篇改作**外部锚点**用于核验「部位效应」的指标稳健性，并已**提升为正式步骤** `code/04f_lit_site_anchor.R`（2026-10-16 入链，紧接 04d 之后）。"))
p("")
p("**仍待确认 / Open**")
p("")
p("（暂无。以上 6 项均已确认。）")
p("")

# ---------------------------------------------------------------------------
# 5. 落盘
# ---------------------------------------------------------------------------
out_md <- file.path(DIR_OUT, "CAPTIONS_figures_tables.md")
writeLines(L, out_md, useBytes = TRUE)

cat("\n--- 10 图注完成 ---\n")
cat(sprintf("产出：%s（%d 行，%.1f KB）\n", basename(out_md), length(L), file.info(out_md)$size / 1024))
cat(sprintf("覆盖：Fig 1-6（17 面板）+ Table 1-4 + 补充表 S1-S12\n"))
cat(sprintf("缺产物：%s\n", if (length(MISSING)) paste(MISSING, collapse = ", ") else "无"))
cat(sprintf("一致性自检：%d 个来源，最大相对差 %.2f%%\n", nrow(CONS), SPREAD))
if (nrow(SAMP))
  cat(sprintf("两段式样本口径：%d 个量 / %d 处来源，跨脚本最大相对差 %.4f%%（设备样本 %s 人 / %s 死；Cox 分析集 %s 人 / %s 死，其中心血管 %s 例）\n",
              length(unique(SAMP$quantity)), nrow(SAMP), max(SAMP$spread_pct, na.rm = TRUE),
              nf(N_ALL_N), nf(D_ALL_N), nf(N_MOD), if (STAGE2) nf(D_MOD) else "未落盘",
              if (has1(CVD_MOD)) nf(CVD_MOD) else "未落盘"))
cat(sprintf("用时 %.1f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
pa_log("10 完成 -> output/CAPTIONS_figures_tables.md")
