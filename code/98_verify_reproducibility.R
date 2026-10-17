# =============================================================================
# 98_verify_reproducibility.R  —  可复现性核验
#
# 用途：任何人在任何机器上拿到本项目后，运行本脚本即可回答一个问题：
#       "我手上的这套数据与代码，能不能复现出与作者一致的结果？"
#
# 核验五个层面：
#   A 环境     R 版本 / locale（中文路径可用性）/ 必需包
#   B 原始数据 是否齐备，且 SHA-256 是否与 data/sources/checksums.csv 固化值一致
#   C 中间数据 关键中间产物是否存在（说明流程确实跑过）
#   D 交付产出 图表/表格是否齐备，且字节数是否与 output/manifest.csv 一致
#   E 跨运行   本次 manifest 与历史运行 manifest 的产物指纹是否一致（真·复现判定）
#
# 输出：
#   output/QC_98_checks.csv           逐项核验结果（item, layer, status, detail）
#   output/REPRODUCIBILITY_REPORT.txt 人可读总报告（含总体结论 PASS/WARN/FAIL）
# 退出码：0 = PASS/WARN，1 = FAIL（便于接入 CI）
# =============================================================================

# ---- 统一引导（勿改）--------------------------------------------------------
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
pa_log("===== 98 可复现性核验 =====")

CHECKS <- list()
add <- function(layer, item, status, detail = "") {
  CHECKS[[length(CHECKS) + 1L]] <<- data.table(layer = layer, item = item,
                                               status = status, detail = detail)
  invisible(NULL)
}

# =============================================================================
# A. 环境
# =============================================================================
add("A 环境", "R 版本", "INFO", paste0(R.version.string, "  (锁定基线: 4.5.2)"))
lc <- Sys.getlocale("LC_CTYPE")
if (grepl("UTF-8|utf8|936", lc)) {
  add("A 环境", "locale (LC_CTYPE)", "PASS", lc)
} else {
  add("A 环境", "locale (LC_CTYPE)", "FAIL",
      paste0(lc, " — 非 UTF-8，中文路径不可用；请见 data/README.md 的环境章节"))
}
miss_req <- setdiff(PA$pkgs_required, rownames(installed.packages()))
if (!length(miss_req)) {
  add("A 环境", "必需 R 包", "PASS", paste(PA$pkgs_required, collapse = ", "))
} else {
  add("A 环境", "必需 R 包", "FAIL", paste0("缺失: ", paste(miss_req, collapse = ", ")))
}
add("A 环境", "随机种子", "INFO", paste0("PA_SEED = ", PA_SEED,
                                          "；RNGkind = ", paste(RNGkind(), collapse = "/")))
add("A 环境", "SHA-256 支持", if (requireNamespace("digest", quietly = TRUE)) "PASS" else "WARN",
    if (requireNamespace("digest", quietly = TRUE)) "digest 已安装" else "退回 MD5（强度较低）")
# Module 2 合成引擎的**可追溯性**：默认真贝叶斯（brms/rstan/StanHeaders）需可复现地登记版本；
# 三者缺一 → 05a 静默回退 metafor(REML)，数值口径不同 → 此处必须显式报警而非默认放行。
.bayes_pkgs <- c("brms", "rstan", "StanHeaders")
.bayes_have <- vapply(.bayes_pkgs, function(p) requireNamespace(p, quietly = TRUE), TRUE)
if (all(.bayes_have)) {
  add("A 环境", "Module 2 合成引擎", "PASS",
      paste0("真贝叶斯可用：",
             paste(sprintf("%s %s", .bayes_pkgs,
                           vapply(.bayes_pkgs, function(p) as.character(packageVersion(p)), "")),
                   collapse = " / "),
             "；Rtools45=", ifelse(nzchar(Sys.getenv("RTOOLS45_HOME")),
                                  Sys.getenv("RTOOLS45_HOME"), "未设(须为 c:/rtools45 或显式配置)")))
} else {
  add("A 环境", "Module 2 合成引擎", "WARN",
      paste0("缺 ", paste(.bayes_pkgs[!.bayes_have], collapse = ", "),
             " → 05a 将回退 metafor(REML) 参数自助，与主分析口径不同；",
             "如为有意回退请设 PA_BOP_ENGINE=metafor"))
}

