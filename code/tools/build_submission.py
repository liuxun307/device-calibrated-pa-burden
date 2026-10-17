# -*- coding: utf-8 -*-
"""
build_submission.py — 组装 eClinicalMedicine 投稿包
从 manuscript/ 各中英对照文件抽取 **English.** 段，按 IMRaD 合成投稿主稿；
归集图、表、清单、声明到 submission_eClinMed/。

用法：python code/tools/build_submission.py
口径：只抽 **English.** 到 **中文.**/**挂载**/---/## 之间的内容；跳过表格行(|)、
      引用块(>)、代码块、核对表与易错点等内部说明节（按节名黑名单）。
"""
import io, re, os, shutil, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAN  = os.path.join(ROOT, "manuscript")
SUB  = os.path.join(ROOT, "submission_eClinMed")

def read(p):   return io.open(p, encoding="utf-8").read()
def write(p,s):io.open(p, "w", encoding="utf-8", newline="\n").write(s)

STOP = ("**中文.**", "**挂载**", "---", "## ")
def extract_english(text):
    """抽取文件中全部 **English.** 段（按出现顺序）。"""
    out, lines, in_en = [], text.splitlines(), False
    for ln in lines:
        s = ln.strip()
        if s.startswith("**English.**"):
            in_en = True
            rest = s[len("**English.**"):].strip()
            if rest: out.append(rest)
            continue
        if in_en:
            if any(s.startswith(k) for k in STOP) or s.startswith("|") or s.startswith(">"):
                in_en = False
                continue
            out.append(ln)
    # 压缩多余空行
    txt, blank = [], 0
    for ln in out:
        blank = blank + 1 if not ln.strip() else 0
        if blank <= 1: txt.append(ln)
    return "\n".join(txt).strip()

def section_text(text, header_prefix):
    """取 `## <header_prefix>` 节的全文（到下一个 ## 为止）。"""
    lines, cap, on = text.splitlines(), [], False
    for ln in lines:
        if ln.startswith("## "):
            on = ln[3:].strip().startswith(header_prefix)
            continue
        if on: cap.append(ln)
    return "\n".join(cap)

def para_block(sec, start_prefix):
    """节内从 start_prefix 开头的段落到下一个空行/段落标题（含续行）。"""
    lines, out, on = sec.splitlines(), [], False
    for ln in lines:
        s = ln.strip()
        if s.startswith(start_prefix): on = True
        elif on and (not s or s.startswith(("(", "**", "-", "|", ">"))):
            if s == "" and out and out[-1] != "": out.append("")
            if s.startswith(("(", "**", "-")): on = False
            continue
        if on: out.append(ln)
    return "\n".join(out).strip()

def sec_eng(path, header):
    return extract_english(section_text(read(os.path.join(MAN, path)), header))

# ============================== 1. 主稿 =====================================
P = []
# --- Abstract ---
ab = read(os.path.join(MAN, "Abstract_结构化_中英对照.md"))
CJK = re.compile(r"[\u4e00-\u9fff]")
def strip_chinese(sec):
    keep = []
    for ln in sec.splitlines():
        if ln.strip().startswith(("**中文.**", "**挂载**")): break
        if CJK.search(ln): continue            # 纯中文对照行
        if ln.strip().startswith(("|", ">", "---")): continue
        keep.append(ln)
    txt, blank = [], 0
    for ln in keep:
        blank = blank + 1 if not ln.strip() else 0
        if blank <= 1: txt.append(ln)
    return "\n".join(txt).strip()
tr  = section_text(ab, "Title 与 Running head")
abx = section_text(ab, "Abstract（eClinicalMedicine")
kw  = section_text(ab, "Key words")
P.append(strip_chinese(tr)); P.append("")
P.append(strip_chinese(abx)); P.append("")
P.append(strip_chinese(kw))

# --- Introduction ---
P.append("# Introduction\n")
P.append(extract_english(read(os.path.join(MAN, "Introduction_P1_P4_中英对照.md"))))

# --- Methods（R1 除外）---
P.append("\n# Methods\n")
P.append("## Study population and exposure assessment\n")
P.append(sec_eng("Methods_2.1_Results_R1_样本与暴露_中英对照.md", "2.1 Study population"))
P.append("\n## Outcomes and covariates\n")
P.append(sec_eng("Methods_2.2_结局与协变量_中英对照.md", "2.2 Outcomes"))
P.append("\n## Module 1 — device-scale dose–response and calibration\n")
P.append(sec_eng("Methods_2.3_Module1_剂量反应与校准_中英对照.md", "2.3 Module 1"))
P.append("\n## Module 2 — evidence synthesis across cohorts\n")
m2 = read(os.path.join(MAN, "Methods_M2_证据合成_中英对照.md"))
for h in ["1. 池的数据来源", "2. 统计模型", "3. 先验", "4. 后验抽样",
          "5. 对比与外推", "6. 敏感性分析"]:
    P.append(extract_english(section_text(m2, h)))
P.append("\n## Module 3 — burden recomputation\n")
P.append(sec_eng("Methods_2.5_Module3_负担重算_中英对照.md", "2.5 Module 3"))
P.append("\n## Wear-site and metric-axis sensitivity analyses\n")
P.append(sec_eng("Methods_2.6_2.7_部位指标轴_敏感性与软件_中英对照.md", "2.6 Wear-site"))
P.append("\n## Sensitivity analyses and software\n")
P.append(sec_eng("Methods_2.6_2.7_部位指标轴_敏感性与软件_中英对照.md", "2.7 Sensitivity"))

