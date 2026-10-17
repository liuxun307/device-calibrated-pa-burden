#!/usr/bin/env Rscript
# =============================================================================
# syncheck.R  --  R 脚本语法总检（带 locale 回退链）
#
# 为什么需要它
# ------------
# 本项目脚本含中文变量名与中文注释。若 LC_CTYPE 未设置，
# parse() 会把中文当作非法 token（"unexpected invalid token"），
# 造成「文件其实没错、检查却报错」的假警报（见 code/README.md 的 R 陷阱节）。
# 故必须先跑 locale 回退链再 parse。
#
# 用法
# ----
#   Rscript tools/syncheck.R                      # 检查上一级（code/）全部 .R
#   Rscript tools/syncheck.R 10_captions.R 97_m3_scenarios.R
#
# 退出码：0 = 全部 OK；1 = 有文件语法失败。
# =============================================================================

local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8"))
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
})
cat("LC_CTYPE =", Sys.getlocale("LC_CTYPE"), "\n")

args <- commandArgs(TRUE)
self <- tryCatch({
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(a)) normalizePath(dirname(sub("^--file=", "", a[1])), mustWork = FALSE) else getwd()
}, error = function(e) getwd())

fs <- if (length(args)) args else unique(c(
  # 候选 1：脚本所在目录的上一级（code/）
  list.files(file.path(self, ".."), pattern = "[.][Rr]$", full.names = TRUE),
  # 候选 2：当前工作目录（Windows 中文路径下 normalizePath 偶尔返回乱码，故做双候选）
  list.files(".", pattern = "[.][Rr]$", full.names = TRUE)))
fs <- fs[file.exists(fs)]
fs <- fs[!grepl("[/\\\\]tools[/\\\\]", fs)]     # 不检查本目录
if (!length(fs)) stop("没有找到要检查的 .R 文件")

n_bad <- 0L
for (f in fs) {
  e <- tryCatch({ parse(file = f); NULL }, error = function(e) conditionMessage(e))
  if (is.null(e)) {
    cat(sprintf("%-46s OK\n", basename(f)))
  } else {
    n_bad <- n_bad + 1L
    cat(sprintf("%-46s FAIL: %s\n", basename(f), e))
  }
}
cat(sprintf("\n共 %d 个文件，%d 个失败\n", length(fs), n_bad))
quit(status = if (n_bad == 0L) 0L else 1L)
