suppressMessages(library(data.table))
d <- fread("output/PREVIEW_module3_s1p_totals.csv", encoding = "UTF-8")
x <- d[location == "Global" & year == 2022 & rr_source == "pooled"]
cat("列名:", paste(names(x), collapse = " | "), "\n\n")
for (nm in names(x)) {
  v <- x[[nm]][1]
  if (is.numeric(v)) cat(sprintf("  %-24s %.10g\n", nm, v))
}
