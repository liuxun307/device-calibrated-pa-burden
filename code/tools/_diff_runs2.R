# 对比两次 run 的 manifest，列出全部差异（不依赖 98 的展示上限）
#
# ⚠️ 陷阱（2026-10-16 实测踩过）：manifest 的 content_hash **只对 RDS 类产物计算**，
#    CSV / PDF / .md 等一律为空串。若写成 `!is.na(ch) & ch == ch`，空串 == 空串 → TRUE，
#    会把 32 个真实差异全部误判为"内容一致"。必须同时要求 nzchar()。
suppressMessages(library(data.table))
argv <- commandArgs(TRUE)
prev_dir <- if (length(argv) >= 1) argv[1] else "logs/20261016_154842"
prev <- fread(file.path(prev_dir, "manifest.csv"), encoding = "UTF-8")
curr <- fread("output/manifest.csv", encoding = "UTF-8")
norm_ch <- function(x) ifelse(is.na(x) | !nzchar(x), NA_character_, x)
m <- merge(prev[, .(rel_path, scope, hp = hash, chp = norm_ch(content_hash))],
           curr[, .(rel_path, scope, hn = hash, chn = norm_ch(content_hash))],
           by = c("rel_path", "scope"), all = TRUE)
cat("前次:", prev_dir, " 记录", nrow(prev), " | 本次: 记录", nrow(curr), "\n")
cat("仅前次有(消失):", sum(is.na(m$hn)), " 仅本次有(新增):", sum(is.na(m$hp)), "\n")
d <- m[!is.na(hp) & !is.na(hn) & hp != hn]
cat("字节哈希不同:", nrow(d), "\n")
if (nrow(d)) {
  # 只有两侧都有非空内容指纹、且相等，才算"仅元数据变"
  d[, content_same := !is.na(chp) & !is.na(chn) & chp == chn]
  cat("  其中【RDS 且内容指纹相同】(仅序列化编码变):", sum(d$content_same), "\n")
  cat("  需人工确认的实质差异:", sum(!d$content_same), "\n\n")
  for (i in seq_len(nrow(d))) cat(sprintf("%2d  [%s] %s%s\n", i, d$scope[i], d$rel_path[i],
                                          if (isTRUE(d$content_same[i])) "   (RDS 内容一致)" else ""))
}
