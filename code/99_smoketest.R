# =============================================================================
# 99_smoketest.R  —— 真实管道测试（不接触真实数据，不需要联网）
# 做法：在独立目录里造出符合 NHANES 变量结构的合成数据（含故意植入的质控违规），
#       然后按序 source 02 -> 03 -> 04 -> 05，验证全链路能跑通并产出文件。
# 用法：Rscript 99_smoketest.R
# =============================================================================

suppressPackageStartupMessages({ library(data.table); library(haven) })

local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8",
                "English_United States.utf8", "C.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
})

CODE <- dirname(gsub("\\\\", "/", normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))))
if (is.na(CODE) || !dir.exists(CODE)) CODE <- getwd()
cat("CODE =", CODE, "\n")

SMOKE <- file.path(dirname(CODE), "_smoketest")
unlink(SMOKE, recursive = TRUE)
for (d in c("data/raw", "data/derived", "data/gbd", "output"))
  dir.create(file.path(SMOKE, d), recursive = TRUE, showWarnings = FALSE)
Sys.setenv(PARADIGM_A_ROOT = SMOKE)

set.seed(20261011)
N <- 1500                      # 参与者
ids_G <- 60000 + seq_len(750)  # 2011-2012 周期
ids_H <- 70000 + seq_len(750)  # 2013-2014 周期

# ---------- 1. 参与者层：潜在活动量 + 死亡风险 ---------------------------------
pt <- data.table(
  SEQN      = c(ids_G, ids_H),
  cycle     = rep(c("G", "H"), each = 750),
  RIDAGEYR  = pmin(85, pmax(25, round(rnorm(N, 55, 15)))),
  RIAGENDR  = sample(1:2, N, TRUE),
  RIDRETH3  = sample(1:5, N, TRUE, prob = c(.15, .12, .40, .22, .11)),
  DMDEDUC2  = sample(1:5, N, TRUE),
  INDFMPIR  = round(runif(N, 0.2, 5), 2),
  SDMVPSU   = sample(1:15, N, TRUE),
  SDMVSTRA  = sample(1:15, N, TRUE),
  WTMEC2YR  = round(runif(N, 20000, 60000))
)
# 潜在活动量：年龄越大越低
pt[, latent := rnorm(N, 14000 - 90 * (RIDAGEYR - 25), 3500)]

# ---------- 2. PAXDAY（日级加速度计）-------------------------------------------
mk_day <- function(cyc, ids) {
  d <- CJ(SEQN = ids, PAXDAYM = 1:7)
  d <- merge(d, pt[cycle == cyc, .(SEQN, latent)], by = "SEQN")
  # 按 24h 上限逐项截断，保证 佩戴分钟 之和 <= 1440（真实数据满足该约束）
  d[, PAXWWMD := pmin(1440, pmax(0, round(rnorm(.N, 790, 130))))]
  d[, PAXSWMD := pmin(1440 - PAXWWMD, pmax(0, round(rnorm(.N, 420,  70))))]
  d[, PAXNWMD := pmin(1440 - PAXWWMD - PAXSWMD, pmax(0, round(rnorm(.N, 90, 60))))]
  d[, PAXUMD  := pmin(1440 - PAXWWMD - PAXSWMD - PAXNWMD, pmax(0, round(rnorm(.N, 25, 20))))]
  d[, PAXDAYWM := sample(c("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"),
                         7 * length(ids), TRUE)]
  # 约 8% 的参与者前 5 天佩戴不足 10h（测试有效日过滤）；须在计算 PAXVMD 之前施加
  short <- sample(ids, round(0.08 * length(ids)))
  d[SEQN %in% short & PAXDAYM <= 5, PAXWWMD := 300]
  d[, PAXVMD := PAXWWMD + PAXSWMD + PAXNWMD + PAXUMD]
  d[, PAXTMD := pmin(1440, PAXVMD + pmax(0, round(rnorm(.N, 0, 2))))]
  d[, PAXMTSD := pmax(0, latent + rnorm(.N, 0, 1500))]

  # 故意植入质控违规：约 1% 行的 PAXVMD 与分项之和不符（应在 QC 报告中显示 ~1%）
  bad <- sample(nrow(d), round(0.01 * nrow(d)))
  d[bad, PAXVMD := PAXVMD + 7]
  d[]
  d[, .(SEQN, PAXDAYM, PAXDAYWM, PAXMTSD, PAXWWMD, PAXSWMD, PAXNWMD, PAXUMD, PAXVMD, PAXTMD)]
}
write_xpt(as.data.frame(mk_day("G", ids_G)), file.path(SMOKE, "data/raw/PAXDAY_G.xpt"))
write_xpt(as.data.frame(mk_day("H", ids_H)), file.path(SMOKE, "data/raw/PAXDAY_H.xpt"))