# --- Results（R1 自 2.1 文件）---
P.append("\n# Results\n")
P.append("## Sample and baseline characteristics\n")
P.append(sec_eng("Methods_2.1_Results_R1_样本与暴露_中英对照.md", "R1 Sample"))
rres = read(os.path.join(MAN, "Results_R2_R6_中英对照.md"))
for h, t in [("R2 Self-report", "Self-report versus device measurement"),
             ("R3 Dose–response", "Dose–response"),
             ("R4 Calibration", "Calibration and reporting bias"),
             ("R5 Reconstructed burden", "Reconstructed burden versus GBD 2023"),
             ("R6 Sensitivity", "Sensitivity analyses")]:
    P.append("\n## %s\n" % t)
    P.append(extract_english(section_text(rres, h)))

# --- Discussion ---
P.append("\n# Discussion\n")
dd = read(os.path.join(MAN, "Discussion_D1_D4_D6_中英对照.md"))
d5 = read(os.path.join(MAN, "Discussion_D5_局限_中英对照.md"))
for h, t in [("D1 Principal", "Principal findings"),
             ("D2 Comparison", "Comparison with previous estimates"),
             ("D3 Origin", "Origin of the gap and policy implications"),
             ("D4 Strengths", "Strengths and innovation")]:
    P.append("\n## %s\n" % t)
    P.append(extract_english(section_text(dd, h)))
P.append("\n## Limitations\n")
P.append(extract_english(section_text(d5, "D5 Limitations")))
P.append("\n## Conclusion\n")
P.append(extract_english(section_text(dd, "D6 Conclusion")))

main = "\n".join(P)
write(os.path.join(SUB, "manuscript", "02_Main_Manuscript.md"), main)

# ============================== 2. References ================================
ref_src = read(os.path.join(MAN, "References_参考文献表_eClinMed.md"))
sec1 = section_text(ref_src, "1. 参考文献表")
lines, keep = sec1.splitlines(), []
for ln in lines:
    s = ln.strip()
    if not s or s.startswith(("#", "###", "---")): continue
    if s.startswith("<br/>"):  continue          # 中文/说明注释行
    if s.startswith("**注**"): continue
    if re.match(r"^\d+\.", s) or (keep and not s.startswith(("→", "**"))):
        if s.startswith("→") or s.startswith("**→"): continue
        keep.append(s)
refs = "\n".join(keep)
# 清理行内中文注释（行首 → 已滤；防漏）
refs = "\n".join(l for l in refs.splitlines() if "→" not in l[:6])
write(os.path.join(SUB, "manuscript", "03_References.md"),
      "# References\n\n" + refs)

# ============================== 3. Title Page ================================
shutil.copy(os.path.join(MAN, "Title_Page_投稿用.md"),
            os.path.join(SUB, "manuscript", "01_Title_Page.md"))

# ============================== 4. 声明（英文段）=============================
dec = read(os.path.join(MAN, "声明与补充材料_草稿_中英对照.md"))
# 声明文件节标题为 `## N. xxx`，抽全部 English 段但保留节结构
dec_out, lines, cur = [], dec.splitlines(), None
buf = []
def flush(title, buf):
    if title is None: return
    en = extract_english("\n".join(buf))
    if en: dec_out.append("## " + title + "\n\n" + en)
for ln in lines:
    if ln.startswith("## "):
        flush(cur, buf); cur = ln[3:].strip(); buf = []
    else:
        buf.append(ln)
flush(cur, buf)
write(os.path.join(SUB, "supplementary", "Declarations_声明.md"),
      "# Declarations\n\n" + "\n\n".join(dec_out))

# ============================== 5. 图 / 表 / 清单 ============================
FIG = os.path.join(ROOT, "figures")
for i in range(1, 7):
    for ex in ("pdf", "png"):
        src = os.path.join(FIG, "combined", "Fig%d.%s" % (i, ex))
        if os.path.exists(src):
            shutil.copy(src, os.path.join(SUB, "figures", "Fig%d.%s" % (i, ex)))
# 备选拼版
for nm in ("Fig3_combined_4panels", "Fig6_combined_2panels"):
    for ex in ("pdf", "png"):
        src = os.path.join(FIG, "combined", "%s.%s" % (nm, ex))
        if os.path.exists(src):
            shutil.copy(src, os.path.join(SUB, "figures", nm + "." + ex))
# 表（S1–S16 的 PDF/PNG，来自 figures/tables）
tabdir = os.path.join(FIG, "tables")
if os.path.isdir(tabdir):
    for fn in sorted(os.listdir(tabdir)):
        if fn.startswith("TableS") and fn.endswith((".pdf", ".png")):
            shutil.copy(os.path.join(tabdir, fn),
                        os.path.join(SUB, "supplementary", fn))
# 表数据 CSV
for fn in sorted(os.listdir(os.path.join(ROOT, "output"))):
    if fn.startswith("Table") and fn.endswith(".csv"):
        shutil.copy(os.path.join(ROOT, "output", fn),
                    os.path.join(SUB, "tables", fn))
shutil.copy(os.path.join(ROOT, "output", "CAPTIONS_figures_tables.md"),
            os.path.join(SUB, "supplementary", "CAPTIONS_figures_tables.md"))
shutil.copy(os.path.join(MAN, "STROBE_GATHER_清单_eClinMed.md"),
            os.path.join(SUB, "checklists", "STROBE_checklist.md"))
shutil.copy(os.path.join(MAN, "STROBE_GATHER_清单_eClinMed.md"),
            os.path.join(SUB, "checklists", "GATHER_checklist.md"))

print("主稿词数检查（英文段，含标题）:", len(re.findall(r"[A-Za-z][A-Za-z'\-]*", main)))
print("完成 -> submission_eClinMed/")