# =============================================================================
# B. 原始数据 + 指纹一致性
# =============================================================================
KEY_RAW <- c("DEMO_G.xpt", "DEMO_H.xpt", "PAXDAY_G.xpt", "PAXDAY_H.xpt", "PAQ_G.xpt", "PAQ_H.xpt")
CHK_CSV <- file.path(DIR_SOURCES, "checksums.csv")

if (file.exists(CHK_CSV)) {
  chk <- fread(CHK_CSV)
  add("B 原始数据", "指纹台账存在", "PASS", paste0(nrow(chk), " 条记录"))
  for (i in seq_len(nrow(chk))) {
    p <- file.path(DIR_RAW, chk$filename[i])
    if (!file.exists(p)) {
      add("B 原始数据", chk$filename[i], "FAIL", "文件缺失")
      next
    }
    h <- pa_hash(p, algo = "sha256")
    if (is.na(h)) { add("B 原始数据", chk$filename[i], "WARN", "无法计算指纹"); next }
    if (!is.na(chk$hash[i]) && identical(h, chk$hash[i])) {
      add("B 原始数据", chk$filename[i], "PASS",
          paste0(format(file.size(p) / 1024, digits = 5), " KB  指纹一致"))
    } else {
      add("B 原始数据", chk$filename[i], "FAIL",
          paste0("指纹不一致：固化 ", substr(chk$hash[i], 1, 12), " vs 实测 ", substr(h, 1, 12)))
    }
  }
} else {
  add("B 原始数据", "指纹台账", "FAIL",
      "data/sources/checksums.csv 不存在：尚未运行 01，或原始数据未固化")
}
for (f in KEY_RAW) {
  if (!file.exists(file.path(DIR_RAW, f)))
    add("B 原始数据", paste0("关键文件 ", f), "FAIL", "缺失，主流程将降级")
}

# =============================================================================
# C. 中间数据
# =============================================================================
KEY_DERIV <- c("accel_daily.rds", "analytic.rds", "MORT_2011_2014.rds",
               # 佩戴部位效应子分析（03b）
               "pam_2003_2006.rds", "MORT_2003_2006.rds",
               # 部位效应矛盾裁决：wear 规则 / 判据全谱（03c/03d）
               "pam_hip_wearvariants.rds", "wrist_criterion_variants.rds")
for (f in KEY_DERIV) {
  p <- file.path(DIR_DERIV, f)
  if (file.exists(p)) {
    n <- tryCatch({ x <- readRDS(p); if (is.data.frame(x)) nrow(x) else NA_integer_ },
                  error = function(e) NA_integer_)
    add("C 中间数据", f, "PASS", paste0("存在；行数 ", n))
  } else {
    add("C 中间数据", f, "FAIL", "缺失：对应步骤（02/03）未成功运行")
  }
}

