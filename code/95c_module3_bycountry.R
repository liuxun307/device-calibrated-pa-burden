# =============================================================================
# 95c_module3_bycountry.R
# Module 3 逐国版（205 个 location = Global + 204 国）—— Fig 5(b)(c) + Table 4 逐国版
# -----------------------------------------------------------------------------
# 为什么要单独一个脚本，而不是把 95 的 LOCS 从 8 改成 205：
#   · `95` 的 5 个产物（PREVIEW_module3_*）是**已冻结、逐字节校验过**的 8 地区版本，
#     被 98 的 KEY_OUT 与 Fig 5(a) 消费。直接改 LOCS 会一次性改写它们，
#     让「8 地区对照」消失，且 205 国的长跑会拖累主链（预估 ~45 min）。
#   · 因此本脚本**复用 95 的全部桥接逻辑**（通过 PA_M3_HELPERS_ONLY=1 开关，
#     见 95_module3_paf.R §5 开头），只换 location 集合与产物文件名。
#     —— 复制 200 行口径敏感代码会长期漂移，故不复制。
#
# 口径（与 95 逐字一致，不做任何本地改动）：
#   · 暴露分布：CV_MODE 默认 **s1p（S1′，主分析口径）**；可用 PA_CV_MODE=grid 覆盖
#   · RR 来源：Module 2 池化 device_pooled × total_PA（bop_rr_draws.rds 后验）
#   · 反事实：以 TMREL 设备等效（13,222 MIMS/day）重锚定 + ≥TMREL 封顶
#   · 分母：GBD 批次 2（cause 总负担，25+ 口径）
#   · 对照：GBD 批次 1（LPA 现报归因值）
#   · 种子：set.seed(PA_SEED + 3L)（在 95 内已固定，本脚本沿用同一流起点）
#
# 产物：
#   output/M3_BYCOUNTRY_totals.csv         逐国 × 年 × RR 来源（Table 4 逐国版底表）
#   output/M3_BYCOUNTRY_by_cause.csv       逐国 × 年 × cause（Fig 5(c) 底表）
#   output/M3_BYCOUNTRY_exposure_diag.csv  暴露分布诊断（审计用）
#   output/M3_BYCOUNTRY_by_sdi.csv         按 SDI 五分位聚合（Fig 5(b) 底表）
#   logs/module3_bycountry.txt             运行报告
#
# 运行：
#   Rscript 95c_module3_bycountry.R                 # s1p（主分析，并行约 15 min）
#   PA_M3_CORES=1 Rscript 95c_module3_bycountry.R   # 强制顺序（结果与并行逐字节一致）
#   PA_CV_MODE=grid Rscript 95c_module3_bycountry.R # S3 网格敏感性（约 2 h，不建议）
#   PA_M3_N_MAX=12 Rscript 95c_module3_bycountry.R  # 冒烟测试：只跑前 12 个 location
#
# 并行确定性：调度**只影响墙钟时间**。run_one_location() 按 location 独立播种
#   （set.seed(PA_SEED + 3L + li)），故 PA_M3_CORES=1/8 的四个产物必须逐字节一致。
# =============================================================================

# ---- 统一引导（与 95 同款）----
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8",
                "English_United States.utf8", "C.UTF-8"))
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

# ⚠️ 两个env 必须在 source 95 之前设好：95 在**解析期**读 PA_CV_MODE 决定产物前缀，
#    并靠 PA_M3_HELPERS_ONLY 决定是否执行 8 地区主循环。
if (!nzchar(Sys.getenv("PA_CV_MODE")))     Sys.setenv(PA_CV_MODE = "s1p")
Sys.setenv(PA_M3_HELPERS_ONLY = "1")
.old_wd <- getwd()
source("95_module3_paf.R")
setwd(.old_wd)

suppressPackageStartupMessages({ library(data.table); library(tidyverse) })

BY_PREFIX <- NULL   # 见下（冒烟模式会加 SMOKE_ 前缀）
YEARS     <- c(1990, 2022)
CVS       <- if (CV_MODE == "s1p") 1 else EXPO_SD_GRID
N_MAX     <- suppressWarnings(as.integer(Sys.getenv("PA_M3_N_MAX", unset = "0")))
# 冒烟模式（PA_M3_N_MAX>0）只跑前若干 location，产物加 "SMOKE_" 前缀，
# 避免半成品被误当成正式逐国产物消费。
BY_PREFIX <- if (N_MAX > 0L) "SMOKE_M3_BYCOUNTRY_" else "M3_BYCOUNTRY_"
CKPT_DIR  <- file.path(DIR_LOGS, "_ckpt")
if (!dir.exists(CKPT_DIR)) dir.create(CKPT_DIR, recursive = TRUE, showWarnings = FALSE)

