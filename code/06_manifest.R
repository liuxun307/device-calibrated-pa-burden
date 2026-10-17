# =============================================================================
# 06_manifest.R  —  生成完整产物清单（manifest）
#
# 目的：把"这次运行到底产出了什么"变成可核对的机器可读清单。
#       任何人拿到项目后，可用 98_verify_reproducibility.R 对照本清单，
#       逐文件核验字节数 / SHA-256，从而判断"是否复现成功"。
#
# 覆盖范围：data/raw（原始）· data/derived（中间）· data/gbd（外部）· output（交付）
# 记录字段：scope, rel_path, bytes, hash_algo, hash, mtime, rows, cols, note
#
# 输出：
#   output/manifest.csv          逐文件清单（含指纹）
#   output/manifest_summary.txt  人可读摘要（数量/体量/分组）
# =============================================================================

# ---- 统一引导（勿改）--------------------------------------------------------
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
  if (is.null(.ps)) stop("未找到 00_setup.R：请 setwd() 到 code/ 目录")
  source(.ps); rm(.ps, .c)
}

suppressPackageStartupMessages({ library(data.table) })
pa_log("===== 06 生成产物清单 =====")

MANIFEST_CSV <- file.path(DIR_OUT, "manifest.csv")

# ---------------------------------------------------------------- 工具 -------
# 与 locale 无关的对象内容指纹（仅用于 .rds）
# 背景（2026-10-15 实测，scratch/_probe_rds_locale.R）：
#   .rds 的**字节**哈希取决于解析期 LC_CTYPE —— Git Bash 会传 LC_ALL=C.UTF-8，
#   Windows 上的 R 无法设置它 → 回退到非 UTF-8 locale → 字符串字面量不带 UTF-8
#   编码标记 → saveRDS 字节不同，但**数值完全一致**。
#   因此字节哈希不能作为 RDS 的跨环境复现判据；这里对"载入后的对象"做归一化
#   （数值 → %.17g 定点字符串；字符串 → 强制 UTF-8）后再哈希，结果与 locale 无关。
content_fingerprint <- function(x) {
  if (!requireNamespace("digest", quietly = TRUE)) return(NA_character_)
  y <- tryCatch(rapply(x, function(v) {
    if (is.numeric(v))  sprintf("%.17g", as.numeric(v))
    else if (is.character(v)) enc2utf8(v)
    else if (is.factor(v))    enc2utf8(as.character(v))
    else v
  }, how = "replace"), error = function(e) x)
  digest::digest(y)
}

rows_cols <- function(p) {
  ext <- tolower(tools::file_ext(p))
  out <- list(rows = NA_integer_, cols = NA_integer_, content_hash = NA_character_)
  # ⚠️ 必须显式给 sep（2026-10-15 实测）：
  #   `fread(..., fill = TRUE)` **不带 sep** 时，分隔符自动探测会退化 ——
  #   当表头字段名含空格时（如 GBD 的 `Location ID,Location Name,...`），
  #   探测会选中 " " 作为分隔符 → 列数 7（正确 4）、读到第 222 行提前停止、
  #   行数记 220（正确 934）。且这一步**可能不报任何告警**（取决于 encoding 参数），
  #   属静默错误。最小复现：表头 `Location ID,Location Name,2023 SDI Index Value,SDI Quintile`
  #   + 400 行数据 → fill=TRUE 得 7 列，默认得 4 列。
  #   受影响文件：data/gbd/SDI/IHME_GBD_2023_SDI_1950_2023_SDI_QUINTILES_*.csv
  #   （另有编码陷阱：该文件是 Latin-1，见 96b_sdi_anchor.R 的说明）。
  SEP <- if (ext == "tsv") "\t" else ","
  read_meta <- function(enc) {
    warned <- character(0)
    res <- withCallingHandlers(
      tryCatch({
        d <- fread(p, nrows = 0, fill = TRUE, sep = SEP, encoding = enc)
        n <- nrow(fread(p, select = 1, fill = TRUE, sep = SEP, encoding = enc))
        list(cols = ncol(d), rows = n)
      }, error = function(e) NULL),
      warning = function(w) { warned <<- c(warned, conditionMessage(w)); invokeRestart("muffleWarning") }
    )
    list(res = res, early = any(grepl("Stopped early", warned, fixed = TRUE)))
  }
  try({
    if (ext %in% c("csv", "tsv")) {
      a <- read_meta("UTF-8")
      # 兜底：仍出现「Stopped early」（真·不规则文件）时，换 Latin-1 再试一次，取行数更大者
      if (a$early || is.null(a$res)) {
        b <- read_meta("Latin-1")
        if (!is.null(b$res) && (is.null(a$res) || b$res$rows > a$res$rows)) a <- b
      }
      if (!is.null(a$res)) { out$cols <- a$res$cols; out$rows <- a$res$rows }
    } else if (ext == "rds") {
      x <- readRDS(p)
      if (is.data.frame(x)) { out$rows <- nrow(x); out$cols <- ncol(x) }
      out$content_hash <- content_fingerprint(x)
    }
  }, silent = TRUE)
  out
}

