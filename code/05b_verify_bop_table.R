# =============================================================================
# 05b_verify_bop_table.R
# Module 2 输入表审计 —— 把「百分位是怎么算出来的」变成可复算的检查
# =============================================================================
# 为什么需要这一步：
#   Module 2 唯一的输入是 data/bop/rr_table.csv，而该表把**不同来源的暴露刻度**
#   统一换算到「各自分布内的百分位」——这是整个 BoP 合成最关键、也最容易被审稿人
#   质疑的一步换算。因此必须：
#     ① 把原文类别人数重新代回，复算百分位，逐行比对（不允许"手工算完就完事"）；
#     ② 检查 HR/CI 的内部一致性与方向单调性（抽错方向是最常见的人为错误）；
#     ③ 检查参照锚定（每行必须严格在自身参照之上）。
#   本脚本**只读** rr_table.csv，不改任何数据。
#
# 输出：output/QC_bop_table_audit.csv（逐项 PASS/WARN/FAIL）
#       logs/bop_table_audit.txt（人类可读报告）
# =============================================================================

local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
})
if (!isTRUE(getOption("PA_SETUP_DONE"))) {
  .ps <- NULL
  for (.c in c("00_setup.R", file.path(getwd(), "00_setup.R"))) {
    if (!is.null(.c) && nzchar(.c) && file.exists(.c)) { .ps <- normalizePath(.c); break }
  }
  if (is.null(.ps)) stop("未找到 00_setup.R：请 setwd() 到 code/ 目录后重试")
  source(.ps); rm(.ps, .c)
}
suppressPackageStartupMessages({ library(data.table) })

DIR_BOP <- file.path(PA_ROOT, "data", "bop")
RR_CSV  <- file.path(DIR_BOP, "rr_table.csv")
TOL_PCT <- 0.02   # 百分位复算容差（百分点）

CHK <- list()
add <- function(layer, item, status, detail = "")
  CHK[[length(CHK) + 1L]] <<- data.table(layer = layer, item = item,
                                         status = status, detail = detail)

stopifnot(file.exists(RR_CSV))
dt <- fread(RR_CSV, encoding = "UTF-8")

# 与 05a 完全同规则派生 arm（方法 × 佩戴部位）——审计必须按同一分轴报告，
# 否则"覆盖度"结论会与 05a 的实际模型设计脱节。
ARM_LEVELS <- c("self", "device_hip", "device_mixed", "device_wrist")
dt[, arm := fcase(
  method == "self",                          "self",
  method == "device" & wear_site == "hip",   "device_hip",
  method == "device" & wear_site == "wrist", "device_wrist",
  method == "device" & wear_site == "mixed", "device_mixed",
  default = NA_character_)]
if (anyNA(dt$arm))
  stop("05b：以下行无法归入 arm（检查 method / wear_site）：\n  ",
       paste(dt[is.na(arm), row_id], collapse = "\n  "))

# ---------------------------------------------------------------------------
# A. 原文公布的类别人数 → 复算百分位（Moore 2012, PMID 23139642, Table 3）
#    硬编码的是**原文印刷值**，不是本项目的派生值 —— 这是复算能成立的前提。
# ---------------------------------------------------------------------------
MOORE_PUB <- data.table(
  k = 1:6,
  lo = c(0, 0.1, 3.75, 7.5, 15.0, 22.5),      # MET-h/wk 类别下界
  hi = c(0, 3.74, 7.4, 14.9, 22.4, NA),       # 上界（最高类开放）
  n  = c(50555, 112661, 60132, 167931, 118255, 145293),
  d  = c(9754, 18352, 6968, 20428, 11814, 15149),
  hr = c(1.00, 0.81, 0.76, 0.68, 0.61, 0.59),
  lo95 = c(NA, 0.79, 0.74, 0.66, 0.59, 0.57),
  hi95 = c(NA, 0.83, 0.78, 0.69, 0.63, 0.61))
MOORE_N_TOTAL <- 654827L   # 原文报告的合计（摘要 + Table 3 一致）
MOORE_D_TOTAL <- 82465L

add("A 原文数值自洽", "Moore2012 类别人数合计",
    if (sum(MOORE_PUB$n) == MOORE_N_TOTAL) "PASS" else "FAIL",
    sprintf("%s vs 原文 %s", format(sum(MOORE_PUB$n), big.mark = ","),
            format(MOORE_N_TOTAL, big.mark = ",")))