# -----------------------------------------------------------------------------
# C2. Module 2 合成门禁（QC_bop_status.csv）——任何 FAIL/MISSING 都不得放行
#     动机（2026-10-16）：Module 2 的引擎与后验收敛状态（含曲率模型的 Rhat）
#     此前只写在 QC_bop_status.csv 里，98 **完全不读它** → 引擎静默回退 metafor、
#     或曲率模型 Rhat = 3.61（未收敛）时，整链核验仍会「全绿」。此处补上这道关。
# -----------------------------------------------------------------------------
QC_BOP <- file.path(DIR_OUT, "QC_bop_status.csv")
if (file.exists(QC_BOP)) {
  qb <- tryCatch(fread(QC_BOP), error = function(e) NULL)
  if (is.null(qb) || !all(c("item", "status", "detail") %in% names(qb))) {
    add("C 中间数据", "Module 2 门禁", "WARN",
        "QC_bop_status.csv 存在但无法解析（缺 item/status/detail 列）")
  } else {
    .st  <- toupper(as.character(qb$status))
    n_bad <- sum(.st %in% c("FAIL", "MISSING"), na.rm = TRUE)
    add("C 中间数据", "Module 2 门禁", if (n_bad == 0L) "PASS" else "FAIL",
        sprintf("QC_bop_status.csv：%d 项，FAIL/MISSING %d / WARN %d%s",
                nrow(qb), n_bad, sum(.st == "WARN", na.rm = TRUE),
                if (n_bad) paste0("；异常项：", paste(qb$item[.st %in% c("FAIL", "MISSING")],
                                                    collapse = ", ")) else ""))
    # 引擎一致性：A 层若判定真贝叶斯可用，BoP 主分析就必须真的走贝叶斯（防静默回退）
    #   ⚠️ 判据**不能**只看「合成引擎」行的文本 —— 那一行是**版本与配置说明**，本身不含
    #      "bayesian" 字样；引擎名的权威落点是「拟合」行的 fit_mode
    #      （bayesian_multilevel_meta_regression(...) vs multilevel_random_effects(metafor REML)）。
    #      2026-10-16 实测：贝叶斯已生效却被本项判 FAIL —— 是**本检查自身的 bug**，非数据问题。
    #      此处改为在「拟合」「合成引擎」两行上联合判定，并把证据写进 detail。
    .eng <- qb$detail[qb$item == "合成引擎"]
    .fit <- qb$detail[qb$item == "拟合"]
    .is_bayes <- (length(.fit) && grepl("bayesian", .fit[1], ignore.case = TRUE)) ||
                 (length(.eng) && grepl("brms",     .eng[1], ignore.case = TRUE))
    .evi <- if (length(.fit)) substr(.fit[1], 1, 90) else "（缺「拟合」行）"
    if (length(.eng) || length(.fit)) {
      if (all(.bayes_have) && !.is_bayes) {
        add("C 中间数据", "Module 2 引擎一致", "FAIL",
            paste0("A 层检测到 brms/rstan 可用，但 BoP 实际未走贝叶斯：", .evi))
      } else {
        add("C 中间数据", "Module 2 引擎一致", "PASS",
            paste0("拟合 = ", .evi,
                   if (length(.eng)) paste0("；合成引擎 = ", substr(.eng[1], 1, 70)) else ""))
      }
    }
  }
} else {
  add("C 中间数据", "Module 2 门禁", "FAIL",
      "缺少 output/QC_bop_status.csv：05a_module2_bop.R 未运行或失败")
}

