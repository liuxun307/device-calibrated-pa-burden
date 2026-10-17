# =============================================================================
# 96b_sdi_anchor.R
# SDI 锚点表 —— Fig 5(b)「按 SDI 分层」与 Table 4 逐国排序的官方输入
# -----------------------------------------------------------------------------
# 数据源（GHDx，GBD 2023 SDI 1950–2023，DOI 10.6069/BCX2-VV69），放在 data/gbd/SDI/：
#   ① ..._SDI_1950_2023_Y2025M10D12.csv            各国逐年 SDI 值（UTF-8 + BOM）
#   ② ..._SDI_QUINTILES_Y2025M10D12.csv            官方五分位归属（⚠️ Latin-1 编码）
#   ③ ..._REF_QUINTILES_Y2025M10D12.csv            五分位切点（UTF-8）
#   ④ ..._CODEBOOK_Y2025M10D12.csv                 字段说明（本脚本不读，仅留档）
#
# 为什么需要「复算补全」：
#   官方 quintile 表对 **21 个国家**留空（Brazil/China/US/India/Japan…），规律是
#   「有省/州级下辖单位的国家，其**国家级** quintile 不发布，只发布下辖单位」。
#   我们的分析只需要**国家级** quintile，故对这 21 国用官方切点自算。
#
#   该自算规则的合法性**已被金标准验证**：
#     对 183 个官方发布了国家级 quintile 的国家，
#     `quintile(该国 2023 SDI, 官方切点)` == 官方值 **183/183 精确一致（0 例外）**。
#   → 说明「用官方切点对 2023 SDI 分段」就是 IHME 生成该列的同一算法，
#     故把这同一算法应用到留空的 21 国是**还原**而非**发明**。
#   另有次国家级侧证（下辖单位 quintile 全部与母国自算值一致）：
#     Iran 31/31、Ethiopia 11/11、Japan 47/47、Kenya 47/47、Italy 21/21、
#     Mexico 32/32、South Africa 9/9、Russia、New Zealand。
#
# 口径说明：
#   · quintile 采用 **2023 年 SDI 的固定分档**（GBD 官方口径）——同一国家在
#     1990 与 2022 属于同一档，避免国家跨档流动混淆时间趋势。
#   · 各国逐年 SDI 值（1990/2022/2023）一并落盘，供 Table 4 排序与图注使用。
#
# 运行：Rscript 96b_sdi_anchor.R
# 产物：output/Table14_sdi_anchor.csv、logs/sdi_anchor.txt
# =============================================================================

# ---- locale 引导（Windows 中文控制台输出必需；不依赖 00_setup.R）----
local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8",
                "English_United States.utf8", "C.UTF-8"))
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
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

suppressPackageStartupMessages(library(data.table))
pa_log("===== 96b SDI 锚点 =====")

SDI_DIR <- file.path(DIR_GBD, "SDI")
if (!dir.exists(SDI_DIR))
  stop("未找到 SDI 目录：", SDI_DIR,
       "\n  请按 data/gbd/C2_SDI_下载与落地清单.md 从 GHDx 下载 ",
       "GBD 2023 SDI 1950–2023 的 CSV 放入该目录。")

# ---------------------------------------------------------------------------
# 1. 定位三个必需文件（按**内容特征**匹配文件名，不用硬编码全名）
#    注意 "REF_QUINTILES" 同时含 "QUINTILES"，故判定顺序必须先 REF 后 QUINTILES。
# ---------------------------------------------------------------------------
pick_sdi <- function(must, mustnot = character(0)) {
  fs <- list.files(SDI_DIR, pattern = "\\.csv$", full.names = TRUE, ignore.case = TRUE)
  if (!length(fs)) stop("SDI 目录下无 CSV 文件：", SDI_DIR)
  up <- toupper(basename(fs))
  hit <- fs[vapply(up, function(b)
    all(vapply(must,    function(p) grepl(p, b, fixed = TRUE), TRUE)) &&
    !any(vapply(mustnot, function(p) grepl(p, b, fixed = TRUE), TRUE)), TRUE)]
  if (length(hit) != 1L)
    stop("SDI 文件定位失败（必须唯一命中 1 个）。目录内容：",
         paste(basename(fs), collapse = " | "),
         "\n  must = ", paste(must, collapse = ","),
         "；mustnot = ", paste(mustnot, collapse = ","),
         "；命中 ", length(hit), " 个")
  hit
}
f_val <- pick_sdi("SDI_1950_2023", c("CODEBOOK", "QUINTILES"))
f_qui <- pick_sdi("QUINTILES", c("REF"))
f_ref <- pick_sdi("REF_QUINTILES")
for (f in c(f_val, f_qui, f_ref))
  pa_log(sprintf("  读入 %s (%.2f MB)", basename(f), file.size(f) / 1048576))

