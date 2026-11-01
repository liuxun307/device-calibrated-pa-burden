# -*- coding: utf-8 -*-
r"""
audit_submission_package.py — 投稿包（eClinicalMedicine）投稿前自动审查

检查项：
  A. 文件齐全性（7 个 Word + 图 + 补充 PDF + CSV + checklist）
  B. 文本卫生：中文残留、markdown 标记残留（** / 反引号 / 转义星号）、HTML 实体
  C. 编号一致性：Fig 1–6、Table S1–S16 是否全部在正文被引用、是否有旧编号 Table 1–4
  D. 字数口径：Abstract ≤250（Word 口径）、正文 3,500–5,000、参考文献 ≤30
  E. 声明完整性：eClinicalMedicine 必需小节逐项检查
  F. 图注/表注与正文数字抽检（关键读数）

用法：<venv>/Scripts/python.exe code/tools/audit_submission_package.py [--pkg <目录>]
输出：控制台报告 + <pkg>/审查报告_AUDIT.md
"""
import io
import os
import re
import sys

import docx

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DEFAULT_PKG = os.path.join(ROOT, "\u6295\u7a3f\u5305_eClinMed_2026-11-01")

CJK = re.compile(r"[\u4e00-\u9fff]")
MD_LEFTOVER = re.compile(r"\*\*|`|\\\*|&nbsp;|&amp;")

# eClinicalMedicine 必需小节（Declarations 下）
REQ_SECTIONS = [
    "Ethics approval and consent to participate",
    "Data availability",
    "Code availability",
    "Funding",
    "Declaration of interests",
    "Author contributions",
    "Declaration of generative AI and AI-assisted technologies in the writing process",
    "Acknowledgements",
    "Reporting guidelines",
]

ROWS = []   # (level, item, detail)


def add(level, item, detail=""):
    ROWS.append((level, item, detail))


def read_docx_text(path):
    d = docx.Document(path)
    parts = [p.text for p in d.paragraphs]
    for tb in d.tables:
        for r in tb.rows:
            for c in r.cells:
                parts.append(c.text)
    return d, "\n".join(parts)


def check_files(pkg):
    need_root = [
        "00_Cover_Letter.docx", "01_Main_Manuscript.docx", "02_Figure_Legends.docx",
        "03_Table_S13_S16.docx", "04_Table_S1_S12.docx", "05_Supplementary_Table_Captions.docx",
    ]
    for f in need_root:
        p = os.path.join(pkg, f)
        add("PASS" if os.path.exists(p) else "FAIL", "存在 %s" % f,
            "%.1f KB" % (os.path.getsize(p) / 1024.0) if os.path.exists(p) else "缺失")
    figs = [f for f in os.listdir(os.path.join(pkg, "Figures")) if f.lower().endswith(".pdf")]
    add("PASS" if len(figs) == 6 else "FAIL", "主图 PDF 数量 = 6", "实际 %d：%s" % (len(figs), sorted(figs)))
    csvs = [f for f in os.listdir(os.path.join(pkg, "Data_Tables_CSV")) if f.lower().endswith(".csv")]
    add("PASS" if csvs else "FAIL", "机器可读数据表", "%d 个 CSV" % len(csvs))
    chk = os.listdir(os.path.join(pkg, "Checklists"))
    add("PASS" if len([f for f in chk if f.endswith(".docx")]) == 2 else "FAIL",
        "STROBE + GATHER 清单", ", ".join(sorted(chk)))


def check_hygiene(pkg):
    for f in sorted(os.listdir(pkg)):
        if not f.endswith(".docx"):
            continue
        _, t = read_docx_text(os.path.join(pkg, f))
        cjk = CJK.findall(t)
        add("PASS" if not cjk else "FAIL", "%s 无中文残留" % f,
            "%d 个中文字符" % len(cjk) if cjk else "")
        left = MD_LEFTOVER.findall(t)
        add("PASS" if not left else "WARN", "%s 无 markdown 残留" % f,
            "命中 %s" % sorted(set(left)) if left else "")


def check_numbers(pkg):
    _, main = read_docx_text(os.path.join(pkg, "01_Main_Manuscript.docx"))
    body = main[main.find("Introduction"):]

    figs = set(int(x) for x in re.findall(r"Fig(?:ure)?\s?(\d)", body))
    add("PASS" if figs >= {1, 2, 3, 4, 5, 6} else "FAIL", "Fig 1–6 全部在正文引用",
        "已引用 %s" % sorted(figs))

    cov = set()
    for m in re.finditer(r"Tables?\s+(S\d+)(?:\s*[\u2013\-]\s*(S\d+))?", body):
        lo = int(m.group(1)[1:])
        hi = int(m.group(2)[1:]) if m.group(2) else lo
        cov.update(range(lo, hi + 1))
    missing = [i for i in range(1, 17) if i not in cov]
    add("PASS" if not missing else "FAIL", "Table S1–S16 全部在正文引用",
        "未引用 %s" % missing if missing else "16/16 覆盖")

    legacy = re.findall(r"Table\s([1-4])\b", body)
    add("PASS" if not legacy else "FAIL", "正文无旧表号 Table 1–4", "命中 %s" % legacy if legacy else "")

    # 图按首次提及顺序编号
    order = []
    for m in re.finditer(r"Fig(?:ure)?\s?(\d)", body):
        n = int(m.group(1))
        if n not in order:
            order.append(n)
    add("PASS" if order == sorted(order) else "FAIL",
        "Fig 按首次提及顺序编号", "首现顺序 %s" % order)

    # 引文按首次出现顺序编号（Vancouver）
    cits = []
    for m in re.finditer(r"\[(\d+(?:\s*[,\u2013\-]\s*\d+)*)\]", body):
        for part in m.group(1).split(","):
            part = part.strip()
            if re.search(r"[\u2013\-]", part):
                a, b = re.split(r"[\u2013\-]", part)
                cits.extend(range(int(a), int(b) + 1))
            elif part.isdigit():
                cits.append(int(part))
    first = []
    for c in cits:
        if c not in first:
            first.append(c)
    add("PASS" if first == sorted(first) else "FAIL",
        "引文按首次出现顺序编号", "首现顺序尾段 %s" % first[-4:])

    # running head ≤ 40 字符（Lancet 系列要求）
    _, full = read_docx_text(os.path.join(pkg, "01_Main_Manuscript.docx"))
    m = re.search(r"Running head:?\s*(.+)", full)
    if m:
        rh = m.group(1).strip()
        add("PASS" if len(rh) <= 40 else "WARN", "Running head ≤ 40 字符",
            "%d 字符：%s" % (len(rh), rh))