scan_scope <- function(dir, scope) {
  if (!dir.exists(dir)) return(NULL)
  fs <- list.files(dir, recursive = TRUE, full.names = TRUE, all.files = FALSE)
  fs <- fs[!dir.exists(fs)]
  # 排除 manifest 自身，避免自指
  fs <- fs[normalizePath(fs, mustWork = FALSE) !=
             normalizePath(MANIFEST_CSV, mustWork = FALSE)]
  if (!length(fs)) return(NULL)
  # 相对路径：直接做前缀截取（避免拼正则时转义 Windows 路径中的特殊字符）
  full   <- gsub("\\\\", "/", fs)
  prefix <- paste0(gsub("\\\\", "/", gsub("/+$", "", dir)), "/")
  rel    <- ifelse(startsWith(full, prefix), substring(full, nchar(prefix) + 1L), full)
  r <- lapply(fs, rows_cols)
  data.table(
    scope      = scope,
    rel_path   = rel,
    bytes      = as.numeric(file.size(fs)),
    hash_algo  = if (requireNamespace("digest", quietly = TRUE)) "sha256" else "md5",
    hash       = pa_hash(fs, algo = "sha256"),
    mtime      = format(file.info(fs)$mtime, "%Y-%m-%d %H:%M:%S"),
    rows       = vapply(r, function(z) z$rows, integer(1)),
    cols       = vapply(r, function(z) z$cols, integer(1)),
    content_hash = vapply(r, function(z) if (is.null(z$content_hash)) NA_character_
                                        else z$content_hash, character(1)),
    note       = ""
  )
}

# ---------------------------------------------------------------- 扫描 -------
mf <- rbindlist(list(
  scan_scope(DIR_RAW,     "raw"),
  scan_scope(DIR_GBD,     "gbd"),
  scan_scope(DIR_BOP,     "bop"),
  scan_scope(DIR_DERIV,   "derived"),
  scan_scope(DIR_OUT,     "output")
), use.names = TRUE, fill = TRUE)

if (!nrow(mf)) stop("未扫描到任何文件：请先运行 01-05")

# 打标签
mf[scope == "output" & grepl("\\.(pdf|png|tiff?|eps|svg)$", rel_path, ignore.case = TRUE),
   note := "figure"]
mf[scope == "output" & grepl("\\.csv$", rel_path, ignore.case = TRUE), note := "table/csv"]
mf[scope == "output" & grepl("\\.md$",  rel_path, ignore.case = TRUE), note := "caption/说明文档"]
mf[scope == "raw",     note := "原始数据（只读，勿改）"]
mf[scope == "derived", note := "中间缓存"]
mf[scope == "gbd",     note := "GBD 外部获取数据"]

setorder(mf, scope, rel_path)
mf[, manifest_generated_at := format(Sys.time(), "%Y-%m-%d %H:%M:%S")]
mf[, run_id := PA_RUN_ID]
fwrite(mf, MANIFEST_CSV)
# 归档一份到本次运行日志目录，供跨运行比对（98 脚本会用到）
file.copy(MANIFEST_CSV, file.path(PA_RUN_DIR, "manifest.csv"), overwrite = TRUE)

# ---------------------------------------------------------------- 摘要 -------
sink(file.path(DIR_OUT, "manifest_summary.txt"))
cat("产物清单摘要\n")
cat("生成时间 :", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("运行 ID  :", PA_RUN_ID, "\n")
cat("项目根   :", PA_ROOT, "\n")
cat("指纹算法 :", mf$hash_algo[1], "\n\n")
sm <- mf[, .(文件数 = .N, 总字节 = sum(bytes, na.rm = TRUE)), by = scope]
sm[, 体量 := sprintf("%.2f MB", 总字节 / 1024^2)]
print(sm[, .(scope, 文件数, 体量)])
cat("\n--- 交付物（output）---\n")
print(mf[scope == "output", .(rel_path, bytes, rows, cols, note)])
cat("\n--- 原始数据（raw）---\n")
print(mf[scope == "raw", .(rel_path, bytes)])
sink()

pa_log("06 完成：清单 ", nrow(mf), " 个文件 -> output/manifest.csv")
print(mf[, .N, by = scope])
