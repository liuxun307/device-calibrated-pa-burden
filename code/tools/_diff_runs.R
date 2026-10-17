suppressMessages(library(data.table))
prev <- fread("logs/20261016_124030/manifest.csv", encoding = "UTF-8")
curr <- fread("output/manifest.csv", encoding = "UTF-8")
m <- merge(prev[, .(rel_path, hp = hash)], curr[, .(rel_path, hn = hash)], by = "rel_path")
d <- m[!is.na(hp) & !is.na(hn) & hp != hn]
cat("总差异:", nrow(d), "\n")
is_pdf <- grepl("\\.pdf$", d$rel_path)
META <- c("manifest_summary.txt", "REPRODUCIBILITY_REPORT.txt", "QC_98_checks.csv")
is_meta <- basename(d$rel_path) %in% META
is_doc <- grepl("\\.md$", d$rel_path, ignore.case = TRUE)
cat("其中 PDF:", sum(is_pdf), " 元产物:", sum(is_meta), " 文档:", sum(is_doc), "\n\n")
real <- d[!is_pdf & !is_meta & !is_doc]
for (i in seq_len(nrow(real))) cat(sprintf("%2d  %s\n", i, real$rel_path[i]))
