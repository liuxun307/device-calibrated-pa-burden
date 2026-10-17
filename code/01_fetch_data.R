# =============================================================================
# 01_fetch_data.R  —  原始数据获取 · 校验 · 台账
#
# 职责（四件事，缺一不可）：
#   (1) 按外置清单下载 NHANES 原始 xpt + 官方 LMF 死亡链接文件（含重试）
#   (2) 为每个原始文件固化指纹（SHA-256 / MD5 + 字节数 + 源站 Last-Modified）
#       -> data/sources/checksums.csv   【这是"原始数据可复现"的锚点】
#   (3) 生成原始数据台账 -> data/RAW_INVENTORY.csv（投稿 Data Availability 用）
#   (4) 读入并缓存为 .rds，供 02/03 使用；GBD 手工数据做存在性与列名校验
#
# 重要事实（已核对于官方来源，勿凭记忆改写）：
#   * 公开版 LMF 是"按周期分文件"的，没有 2011-2014 合并文件：
#       NHANES_2011_2012_MORT_2019_PUBLIC.dat
#       NHANES_2013_2014_MORT_2019_PUBLIC.dat
#     写成 NHANES_2011_2014_... 会 404，并使整个死亡随访静默无数据。
#   * LMF 固定宽度布局（官方 R_ReadInProgramAllSurveys.R，NHANES 版）：
#       seqn c(1,6)  eligstat c(15,15)  mortstat c(16,16)  ucod_leading c(17,19)
#       diabetes c(20,20)  hyperten c(21,21)  permth_int c(43,45)  permth_exm c(46,48)
#   * 随访截止 2019-12-31 -> 2013-2014 周期实际随访仅约 5-6 年。
#
# 环境变量开关：
#   PARADIGM_A_ROOT               项目根（由 00_setup 处理）
#   PARADIGM_A_DOWNLOAD_HUGE=1    下载 PAXMIN（分钟级，数百 MB）；默认跳过
#   PARADIGM_A_REFRESH_MANIFEST=1 用脚本内置清单覆盖 data/sources/nhanes_files.csv
#   PARADIGM_A_OFFLINE=1          只校验/读入，不联网
# =============================================================================

# ---- 统一引导（勿改）--------------------------------------------------------
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
})
if (!isTRUE(getOption("PA_SETUP_DONE"))) {
  .ps <- NULL
  for (.c in c("00_setup.R",
               file.path(getwd(), "00_setup.R"),
               file.path(dirname(gsub("\\\\", "/", sub("^--file=", "",
                 grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))), "00_setup.R"))) {
    if (!is.null(.c) && nzchar(.c) && file.exists(.c)) { .ps <- normalizePath(.c); break }
  }
  if (is.null(.ps)) stop("未找到 00_setup.R：请 setwd() 到 code/ 目录，或设置 PARADIGM_A_ROOT")
  source(.ps); rm(.ps, .c)
}

suppressPackageStartupMessages({ library(data.table); library(haven) })

OFFLINE      <- nzchar(Sys.getenv("PARADIGM_A_OFFLINE", unset = ""))
GET_HUGE     <- nzchar(Sys.getenv("PARADIGM_A_DOWNLOAD_HUGE", unset = ""))
REFRESH_MF   <- nzchar(Sys.getenv("PARADIGM_A_REFRESH_MANIFEST", unset = ""))

pa_log("===== 01 原始数据获取 =====")

# =============================================================================
# Part 0. 原始数据清单（外置 CSV，可人工审阅/编辑）
# =============================================================================
MF_CSV <- file.path(DIR_SOURCES, "nhanes_files.csv")

