# 临时环境探测：Stan/brms 可用性（用完即删）
local({
  for (loc in c("Chinese_China.utf8","zh_CN.UTF-8","English_United States.utf8","C.UTF-8"))
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
})
cat("R 版本      :", R.version.string, "\n")
cat("R.home()    :", R.home(), "\n")
cat("libPaths    :\n"); print(.libPaths())

cat("\n--- 编译器探测（Stan 必需）---\n")
for (b in c("gcc", "g++", "make", "gfortran", "clang")) {
  p <- Sys.which(b)
  cat(sprintf("  %-9s %s\n", b, if (nzchar(p)) p else "<未找到>"))
}

cat("\n--- Rtools / BINPREF ---\n")
cat("  BINPREF env :", Sys.getenv("BINPREF", "<空>"), "\n")
cat("  RTOOLS* env :", paste(grep("RTOOLS", names(Sys.getenv()), value = TRUE), collapse = ", "), "\n")
cat("  R_MAKEVARS_USER:", Sys.getenv("R_MAKEVARS_USER", "<空>"), "\n")
for (p in c("C:/rtools45", "C:/rtools44", "C:/rtools43", "C:/rtools42",
            "D:/rtools45", "D:/rtools44", "D:/rtools43", "D:/rtools42",
            "C:/Program Files/Rtools45", "C:/Program Files/Rtools44")) {
  if (dir.exists(p)) cat("  发现 Rtools:", p, "\n")
}
cat("  （以上无输出即未发现）\n")

cat("\n--- 相关包是否已装 ---\n")
want <- c("brms","rstan","cmdstanr","StanHeaders","metafor","meta","baggr",
          "pkgbuild","withr","Rcpp","RcppEigen","RcppArmadillo","BH","loo",
          "posterior","bayesplot","emmeans","splines2","projpred","mice",
          "sandwich","clubSandwich","metafor")
inst <- rownames(installed.packages())
for (p in unique(want))
  cat(sprintf("  %-16s %s\n", p, if (p %in% inst) "已装" else "—— 未装"))

cat("\n--- 编译能力自检（写一个极小 C++ 文件并编译）---\n")
td <- tempfile("cxxprobe"); dir.create(td)
writeLines(c("int main(){return 0;}"), file.path(td, "t.cpp"))
old <- setwd(td); on.exit(setwd(old), add = TRUE)
res <- tryCatch(
  system2(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "t.cpp"),
          stdout = TRUE, stderr = TRUE),
  error = function(e) paste("ERR:", conditionMessage(e)))
cat(paste(res, collapse = "\n"), "\n")
cat("  编译产物:", paste(list.files(td), collapse = ", "), "\n")