message("\n=========== 95c Module 3 逐国版（CV_MODE=", CV_MODE,
        " | RR 桥接=确定性枚举（全部后验曲线））===========\n")

# ---------------------------------------------------------------------------
# 1. 分析宇宙：205 个 location（与 96b 的 SDI 锚点、GBD 负担分片同集合）
# ---------------------------------------------------------------------------
fs_burden <- list.files(DIR_GBD, full.names = TRUE, recursive = TRUE)
fs_burden <- fs_burden[!grepl("_archive", fs_burden, fixed = TRUE)]
fs_burden <- fs_burden[grepl("IHME-GBD_2023_DATA-.*\\.csv$",
                             basename(fs_burden), ignore.case = TRUE)]
if (!length(fs_burden)) stop("未找到 GBD 负担分片（data/gbd/IHME-GBD_2023_DATA-*/*.csv）")

loc_tab <- unique(rbindlist(lapply(fs_burden, function(f)
  as.data.table(fread(f, select = c("location_id", "location_name")))))[
    , .(location_id = as.integer(location_id), location_name)])
setorder(loc_tab, location_id)
if (nrow(loc_tab) != 205L)
  stop("负担分片的 location 数应为 205（Global + 204 国），实际 ", nrow(loc_tab))
if (sum(loc_tab$location_name == "Global") != 1L) stop("location 集合中缺 Global")

LOCS <- loc_tab$location_name
if (N_MAX > 0L) {
  LOCS <- head(LOCS, N_MAX)
  message("[冒烟模式] PA_M3_N_MAX=", N_MAX, " → 只跑前 ", N_MAX, " 个 location")
}
message(sprintf("分析宇宙：%d 个 location（%d 年 × %d 个 CV × 2 个 RR 来源）",
                length(LOCS), length(YEARS), length(CVS)))

# ---------------------------------------------------------------------------
# 2. SDI 锚点合并（quintile 供 Fig 5(b) 分层与 Table 4 排序）
# ---------------------------------------------------------------------------
anchor_f <- file.path(DIR_OUT, "Table14_sdi_anchor.csv")
if (!file.exists(anchor_f))
  stop("缺少 ", anchor_f, " —— 请先跑 96b_sdi_anchor.R（需 data/gbd/SDI/ 下的 GBD 2023 SDI 文件）。")
ANCH <- as.data.table(fread(anchor_f))
ANCH[, location_name := gsub("^\ufeff", "", location_name)]
ANCH <- ANCH[, .(location_name, sdi_1990, sdi_2022, sdi_2023, quintile, quintile_ord)]
miss_a <- setdiff(LOCS, ANCH$location_name)
if (length(miss_a)) stop("SDI 锚点缺以下 location：", paste(miss_a, collapse = ", "))

# ---------------------------------------------------------------------------
# 3. 人口权重可解析性硬校验（防静默降级）
#    px_cells_s1p() 在 resolve_pop_loc() 返回 NA 时会**静默回退「均匀权重」**
#    （w_src="uniform"），不报错、不留痕 —— 逐国 205 个 location 必须逐条挡住。
# ---------------------------------------------------------------------------
if (CV_MODE == "s1p") {
  unres <- LOCS[vapply(LOCS, function(l) is.na(resolve_pop_loc(l)), logical(1))]
  if (length(unres))
    stop("以下 location 无法在人口表中解析（会造成**静默**的均匀权重回退）：\n  ",
         paste(unres, collapse = "\n  "),
         "\n→ 请在 05 的 POP_LOC_ALIAS 中补别名（键按 pop_norm_loc() 归一化后索引）。")
  message("人口权重解析：", length(LOCS), "/", length(LOCS), " 全部命中 ✓（来源 ", POP_SRC, "）")
}

# ---------------------------------------------------------------------------
# 4. 主循环（逐 location × year × CV × RR 来源）
#    ★ 2026-10-15 重构：串行 → 按 location 并行。逐国 205 个 location 串行实测
#      约 90 min（远超原估 45 min），改为 parLapplyLB 后约 15 min。
#      全部计算抽成 run_one_location()，顺序与并行两条路径**共用同一实现**，
#      因此不存在「并行版口径与串行版不同」的风险。
# ---------------------------------------------------------------------------
t0 <- Sys.time()

