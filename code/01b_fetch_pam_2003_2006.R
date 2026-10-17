# =============================================================================
# 01b_fetch_pam_2003_2006.R
# 取数：NHANES 2003-2006 Physical Activity Monitor（髋式 ActiGraph 7164）
# -----------------------------------------------------------------------------
# 为什么需要这一批数据（目的：估计**佩戴部位效应**）
#   Module 2 的池化曲线里，总量指标（total_PA）只有 device_hip / device_mixed 来源，
#   而本研究的暴露侧（NHANES 2011-2014 腕式 GT3X+，MIMS/day）与 GBD 暴露侧都是腕式。
#   要直接估计 hip → wrist 的可迁移性，最干净的做法是：
#     用**同一个国家、同一调查体系、同一套处理口径**的两个周期各估一条 PA→死亡 RR 曲线
#       · 2003-2006：髋式 ActiGraph 7164，单位 counts/min（本脚本）
#       · 2011-2014：腕式 GT3X+，单位 MIMS（既有 02-04 已做）
#   两者单位不同 → **不比较暴露绝对值**，而是各自表达在「本人群百分位偏移轴」上，
#   部位效应恰好落在 BoP 元回归既有的 wear_site 协变量里。
#
# 取什么（两类输入，共 12 个文件）
#   A. 原始下载件（权威来源，SHA-256 固化）—— 2 个 ZIP
#        PAXRAW_C.zip (2003-2004, 427,543,657 B)  → 内含 paxraw_c.xpt (SEQN,PAXSTAT,PAXCAL,
#        PAXRAW_D.zip (2005-2006, 470,990,068 B)     PAXDAY,PAXN,PAXHOUR,PAXMINUT,PAXINTEN[,PAXSTEP])
#        ⚠️ CDC 已改版：必须用 /Nchs/Data/Nhanes/Public/<year>/DataFiles/ 新路径。
#          旧式 /Nchs/Nhanes/<cycle>/ 现返回 HTML（Content-Length 恒为 20905 字节），
#          2026-10-12 实测踩过这个坑。
#
#   B. rnhanesdata 参考数据集（外部衍生输入，用其已同行评议的清洗结果）
#        github.com/oslerinhealth/rnhanesdata  → data/*.rda（合计约 85 MB）
#        · PAXINTEN_C/D  1440+ 格式分钟活动计数（= process_accel() 产物）
#        · Flags_C/D     wear/non-wear 标志（= process_flags() 产物）
#        · Covariate_C/D 人口学/生活方式/合并症协变量
#        · Mortality_2011/2015_C/D  NDI 死亡链接（2015 版随访更长，主用）
#        方法学依据：Leroux et al. 2019（PMC7012355）；上游原始数据仍由 A 提供，
#        本项目另跑 01c 做「自读原始 xpt vs 参考数据」的一致性核验。
#
# 输出
#   data/raw/pam_2003_2006/PAXRAW_C.zip, PAXRAW_D.zip        原始下载件（只读）
#   data/raw/rnhanesdata_ref/*.rda                           参考数据集（只读）
#   data/scratch/pam_extracted/paxraw_c.xpt, paxraw_d.xpt    解压件（可由 ZIP 再生）
#   data/sources/checksums.csv                               追加 12 条指纹（幂等）
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
suppressPackageStartupMessages({ library(data.table) })
pa_log("===== 01b 取数：NHANES 2003-2006 PAM（髋式） =====")