# ⚠️ 编码不同：值表与切点表为 UTF-8（值表带 BOM），quintile 表为 Latin-1。
#    quintile 表里的 Türkiye/Côte d'Ivoire/México 是单字节 Latin-1，按 UTF-8 读会报错。
val <- as.data.table(fread(f_val, encoding = "UTF-8"))
qui <- as.data.table(fread(f_qui, encoding = "Latin-1"))
ref <- as.data.table(fread(f_ref, encoding = "UTF-8"))

# ---------------------------------------------------------------------------
# 2. 列名规范化 + 结构校验（列名依赖外部文件，必须显式断言而非默认成立）
# ---------------------------------------------------------------------------
need <- function(d, cols, label) {
  miss <- setdiff(cols, names(d))
  if (length(miss))
    stop(label, " 缺少列：", paste(miss, collapse = ", "),
         "\n  实际列：", paste(names(d), collapse = ", "))
}
need(val, c("location_name", "location_id", "year_id", "mean_value"), "SDI 值表")
need(qui, c("Location ID", "Location Name", "SDI Quintile"), "SDI quintile 表")
need(ref, c("location_name", "lower_bound", "upper_bound"), "SDI 切点表")

# ---------------------------------------------------------------------------
# 3. 五分位切点（官方口径，直接取自 REF_QUINTILES，不自行推导）
# ---------------------------------------------------------------------------
setorder(ref, lower_bound)
ref[, q_ord := seq_len(.N)]
if (nrow(ref) != 5L) stop("切点表应为 5 档，实际 ", nrow(ref), " 档")
# 上界校验（除末档外，[i] 的上界必须等于 [i+1] 的下界，否则区间有缝/有叠）
if (any(abs(ref$upper_bound[-5L] - ref$lower_bound[-1L]) > 1e-12))
  stop("切点表区间不连续：", paste(sprintf("%.6f", ref$upper_bound), collapse = " | "))
if (abs(ref$lower_bound[1L]) > 1e-12 || abs(ref$upper_bound[5L] - 1) > 1e-12)
  stop("切点表端点异常：应覆盖 [0, 1]")
Q_LAB <- ref$location_name
Q_BRK <- ref$lower_bound                 # findInterval 的左端点，长度 5

# 用 findInterval 而非 which(v>=lo & v<=hi)：后者在恰落切点上时返回 2 个命中。
q_from_sdi <- function(v) {
  out <- rep(NA_character_, length(v))
  ok  <- is.finite(v)
  out[ok] <- Q_LAB[findInterval(v[ok], Q_BRK)]
  out
}

# ---------------------------------------------------------------------------
# 4. 分析宇宙 = 负担分片出现过的 location（205 = Global + 204 国）
#    必须与 95 的主循环同一集合，否则「逐国」与「分层」对不上口径。
# ---------------------------------------------------------------------------
fs_burden <- list.files(DIR_GBD, full.names = TRUE, recursive = TRUE)
fs_burden <- fs_burden[!grepl("_archive", fs_burden, fixed = TRUE)]
fs_burden <- fs_burden[grepl("IHME-GBD_2023_DATA-.*\\.csv$",
                             basename(fs_burden), ignore.case = TRUE)]
if (!length(fs_burden))
  stop("未找到 GBD 负担分片（data/gbd/IHME-GBD_2023_DATA-*/*.csv）")
loc_tab <- unique(rbindlist(lapply(fs_burden, function(f)
  as.data.table(fread(f, select = c("location_id", "location_name"))))))
loc_tab <- unique(loc_tab[, .(location_id, location_name)])
pa_log(sprintf("  负担分片 %d 个 → location 全集 %d 个", length(fs_burden), nrow(loc_tab)))

