# =============================================================================
# 05d_bop_intake_pending.R
# 路径 1「文献传递全文到手 → 补 2-3 行 device_wrist|total_PA」的**待命入表管线**
# -----------------------------------------------------------------------------
# ✅ 2026-10-16 状态更新：两篇全文已由作者直接获取并逐字段核验，**结论是不入池**
#    （两者与池内 Sun2025 同属 UK Biobank 加速度计子队列 → 违反独立性假定）。
#    见 data/bop/20261016_入池裁定_UKB腕式总PA双源.md。
#    台账 5 行已标 `rejected` → 本脚本会输出 SKIP（人工标记不入表），主池保持 22 行。
#    因此**图书馆文献传递与索取邮件均无需再执行**；本脚本转为「裁定留痕 + 回归护栏」：
#    任何未来克隆若误改 intake_status，SKIP 会立即失效、校验表会报 ACCEPT/PENDING → 可被审计发现。
#
# 为什么要有这一步（保留原因）
#   路径 1 曾判定 Ko2025（PMID 40721562）与 Inan-Eroglu2024（PMID 38437645）
#   三条渠道（Europe PMC / Unpaywall / 机构仓储）一致判定**不存在免费合法全文**，
#   须走机构文献传递。全文到手后要做的事很机械，但**极易出错**：
#   填错一个百分位 → 05a 的 arm 效应被污染 → 顺着 05c/95 传到底。
#   所以把「校验 → 备份 → 入表 → 留痕 → 打印后续命令」固化成脚本，
#   默认**只校验不改表**（dry-run），要真入表必须显式设 PA_INTAKE_APPLY=1。
#
# 用法
#   1) 首次运行（或想重置模板）：
#        Rscript 05d_bop_intake_pending.R            # 生成模板 + 校验（只读）
#      模板落在 data/bop/rr_table_pending_intake.csv，逐行填「待确认字段」。
#   2) 全文到手、模板填好后：
#        Rscript 05d_bop_intake_pending.R            # 先看校验报告（output/QC_bop_intake.csv）
#        PA_INTAKE_APPLY=1 Rscript 05d_bop_intake_pending.R   # 校验全绿才真正入表
#   3) 入表后按脚本末尾打印的命令重跑主链。
#
# 硬性校验（任一不过 → 该校验行 REJECT，且 APPLY 模式下拒绝写表）
#   V1  row_id 非空且不与现有表重复
#   V2  05a 要求的 15 个必需列齐备（REQ）
#   V3  HR/CI 合法：0 < hr_lo <= hr <= hr_hi
#   V4  method=="device" 且 wear_site=="wrist"（本路径只补腕式行）
#   V5  exposure_center / exposure_ref_center 非空且 ref < center（offset > 0）
#   V6  population ∈ {"general","clinical_subgroup"}；本轴要求 general
#   V7  intake_axis_confirmed == "total_PA"（按申请单 A1/B2 的结论；不确定则不入表）
#   V8  pmid 与 doi 齐备（可追溯）
#   V9  intake_ref_is_lowest == "Y"（PAF 反事实锚点必须锚在最低类）
#   V10 intake_cutpoints_known == "Y"（05b 会逐项复算百分位）
#
# 输出
#   data/bop/rr_table_pending_intake.csv   模板（首次生成；之后由人工填写）
#   output/QC_bop_intake.csv               逐行逐条校验结果
#   data/bop/rr_table.csv                  仅当 PA_INTAKE_APPLY=1 且全绿时被追加
#   data/bop/rr_table_backup_<RUN_ID>.csv  入表前的自动备份
# =============================================================================

# ---- 统一引导 -----------------------------------------------------------------
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8"))
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
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
pa_log("===== 05d 路径 1 入表待命管线（默认只读校验）=====")

APPLY   <- identical(Sys.getenv("PA_INTAKE_APPLY", unset = "0"), "1")
RR_CSV  <- file.path(DIR_BOP, "rr_table.csv")
PEND    <- file.path(DIR_BOP, "rr_table_pending_intake.csv")
LOG_CSV <- file.path(DIR_BOP, "extraction_log.csv")

REQ <- c("source", "study", "design", "method", "device_type", "wear_site",
         "metric_definition", "exposure_scale", "exposure_center",
         "exposure_ref_center", "outcome", "hr", "hr_lo", "hr_hi", "population")
