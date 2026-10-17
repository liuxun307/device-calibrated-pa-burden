# -*- coding: utf-8 -*-
"""把正文各文件的 **English.** 段抽成可审计快照（裁剪前存档 / 裁剪后比对）。

用法：
    python code/tools/snapshot_manuscript.py --out <输出目录>
    python code/tools/snapshot_manuscript.py --diff <快照A目录> <快照B目录>

快照只含英文正文，不含中文对照与元数据，便于逐段 diff 与词数复算。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "manuscript"
FILES = [
    "Introduction_P1_P4_中英对照.md",
    "Methods_2.1_Results_R1_样本与暴露_中英对照.md",
    "Methods_2.2_结局与协变量_中英对照.md",
    "Methods_2.3_Module1_剂量反应与校准_中英对照.md",
    "Methods_M2_证据合成_中英对照.md",
    "Methods_2.5_Module3_负担重算_中英对照.md",
    "Methods_2.6_2.7_部位指标轴_敏感性与软件_中英对照.md",
    "Results_R2_R6_中英对照.md",
    "Discussion_D1_D4_D6_中英对照.md",
    "Discussion_D5_局限_中英对照.md",
]
PAT = re.compile(r"\*\*English\.\*\*(.*?)(?=\*\*中文|\*\*Chinese|\n## |\n---|\Z)", re.S)


def words(s: str) -> int:
    s = re.sub(r"`[^`]*`", " ", s)
    return len(re.findall(r"[A-Za-z][A-Za-z'\-]*", s))


def snapshot(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    idx = {}
    for f in FILES:
        p = ROOT / f
        if not p.exists():
            continue
        blocks = [m.group(1).strip() for m in PAT.finditer(p.read_text(encoding="utf-8"))]
        # 去掉表格行与引用行，避免中文注释混入
        clean = ["\n".join(l for l in b.splitlines()
                           if not l.strip().startswith(("|", ">", "```"))) for b in blocks]
        idx[f] = {"n_blocks": len(clean), "words": sum(words(b) for b in clean)}
        (out_dir / (f.replace(".md", ".EN.txt"))).write_text(
            "\n\n".join(f"[[block {i+1}]]\n{b}" for i, b in enumerate(clean)), encoding="utf-8")
    (out_dir / "_index.json").write_text(json.dumps(idx, ensure_ascii=False, indent=2), encoding="utf-8")
    total = sum(v["words"] for v in idx.values())
    print(f"snapshot → {out_dir}")
    for k, v in idx.items():
        print(f"  {k:52s} {v['n_blocks']:3d} blocks  {v['words']:5d} words")
    print(f"  {'TOTAL':52s} {'':9s} {total:5d} words")


def diff(a: Path, b: Path) -> None:
    for f in FILES:
        fa, fb = a / f.replace(".md", ".EN.txt"), b / f.replace(".md", ".EN.txt")
        if not fa.exists() or not fb.exists():
            continue
        ta = fa.read_text(encoding="utf-8").split("\n\n")
        tb = fb.read_text(encoding="utf-8").split("\n\n")
        wa, wb = words("\n".join(ta)), words("\n".join(tb))
        print(f"{f:52s} {wa:5d} → {wb:5d}  ({wb-wa:+5d})  blocks {len(ta)}→{len(tb)}")


if __name__ == "__main__":
    if "--out" in sys.argv:
        snapshot(Path(sys.argv[sys.argv.index("--out") + 1]))
    elif "--diff" in sys.argv:
        i = sys.argv.index("--diff")
        diff(Path(sys.argv[i + 1]), Path(sys.argv[i + 2]))
    else:
        print(__doc__)
