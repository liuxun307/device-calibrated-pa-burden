# =============================================================================
# 99_missing_table.R — 逐协变量缺失比例（供 Table S13 表注 / STROBE 14b）
#
# 目的：STROBE 14b 要求报告每个协变量的缺失数量。此前只在表注写了
#       "complete-case，n=7,007"，未给逐变量缺失比例。本脚本把该读数落盘，
#       使表注中的每个数字都可回溯到产物，而不是手算后硬编码。
#
# 权威协变量清单来源：04_cox_dose_response.R 第 62 行 `covars`（Model 2 全调整集，11 项）。
#   ⚠️ 不得凭记忆另立清单——本脚本直接复刻该行，改那一行时须同步改这里。
#
# 输出：output/TableS13_missing_by_variable.csv
# 口径：分母 = 设备样本 n（25+、有效加速度计、具权重）；
#       分子 = 该变量 is.na 计数；另给出 complete-case 样本量与结局变量缺失。
# =============================================================================

local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
})
if (!isTRUE(getOption("PA_SETUP_DONE"))) {
  .ps <- NULL
  for (.c in c("00_setup.R", file.path(getwd(), "00_setup.R"),
               file.path(dirname(gsub("\\\\", "/", sub("^--file=", "",
                 grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))), "00_setup.R"))) {
    if (!is.null(.c) && nzchar(.c) && file.exists(.c)) { .ps <- normalizePath(.c); break }
  }
  if (is.null(.ps)) stop("未找到 00_setup.R：请 setwd() 到 code/ 目录")
  source(.ps); rm(.ps, .c)
}

suppressPackageStartupMessages({ library(data.table) })
pa_log("===== 99 逐协变量缺失比例 =====")

d <- as.data.table(readRDS(file.path(DIR_DERIV, "analytic.rds")))
n <- nrow(d)
pa_log("设备样本 n = ", n)

# ---- 协变量清单（复刻 04_cox_dose_response.R:62）---------------------------
covars <- c("age","female","race","educ","pir","bmi","sbp",
            "cur_smoke","drink_any","diabetes","cvd_hx")
miss_cols <- setdiff(covars, names(d))
if (length(miss_cols)) stop("analytic.rds 缺少协变量列：", paste(miss_cols, collapse = ", "))

# 中文标签（与 Table S13 行名对应）
lab <- c(age = "年龄 age", female = "女性 female", race = "种族/族裔 race/ethnicity",
         educ = "教育 educ", pir = "家庭收入比 PIR", bmi = "BMI",
         sbp = "收缩压 SBP", cur_smoke = "现吸烟 current smoking",
         drink_any = "饮酒 any drinking", diabetes = "糖尿病 diabetes",
         cvd_hx = "心血管病史 CVD history")

res <- rbindlist(lapply(covars, function(v) {
  x  <- d[[v]]
  nm <- sum(is.na(x))
  data.table(variable    = v,
             label       = unname(lab[v]),
             n_total     = n,
             n_missing   = nm,
             pct_missing = round(100 * nm / n, 2),
             n_complete  = n - nm)
}))

# ---- 结局与随访变量的缺失（单独成组，供表注分母说明）----------------------
endp <- intersect(c("died","cvd_death","surv_mo"), names(d))
res_end <- rbindlist(lapply(endp, function(v) {
  nm <- sum(is.na(d[[v]]))
  data.table(variable    = v,
             label       = sprintf("结局/随访 %s（%s）", v, "未链接到 NDI 死亡随访"),
             n_total     = n,
             n_missing   = nm,
             pct_missing = round(100 * nm / n, 2),
             n_complete  = n - nm)
}))
res <- rbind(res_end, res)

res[, note := fifelse(n_missing == 0, "无缺失", "")]
setorder(res, -n_missing, variable)

out <- file.path(DIR_OUT, "TableS13_missing_by_variable.csv")
fwrite(res, out)

# ---- 汇总读数（供表注引用）------------------------------------------------
cc <- complete.cases(as.data.frame(d[, c(covars, "surv_mo"), with = FALSE])) & !is.na(d$surv_mo) & d$surv_mo > 0
pa_log("仅因协变量缺失剔除的个体 = ", n - sum(complete.cases(as.data.frame(d[, covars, with = FALSE]))))
pa_log("协变量 + 有效随访均完整的 complete-case n = ", sum(cc),
       "（其中死亡 ", sum(d$died[cc], na.rm = TRUE), "）")
pa_log("结局三变量（died/cvd_death/surv_mo）同时缺失 = ",
       sum(is.na(d$died) & is.na(d$cvd_death) & is.na(d$surv_mo)))
pa_log("→ ", out)

print(res[, .(variable, n_missing, pct_missing, n_complete)])