# ---- 路径 ---------------------------------------------------------------------
DIR_PAM    <- file.path(DIR_RAW, "pam_2003_2006")
DIR_RNH    <- file.path(DIR_RAW, "rnhanesdata_ref")
DIR_SCRATCH<- file.path(PA_ROOT, "data", "scratch", "pam_extracted")
for (d in c(DIR_PAM, DIR_RNH, DIR_SCRATCH)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

# ---- 清单 ---------------------------------------------------------------------
PAM_BASE <- "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public"
# ⚠️ 下载源：raw.githubusercontent.com 本机实测仅 18–46 KB/s（85 MB 要 40+ 分钟），
#    gh-proxy.com 镜像实测 313 KB/s（约 17×）。故镜像优先、原始源兜底（见 url_alt）。
RNH_MIRROR <- "https://gh-proxy.com/https://raw.githubusercontent.com/oslerinhealth/rnhanesdata/master/data"
RNH_RAW    <- "https://raw.githubusercontent.com/oslerinhealth/rnhanesdata/master/data"
RNH_BASE   <- RNH_MIRROR

FILES <- rbindlist(list(
  data.table(
    subdir = "pam_2003_2006", fname = "PAXRAW_C.zip",
    url    = paste0(PAM_BASE, "/2003/DataFiles/PAXRAW_C.zip"),
    expect = 427543657,
    note   = "NHANES 2003-2004 髋式 ActiGraph 7164 分钟级 counts（原始下载件）"),
  data.table(
    subdir = "pam_2003_2006", fname = "PAXRAW_D.zip",
    url    = paste0(PAM_BASE, "/2005/DataFiles/PAXRAW_D.zip"),
    expect = 470990068,
    note   = "NHANES 2005-2006 髋式 ActiGraph 7164 分钟级 counts（原始下载件）"),
  data.table(
    subdir = "rnhanesdata_ref", fname = "PAXINTEN_C.rda",
    url    = paste0(RNH_BASE, "/PAXINTEN_C.rda"), expect = 42829304,
    note   = "1440+ 格式分钟活动计数（cycle C）"),
  data.table(
    subdir = "rnhanesdata_ref", fname = "PAXINTEN_D.rda",
    url    = paste0(RNH_BASE, "/PAXINTEN_D.rda"), expect = 44618520,
    note   = "1440+ 格式分钟活动计数（cycle D）"),
  data.table(
    subdir = "rnhanesdata_ref", fname = "Flags_C.rda",
    url    = paste0(RNH_BASE, "/Flags_C.rda"), expect = 564580,
    note   = "wear/non-wear 标志（cycle C）"),
  data.table(
    subdir = "rnhanesdata_ref", fname = "Flags_D.rda",
    url    = paste0(RNH_BASE, "/Flags_D.rda"), expect = 585728,
    note   = "wear/non-wear 标志（cycle D）"),
  data.table(
    subdir = "rnhanesdata_ref", fname = "Covariate_C.rda",
    url    = paste0(RNH_BASE, "/Covariate_C.rda"), expect = 176236,
    note   = "协变量（cycle C）"),
  data.table(
    subdir = "rnhanesdata_ref", fname = "Covariate_D.rda",
    url    = paste0(RNH_BASE, "/Covariate_D.rda"), expect = 173892,
    note   = "协变量（cycle D）"),
  data.table(
    subdir = "rnhanesdata_ref", fname = "Mortality_2011_C.rda",
    url    = paste0(RNH_BASE, "/Mortality_2011_C.rda"), expect = 27452,
    note   = "NDI 死亡链接，随访至 2011（cycle C）"),
  data.table(
    subdir = "rnhanesdata_ref", fname = "Mortality_2011_D.rda",
    url    = paste0(RNH_BASE, "/Mortality_2011_D.rda"), expect = 25576,
    note   = "NDI 死亡链接，随访至 2011（cycle D）"),
  data.table(
    subdir = "rnhanesdata_ref", fname = "Mortality_2015_C.rda",
    url    = paste0(RNH_BASE, "/Mortality_2015_C.rda"), expect = 23752,
    note   = "NDI 死亡链接，随访至 2015（cycle C）—— 主用，随访更长"),
  data.table(
    subdir = "rnhanesdata_ref", fname = "Mortality_2015_D.rda",
    url    = paste0(RNH_BASE, "/Mortality_2015_D.rda"), expect = 22760,
    note   = "NDI 死亡链接，随访至 2015（cycle D）—— 主用，随访更长")
), use.names = TRUE)

# 兜底源：镜像不可用时回退到 GitHub 原始地址（慢但权威）
FILES[, url_alt := NA_character_]
FILES[subdir == "rnhanesdata_ref",
      url_alt := paste0(RNH_RAW, "/", fname)]

# 台账里记录的始终是**权威原始地址**（不是镜像），保证溯源信息不随镜像失效而失真
FILES[, url_canonical := fifelse(subdir == "rnhanesdata_ref",
                                 paste0(RNH_RAW, "/", fname), url)]

# ---- 下载（已存在且大小正确则跳过，绝不重下 900 MB）---------------------------
dl_one <- function(urls, dest) {
  for (u in urls) {
    if (is.na(u) || !nzchar(u)) next
    ok <- tryCatch({
      utils::download.file(u, dest, mode = "wb", quiet = TRUE, method = "libcurl")
      file.exists(dest) && file.size(dest) > 0
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok) {
      st <- system2("curl", c("-sL", "--retry", "5", "--retry-delay", "5",
                              "--max-time", "3600", "-o", shQuote(dest), shQuote(u)))
      ok <- (st == 0) && file.exists(dest) && file.size(dest) > 0
    }
    if (ok) { pa_log("  来源: ", u); return(TRUE) }
    pa_log("  该源失败，尝试下一个: ", u)
  }
  FALSE
}

fetch_report <- list()
for (i in seq_len(nrow(FILES))) {
  dest <- file.path(PA_ROOT, "data", "raw", FILES$subdir[i], FILES$fname[i])
  # ⚠️ 两个坑：① 必须先判 file.exists（否则 file.size 返回 NA，比较结果也是 NA，
  #    在 if 里会被当成错误；② 不能用 `a && b || c` —— && 优先级高于 ||，
  #    会被解析成 (a && b) || c，从而在 expect 为 NA 时把「文件不存在」也判为「已有」。
  #    → 统一要求：文件存在，且（期望大小未知 或 大小精确匹配）。部分下载会被重下。
  size_ok <- file.exists(dest) &&
             (is.na(FILES$expect[i]) || file.size(dest) == FILES$expect[i])
  if (size_ok) {
    pa_log("[已有] ", FILES$fname[i], " (", format(file.size(dest), big.mark = ","), " B)")
    fetch_report[[length(fetch_report) + 1L]] <- data.table(
      file = FILES$fname[i], action = "skipped_exists",
      bytes = file.size(dest), ok = TRUE)
    next
  }
  pa_log("[下载] ", FILES$fname[i], " ...")
  ok <- dl_one(c(FILES$url[i], FILES$url_alt[i]), dest)
  b  <- if (file.exists(dest)) file.size(dest) else 0
  if (ok && !is.na(FILES$expect[i]) && b != FILES$expect[i]) {
    ok <- FALSE
    pa_log("  ✗ 大小不符：期望 ", FILES$expect[i], " 实际 ", b)
  }
  fetch_report[[length(fetch_report) + 1L]] <- data.table(
    file = FILES$fname[i], action = "downloaded", bytes = b, ok = ok)
  if (!ok) stop("下载失败：", FILES$fname[i])
}
FR <- rbindlist(fetch_report)

# ---- 解压 PAM ZIP → scratch（可由 ZIP 再生，不进指纹台账）---------------------
for (z in c("PAXRAW_C", "PAXRAW_D")) {
  xpt <- file.path(DIR_SCRATCH, paste0(tolower(z), ".xpt"))
  if (file.exists(xpt) && file.size(xpt) > 1e9) {
    pa_log("[已有] ", basename(xpt), " (", sprintf("%.2f GB", file.size(xpt) / 1024^3), ")")
    next
  }
  zip <- file.path(DIR_PAM, paste0(z, ".zip"))
  pa_log("[解压] ", basename(zip), " -> ", basename(xpt))
  utils::unzip(zip, exdir = DIR_SCRATCH)
  if (!file.exists(xpt)) stop("解压后未找到 ", xpt)
}
for (z in c("PAXRAW_C", "PAXRAW_D")) {
  xpt <- file.path(DIR_SCRATCH, paste0(tolower(z), ".xpt"))
  pa_log(sprintf("  %-16s %s B (%.2f GB)", basename(xpt),
                 format(file.size(xpt), big.mark = ","), file.size(xpt) / 1024^3))
}

# ---- 指纹台账（幂等追加）------------------------------------------------------
CHK <- file.path(DIR_SOURCES, "checksums.csv")
chk <- if (file.exists(CHK)) fread(CHK) else data.table(
  filename = character(), size_bytes = numeric(), hash_algo = character(),
  hash = character(), url = character(), last_modified_http = character(),
  first_seen = character())

FILES[, rel := paste0(subdir, "/", fname)]
newrows <- list()
for (i in seq_len(nrow(FILES))) {
  rel <- FILES$rel[i]
  if (rel %in% chk$filename) { pa_log("[台账已有] ", rel); next }
  p <- file.path(PA_ROOT, "data", "raw", rel)
  if (!file.exists(p)) { pa_log("[跳过] 文件不存在 ", rel); next }
  h <- pa_hash(p, algo = "sha256")
  newrows[[length(newrows) + 1L]] <- data.table(
    filename = rel, size_bytes = file.size(p), hash_algo = "sha256", hash = h,
    url = FILES$url_canonical[i], last_modified_http = "n/a",
    first_seen = format(Sys.time(), "%Y-%m-%d"))
  pa_log(sprintf("[台账新增] %-34s %s", rel, substr(h, 1, 16)))
}
if (length(newrows)) {
  chk <- rbindlist(list(chk, rbindlist(newrows)), use.names = TRUE, fill = TRUE)
  setorder(chk, filename)
  fwrite(chk, CHK)
  pa_log("checksums.csv 现有 ", nrow(chk), " 条")
} else {
  pa_log("checksums.csv 无需新增（现有 ", nrow(chk), " 条）")
}

pa_log("01b 完成。")
print(FR)
