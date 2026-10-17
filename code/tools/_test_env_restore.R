# 最小用例：验证 00_run_all.R 中「本轮环境变量轮后还原」逻辑的正确性
# 背景：Sys.getenv() 在 names = NA（缺省）下只在长度 > 1 时给返回值加名字，
#       单个变量返回无名向量 → 按名字取 ev_old[[k]] 会 subscript out of bounds。
# 修法：一律按位置索引 ev_old[i]。
restore <- function(ev_names, ev_old) {
  for (i in seq_along(ev_names)) {
    if (is.na(ev_old[i])) Sys.unsetenv(ev_names[i])
    else do.call(Sys.setenv, setNames(list(ev_old[i]), ev_names[i]))
  }
}

cat("== 场景 1：变量原本未设置 ==\n")
Sys.unsetenv("PA_CV_MODE")
en <- "PA_CV_MODE"; eo <- Sys.getenv(en, unset = NA)
cat("  长度 =", length(eo), " 有名字 =", !is.null(names(eo)), " eo[1] =", eo[1], "\n")
do.call(Sys.setenv, list(PA_CV_MODE = "s1p"))
restore(en, eo)
cat("  轮内设为 s1p，还原后 =", Sys.getenv("PA_CV_MODE", unset = "<未设置>"), "\n")

cat("== 场景 2：变量原本有值 ==\n")
Sys.setenv(PA_CV_MODE = "grid")
en <- "PA_CV_MODE"; eo <- Sys.getenv(en, unset = NA)
do.call(Sys.setenv, list(PA_CV_MODE = "s1p"))
cat("  轮内 =", Sys.getenv("PA_CV_MODE"), "\n")
restore(en, eo)
cat("  还原后 =", Sys.getenv("PA_CV_MODE"), "（应为 grid）\n")

cat("== 场景 3：两个变量（一未设置、一有值）==\n")
Sys.unsetenv("A1"); Sys.setenv(A2 = "keep")
en <- c("A1", "A2"); eo <- Sys.getenv(en, unset = NA)
cat("  长度 =", length(eo), " 有名字 =", !is.null(names(eo)), "\n")
do.call(Sys.setenv, list(A1 = "x", A2 = "y"))
restore(en, eo)
cat("  A1 =", Sys.getenv("A1", unset = "<未设置>"), " A2 =", Sys.getenv("A2", unset = "<未设置>"), "（应为 <未设置> / keep）\n")

cat("== 场景 4：STEP_PLAN 的两轮（grid 轮 -> s1p 轮）互不串味 ==\n")
plan <- list(list(tag = "", env = list(PA_CV_MODE = "grid")),
             list(tag = "s1p", env = list(PA_CV_MODE = "s1p")))
seen <- character(0)
for (ru in plan) {
  en <- names(ru$env)
  eo <- if (length(en)) Sys.getenv(en, unset = NA) else character(0)
  if (length(en)) do.call(Sys.setenv, as.list(ru$env))
  seen <- c(seen, Sys.getenv("PA_CV_MODE", unset = "<未设置>"))
  if (length(en)) restore(en, eo)
}
cat("  两轮实际生效的 PA_CV_MODE =", paste(seen, collapse = " / "), "（应为 grid / s1p）\n")
cat("  全部轮结束后 =", Sys.getenv("PA_CV_MODE", unset = "<未设置>"), "（应回到初始）\n")
