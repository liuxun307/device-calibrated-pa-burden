# =============================================================================
# 00_run_all.R  —  全流程编排器
#
# 用法：
#   Rscript 00_run_all.R                 # 跑完整链条（01 -> 06 -> 98）
#   Rscript 00_run_all.R --from 03       # 从 03 开始（01/02 已有结果时省时）
#   Rscript 00_run_all.R --to 04         # 只跑到 04
#   Rscript 00_run_all.R --only 06,98    # 只跑指定步骤
#   Rscript 00_run_all.R --dry-run       # 只打印将要执行的步骤
#
# 设计要点：
#   * 每一步在【独立 R 进程】中执行 -> 脚本之间零内存污染。
#     本方案历史上出现过"03 在全局环境留下残留对象把 04 的分析集清空"这类
#     静默错误，独立进程从架构上杜绝了这一类问题。
#   * 每步 stdout/stderr 落盘到 logs/<RUN_ID>/step_XX.log，失败时打印日志尾部。
#   * 全部脚本通过共享的 PARADIGM_A_RUN_ID 写入同一日志目录，便于追溯。
#   * 不写死绝对路径：Rscript 位置由 R.home() 推导，项目根由 00_setup.R 推导。
#
# 退出码：0 = 全部步骤成功；1 = 有步骤失败。
# =============================================================================

# ---- 统一引导（勿改）--------------------------------------------------------
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
})

# 本文件所在的 code 目录
.self <- tryCatch({
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(a)) normalizePath(dirname(sub("^--file=", "", a[1])), mustWork = FALSE) else getwd()
}, error = function(e) getwd())

if (!isTRUE(getOption("PA_SETUP_DONE"))) {
  source(file.path(.self, "00_setup.R"))
}

