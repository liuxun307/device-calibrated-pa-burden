# =============================================================================
# 08_fig_style.R —— 投稿图/表统一风格与导出工具（被 08a–08f 与 09 共享）
# -----------------------------------------------------------------------------
# 目录约定（panel-by-panel，便于手动编辑与重组）：
#   figures/panel/     每个子图一份独立 PDF（+ 同名 PNG 供预览/核对）
#   figures/combined/  各图拼接后的整图 PDF（投稿版）
#   figures/tables/    表格 PDF（投稿版）
#
# 为什么每个子图单独出 PDF：用户按 panel 手动编辑与重排；整图 PDF 由拼合步骤生成，
# 二者内容一致（同一 ggplot 对象）。
#
# ⚠️ 图内文字一律 ASCII：Windows 图形设备在非 UTF-8 locale 下无法渲染中文。
# ⚠️ 所有导出走 cairo_pdf（字体嵌入、无中文乱码风险；PDF 时间戳由 98 的 E 层豁免）。
# =============================================================================

local({
  for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8", "C.UTF-8"))
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

suppressPackageStartupMessages({
  library(data.table); library(ggplot2); library(scales)
  library(grid); library(gridExtra); library(patchwork)
})

# ---------------------------------------------------------------- 目录 -------
FIG_ROOT     <- file.path(PA_ROOT, "figures")
FIG_PANEL    <- file.path(FIG_ROOT, "panel")
FIG_COMBINED <- file.path(FIG_ROOT, "combined")
FIG_TABLES   <- file.path(FIG_ROOT, "tables")
for (d in c(FIG_ROOT, FIG_PANEL, FIG_COMBINED, FIG_TABLES)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# ------------------------------------------------------------ 调色板 --------
# Okabe–Ito 色盲友好色板（8 色）
OI <- c(blue   = "#0072B2", orange = "#E69F00", green  = "#009E73",
        red    = "#D55E00", purple = "#CC79A7", sky    = "#56B4E9",
        yellow = "#F0E442", grey   = "#999999")

# 语义色（全项目统一，避免各图各色）
PA_COLS <- c(
  device   = "#0072B2",  # 设备测量
  reported = "#E69F00",  # 自报
  hip      = "#009E73",  # 髋式
  wrist    = "#CC79A7",  # 腕式
  male     = "#0072B2",
  female   = "#D55E00",
  gbd      = "#8C8C8C",  # GBD 现报
  study    = "#3C5488",  # 本研究
  up       = "#D55E00",  # 使估计升高
  down     = "#4C9F70",  # 使估计降低
  ref      = "#333333"
)

# ------------------------------------------------------------- 主题 ---------
#' 统一主题：theme_classic + 收紧边距 + 细线
#' @param base_size 基准字号（拼版用 7；单图用 8；可小至 4.6 供高度压缩面板）
theme_pa <- function(base_size = 8, base_family = "") {
  theme_classic(base_size = base_size, base_family = base_family) +
    theme(
      axis.line    = element_line(linewidth = 0.35, colour = "grey20"),
      axis.ticks   = element_line(linewidth = 0.35, colour = "grey20"),
      axis.text    = element_text(colour = "grey15"),
      axis.title   = element_text(colour = "grey10"),
      plot.title   = element_text(size = base_size + 0.5, face = "bold", hjust = 0),
      plot.subtitle = element_text(size = base_size - 1, colour = "grey35"),
      plot.tag     = element_text(size = base_size + 1, face = "bold"),
      legend.title = element_text(size = base_size - 0.5),
      legend.text  = element_text(size = base_size - 1),
      legend.key.size = unit(0.28, "cm"),
      legend.margin = margin(0, 0, 0, 0),
      strip.background = element_blank(),
      strip.text   = element_text(size = base_size - 0.5, face = "bold"),
      plot.margin  = margin(5, 7, 5, 7)
    )
}

# --------------------------------------------------------- 导出工具 ---------
#' 导出单个 panel：figures/panel/<name>.pdf（矢量，可编辑）+ 同名 PNG（预览）
#' @param p ggplot 对象
#' @param name 文件名（不含扩展名），如 "Fig2b_density_reported_vs_device"
save_panel <- function(p, name, width, height, dpi = 300) {
  pdf_f <- file.path(FIG_PANEL, paste0(name, ".pdf"))
  png_f <- file.path(FIG_PANEL, paste0(name, ".png"))
  ggsave(pdf_f, p, width = width, height = height, device = cairo_pdf)
  ggsave(png_f, p, width = width, height = height, dpi = dpi, bg = "white")
  pa_log(sprintf("  panel -> %s.pdf (%.1f x %.1f in)", name, width, height))
  invisible(pdf_f)
}

#' 拼合整图：figures/combined/<name>.pdf（+ PNG 预览）
#' @param plots 由 patchwork 表达式拼装好的对象，或单个 ggplot
save_combined <- function(p, name, width, height, dpi = 300) {
  pdf_f <- file.path(FIG_COMBINED, paste0(name, ".pdf"))
  png_f <- file.path(FIG_COMBINED, paste0(name, ".png"))
  ggsave(pdf_f, p, width = width, height = height, device = cairo_pdf)
  ggsave(png_f, p, width = width, height = height, dpi = dpi, bg = "white")
  pa_log(sprintf("  combined -> %s.pdf (%.1f x %.1f in)", name, width, height))
  invisible(pdf_f)
}

#' 导出表格 PDF（用 gridExtra 渲染 data.frame，支持长表分页）
#' @param df data.frame / data.table
#' @param name 文件名（不含扩展名），如 "Table1_baseline"
#' @param title 表标题（英文，ASCII）
#' @param footnote 脚注（英文，ASCII；可 NULL）
#' @param font_size 表内字号（pt）
save_table_pdf <- function(df, name, title = NULL, footnote = NULL,
                           font_size = 7.5, width = 11, height = NULL,
                           page_rows = NULL, ...) {
  d <- as.data.frame(df)
  # 列名去下划线，转可读
  names(d) <- gsub("_", " ", names(d))
  # page_rows：>0 且行数超过时**分页**输出多页 PDF（每页重复表头），
  #   避免长表（如 Table S4 逐国 410 行）被渲染成 2 m 高的单页而无法查看。
  mk_tg <- function(x) gridExtra::tableGrob(x, rows = NULL,
                             theme = gridExtra::ttheme_minimal(
                               base_size = font_size,
                               padding = unit(c(2.2, 3.2), "mm"),
                               core = list(fg_params = list(hjust = 0, x = 0.02)),
                               colhead = list(fg_params = list(fontface = "bold", hjust = 0, x = 0.02))))
  tt <- if (is.null(title)) NULL else
    textGrob(title, gp = gpar(fontsize = font_size + 2, fontface = "bold"), hjust = 0, x = 0)
  fn <- if (is.null(footnote)) NULL else
    textGrob(footnote, gp = gpar(fontsize = font_size - 1.5, col = "grey25"), hjust = 0, x = 0)
  tg <- mk_tg(d)
  # 页面高度 = 标题/脚注固定空间 + 表格实际高度（tableGrob 自带每行高度，直接累加）
  h <- if (is.null(height)) {
    sum(convertHeight(tg$heights, "in", valueOnly = TRUE)) +
      (if (is.null(tt)) 0 else 0.75) + (if (is.null(fn)) 0 else 0.65) + 0.4
  } else height
  h <- max(h, 2.0)
  # heights 用绝对 unit（null 给表格），否则标题/脚注按比例挤压表格导致重叠
  hts_of <- function(has_tt, has_fn)
    unit.c(if (has_tt) unit(0.9, "cm") else unit(0, "cm"),
           unit(1, "null"),
           if (has_fn) unit(0.9, "cm") else unit(0, "cm"))
  pdf_f <- file.path(FIG_TABLES, paste0(name, ".pdf"))
  png_f <- file.path(FIG_TABLES, paste0(name, ".png"))

  if (is.null(page_rows) || !is.finite(page_rows) || nrow(d) <= page_rows) {
    # ---- 单页（原行为，未改动）----
    grobs <- Filter(Negate(is.null), list(tt, tg, fn))
    hts <- hts_of(!is.null(tt), !is.null(fn))
    hts <- hts[sapply(list(tt, tg, fn), Negate(is.null))]
    grDevices::cairo_pdf(pdf_f, width = width, height = h)
    gridExtra::grid.arrange(grobs = grobs, ncol = 1, heights = hts)
    grDevices::dev.off()
    grDevices::png(png_f, width = width, height = h, units = "in", res = 220, bg = "white")
    gridExtra::grid.arrange(grobs = grobs, ncol = 1, heights = hts)
    grDevices::dev.off()
    pa_log(sprintf("  table -> %s.pdf (%d 行)", name, nrow(d)))
  } else {
    # ---- 多页：每页 page_rows 行，表头每页重复；高度按各页实际行数估 ----
    idx   <- split(seq_len(nrow(d)), ceiling(seq_len(nrow(d)) / page_rows))
    n_p   <- length(idx)
    pages <- vector("list", n_p); h_pg <- numeric(n_p)
    for (k in seq_along(idx)) {
      tgk    <- mk_tg(d[idx[[k]], , drop = FALSE])
      has_tt <- k == 1L && !is.null(tt)
      has_fn <- k == n_p && !is.null(fn)
      labs <- list(
        if (has_tt) tt else
          textGrob(sprintf("%s (continued %d/%d)", name, k, n_p),
                   gp = gpar(fontsize = font_size, col = "grey35"), hjust = 0, x = 0),
        tgk,
        if (has_fn) fn else NULL)
      keep <- !vapply(labs, is.null, logical(1))
      pages[[k]] <- gridExtra::arrangeGrob(grobs = labs[keep], ncol = 1,
                                           heights = hts_of(TRUE, has_fn)[keep])
      h_pg[k] <- sum(convertHeight(tgk$heights, "in", valueOnly = TRUE)) +
        0.75 + (if (has_fn) 0.65 else 0) + 0.4
    }
    h_max <- max(h_pg, 2.0)
    grDevices::cairo_pdf(pdf_f, width = width, height = h_max, onefile = TRUE)
    grid::grid.draw(pages[[1]])
    if (n_p > 1L) for (k in 2:n_p) { grid::grid.newpage(); grid::grid.draw(pages[[k]]) }
    grDevices::dev.off()
    # PNG 只出首页（预览）；全量以上述多页 PDF 与 CSV 为准
    grDevices::png(png_f, width = width, height = h_max, units = "in", res = 220, bg = "white")
    grid::grid.draw(pages[[1]])
    grDevices::dev.off()
    pa_log(sprintf("  table -> %s.pdf (%d 行, 分 %d 页 @%d 行/页) + %s.png(首页)",
                   name, nrow(d), n_p, as.integer(page_rows), name))
  }
  invisible(pdf_f)
}

# ------------------------------------------------------- 小工具 ------------
#' 千分位
fmt_n <- function(x) formatC(round(x), format = "d", big.mark = ",")
#' 固定小数
fmt_f <- function(x, d = 2) formatC(x, format = "f", digits = d)
#' P 值格式（<0.001）
fmt_p <- function(p) ifelse(is.na(p), "", ifelse(p < 0.001, "<0.001", formatC(p, format = "f", digits = 3)))
#' 加权均值（NHANES 抽样权重）
wmean <- function(x, w) sum(x * w, na.rm = TRUE) / sum(w[!is.na(x)], na.rm = TRUE)

pa_log("08_fig_style 就绪：figures/{panel,combined,tables}")