add("A 原文数值自洽", "Moore2012 类别死亡数合计",
    if (sum(MOORE_PUB$d) == MOORE_D_TOTAL) "PASS" else "FAIL",
    sprintf("%s vs 原文 %s", format(sum(MOORE_PUB$d), big.mark = ","),
            format(MOORE_D_TOTAL, big.mark = ",")))

# 累计中点百分位（与 rr_table.csv 中 exposure_center 的口径完全一致）
cum <- cumsum(MOORE_PUB$n)
MOORE_PUB[, pct_mid := (c(0, head(cum, -1)) + cum) / 2 / MOORE_N_TOTAL * 100]

got <- dt[source == "Moore2012"][order(exposure_center)]
exp_pct <- MOORE_PUB$pct_mid[-1]          # 去掉参照类（k=1），对应 C2..C6
if (nrow(got) != length(exp_pct)) {
  add("B 百分位复算", "Moore2012 行数", "FAIL",
      sprintf("表内 %d 行，原文非参照类别 %d 个", nrow(got), length(exp_pct)))
} else {
  dif <- abs(got$exposure_center - exp_pct)
  add("B 百分位复算", "Moore2012 各类别百分位",
      if (max(dif) <= TOL_PCT) "PASS" else "FAIL",
      sprintf("最大偏差 %.4f 百分点（容差 %.2f）", max(dif), TOL_PCT))
  add("B 百分位复算", "Moore2012 参照百分位",
      if (abs(unique(got$exposure_ref_center) - MOORE_PUB$pct_mid[1]) <= TOL_PCT)
        "PASS" else "FAIL",
      sprintf("表内 %.3f vs 复算 %.3f（0 MET-h/wk 组的累计中点）",
              unique(got$exposure_ref_center), MOORE_PUB$pct_mid[1]))
  add("B 百分位复算", "Moore2012 HR 与原文一致",
      if (all(abs(got$hr - MOORE_PUB$hr[-1]) < 1e-9)) "PASS" else "FAIL",
      paste(sprintf("%.2f", got$hr), collapse = " / "))

  # 真实的错位风险：CSV 里的百分位排序必须与原文类别**下界**排序一致
  # （若把 Table 3 的行错位对应，HR 会整体平移而百分位仍"看起来合理"）
  ord_ok <- identical(order(got$exposure_center), order(got$exposure_orig_lo))
  add("B 百分位复算", "百分位排序与原文类别边界一致",
      if (ord_ok) "PASS" else "FAIL",
      if (ord_ok) "表内百分位升序 = 原文 exposure_orig_lo 升序"
      else sprintf("排序不一致：percentile %s vs orig_lo %s",
                   paste(got$exposure_center, collapse = ","),
                   paste(got$exposure_orig_lo, collapse = ",")))
}

# ---------------------------------------------------------------------------
# B2. 腕式来源（A3 补齐）—— 原文印刷值逐行核对
#     Sun 2025 (PMID 41201595)：UK Biobank 一般人群腕式，LPA 四分位（Q2/Q3/Q4）
#     Cao 2024 (PMID 39087659)：UK Biobank 既往 CVD 亚组腕式，**仅报最高四分位**
#     腕式证据是"髋 vs 腕"部位对比的唯一来源 → 其数值必须与 Moore 同等严格核对。
# ---------------------------------------------------------------------------
SV_PUB <- data.table(
  k    = 1:4,
  lo   = c(0, 3.9, 5.0, 6.1),          # LPA 类别下界（h/day）
  hi   = c(3.9, 5.0, 6.1, NA),
  hr   = c(1.00, 0.82, 0.75, 0.77),
  lo95 = c(NA, 0.73, 0.66, 0.68),
  hi95 = c(NA, 0.93, 0.85, 0.88))