POP_LEVELS <- c("general", "clinical_subgroup")
BASE_COLS <- c("row_id", "source", "study", "design", "method", "device_type", "wear_site",
               "metric_definition", "exposure_scale", "exposure_center", "exposure_ref_center",
               "exposure_orig_unit", "exposure_orig_lo", "exposure_orig_hi", "category_n",
               "pct_rule", "outcome", "n_total", "n_cases", "hr", "hr_lo", "hr_hi",
               "sex", "mean_age", "followup_y", "region", "population", "pmid", "doi", "notes")
INTAKE_COLS <- c("intake_status", "intake_axis_confirmed", "intake_population",
                 "intake_category", "intake_ref_is_lowest", "intake_cutpoints_known",
                 "intake_independent_of_sun2025", "intake_evidence", "intake_verifier", "intake_date")

# =============================================================================
# 1. 模板：不存在则生成（由 R 生成 → CSV 引号/转义一定合法）
# =============================================================================
if (!file.exists(PEND)) {
  mk <- function(row_id, study, design, dev, metric, cat_n, pct_rule, pop, pmid, doi, notes) {
    d <- as.list(rep(NA_character_, length(BASE_COLS) + length(INTAKE_COLS)))
    names(d) <- c(BASE_COLS, INTAKE_COLS)
    d$row_id <- row_id; d$source <- study; d$study <- study; d$design <- design
    d$method <- "device"; d$device_type <- dev; d$wear_site <- "wrist"
    d$metric_definition <- metric; d$exposure_scale <- "quantile_pct"
    d$outcome <- "all_cause"; d$category_n <- as.character(cat_n)
    d$pct_rule <- "by_construction_equal_share"; d$population <- pop
    d$pmid <- pmid; d$doi <- doi; d$notes <- notes
    d$intake_status <- "pending"
    d$intake_axis_confirmed <- ""      # 只能填 total_PA / MVPA / NA（见申请单 A1、B2）
    d$intake_population <- pop
    d$intake_category <- cat_n
    d$intake_ref_is_lowest <- ""
    d$intake_cutpoints_known <- ""
    d$intake_independent_of_sun2025 <- ""
    d$intake_evidence <- ""            # 例：Table 3, p.2381
    d$intake_verifier <- ""
    d$intake_date <- ""
    as.data.table(d)
  }
  # 2026-10-16 更新：两篇全文已由作者直接获取并逐字段核验（见
  #   data/bop/20261016_入池裁定_UKB腕式总PA双源.md）。
  #   ⚠️ 两者均与池内 Sun2025 同属 UK Biobank 加速度计子队列 → 台账标 rejected（SKIP），
  #      模板仍保留 5 行以便任何全新克隆都能复现这条裁定，而不是直接删掉证据。
  K <- "Ko2025 慢性肾脏病队列（J Nephrol 2025;38(8):2375-2387）★已核验：Axivity AX3 腕式；指标轴=05:00–24:00 平均加速度(mg)（=total_PA）；四分位；完全校正 Model 3。★与 Sun2025 同源 → 不入池"
  I <- "Inan-Eroglu2024 UKB（Cancer Epidemiol Biomarkers Prev 2024;33(8):1028-1036）★已核验：Axivity AX3 腕式；TPA=非久坐总体力活动(min/day)；性别特异三分位；正文 Results 已给边际 HR。★与 Sun2025 同源 → 不入池"
  tpl <- rbindlist(list(
    mk("KO25_wrist_tot_Q2", "Ko2025", "cohort", "Axivity AX3", "total_PA", 4, "", "general", "40721562", "10.1007/s40620-025-02345-y", K),
    mk("KO25_wrist_tot_Q3", "Ko2025", "cohort", "Axivity AX3", "total_PA", 4, "", "general", "40721562", "10.1007/s40620-025-02345-y", K),
    mk("KO25_wrist_tot_Q4", "Ko2025", "cohort", "Axivity AX3", "total_PA", 4, "", "general", "40721562", "10.1007/s40620-025-02345-y", K),
    mk("IE24_wrist_tot_T2", "Inan-Eroglu2024", "cohort", "Axivity AX3", "total_PA", 3, "", "general", "38437645", "10.1158/1055-9965.EPI-23-1185", I),
    mk("IE24_wrist_tot_T3", "Inan-Eroglu2024", "cohort", "Axivity AX3", "total_PA", 3, "", "general", "38437645", "10.1158/1055-9965.EPI-23-1185", I)),
    use.names = TRUE, fill = TRUE)
  fwrite(tpl, PEND, encoding = "UTF-8")
  pa_log("已生成模板：data/bop/rr_table_pending_intake.csv（", nrow(tpl), " 个候选行，全部 status=pending）")
}