nh_manifest_default <- function() {
  mk <- function(cycle, yyyy, comp, category, required, min_bytes, purpose) {
    data.table(cycle = cycle, year = yyyy, comp = comp, filename = sprintf("%s_%s.xpt", comp, cycle),
               url = sprintf("https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/%d/DataFiles/%s_%s.xpt", yyyy, comp, cycle),
               category = category, required = required, min_bytes = min_bytes, purpose = purpose)
  }
  LMFBASE <- "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/datalinkage/linked_mortality"
  # 注意：C/D 两周期（2003-2006）的 LMF 与 2011-2014 用**同一年代**的 2019 版公开链接文件
  # → 随访截止一致，髋式/腕式两条曲线的结局判定口径可比。required=FALSE：
  #    它们是「佩戴部位效应」子分析（01b/03b/04b）的输入，不阻塞主 LPA 归因流程。
  lmf <- data.table(
    cycle = c("G", "H", "C", "D"), year = c(2011L, 2013L, 2003L, 2005L), comp = "MORT",
    filename = paste0("NHANES_", c("2011_2012", "2013_2014", "2003_2004", "2005_2006"),
                      "_MORT_2019_PUBLIC.dat"),
    url = sprintf("%s/NHANES_%s_MORT_2019_PUBLIC.dat", LMFBASE,
                  c("2011_2012", "2013_2014", "2003_2004", "2005_2006")),
    category = "mortality", required = c(TRUE, TRUE, FALSE, FALSE), min_bytes = 200000L,
    purpose = "公开版链接死亡文件（随访至 2019-12-31）：MORTSTAT/UCOD_LEADING/PERMTH_EXM")
  prov <- data.table(
    cycle = "-", year = NA_integer_, comp = "READIN", filename = "R_ReadInProgramAllSurveys.R",
    url = sprintf("%s/R_ReadInProgramAllSurveys.R", LMFBASE),
    category = "provenance", required = TRUE, min_bytes = 3000L,
    purpose = "NCHS 官方 LMF 读入程序（固定宽度布局的权威依据）")

  rbindlist(list(
    mk("G", 2011L, "DEMO",    "core",     TRUE,  50000L, "人口学/4年权重 WTMEC4YR/设计变量 SDMVPSU,SDMVSTRA"),
    mk("H", 2013L, "DEMO",    "core",     TRUE,  50000L, "同上"),
    mk("G", 2011L, "PAXDAY",  "core",     TRUE, 100000L, "加速度计日级汇总：MIMS/day 主暴露"),
    mk("H", 2013L, "PAXDAY",  "core",     TRUE, 100000L, "同上"),
    mk("G", 2011L, "PAXHD",   "core",     TRUE,   3000L, "加速度计表头：佩戴/校准元数据"),
    mk("H", 2013L, "PAXHD",   "core",     TRUE,   3000L, "同上"),
    mk("G", 2011L, "PAQ",     "core",     TRUE,  50000L, "自报体力活动（GPAQ 结构）→ MET-min/wk 校准锚"),
    mk("H", 2013L, "PAQ",     "core",     TRUE,  50000L, "同上"),
    mk("G", 2011L, "BMX",     "covariate",TRUE, 100000L, "BMI / 腰围"),
    mk("H", 2013L, "BMX",     "covariate",TRUE, 100000L, "同上"),
    mk("G", 2011L, "BPX",     "covariate",TRUE,  50000L, "血压"),
    mk("H", 2013L, "BPX",     "covariate",TRUE,  50000L, "同上"),
    mk("G", 2011L, "BIOPRO",  "covariate",TRUE, 100000L, "生化（肌酐 LBXSCR 等）"),
    mk("H", 2013L, "BIOPRO",  "covariate",TRUE, 100000L, "同上"),
    mk("G", 2011L, "GHB",     "covariate",TRUE,  30000L, "糖化血红蛋白 LBXGH"),
    mk("H", 2013L, "GHB",     "covariate",TRUE,  30000L, "同上"),
    mk("G", 2011L, "HDL",     "covariate",TRUE,  30000L, "HDL-C LBDHDD"),
    mk("H", 2013L, "HDL",     "covariate",TRUE,  30000L, "同上"),
    mk("G", 2011L, "TRIGLY",  "covariate",TRUE,  30000L, "甘油三酯 LBXTR"),
    mk("H", 2013L, "TRIGLY",  "covariate",TRUE,  30000L, "同上"),
    mk("G", 2011L, "SMQ",     "covariate",TRUE,  30000L, "吸烟 SMQ020/SMQ040"),
    mk("H", 2013L, "SMQ",     "covariate",TRUE,  30000L, "同上"),
    mk("G", 2011L, "ALQ",     "covariate",TRUE,  30000L, "饮酒 ALQ101"),
    mk("H", 2013L, "ALQ",     "covariate",TRUE,  30000L, "同上"),
    mk("G", 2011L, "DIQ",     "covariate",TRUE,  30000L, "糖尿病 DIQ010"),
    mk("H", 2013L, "DIQ",     "covariate",TRUE,  30000L, "同上"),
    mk("G", 2011L, "MCQ",     "covariate",TRUE,  50000L, "合并症 MCQ160B/D/E/F"),
    mk("H", 2013L, "MCQ",     "covariate",TRUE,  50000L, "同上"),
    # --- 扩展 / 敏感性分析（非必需，失败不阻塞主流程） ---
    mk("G", 2011L, "PAXHR",   "extended", FALSE, 100000L, "小时级活动（日内节律）"),
    mk("H", 2013L, "PAXHR",   "extended", FALSE, 100000L, "同上"),
    mk("G", 2011L, "SLQ",     "extended", FALSE,  20000L, "睡眠（敏感性分析）"),
    mk("H", 2013L, "SLQ",     "extended", FALSE,  20000L, "同上"),
    mk("G", 2011L, "DPQ",     "extended", FALSE,  20000L, "抑郁（阴性对照）"),
    mk("H", 2013L, "DPQ",     "extended", FALSE,  20000L, "同上"),
    mk("G", 2011L, "HUQ",     "extended", FALSE,  20000L, "医疗利用"),
    mk("H", 2013L, "HUQ",     "extended", FALSE,  20000L, "同上"),
    mk("G", 2011L, "RXQ_RX",  "extended", FALSE, 100000L, "处方药（多重用药）"),
    mk("H", 2013L, "RXQ_RX",  "extended", FALSE, 100000L, "同上"),
    mk("G", 2011L, "DR1TOT",  "extended", FALSE,  50000L, "24h 膳食 recall（HEI-2015）"),
    mk("H", 2013L, "DR1TOT",  "extended", FALSE,  50000L, "同上"),
    # --- 大文件：默认不下载 ---
    mk("G", 2011L, "PAXMIN",  "huge",     FALSE,   1e8,   "分钟级 MIMS（仅 MVPA/Peak-30 需要，约 300+ MB）"),
    mk("H", 2013L, "PAXMIN",  "huge",     FALSE,   1e8,   "同上"),
    # --- 2003-2006（cycle C/D）：髋式 ActiGraph 7164 → 估计「佩戴部位效应」---------
    # 目的：与 2011-2014（腕式）用**同一套协变量定义**各估一条 PA→死亡 RR 曲线，
    #       两条曲线表达在同一「人群百分位」轴上 → 直接得到 hip vs wrist 的部位效应。
    # ⚠️ 分钟级活动计数本身不在本清单（PAXRAW_C/D 各 400+ MB，由 01b_fetch_pam_2003_2006.R
    #    单独下载并固化指纹）；这里只取构协变量所需的**小型**问卷/体检组件。
    # required = FALSE：仅服务部位效应子分析，不阻塞主 LPA 归因流程。
    mk("C", 2003L, "DEMO", "pam_site", FALSE, 2000000L, "2003-2004 人口学/权重 WTMEC2YR/设计变量（与 G/H 同口径）"),
    mk("D", 2005L, "DEMO", "pam_site", FALSE, 2000000L, "2005-2006 同上"),
    mk("C", 2003L, "BMX",  "pam_site", FALSE, 1000000L, "BMI / 腰围"),
    mk("D", 2005L, "BMX",  "pam_site", FALSE, 1000000L, "同上"),
    mk("C", 2003L, "BPX",  "pam_site", FALSE, 1000000L, "血压（sbp）"),
    mk("D", 2005L, "BPX",  "pam_site", FALSE, 1000000L, "同上"),
    mk("C", 2003L, "SMQ",  "pam_site", FALSE,  500000L, "吸烟 SMQ020/SMQ040"),
    mk("D", 2005L, "SMQ",  "pam_site", FALSE,  500000L, "同上"),
    mk("C", 2003L, "ALQ",  "pam_site", FALSE,  200000L, "饮酒 ALQ101"),
    mk("D", 2005L, "ALQ",  "pam_site", FALSE,  200000L, "同上"),
    mk("C", 2003L, "DIQ",  "pam_site", FALSE,  500000L, "糖尿病 DIQ010"),
    mk("D", 2005L, "DIQ",  "pam_site", FALSE,  500000L, "同上"),
    mk("C", 2003L, "MCQ",  "pam_site", FALSE, 2000000L, "合并症 MCQ160B/D/E/F"),
    mk("D", 2005L, "MCQ",  "pam_site", FALSE, 2000000L, "同上"),
    mk("C", 2003L, "PAQ",  "pam_site", FALSE,  500000L, "自报体力活动（GPAQ 结构）—— 供跨周期自报口径核对"),
    mk("D", 2005L, "PAQ",  "pam_site", FALSE,  500000L, "同上"),
    lmf, prov
  ))
}