# ---------------------------------------------------------------------------
# 4b. 单个 location 的全部计算
# ---------------------------------------------------------------------------
run_one_location <- function(li) {
  loc <- LOCS[li]
  # ⚠️ 每个 location **独立播种** —— 这是并行安全的核心前提：
  #    若沿用「循环外统一设一次种子」，parLapplyLB 的完成顺序会改变抽样序列，
  #    结果就随核数与机器负载漂移。按 li 播种后，结果与顺序、核数**完全无关**。
  #    这比原实现（单一全局流）更稳健：原实现的产物会随循环顺序变化。
  set.seed(PA_SEED + 3L + li)

  cr_l <- list(); tot_l <- list(); diag_l <- list()
  den_l <- list(); gbd_l <- list(); skip_l <- character(0)

  for (yr in YEARS) {
    mt <- pop_mean_met(loc, yr)
    w2 <- build_wide(b2, loc, yr, "total")
    if (is.null(w2) || !is.finite(mt)) {
      skip_l <- c(skip_l, sprintf("%s %d (分母/暴露缺失)", loc, yr)); next
    }
    for (cc in c("deaths_total", "dalys_total"))
      if (!cc %in% names(w2)) w2[, (cc) := NA_real_]

    w1 <- if (!is.null(b1)) build_wide(b1, loc, yr, "gbd") else NULL

    # 逐病因的分母（批次 2）与 GBD 现报归因（批次 1）另留一份长表：
    #   · recompute_burden() 只返回归因数，须与分母并起来才能算逐病因 PAF / fold
    #     （Fig 5(c) 需要）。合并键走 norm_cause()：LPA_CAUSES 是规范名，
    #     而 GBD CSV 的 cause_name 大小写/标点可能不同，按原串 join 会静默丢行。
    den_l[[length(den_l) + 1L]] <- w2[, .(
      location = loc, year = yr, ck = norm_cause(cause_name),
      total_deaths_c = deaths_total, total_dalys_c = dalys_total)]
    if (!is.null(w1))
      gbd_l[[length(gbd_l) + 1L]] <- w1[, .(
        location = loc, year = yr, ck = norm_cause(cause_name),
        gbd_deaths_c = deaths_gbd, gbd_dalys_c = dalys_gbd)]

    for (cv in CVS) {
      px <- build_px(loc, yr, cv)
      if (is.null(px)) { skip_l <- c(skip_l, sprintf("%s %d (px 构造失败)", loc, yr)); next }

      cv_lab  <- if (CV_MODE == "s1p") px$cv_wavg else cv
      is_main <- if (CV_MODE == "s1p") TRUE else abs(cv - CV_MAIN) < 1e-9
      mt_lab  <- if (!is.null(px$mean_met_w)) px$mean_met_w else mt

      for (src in c("pooled", "nhanes")) {
        rrf <- if (src == "pooled")
          make_rr_fun_pooled(BOP, px, metric = "total_PA",
                             clamp = !NOCLAMP, compute_curve = FALSE)$fun
        else
          make_rr_fun_nhanes(rr_all, px$mims)

        res <- recompute_burden(px$f, rrf, gbd_dt = w2,
                                causes = LPA_CAUSES, n_draws = N_DRAWS)
        res[, `:=`(location = loc, year = yr, cv = cv_lab, cv_mode = CV_MODE,
                   is_main = is_main, rr_source = src)]
        cr_l[[length(cr_l) + 1L]] <- res

        tot <- data.table(
          location = loc, year = yr, rr_source = src, cv_mode = CV_MODE,
          cv_main = cv_lab, is_main = is_main, mean_met_wk = mt_lab,
          total_deaths = sum(w2$deaths_total, na.rm = TRUE),
          total_dalys  = sum(w2$dalys_total,  na.rm = TRUE),
          recomputed_deaths = sum(res$deaths_attrib, na.rm = TRUE),
          recomputed_dalys  = sum(res$dalys_attrib,  na.rm = TRUE))
        tot[, `:=`(paf_deaths = recomputed_deaths / total_deaths,
                   paf_dalys  = recomputed_dalys  / total_dalys)]
        if (!is.null(w1)) {
          tot[, `:=`(gbd_deaths = sum(w1$deaths_gbd, na.rm = TRUE),
                     gbd_dalys  = sum(w1$dalys_gbd,  na.rm = TRUE))]
          tot[, `:=`(gbd_paf_deaths = gbd_deaths / total_deaths,
                     gbd_paf_dalys  = gbd_dalys  / total_dalys,
                     fold_deaths = recomputed_deaths / gbd_deaths,
                     fold_dalys  = recomputed_dalys  / gbd_dalys,
                     diff_deaths_pct = 100 * (recomputed_deaths / gbd_deaths - 1),
                     diff_dalys_pct  = 100 * (recomputed_dalys  / gbd_dalys  - 1))]
        }
        tot_l[[length(tot_l) + 1L]] <- tot
      }

      # 暴露分布诊断（RR 桥接与 95 同式）
      br  <- make_rr_fun_pooled(BOP, px, metric = "total_PA", clamp = !NOCLAMP)
      mu  <- sum(px$mims * px$f)
      sdv <- sqrt(sum(px$f * (px$mims - mu)^2))
      diag_l[[length(diag_l) + 1L]] <- data.table(
        location = loc, year = yr, cv = cv_lab, cv_mode = CV_MODE,
        mean_met_wk = mt_lab, mean_mims = mu, sd_mims = sdv,
        cv_wavg_met = if (!is.null(px$cv_wavg))    px$cv_wavg    else NA_real_,
        cv_eff_dev  = if (!is.null(px$cv_eff_dev)) px$cv_eff_dev else sdv / mu,
        pop_w_src   = if (!is.null(px$w_src))      px$w_src      else "n/a",
        pop_entity  = if (!is.null(px$pop_entity)) px$pop_entity else NA_character_,
        median_mims = px$mims[which.min(abs(cumsum(px$f) / sum(px$f) - 0.5))],
        pct_below_tmrel = sum(px$f[px$mims < TMREL_MID_MIMS]),
        p_tmrel = br$info$p_tmrel, off_tmrel = br$info$off_tmrel,
        # 同 recompute_burden() 口径：逐曲线算 PAF 再平均（PAF(E[rr]) 会偏高约 0.24%）
        implied_paf_pooled = mean(paf_from_dist_mat(px$f, br$fun())),
        clamp = !NOCLAMP)
    }
  }
  list(loc = loc, cause = cr_l, tot = tot_l, diag = diag_l,
       den = den_l, gbd = gbd_l, skipped = skip_l)
}