P <- fread(PEND, encoding = "UTF-8", fill = TRUE, sep = ",")   # sep 必须显式给，见 06_manifest.R 的说明
for (cc in setdiff(c(BASE_COLS, INTAKE_COLS), names(P))) P[, (cc) := NA_character_]

# =============================================================================
# 2. 逐行逐条校验
# =============================================================================
cur <- if (file.exists(RR_CSV)) fread(RR_CSV, encoding = "UTF-8") else data.table(row_id = character())
num <- function(x) suppressWarnings(as.numeric(x))
chr <- function(x) trimws(as.character(ifelse(is.na(x), "", x)))

res <- rbindlist(lapply(seq_len(nrow(P)), function(i) {
  r <- P[i]
  f <- list()
  add <- function(rule, ok, detail = "") f[[length(f) + 1L]] <<- data.table(
    row_id = chr(r$row_id), rule = rule, pass = isTRUE(ok), detail = detail)

  add("V1 row_id 唯一且非空", nzchar(chr(r$row_id)) && !chr(r$row_id) %in% cur$row_id,
      ifelse(chr(r$row_id) %in% cur$row_id, "与现有表重复", ""))
  miss <- setdiff(REQ, names(P))
  add("V2 必需列齐备", !length(miss), paste(miss, collapse = ","))
  hr <- num(r$hr); lo <- num(r$hr_lo); hi <- num(r$hr_hi)
  add("V3 HR/CI 合法", !is.na(hr) && !is.na(lo) && !is.na(hi) && lo > 0 && lo <= hr && hr <= hi,
      sprintf("hr=%s lo=%s hi=%s", chr(r$hr), chr(r$hr_lo), chr(r$hr_hi)))
  add("V4 method=device & wear_site=wrist",
      chr(r$method) == "device" && chr(r$wear_site) == "wrist",
      paste(chr(r$method), chr(r$wear_site)))
  ec <- num(r$exposure_center); er <- num(r$exposure_ref_center)
  add("V5 暴露中心/参照齐备且 ref<center", !is.na(ec) && !is.na(er) && er < ec,
      sprintf("center=%s ref=%s", chr(r$exposure_center), chr(r$exposure_ref_center)))
  add("V6 population 合法且为 general",
      chr(r$population) %in% POP_LEVELS && chr(r$population) == "general", chr(r$population))
  add("V7 指标轴已确认为 total_PA", chr(r$intake_axis_confirmed) == "total_PA",
      chr(r$intake_axis_confirmed))
  add("V8 pmid 与 doi 齐备", nzchar(chr(r$pmid)) && nzchar(chr(r$doi)),
      paste(chr(r$pmid), chr(r$doi)))
  add("V9 参照为最低类", toupper(chr(r$intake_ref_is_lowest)) == "Y", chr(r$intake_ref_is_lowest))
  add("V10 切点数值已知", toupper(chr(r$intake_cutpoints_known)) == "Y", chr(r$intake_cutpoints_known))
  rbindlist(f)
}))

QC <- res[, .(n_rules = .N, n_pass = sum(pass), all_pass = all(pass)), by = row_id]
QC <- merge(QC, P[, .(row_id = chr(row_id), intake_status = chr(intake_status),
                      axis = chr(intake_axis_confirmed), category = chr(intake_category))],
            by = "row_id", all.x = TRUE)
QC[, verdict := fifelse(intake_status %in% c("rejected","skip"), "SKIP（人工标记不入表）",
                        fifelse(all_pass, "ACCEPT", "PENDING（字段未填齐）"))]
fwrite(QC, file.path(DIR_OUT, "QC_bop_intake.csv"))
QC <- QC[order(row_id)]

cat("\n===== 待入表行校验结果 =====\n"); print(QC)
cat("\n===== 未通过的条目明细（前 30 条）=====\n")
print(head(res[pass == FALSE, .(row_id, rule)], 30))

# =============================================================================
# 3. 入表（默认不执行；必须 PA_INTAKE_APPLY=1 且全绿）
# =============================================================================
acc <- QC[verdict == "ACCEPT", row_id]
pa_log("ACCEPT 行数：", length(acc), "／ 待入表行数：", nrow(QC))