got_sv <- dt[source == "Sun2025"][order(exposure_center)]
if (nrow(got_sv) != 3L) {
  add("B2 腕式来源", "Sun2025 行数", "FAIL",
      sprintf("表内 %d 行，应为 3（Q2/Q3/Q4，原文只报这 3 个对比）", nrow(got_sv)))
} else {
  add("B2 腕式来源", "Sun2025 HR/CI 与原文一致",
      if (all(abs(got_sv$hr - SV_PUB$hr[-1]) < 1e-9) &&
          all(abs(got_sv$hr_lo - SV_PUB$lo95[-1]) < 1e-9) &&
          all(abs(got_sv$hr_hi - SV_PUB$hi95[-1]) < 1e-9)) "PASS" else "FAIL",
      paste(sprintf("%.2f [%.2f, %.2f]", got_sv$hr, got_sv$hr_lo, got_sv$hr_hi),
            collapse = " / "))
  add("B2 腕式来源", "Sun2025 百分位排序与原文边界一致",
      if (identical(order(got_sv$exposure_center), order(got_sv$exposure_orig_lo)))
        "PASS" else "FAIL",
      sprintf("中心 = %s；原文下界 = %s", paste(got_sv$exposure_center, collapse = ","),
              paste(got_sv$exposure_orig_lo, collapse = ",")))
  add("B2 腕式来源", "Sun2025 参照锚定（最低四分位）",
      if (all(abs(got_sv$exposure_ref_center - 12.5) < 1e-9)) "PASS" else "FAIL",
      sprintf("参照中心 = %.3f（四分位构造应为 12.5）", unique(got_sv$exposure_ref_center)))
  add("B2 腕式来源", "Sun2025 源数据非单调性已登记",
      if (any(grepl("非严格单调", got_sv$notes))) "PASS" else "WARN",
      "原文 Q4(0.77) > Q3(0.75) —— 必须在 notes 写明，否则会被误判为抽取错误")
  add("B2 腕式来源", "Sun2025 佩戴部位与人群标注",
      if (all(as.character(got_sv$wear_site) == "wrist") &&
          all(as.character(got_sv$population) == "general")) "PASS" else "FAIL",
      sprintf("wear_site=%s；population=%s",
              paste(unique(got_sv$wear_site), collapse = ","),
              paste(unique(got_sv$population), collapse = ",")))
}

CAO_PUB <- list(hr = 0.63, lo95 = 0.51, hi95 = 0.79, n = 8024L, d = 691L)
got_ca <- dt[source == "Cao2024"]
if (nrow(got_ca) != 1L) {
  add("B2 腕式来源", "Cao2024 行数", "FAIL",
      sprintf("表内 %d 行，应为 1（原文摘要只报最高四分位）", nrow(got_ca)))
} else {
  add("B2 腕式来源", "Cao2024 HR/CI 与原文一致",
      if (abs(got_ca$hr - CAO_PUB$hr) < 1e-9 && abs(got_ca$hr_lo - CAO_PUB$lo95) < 1e-9 &&
          abs(got_ca$hr_hi - CAO_PUB$hi95) < 1e-9) "PASS" else "FAIL",
      sprintf("%.2f [%.2f, %.2f]", got_ca$hr, got_ca$hr_lo, got_ca$hr_hi))
  add("B2 腕式来源", "Cao2024 样本量与事件数",
      if (got_ca$n_total == CAO_PUB$n && got_ca$n_cases == CAO_PUB$d) "PASS" else "FAIL",
      sprintf("n=%d，死亡=%d（原文 8024 / 691）", got_ca$n_total, got_ca$n_cases))
  add("B2 腕式来源", "Cao2024 临床亚组已隔离",
      if (as.character(got_ca$population) == "clinical_subgroup" &&
          grepl("不入主分析|仅作敏感性", got_ca$notes)) "PASS" else "FAIL",
      sprintf("population=%s → 主分析排除，仅以 spec=sensitivity_all_populations 纳入",
              got_ca$population))
}
add("B2 腕式来源", "腕式来源同一队列（非独立）已登记",
    if (any(grepl("同属 UK Biobank|非独立", dt[grepl("wrist", wear_site), notes]))) "PASS" else "WARN",
    "Sun2025 与 Cao2024 同为 UK Biobank、且 Cao2024 仅 1 行 → 二者不可当作独立证据")

# ---------------------------------------------------------------------------
# C. 结构性检查（全表）
# ---------------------------------------------------------------------------
REQ2 <- c("row_id", "source", "study", "method", "wear_site", "population",
          "metric_definition", "exposure_center", "exposure_ref_center",
          "hr", "hr_lo", "hr_hi", "pmid", "pct_rule")
miss <- setdiff(REQ2, names(dt))
add("C 结构", "必需列齐备", if (!length(miss)) "PASS" else "FAIL",
    if (!length(miss)) sprintf("%d 列均在", length(REQ2)) else paste("缺", paste(miss, collapse = ",")))

bad_ci <- dt[!(hr_lo <= hr & hr <= hr_hi)]
add("C 结构", "HR 落在 95%CI 内", if (!nrow(bad_ci)) "PASS" else "FAIL",
    if (!nrow(bad_ci)) sprintf("%d 行全部满足 hr_lo ≤ hr ≤ hr_hi", nrow(dt))
    else paste(bad_ci$row_id, collapse = ", "))

