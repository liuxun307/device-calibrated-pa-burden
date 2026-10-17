suppressMessages(library(data.table))
d <- fread("output/QC_98_checks.csv", encoding = "UTF-8")
cat("=== 各状态计数 ===\n"); print(d[, .N, by = status])
cat("\n=== WARN 明细 ===\n")
w <- d[status == "WARN"]
for (i in seq_len(nrow(w))) cat(sprintf("[%s] %s :: %s\n", w$layer[i], w$item[i], substr(w$detail[i], 1, 110)))
cat("\n=== Module 2 / BoP / 引擎 相关 ===\n")
k <- d[grepl("引擎|Module 2|BoP", item) | grepl("引擎|Module 2|BoP", detail)]
for (i in seq_len(nrow(k))) cat(sprintf("%-6s [%s] %s :: %s\n", k$status[i], k$layer[i], k$item[i], substr(k$detail[i], 1, 100)))
