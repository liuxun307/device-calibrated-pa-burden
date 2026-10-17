# =============================================================================
# 96_gbd_download_plan.R
# GBD Results 工具「下载计划」复算器 + 已下载分片核验器（零依赖，可单独运行）
#
# 用途：
#   (1) plan  给定维度取值 → 复算行数 → 判定是否超 Results 工具上限
#             → 输出可执行的分片方案（每一刀选什么、存什么文件名）。
#   (2) audit 扫描 data/gbd/ 下已下载的结果文件 → 核对每个分片的行数、
#             维度交叉表、以及**分片之间是否重叠**（重叠会让 PAF 分母被重复计入）。
#
# 为什么必须代码化：
#   本项目硬标准是「原始数据 + 分析代码 + 过程可复现」。下载步骤同样是数据
#   产生过程的一环——行数预算是纯算术，不该靠肉眼估；分片重叠是**静默错误**，
#   必须机器核验。本脚本只做算术与记账，不下载、不改写任何原始文件。
#
# 运行：
#   Rscript 96_gbd_download_plan.R            # 默认 plan + audit
#   PA_GBD_PLAN_MODE=plan  Rscript 96_gbd_download_plan.R
#   PA_GBD_PLAN_MODE=audit Rscript 96_gbd_download_plan.R
# =============================================================================

# ---- locale 引导（Windows 中文控制台输出必需；不依赖 00_setup.R）----
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8",
                "English_United States.utf8", "C.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
})
options(encoding = "UTF-8")

# ---- 定位项目根目录（与 00_setup.R 同规则，但独立实现，保证本脚本可单跑）----
local({
  root <- Sys.getenv("PARADIGM_A_ROOT", unset = "")
  if (!nzchar(root)) {
    a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
    f <- if (length(a)) sub("^--file=", "", a[1]) else
      file.path(getwd(), "96_gbd_download_plan.R")
    f <- gsub("\\\\", "/", normalizePath(f, mustWork = FALSE))
    root <- if (basename(dirname(f)) == "code") dirname(dirname(f)) else
      normalizePath(file.path(getwd(), ".."), mustWork = FALSE)
  }
  assign("ROOT", gsub("\\\\", "/", root), envir = globalenv())
})
DIR_GBD <- file.path(ROOT, "data", "gbd")
DIR_LOGS <- file.path(ROOT, "logs")
dir.create(DIR_LOGS, showWarnings = FALSE, recursive = TRUE)

# ---- 工具上限（GBD Results 工具实测口径）----
LIMIT_HARD <- 100000L   # 硬上限：总和超过则连 Download 也失败
LIMIT_WARN <- 50000L    # 软阈值：可下载，但网页表格不给预览（即本次遇到的报错）

# =============================================================================
# Part 1. 下载计划复算
# =============================================================================

# 维度基线（本项目的实际取值）
BASE <- list(
  n_cause = 8L,   # LPA 的 risk-outcome pair 数（GBD 2021 起 8 类）
  n_loc   = 205L, # Global + 204 countries/territories
  n_age   = 2L,   # All ages + Age-standardized
  n_year  = 6L,   # 1990 / 2000 / 2010 / 2019 / 2021 / 2022
  years   = c(1990L, 2000L, 2010L, 2019L, 2021L, 2022L),
  # ⚠️ Sex：Both = Male + Female，三者同勾等于同一批数重复算 3 遍 → 永远只勾 Both
  sex_opts_1 = 1L,                      # 只勾 Both
  sex_opts_3 = 3L,                      # Both + Male + Female
  measures = c("Deaths", "DALYs")       # 必须分两次下（不能同时勾）
)

# 单个分片的行数
rows_per_chunk <- function(n_cause, n_loc, n_sex, n_age, n_year, n_measure) {
  as.numeric(n_cause) * n_loc * n_sex * n_age * n_year * n_measure
}