# =============================================================================
# D. 交付产出 + 与 manifest 的一致性
# =============================================================================
KEY_OUT <- c("Fig3_dose_response.png", "Fig3_dose_response.pdf",
             "rr_curves.csv", "Table2_quartile_HK.csv", "Table3_calibration.txt",
             # 04 的参照锚点台账（2026-10-15：锚点由占位分位改为 TMREL 设备等效绝对锚点）
             "Table2_reference_anchor.csv",
             # Fig 3 六面板投稿版（08c；镜像至 output/。PDF 时间戳由 E 层豁免，PNG 承担一致性）
             "Fig3_reference_points.csv",
             "Fig3a_mims_all_cause.pdf", "Fig3a_mims_all_cause.png",
             "Fig3b_mims_cvd.pdf", "Fig3b_mims_cvd.png",
             "Fig3c_peak30_all_cause.pdf", "Fig3c_peak30_all_cause.png",
             "Fig3d_peak30_cvd.pdf", "Fig3d_peak30_cvd.png",
             "Fig3e_mvpa_all_cause.pdf", "Fig3e_mvpa_all_cause.png",
             "Fig3f_mvpa_cvd.pdf", "Fig3f_mvpa_cvd.png",
             # 髋式强度维度曲线网格 / 四分位 / 每 IQR（04e）
             "Table11_pam_intensity_RR.csv", "Table11_pam_intensity_quartiles.csv",
             "Table11_pam_intensity_per_IQR.csv", "QC_pam_intensity_fit.csv",
             # Module 3 PAF 预览（95_module3_paf.R）：RR 来源 = Module 2 device_pooled 后验
             "PREVIEW_module3_totals.csv", "PREVIEW_module3_by_cause.csv",
             "PREVIEW_module3_exposure_diag.csv", "PREVIEW_module3_rr_source_compare.csv",
             "PREVIEW_module3_rr_bridge.csv",
             # Module 3 主分析通道（PA_CV_MODE=s1p：S1′ 查表 CV + 人口加权）
             "PREVIEW_module3_s1p_totals.csv", "PREVIEW_module3_s1p_by_cause.csv",
             "PREVIEW_module3_s1p_exposure_diag.csv",
             "PREVIEW_module3_s1p_rr_source_compare.csv", "PREVIEW_module3_s1p_rr_bridge.csv",
             # SDI 锚点（96b_sdi_anchor.R；2026-10-15）：Fig 5(b) 分层 + Table 4 排序的官方输入
             "Table14_sdi_anchor.csv",
             # Module 3 逐国版（95c_module3_bycountry.R；2026-10-15）→ Fig 5(b)(c) + Table 4 逐国底表
             "M3_BYCOUNTRY_totals.csv", "M3_BYCOUNTRY_by_cause.csv",
             "M3_BYCOUNTRY_exposure_diag.csv", "M3_BYCOUNTRY_by_sdi.csv",
             # Table 4 逐国补充表（09_tables.R，按 SDI 排序，410 行）
             "TableS4_burden_bycountry_manuscript.csv",
             # S1′ 的 SD–mean 关系（05 Part A5）与人口加权（Part A6）
             "Table3_sd_mean_relation_coefs.csv", "Table3_sd_mean_relation_cells.csv",
             "Table3_sd_mean_age_map.csv",
             # Module 3 情景表 + 稳健性 + 国别同质化（97_m3_scenarios.R，2026-10-15 N1/N2/N3 落地）
             "Table4_m3_decomp.csv", "Table5_m1_vs_m2.csv",
             "Table9_m3_scenario_summary.csv",
             "Table10_m3_robustness.csv", "Table10_m3_country_homogeneity.csv",
             # Fig 5(d) 口径分解瀑布图（07_fig5d_waterfall.R；PDF 时间戳由 E 层豁免，PNG 承担一致性）
             "Fig5d_waterfall_decomposition.pdf", "Fig5d_waterfall_decomposition.png",
             "Fig5d_waterfall_by_region.pdf", "Fig5d_waterfall_by_region.png",
             "Fig5d_waterfall_data.csv", "Fig5d_waterfall_caption.md",
             # 佩戴部位效应子分析（03b/04b/01c）
             "Table6_nhanes_hip_wrist_RR.csv", "Table6_pam_percentile_map.csv",
             "QC_pam_site_fit.csv", "QC_pam_2003_2006.csv", "QC_paxinten_vs_raw.csv",
             # 路径 2 收尾（05c）：NHANES 两臂接入 BoP 池的受控敏感性
             "Table7_bop_nhanes_site_sensitivity.csv", "Table7_bop_nhanes_pooled_curve.csv",
             "Table7_bop_nhanes_weight_share.csv", "QC_bop_nhanes_sensitivity.csv",
             # 部位效应矛盾裁决（03c/03d/04c/04d）：wear 规则 × 判据全谱
             "Table8_hip_wear_rule_curves.csv", "Table8_wrist_criterion_curves.csv",
             "Table8_site_ratio_matrix.csv", "Table8_site_ratio_summary.csv",
             "Table8_metric_axis_check.csv",
             "QC_hip_wear_rules.csv", "QC_hip_wear_rules_analytic.csv",
             "QC_hip_wear_R0_equivalence.csv",
             "QC_wrist_criteria.csv", "QC_wrist_criteria_analytic.csv",
             "QC_wrist_day_qc.csv", "QC_wrist_C0_equivalence.csv",
             "QC_site_wear_sensitivity.csv", "QC_site_R0C0_equivalence.csv",
             # 文献侧可分解性与相容性（04d）
             "Table8_lit_site_contrast.csv", "Table8_lit_site_compatibility.csv",
             "Table8_lit_site_leverage.csv", "Table8_lit_design_incompat.csv",
             "QC_lit_site_contrast.txt",
             # 指标轴错配的量化许可（04d §2b，2026-10-16 metric-aware 改造）
             "Table8_lit_site_metric_license.csv",
             # 文献侧部位效应的指标稳健性：total_PA 外部锚定 + 与 NHANES 的**同指标**对照
             #   （04f_lit_site_anchor.R，2026-10-16 由 tools/site_anchor_totalPA.R 提升为正式步骤）
             "Table8b_site_anchor_totalPA.csv", "Table8b_site_anchor_slopes.csv",
             "Table8b_site_metric_compare.csv", "Table8b_site_anchor_vs_nhanes.csv",
             "QC_site_anchor_totalPA.txt", "QC_site_anchor_license_xcheck.csv",
             # 路径 1 待命入表管线（05d，默认 dry-run）
             "QC_bop_intake.csv",
             # Module 2 留一法（05e）与 E-value 敏感性（05f）
             "Table12_bop_loo_RR.csv", "Table12_m3_loo_paf.csv", "Table13_evalues.csv",
             # Fig 6 敏感性三面板（08f；PDF 时间戳由 E 层豁免，PNG 承担一致性）
             "Fig6a_scenario_forest.pdf", "Fig6a_scenario_forest.png",
             "Fig6b_leave_one_out.pdf", "Fig6b_leave_one_out.png",
             "Fig6c_evalue.pdf", "Fig6c_evalue.png",
             # 图注 / 表注（10_captions.R；中英双语，数值全部动态取自 output/ 产物）
             "CAPTIONS_figures_tables.md")