if (!file.exists(MF_CSV) || REFRESH_MF) {
  mf <- nh_manifest_default()
  fwrite(mf, MF_CSV)
  pa_log("已写出数据清单 -> data/sources/nhanes_files.csv（", nrow(mf), " 行）")
} else {
  mf <- fread(MF_CSV)
  need_cols <- c("cycle", "year", "comp", "filename", "url", "required", "min_bytes")
  if (!all(need_cols %in% names(mf)))
    stop("data/sources/nhanes_files.csv 列不完整，请设置 PARADIGM_A_REFRESH_MANIFEST=1 重建")
  pa_log("读入数据清单：", nrow(mf), " 行（", MF_CSV, "）")
}

if (!GET_HUGE) mf <- mf[category != "huge"]

# =============================================================================
# Part 1. 下载（重试 + 跳过已存在）
# =============================================================================
pa_download <- function(url, dest, min_bytes, retries = 3L) {
  if (file.exists(dest) && file.size(dest) >= min_bytes) return("cached")
  if (OFFLINE) return("offline-skip")
  for (i in seq_len(retries)) {
    if (file.exists(dest) && file.size(dest) < min_bytes) unlink(dest)
    ok <- try(utils::download.file(url, dest, mode = "wb", quiet = TRUE,
                                   method = "libcurl"), silent = TRUE)
    if (!inherits(ok, "try-error") && file.exists(dest) &&
        file.size(dest) >= min_bytes) return("downloaded")
    if (i < retries) Sys.sleep(2^i)
  }
  "failed"
}