if (!APPLY) {
  cat("\n（dry-run：未改动 rr_table.csv。确认无误后加 PA_INTAKE_APPLY=1 重跑本脚本）\n")
} else if (!length(acc)) {
  pa_log("APPLY 已请求，但没有任何 ACCEPT 行 → 拒绝写表（避免把未核实的 HR 灌进主池）", level = "WARN")
} else {
  bkp <- file.path(DIR_BOP, sprintf("rr_table_backup_%s.csv", Sys.getenv("RUN_ID", "manual")))
  file.copy(RR_CSV, bkp, overwrite = FALSE)
  pa_log("已备份原表 → ", basename(bkp))
  # 只取主表列，按主表列序追加；未填写的字段留空（与主表空字段的表示一致）
  add_rows <- P[chr(row_id) %in% acc]
  add_rows <- add_rows[, BASE_COLS, with = FALSE]
  fwrite(add_rows, RR_CSV, append = TRUE, col.names = FALSE)
  # 抽取台账留痕（幂等：按 row_id 查重）
  # ⚠️ 台账首列是 `date_utc`（不是 row_id），且共有 12 列。**必须按台账自身列名构造**，
  #    否则日期会落到不存在的列上 → 出现整列 NA 的“幽灵行”。
  LOG <- if (file.exists(LOG_CSV)) fread(LOG_CSV, encoding = "UTF-8", fill = TRUE, sep = ",") else NULL
  SRC <- P[chr(row_id) %in% acc]
  lg  <- data.table(
    date_utc       = format(Sys.time(), "%Y-%m-%d", tz = "UTC"),
    row_id         = acc,
    source         = SRC$study,
    paper_table    = paste0("全文（文献传递）：", chr(SRC$intake_evidence)),
    model_adjustment = "",
    ci_type        = "95CI",
    referent_group = "最低类（全文确认）",
    converted      = "no",
    extracted_by   = chr(SRC$intake_verifier),
    verified_by    = "待人工复核",
    pct_derivation = "按全文切点数值推算（05b 将逐项复算）",
    note           = "路径 1 入表：见 data/bop/文献传递申请单_腕式总量来源.md 的 A1–A6 / B1–B6 核对项")
  if (!is.null(LOG)) {
    for (cc in setdiff(names(LOG), names(lg))) lg[, (cc) := NA_character_]
    lg <- lg[, names(LOG), with = FALSE]
    lg <- lg[!as.character(row_id) %in% as.character(LOG$row_id)]
  }
  if (nrow(lg))
    fwrite(lg, LOG_CSV, append = file.exists(LOG_CSV), col.names = !file.exists(LOG_CSV))
  pa_log("已入表 ", nrow(add_rows), " 行；台账追加 ", nrow(lg), " 条")
}

# =============================================================================
# 4. 入表后必须重跑的主链（顺序不可换）
# =============================================================================
cat("\n===== 入表后请按此顺序重跑（顺序不可换）=====\n")
cat("  cd ", normalizePath(if (dir.exists("code")) "code" else "."), "\n", sep = "")
cat("  RS=\"D:/Program Files/R/R-4.5.2/bin/Rscript.exe\"\n")
cat("  # 1) 输入表审计（百分位复算 + 方向/结构检查）\n")
cat("  \"$RS\" 05b_verify_bop_table.R\n")
cat("  # 2) 重跑池化（arm 效应会吸收新行；观察 wear_site 后验是否更新）\n")
cat("  \"$RS\" 05a_module2_bop.R\n")
cat("  # 3) NHANES 敏感性档（自动重读新池）\n")
cat("  \"$RS\" 05c_module2_nhanes_site_sensitivity.R\n")
cat("  # 4) 部位效应敏感性矩阵 + 文献侧对照（自动重读新池）\n")
cat("  \"$RS\" 04c_site_wear_sensitivity.R ; \"$RS\" 04d_lit_site_contrast.R\n")
cat("  # 5) Module 3 PAF（默认路径会自动用新的 bop_rr_draws.rds）\n")
cat("  \"$RS\" 95_module3_paf.R ; \"$RS\" 95b_paf_impact_compare.R\n")
cat("  # 6) 清单 + 复现性核验（连跑两遍让 E 层有可比基准）\n")
cat("  \"$RS\" 00_run_all.R --only 06_manifest,98_verify_reproducibility\n")
cat("  \"$RS\" 00_run_all.R --only 06_manifest,98_verify_reproducibility\n")

pa_log("05d 完成（APPLY=", APPLY, "；ACCEPT=", length(acc), " 行）")