MANIFEST_CSV <- file.path(DIR_OUT, "manifest.csv")
for (f in KEY_OUT) {
  p <- file.path(DIR_OUT, f)
  add("D 交付产出", f, if (file.exists(p)) "PASS" else "FAIL",
      if (file.exists(p)) paste0(format(file.size(p) / 1024, digits = 5), " KB") else "缺失")
}

# --- 按需（opt-in）敏感性产物：存在则 PASS，不存在则 INFO（不影响总体判定）---
# 由 code/95b_paf_impact_compare.R 产出（需把 95 跑两遍，约 +12~24 min）。
# ⚠️ 刻意不放进 KEY_OUT：否则「只跑 00_run_all.R」的全新克隆会因缺这些文件而 FAIL。
KEY_OUT_OPT <- c("Table7_bop_nhanes_paf_impact.csv",
                 "Table7_bop_nhanes_paf_impact_by_cause.csv",
                 "QC_95_env_override_invariance.csv",
                 # ★ 2026-10-16 更正：B 档的真实前缀是 PREVIEW_NHANES_**s1p**_（95b 的 P_B）。
                 #   原先此处写的是 PREVIEW_NHANES_totals/by_cause（无 s1p）—— 那是 10-12 旧命名
                 #   留下的**陈旧孤儿**，早已无人再生成；于是 D 层一直在给两个死文件盖章 PASS，
                 #   而**真正的 B 档产物从未被 D 层检查**。属与 B3 同类的"指向过时产物名"缺陷。
                 "PREVIEW_NHANES_s1p_totals.csv", "PREVIEW_NHANES_s1p_by_cause.csv",
                 "PREVIEW_NHANES_s1p_exposure_diag.csv",
                 "PREVIEW_NHANES_s1p_rr_source_compare.csv", "PREVIEW_NHANES_s1p_rr_bridge.csv",
                 # 行为不变性证据：仅在 PA_VERIFY_DEFAULT=1 时由 95b 生成（确实可选）
                 "VERIFY_default_totals.csv", "VERIFY_default_by_cause.csv")