# ---------------------------------------------------------------------------
# 4c. 调度：并行（默认）或顺序
#   调度只影响**墙钟时间**，不影响结果（run_one_location 按 li 独立播种）。
#   实证：PA_M3_CORES=1 与 PA_M3_CORES=8 的四个产物必须**逐字节一致**。
# ---------------------------------------------------------------------------
# 瘦身 expo：并行时该对象会被复制到每个 worker，只留逐国计算真正用到的列
#   （05 的 read_lpa_exposure 结果含 measure 等冗余列，内存占用可降一个量级）。
if (is.data.frame(expo)) {
  .keep <- intersect(c("location_name", "year_id", "age_group_id", "sex", "mean"),
                     names(expo))
  # ⚠️ 必须用 with = FALSE；`DT[, ..(.keep)]` 是**非法**语法 —— `..` 只是符号前缀
  #    （DT[, ..cols]），写成 ..(x) 会被当成函数调用 → "could not find function .."。
  if (length(.keep) == 5L) expo <- as.data.table(expo)[, .keep, with = FALSE] else
    message("⚠️ expo 列名与预期不符，跳过瘦身：", paste(names(expo), collapse = ", "))
}

N_CORE <- suppressWarnings(as.integer(Sys.getenv("PA_M3_CORES", unset = "0")))
if (is.na(N_CORE) || N_CORE <= 0L) {
  .dc <- tryCatch(parallel::detectCores(logical = FALSE), error = function(e) NA_integer_)
  if (is.na(.dc) || .dc < 2L)
    .dc <- tryCatch(parallel::detectCores(), error = function(e) 2L)
  N_CORE <- max(1L, min(8L, .dc - 1L))
}
N_CORE <- min(N_CORE, length(LOCS))
message(sprintf("并行核数 = %d（PA_M3_CORES 可覆盖；=1 为纯顺序）", N_CORE))