bad_anc <- dt[exposure_center <= exposure_ref_center]
add("C 结构", "每行严格在自身参照之上", if (!nrow(bad_anc)) "PASS" else "FAIL",
    if (!nrow(bad_anc)) "全部 exposure_center > exposure_ref_center"
    else paste(bad_anc$row_id, collapse = ", "))

dup <- dt[duplicated(paste(source, metric_definition, exposure_center))]
add("C 结构", "同一来源同指标无重复暴露点", if (!nrow(dup)) "PASS" else "FAIL",
    if (!nrow(dup)) "无重复" else paste(dup$row_id, collapse = ", "))

add("C 结构", "百分位推导口径已登记", if (all(nzchar(dt$pct_rule))) "PASS" else "FAIL",
    paste(sprintf("%s×%d", names(table(dt$pct_rule)), as.integer(table(dt$pct_rule))),
          collapse = "; "))

# 近似口径的登记粒度 = **来源级**（同一来源只需在任一行说明一次，
# 且必须留下原始单位与类别边界，否则换算不可审计）
approx_src <- unique(dt[pct_rule == "equal_share_assumption", source])
if (length(approx_src)) {
  ok_one <- vapply(approx_src, function(s)
    any(grepl("假定|等份额", dt[source == s, notes])) &&
      all(nzchar(dt[source == s, exposure_orig_unit])) , logical(1))
  add("C 结构", "近似口径已在表内登记（来源级）",
      if (all(ok_one)) "PASS" else "WARN",
      paste(sprintf("%s：%s", approx_src, ifelse(ok_one, "已登记", "缺说明/缺原始单位")),
            collapse = "; "))
} else {
  add("C 结构", "近似口径已在表内登记（来源级）", "PASS", "无等份额假定来源")
}

# ---------------------------------------------------------------------------
# D. 方向单调性：同一 (研究 × 指标) 内，暴露升高时 HR 不应上升
#    ⚠️ 不能对"任何非单调"一律 FAIL：**源文献自身**可能报告非单调的已校正曲线
#    （如 Sun2025 的 LPA Q4 0.77 高于 Q3 0.75）。判据改为按**回升幅度**分级：
#      回升 ≤ 0.05 → WARN（属源数据特征，非抽取错误；notes 须登记）
#      回升 >  0.05 → FAIL（幅度过大，疑似把类别行错位，须人工复核）
# ---------------------------------------------------------------------------
grp <- dt[, .(n = .N,
              viol = sum(diff(hr) > 1e-9),
              rebound = max(c(0, diff(hr))),
              r = if (.N >= 3) cor(exposure_center, log(hr)) else NA_real_),
          by = .(study, metric_definition)]
reb <- if (nrow(grp)) max(grp$rebound, na.rm = TRUE) else 0
add("D 方向单调", "组内 HR 单调不升",
    if (sum(grp$viol) == 0L) "PASS" else if (reb <= 0.05) "WARN" else "FAIL",
    sprintf("%d 组检查；非单调 %d 处；最大回升 %.3f —— %s", nrow(grp), sum(grp$viol), reb,
            if (sum(grp$viol) == 0L) "全部严格单调"
            else if (reb <= 0.05) "属源文献自身报告的非单调（Sun2025 LPA Q4>Q3），已在 notes 登记"
            else "回升幅度过大 → 疑似抽取错位，必须人工复核"))
add("D 方向单调", "组内剂量-反应为负相关",
    if (all(na.omit(grp$r) < 0)) "PASS" else "WARN",
    paste(sprintf("%s/%s r=%.3f", grp$study, grp$metric_definition,
                  ifelse(is.na(grp$r), NA, grp$r)), collapse = "; "))

# ---------------------------------------------------------------------------
# E. arm 覆盖的信息量检查（按"方法 × 佩戴部位"分轴，而非仅方法）
#    ⛔ 不能用 method 一刀切：全部设备研究若都是髋式，则"设备 vs 自报"的方法效应
#    会把**佩戴部位**差异一并吞掉，使部位效应不可分离。
# ---------------------------------------------------------------------------
armc <- dcast(dt[, .N, by = .(metric_definition, arm)], metric_definition ~ arm,
              value.var = "N", fill = 0L)