for (f in KEY_OUT_OPT) {
  p <- file.path(DIR_OUT, f)
  add("D 交付产出（按需敏感性）", f, if (file.exists(p)) "PASS" else "INFO",
      if (file.exists(p)) paste0(format(file.size(p) / 1024, digits = 5), " KB")
      else "未生成（如需：cd code && Rscript 95b_paf_impact_compare.R）")
}

# 自指元产物：内容含运行 ID / 生成时间，或本身是核验脚本的本次输出，
# 每次运行必然变化 —— D 层（字节一致性）与 E 层（跨运行指纹）共用同一豁免清单。
# ⚠️ 2026-10-12 修复：D 层原先未豁免这些文件，导致一旦 manifest 内容长度变化
#    （例如新增 DRYRUN 产物、新增 GBD 分片），manifest_summary.txt 就会报 1 个假漂移。
META_SELFREF <- c("manifest_summary.txt", "REPRODUCIBILITY_REPORT.txt",
                  "QC_98_checks.csv", "manifest.csv")

if (file.exists(MANIFEST_CSV)) {
  mf <- fread(MANIFEST_CSV)
  add("D 交付产出", "manifest.csv", "PASS", paste0(nrow(mf), " 条记录"))
  drift <- 0L; skipped <- 0L
  for (i in seq_len(nrow(mf))) {
    if (basename(mf$rel_path[i]) %in% META_SELFREF) { skipped <- skipped + 1L; next }
    p <- file.path(if (mf$scope[i] == "raw") DIR_RAW
                   else if (mf$scope[i] == "derived") DIR_DERIV
                   else if (mf$scope[i] == "gbd") DIR_GBD
                   else if (mf$scope[i] == "bop") DIR_BOP else DIR_OUT,
                   mf$rel_path[i])
    if (!file.exists(p)) { drift <- drift + 1L; next }
    if (!is.na(mf$bytes[i]) && file.size(p) != mf$bytes[i]) drift <- drift + 1L
  }
  add("D 交付产出", "manifest 字节一致性",
      if (drift == 0L) "PASS" else "WARN",
      sprintf("%s（已按自指规则排除元产物 %d 个）",
              if (drift == 0L) "全部与清单一致"
              else paste0(drift, " 个文件与清单不符（可能已被手动编辑）"),
              skipped))
} else {
  add("D 交付产出", "manifest.csv", "WARN", "尚未生成，请先运行 06_manifest.R")
}

# =============================================================================
# E. 跨运行复现判定（本次 vs 历史）
# =============================================================================
# ★ 自指防护（2026-10-16 实测新增）：
#   06_manifest.R 会把 output/manifest.csv **原样拷进** logs/<RUN_ID>/manifest.csv。
#   因此若本次运行**未包含** 06_manifest.R（例如 `--only 98_verify_reproducibility`
#   单跑核验），output/manifest.csv 根本没被重算 → 它与"最近一次历史 manifest"
#   （即上一次 run 结束时的同一份拷贝）**逐字节相同** → 得到 313/0 的**假绿 PASS**，
#   反而把真实的跨运行差异全部掩盖。故：只有本次确实重算过产物清单，才做跨运行判定。
MF_REGENERATED <- file.exists(file.path(PA_RUN_DIR, "step_06_manifest.log"))
hist_mf <- list.files(DIR_LOGS, pattern = "^manifest\\.csv$", recursive = TRUE,
                      full.names = TRUE)