# ---------------------------------------------------------------------------
# 步骤表（顺序即依赖顺序）
# ---------------------------------------------------------------------------
ALL_STEPS <- c(
  "00_setup.R",                    # 环境锁定 + 会话快照
  "01_fetch_data.R",               # 原始数据获取 + 指纹固化 + 台账
  "01b_fetch_pam_2003_2006.R",     # 2003-2006 髋式 PAM 原始件 + rnhanesdata 参考数据（约 20 min，含 ~880 MB 下载）
  "01c_verify_paxinten_vs_raw.R",  # 【核验】参考宽表 vs 原始 xpt 逐人一致性（全文件，约 25 min）
  "02_accel_processing.R",         # 加速度计清洗 -> 暴露
  "03_exposure_merge_survival.R",  # 协变量 + 自评 MET + 死亡合并（2011-2014 腕式）
  "03b_pam_exposure_2003_2006.R",  # 2003-2006 髋式暴露 + 同口径协变量 + 死亡
  "03c_hip_wear_rule_variants.R",  # 髋式 wear 判定规则全谱（5 套，同一分钟矩阵；含与 03b 的 R0 等价性核验）
  "03d_wrist_criterion_variants.R",# 腕式有效日判据全谱（7 套；含与 analytic.rds 的 C0 等价性核验）
  "04_cox_dose_response.R",        # 加权 Cox + RCS 剂量-反应（腕式主线）
  "04b_pam_site_rr.R",             # 佩戴部位效应：髋式 vs 腕式（百分位轴）→ Table 6
  "04c_site_wear_sensitivity.R",   # 部位效应矛盾裁决：髋规则 × 腕判据 → 比值矩阵（含与 04b 的等价性核验）
  "04d_lit_site_contrast.R",       # 文献侧「部位效应」的可分解性 + 与 NHANES 的相容性检验（含指标轴归属机器校验）
  "04f_lit_site_anchor.R",         # 文献侧部位效应的**指标稳健性**：腕式×total_PA 外部锚定 + 与 NHANES 的**同指标**对照
                                   #   （2026-10-16 由 code/tools/site_anchor_totalPA.R 提升为正式步骤；
                                   #    04e 编号已被 04e_pam_intensity_rr.R 占用，故取 04f；依赖 04c 的比值矩阵）
  "05a_module2_bop.R",             # Module 2：外部队列池化（测量方法为协变量）
  "05b_verify_bop_table.R",        # Module 2 输入表审计（百分位复算 + 方向/结构检查）
  "05c_module2_nhanes_site_sensitivity.R",  # 路径 2 收尾：NHANES 两臂接入的**受控敏感性**（不改主池）
  "05d_bop_intake_pending.R",      # 路径 1 待命入表管线（**默认 dry-run**：只校验待入表行，不改 rr_table.csv）
  "05e_bop_leave_one_out.R",       # Module 2 留一法（leave-one-study-out）→ Table 12（自 source 05/05a）
  "05f_evalues.R",                 # E-value 敏感性分析（未测混杂）→ Table 13
  "05_burden_calibration_paf.R",   # 校准 + BoP 合成 + PAF 重算
  "96b_sdi_anchor.R",              # SDI 锚点表（205 国 quintile + 逐年 SDI）→ Table 14（秒级）
  "95_module3_paf.R",              # Module 3：真实池化 RR → PAF 预览（8 地区冻结版，约 15 min）
  "95c_module3_bycountry.R",       # Module 3 逐国版（205 location）→ Fig 5(b)(c) + Table S4 底表（s1p，6 核并行 ≈17 min）
  "95b_paf_impact_compare.R",      # A（文献池 s1p）vs B（+NHANES s1p）影响力对照 → Table 7（2026-10-15 入链：产物被 10 引用，留在链外会与主链不同步）
  "97_m3_scenarios.R",             # Module 3 情景表 + 稳健性 + 国别同质化（约 2 min，影子：不改主链）
  "07_fig5d_waterfall.R",          # Fig 5(d) 口径分解瀑布图（只读 97 的 Table4/9；约 5 s）
  "08a_fig1_design.R",             # Fig 1 研究设计流程图（figures/panel + combined）
  "08b_fig2_sample.R",             # Fig 2 样本流程 + 自报/设备暴露对比（3 panels）
  "08c_fig3_dose_response.R",      # Fig 3 剂量-反应曲线（6 面板，含 peak-30/MVPA 强度维度）
  "08d_fig4_calibration.R",        # Fig 4 校准三面板（含与 Table4 主链一致性对照）
  "08e_fig5_burden.R",             # Fig 5 四面板：(a) 哑铃图 / (b) SDI 分组柱 / (c) 204 国 fold 热图 / (d) 瀑布渲染
  "08f_fig6_sensitivity.R",        # Fig 6 敏感性三面板（a 情景森林 / b 留一法 / c E-value）
  "09_tables.R",                   # Table 1-4 投稿 PDF（加权基线 / HR / 校准 / 负担对比）
  "10_captions.R",                 # 图注 / 表注（中英双语，数值全部从 output/ 产物动态读取；约 6 s）
  "06_manifest.R",                 # 产物清单
  "98_verify_reproducibility.R"    # 可复现性核验
)
step_id <- sub("\\.R$", "", ALL_STEPS)

# ---------------------------------------------------------------------------
# 逐步执行计划（2026-10-16 新增）—— 让「一条命令跑完全链」自足
# ---------------------------------------------------------------------------
# ⚠️ 修的是这个缺口（实测发现）：
#   Module 3 的**主分析产物**是 `PREVIEW_module3_s1p_*.csv`（下称 A 档），由
#   `95_module3_paf.R` 在 `PA_CV_MODE=s1p` 下产出；而该脚本的**默认** CV_MODE 是 `grid`。
#   `code/README.md` §3 因而把主分析写成一条**单独的**命令：
#       PA_CV_MODE=s1p Rscript code/00_run_all.R --only 95_module3_paf
#   但直接 `Rscript code/00_run_all.R` 全链运行时，95 只跑 grid → **A 档不刷新**，
#   退化为陈旧孤儿文件；而下游 07 / 08e / 09 / 10 / 95b 读的正是 A 档
#   （95b 还对它的存在做硬断言）→ Fig 5 / Table 4 / Table 7 / 图注会引用
#   **未参与本次运行**的数据。2026-10-15 的「跨轨假差异」修正只把**消费方**
#   从 grid 改到 s1p，漏了**生产方**，本处补齐。
#   同理 `95b` 的 B 档（`PREVIEW_NHANES_s1p_*`）默认「有则复用」→ 同样会陈旧，
#   故在链中显式传 `--force`。
#   grid 轨仍保留（敏感性双轨，98 的必需产物清单含 `PREVIEW_module3_*`），
#   故 95 在链中按 **grid → s1p** 各跑一次，两者产物文件名互不覆盖。
#
# 结构：step 文件名 → list(轮次)，每轮 = list(tag = 日志后缀, env = 环境变量, args = 追加参数)
#       未登记的 step 默认跑一轮、无额外 env / args。
STEP_PLAN <- list(
  "95_module3_paf.R" = list(
    list(tag = "",    env = list(PA_CV_MODE = "grid")),   # 敏感性双轨（默认口径，产物 PREVIEW_module3_*）
    list(tag = "s1p", env = list(PA_CV_MODE = "s1p"))     # 主分析 A 档（产物 PREVIEW_module3_s1p_*，下游唯一消费）
  ),
  "95b_paf_impact_compare.R" = list(
    list(tag = "", env = list(), args = "--force")        # 强制重算 B 档，避免复用陈旧产物
  )
)