# 方案定义：split_by 决定把哪一维切开
PLANS <- list(
  list(id = "alpha", label = "方案 α（首选）",
       n_sex = BASE$sex_opts_1, n_year = BASE$n_year,
       split_by = "measure",
       note = "保住全部 6 个年份；不做性别分层"),
  list(id = "beta", label = "方案 β",
       n_sex = BASE$sex_opts_3, n_year = 3L,
       split_by = "measure",
       note = "保住性别分层；年份减到 3 个（1990/2010/2022）"),
  list(id = "gamma", label = "方案 γ",
       n_sex = BASE$sex_opts_3, n_year = BASE$n_year,
       split_by = "measure_sex",
       note = "年份与性别都要；代价是下载 6 次")
)

eval_plan <- function(p) {
  n_measure <- length(BASE$measures)
  total <- rows_per_chunk(BASE$n_cause, BASE$n_loc, p$n_sex,
                          BASE$n_age, p$n_year, n_measure)
  n_chunk <- switch(p$split_by,
                    measure      = n_measure,
                    measure_sex  = n_measure * p$n_sex)
  per_chunk <- total / n_chunk
  verdict <- if (per_chunk > LIMIT_HARD) "FAIL(单)>10万，Download 也失败"
             else if (total > LIMIT_HARD) "WARN(总)>10万，必须拆"
             else if (per_chunk > LIMIT_WARN) "WARN(单)>5万，无网页预览"
             else "OK"
  data.frame(id = p$id, label = p$label, n_sex = p$n_sex, n_year = p$n_year,
             split_by = p$split_by, n_chunk = n_chunk,
             rows_per_chunk = per_chunk, rows_total = total,
             verdict = verdict, note = p$note, stringsAsFactors = FALSE)
}

plan_tbl <- do.call(rbind, lapply(PLANS, eval_plan))

cat("\n===================================================================\n")
cat("GBD Results 下载计划复算  |  root =", ROOT, "\n")
cat("===================================================================\n")
cat(sprintf("基线维度：cause=%d  location=%d  age=%d  year=%d\n",
            BASE$n_cause, BASE$n_loc, BASE$n_age, BASE$n_year))
cat(sprintf("公式：行数 = cause × location × sex × age × year × measure\n"))
cat(sprintf("上限：硬 %d 行 / 软(预览) %d 行\n\n", LIMIT_HARD, LIMIT_WARN))

print(plan_tbl[, c("id", "label", "n_sex", "n_year", "n_chunk",
                   "rows_per_chunk", "rows_total", "verdict")],
      row.names = FALSE)

cat("\n--- 方案明细 ---\n")
for (i in seq_len(nrow(plan_tbl))) {
  r <- plan_tbl[i, ]
  cat(sprintf("\n[%s] %s  —— %s\n", r$id, r$label, r$note))
  cat(sprintf("  勾选：Sex=%s  Year=%d 个  Measure=%s\n",
              if (r$n_sex == 1) "Both（仅此一项）" else "Both+Male+Female",
              r$n_year, paste(BASE$measures, collapse = " / ")))
  cat(sprintf("  拆 %d 刀，每刀 %.0f 行\n", r$n_chunk, r$rows_per_chunk))
  if (r$split_by == "measure") {
    for (m in BASE$measures)
      cat(sprintf("    · 第 %d 刀：Measure 只勾 %-6s → risk_lpa_attributable_%s.csv\n",
                  match(m, BASE$measures), m, tolower(m)))
  } else {
    k <- 0
    for (m in BASE$measures) for (s in c("both", "male", "female")) {
      k <- k + 1
      cat(sprintf("    · 第 %d 刀：Measure=%s，Sex=%s → risk_lpa_attributable_%s_%s.csv\n",
                  k, m, s, tolower(m), s))
    }
  }
}
cat("\n⛔ 硬性规则：\n")
cat("   1) Measure 的 Deaths 与 DALYs **绝不同时勾**（同时勾 = 行数翻倍，必超限）；\n")
cat("   2) Sex 只勾 Both 即可；Both 已等于 Male+Female，三个同勾纯属重复；\n")
cat("   3) Age 只勾 All ages（metric = Number 时 Age-standardized 是率口径，混进来会污染）；\n")
cat("   4) 文件名与目录**随意**（Results 工具生成的 hash 名原样保留，不要改名/移动）：\n")
cat("      脚本 05 按**内容**识别角色（rei_name 是否有值区分批次1/批次2），\n")
cat("      并递归扫描 data/gbd/ 全部子目录，分几片都能自动拼接。\n")

