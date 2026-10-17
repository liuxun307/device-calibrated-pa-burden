# =============================================================================
# 00_setup.R  —  环境锁定 · 路径常量 · 随机种子 · 会话快照 · 通用工具
#
# 作用：01-06 / 98-99 全部脚本的第一件事就是 source 本文件（幂等，
#       由 options("PA_SETUP_DONE") 守护，重复 source 不会重复执行）。
#       单独运行本文件亦可，用于查看或固化当前环境。
#
# 只向 globalenv 导出以下对象（内部临时变量全部封在 local() 内，避免污染）：
#   PA                          配置总表（list）
#   PA_ROOT                     项目根目录（字符）
#   DIR_RAW DIR_DERIV DIR_GBD DIR_BOP DIR_OUT DIR_LOGS DIR_SOURCES DIR_CODE
#   PA_SEED                     本次运行的随机种子
#   PA_RUN_ID / PA_RUN_DIR      本次运行的时间戳 ID 与日志目录
#   TMREL_LO_MET TMREL_HI_MET   跨脚本科学常量：GBD 2023 LPA 的 TMREL（MET-min/周）
#   TMREL_LO_MIMS TMREL_HI_MIMS TMREL_MID_MIMS SIGMA_MIMS_REF
#                               上者的设备等效值（MIMS/day）与校准残差 SD
#                               —— 派生量，由 05 重算并断言（见 §7b）
#   pa_hash()  pa_log()  pa_pkg_versions()  pa_session_snapshot()  pa_seed_with()
# =============================================================================