# ---------------------------------------------------------------------------
# 解析命令行
# ---------------------------------------------------------------------------
args <- commandArgs(TRUE)
get_opt <- function(name) {
  i <- match(paste0("--", name), args)
  if (is.na(i)) return(NULL)
  if (i == length(args)) return("")
  args[i + 1]
}
from_n <- get_opt("from"); to_n <- get_opt("to")
only_n <- get_opt("only")
DRY    <- "--dry-run" %in% args

sel <- ALL_STEPS
if (!is.null(only_n) && nzchar(only_n)) {
  want <- trimws(strsplit(only_n, ",")[[1]])
  sel <- ALL_STEPS[step_id %in% want | ALL_STEPS %in% want]
} else {
  if (!is.null(from_n) && nzchar(from_n)) {
    k <- which(step_id == from_n | ALL_STEPS == from_n)
    if (!length(k)) stop("未知起始步骤: ", from_n)
    sel <- sel[k[1]:length(sel)]
  }
  if (!is.null(to_n) && nzchar(to_n)) {
    k <- which(step_id == to_n | ALL_STEPS == to_n)
    if (!length(k)) stop("未知结束步骤: ", to_n)
    sel <- sel[seq_len(which(sel == ALL_STEPS[k[1]]))]
  }
}

# 推导 Rscript 可执行文件（不写死盘符）
rs <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(rs)) rs <- file.path(R.home("bin"), "x64", "Rscript.exe")
if (!file.exists(rs)) rs <- file.path(R.home("bin"), "Rscript")

cat("\n=============================================================\n")
cat(" 范式 A 全流程编排\n")
cat("=============================================================\n")
cat("Rscript   :", rs, "\n")
cat("code 目录 :", DIR_CODE, "\n")
cat("项目根    :", PA_ROOT, "\n")
cat("运行 ID   :", PA_RUN_ID, "\n")
cat("日志目录  :", PA_RUN_DIR, "\n")
cat("将执行    :", paste(sel, collapse = " -> "), "\n")
cat("=============================================================\n\n")

if (DRY) { cat("[dry-run] 未实际执行任何步骤。\n"); quit(status = 0L) }

# ---------------------------------------------------------------------------
# 关键（Windows）：R 无法把含中文的参数转成 native encoding 传给外部进程
#   报错形式：unable to translate '...' to native encoding，或静默失败。
#   解法：切到 code 目录，用【纯 ASCII 相对路径】调用子进程；子进程继承 cwd，
#         并由 --file= 参数自行推导项目根，全程不传含中文的命令行参数。
# ---------------------------------------------------------------------------
.old_wd <- getwd()
setwd(DIR_CODE)

# RUN_ID 是 ASCII 时间戳，可安全传递；PA_ROOT 含中文时不传（子进程能自行推导）
Sys.setenv(PARADIGM_A_RUN_ID = PA_RUN_ID)
if (grepl("^[ -~]*$", PA_ROOT)) Sys.setenv(PARADIGM_A_ROOT = PA_ROOT)

t_all <- Sys.time()
status_tbl <- list()