# ---------- 3. 其余派生 rds（模拟 01 的输出）---------------------------------
save_rds <- function(x, nm) saveRDS(x, file.path(SMOKE, "data/derived", paste0(nm, ".rds")))

g <- pt[cycle == "G"]; h <- pt[cycle == "H"]
save_rds(pt[cycle == "G", .(SEQN, RIDAGEYR, RIAGENDR, RIDRETH3, DMDEDUC2, INDFMPIR,
                            WTMEC2YR, SDMVPSU, SDMVSTRA)], "DEMO_G")
save_rds(pt[cycle == "H", .(SEQN, RIDAGEYR, RIAGENDR, RIDRETH3, DMDEDUC2, INDFMPIR,
                            WTMEC2YR, SDMVPSU, SDMVSTRA)], "DEMO_H")

# 自报 PAQ：与设备活动量弱相关（模拟真实的自报高估）
mk_paq <- function(cyc) {
  x <- pt[cycle == cyc]
  x[, `:=`(
    PAQ605 = rbinom(.N, 1, .35), PAQ610 = 3, PAD615 = pmax(0, round(rnorm(.N, 40, 25))),
    PAQ620 = rbinom(.N, 1, .55), PAQ625 = 4, PAD630 = pmax(0, round(rnorm(.N, 55, 30))),
    PAQ635 = rbinom(.N, 1, .30), PAQ640 = 3, PAD645 = pmax(0, round(rnorm(.N, 30, 20))),
    PAQ650 = rbinom(.N, 1, .25), PAQ655 = 3, PAD660 = pmax(0, round(rnorm(.N, 45, 25))),
    PAQ665 = rbinom(.N, 1, .45), PAQ670 = 4, PAD675 = pmax(0, round(rnorm(.N, 50, 25))),
    PAD680 = pmax(0, round(rnorm(.N, 380, 150)))
  )]
  # 注入少量特殊码 7777/9999，测试 num_clean()
  x[sample(.N, 5), PAD615 := 9999]
  x[, .(SEQN, PAQ605, PAQ610, PAD615, PAQ620, PAQ625, PAD630, PAQ635, PAQ640, PAD645,
        PAQ650, PAQ655, PAD660, PAQ665, PAQ670, PAD675, PAD680)]
}
save_rds(mk_paq("G"), "PAQ_G"); save_rds(mk_paq("H"), "PAQ_H")

mk_cyc <- function(cyc, cols, gen) { x <- pt[cycle == cyc]; x <- gen(x); x[, c("SEQN", cols), with = FALSE] }

save_rds(mk_cyc("G", c("BMXBMI","BMXWAIST"), function(x) x[, `:=`(BMXBMI = round(rnorm(.N, 28, 5.5), 1), BMXWAIST = round(rnorm(.N, 98, 14), 1))]), "BMX_G")
save_rds(mk_cyc("H", c("BMXBMI","BMXWAIST"), function(x) x[, `:=`(BMXBMI = round(rnorm(.N, 28, 5.5), 1), BMXWAIST = round(rnorm(.N, 98, 14), 1))]), "BMX_H")

