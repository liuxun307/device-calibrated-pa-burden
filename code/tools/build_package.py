# -*- coding: utf-8 -*-
"""
build_package.py — 把投稿所需文件汇总到「一个文件夹」

产出：<项目根>/投稿包_eClinMed_2026-11-01/
  00_Cover_Letter.docx / .md
  01_Main_Manuscript.docx
  02_Figure_Legends.docx
  03_Table_S13_S16.docx
  04_Table_S1_S12.docx
  05_Supplementary_Table_Captions.docx
  上传清单_UPLOAD.md
  Figures/            Fig1–6 .pdf/.png
  Supplementary_PDF/  TableS*.pdf
  Checklists/         STROBE / GATHER（英文，docx）
  Data_Tables_CSV/    全部表格 CSV

用法：<venv>/Scripts/python.exe code/tools/build_package.py
"""
import csv, io, os, shutil, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_docx as B

STAMP = "2026-11-01"
PKG = os.path.join(B.ROOT, "\u6295\u7a3f\u5305_eClinMed_%s" % STAMP)

FIG_DIR = os.path.join(PKG, "Figures")
SUP_DIR = os.path.join(PKG, "Supplementary_PDF")
CHK_DIR = os.path.join(PKG, "Checklists")
CSV_DIR = os.path.join(PKG, "Data_Tables_CSV")

MANAGED = [FIG_DIR, SUP_DIR, CHK_DIR, CSV_DIR]


def clean():
    """只清理本脚本自己管理的目录，不触碰其他内容。"""
    for d in MANAGED:
        if os.path.isdir(d):
            shutil.rmtree(d)
    if os.path.isdir(PKG):
        for f in os.listdir(PKG):
            p = os.path.join(PKG, f)
            if os.path.isfile(p) and (f.endswith(".docx") or f.endswith(".md")):
                os.remove(p)
    for d in MANAGED:
        os.makedirs(d, exist_ok=True)


def copy(src, dst):
    if not os.path.exists(src):
        print("!! missing: %s" % src)
        return False
    shutil.copy2(src, dst)
    return True