RES <- NULL
# ---------------------------------------------------------------------------
# 4d. 断点续跑（**显式开关** PA_M3_RESUME=1，默认关闭）
#   用途：只改了 §5 的聚合/落盘逻辑（§4 的逐国计算未动）时，复用 checkpoint 中
#         已算好的 205 个 location 结果，省掉 ~17 min 重算。
#   ⚠️ 刻意**不做**自动续跑：本项目硬标准是「过程可复现」，若自动复用陈旧结果，
#     一旦 §4 的计算逻辑被改动，产物会静默地不反映新代码 —— 无法察觉的坑。
#     故必须由调用者显式声明「我知道 §4 没变」。
#   等价性依据：run_one_location() 按 location 独立播种（set.seed(PA_SEED+3+li)），
#     结果只依赖 li 与该 location 的输入数据，与运行顺序、核数无关。
# ---------------------------------------------------------------------------
RES_FROM_CKPT <- FALSE
if (identical(Sys.getenv("PA_M3_RESUME", unset = ""), "1") && N_MAX == 0L) {
  .ckf <- file.path(CKPT_DIR, "m3_bycountry_partial.rds")
  if (file.exists(.ckf)) {
    .ck <- tryCatch(readRDS(.ckf), error = function(e) NULL)
    .n  <- if (is.null(.ck$parts)) 0L else
      sum(vapply(.ck$parts, function(p) length(p), integer(1)))
    if (.n == length(LOCS)) {
      RES <- unlist(.ck$parts, recursive = FALSE)
      RES_FROM_CKPT <- TRUE
      message(sprintf("断点续跑：从 checkpoint 复用全部 %d 个 location 的结果（跳过 §4 计算）。", .n))
      message("⚠️ 该模式假定 §4（run_one_location）的计算逻辑未变；仅 §5 及之后的聚合/落盘被改动。")
    } else {
      message(sprintf("断点续跑：checkpoint 只有 %d / %d 个 location，改为完整重算。",
                      .n, length(LOCS)))
    }
  } else {
    message("断点续跑：未找到 ", basename(.ckf), "，改为完整重算。")
  }
}
if (is.null(RES) && N_CORE > 1L) {
  # ⚠️ 导出策略：**导出 globalenv 的全部对象**，而不是硬编码名单。
  #   教训（2026-10-15 实测踩坑）：硬编码名单漏了 `GBD_AGE_25PLUS`
  #   （95 第 288 行定义、第 309 行用于 pop_mean_met 的年龄过滤），
  #   导致 worker 报 "object 'GBD_AGE_25PLUS' not found"、整批并行失败后回退顺序。
  #   `ls(globalenv())` 与顺序路径的解析语义**完全等价**（顺序版也是从 globalenv
  #   逐个取自由变量），故不可能再漏；名单式维护必然长期漂移。
  #   代价是每个 worker 复制一份环境 → 打印总体积以便发现异常膨胀。
  #   ⚠️ 必须 all.names = TRUE：`ls()` 默认**排除点号开头的对象**，而 95 内部用了
  #     `.pm_mono` 等点号变量（2026-10-15 实测踩坑："object '.pm_mono' not found"）。
  EXPORT <- ls(globalenv(), all.names = TRUE)
  .sz <- vapply(EXPORT, function(nm) {
    o <- tryCatch(get(nm, envir = globalenv()), error = function(e) NULL)
    if (is.null(o)) 0 else as.numeric(object.size(o))
  }, numeric(1))
  message(sprintf("并行导出：%d 个 globalenv 对象，合计 %.1f MB（每 worker 一份）",
                  length(EXPORT), sum(.sz) / 1024^2))
  .big <- sort(.sz, decreasing = TRUE)[1:min(3, length(.sz))]
  message("  最大的 3 个：", paste(sprintf("%s %.1f MB", names(.big), .big / 1024^2),
                                 collapse = " | "))

  cl <- tryCatch(parallel::makeCluster(N_CORE), error = function(e) NULL)
  if (is.null(cl)) {
    message("⚠️ 并行集群创建失败，回退顺序执行：", conditionMessage(attr(cl, "condition")))
    N_CORE <- 1L
  } else {
    parallel::clusterEvalQ(cl, suppressPackageStartupMessages({
      library(data.table); library(tidyverse) }))
    parallel::clusterExport(cl, EXPORT, envir = globalenv())
    CHUNK  <- 25L
    chunks <- split(seq_along(LOCS), ceiling(seq_along(LOCS) / CHUNK))
    parts  <- vector("list", length(chunks))
    ok <- TRUE
    for (ci in seq_along(chunks)) {
      parts[[ci]] <- tryCatch(
        parallel::parLapplyLB(cl, chunks[[ci]], run_one_location),
        error = function(e) { ok <<- FALSE; message("⚠️ 并行执行失败：", conditionMessage(e)); NULL })
      if (!ok) break
      nd <- length(unlist(chunks[seq_len(ci)]))
      el <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
      message(sprintf("  已完成 %3d/%3d 个 location，已用 %5.1f min，预计总 %5.1f min",
                      nd, length(LOCS), el, el * length(LOCS) / nd))
      saveRDS(list(parts = parts[seq_len(ci)]),
              file.path(CKPT_DIR, "m3_bycountry_partial.rds"))
    }
    parallel::stopCluster(cl)
    if (ok) RES <- unlist(parts, recursive = FALSE) else {
      message("⚠️ 并行中途失败，回退顺序重跑全部 location（结果不受影响）。")
      N_CORE <- 1L
    }
  }
}
if (is.null(RES)) {                       # 顺序路径（N_CORE=1，或并行失败后回退）
  RES <- vector("list", length(LOCS))
  for (i in seq_along(LOCS)) {
    RES[[i]] <- run_one_location(i)
    if (i %% 10L == 0L || i == length(LOCS)) {
      el <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
      message(sprintf("  已完成 %3d/%3d 个 location，已用 %5.1f min，预计总 %5.1f min",
                      i, length(LOCS), el, el * length(LOCS) / i))
      saveRDS(list(parts = RES[seq_len(i)]),
              file.path(CKPT_DIR, "m3_bycountry_partial.rds"))
    }
  }
}

