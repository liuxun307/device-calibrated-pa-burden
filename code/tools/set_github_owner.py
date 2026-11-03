#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""set_github_owner.py — 一处改动，同步所有出现仓库地址的位置。

背景：仓库 owner 名曾写死为 liuxun-sj-hospital，但该账号在 GitHub 上并不存在，
      导致 README / CITATION.cff / docs / git remote 全部指向死链。
      本脚本把 owner 名在下列位置统一替换，并可选地同步 git remote。

用法：
    python set_github_owner.py <新owner>                       # 预演，只打印将改什么
    python set_github_owner.py <新owner> --apply               # 真正写入
    python set_github_owner.py <新owner> --apply --remote      # 同时改 git remote

替换范围（写死的清单，不靠通配搜索，避免误伤）：
    README.md
    CITATION.cff
    docs/GITHUB_UPLOAD_GUIDE.md
    docs/UPLOAD_CHECKLIST.md
    .git/config（origin 的 url，可选，加 --remote）

两遍替换：
    A. URL 形态  https://github.com/<owner>/…  与  git@github.com:<owner>/…
    B. 裸用户名  docs 里「账号填 <owner>」这类散文提及（只对 docs 生效）
"""
import io
import os
import re
import sys
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REPO = "device-calibrated-pa-burden"
OLD = "liuxun-sj-hospital"          # 已知的、GitHub 上不存在的 owner（改名时改这一行）
FILES = [
    "README.md",
    "CITATION.cff",
    os.path.join("docs", "GITHUB_UPLOAD_GUIDE.md"),
    os.path.join("docs", "UPLOAD_CHECKLIST.md"),
]
PROSE_FILES = {os.path.join("docs", "GITHUB_UPLOAD_GUIDE.md"),
               os.path.join("docs", "UPLOAD_CHECKLIST.md")}

# 匹配 https://github.com/<owner>/device-calibrated-pa-burden 与
# git@github.com:<owner>/device-calibrated-pa-burden 两种形态
PAT = re.compile(
    r"(https://github\.com/|git@github\.com:)([A-Za-z0-9._-]+)/" + re.escape(REPO)
)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if not args:
        print(__doc__)
        return 2
    owner = args[0].strip()
    apply_ = "--apply" in flags
    with_remote = "--remote" in flags

    print("目标 owner : %s" % owner)
    print("模式       : %s" % ("写入" if apply_ else "预演（不落盘）"))
    print("")

    total = 0
    for rel in FILES:
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            print("  跳过（不存在）: %s" % rel)
            continue
        txt = io.open(p, encoding="utf-8").read()
        hits = PAT.findall(txt)
        owners = sorted({m[1] for m in hits})

        # A. URL 形态
        url_changes = 0
        if hits and owners != [owner]:
            txt = PAT.sub(lambda m: m.group(1) + owner + "/" + REPO, txt)
            url_changes = len(hits)

        # B. 散文中裸用户名（仅 docs）
        prose_changes = 0
        if rel in PROSE_FILES and OLD != owner and OLD in txt:
            prose_changes = txt.count(OLD)
            txt = txt.replace(OLD, owner)

        n = url_changes + prose_changes
        if n == 0:
            print("  无需改动: %s（owner 已是 %s）" % (rel, owner))
            continue
        print("  待改  : %s  URL %d 处 + 散文 %d 处  %s -> %s"
              % (rel, url_changes, prose_changes, owners or [OLD], owner))
        total += n
        if apply_:
            io.open(p, "w", encoding="utf-8", newline="\n").write(txt)

    if with_remote:
        url = "https://github.com/%s/%s.git" % (owner, REPO)
        print("\n  remote origin -> %s" % url)
        if apply_:
            subprocess.check_call(["git", "-C", ROOT, "remote", "set-url", "origin", url])
            print("  已更新 .git/config")

    print("\n合计 %d 处%s" % (total, "已替换" if apply_ else "待替换（加 --apply 生效）"))
    if apply_:
        print("\n下一步：重跑 code/tools/build_package.py 让 docx 同步，并 git commit。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