hist_mf <- hist_mf[normalizePath(dirname(hist_mf)) != normalizePath(PA_RUN_DIR)]
if (MF_REGENERATED && file.exists(MANIFEST_CSV) && length(hist_mf)) {
  # 取最近一次历史
  hm <- hist_mf[which.max(file.info(hist_mf)$mtime)]
  prev <- fread(hm); curr <- fread(MANIFEST_CSV)
  # 旧版 manifest 没有 content_hash 列（2026-10-15 引入，见 06 的 content_fingerprint 注释）
  if (!"content_hash" %in% names(prev)) prev[, content_hash := NA_character_]
  if (!"content_hash" %in% names(curr)) curr[, content_hash := NA_character_]
  cmp <- merge(prev[, .(rel_path, scope, hash_prev = hash, bytes_prev = bytes,
                        ch_prev = content_hash)],
               curr[, .(rel_path, scope, hash_now = hash, bytes_now = bytes,
                        ch_now = content_hash)],
               by = c("rel_path", "scope"), all = TRUE)
  same <- cmp[!is.na(hash_prev) & !is.na(hash_now) & hash_prev == hash_now]
  diff <- cmp[!is.na(hash_prev) & !is.na(hash_now) & hash_prev != hash_now]
  # 豁免四类"必然不同、且不反映数据/代码漂移"的产物：
  #   ① PDF：内嵌创建时间戳，逐字节必不同（内容一致性由同名 PNG 承担）；
  #   ② 元产物：manifest_summary.txt 含生成时间与运行 ID；
  #             REPRODUCIBILITY_REPORT.txt 与 QC_98_checks.csv 是本次比对**自身的输出**（自指）。
  #   ③ 文档（.md）：GBD 下载指南 / bop README 等是**人工维护的说明文件**，
  #      随认知更新而改是预期行为，不应报为"数据漂移"。
  #   ④ RDS **内容指纹一致**的（2026-10-15 新增）：.rds 的字节哈希随解析期 LC_CTYPE
  #      变化（见 06 的 content_fingerprint 注释）；若归一化内容指纹一致，
  #      说明数值与字符串内容逐位相同，仅序列化编码标记不同 → 不算漂移。
  #      旧 manifest 无 content_hash（NA）时退回原行为（仍报差异，供人工确认）。
  #      注意：QC_01_fetch_report.csv **不在**豁免内——它反映数据获取的真实状态，
  #            其变化是需要人工确认的信号（例如新增了 GBD 文件）。
  #   META_SELFREF 已在 D 层统一声明（D 层与 E 层共用一个豁免清单）。
  # 注意：此处必须写 diff$rel_path —— rel_path 是 cmp 的列名，
  # 只在 data.table 的 `[` 内才被解析为变量，函数体顶层直接引用会 object not found。
  is_pdf   <- grepl("\\.pdf$", diff$rel_path)
  is_meta  <- basename(diff$rel_path) %in% META_SELFREF
  # ★ 文档豁免只限【人工维护】的说明文件（scope = bop / gbd 下的 .md）。
  #   2026-10-16 收窄：output/ 下的 .md 是**流水线产物**（CAPTIONS_figures_tables.md 由 10 生成、
  #   Fig5d_waterfall_caption.md 由 07 生成），随数据漂移而变是**必须被看见**的信号，
  #   若一律按 .md 豁免，则图注文档改了而 E 层仍报 PASS —— 属漏报。
  is_doc   <- grepl("\\.md$", diff$rel_path, ignore.case = TRUE) & diff$scope != "output"
  is_rds_ok <- grepl("\\.rds$", diff$rel_path) &
               !is.na(diff$ch_prev) & !is.na(diff$ch_now) & diff$ch_prev == diff$ch_now
  pdf_diff   <- diff[is_pdf]
  meta_diff  <- diff[is_meta]
  doc_diff   <- diff[is_doc & !is_pdf & !is_meta]
  rds_diff   <- diff[is_rds_ok & !is_pdf & !is_meta & !is_doc]
  diff <- diff[!is_pdf & !is_meta & !is_doc & !is_rds_ok]
  newf <- cmp[is.na(hash_prev)]
  gone <- cmp[is.na(hash_now)]
  add("E 跨运行", "产物指纹比对",
      if (nrow(diff) == 0L) "PASS" else "WARN",
      sprintf(paste0("对照 %s：一致 %d，不一致 %d；已豁免预期差异 %d",
                     "（PDF 时间戳 %d + 元产物自指 %d + 文档 %d + RDS 内容一致 %d）；",
                     "新增 %d，消失 %d"),
              basename(dirname(hm)), nrow(same), nrow(diff),
              nrow(pdf_diff) + nrow(meta_diff) + nrow(doc_diff) + nrow(rds_diff),
              nrow(pdf_diff), nrow(meta_diff), nrow(doc_diff), nrow(rds_diff),
              nrow(newf), nrow(gone)))
  if (nrow(diff)) {
    # 展示上限 40：健康运行下 diff 为空，不会占篇幅；出问题时宁可多列（原上限 10 会
    # 静默漏列，例如 2026-10-16 那次实测 15 项差异只列了 10 项 → 违反可审计要求）。
    CAP <- 40L
    for (k in seq_len(min(nrow(diff), CAP)))
      add("E 跨运行", paste0("差异 ", diff$rel_path[k]), "WARN",
          paste0(substr(diff$hash_prev[k], 1, 10), " -> ", substr(diff$hash_now[k], 1, 10)))
    if (nrow(diff) > CAP)
      add("E 跨运行", "差异（其余未列出）", "WARN",
          sprintf("共 %d 项不一致，上方仅列前 %d 项", nrow(diff), CAP))
  }
} else {
  if (!MF_REGENERATED) {
    add("E 跨运行", "产物指纹比对", "INFO",
        paste0("本次运行未包含 06_manifest.R（产物清单未重算），跨运行判定自动跳过 —— ",
               "否则会与上一次 run 的同一份清单逐字节相同而给出假绿 PASS。",
               "请运行完整链（或至少 06_manifest.R → 98）后再判定。"))
  } else {
    add("E 跨运行", "产物指纹比对", "INFO",
        "无历史 manifest 可比对；连续运行两次 00_run_all.R 后本项即生效")
  }
}

