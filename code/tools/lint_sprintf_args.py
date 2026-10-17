#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
lint_sprintf_args.py  --  R 源码 sprintf() 参数-占位符一致性静态检查

背景
----
本项目多次出现「数值占位符收到字符型表达式」的运行期错误，例如：
    sprintf("... %.0f ...", nf(x))        # nf() 返回 "13,222.1"（character）
R 会直接报 invalid format '%.0f'; use format %s for character objects。
这类错误只能在运行到该行时才暴露，代价高。

本脚本对目标 .R 文件做静态解析：
  1) 定位每一个 sprintf( 调用；
  2) 解析第一个实参（格式串字面量）与其余顶层逗号分隔的实参；
  3) 按顺序统计格式串中的转换说明符（跳过 %%）；
  4) 报告三类问题：
       [E1] 参数个数 != 占位符个数（会 too few / unused arguments）
       [E2] 数值型占位符 (%f %e %g %d %i %x %X %o %a %A) 位置上是字符型表达式
            （表达式以 nf(/sg(/num(/fmtC(/paste(/paste0(/formatC(/format(/as.character( 开头，
             或以引号开头）
       [E3] 字符型占位符 %s 位置上是裸数值字面量（仅信息级，不报错）

用法
----
    python lint_sprintf_args.py 10_captions.R [more.R ...]
    python lint_sprintf_args.py            # 默认扫描同目录上级的全部 .R

退出码：有 E1/E2 时返回 1，否则 0。
"""

import os
import re
import sys

NUM_CONV = set("feEgGdi") | {"x", "X", "o", "a", "A"}
# R 里 %f/%e/%g 的作用；%d/%i 需要整数
DEFINITE_CHR = (
    "nf(", "sg(", "num(", "fmtC(", "paste(", "paste0(", "formatC(",
    "format(", "as.character(", "trimws(", "sub(", "gsub(", "sprintf(",
    "strsplit(", "substr(", "toupper(", "tolower(",
)
# 返回值类型不确定：仅当内部出现字符串字面量时才判为字符型
AMBIGUOUS_CHR = ("ifelse(", "case_when(", "coalesce(", "fifelse(")

DIRECTIVE_RE = re.compile(r"%(?:[-+ #0']|\d+|\*|\.(?:\d+|\*))*[a-zA-Z%]")


def strip_comments_and_strings(src):
    """把注释与字符串*内部*替换为同长度的占位字符（保留两侧引号），
    使顶层逗号切分与括号配对不受字符串内容干扰。
    返回 (masked, spans)，spans 为字符串字面量的 (起, 止) 区间。"""
    out = list(src)
    n = len(src)
    i = 0
    spans = []
    while i < n:
        c = src[i]
        if c == "#":
            j = src.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        if c in "'\"":
            q = c
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == q:
                    break
                if src[j] == "\n":  # 未闭合保护
                    break
                out[j] = "\x01"
                j += 1
            spans.append((i, min(j + 1, n)))
            i = j + 1
            continue
        i += 1
    return "".join(out), spans


def find_calls(masked, name):
    """返回 name( 之后左括号的下标列表。"""
    res = []
    for m in re.finditer(r"\b" + re.escape(name) + r"\s*\(", masked):
        res.append(m.end() - 1)
    return res


def match_paren(masked, open_idx):
    """给定左括号下标，返回配对右括号下标，-1 表示未闭合。"""
    depth = 0
    n = len(masked)
    i = open_idx
    while i < n:
        c = masked[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def split_top_level(masked, a, b):
    """把 [a, b) 区间按顶层逗号切分，返回 [(s,e), ...]。"""
    parts = []
    depth = 0
    start = a
    i = a
    while i < b:
        c = masked[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            parts.append((start, i))
            start = i + 1
        i += 1
    parts.append((start, b))
    return parts


def count_directives(fmt):
    """返回 [(conv_char, raw_directive, n_star), ...]，跳过 %%。
    n_star = 该说明符中 * 的个数（每个 * 额外消耗一个实参，如 %.*f）。"""
    res = []
    for m in DIRECTIVE_RE.finditer(fmt):
        raw = m.group(0)
        conv = raw[-1]
        if conv == "%":
            continue
        body = raw[1:-1]
        n_star = body.count("*")
        res.append((conv, raw, n_star))
    return res


def classify_arg(masked, s, e):
    t = masked[s:e].strip()
    return t


def looks_character(t, masked_src=None):
    if not t:
        return False
    if t[0] in "'\"":
        return True
    for p in DEFINITE_CHR:
        # 比较时先剥掉可能的 ( 前缀包裹
        if t.startswith(p):
            return True
    for p in AMBIGUOUS_CHR:
        if t.startswith(p):
            # 仅当括号内出现字符串字面量（掩码后为 \x01 占位）才判字符型
            return "\x01" in t
    return False


def looks_numeric_literal(t):
    t = t.strip()
    if re.fullmatch(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?[L]?", t):
        return True
    return False


def line_of(src, idx):
    return src.count("\n", 0, idx) + 1


def check_file(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        src = f.read()
    masked, _ = strip_comments_and_strings(src)
    findings = []
    for op in find_calls(masked, "sprintf"):
        cl = match_paren(masked, op)
        if cl < 0:
            continue
        parts = split_top_level(masked, op + 1, cl)
        if len(parts) < 1:
            continue
        # 第一个实参必须是字符串字面量才可判
        f_s, f_e = parts[0]
        f_raw = src[f_s : f_e].strip()
        if not f_raw or f_raw[0] not in "'\"":
            continue  # 动态格式串，跳过
        fmt = f_raw[1:-1]
        dirs = count_directives(fmt)
        args = parts[1:]
        ln = line_of(src, op)

        # 把 %.*f 这类说明符展开为「星号实参 + 值实参」两个槽位
        slots = []
        for conv, raw, ns in dirs:
            for _ in range(ns):
                slots.append(("d", f"* of {raw!r}"))
            slots.append((conv, raw))

        if len(args) != len(slots):
            findings.append(
                (
                    "E1",
                    ln,
                    f"参数个数 {len(args)} != 占位符槽位 {len(slots)}  ::  "
                    f"{fmt[:70]!r}",
                )
            )
            continue

        for (conv, raw), (as_, ae) in zip(slots, args):
            t = classify_arg(masked, as_, ae)
            if conv in NUM_CONV and looks_character(t):
                findings.append(
                    ("E2", ln, f"{raw} 位置收到字符型表达式  ->  {t[:80]}")
                )
            elif conv == "s" and looks_numeric_literal(t) and "." not in t:
                findings.append(
                    ("E3", ln, f"'%s' 位置是裸整数 {t[:40]}（建议保留数值/格式化）")
                )
    return findings


def main(argv):
    files = argv[1:]
    if not files:
        here = os.path.dirname(os.path.abspath(__file__))
        root = os.path.dirname(here)
        files = sorted(
            os.path.join(root, f)
            for f in os.listdir(root)
            if f.endswith(".R")
        )
    total = 0
    hard = 0
    for p in files:
        if not os.path.isfile(p):
            print(f"!! 找不到 {p}")
            continue
        fnd = check_file(p)
        if not fnd:
            continue
        print(f"\n=== {os.path.basename(p)} ===")
        for code, ln, msg in fnd:
            total += 1
            if code in ("E1", "E2"):
                hard += 1
            print(f"  [{code}] line {ln}: {msg}")
    print(f"\n合计 {total} 条；其中 E1/E2（必须修） {hard} 条。")
    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