mk_bpx <- function(cyc) { x <- pt[cycle == cyc]
  x[, `:=`(BPXSY1 = round(rnorm(.N, 126, 18)), BPXSY2 = round(rnorm(.N, 125, 18)),
           BPXSY3 = round(rnorm(.N, 125, 18)), BPXSY4 = round(rnorm(.N, 124, 18)))]
  x[, .(SEQN, BPXSY1, BPXSY2, BPXSY3, BPXSY4)] }
save_rds(mk_bpx("G"), "BPX_G"); save_rds(mk_bpx("H"), "BPX_H")

save_rds(mk_cyc("G", "LBXSCR", function(x) x[, LBXSCR := round(runif(.N, .5, 1.4), 2)]), "BIOPRO_G")
save_rds(mk_cyc("H", "LBXSCR", function(x) x[, LBXSCR := round(runif(.N, .5, 1.4), 2)]), "BIOPRO_H")
save_rds(mk_cyc("G", "LBXGH",  function(x) x[, LBXGH  := round(runif(.N, 4.8, 7.5), 1)]), "GHB_G")
save_rds(mk_cyc("H", "LBXGH",  function(x) x[, LBXGH  := round(runif(.N, 4.8, 7.5), 1)]), "GHB_H")
save_rds(mk_cyc("G", "LBDHDD", function(x) x[, LBDHDD := round(runif(.N, 30, 80), 1)]),  "HDL_G")
save_rds(mk_cyc("H", "LBDHDD", function(x) x[, LBDHDD := round(runif(.N, 30, 80), 1)]),  "HDL_H")
save_rds(mk_cyc("G", "LBXTR",  function(x) x[, LBXTR  := round(runif(.N, 50, 260), 1)]), "TRIGLY_G")
save_rds(mk_cyc("H", "LBXTR",  function(x) x[, LBXTR  := round(runif(.N, 50, 260), 1)]), "TRIGLY_H")

save_rds(mk_cyc("G", c("SMQ020","SMQ040"), function(x) x[, `:=`(SMQ020 = rbinom(.N,1,.45), SMQ040 = sample(1:3,.N,TRUE))]), "SMQ_G")
save_rds(mk_cyc("H", c("SMQ020","SMQ040"), function(x) x[, `:=`(SMQ020 = rbinom(.N,1,.45), SMQ040 = sample(1:3,.N,TRUE))]), "SMQ_H")
save_rds(mk_cyc("G", "ALQ101", function(x) x[, ALQ101 := rbinom(.N,1,.6)]), "ALQ_G")
save_rds(mk_cyc("H", "ALQ101", function(x) x[, ALQ101 := rbinom(.N,1,.6)]), "ALQ_H")
save_rds(mk_cyc("G", "DIQ010", function(x) x[, DIQ010 := rbinom(.N,1,.15)]), "DIQ_G")
save_rds(mk_cyc("H", "DIQ010", function(x) x[, DIQ010 := rbinom(.N,1,.15)]), "DIQ_H")
mk_mcq <- function(cyc) mk_cyc(cyc, c("MCQ160B","MCQ160D","MCQ160E","MCQ160F"),
                               function(x) x[, `:=`(MCQ160B = rbinom(.N,1,.06), MCQ160D = rbinom(.N,1,.05),
                                                    MCQ160E = rbinom(.N,1,.04), MCQ160F = rbinom(.N,1,.05))])
save_rds(mk_mcq("G"), "MCQ_G"); save_rds(mk_mcq("H"), "MCQ_H")

# 死亡文件：活动量越低、年龄越大，死亡风险越高（保证 Cox 有可估的信号）
mort <- copy(pt)
mort[, eta := -3.1 + 0.055 * (RIDAGEYR - 25) - 0.00011 * latent]
mort[, died := rbinom(.N, 1, plogis(eta))]
mort[, `:=`(
  ELIGSTAT     = 1L,
  MORTSTAT     = died,
  # UCOD_LEADING 取 1=心脏病 / 2=恶性肿瘤 / 5=脑血管病（与官方编码一致）
  UCOD_LEADING = fifelse(died == 1, sample(c(1L, 2L, 5L), .N, TRUE), 0L),
  PERMTH_EXM   = fifelse(died == 1, pmax(1, round(runif(.N, 6, 96))), round(runif(.N, 60, 96)))
)]
mort[, PERMTH_INT := PERMTH_EXM]
mort[, `:=`(DIABETES = 0L, HYPERTEN = 0L)]
save_rds(mort[, .(SEQN, ELIGSTAT, MORTSTAT, UCOD_LEADING, PERMTH_INT, PERMTH_EXM, DIABETES, HYPERTEN)],
         "MORT_2011_2014")