dev_cols <- grep("^device", names(armc), value = TRUE)
armc[, n_device := if (length(dev_cols)) rowSums(.SD) else 0L, .SDcols = dev_cols]
if (!"self" %in% names(armc)) armc[, self := 0L]
add("E arm 覆盖", "同指标双方法可比（device vs self）",
    if (any(armc$self > 0 & armc$n_device > 0)) "PASS" else "FAIL",
    paste(sprintf("%s: device %d 行 / self %d 行", armc$metric_definition,
                  armc$n_device, armc$self), collapse = "; "))

site_pair <- if (all(c("device_hip", "device_wrist") %in% names(armc))) {
  armc[device_hip > 0 & device_wrist > 0, metric_definition]
} else character(0)
add("E arm 覆盖", "髋式与腕式双覆盖（部位效应可估）",
    if (length(site_pair)) "PASS" else "WARN",
    if (length(site_pair))
      sprintf("双覆盖指标：%s（其余指标因**文献缺腕式来源**无法分离部位效应）",
              paste(as.character(site_pair), collapse = ", "))
    else "无指标同时含髋式与腕式 → 部位效应不可估，Methods 必须声明该局限")

thin <- armc[n_device > 0 & self > 0 & (self < 3L | n_device < 3L)]
add("E arm 覆盖", "可比指标的行数充足性",
    if (!nrow(thin)) "PASS" else "WARN",
    if (!nrow(thin)) "各双方法可比指标两侧均 ≥3 行"
    else sprintf("行数偏少（斜率稳健性受限）：%s",
                 paste(sprintf("%s(self=%d, device=%d)", thin$metric_definition,
                               thin$self, thin$n_device), collapse = "; ")))

if (any(as.character(dt$population) == "clinical_subgroup"))
  add("E arm 覆盖", "临床亚组未混入主分析",
      "PASS",
      sprintf("%d 行 population=clinical_subgroup（%s）→ 05a 主分析按 population=='general' 过滤，仅在敏感性中纳入",
              sum(dt$population == "clinical_subgroup"),
              paste(unique(dt[population == "clinical_subgroup", source]), collapse = ", ")))

# 独立性与重叠队列的显式提示（不能藏在 notes 里就完事）
add("E arm 覆盖", "设备侧研究独立性",
    "WARN",
    paste0("① Tarp2024（9 队列）与 Ekelund2019（8 队列）来自同一研究组且队列高度重叠；",
           "② Sun2025 与 Cao2024 同属 UK Biobank（后者且仅 1 行）",
           " → 设备侧研究**非独立**，随机效应会低估不确定性；Methods 必须声明并做留一敏感性"))

# ---------------------------------------------------------------------------
# F. 汇总输出
# ---------------------------------------------------------------------------
res <- rbindlist(CHK)
fwrite(res, file.path(DIR_OUT, "QC_bop_table_audit.csv"))

rep_lines <- c(
  "Module 2 输入表审计报告（05b_verify_bop_table.R）",
  sprintf("生成时间（UTC）：%s", format(Sys.time(), tz = "UTC")),
  sprintf("输入：%s（%d 行 / %d 来源 / %d 研究）",
          basename(RR_CSV), nrow(dt), uniqueN(dt$source), uniqueN(dt$study)),
  "",
  sprintf("结论：PASS %d / WARN %d / FAIL %d",
          sum(res$status == "PASS"), sum(res$status == "WARN"), sum(res$status == "FAIL")),
  "", capture.output(print(res[, .(layer, item, status)])), "",
  "—— 方法 × 佩戴部位 归属与斜率（每 1 个百分位点）——",
  capture.output(print(dt[, .(n_rows = .N,
                              slope = round(coef(lm(log(hr) ~ 0 + I(exposure_center - exposure_ref_center))), 5)),
                         by = .(arm, metric_definition)][order(arm, metric_definition)])),
  "",
  "注：slope 为各臂自身的一元过原点斜率（不含随机效应），用于快速目视比较；",
  "    正式估计见 output/Table5_bop_slopes.csv、Table5_bop_method_effect.csv",
  "    与 Table5_bop_wear_site.csv。"
)
dir.create(DIR_LOGS, showWarnings = FALSE, recursive = TRUE)
writeLines(rep_lines, file.path(DIR_LOGS, "bop_table_audit.txt"))

cat(paste(rep_lines, collapse = "\n"), "\n")

if (any(res$status == "FAIL"))
  stop("05b：输入表审计未通过 —— 见 output/QC_bop_table_audit.csv")
cat("\n05b 完成：输入表审计通过。\n")
