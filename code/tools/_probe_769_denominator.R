# 核验 769 的分母：7,854 行中「死亡状态已知」多少行？
suppressMessages(library(data.table))
adm <- as.data.table(readRDS(file.path("..","data","derived","analytic.rds")))
cat("nrow(adm) =", nrow(adm), "\n")
cat("NA in died     :", sum(is.na(adm$died)), "\n")
cat("NA in cvd_death:", sum(is.na(adm$cvd_death)), "\n")
cat("NA in surv_mo  :", sum(is.na(adm$surv_mo)), " ; surv_mo<=0 :", sum(!is.na(adm$surv_mo) & adm$surv_mo<=0), "\n")
cat("died 非缺失行数 :", sum(!is.na(adm$died)), "\n")
cat("sum(died, na.rm=TRUE) =", sum(adm$died, na.rm=TRUE), "\n")
cat("died 与 surv_mo 缺失是否同一批人：died_NA & surv_NA =",
    sum(is.na(adm$died) & is.na(adm$surv_mo)),
    " | died_NA & surv_notNA =", sum(is.na(adm$died) & !is.na(adm$surv_mo)), "\n")
# Table 1 的分母口径（09 L24）
t1d <- adm[!is.na(mims_q4) & !is.na(WTMEC4YR)]
cat("t1d n =", nrow(t1d), " ; t1d 中 died 非缺失 =", sum(!is.na(t1d$died)), "\n")