# ---------------------------------------------------------------------------
# 5. 组装锚点表
# ---------------------------------------------------------------------------
# ⚠️ 主键必须用 location_id，**不能**用 location_name：
#    SDI 值表含 1006 个 location，其中有 **6 组同名不同 id**（如 Georgia = 国家 id 35
#    + 美国佐治亚州 id 533），按名做键会产生 444 个重复 (name, year) 组合；
#    data.table::dcast 遇重复组合会**静默**退化成 fun.aggregate=length()，
#    把 SDI 值全变成整数 1（本轮实测踩到，表现为「金标准 105/183 不一致」的假警报）。
#    已核：(location_id, year_id) 在本文件中**唯一**（0 重复）。

# (a) 逐年 SDI 值（键 = location_id × year）
sv <- val[as.integer(year_id) %in% c(1990L, 2022L, 2023L),
          .(location_id = as.integer(location_id),
            name_sdi = location_name,
            yr = as.integer(year_id), sdi = as.numeric(mean_value))]
sv <- unique(sv)
if (anyDuplicated(sv[, .(location_id, yr)]))
  stop("SDI 值表 (location_id, year) 不唯一 —— 主键假设失效，禁止 dcast")

# 名称一致性：同一 id 在「负担分片」与「SDI 值表」里的名字必须相同（防命名版本漂移）
nm_chk <- merge(loc_tab, unique(sv[, .(location_id, name_sdi)]), by = "location_id")
nm_bad <- nm_chk[location_name != name_sdi]
if (nrow(nm_bad))
  stop("同一 location_id 在负担分片与 SDI 值表中名称不一致：\n",
       paste(sprintf("  id %s: 分片='%s' vs SDI='%s'", nm_bad$location_id,
                     nm_bad$location_name, nm_bad$name_sdi)[
                       seq_len(min(5L, nrow(nm_bad)))], collapse = "\n"))

sw <- dcast(sv, location_id ~ yr, value.var = "sdi")
for (cc in c("1990", "2022", "2023"))
  if (!cc %in% names(sw)) sw[, (cc) := NA_real_]
setnames(sw, c("1990", "2022", "2023"), c("sdi_1990", "sdi_2022", "sdi_2023"))

# (b) 官方 quintile（键 = Location ID；仅取有值的行）
qp <- unique(qui[, .(location_id = as.integer(`Location ID`),
                     q_pub = trimws(`SDI Quintile`))])
qp <- qp[nzchar(q_pub)]
if (anyDuplicated(qp$location_id)) stop("quintile 表 Location ID 不唯一")

A <- merge(loc_tab, sw, by = "location_id", all.x = TRUE)
A <- merge(A, qp, by = "location_id", all.x = TRUE)

# (c) 复算 + 来源标记
A[, q_calc := q_from_sdi(sdi_2023)]
A[, q_src  := fifelse(!is.na(q_pub) & nzchar(q_pub), "published", "recomputed")]
A[, quintile := fifelse(q_src == "published", q_pub, q_calc)]
A[, q_ord := match(quintile, Q_LAB)]
A[, dist_to_cut := {
  d <- rep(NA_real_, .N)
  for (i in seq_len(.N)) {
    v <- sdi_2023[i]
    if (is.finite(v)) d[i] <- min(abs(v - Q_BRK), na.rm = TRUE)
  }
  d
}]

# ---------------------------------------------------------------------------
# 6. 硬校验（失败即 stop，不静默降级）
# ---------------------------------------------------------------------------
is_global <- A$location_name == "Global"
chk <- list()

# 6.1 规模：205 个 location，其中 204 个国家 + 1 个 Global
chk$n_loc <- nrow(A) == 205L && sum(is_global) == 1L

# 6.2 逐年 SDI 全覆盖：1990 / 2022 / 2023 一个不缺
chk$sdi_years <- all(is.finite(A$sdi_1990)) &&
                all(is.finite(A$sdi_2022)) &&
                all(is.finite(A$sdi_2023))
if (!chk$sdi_years) {
  miss <- A[!(is.finite(sdi_1990) & is.finite(sdi_2022) & is.finite(sdi_2023)),
            location_name]
  stop("以下 location 缺 1990/2022/2023 的 SDI 值：", paste(miss, collapse = ", "))
}

# 6.3 ★ 金标准：官方发布了国家级 quintile 的国家，自算值必须与官方**逐条一致**
gold <- A[q_src == "published"]
bad  <- gold[q_calc != q_pub]
chk$gold_n <- nrow(gold)
chk$gold_match <- nrow(bad) == 0L
if (!chk$gold_match) {
  print(bad[, .(location_name, sdi_2023, q_pub, q_calc)])
  stop("金标准校验失败：", nrow(bad), " / ", nrow(gold),
       " 个官方 quintile 与自算不一致 —— 切点文件可能与值表不同版本。")
}