# 源站 Last-Modified（用于固化"数据版本"，失败不阻塞）
http_lastmod <- function(url) {
  if (OFFLINE) return(NA_character_)
  res <- try(system2("curl", c("-sI", "--max-time", "25", shQuote(url)),
                     stdout = TRUE, stderr = FALSE), silent = TRUE)
  if (inherits(res, "try-error") || !length(res)) return(NA_character_)
  hit <- grep("^last-modified:", res, ignore.case = TRUE, value = TRUE)
  if (!length(hit)) return(NA_character_)
  trimws(sub("^[^:]*:", "", hit[1]))
}

pa_log("--- 下载阶段（", nrow(mf), " 个文件，离线模式 = ", OFFLINE, "）---")
fetch_status <- character(nrow(mf))
for (i in seq_len(nrow(mf))) {
  dest <- file.path(DIR_RAW, mf$filename[i])
  fetch_status[i] <- pa_download(mf$url[i], dest, mf$min_bytes[i])
  if (fetch_status[i] == "failed")
    pa_log("下载失败: ", mf$filename[i], "  <- ", mf$url[i], level = "WARN")
}
mf[, fetch_status := fetch_status]
mf[, exists_now := file.exists(file.path(DIR_RAW, filename))]
mf[, size_bytes := fifelse(exists_now,
                           as.numeric(file.size(file.path(DIR_RAW, filename))),
                           NA_real_)]

