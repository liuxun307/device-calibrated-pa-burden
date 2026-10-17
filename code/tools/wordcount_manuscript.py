# -*- coding: utf-8 -*-
"""正文词数实测（按期刊口径：只数 **English.** 段，排除中文对照、表格、代码块、引用标记）。

用法：
    python code/tools/wordcount_manuscript.py [--per-section]

口径说明：
- 只统计 `**English.**` 之后的英文块，直到下一个 `**中文` 或 `---` 或下一个 `## ` 标题。
- 剔除 markdown 表格行（以 | 开头）、代码围栏、HTML 注释。
- 单词正则 [A-Za-z][A-Za-z'-]*（与 Title Page §5 一致），数字与符号不计。
- 结果与期刊"含数字/含参考文献"计法会有 ±3% 差异，属正常。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "manuscript"

# 正文组成：(显示名, 文件名, 章节标记)，章节标记用于分段统计
SECTIONS = [
    ("Introduction", "Introduction_P1_P4_中英对照.md"),
    ("Methods 2.1+M2.1", "Methods_2.1_Results_R1_样本与暴露_中英对照.md"),
    ("Methods 2.2", "Methods_2.2_结局与协变量_中英对照.md"),
    ("Methods 2.3", "Methods_2.3_Module1_剂量反应与校准_中英对照.md"),
    ("Methods M2", "Methods_M2_证据合成_中英对照.md"),
    ("Methods 2.5", "Methods_2.5_Module3_负担重算_中英对照.md"),
    ("Methods 2.6/2.7", "Methods_2.6_2.7_部位指标轴_敏感性与软件_中英对照.md"),
    ("Results R1", "Methods_2.1_Results_R1_样本与暴露_中英对照.md"),
    ("Results R2–R6", "Results_R2_R6_中英对照.md"),
    ("Discussion D1–D4/D6", "Discussion_D1_D4_D6_中英对照.md"),
    ("Discussion D5", "Discussion_D5_局限_中英对照.md"),
]


def strip_noise(text: str) -> str:
    """去掉表格行、代码块、引用块标记、markdown 强调符号。"""
    out = []
    in_code = False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            continue
        if s.startswith("|"):          # 表格
            continue
        if s.startswith(">"):          # 引用块（多为中文注释）
            continue
        out.append(line)
    return "\n".join(out)


def english_blocks(text: str):
    """返回该文件中所有 **English.** 段（不含中文段）。

    修正（2026-10-17）：原实现先用 strip_noise 删掉表格/引用块再切段，
    会把段内以 ">" 起头的折行或段间说明块误删，导致 2.6/2.7 等节漏算。
    改为「先按 **English.** 切段，再对每段单独清洗」。
    """
    # 以 **English.** 为起点，止于 **中文 / **Chinese / 下一个小节标题 / ---
    pat = re.compile(r"\*\*English\.\*\*(.*?)(?=\*\*中文|\*\*Chinese|\n## |\n---|\Z)", re.S)
    blocks = []
    for m in pat.finditer(text):
        seg = m.group(1)
        # 去掉段内残留的表格行与引用块前缀（保留正文文字）
        lines = []
        for line in seg.splitlines():
            st = line.strip()
            if st.startswith("|"):
                continue
            if st.startswith(">"):
                continue
            lines.append(line)
        blocks.append("\n".join(lines))
    return blocks


def count_words(s: str) -> int:
    s = re.sub(r"`[^`]*`", " ", s)          # 行内代码
    s = re.sub(r"\[[^\]]*\]\([^)]*\)", " ", s)  # markdown 链接
    return len(re.findall(r"[A-Za-z][A-Za-z'\-]*", s))


def main() -> None:
    per_section = "--per-section" in sys.argv
    total = 0
    detail: dict[str, int] = {}

    for name, fname in SECTIONS:
        path = ROOT / fname
        if not path.exists():
            print(f"[MISSING] {fname}")
            continue
        blocks = english_blocks(path.read_text(encoding="utf-8"))
        n = sum(count_words(b) for b in blocks)

        # R1 与 M2.1 同文件：用标题切分（先按行找标题，再各自走 english_blocks，
        # 不用 strip_noise —— 它会把段内表行/引用行删掉后破坏切分边界）
        if name.startswith("Methods 2.1") or name.startswith("Results R1"):
            lines = path.read_text(encoding="utf-8").splitlines()
            cut = None
            for i, ln in enumerate(lines):
                st = ln.strip()
                if st.startswith("## R1") or st.startswith("## Results"):
                    cut = i
                    break
            body_meth = "\n".join(lines[:cut]) if cut else "\n".join(lines)
            body_res = "\n".join(lines[cut:]) if cut else ""
            n = sum(count_words(b) for b in english_blocks(body_meth)) \
                if name.startswith("Methods") else sum(count_words(b) for b in english_blocks(body_res))

        detail[name] = n
        total += n

    if per_section:
        for k, v in detail.items():
            print(f"{k:26s} {v:6d}")
        print("-" * 34)

    print(f"{'正文合计（English 段）':24s} {total:6d}")

    # 分段汇总
    groups = {
        "Introduction": ["Introduction"],
        "Methods": [k for k in detail if k.startswith("Methods")],
        "Results": [k for k in detail if k.startswith("Results")],
        "Discussion": [k for k in detail if k.startswith("Discussion")],
    }
    print()
    for g, keys in groups.items():
        s = sum(detail.get(k, 0) for k in keys)
        print(f"{g:14s} {s:6d}")


if __name__ == "__main__":
    main()