def main():
    os.makedirs(PKG, exist_ok=True)
    clean()

    # ---- 1. 文档类 ----
    # 主稿直接生成到包内：避开 submission_eClinMed/word 下可能被 Word/WPS 占用的旧文件
    B.build_main(os.path.join(PKG, "01_Main_Manuscript.docx"))
    copy(os.path.join(B.WORD, "Figure_Legends.docx"),
         os.path.join(PKG, "02_Figure_Legends.docx"))
    copy(os.path.join(B.WORD, "Tables_S13_S16.docx"),
         os.path.join(PKG, "03_Table_S13_S16.docx"))
    copy(os.path.join(B.WORD, "Tables_S1_S12_data.docx"),
         os.path.join(PKG, "04_Table_S1_S12.docx"))
    copy(os.path.join(B.WORD, "Supplementary_Tables_S1_S16_captions.docx"),
         os.path.join(PKG, "05_Supplementary_Table_Captions.docx"))

    # 投稿信（md 为主，另转 docx）
    cl_md = os.path.join(B.SUB, "00_Cover_Letter.md")
    copy(cl_md, os.path.join(PKG, "00_Cover_Letter.md"))
    B.build_md_docx(cl_md, os.path.join(PKG, "00_Cover_Letter.docx"), size=11)

    # 清单（英文版；中文底稿不作为投稿件）
    for name, out in [("STROBE_checklist_EN.md", "STROBE_checklist.docx"),
                      ("GATHER_checklist_EN.md", "GATHER_checklist.docx")]:
        src = os.path.join(B.SUB, "checklists", name)
        if os.path.exists(src):
            B.build_md_docx(src, os.path.join(CHK_DIR, out), size=10, landscape=True)

    # ---- 2. 图（主文 Fig 1–6）----
    nfig = 0
    for i in range(1, 7):
        for ex in ("pdf", "png"):
            s = os.path.join(B.SUB, "figures", "Fig%d.%s" % (i, ex))
            if copy(s, os.path.join(FIG_DIR, "Fig%d.%s" % (i, ex))):
                nfig += 1

    # ---- 3. 补充表印刷版 PDF ----
    # 2026-11-01：09_tables.R 已把逐国表改名为 TableS12_burden_bycountry，
    # 与补充表编号一致，故不再排除；旧名 TableS4_recomputed_vs_gbd_bycountry 已废弃。
    nsup, skipped_pdf = 0, []
    sdir = os.path.join(B.SUB, "supplementary")
    for f in sorted(os.listdir(sdir)):
        if f.lower().endswith(".pdf"):
            if copy(os.path.join(sdir, f), os.path.join(SUP_DIR, f)):
                nsup += 1

    # ---- 4. 全部表格 CSV ----
    ncsv = 0
    for f in sorted(os.listdir(B.TAB)):
        if f.lower().endswith(".csv"):
            if copy(os.path.join(B.TAB, f), os.path.join(CSV_DIR, f)):
                ncsv += 1

    # ---- 5. 上传清单 ----
    rows = []
    for f in sorted(os.listdir(PKG)):
        p = os.path.join(PKG, f)
        if os.path.isfile(p):
            rows.append((f, os.path.getsize(p) / 1024.0))
    txt = []
    txt.append("# \u6295\u7a3f\u5305\u4e0e\u4e0a\u4f20\u6e05\u5355\uff08eClinicalMedicine\uff09\n")
    txt.append("**\u751f\u6210\u65f6\u95f4**\uff1a%s\u3000**\u811a\u672c**\uff1a`code/tools/build_package.py`\uff08\u53ef\u91cd\u8dd1\uff09\n" % STAMP)
    txt.append("**\u539f\u7a3f**\uff1a`submission_eClinMed/`\uff08\u7ec4\u88c5\u4ea7\u7269\uff09\uff0c\u6e90\u6587\u4ef6\u5728 `manuscript/`\u3002\n")
    txt.append("\n## \u4e00\u3001\u6309\u7cfb\u7edf\u4e0a\u4f20\u987a\u5e8f\n")
    txt.append("| \u6b65\u9aa4 | \u4e0a\u4f20\u9879 | \u6587\u4ef6 | \u5907\u6ce8 |")
    txt.append("|---|---|---|---|")
    txt.append("| 1 | Cover Letter | `00_Cover_Letter.docx`\uff08\u6216 .md\uff09 | \u63a8\u8350\u5ba1\u7a3f\u4eba\u4e00\u680f\u4e3a\u53ef\u9009\uff0c\u9700\u4f5c\u8005\u81ea\u884c\u586b\u5199 |")
    txt.append("| 2 | Main Manuscript | `01_Main_Manuscript.docx` | \u6807\u9898\u9875 + \u6458\u8981 + \u6b63\u6587 + \u53c2\u8003\u6587\u732e\uff0c\u8fde\u7eed\u6587\u6863 |")
    txt.append("| 3 | Figures | `Figures/Fig1.pdf` \u2026 `Fig6.pdf` | \u6bcf\u5f20\u5355\u72ec\u4e0a\u4f20\uff1b.png \u4ec5\u4f9b\u9884\u89c8 |")
    txt.append("| 4 | Figure legends | `02_Figure_Legends.docx` | Fig 1\u20136 \u82f1\u6587\u56fe\u6ce8 |")
    txt.append("| 5 | Tables | `03_Table_S13_S16.docx`\uff08\u4e3b\u8868\uff09+ `04_Table_S1_S12.docx` | \u82e5\u7cfb\u7edf\u53ea\u6536\u8868\u683c\u6587\u4ef6\uff0c\u4e24\u4e2a\u90fd\u4e0a\u4f20 |")
    txt.append("| 6 | Supplementary | `05_Supplementary_Table_Captions.docx`\u3001`Supplementary_PDF/`\u3001`Data_Tables_CSV/` | \u8868\u6ce8\u7d22\u5f15 + \u5370\u5237\u7248 + \u673a\u5668\u53ef\u8bfb\u6570\u636e |")
    txt.append("| 7 | Checklists | `Checklists/STROBE_checklist.docx`\u3001`GATHER_checklist.docx` | \u4e24\u4efd\u5747\u9700\u4e0a\u4f20 |")
    txt.append("\n> \u4e3b\u6587\u65e0\u8868\uff1a\u539f Table 1\u20134 \u5df2\u4e0b\u6c89\u4e3a Table S13\u2013S16\u3002\u82e5\u76ee\u6807\u520a\u5f3a\u5236\u8981\u6c42\u4e3b\u6587\u8868\uff0c\u628a `03_Table_S13_S16.docx` \u7684\u8868\u53f7\u6539\u4e3a Table 1\u20134 \u5373\u53ef\uff0c\u6570\u636e\u4e0e\u8868\u6ce8\u5b8c\u5168\u4e00\u81f4\u3002\n")
    txt.append("\n## \u4e8c\u3001\u6839\u76ee\u5f55\u6587\u4ef6\n")
    txt.append("| \u6587\u4ef6 | \u5927\u5c0f (KB) |")
    txt.append("|---|---:|")
    for f, kb in rows:
        txt.append("| `%s` | %.1f |" % (f, kb))
    txt.append("\n## \u4e09\u3001\u5b50\u76ee\u5f55\n")
    txt.append("| \u76ee\u5f55 | \u6587\u4ef6\u6570 | \u5185\u5bb9 |")
    txt.append("|---|---:|---|")
    txt.append("| `Figures/` | %d | Fig 1\u20136 \u7684 PDF \u4e0e PNG |" % nfig)
    txt.append("| `Supplementary_PDF/` | %d | Table S12\u2013S16 \u7684\u5370\u5237\u7248\uff08S15 \u5206 a/b \u4e24\u9875\uff0cS12 \u4e3a 204 \u56fd\u9010\u56fd\u8868\uff09 |" % nsup)
    txt.append("| `Checklists/` | 2 | STROBE / GATHER \u82f1\u6587\u586b\u5199\u7248 |")
    txt.append("| `Data_Tables_CSV/` | %d | \u5168\u90e8\u8868\u683c\u7684\u673a\u5668\u53ef\u8bfb\u6570\u636e\uff08\u5217\u540d\u5df2\u82f1\u6587\u5316\uff09 |" % ncsv)
    if skipped_pdf:
        txt.append("\n> \u672a\u7eb3\u5165\uff1a%s\u3002\u8be5 PDF \u9875\u9762\u6807\u9898\u4ecd\u4e3a\u65e7\u7f16\u53f7"
                   "\u300cTable S4\u300d\uff08\u73b0 S4 \u5df2\u4e3a\u9acb\u5f0f\u00d7\u8155\u5f0f\u77e9\u9635\uff09\uff0c"
                   "\u4e0e\u8868\u6ce8\u6e05\u5355\u51b2\u7a81\uff1b\u5176\u6570\u636e\u5df2\u7531 "
                   "`04_Table_S1_S12.docx`\uff08Table S12\uff09\u4e0e CSV \u5b8c\u6574\u8986\u76d6\u3002"
                   % "\u3001".join("`%s`" % f for f in skipped_pdf))
    txt.append("\n## \u56db\u3001\u4e0a\u4f20\u524d\u8bf7\u4f5c\u8005\u786e\u8ba4\n")
    txt.append("1. \u6807\u9898\u9875\u4f5c\u8005\u59d3\u540d\u3001\u5355\u4f4d\u3001\u5171\u4e00\u4e0e\u901a\u8baf\u6807\u8bb0\uff1b")
    txt.append("2. Cover Letter \u7684\u63a8\u8350\u5ba1\u7a3f\u4eba\uff08\u53ef\u9009\uff09\u4e0e\u7b7e\u540d\u4eba\uff1b")
    txt.append("3. \u751f\u6210\u5f0f AI \u4f7f\u7528\u58f0\u660e\u7684\u63aa\u8f9e\uff08\u4e3b\u7a3f Declarations \u4e0e Cover Letter \u5404\u4e00\u5904\uff09\u662f\u5426\u4e0e\u5b9e\u9645\u4f7f\u7528\u60c5\u51b5\u4e00\u81f4\u3002")
    open(os.path.join(PKG, "\u4e0a\u4f20\u6e05\u5355_UPLOAD.md"), "w", encoding="utf-8", newline="\n").write("\n".join(txt) + "\n")

    total = sum(os.path.getsize(os.path.join(dp, f))
                for dp, _, fs in os.walk(PKG) for f in fs)
    print("PKG  %s" % PKG)
    print("  root files : %d" % len(rows))
    print("  figures    : %d" % nfig)
    print("  supp PDF   : %d" % nsup)
    print("  csv        : %d" % ncsv)
    print("  total size : %.1f MB" % (total / 1048576.0))


if __name__ == "__main__":
    main()