n_ok   <- sum(mf$exists_now)
n_fail <- sum(mf$required & !mf$exists_now)
pa_log("下载完成：", n_ok, "/", nrow(mf), " 个文件在盘；必需文件缺失 ", n_fail, " 个")
if (n_fail > 0) {
  pa_log("以下必需文件缺失，02/03 会相应降级：", level = "WARN")
  for (f in mf[required == TRUE & exists_now == FALSE, filename]) pa_log("  - ", f, level = "WARN")
}

# =============================================================================
# Part 2. 指纹固化 —— 原始数据可复现的锚点
# =============================================================================
CHK_CSV <- file.path(DIR_SOURCES, "checksums.csv")
have_files <- mf[exists_now == TRUE]
if (nrow(have_files)) {
  new_hash <- pa_hash(file.path(DIR_RAW, have_files$filename), algo = "sha256")
  algo_used <- if (requireNamespace("digest", quietly = TRUE)) "sha256" else "md5"
  cur <- data.table(filename = have_files$filename, size_bytes = have_files$size_bytes,
                    hash_algo = algo_used, hash = new_hash,
                    url = have_files$url, last_modified_http = NA_character_)

  if (file.exists(CHK_CSV)) {
    old <- fread(CHK_CSV)
    merged <- merge(cur, old[, .(filename, hash_old = hash, algo_old = hash_algo)],
                    by = "filename", all.x = TRUE)
    drift <- merged[!is.na(hash_old) & hash_old != hash]
    if (nrow(drift)) {
      pa_log("!! 检出 ", nrow(drift), " 个文件指纹与首次固化不一致：", level = "WARN")
      for (k in seq_len(nrow(drift)))
        pa_log("   ", drift$filename[k], " : ", substr(drift$hash_old[k], 1, 12),
               " -> ", substr(drift$hash[k], 1, 12), level = "WARN")
      pa_log("   可能原因：CDC 更新了该文件。请评估是否影响结果，并在文档中记录。", level = "WARN")
    }
    # 保留首次固化记录，仅补充新文件
    cur <- rbind(old[!filename %in% cur$filename], cur, fill = TRUE)
  } else {
    pa_log("首次固化原始数据指纹（", algo_used, "），写入 data/sources/checksums.csv")
  }

  # 补记源站 Last-Modified（只对尚无记录的做，避免每次请求）
  need_lm <- cur[is.na(last_modified_http) | last_modified_http == ""]
  if (nrow(need_lm) && !OFFLINE) {
    for (k in seq_len(nrow(need_lm))) {
      lm <- http_lastmod(need_lm$url[k])
      if (!is.na(lm)) cur[filename == need_lm$filename[k], last_modified_http := lm]
    }
  }
  cur[, first_seen := ifelse(filename %in% (if (file.exists(CHK_CSV)) fread(CHK_CSV)$filename else character(0)),
                             "recorded-earlier", format(Sys.Date()))]
  setorder(cur, filename)
  fwrite(cur, CHK_CSV)
} else {
  cur <- data.table(filename = character(), size_bytes = integer(), hash_algo = character(),
                    hash = character(), url = character(), last_modified_http = character(),
                    first_seen = character())
  pa_log("警告：data/raw 下无任何文件，未能固化指纹（离线或下载失败）", level = "WARN")
}