# ---------- 4. 假的 GBD 2023 结果表 -------------------------------------------
# 2026-10-11 更正：GBD 2021 起 LPA 的 risk–outcome pair 为 8 类（非 5 类），
# 名称也须与 GBD cause 正式名一致（Stroke 整体 / Diabetes mellitus 不分型）。
# 合成数据必须反映这一真实结构，否则测不出 05 的 cause 匹配逻辑是否工作。
gbd <- data.table(
  cause_name = c("Ischemic heart disease", "Stroke", "Diabetes mellitus",
                 "Chronic kidney disease", "Lower extremity peripheral arterial disease",
                 "Colon and rectum cancer", "Breast cancer", "Tuberculosis"),
  deaths_total = c(9.0e6, 3.6e6, 1.5e6, 1.6e6, 1.0e5, 9.0e5, 7.0e5, 1.2e6),
  dalys_total  = c(1.93e8, 1.57e8, 9.0e7, 3.0e7, 2.0e6, 2.0e7, 1.9e7, 4.0e7)
)
fwrite(gbd, file.path(SMOKE, "data/gbd/risk_lpa_2023.csv"))
fwrite(gbd, file.path(SMOKE, "data/gbd/cause_lpa_2023.csv"))

cat("\n########## 合成数据就绪:", SMOKE, "##########\n")

# ---------- 5. 语法解析检查（含 01，01 只解析不执行）-------------------------
cat("\n===== 语法解析检查 =====\n")
for (f in sort(list.files(CODE, pattern = "\\.R$", full.names = TRUE))) {
  ok <- tryCatch({ parse(f); TRUE }, error = function(e) { cat("FAIL", basename(f), ":", conditionMessage(e), "\n"); FALSE })
  if (ok) cat("OK  ", basename(f), "\n")
}

# ---------- 6. 按序执行 02 -> 06（独立进程，与 00_run_all.R 行为完全一致）----
# 为什么用独立进程：本方案历史上出现过"03 在全局环境留下残留对象 peak30=NULL，
# 把 04 的动态列筛选择空、静默产出空图"这类错误。独立进程从架构上杜绝该问题，
# 冒烟测试必须与正式运行方式一致，否则测不出真实行为。
#
# Windows 关键约束：R 无法把含中文的路径参数转成 native encoding 传给外部进程。
# 解法：把 code 复制进沙箱，setwd(SMOKE) 后用纯 ASCII 相对路径调用子进程。
RS <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(RS)) RS <- file.path(R.home("bin"), "x64", "Rscript.exe")
if (!file.exists(RS)) RS <- file.path(R.home("bin"), "Rscript")

dir.create(file.path(SMOKE, "code"), showWarnings = FALSE, recursive = TRUE)
cp_ok <- file.copy(list.files(CODE, pattern = "\\.R$", full.names = TRUE),
                   file.path(SMOKE, "code"), overwrite = TRUE)
if (!all(cp_ok)) stop("复制 code/ 到沙箱失败（file.copy 返回 FALSE）")

setwd(SMOKE)
Sys.setenv(PARADIGM_A_RUN_ID = format(Sys.time(), "%Y%m%d_%H%M%S"))

run_step <- function(f) {
  cat("\n===== 执行 ", f, " =====\n", sep = "")
  st <- system2(RS, file.path("code", f), stdout = "", stderr = "")
  if (!identical(as.integer(st), 0L)) stop("步骤失败：", f, " 退出码 ", st)
  invisible(TRUE)
}
for (f in c("02_accel_processing.R", "03_exposure_merge_survival.R",
            "04_cox_dose_response.R", "05_burden_calibration_paf.R",
            "06_manifest.R")) run_step(f)