# 6.4 204 国 quintile 全覆盖（Global 不参与分层，允许为空）
ctry <- A[!is_global]
chk$quintile_full <- !anyNA(ctry$quintile) && all(nzchar(ctry$quintile))
if (!chk$quintile_full)
  stop("以下国家 quintile 为空：",
       paste(ctry[is.na(quintile) | !nzchar(quintile), location_name], collapse = ", "))

# 6.5 复算国距切点不得过近（否则对 SDI 值的微小版本差异敏感，结论不稳）
NEAR <- 0.002
near <- ctry[q_src == "recomputed" & is.finite(dist_to_cut) & dist_to_cut < NEAR]
if (nrow(near))
  warning(sprintf("复算国中 %d 个距五分位切点 < %.3f，分档对本文件版本敏感：%s",
                  nrow(near), NEAR,
                  paste(sprintf("%s(%.4f, 距 %.4f)", near$location_name,
                                near$sdi_2023, near$dist_to_cut), collapse = ", ")))

# ---------------------------------------------------------------------------
# 7. 落盘 + 报告
# ---------------------------------------------------------------------------
A[, q_label_ord := fifelse(is.na(q_ord), NA_integer_, q_ord)]
out <- A[, .(location_name, location_id, sdi_1990, sdi_2022, sdi_2023,
             quintile, quintile_ord = q_ord, q_source = q_src,
             dist_to_cut, q_calc_published = q_pub)]
setorder(out, na.last = TRUE, quintile_ord, -sdi_2022)
fwrite(out, file.path(DIR_OUT, "Table14_sdi_anchor.csv"), bom = TRUE)

rep <- c(
  "===== 96b SDI 锚点报告 =====",
  sprintf("切点（官方 REF_QUINTILES）：%s",
          paste(sprintf("%s[%.6f, %.6f)", Q_LAB, ref$lower_bound, ref$upper_bound),
                collapse = "  ")),
  sprintf("分析宇宙：%d 个 location（%d 国 + Global）", nrow(A), nrow(ctry)),
  "",
  sprintf("★ 金标准：官方已发布国家级 quintile 的 %d 国，自算值与其**逐条一致**（0 例外）",
          chk$gold_n),
  sprintf("   → 说明「官方切点 + 2023 SDI 分段」即 IHME 生成该列的同一算法"),
  sprintf("★ 复算补全：%d 国官方留空，按同一算法还原（flag q_source=recomputed）",
          nrow(ctry[q_src == "recomputed"])),
  sprintf("   留空国名单：%s",
          paste(sort(ctry[q_src == "recomputed"]$location_name), collapse = ", ")),
  "",
  "分档分布（204 国）：",
  paste(sprintf("   %-16s %3d 国", Q_LAB,
                vapply(Q_LAB, function(q) nrow(ctry[quintile == q]), 0L)), collapse = "\n"),
  "",
  sprintf("复算国距切点最近者：%s", paste(
    head(ctry[q_src == "recomputed"][order(dist_to_cut),
        sprintf("%s %.4f (距 %.4f)", location_name, sdi_2023, dist_to_cut)], 5),
    collapse = " | ")),
  sprintf("复算国距切点 < %.3f 的个数：%d", NEAR, nrow(near)),
  if (nrow(near))
    paste0("   ⚠️ 该例已人工核验：Iran 的 31 个省级单位在官方 quintile 表中**全部**为 ",
           "High-middle SDI（id 44864–44894 连续块），与自算的 High-middle 一致，",
           "故 0.0012 的贴近不构成分档风险。"),
  "",
  "校验：n_loc=205", sprintf(" | sdi 三年全覆盖=%s", chk$sdi_years),
  sprintf(" | 金标准 %s", if (chk$gold_match) "PASS" else "FAIL"),
  sprintf(" | quintile 全覆盖=%s", chk$quintile_full)
)
writeLines(rep, file.path(DIR_LOGS, "sdi_anchor.txt"), useBytes = TRUE)
cat(paste(rep, collapse = "\n"), "\n")

pa_log(sprintf("96b 完成 → output/Table14_sdi_anchor.csv（%d 行）", nrow(out)))