if (isTRUE(getOption("PA_SETUP_DONE"))) {
  # 已初始化，静默跳过
} else {

local({
  # ---------------------------------------------------------------------------
  # 0. 输出编码：源文件以 UTF-8 保存，显式声明避免 Windows 下错码
  # ---------------------------------------------------------------------------
  options(encoding = "UTF-8")

  # ---------------------------------------------------------------------------
  # 1. locale 引导（Windows 必需）
  #    R 在中文 Windows 上启动时 LC_CTYPE 常为 "C"，此时：
  #      - list.files() 对中文目录返回 character(0)
  #      - source() 会截断中文路径
  #      - 图形设备渲染中文报 mbcsToSbcs conversion failure
  #    置为 UTF-8 locale 后前两条恢复；第三条无解，图内标签必须用 ASCII。
  # ---------------------------------------------------------------------------
  LOCALE_TRIED <- c("Chinese_China.utf8", "zh_CN.UTF-8", "Chinese_China.936",
                    "English_United States.utf8", "C.UTF-8")
  locale_hits <- vapply(LOCALE_TRIED, function(loc)
    nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc))), logical(1))

  # ---------------------------------------------------------------------------
  # 2. 定位项目根目录（三级兜底）
  # ---------------------------------------------------------------------------
  this_file <- tryCatch({
    # (a) source() 时
    f <- sys.frame(1)$ofile
    if (is.null(f) || !nzchar(f)) NA_character_ else normalizePath(f, mustWork = FALSE)
  }, error = function(e) NA_character_)

  if (is.na(this_file)) {
    # (b) Rscript 时
    a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
    if (length(a)) this_file <- normalizePath(sub("^--file=", "", a[1]), mustWork = FALSE)
  }
  if (is.na(this_file)) {
    # (c) 当前工作目录
    this_file <- file.path(getwd(), "00_setup.R")
  }

  # 根目录优先级：环境变量 > 本文件位于 <root>/code/ 推得 > 工作目录
  root_from_env <- Sys.getenv("PARADIGM_A_ROOT", unset = "")
  if (nzchar(root_from_env)) {
    PA_ROOT <- normalizePath(root_from_env, mustWork = FALSE)
  } else if (basename(dirname(this_file)) == "code") {
    PA_ROOT <- dirname(dirname(this_file))
  } else {
    PA_ROOT <- normalizePath(file.path(getwd(), ".."), mustWork = FALSE)
  }
  PA_ROOT <- gsub("\\\\", "/", PA_ROOT)

  # ---------------------------------------------------------------------------
  # 3. 目录常量
  # ---------------------------------------------------------------------------
  DIR_CODE    <- file.path(PA_ROOT, "code")
  DIR_RAW     <- file.path(PA_ROOT, "data", "raw")       # 原始数据（下载所得，只读）
  DIR_DERIV   <- file.path(PA_ROOT, "data", "derived")   # 中间缓存 rds
  DIR_GBD     <- file.path(PA_ROOT, "data", "gbd")       # GBD 手工获取结果
  DIR_BOP     <- file.path(PA_ROOT, "data", "bop")       # Module 2 外部证据输入（rr_table.csv）
  DIR_SOURCES <- file.path(PA_ROOT, "data", "sources")   # 数据来源清单 / 校验和 / 官方读入程序
  DIR_OUT     <- file.path(PA_ROOT, "output")            # 图表与表格（交付物）
  DIR_LOGS    <- file.path(PA_ROOT, "logs")              # 运行日志与环境快照

  for (d in c(DIR_RAW, DIR_DERIV, DIR_GBD, DIR_BOP, DIR_SOURCES, DIR_OUT, DIR_LOGS)) {
    dir.create(d, showWarnings = FALSE, recursive = TRUE)
  }

  # ---------------------------------------------------------------------------
  # 4. 本次运行标识（供日志隔离；由 00_run_all.R 预先设定以便整批共用）
  # ---------------------------------------------------------------------------
  PA_RUN_ID  <- Sys.getenv("PARADIGM_A_RUN_ID",
                           unset = format(Sys.time(), "%Y%m%d_%H%M%S"))
  PA_RUN_DIR <- file.path(DIR_LOGS, PA_RUN_ID)
  dir.create(PA_RUN_DIR, showWarnings = FALSE, recursive = TRUE)

  # ---------------------------------------------------------------------------
  # 5. 随机种子（固定，可被环境变量覆盖以做种子敏感性分析）
  #    影响：Bootstrap、多重插补、贝叶斯抽样（brms/Stan）、任何 sample()
  #    RNGkind 一并记录，否则"同种子不同结果"无法解释。
  # ---------------------------------------------------------------------------
  PA_SEED <- as.integer(Sys.getenv("PARADIGM_A_SEED", unset = "20261011"))
  RNGkind(kind = "Mersenne-Twister", normal.kind = "Inversion",
          sample.kind = "Rejection")   # 显式锁定 R >= 3.6 默认值
  set.seed(PA_SEED)

  # ---------------------------------------------------------------------------
  # 6. 依赖包：必需 / 可选
  # ---------------------------------------------------------------------------
  PKGS_REQUIRED <- c("data.table", "haven", "tidyverse", "survival", "survey", "splines",
                     # metafor：05a 的兜底引擎 + 05c/05e/10 的池化与汇总，链条内多处依赖
                     "metafor")
  PKGS_OPTIONAL <- c(
    # Module 2 默认**真贝叶斯**引擎（2026-10-16 起）：三者齐备才走 brms，否则静默回退 metafor
    "brms", "rstan", "StanHeaders",
    "cmdstanr", "clubSandwich", "digest", "patchwork", "rms", "nhanesA", "renv")

  .installed <- rownames(installed.packages())
  missing_required <- setdiff(PKGS_REQUIRED, .installed)

  pkg_versions <- function() {
    all_p <- rownames(installed.packages())
    v <- vapply(all_p, function(p) as.character(utils::packageVersion(p)), character(1))
    data.frame(package = all_p, version = unname(v), stringsAsFactors = FALSE)
  }

  # ---------------------------------------------------------------------------
  # 7. 通用工具函数
  # ---------------------------------------------------------------------------

  # 文件指纹：优先 SHA-256（digest），否则退回 MD5（tools，base 自带）
  pa_hash <- function(paths, algo = c("sha256", "md5")) {
    algo <- match.arg(algo)
    paths <- as.character(paths)
    out <- rep(NA_character_, length(paths))
    keep <- !is.na(paths) & file.exists(paths)
    if (!any(keep)) return(out)
    if (algo == "sha256" && requireNamespace("digest", quietly = TRUE)) {
      out[keep] <- vapply(paths[keep], function(p)
        digest::digest(file = p, algo = "sha256"), character(1))
    } else {
      out[keep] <- unname(tools::md5sum(paths[keep]))
    }
    out
  }

  # 统一日志：同时写控制台与本次运行的日志文件（append）
  pa_log <- function(..., level = "INFO") {
    msg <- sprintf("[%s] [%s] %s",
                   format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level,
                   paste0(..., collapse = ""))
    cat(msg, "\n", sep = "")
    lf <- file.path(PA_RUN_DIR, "run.log")
    try(cat(msg, "\n", file = lf, append = TRUE, sep = ""), silent = TRUE)
    invisible(msg)
  }

  # 带种子的局部求值（用于任何随机过程），保证可复现且不污染全局 RNG 状态
  pa_seed_with <- function(seed = PA_SEED, expr) {
    old <- if (exists(".Random.seed", envir = globalenv())) {
      get(".Random.seed", envir = globalenv())
    } else NULL
    set.seed(seed)
    on.exit({
      if (is.null(old)) {
        if (exists(".Random.seed", envir = globalenv()))
          rm(".Random.seed", envir = globalenv())
      } else assign(".Random.seed", old, envir = globalenv())
    }, add = TRUE)
    force(expr)
  }

  # 会话与环境快照落盘（返回文件路径）
  pa_session_snapshot <- function(tag = "session") {
    stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    txt <- file.path(PA_RUN_DIR, sprintf("%s-info_%s.txt", tag, stamp))
    sink(txt)
    cat("== 项目 ==\n"); cat("PA_ROOT :", PA_ROOT, "\n"); cat("RUN_ID  :", PA_RUN_ID, "\n")
    cat("\n== 时间 ==\n"); print(Sys.time()); cat("TZ:", Sys.timezone(), "\n")
    cat("\n== 系统 ==\n"); print(Sys.info())
    cat("\n== R ==\n"); print(R.version)
    cat("\n== RNG ==\n"); print(RNGkind()); cat("PA_SEED :", PA_SEED, "\n")
    cat("\n== locale ==\n"); print(Sys.getlocale())
    cat("\n== 包版本 ==\n"); print(pkg_versions())
    cat("\n== 库路径 ==\n"); print(.libPaths())
    cat("\n== sessionInfo ==\n"); print(sessionInfo())
    sink()
    # CSV 版（便于 diff）
    csv <- file.path(DIR_LOGS, "pkg-versions_latest.csv")
    utils::write.csv(pkg_versions(), csv, row.names = FALSE)
    c(txt = txt, csv = csv)
  }

  # ---------------------------------------------------------------------------
  # 7b. 跨脚本科学常量（单一真源）
  #
  #   为什么放在本文件：`04`（剂量-反应曲线）在 `05`（校准）**之前**执行，但它的
  #   参照点必须是 `05` 校准出的「GBD TMREL 设备等效值」。旧版让 04 用 `REF_PCT=60`
  #   占位分位（→ 13,936.5 MIMS/day），造成"04 用占位、05 用 TMREL"的口径分裂。
  #   把派生量登记在此，04 与 05 共用同一个绝对锚点。
  #
  #   ⚠️ TMREL_*_MIMS / SIGMA_MIMS_REF 是**派生量**，不是自由参数：
  #      由 05 的校准回归 `mims_per_day ~ ns(met_min_wk,3) + age*female`
  #      （NHANES 2011-2014 自报 MET ↔ 设备 MIMS，n=7,854）设备等效化得到，且经过
  #      cummax() 单调化（原自然样条在数据两端回折，见 05 的实测缺陷注释）。
  #      05 每次运行都会**重算并与本常量断言一致** —— 校准数据一变立即报错，
  #      提示同步更新此处，绝不静默漂移。
  #
  #   口径来源：GBD 2023 LPA case definition —— 25 岁以上、每领域每次 ≥10 min、
  #             总 MET-min/周 < 3600–4400（JACC 2025 复述）。旧 3000–4500 属
  #             GBD 2021，已废弃。
  # ---------------------------------------------------------------------------
  TMREL_LO_MET   <- 3600
  TMREL_HI_MET   <- 4400
  TMREL_LO_MIMS  <- 13168.4765682372   # pred_mims(3600)
  TMREL_HI_MIMS  <- 13275.6693256004   # pred_mims(4400)
  TMREL_MID_MIMS <- (TMREL_LO_MIMS + TMREL_HI_MIMS) / 2   # 13222.0729469188
  SIGMA_MIMS_REF <- 3335.3558805624    # sd(residuals(m_cal))

  # ---------------------------------------------------------------------------
  # 8. 汇总配置表并导出
  # ---------------------------------------------------------------------------
  PA <- list(
    root         = PA_ROOT,
    dirs         = list(code = DIR_CODE, raw = DIR_RAW, derived = DIR_DERIV,
                        gbd = DIR_GBD, bop = DIR_BOP, sources = DIR_SOURCES,
                        out = DIR_OUT, logs = DIR_LOGS, run = PA_RUN_DIR),
    seed         = PA_SEED,
    run_id       = PA_RUN_ID,
    locale_tried = LOCALE_TRIED,
    locale_hits  = locale_hits,
    lc_ctype     = Sys.getlocale("LC_CTYPE"),
    pkgs_required = PKGS_REQUIRED,
    pkgs_optional = PKGS_OPTIONAL,
    pkgs_missing  = missing_required,
    r_version    = as.character(getRversion()),
    started_at   = Sys.time(),
    tmrel         = list(lo_met = TMREL_LO_MET, hi_met = TMREL_HI_MET,
                         lo_mims = TMREL_LO_MIMS, hi_mims = TMREL_HI_MIMS,
                         mid_mims = TMREL_MID_MIMS, sigma_mims = SIGMA_MIMS_REF)
  )

  g <- globalenv()
  assign("PA", PA, envir = g)
  assign("PA_ROOT", PA_ROOT, envir = g)
  assign("PA_SEED", PA_SEED, envir = g)
  assign("PA_RUN_ID", PA_RUN_ID, envir = g)
  assign("PA_RUN_DIR", PA_RUN_DIR, envir = g)
  assign("DIR_CODE", DIR_CODE, envir = g)
  assign("DIR_RAW", DIR_RAW, envir = g)
  assign("DIR_DERIV", DIR_DERIV, envir = g)
  assign("DIR_GBD", DIR_GBD, envir = g)
  assign("DIR_BOP", DIR_BOP, envir = g)
  assign("DIR_SOURCES", DIR_SOURCES, envir = g)
  assign("DIR_OUT", DIR_OUT, envir = g)
  assign("DIR_LOGS", DIR_LOGS, envir = g)
  assign("TMREL_LO_MET", TMREL_LO_MET, envir = g)
  assign("TMREL_HI_MET", TMREL_HI_MET, envir = g)
  assign("TMREL_LO_MIMS", TMREL_LO_MIMS, envir = g)
  assign("TMREL_HI_MIMS", TMREL_HI_MIMS, envir = g)
  assign("TMREL_MID_MIMS", TMREL_MID_MIMS, envir = g)
  assign("SIGMA_MIMS_REF", SIGMA_MIMS_REF, envir = g)
  assign("pa_hash", pa_hash, envir = g)
  assign("pa_log", pa_log, envir = g)
  assign("pa_seed_with", pa_seed_with, envir = g)
  assign("pa_session_snapshot", pa_session_snapshot, envir = g)
  assign("pa_pkg_versions", pkg_versions, envir = g)
})

  options(PA_SETUP_DONE = TRUE)

  # ---------------------------------------------------------------------------
  # 9. 启动横幅（屏幕 + 日志）
  # ---------------------------------------------------------------------------
  pa_log("00_setup 完成")
  pa_log("PA_ROOT   = ", PA_ROOT)
  pa_log("RUN_ID    = ", PA_RUN_ID)
  pa_log("LC_CTYPE  = ", Sys.getlocale("LC_CTYPE"),
         if (grepl("UTF-8|utf8|936", Sys.getlocale("LC_CTYPE"))) "  (中文路径可用)"
         else "  !! 非 UTF-8，中文路径可能失败，见 README")
  pa_log("R 版本    = ", as.character(getRversion()))
  pa_log("随机种子  = ", PA_SEED)

  if (length(PA$pkgs_missing)) {
    pa_log("缺失必需包: ", paste(PA$pkgs_missing, collapse = ", "), level = "WARN")
    pa_log("  安装命令: install.packages(c(",
           paste0('"', PA$pkgs_missing, '"', collapse = ", "), "))", level = "WARN")
  } else {
    pa_log("依赖包检查: 必需包全部就绪")
  }
  opt_missing <- setdiff(PA$pkgs_optional, rownames(installed.packages()))
  if (length(opt_missing))
    pa_log("可选包未装（按需安装）: ", paste(opt_missing, collapse = ", "))

  invisible(PA)
}
