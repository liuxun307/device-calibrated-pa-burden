# =============================================================================
# tools/_audit_stale_products.R
# 目的：找出 output/ 中「被 code/ 引用、但**未被最近一次全链运行刷新**」的产物
#       —— 这类文件只能是历史遗留（陈旧孤儿）；若被下游消费，就会静默失真。
# 背景：2026-10-16 发现 PREVIEW_module3_s1p_* 属此类（生产方漏设 PA_CV_MODE=s1p），
#       导致 Fig 5 / Table 4 / Table 7 / 图注引用了未参与本次运行的数据。
# 判据：文件 mtime < 最近一次 run 的 run.log mtime → 未参与该次运行。
# 用法：Rscript code/tools/_audit_stale_products.R   （在项目根目录执行）
# =============================================================================
suppressMessages(library(data.table))

rd  <- list.dirs("logs", recursive = FALSE, full.names = TRUE)
rd  <- rd[grepl("20[0-9]{6}_[0-9]{6}$", basename(rd))]
if (!length(rd)) stop("未找到任何 run 目录")
latest <- rd[which.max(file.info(rd)$mtime)]
t0 <- file.info(file.path(latest, "run.log"))$mtime
cat(sprintf("最近一次运行：%s（起始 %s）\n", basename(latest), format(t0, "%Y-%m-%d %H:%M:%S")))

# --- 收集 code/ 中引用的 output 文件名字面量（读 + 写都算"引用"）---
SRCS <- c(list.files("code", pattern = "\\.R$", full.names = TRUE, recursive = TRUE))
txt  <- unlist(lapply(SRCS, function(f) readLines(f, warn = FALSE, encoding = "UTF-8")))
lit  <- unique(unlist(regmatches(txt, gregexpr('"[A-Za-z0-9_.-]+\\.(csv|rds|txt|png|pdf)"', txt))))
lit  <- gsub('"', "", lit)

# --- 只保留 output/ 下真实存在的文件 ---
p  <- file.path("output", lit)
ex <- file.exists(p)
d  <- data.table(file = lit[ex], mtime = file.info(p[ex])$mtime)
d[, age_min := round(as.numeric(difftime(Sys.time(), mtime, units = "mins")), 1)]
d[, stale   := mtime < t0]

cat(sprintf("\n=== A. 被 code/ 引用、但**未被最近一次运行刷新**（%d 个）===\n",
            nrow(d[stale == TRUE])))
print(d[stale == TRUE][order(-age_min), .(file, age_min)], row.names = FALSE)

cat(sprintf("\n=== B. 已被本次运行刷新（%d 个，正常）===\n", nrow(d[stale == FALSE])))
print(head(d[stale == FALSE][order(-age_min), .(file, age_min)], 12), row.names = FALSE)

# --- C. output/ 中完全没有被 code/ 引用过的文件（真·孤儿）---
all_out <- list.files("output", pattern = "\\.(csv|rds|txt|png|pdf|md)$")
orphan  <- setdiff(all_out, d$file)
orph <- data.table(file = orphan)
orph[, age_min := round(as.numeric(difftime(Sys.time(),
                    file.info(file.path("output", file))$mtime, units = "mins")), 1)]
cat(sprintf("\n=== C. output/ 中未被 code/ 任何文件引用（%d 个）===\n", nrow(orph)))
print(orph[order(-age_min)], row.names = FALSE)