skipped <- unlist(lapply(RES, `[[`, "skipped"), use.names = FALSE)
TOT   <- rbindlist(unlist(lapply(RES, `[[`, "tot"),   recursive = FALSE), fill = TRUE)
CAUSE <- rbindlist(unlist(lapply(RES, `[[`, "cause"), recursive = FALSE), fill = TRUE)
DIAG  <- rbindlist(unlist(lapply(RES, `[[`, "diag"),  recursive = FALSE), fill = TRUE)
den_rows <- unlist(lapply(RES, `[[`, "den"), recursive = FALSE)
gbd_rows <- unlist(lapply(RES, `[[`, "gbd"), recursive = FALSE)

# ---------------------------------------------------------------------------
# 5. 合并 SDI 锚点（逐国表）→ 按 quintile 聚合（Fig 5(b)）
# ---------------------------------------------------------------------------
TOT   <- merge(TOT,   ANCH, by.x = "location", by.y = "location_name", all.x = TRUE)
CAUSE <- merge(CAUSE, ANCH, by.x = "location", by.y = "location_name", all.x = TRUE)
DIAG  <- merge(DIAG,  ANCH, by.x = "location", by.y = "location_name", all.x = TRUE)

# (a) 并入逐病因分母与 GBD 逐病因归因
#     合并键统一走 norm_cause()：LPA_CAUSES 是规范名，GBD CSV 里的 cause_name
#     大小写/标点可能不同，按原字符串 join 会**静默**丢行（此时会表现为分母全 NA）。
CAUSE[, ck := norm_cause(cause)]
DEN  <- unique(rbindlist(den_rows, fill = TRUE))
GBDA <- if (length(gbd_rows)) unique(rbindlist(gbd_rows, fill = TRUE)) else NULL
CAUSE <- merge(CAUSE, DEN, by = c("location", "year", "ck"), all.x = TRUE)
if (!is.null(GBDA))
  CAUSE <- merge(CAUSE, GBDA, by = c("location", "year", "ck"), all.x = TRUE)
if (anyNA(CAUSE$total_deaths_c))
  stop("逐病因分母合并后有 NA —— 说明 cause 名未对上（norm_cause 键失配）。\n  例：",
       paste(head(CAUSE[is.na(total_deaths_c), cause], 3), collapse = ", "))

# (b) 逐病因 PAF 与 fold —— 这是 Fig 5(c) 的底表
CAUSE[, paf_deaths_c := deaths_attrib / total_deaths_c]
CAUSE[, paf_dalys_c  := dalys_attrib  / total_dalys_c]
if ("gbd_deaths_c" %in% names(CAUSE)) {
  CAUSE[, fold_deaths_c := deaths_attrib / gbd_deaths_c]
  CAUSE[, fold_dalys_c  := dalys_attrib  / gbd_dalys_c]
}

