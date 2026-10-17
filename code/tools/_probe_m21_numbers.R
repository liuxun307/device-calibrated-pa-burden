# 诊断（只读、不落产物）：为 Methods 2.1 提供随访时长等正文所需量
suppressMessages(library(data.table))
adm <- as.data.table(readRDS(file.path("..","data","derived","analytic.rds")))
cat("nrow(adm) =", nrow(adm), "\n")
cat("surv_mo 非缺失 =", sum(!is.na(adm$surv_mo)), " ; 中位数(月) =",
    sprintf("%.1f", median(adm$surv_mo, na.rm = TRUE)), " -> 年 =",
    sprintf("%.2f", median(adm$surv_mo, na.rm = TRUE)/12), "\n")
q <- quantile(adm$surv_mo, c(.25,.75), na.rm = TRUE)
cat("IQR(月) =", sprintf("%.1f-%.1f", q[1], q[2]), " -> 年", sprintf("%.2f-%.2f", q[1]/12, q[2]/12), "\n")
b <- copy(adm)[!is.na(surv_mo) & surv_mo > 0]
covars <- c("age","female","race","educ","pir","bmi","sbp","cur_smoke","drink_any","diabetes","cvd_hx")
for (v in c("mims_per_day", intersect(covars, names(b)), "WTMEC4YR")) b <- b[!is.na(get(v))]
cat("Cox 集 n =", nrow(b), " ; 随访中位数(月) =", sprintf("%.1f", median(b$surv_mo)), " -> 年",
    sprintf("%.2f", median(b$surv_mo)/12), "\n")
cat("Cox 集 max surv_mo(月) =", sprintf("%.1f", max(b$surv_mo)), " -> 年", sprintf("%.2f", max(b$surv_mo)/12), "\n")
cat("死亡 =", sum(b$died, na.rm=TRUE), " ; CVD 死亡 =", sum(b$cvd_death, na.rm=TRUE), "\n")
# 四分段界值（未加权四分位）
cat("mims_q4 界值:", sprintf("%.0f", quantile(adm$mims_per_day, 0:4/4, na.rm=TRUE)), "\n")
cat("自报 met_min_wk: n 非缺失 =", sum(!is.na(adm$met_min_wk)), "\n")