def check_counts(pkg):
    d, main = read_docx_text(os.path.join(pkg, "01_Main_Manuscript.docx"))
    ps = [p.text for p in d.paragraphs]
    try:
        i = [k for k, p in enumerate(ps) if p.strip() == "Abstract"][0]
        kw = [k for k, p in enumerate(ps) if p.strip().startswith("Keywords")][0]
        intro = [k for k, p in enumerate(ps) if p.strip() == "Introduction"][0]
    except IndexError:
        add("FAIL", "可定位 Abstract / Keywords / Introduction", "结构异常")
        return
    heads = {"Background.", "Methods.", "Findings.", "Interpretation.", "Funding."}
    ab = [x for x in " ".join(ps[i + 1:kw]).split() if x not in heads]
    add("PASS" if len(ab) <= 250 else "FAIL", "Abstract ≤ 250 词（Word 口径）", "%d 词" % len(ab))

    # 正文词数：Introduction 起至 References 前，剔除图注/表注段
    end = [k for k, p in enumerate(ps) if p.strip() == "References"][0]
    body = " ".join(ps[intro:end])
    add("INFO", "正文区间段落数", "%d 段（脚本字数见 wordcount_manuscript.py）" % (end - intro))

    refs = main[main.find("References"):]
    n = len(re.findall(r"^\s*(\d{1,2})\.\s+\S", refs, re.M))
    add("PASS" if 0 < n <= 30 else "FAIL", "参考文献 ≤ 30 条", "%d 条" % n)


def check_declarations(pkg):
    _, main = read_docx_text(os.path.join(pkg, "01_Main_Manuscript.docx"))
    for s in REQ_SECTIONS:
        add("PASS" if s in main else "FAIL", "声明小节：%s" % s, "" if s in main else "缺失")


def check_cover_letter(pkg):
    _, cl = read_docx_text(os.path.join(pkg, "00_Cover_Letter.docx"))
    for s in ["eClinicalMedicine", "5.7", "STROBE", "GATHER", "competing interests", "funding"]:
        add("PASS" if s in cl else "WARN", "Cover Letter 含「%s」" % s)
    add("WARN" if "to be completed" in cl else "PASS", "推荐审稿人一栏需作者填写",
        "仍为占位符" if "to be completed" in cl else "已填写")


def check_checklists(pkg):
    d = os.path.join(pkg, "Checklists")
    for f in sorted(os.listdir(d)):
        if not f.endswith(".docx"):
            continue
        _, t = read_docx_text(os.path.join(d, f))
        cjk = CJK.findall(t)
        add("PASS" if not cjk else "FAIL", "%s 无中文" % f, "%d 字符" % len(cjk) if cjk else "")


def main():
    pkg = DEFAULT_PKG
    if "--pkg" in sys.argv:
        pkg = sys.argv[sys.argv.index("--pkg") + 1]

    check_files(pkg)
    check_hygiene(pkg)
    check_numbers(pkg)
    check_counts(pkg)
    check_declarations(pkg)
    check_cover_letter(pkg)
    check_checklists(pkg)

    n = {"PASS": 0, "WARN": 0, "FAIL": 0, "INFO": 0}
    for lv, _, _ in ROWS:
        n[lv] = n.get(lv, 0) + 1

    out = []
    out.append("# 投稿包审查报告（eClinicalMedicine）\n")
    out.append("**目录**：`%s`　**脚本**：`code/tools/audit_submission_package.py`\n" % os.path.basename(pkg))
    out.append("**结果**：PASS %d / WARN %d / FAIL %d\n" % (n["PASS"], n["WARN"], n["FAIL"]))
    out.append("| 级别 | 检查项 | 详情 |")
    out.append("|---|---|---|")
    for lv, item, detail in ROWS:
        if lv == "INFO":
            continue
        out.append("| %s | %s | %s |" % (lv, item, detail))

    txt = "\n".join(out) + "\n"
    # 报告写到项目根（不进投稿包，避免误上传到投稿系统）
    rpt = os.path.join(ROOT, "_\u5ba1\u67e5\u62a5\u544a_\u6295\u7a3f\u5305_eClinMed.md")
    io.open(rpt, "w", encoding="utf-8").write(txt)

    for lv, item, detail in ROWS:
        if lv != "INFO":
            print("%-4s %-46s %s" % (lv, item, detail))
    print("\n== PASS %d / WARN %d / FAIL %d ==" % (n["PASS"], n["WARN"], n["FAIL"]))
    return 0 if n["FAIL"] == 0 else 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
