# =============================================================================
# 03_exposure_merge_survival.R
# 构建分析数据集：暴露指标 + 自报 MET-min（校准用）+ 协变量 + 死亡结局
# GPAQ 自报 MET-min/周 标准算法（NHANES PAQ 为 GPAQ 结构）：
#   Vigorous work   = 8 MET x min/day x days/week   (PAQ605/610 -> PAD615)
#   Moderate work   = 4 MET x ...                   (PAQ620/625 -> PAD630)
#   Transport       = 4 MET x ...                   (PAQ635/640 -> PAD645)
#   Vigorous leisure= 8 MET x ...                   (PAQ650/655 -> PAD660)
#   Moderate leisure= 4 MET x ...                   (PAQ665/670 -> PAD675)
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
  library(data.table); library(tidyverse); library(haven)
})
# ROOT / DIR_RAW / DIR_DERIV 由 00_setup.R 统一提供

rd <- function(f) { p <- file.path(DIR_DERIV, paste0(f, ".rds")); if (file.exists(p)) readRDS(p) else NULL }

# ---------------------------- 1. 人口学 + 权重 ------------------------------
demo <- rbindlist(list(rd("DEMO_G"), rd("DEMO_H")), use.names = TRUE, fill = TRUE)
demo <- demo[, .(SEQN, RIDAGEYR, RIAGENDR, RIDRETH3, DMDEDUC2, INDFMPIR,
                 WTMEC2YR, SDMVPSU, SDMVSTRA)]
demo[, WTMEC4YR := WTMEC2YR / 2]           # 2011-2014 合并，4 年权重

# ---------------------------- 2. 加速度计暴露 ------------------------------
accel <- rd("accel_daily")

# （可选）分钟级指标：MVPA / Peak-30，由 02 脚本产出
# 注意：变量名不要用 peak30，避免在全局环境留下残留对象而干扰后续脚本的按列筛选
peak30_dt <- {
  p <- file.path(DIR_DERIV, "peak30.rds")
  if (file.exists(p)) { x <- readRDS(p); x[, .(peak30 = mean(peak30, na.rm = TRUE)), by = SEQN] } else NULL
}

# ---------------------------- 3. 自报体力活动（PAQ, GPAQ 计分） -------------
paq <- rbindlist(list(rd("PAQ_G"), rd("PAQ_H")), use.names = TRUE, fill = TRUE)

# 数值化辅助：把 "7777"(拒绝)/"9999"(不知道) 等特殊码置 NA
num_clean <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x[x %in% c(7777, 9999, 777, 999)] <- NA
  x
}
for (v in intersect(c("PAQ605","PAQ610","PAD615","PAQ620","PAQ625","PAD630",
                      "PAQ635","PAQ640","PAD645","PAQ650","PAQ655","PAD660",
                      "PAQ665","PAQ670","PAD675","PAD680"), names(paq))) {
  paq[, (v) := num_clean(get(v))]
}

paq[, `:=`(
  w_vig   = fifelse(!is.na(PAQ605) & PAQ605 == 1, 8 * tidyr::replace_na(PAD615, 0) * tidyr::replace_na(PAQ610, 0), 0),
  w_mod   = fifelse(!is.na(PAQ620) & PAQ620 == 1, 4 * tidyr::replace_na(PAD630, 0) * tidyr::replace_na(PAQ625, 0), 0),
  t_trans = fifelse(!is.na(PAQ635) & PAQ635 == 1, 4 * tidyr::replace_na(PAD645, 0) * tidyr::replace_na(PAQ640, 0), 0),
  l_vig   = fifelse(!is.na(PAQ650) & PAQ650 == 1, 8 * tidyr::replace_na(PAD660, 0) * tidyr::replace_na(PAQ655, 0), 0),
  l_mod   = fifelse(!is.na(PAQ665) & PAQ665 == 1, 4 * tidyr::replace_na(PAD675, 0) * tidyr::replace_na(PAQ670, 0), 0)
)]
paq[, met_min_wk := w_vig + w_mod + t_trans + l_vig + l_mod]     # 自报 MET-min/周
paq[, sedentary_min_day := PAD680]
paq_sr <- paq[, .(SEQN, met_min_wk, sedentary_min_day)]

# GBD 分层（用于交叉表与校准）：inactive<600, low 600-3999, mod 4000-7999, high>=8000
paq_sr[, lpa_gbd_cat := cut(met_min_wk, breaks = c(-Inf, 600, 4000, 8000, Inf),
                            labels = c("inactive","low","moderate","high"), right = FALSE)]

# ---------------------------- 4. 协变量 -------------------------------------
bmx <- rbindlist(list(rd("BMX_G"), rd("BMX_H")), use.names = TRUE, fill = TRUE)[
  , .(SEQN, BMXBMI, BMXWAIST)]

bpx_raw <- rbindlist(list(rd("BPX_G"), rd("BPX_H")), use.names = TRUE, fill = TRUE)
bpx <- bpx_raw[, .(SEQN,
  sbp = rowMeans(.SD, na.rm = TRUE)), .SDcols = intersect(c("BPXSY1","BPXSY2","BPXSY3","BPXSY4"), names(bpx_raw))]
bpx[is.nan(sbp), sbp := NA_real_]

biopro <- rbindlist(list(rd("BIOPRO_G"), rd("BIOPRO_H")), use.names = TRUE, fill = TRUE)[, .(SEQN, LBXSCR)]
ghb    <- rbindlist(list(rd("GHB_G"),    rd("GHB_H")),    use.names = TRUE, fill = TRUE)[, .(SEQN, LBXGH)]
hdl    <- rbindlist(list(rd("HDL_G"),    rd("HDL_H")),    use.names = TRUE, fill = TRUE)[, .(SEQN, LBDHDD)]
trigly <- rbindlist(list(rd("TRIGLY_G"), rd("TRIGLY_H")), use.names = TRUE, fill = TRUE)[, .(SEQN, LBXTR)]