# =============================================================================
# 汇总
# =============================================================================
res <- rbindlist(CHECKS)
fwrite(res, file.path(DIR_OUT, "QC_98_checks.csv"))

n_fail <- sum(res$status == "FAIL"); n_warn <- sum(res$status == "WARN")
n_pass <- sum(res$status == "PASS"); n_info <- sum(res$status == "INFO")
verdict <- if (n_fail > 0) "FAIL" else if (n_warn > 0) "PASS (有警告)" else "PASS"

rpt <- file.path(DIR_OUT, "REPRODUCIBILITY_REPORT.txt")
sink(rpt)
cat("========================================================================\n")
cat(" 可复现性核验报告\n")
cat("========================================================================\n")
cat("生成时间 :", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("运行 ID  :", PA_RUN_ID, "\n")
cat("项目根   :", PA_ROOT, "\n")
cat("总体结论 :", verdict, "\n")
cat(sprintf("统计     : PASS %d / WARN %d / FAIL %d / INFO %d （共 %d 项）\n\n",
            n_pass, n_warn, n_fail, n_info, nrow(res)))
cat("------------------------------------------------------------------------\n")
for (ly in unique(res$layer)) {
  cat("\n【", ly, "】\n", sep = "")
  sub <- res[layer == ly]
  for (i in seq_len(nrow(sub)))
    cat(sprintf("  [%-4s] %-38s %s\n", sub$status[i], sub$item[i], sub$detail[i]))
}
cat("\n------------------------------------------------------------------------\n")
cat("判据说明：\n")
cat("  PASS  该项通过\n")
cat("  WARN  不阻断，但需人工确认（如指纹漂移、清单字节不符）\n")
cat("  FAIL  阻断：原始数据缺失/指纹不符/必需包缺失/中文路径不可用\n")
cat("  INFO  仅记录，不参与判定\n")
cat("\n复现判定要点：B 层全部 PASS 表示你手上的原始数据与作者完全一致；\n")
cat("E 层 PASS 表示在相同原始数据与代码下，产物指纹可逐字节复现。\n")
sink()

pa_log("98 完成：总体结论 = ", verdict, "（PASS ", n_pass, " / WARN ", n_warn,
       " / FAIL ", n_fail, "）")
pa_log("报告 -> output/REPRODUCIBILITY_REPORT.txt")
print(res[, .N, by = .(layer, status)])

if (n_fail > 0L) quit(status = 1L)