# ---------- 7. 函数级验证：PAF 数学（隔离环境内 source 05 后求值）-------------
cat("\n===== 验证 PAF 数学与 recompute_burden =====\n")
setwd(CODE)   # 05 内的引导需在 code 目录下定位 00_setup.R
loc <- new.env(parent = globalenv())
sys.source(file.path(CODE, "05_burden_calibration_paf.R"), envir = loc)
px   <- c(0.30, 0.35, 0.25, 0.10)     # 暴露档位占比
rr_x <- c(1.30, 1.15, 1.05, 1.00)     # 对应 RR
paf  <- loc$paf_from_dist(px, rr_x)
cat(sprintf("PAF = %.4f\n", paf))
stopifnot(abs(paf - sum(px * (rr_x - 1)) / (1 + sum(px * (rr_x - 1)))) < 1e-12)
cat("PAF 与闭式解一致性检查: 通过\n")
# 7a. cause 清单：合成数据下应为 8 类，且绝不含 All causes
gbd_ct <- fread(file.path(SMOKE, "data/gbd/cause_lpa_2023.csv"))
cat(sprintf("\n合成 cause 总负担表: %d 行 / %d 个结局\n", nrow(gbd_ct), uniqueN(gbd_ct$cause_name)))
cat("LPA_CAUSES 数:", length(loc$LPA_CAUSES), "\n")
stopifnot(length(loc$LPA_CAUSES) == 8L)
stopifnot(!any(loc$norm_cause(loc$LPA_CAUSES) == "all causes"))

# 7b. 正常路径：分母齐全 -> 应正常产出 8 行
tb <- loc$recompute_burden(px, function() rr_x, gbd_ct, n_draws = 30)
print(tb)
stopifnot(nrow(tb) == 8L, all(is.finite(tb$deaths_attrib)), all(is.finite(tb$dalys_attrib)))
cat("正常路径通过：8 个结局全部产出有限值\n")

# 7c. 负向测试：分母缺一个 cause 必须报错（旧版会静默丢结果 -> 空表）
bad <- gbd_ct[cause_name != "Tuberculosis"]
r <- try(loc$recompute_burden(px, function() rr_x, bad, n_draws = 2), silent = TRUE)
cat("\n[负向测试 1] 抽掉 Tuberculosis 后是否报错:", inherits(r, "try-error"), "\n")
stopifnot(inherits(r, "try-error"))
cat("  错误信息前 2 行:",
    paste(head(strsplit(conditionMessage(attr(r, "condition")), "\n")[[1]], 2), collapse = " / "), "\n")

# 7d. 负向测试：误把文件路径当数据表传入（旧版会静默产出空结果）
r2 <- try(loc$recompute_burden(px, function() rr_x, loc$gbd_risk, n_draws = 2), silent = TRUE)
cat("[负向测试 2] 误传文件路径是否报错:", inherits(r2, "try-error"), "\n")
stopifnot(inherits(r2, "try-error"))
cat("  错误信息:", conditionMessage(attr(r2, "condition")), "\n")

# ---------- 8. 校验器自检：在合成数据上运行 98 --------------------------------
# 合成数据没有 data/sources/checksums.csv（没跑 01），98 预期报 FAIL ——
# 这正是要验证的：校验器能正确识别"原始数据未固化"。
cat("\n===== 执行 98（合成数据下预期 FAIL，用于验证校验器本身有效）=====\n")
setwd(SMOKE)
st8 <- system2(RS, file.path("code", "98_verify_reproducibility.R"),
               stdout = "", stderr = "")
cat("\n98 退出码 =", st8, "（1 = 正确检出问题，属预期）\n")

cat("\n===== 产出清单 =====\n")
print(list.files(file.path(SMOKE, "output"), full.names = FALSE))
print(list.files(file.path(SMOKE, "data/derived"), full.names = FALSE))
cat("\n########## 冒烟测试通过 ##########\n")
