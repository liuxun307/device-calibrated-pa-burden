# 复刻 98_verify_reproducibility.R 的 E 层判定逻辑，用于在不跑全链的情况下验证豁免规则改动
suppressMessages(library(data.table))
argv <- commandArgs(TRUE)
prev_dir <- if (length(argv) >= 1) argv[1] else "logs/20261016_143924"
prev <- fread(file.path(prev_dir, "manifest.csv"), encoding = "UTF-8")
curr <- fread("output/manifest.csv", encoding = "UTF-8")
if (!"content_hash" %in% names(prev)) prev[, content_hash := NA_character_]
if (!"content_hash" %in% names(curr)) curr[, content_hash := NA_character_]

cmp <- merge(prev[, .(rel_path, scope, hash_prev = hash, ch_prev = content_hash)],
             curr[, .(rel_path, scope, hash_now = hash, ch_now = content_hash)],
             by = c("rel_path", "scope"), all = TRUE)
same <- cmp[!is.na(hash_prev) & !is.na(hash_now) & hash_prev == hash_now]
diff <- cmp[!is.na(hash_prev) & !is.na(hash_now) & hash_prev != hash_now]

META_SELFREF <- c("manifest_summary.txt", "REPRODUCIBILITY_REPORT.txt", "QC_98_checks.csv")
is_pdf    <- grepl("\\.pdf$", diff$rel_path)
is_meta   <- basename(diff$rel_path) %in% META_SELFREF
is_doc_old <- grepl("\\.md$", diff$rel_path, ignore.case = TRUE)                       # 旧规则
is_doc_new <- grepl("\\.md$", diff$rel_path, ignore.case = TRUE) & diff$scope != "output" # 新规则
is_rds_ok <- grepl("\\.rds$", diff$rel_path) &
             !is.na(diff$ch_prev) & !is.na(diff$ch_now) & diff$ch_prev == diff$ch_now

report <- function(tag, is_doc) {
  d <- diff[!is_pdf & !is_meta & !is_doc & !is_rds_ok]
  cat(sprintf("\n== %s ==\n", tag))
  cat(sprintf("  一致 %d；字节差异 %d；豁免：PDF %d + 元产物 %d + 文档 %d + RDS %d = %d\n",
              nrow(same), nrow(diff),
              sum(is_pdf), sum(is_meta), sum(is_doc & !is_pdf & !is_meta), sum(is_rds_ok & !is_pdf & !is_meta & !is_doc),
              sum(is_pdf) + sum(is_meta) + sum(is_doc & !is_pdf & !is_meta) + sum(is_rds_ok & !is_pdf & !is_meta & !is_doc)))
  cat(sprintf("  → 未豁免（实质）差异 %d 项\n", nrow(d)))
  if (nrow(d)) for (i in seq_len(nrow(d))) cat(sprintf("     - [%s] %s\n", d$scope[i], d$rel_path[i]))
}
report("旧规则（所有 .md 豁免）", is_doc_old)
report("新规则（output/ 下 .md 不再豁免）", is_doc_new)