for (f in sel) {
  id   <- sub("\\.R$", "", f)
  plan <- STEP_PLAN[[f]]
  if (is.null(plan)) plan <- list(list(tag = "", env = list(), args = NULL))
  ok   <- TRUE

  for (ru in plan) {
    rid      <- if (nzchar(ru$tag)) paste0(id, "_", ru$tag) else id
    logf     <- file.path(PA_RUN_DIR, paste0("step_", rid, ".log"))
    logf_rel <- file.path("..", "logs", PA_RUN_ID, paste0("step_", rid, ".log"))
    lbl      <- if (nzchar(ru$tag)) paste0(f, " [", ru$tag, "]") else f
    cat(sprintf("\n---- [%s] %s ", format(Sys.time(), "%H:%M:%S"), lbl))
    cat(strrep("-", max(1, 46 - nchar(lbl))), "\n", sep = "")

    # 本轮专属环境变量：只作用于本轮的 system2 子进程，轮后原样还原。
    # ★ 陷阱：Sys.getenv() 在 names = NA（缺省）下【只在长度 > 1 时】给返回值加名字，
    #   单个变量（如 PA_CV_MODE）返回的是无名向量 → ev_old[[name]] 会 subscript out of bounds。
    #   故还原一律用位置索引 ev_old[i]，不按名字取。
    ev_names <- names(ru$env)
    ev_old   <- if (length(ev_names)) Sys.getenv(ev_names, unset = NA) else character(0)
    if (length(ev_names)) do.call(Sys.setenv, as.list(ru$env))

    t1   <- Sys.time()
    code <- system2(rs, c(f, ru$args), stdout = logf_rel, stderr = logf_rel, wait = TRUE)
    secs <- round(as.numeric(difftime(Sys.time(), t1, units = "secs")), 1)

    if (length(ev_names)) {
      for (i in seq_along(ev_names)) {
        if (is.na(ev_old[i])) Sys.unsetenv(ev_names[i])
        else do.call(Sys.setenv, setNames(list(ev_old[i]), ev_names[i]))
      }
    }

    # 回显关键行（完成 / 警告 / 错误），避免用户必须翻日志
    if (file.exists(logf)) {
      ln <- readLines(logf, warn = FALSE, encoding = "UTF-8")
      key <- grep("完成|失败|缺失|WARN|Error|错误|结论|总体", ln, value = TRUE)
      if (length(key)) cat(paste0("   ", utils::head(key, 12), collapse = "\n"), "\n")
    }

    ok <- identical(as.integer(code), 0L)
    status_tbl[[rid]] <- data.table::data.table(step = f, ok = ok, secs = secs,
                                                log = basename(logf))
    cat(sprintf("   => %s  用时 %.1fs  日志 %s\n",
                if (ok) "成功" else paste0("失败(退出码 ", code, ")"), secs, basename(logf)))

    if (!ok) {
      cat("\n!! 步骤失败，已中止。诊断信息（日志尾部）：\n")
      ln <- readLines(logf, warn = FALSE, encoding = "UTF-8")
      cat(paste0("   ", utils::tail(ln, 30), collapse = "\n"), "\n")
      cat("\n完整日志：", logf, "\n")
      break
    }
  }
  if (!ok) break
}

# ---------------------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------------------
st <- data.table::rbindlist(status_tbl, fill = TRUE)
if (nrow(st)) data.table::fwrite(st, file.path(PA_RUN_DIR, "steps_summary.csv"))

el <- round(as.numeric(difftime(Sys.time(), t_all, units = "mins")), 1)
n_fail <- if (nrow(st)) sum(!st$ok) else length(sel)

cat("\n=============================================================\n")
if (n_fail == 0L) {
  cat(" 全部步骤成功，总用时 ", el, " 分钟\n", sep = "")
  cat(" 交付物   : output/\n")
  cat(" 产物清单 : output/manifest.csv\n")
  cat(" 复现报告 : output/REPRODUCIBILITY_REPORT.txt\n")
  cat(" 运行日志 : ", PA_RUN_DIR, "\n", sep = "")
} else {
  cat(" 有 ", n_fail, " 个步骤失败，总用时 ", el, " 分钟\n", sep = "")
  cat(" 请查看 ", PA_RUN_DIR, " 下对应 step_*.log\n", sep = "")
}
cat("=============================================================\n")

quit(status = if (n_fail == 0L) 0L else 1L)