# =============================================================================
# Part 3. 原始数据台账（投稿 Data Availability 支撑材料）
# =============================================================================
inv <- copy(mf[, .(cycle, year, comp, filename, category, required, purpose, url,
                   fetch_status, exists_now, size_bytes)])
inv <- merge(inv, cur[, .(filename, hash_algo, hash, last_modified_http)],
             by = "filename", all.x = TRUE)
inv[, retrieved_on := format(Sys.Date())]
setorder(inv, category, cycle, comp)
fwrite(inv, file.path(PA_ROOT, "data", "RAW_INVENTORY.csv"))
pa_log("原始数据台账 -> data/RAW_INVENTORY.csv")

# =============================================================================
# Part 4. 读入并缓存 .rds（供 02/03）
# =============================================================================
read_cache <- function(stem) {
  xpt <- file.path(DIR_RAW, paste0(stem, ".xpt"))
  if (!file.exists(xpt)) return(NULL)
  d <- as.data.table(haven::read_xpt(xpt))
  saveRDS(d, file.path(DIR_DERIV, paste0(stem, ".rds")))
  d
}

stems <- mf[exists_now == TRUE & grepl("\\.xpt$", filename)]$filename
stems <- sub("\\.xpt$", "", stems)
n_read <- 0L
for (s in stems) {
  x <- try(read_cache(s), silent = TRUE)
  if (inherits(x, "try-error")) { pa_log("读入失败（跳过）: ", s, level = "WARN") }
  else if (!is.null(x)) n_read <- n_read + 1L
}
pa_log("已缓存 rds：", n_read, " 个 -> data/derived/")

# ---- 4b. 死亡链接文件（固定宽度，按官方 layout 读取） ----------------------
read_lmf <- function(path) {
  if (!file.exists(path)) return(NULL)
  if (!requireNamespace("readr", quietly = TRUE)) {
    pa_log("未安装 readr，无法读 LMF（tidyverse 的一部分）", level = "WARN"); return(NULL)
  }
  d <- readr::read_fwf(
    file = path, col_types = "iiiiiiii",
    readr::fwf_cols(seqn         = c(1, 6),
                    eligstat     = c(15, 15),
                    mortstat     = c(16, 16),
                    ucod_leading = c(17, 19),
                    diabetes     = c(20, 20),
                    hyperten     = c(21, 21),
                    permth_int   = c(43, 45),
                    permth_exm   = c(46, 48)),
    na = c("", "."))
  setDT(d); setnames(d, toupper(names(d)))
  d
}

lmf_files <- mf[category == "mortality" & exists_now == TRUE, filename]

# 版式说明：NCHS 官方读入程序 R_ReadInProgramAllSurveys.R 对
# NHANES_<SURVEY>_MORT_2019_PUBLIC.dat 给出的是**所有周期通用的单一固定宽度模板**
# （seqn 1-6, eligstat 15, mortstat 16, ucod 17-19, dm 20, htn 21, permth_int 43-45,
#   permth_exm 46-48）→ 2003-2006 的 LMF 可直接用同一个 read_lmf() 解析，无需另写。
#
# ⚠️ 必须按周期分流保存：若把四个周期混进同一个 rds，主分析产物
#    MORT_2011_2014.rds 就会混入 2003-2006 的行（SEQN 全局唯一，不会误配，
#    但产物名与内容不再对应，且后续 98 指纹核对会被无谓扰动）。
CYCLE_MAP <- c("2011_2012" = "G", "2013_2014" = "H",
               "2003_2004" = "C", "2005_2006" = "D")
LMF_GROUPS <- list(
  MORT_2011_2014 = c("2011_2012", "2013_2014"),
  MORT_2003_2006 = c("2003_2004", "2005_2006"))

