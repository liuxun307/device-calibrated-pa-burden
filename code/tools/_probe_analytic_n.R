# 临时探针：核对 analytic.rds 的样本量口径（Table 1 = 7,854 vs Fig2a 建模集 = 7,007）
suppressPackageStartupMessages(library(data.table))
adm <- as.data.table(readRDS("data/derived/analytic.rds"))
cat("=== analytic.rds ===\n")
cat("总行数:", nrow(adm), "\n\n")

covars <- c("age","female","race","educ","pir","bmi","sbp","cur_smoke","drink_any","diabetes","cvd_hx")
have <- intersect(covars, names(adm))
cat("可用协变量:", paste(have, collapse=","), "\n")
cat("缺失的协变量:", paste(setdiff(covars, have), collapse=","), "\n\n")

vars <- intersect(c(have, "mims_per_day", "surv_mo", "WTMEC4YR", "died", "cvd_death"), names(adm))
cc <- complete.cases(adm[, vars, with = FALSE])
cat("完整案例(mims + surv + 权重 + 全部协变量):", sum(cc), "\n")
cat("总死亡:", sum(adm$died, na.rm = TRUE), "   完整案例内死亡:", sum(adm$died[cc], na.rm = TRUE), "\n\n")

cat("--- 各变量缺失数 ---\n")
for (v in vars) cat(sprintf("  %-14s 缺失 %d\n", v, sum(is.na(adm[[v]]))))

cat("\n--- Table 1 口径（mims_q4 与权重非缺失）---\n")
t1 <- adm[!is.na(mims_q4) & !is.na(WTMEC4YR)]
cat("行数:", nrow(t1), "   死亡:", sum(t1$died, na.rm = TRUE), "\n")