# 落盘一份（可复现留痕）
plan_path <- file.path(DIR_LOGS, "GBD_download_plan.txt")
con <- file(plan_path, open = "wt", encoding = "UTF-8")
writeLines(c(
  sprintf("# GBD Results 下载计划 生成时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  sprintf("# root: %s", ROOT),
  sprintf("# 公式: 行数 = cause × location × sex × age × year × measure"),
  sprintf("# 上限: hard=%d, warn(preview)=%d", LIMIT_HARD, LIMIT_WARN),
  "",
  capture.output(print(plan_tbl, row.names = FALSE))
), con)
close(con)
cat(sprintf("\n计划已落盘：%s\n", plan_path))

# =============================================================================
# Part 1b. D2 方案 B（25+ 年龄分母）行数复算  —— 2026-10-12 新增
# =============================================================================
# 背景：LPA 是 25+ 风险因素，GBD 自身的归因负担也只算在 25+ 人群上；而批次 2
#       分母现用 All ages（含 0–24 岁）→ 0–24 岁人口进分母却不产生归因
#       → PAF 被**系统性低估**。方案 B = 补拉 25+ 年龄分组的 cause 总负担。
#
# 🔑 关键（决定了方案可行性的量级）：
#       code/95_module3_paf.R 实际只使用 YEARS = c(1990, 2022) 两个年份，
#       因此**只需拉 2 个年份**即可覆盖全部下游用途，行数从 14.8 万降到 4.9 万。
#
# 行数 = cause × location × sex × age × year × measure
#        = 8 × 205 × 1(Both) × 15(25+ 五岁组) × 2 × 1 = 49,200  ✅ 单刀可下且有预览
PLAN_B <- list(
  list(id = "B1", label = "B1（推荐）205 国 × 15 个 25+ 组 × 2 年",
       n_loc = 205L, loc_label = "Global + 204 国（与批次 1 完全一致）",
       n_age = 15L, n_year = 2L, years = "1990, 2022",
       note = "全部国家分母都精确化；年份与 Module 3 实际使用完全对齐"),
  list(id = "B2", label = "B2（备选）28 区 × 15 个 25+ 组 × 6 年",
       n_loc = 28L, loc_label = "Global + 21 GBD 区域 + 5 SDI + China",
       n_age = 15L, n_year = 6L, years = "1990/2000/2010/2019/2021/2022",
       note = "保住 6 年时间序列；但仅 28 个 location 有精确分母，其余 177 国回退 All ages")
)

cat("\n\n===================================================================\n")
cat("D2 方案 B｜25+ 年龄分母 下载规格（2026-10-12 拍板选用）\n")
cat("===================================================================\n")
cat(sprintf("公式：行数 = cause × location × sex × age × year × measure\n"))
cat("底色：cause = 8（批次 1 实测）  sex = Both  measure 分 2 次下（Deaths / DALYs）\n\n")

b_tbl <- do.call(rbind, lapply(PLAN_B, function(p) {
  per <- rows_per_chunk(BASE$n_cause, p$n_loc, 1L, p$n_age, p$n_year, 1L)
  verdict <- if (per > LIMIT_HARD) "FAIL(单)>10万"
             else if (per > LIMIT_WARN) "WARN(单)>5万，无网页预览"
             else "OK"
  data.frame(id = p$id, label = p$label, n_loc = p$n_loc, n_age = p$n_age,
             n_year = p$n_year, rows_per_chunk = per, verdict = verdict,
             note = p$note, stringsAsFactors = FALSE)
}))
print(b_tbl[, c("id", "label", "n_loc", "n_age", "n_year",
                "rows_per_chunk", "verdict")], row.names = FALSE)

cat("\n--- 方案 B 明细 ---\n")
for (i in seq_along(PLAN_B)) {
  p <- PLAN_B[[i]]
  per <- rows_per_chunk(BASE$n_cause, p$n_loc, 1L, p$n_age, p$n_year, 1L)
  cat(sprintf("\n[%s] %s\n", p$id, p$label))
  cat(sprintf("  Location : %s  (n=%d)\n", p$loc_label, p$n_loc))
  cat(sprintf("  Age      : 25-29 … 95+ 全部 %d 个五岁组（**必须全勾**）\n", p$n_age))
  cat(sprintf("  Year     : %s  (n=%d)\n", p$years, p$n_year))
  cat(sprintf("  Sex      : Both（仅此一项）   Metric : Number\n"))
  cat(sprintf("  Measure  : 分两次下 —— 第 1 刀只勾 Deaths，第 2 刀只勾 DALYs\n"))
  cat(sprintf("  行数     : 8 × %d × 1 × %d × %d × 1 = %s / 刀\n",
              p$n_loc, p$n_age, p$n_year, format(per, big.mark = ",")))
  cat(sprintf("  说明     : %s\n", p$note))
}
cat("\n⛔ 关键约束（与批次 1 一致，错了会静默出错）：\n")
cat("   1) GBD Estimate 必须选 **Cause of death or injury**（不是 Risk factor）——\n")
cat("      脚本靠 rei_name 是否为空区分批次 1/批次 2；误用 Risk factor 模式会使\n")
cat("      rei_name 有值 → 25+ 分母被误判成批次 1 → PAF 分母缺失。\n")
cat("   2) Cause 逐个勾选那 8 个 Level-3 结局，**不要勾 All causes，也不要勾父节点**。\n")
cat("   3) Age **不要**勾 All ages，只勾 25-29 起的 15 个五岁组。\n")
cat("   4) Deaths 与 DALYs **绝不同时勾**。\n")
cat("   5) 原始 CSV 不改名、不移动、不改数值 —— 脚本按内容识别并递归扫描子目录。\n")

b_path <- file.path(DIR_LOGS, "GBD_download_plan_D2_B.txt")
conB <- file(b_path, open = "wt", encoding = "UTF-8")
writeLines(c(
  sprintf("# D2 方案 B｜25+ 年龄分母 下载规格  生成时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  sprintf("# root: %s", ROOT),
  sprintf("# 公式: 行数 = cause × location × sex × age × year × measure"),
  sprintf("# 上限: hard=%d, warn(preview)=%d", LIMIT_HARD, LIMIT_WARN),
  "",
  capture.output(print(b_tbl, row.names = FALSE))
), conB)
close(conB)
cat(sprintf("\n方案 B 规格已落盘：%s\n", b_path))

# =============================================================================
# Part 2. 已下载分片核验
# =============================================================================

audit_shards <- function() {
  cat("\n\n===================================================================\n")
  cat("已下载 GBD 结果分片核验\n")
  cat("===================================================================\n")

  # recursive = TRUE：Results 工具导出的是「一目录一文件」结构
  #   data/gbd/IHME-GBD_2023_DATA-<hash>-1/IHME-GBD_2023_DATA-<hash>-1.csv
  fs_all <- list.files(DIR_GBD, full.names = TRUE, recursive = TRUE, ignore.case = TRUE)
  fs_all <- fs_all[grepl("\\.csv$", fs_all, ignore.case = TRUE) &
                     !grepl("TABLE_INDEX", fs_all, ignore.case = TRUE)]

  # 用「相对路径」作唯一 key：不同子目录下 basename 可能同名，用 basename 会互相覆盖
  rel_of <- function(f) sub("^/", "", sub(DIR_GBD, "", f, fixed = TRUE))

  # 归档目录排除（2026-10-14 新增）
  #   data/gbd/_archive_*/ 下是**已退役**的历史版本（如 D2 决策前的 All ages 分母）。
  #   本函数是 recursive 扫描：若不排除，All ages 与新版 25+ 分母会被同时计入
  #   同一角色 → PAF 分母被静默重复计入，且「分片互斥」检查**看不出来**
  #   （两者 age_name 不同，键天然不重叠）→ 必须在这里硬排除。
  is_arch <- grepl("[/\\\\]_archive", fs_all, ignore.case = TRUE)
  fs      <- fs_all[!is_arch]
  fs_arch <- fs_all[is_arch]
  if (length(fs_arch)) {
    cat(sprintf("  \u24d8 已忽略 %d 个归档文件（data/gbd/_archive_*/，不参与角色识别）：\n",
                length(fs_arch)))
    for (f in fs_arch) cat(sprintf("      (归档) %s\n", rel_of(f)))
    cat("\n")
  }
  if (!length(fs)) {
    cat("  data/gbd/ 下暂无 CSV（除索引与归档外）。\n"); return(invisible(NULL))
  }

  has_dt <- requireNamespace("data.table", quietly = TRUE)
  if (!has_dt)
    cat("  \u26a0\ufe0f 未安装 data.table \u2192 只能统计行数，跳过维度交叉与重叠检查。\n")
  cat(sprintf("  递归发现 %d 个 CSV 文件：\n\n", length(fs)))

  # 按**内容**识别角色（文件名不可靠：Results 导出名是自动生成的 hash）
  classify <- function(f) {
    hdr <- tryCatch(names(data.table::fread(f, nrows = 0, showProgress = FALSE)),
                    error = function(e) NULL)
    if (is.null(hdr) || !length(hdr)) return("unreadable")
    if (all(c("mean", "age_group_id") %in% hdr)) return("exposure_pack")
    if (all(c("measure_name", "cause_name", "val") %in% hdr)) {
      if ("rei_name" %in% hdr) {
        rv <- tryCatch(unique(data.table::fread(f, select = "rei_name",
                                                showProgress = FALSE)[[1]]),
                       error = function(e) character(0))
        rv <- rv[!is.na(rv) & nzchar(as.character(rv))]
        if (length(rv)) return("batch1_attributable")
      }
      return("batch2_cause_totals")
    }
    "other"
  }

  info <- list()
  for (f in fs) {
    rl <- rel_of(f)
    sz <- file.size(f) / 1024^2
    role <- if (has_dt) classify(f) else "unknown(无 data.table)"
    if (has_dt) {
      d <- tryCatch(data.table::fread(f, showProgress = FALSE),
                    error = function(e) NULL)
      if (is.null(d)) {
        cat(sprintf("  %-56s 读取失败\n", rl)); next
      }
      keep <- intersect(c("cause_name", "cause", "measure_name", "measure",
                          "location_name", "location", "age_name", "age",
                          "sex_name", "sex", "year", "year_id",
                          "val", "value", "rei_name",
                          "metric_name", "population_group_name"), names(d))
      info[[rl]] <- list(file = f, rel = rl, role = role, nrow = nrow(d), mb = sz,
                         cols = names(d), key_cols = keep, data = d[, ..keep])
      cat(sprintf("  %-56s %9d 行  %6.1f MB\n", rl, nrow(d), sz))
    } else {
      n <- tryCatch({
        ln <- readLines(f, n = -1L, encoding = "UTF-8", warn = FALSE)
        max(0L, length(ln) - 1L)
      }, error = function(e) NA_integer_)
      info[[rl]] <- list(file = f, rel = rl, role = role, nrow = n, mb = sz)
      cat(sprintf("  %-56s %9s 行  %6.1f MB\n", rl,
                  ifelse(is.na(n), "?", format(n, big.mark = ",")), sz))
    }
  }

  if (!has_dt || !length(info)) return(invisible(info))

  cat("\n--- 角色识别（按内容，不依赖文件名）---\n")
  for (rl in names(info)) cat(sprintf("  %-56s → %s\n", rl, info[[rl]]$role))

  # --- 维度取值汇总（确认 measure/age/sex/cause 的**实际**取值，而非假定）---
  cat("\n--- 维度取值汇总 ---\n")
  for (rl in names(info)) {
    d <- info[[rl]]$data
    if (is.null(d)) next
    cat(sprintf("\n  [%s]\n    role = %s   行数 = %d\n",
                rl, info[[rl]]$role, info[[rl]]$nrow))
    for (v in c("measure_name", "metric_name", "rei_name", "sex_name",
                "age_name", "population_group_name")) {
      if (v %in% names(d)) {
        u <- unique(d[[v]])
        cat(sprintf("    %-22s n=%-3d %s\n", v, length(u),
                    paste(utils::head(u, 12), collapse = " | ")))
      }
    }
    if ("cause_name" %in% names(d)) {
      u <- sort(unique(d$cause_name))
      cat(sprintf("    %-22s n=%-3d %s\n", "cause_name", length(u),
                  paste(u, collapse = " | ")))
    }
    if ("year" %in% names(d))
      cat(sprintf("    %-22s %s\n", "year",
                  paste(sort(unique(d$year)), collapse = ",")))
    if ("location_name" %in% names(d))
      cat(sprintf("    %-22s %d\n", "location_name 唯一数",
                  length(unique(d$location_name))))
  }

  # --- 重叠检查 ---
  #   ⚠️ 必须**在同一角色内**比较：批次 1（Risk factor）与批次 2（Cause）的维度键
  #      （cause × measure × location × age × sex × year）本来就完全相同，
  #      跨角色比较会产生 100% 的假重叠。
  cat("\n--- 分片重叠检查（同角色内；重复会让 PAF 分母被重复计入）---\n")
  for (role in c("batch1_attributable", "batch2_cause_totals")) {
    grp <- names(info)[vapply(names(info),
                              function(rl) identical(info[[rl]]$role, role),
                              logical(1))]
    if (!length(grp)) next
    cat(sprintf("\n  [%s]  %d 个文件\n", role, length(grp)))

    # --- 年龄口径混用检查（2026-10-14 新增）---
    #   ⚠️ 关键盲区：若同一角色里既有 `All ages` 又有 25+ 五岁组（D2 决策前后两版并存），
    #      两者 age_name 不同 → 下面的「跨文件重复键」检查**永远查不出来**，
    #      但分母会被重复计入（All ages + Σ25+）。必须单独硬检查，否则是"假通过"。
    age_u <- unique(unlist(lapply(grp, function(rl) {
      d <- info[[rl]]$data
      if (is.null(d) || !"age_name" %in% names(d)) return(character(0))
      as.character(unique(d$age_name))
    })))
    has_all  <- any(grepl("^all ages$", age_u, ignore.case = TRUE))
    has_five <- any(grepl("^[0-9]+-[0-9]+ years$", age_u, ignore.case = TRUE))
    if (has_all && has_five) {
      cat("    \u274c 年龄口径混用：同角色内同时存在 `All ages` 与五岁组 \u2192 分母会被重复计入！\n")
      cat(sprintf("       age_name 取值：%s\n", paste(age_u, collapse = " | ")))
      cat("       处置：把退役版本移入 data/gbd/_archive_*/（本脚本与 05 均已自动忽略该目录）。\n")
    } else if (has_all && role == "batch2_cause_totals") {
      cat("    \u26a0\ufe0f 批次 2 只含 `All ages`（无 25+ 五岁组）\u2192 PAF 分母为 All ages 口径，\n")
      cat("       与「LPA 仅覆盖 25+」不匹配 \u2192 PAF 会被系统性低估（D2 待办未完成）。\n")
    } else if (has_five && role == "batch2_cause_totals") {
      cat("    \u2705 批次 2 为 25+ 五岁组口径（与 LPA 暴露定义一致）。\n")
    }

    per_file_keys <- list()
    for (rl in grp) {
      d <- info[[rl]]$data
      if (is.null(d)) next
      cand <- c("cause_name", "cause", "measure_name", "measure",
                "location_name", "location", "age_name", "age",
                "sex_name", "sex", "year", "year_id")
      use <- intersect(cand, names(d))
      if (!length(use)) next
      k <- do.call(paste, c(as.list(d[, ..use]), sep = "|"))
      # 文件内自身重复也是静默错误（同键多行 → PAF 分母被重复计入）
      dup_in <- sum(duplicated(k))
      if (dup_in > 0L)
        cat(sprintf("    ⚠️ 文件内自身含 %d 条重复键：%s\n", dup_in, rl))
      per_file_keys[[rl]] <- unique(k)
    }
    if (length(per_file_keys) < 2) {
      cat("    仅 1 个文件，跳过跨文件比较。\n"); next
    }
    found_dup <- FALSE
    for (i in seq_along(per_file_keys)) for (j in seq_along(per_file_keys)) {
      if (j <= i) next
      ov <- length(intersect(per_file_keys[[i]], per_file_keys[[j]]))
      if (ov > 0L) {
        found_dup <- TRUE
        cat(sprintf("    ❌ 跨文件重叠 %6d 条键：%s  ×  %s\n",
                    ov, names(per_file_keys)[i], names(per_file_keys)[j]))
      }
    }
    if (!found_dup) cat("    ✅ 未检出跨文件重复键（分片互斥）。\n")
  }

  # --- 行数 vs 预算 + 维度乘积自洽性 ---
  # ⚠️ 10 万行上限只约束 **Results 工具导出**；GHDx 整包文件（暴露包 80 万行）
  #    是打包下载，不受此限，不得对其报 FAIL（否则会产生假警报）。
  #
  # 键 → 值 映射（2026-10-14 新增）
  #   键**刻意不含 measure_name**：工具"省略零值行"的行为只发生在某个 measure 里
  #   （实测：Deaths 省略了 PAD 25-39 的零死亡行，而同格在 DALYs 文件中存在且 =0），
  #   所以判定缺口必须**跨 measure** 比对。
  kv_of <- function(d) {
    cand <- c("cause_name", "cause", "location_name", "location",
              "age_name", "age", "sex_name", "sex", "year", "year_id")
    use <- intersect(cand, names(d))
    if (!length(use) || !"val" %in% names(d)) return(NULL)
    list(use = use,
         k = do.call(paste, c(as.list(d[, ..use]), sep = "|")),
         v = suppressWarnings(as.numeric(d$val)))
  }

  # 缺口是否可由「零值行被工具省略」解释（→ 无偏，不应报 FAIL）
  #   返回 verdict ∈ {"ok"(缺口全为零), "nonzero"(有非零缺口), "unknown"(无参照)}
  zero_omission_verdict <- function(d, role) {
    ki <- kv_of(d)
    if (is.null(ki))
      return(list(verdict = "unknown", n_missing = NA_integer_, n_nonzero = NA_integer_,
                  ref = NA_character_))
    uki <- unique(ki$k); best <- NULL
    for (rj in names(info)) {
      dj <- info[[rj]]$data
      if (is.null(dj) || !identical(info[[rj]]$role, role)) next
      kj <- kv_of(dj); if (is.null(kj)) next
      if (!identical(sort(ki$use), sort(kj$use))) next
      miss <- setdiff(unique(kj$k), uki)
      if (!length(miss)) next
      vv <- kj$v[kj$k %in% miss]
      n_nonzero <- sum(!is.na(vv) & vv != 0)
      cand <- list(verdict = if (n_nonzero == 0L) "ok" else "nonzero",
                   n_missing = length(miss), n_nonzero = n_nonzero,
                   ref = info[[rj]]$rel)
      if (is.null(best) || cand$n_missing > best$n_missing) best <- cand
    }
    if (is.null(best))
      list(verdict = "unknown", n_missing = NA_integer_, n_nonzero = NA_integer_,
           ref = NA_character_)
    else best
  }

  cat("\n--- 行数 vs Results 工具 10 万行上限 ---\n")
  cat("  （仅约束 Results 工具导出；GHDx 整包文件不受此限）\n")
  for (rl in names(info)) {
    n  <- info[[rl]]$nrow
    bt <- info[[rl]]$role
    flag <- if (is.na(n)) "?"
            else if (bt == "exposure_pack") "— 整包，不受限"
            else if (n > LIMIT_HARD) "❌ 超硬上限"
            else if (n > LIMIT_WARN) "⚠️ 可下但无网页预览"
            else "✅"
    cat(sprintf("  %-56s %9s 行  %s\n", rl,
                ifelse(is.na(n), "?", format(n, big.mark = ",")), flag))

    # 维度乘积自洽性：行数应恰好等于各维度唯一值数的乘积。
    #   行数 > 乘积 → 有重复行（静默错误，必须报）。
    #   行数 < 乘积 → 有两种可能：
    #     (a) 真缺失（该下的维度没下全）→ 必须报 FAIL；
    #     (b) **零值行被工具省略**（如 Deaths 里 PAD 25-39 岁死亡数 = 0 的行不存在）
    #         → 视为 0 无偏，**不应报 FAIL**（否则是假警报）。
    #     区分方法：以同角色、同维度列集合的另一文件为参照，求缺失键；
    #     若缺失键在参照文件中的值**全为 0** → 判 (b)。见 zero_omission_verdict()。
    if (bt %in% c("batch1_attributable", "batch2_cause_totals") &&
        !is.null(info[[rl]]$data)) {
      d <- info[[rl]]$data
      dims <- intersect(c("cause_name", "measure_name", "location_name",
                          "age_name", "sex_name", "year"), names(d))
      if (length(dims) >= 5) {
        cnt <- vapply(dims, function(v) length(unique(d[[v]])), numeric(1))
        prod_exp <- prod(cnt)
        head_txt <- sprintf("%s = %s",
                            paste(format(cnt, big.mark = ","), collapse = " \u00d7 "),
                            format(prod_exp, big.mark = ","))
        if (isTRUE(all.equal(as.numeric(n), prod_exp))) {
          cat(sprintf("        \u2705 维度乘积：%s  与行数一致\n", head_txt))
        } else if (as.numeric(n) > prod_exp) {
          cat(sprintf("        \u274c 维度乘积：%s  但实际 %s 行 \u2192 **行数超过乘积，存在重复行！**\n",
                      head_txt, format(n, big.mark = ",")))
        } else {
          v <- zero_omission_verdict(d, bt)
          if (identical(v$verdict, "ok")) {
            cat(sprintf("        \u2705 维度乘积：%s  实际 %s 行 \u2192 缺 %s 格；\n",
                        head_txt, format(n, big.mark = ","),
                        format(v$n_missing, big.mark = ",")))
            cat(sprintf("           经跨-measure 比对（参照 %s），缺失格的值**全为 0**\n", v$ref))
            cat("           \u2192 系工具省略零值行，按 0 处理**无偏**（非下载错误）。\n")
          } else if (identical(v$verdict, "nonzero")) {
            cat(sprintf("        \u274c 维度乘积：%s  但实际 %s 行 \u2192 缺 %s 格，\n",
                        head_txt, format(n, big.mark = ","),
                        format(v$n_missing, big.mark = ",")))
            cat(sprintf("           其中 **%s 格**在参照 %s 中为非零 \u2192 真缺失，需重下不全的维度！\n",
                        format(v$n_nonzero, big.mark = ","), v$ref))
          } else {
            cat(sprintf("        \u274c 维度乘积：%s  但实际 %s 行 \u2192 存在缺失，\n",
                        head_txt, format(n, big.mark = ",")))
            cat("           且无同角色参照文件可判定是否为零值 \u2192 请人工确认（勿默认视为 0）。\n")
          }
        }
      }
    }
  }

  invisible(info)
}

# =============================================================================
# 主流程
# =============================================================================
MODE <- tolower(Sys.getenv("PA_GBD_PLAN_MODE", unset = "both"))
if (MODE %in% c("plan", "both"))  invisible(plan_tbl)
if (MODE %in% c("audit", "both")) {
  # 核验报告双写：控制台 + logs/（可存档、可 diff）
  audit_path <- file.path(DIR_LOGS, "GBD_download_audit.txt")
  con2 <- file(audit_path, open = "wt", encoding = "UTF-8")
  sink(con2, split = TRUE)
  cat(sprintf("# GBD 已下载文件核验报告  生成时间: %s\n",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
  cat(sprintf("# root: %s\n", ROOT))
  info <- audit_shards()
  sink()
  close(con2)
  cat(sprintf("\n核验报告已落盘：%s\n", audit_path))
}

cat("\n96 完成。\n")