N_LMF <- 0L   # LMF 总行数（跨两个分组累加，供 Part 6 校验报告使用）
for (gname in names(LMF_GROUPS)) {
  yrs <- LMF_GROUPS[[gname]]
  fs  <- lmf_files[vapply(lmf_files, function(f) any(startsWith(f, paste0("NHANES_", yrs))), logical(1))]
  if (!length(fs)) { pa_log("LMF 分组 ", gname, "：无文件（跳过）", level = "WARN"); next }
  dts <- rbindlist(lapply(file.path(DIR_RAW, fs), function(p) {
    d <- read_lmf(p)
    if (!is.null(d)) d[, source_file := basename(p)]
    d
  }), use.names = TRUE, fill = TRUE)
  if (!nrow(dts)) { pa_log("LMF 分组 ", gname, "：解析为空", level = "WARN"); next }
  dts[, cycle := CYCLE_MAP[sub("^NHANES_([0-9_]+)_MORT.*$", "\\1", source_file)]]
  saveRDS(dts, file.path(DIR_DERIV, paste0(gname, ".rds")))
  N_LMF <- N_LMF + nrow(dts)
  pa_log("LMF [", gname, "] 已合并：", nrow(dts), " 行，符合资格者 ",
         sum(dts$ELIGSTAT %in% c(1, NA), na.rm = TRUE),
         "；死亡 ", sum(dts$MORTSTAT == 1, na.rm = TRUE),
         "（周期 ", paste(sort(unique(dts$cycle)), collapse = ","), "）",
         " -> data/derived/", gname, ".rds")
}
if (!any(grepl("^MORT_", list.files(DIR_DERIV))))
  pa_log("未读到任何 LMF 文件：死亡随访将为空，请检查 data/raw/", level = "WARN")

# =============================================================================
# Part 5. GBD 2023 手工数据 —— 存在性与列名校验
# =============================================================================
# GBD 结果无法脚本化获取：GHDx 需要注册并接受使用条款。因此本方案的做法是
# 把"获取步骤"当作数据来源的一部分显式记录，并对文件本体做严格校验。
gbd_files <- list.files(DIR_GBD, pattern = "\\.csv$", full.names = TRUE)
if (length(gbd_files)) {
  for (f in gbd_files) {
    d <- try(fread(f, nrows = 5), silent = TRUE)
    if (inherits(d, "try-error")) { pa_log("GBD 文件读取失败: ", basename(f), level = "WARN"); next }
    pa_log("GBD 文件 ", basename(f), " 列数 ", ncol(d), "：", paste(head(names(d), 8), collapse = ", "),
           if (ncol(d) > 8) " ..." else "")
  }
  gbd_inv <- data.table(file = basename(gbd_files),
                        size_bytes = file.size(gbd_files),
                        hash_algo = "sha256",
                        hash = pa_hash(gbd_files, algo = "sha256"))
  fwrite(gbd_inv, file.path(DIR_SOURCES, "gbd_checksums.csv"))
  pa_log("GBD 数据指纹 -> data/sources/gbd_checksums.csv")
} else {
  pa_log("data/gbd/ 为空：Module 3（PAF 重算）无法运行。", level = "WARN")
  pa_log("  获取步骤见 data/README.md 第 3 节；文件放入 data/gbd/ 后重跑本脚本即可。", level = "WARN")
}

# =============================================================================
# Part 6. 本步校验报告
# =============================================================================
rep <- data.table(
  item = c("清单文件总数", "在盘文件数", "必需文件缺失数", "已缓存 rds 数",
           "LMF 行数", "GBD CSV 数", "指纹算法", "离线模式", "含大文件"),
  value = c(nrow(mf), n_ok, n_fail, n_read, N_LMF, length(gbd_files),
            if (requireNamespace("digest", quietly = TRUE)) "sha256" else "md5",
            OFFLINE, GET_HUGE))
fwrite(rep, file.path(DIR_OUT, "QC_01_fetch_report.csv"))
print(rep)

pa_log("01 完成：原始数据 -> data/raw/ ；缓存 -> data/derived/ ；台账 -> data/RAW_INVENTORY.csv")
