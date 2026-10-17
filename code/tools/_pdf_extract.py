# -*- coding: utf-8 -*-
"""把两篇待入池文献的 PDF 抽成文本，供逐字段核对。
输出：data/bop/_intake_extract/<slug>.txt（带页码标记）与 <slug>.pages.txt（按页分块）
用法：python code/tools/_pdf_extract.py
"""
import os
import re
import sys

import pymupdf

SRC = [
    ("ko2025_ukb_ckd",
     r"D:\浏览器下载\Association of accelerometer-measured physical activity with adverse cardiovascular outcomes in individuals with or without chronic kidney diseases_ the UK biobank study.pdf"),
    ("inaneroglu2024_ukb_dietpa",
     r"D:\浏览器下载\Joint Associations of Diet and Device-Measured Physical Activity with Mortality and Incident CVD and Cancer_ A Prospective Analysis of the UK Biobank Study.pdf"),
]

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "data", "bop", "_intake_extract")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for slug, path in SRC:
        if not os.path.exists(path):
            print("缺失:", path)
            continue
        doc = pymupdf.open(path)
        pages = []
        for i, page in enumerate(doc, start=1):
            t = page.get_text("text")
            t = re.sub(r"[ \t]+\n", "\n", t)
            pages.append((i, t))
        doc.close()

        full = "\n".join(f"\n===== PAGE {i} =====\n{t}" for i, t in pages)
        fp = os.path.join(OUT_DIR, slug + ".txt")
        with open(fp, "w", encoding="utf-8") as f:
            f.write(full)
        print(f"{slug}: {len(pages)} 页, {len(full)} 字符 -> {fp}")


if __name__ == "__main__":
    sys.exit(main())