# ⚠️ 已知口径限制（务必在正文/图注中如实声明）：
#   本实现的 RR 曲线来自 Module 2 的 device_pooled × **total_PA**（总量型），
#   对全部 8 个结局共用同一条 RR → 重算出的 PAF **不随 cause 变化**，
#   cause 之间的**绝对归因数**差异全部来自 GBD 分母。
#   故 by_cause 表用于「绝对归因数」与「逐病因 fold」，
#   **不能**解读为病因特异的 RR 差异（cause-specific RR 属未来 refinement）。
CAUSE_M <- CAUSE[is_main == TRUE]
paf_by_cause <- CAUSE_M[, .(n_paf = uniqueN(signif(paf_deaths_c, 12))),
                        by = .(location, year, rr_source, cause)]

BY_SDI <- NULL
if (!is.null(names(TOT)) && "quintile" %in% names(TOT)) {
  # ⚠️ 必须剔除 Global：Global（世界）不是国家、没有有意义的 SDI 五分位归属，
  #    但 Table14 给 205 行都算了 quintile → 若不剔除，Global 会被塞进某一档，
  #    把全球负担重复计入该档（实测：High-middle 由 23 变 24、合计 205 而非 204）。
  agg <- TOT[!is.na(quintile) & is_main == TRUE & location != "Global"]
  BY_SDI <- agg[, .(
    n_country        = uniqueN(location),
    total_deaths     = sum(total_deaths,     na.rm = TRUE),
    total_dalys      = sum(total_dalys,      na.rm = TRUE),
    recomputed_deaths = sum(recomputed_deaths, na.rm = TRUE),
    recomputed_dalys  = sum(recomputed_dalys,  na.rm = TRUE),
    gbd_deaths       = sum(gbd_deaths,       na.rm = TRUE),
    gbd_dalys        = sum(gbd_dalys,        na.rm = TRUE)),
    by = .(quintile, quintile_ord, year, rr_source)]
  BY_SDI[, `:=`(
    paf_recomputed_deaths = recomputed_deaths / total_deaths,
    paf_gbd_deaths        = gbd_deaths / total_deaths,
    paf_recomputed_dalys  = recomputed_dalys / total_dalys,
    paf_gbd_dalys         = gbd_dalys / total_dalys,
    fold_deaths = recomputed_deaths / gbd_deaths,
    fold_dalys  = recomputed_dalys  / gbd_dalys)]
  setorder(BY_SDI, year, rr_source, quintile_ord)
}

# ---------------------------------------------------------------------------
# 6. 硬校验
# ---------------------------------------------------------------------------
chk <- list()
chk$n_loc <- uniqueN(TOT$location) == length(LOCS)
chk$all_yr <- all(YEARS %in% unique(TOT$year))
chk$both_src <- setequal(unique(TOT$rr_source), c("pooled", "nhanes"))
# 主情景每个 location × year × source 必须恰好 1 行
dup <- TOT[is_main == TRUE, .N, by = .(location, year, rr_source)][N != 1L]
chk$main_unique <- nrow(dup) == 0L
# PAF 必须在 cause 间恒定（当前口径的**预期**性质；若不再成立说明 RR 口径已改，需复核）
sp <- paf_by_cause[, .(n_paf = max(n_paf)), by = .(location, year, rr_source)]
chk$paf_cause_invariant <- all(sp$n_paf == 1L)
chk$sdi_agg <- !is.null(BY_SDI) && nrow(BY_SDI) > 0L
# 分桶国数合计必须 == 204（已剔 Global）；否则说明 Global 混进了某一档
chk$sdi_n <- !is.null(BY_SDI) &&
  all(BY_SDI[, .(n = sum(n_country)), by = .(year, rr_source)]$n ==
      (uniqueN(TOT$location) - 1L))

if (!chk$n_loc) stop("location 覆盖不全：", uniqueN(TOT$location), " / ", length(LOCS))
if (!chk$main_unique)
  stop("主情景存在重复行（location × year × rr_source 不唯一）：", nrow(dup))
if (!chk$paf_cause_invariant)
  stop("PAF 在 cause 间不再恒定 —— RR 口径可能已从 total_PA 改为 cause-specific，",
       "请复核本脚本 §5 的『已知口径限制』注释与下游图注。")
if (!chk$sdi_n)
  stop("BY_SDI 各档国数合计 != 204 —— Global 可能被计入某个 SDI 档（会使该档负担翻倍）。")

