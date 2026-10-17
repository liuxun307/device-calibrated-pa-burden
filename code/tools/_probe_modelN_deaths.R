# 诊断：07,854（Table1 对象）与 7,007（08b 建模样本）两段式样本的死亡数
# 目的：为 B9「两段式表述」提供**落盘来源**，禁止凭记忆写入图注。
suppressMessages({library(data.table); library(haven)})
DIR_DERIV <- file.path("..", "data", "derived")
adm <- as.data.table(readRDS(file.path(DIR_DERIV, "analytic.rds")))

cat("analytic.rds 行数 =", nrow(adm), "\n")
cat("列中含死亡/随访的字段：", paste(grep("death|mort|surv|dth", names(adm), value = TRUE), collapse = ", "), "\n\n")

# 判据 A：08b 的建模集口径
b <- copy(adm)[!is.na(surv_mo) & surv_mo > 0]
covars <- c("age","female","race","educ","pir","bmi","sbp","cur_smoke","drink_any","diabetes","cvd_hx")
for (v in c("mims_per_day", intersect(covars, names(b)), "WTMEC4YR")) b <- b[!is.na(get(v))]

cat("--- ① 有效加速度计 + 年龄>=25（= Fig2a 第 3 节点，Table 1 对象）---\n")
cat("   n =", nrow(adm), "\n")
# 找出死亡指示字段
dcol <- intersect(c("death_all","death","died","event","status","death_allcause"), names(adm))
cat("   候选死亡列：", paste(dcol, collapse=", "), "\n")

cat("\n--- ② 08b 建模集（完整协变量 + 有效随访）---\n")
cat("   n =", nrow(b), "\n")
for (dc in dcol) cat(sprintf("   sum(%s) = %s ; 非缺失 = %s\n", dc,
    format(sum(as.numeric(b[[dc]]), na.rm = TRUE), big.mark=","),
    format(sum(!is.na(b[[dc]])), big.mark=",")))
cat("\n--- ①/② 两段差异 ---\n")
cat("   n 差 =", nrow(adm) - nrow(b), "\n")