smq <- rbindlist(list(rd("SMQ_G"), rd("SMQ_H")), use.names = TRUE, fill = TRUE)[, .(SEQN, SMQ020, SMQ040)]
alq <- rbindlist(list(rd("ALQ_G"), rd("ALQ_H")), use.names = TRUE, fill = TRUE)[, .(SEQN, ALQ101)]
diq <- rbindlist(list(rd("DIQ_G"), rd("DIQ_H")), use.names = TRUE, fill = TRUE)[, .(SEQN, DIQ010)]
mcq <- rbindlist(list(rd("MCQ_G"), rd("MCQ_H")), use.names = TRUE, fill = TRUE)[
  , .(SEQN, MCQ160B, MCQ160D, MCQ160E, MCQ160F)]   # CHF / 卒中 / 心绞痛 / 心梗

# ---------------------------- 5. 死亡结局 -----------------------------------
mort <- rd("MORT_2011_2014")
if (!is.null(mort)) {
  setDT(mort)
  # 官方字段：ELIGSTAT, MORTSTAT, UCOD_LEADING, PERMTH_INT, PERMTH_EXM
  keep <- intersect(c("SEQN","ELIGSTAT","MORTSTAT","UCOD_LEADING","PERMTH_INT","PERMTH_EXM",
                      "DIABETES","HYPERTEN"), names(mort))
  mort <- mort[, ..keep]
  mort <- mort[is.na(ELIGSTAT) | ELIGSTAT == 1]    # 仅保留符合链接资格者
  # UCOD_LEADING 编码 —— 已核对 NCHS 官方读入程序 R_ReadInProgramAllSurveys.R（NHANES 版）：
  #   1 = Diseases of heart (I00-I09, I11, I13, I20-I51)
  #   2 = Malignant neoplasms         3 = Chronic lower respiratory diseases
  #   4 = Accidents                   5 = Cerebrovascular diseases (I60-I69)
  #   6 = Alzheimer's                 7 = Diabetes mellitus
  #   8 = Influenza and pneumonia     9 = Nephritis / nephrotic syndrome
  #  10 = All other causes (residual)
  # !! 这是 NCHS 的粗分类，无法区分 IHD 与缺血性卒中。故本方案的心血管次要结局
  #    只能定义为「心脏病 + 脑血管病」(1 或 5)，投稿时须在局限部分如实写明。
  mort[, `:=`(
    died      = fifelse(MORTSTAT == 1, 1L, 0L),
    surv_mo   = as.numeric(PERMTH_EXM),           # 时间尺度：自 MEC 检查起月数
    cvd_death = fifelse(MORTSTAT == 1 & UCOD_LEADING %in% c(1L, 5L), 1L, 0L)
  )]
}

# ---------------------------- 6. 合并分析集 ---------------------------------
# 以加速度计有效样本为主表（内连接）
# 注意：01 在文件缺失时会返回 NULL，必须先剔除，否则 merge 会报错
parts <- list(accel, demo, paq_sr, bmx, bpx, biopro, ghb, hdl, trigly,
              smq, alq, diq, mcq, mort, peak30_dt)
parts <- Filter(Negate(is.null), parts)

adm <- Reduce(function(a, b) merge(a, b, by = "SEQN", all.x = TRUE), parts)

# 年龄 >= 25（与 GBD LPA 覆盖一致）
adm <- adm[RIDAGEYR >= 25]

# 派生协变量
adm[, `:=`(
  age = RIDAGEYR,
  female = fifelse(RIAGENDR == 2, 1L, 0L),
  race = factor(RIDRETH3),
  educ = { e <- DMDEDUC2; e[e %in% c(7, 9)] <- NA; factor(e) },   # 7=拒答 9=不知道 -> NA（否则近零方差哑变量致 svycoxph 奇异）
  pir  = INDFMPIR,
  bmi  = BMXBMI,
  cur_smoke = fifelse(!is.na(SMQ020) & SMQ020 == 1 & !is.na(SMQ040) & SMQ040 %in% c(1,2), 1L, 0L),
  drink_any = fifelse(!is.na(ALQ101) & ALQ101 == 1, 1L, 0L),
  diabetes  = fifelse(!is.na(DIQ010) & DIQ010 == 1, 1L, 0L),
  cvd_hx    = fifelse(rowSums(.SD == 1, na.rm = TRUE) > 0, 1L, 0L)
), .SDcols = intersect(c("MCQ160B","MCQ160D","MCQ160E","MCQ160F"), names(adm))]

# 暴露分层（按 MIMS/day 四分位，用于 Table 1 与分类模型）
adm[, mims_q4 := cut(mims_per_day,
                     breaks = quantile(mims_per_day, probs = 0:4/4, na.rm = TRUE),
                     include.lowest = TRUE, labels = paste0("Q", 1:4))]

saveRDS(adm, file.path(DIR_DERIV, "analytic.rds"))

# ---------------------------- 7. 描述与交叉表（Fig 2 素材） -----------------
cat("分析集人数:", nrow(adm), " 死亡:", sum(adm$died, na.rm = TRUE), "\n")
ct <- adm[!is.na(lpa_gbd_cat) & !is.na(mims_q4), .N, by = .(sr = lpa_gbd_cat, dev = mims_q4)]
fwrite(ct, file.path(DIR_OUT, "reported_vs_device_crosstab.csv"))

# 自报"达指南"(>=600 MET-min/wk) vs 设备活动量四分位 —— 直接展示自报高估
message("03 完成 -> data/derived/analytic.rds")