# ---------------------------------------------------------------------------
# 7. 落盘 + 报告
# ---------------------------------------------------------------------------
fwrite(TOT,    file.path(DIR_OUT, paste0(BY_PREFIX, "totals.csv")),        bom = TRUE)
fwrite(CAUSE,  file.path(DIR_OUT, paste0(BY_PREFIX, "by_cause.csv")),      bom = TRUE)
fwrite(DIAG,   file.path(DIR_OUT, paste0(BY_PREFIX, "exposure_diag.csv")), bom = TRUE)
if (!is.null(BY_SDI))
  fwrite(BY_SDI, file.path(DIR_OUT, paste0(BY_PREFIX, "by_sdi.csv")),      bom = TRUE)

g <- TOT[is_main == TRUE & rr_source == "pooled" & year == 2022 & location != "Global"]
setorder(g, -recomputed_deaths)
g_glob <- TOT[is_main == TRUE & rr_source == "pooled" & year == 2022 &
              location == "Global"]
rep <- c(
  "===== 95c Module 3 逐国版报告 =====",
  sprintf("CV_MODE=%s | RR 桥接=确定性枚举（全部后验曲线）| clamp=%s", CV_MODE, !NOCLAMP),
  sprintf("结果来源 = %s", if (RES_FROM_CKPT)
    "断点续跑（PA_M3_RESUME=1，复用 checkpoint 的 §4 结果；假定 §4 计算逻辑未变）"
    else "本次完整计算"),
  sprintf("location = %d（Global + %d 国）| 年份 = %s | RR 来源 = pooled / nhanes",
          uniqueN(TOT$location), uniqueN(TOT$location) - 1L,
          paste(YEARS, collapse = ", ")),
  if (length(skipped)) sprintf("跳过 %d 条：%s", length(skipped),
                               paste(head(skipped, 8), collapse = "; ")) else "无跳过项",
  "",
  "★ Global 2022（pooled，主情景）",
  sprintf("   分母（25+ 总死亡）= %s | 重算归因 = %s | GBD 现报 = %s",
          format(round(g_glob$total_deaths), big.mark = ","),
          format(round(g_glob$recomputed_deaths), big.mark = ","),
          format(round(g_glob$gbd_deaths), big.mark = ",")),
  sprintf("   PAF 重算 = %.4f | PAF GBD = %.4f | fold = %.2f",
          g_glob$paf_deaths, g_glob$gbd_paf_deaths, g_glob$fold_deaths),
  "",
  sprintf("★ fold 分布（%d 个国家，已剔 Global；pooled，2022）", nrow(g)),
  sprintf("   中位 %.2f | IQR %.2f–%.2f | 范围 %.2f–%.2f | fold>1 的国家 %d/%d",
          median(g$fold_deaths), quantile(g$fold_deaths, .25), quantile(g$fold_deaths, .75),
          min(g$fold_deaths), max(g$fold_deaths),
          sum(g$fold_deaths > 1), nrow(g)),
  "",
  "★ 按 SDI 五分位（pooled，2022）",
  if (!is.null(BY_SDI)) paste(capture.output(print(
    BY_SDI[rr_source == "pooled" & year == 2022,
           .(quintile, n_country, paf_recomputed = round(paf_recomputed_deaths, 4),
             paf_gbd = round(paf_gbd_deaths, 4), fold_deaths = round(fold_deaths, 2))])),
    collapse = "\n") else "（未生成）",
  "",
  "★ 口径限制（必须写入正文/图注）",
  "   RR 曲线 = Module 2 device_pooled × total_PA（总量型），8 个结局共用同一条 →",
  "   重算 PAF **不随 cause 变化**（cause 间差异全部来自 GBD 分母）。",
  "   故 by_cause 仅用于绝对归因数与 fold，不可解读为病因特异 RR 差异。",
  "",
  sprintf("校验：n_loc=%s | 年份齐全=%s | 双来源=%s | 主情景唯一=%s | PAF 病因恒定=%s | SDI 聚合=%s | SDI 国数=204=%s",
          chk$n_loc, chk$all_yr, chk$both_src, chk$main_unique,
          chk$paf_cause_invariant, chk$sdi_agg, chk$sdi_n)
)
writeLines(rep, file.path(DIR_LOGS,
           paste0(if (N_MAX > 0L) "SMOKE_" else "", "module3_bycountry.txt")), useBytes = TRUE)
cat(paste(rep, collapse = "\n"), "\n")

message(sprintf("\n95c 完成，用时 %.1f min。产物：%s{totals,by_cause,exposure_diag,by_sdi}.csv",
                as.numeric(difftime(Sys.time(), t0, units = "mins")), BY_PREFIX))
