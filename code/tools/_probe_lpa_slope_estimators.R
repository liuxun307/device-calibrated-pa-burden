# =============================================================================
# tools/_probe_lpa_slope_estimators.R
# 诊断：为什么「单来源过原点拟合」的 LPA 髋式斜率与 05a 模型给出的差 2 倍？
#   · E1 单来源过原点 WLS（我的锚点脚本用的估计量）
#   · E2 单来源 截距+斜率 WLS
#   · E3 单来源 metafor rma.mv(yi, V=vi, random=~1|study) + mods=~0+offset
#   · E4 全池 metafor rma.mv（含全部里程）取 device_hip|LPA 系数
# 对照 05a 的 Table5_bop_wear_site.csv 的 slope_hip。
# =============================================================================
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8"))
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
})
if (!isTRUE(getOption("PA_SETUP_DONE"))) {
  .ps <- NULL
  for (.c in c("00_setup.R", file.path(getwd(), "00_setup.R"), "../00_setup.R")) {
    if (!is.null(.c) && nzchar(.c) && file.exists(.c)) { .ps <- normalizePath(.c); break }
  }
  source(.ps); rm(.ps, .c)
}
suppressPackageStartupMessages({ library(data.table); library(metafor) })

Z975 <- qnorm(0.975)
d <- fread(file.path(DIR_BOP, "rr_table.csv"), encoding = "UTF-8")
d[, offset := as.numeric(exposure_center) - as.numeric(exposure_ref_center)]
d[, `:=`(yi = log(as.numeric(hr)),
         vi = ((log(as.numeric(hr_hi)) - log(as.numeric(hr_lo))) / (2 * Z975))^2)]
d[, arm := fcase(method == "self", "self",
                 method == "device" & wear_site == "hip",   "device_hip",
                 method == "device" & wear_site == "wrist", "device_wrist",
                 method == "device" & wear_site == "mixed", "device_mixed")]

sub <- d[arm == "device_hip" & metric_definition == "LPA"]
cat("\n---- LPA 髋侧行 ----\n")
print(sub[, .(row_id, study, offset, yi, vi, se = sqrt(vi))])

# E1 单来源过原点 WLS
w <- 1 / sub$vi
cat(sprintf("\nE1 单来源过原点 WLS      : b = %+.6f  (SE %.6f)\n",
            sum(w * sub$offset * sub$yi) / sum(w * sub$offset^2),
            1 / sqrt(sum(w * sub$offset^2))))

# E2 截距 + 斜率
m2 <- lm(yi ~ offset, data = sub, weights = w)
cat(sprintf("E2 单来源 截距+斜率 WLS  : b = %+.6f  (SE %.6f)  intercept = %+.4f\n",
            coef(m2)[2], summary(m2)$coefficients[2, 2], coef(m2)[1]))

# E3 单来源 rma.mv（随机截距 per study）
m3 <- tryCatch(rma.mv(yi = yi, V = vi, mods = ~ 0 + offset, random = ~ 1 | study,
                      data = sub, method = "REML"), error = function(e) NULL)
if (!is.null(m3)) cat(sprintf("E3 单来源 rma.mv ~0+offset: b = %+.6f  (SE %.6f)  tau2 = %.3g\n",
                              coef(m3)[1], m3$se[1], m3$sigma2[1]))

# E4 全池 rma.mv（与 05a 同结构；把 metric 与 arm 合成组合因子）
d[, combo := factor(paste(arm, metric_definition, sep = "|"))]
m4 <- tryCatch(rma.mv(yi = yi, V = vi, mods = ~ 0 + combo:offset, random = ~ 1 | study,
                      data = d[population == "general"], method = "REML"), error = function(e) NULL)
if (!is.null(m4)) {
  nm <- grep("device_hip\\|LPA", names(coef(m4)), value = TRUE)
  cat(sprintf("E4 全池 rma.mv           : %s = %+.6f  (SE %.6f)\n", nm[1], coef(m4)[nm[1]], m4$se[nm[1]]))
  nmw <- grep("device_wrist\\|LPA", names(coef(m4)), value = TRUE)
  cat(sprintf("                            %s = %+.6f  (SE %.6f)\n", nmw[1], coef(m4)[nmw[1]], m4$se[nmw[1]]))
}

cat("\n---- 05a 的表（贝叶斯模型） ----\n")
t5 <- fread(file.path(DIR_OUT, "Table5_bop_wear_site.csv"), encoding = "UTF-8")
print(t5[spec == "main_general_population" & metric_definition == "LPA",
         .(offset_pts, slope_hip, slope_wrist, rr_ratio_hip_over_wrist)])
