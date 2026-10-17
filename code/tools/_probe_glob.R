suppressMessages(library(data.table))
o <- function(f, dec = 4) {
  d <- fread(file.path("output", f), encoding = "UTF-8")
  cat("\n=== ", f, " ===\n", sep = "")
  cat("列: ", paste(names(d), collapse = ", "), "\n", sep = "")
  g <- d[location == "Global" & year == 2022]
  if (!nrow(g)) g <- d[location == "Global"]
  print(as.data.frame(g))
}
o("PREVIEW_module3_totals.csv")
o("M3_BYCOUNTRY_totals.csv")
