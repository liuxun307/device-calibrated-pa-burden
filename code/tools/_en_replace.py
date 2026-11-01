# -*- coding: utf-8 -*-
"""
_en_replace.py — 安全替换 manuscript/ 中 **English.** 段：
只按「段序号」重写英文段正文，中文段与小节标题一律不动。

用法：在 Python 中 import 后调用 replace_en(path, index, new_text)
index 为文件中 **English.** 段出现的顺序（0 起）。
"""
import io, re


def _segments(lines):
    """返回 [(start_line, end_line_exclusive, marker_line_index)]，仅 **English.** 段。"""
    segs, cur = [], None
    for i, ln in enumerate(lines):
        s = ln.strip()
        if s.startswith("**English.**"):
            if cur is not None:
                segs.append((cur, i))
            cur = i
            continue
        if cur is not None and (s.startswith("**中文.**") or s.startswith("**挂载**")
                                or s.startswith("**Definitions") or s.startswith("---")
                                or s.startswith("## ") or s.startswith("# ")):
            # 段结束；若结束标记是标题/分隔，则回退尾部空行
            segs.append((cur, i))
            cur = None
    if cur is not None:
        segs.append((cur, len(lines)))
    return segs


def replace_en(path, index, new_body):
    """new_body 为不含 **English.** 前缀的正文（可多行）。"""
    text = io.open(path, encoding="utf-8").read()
    lines = text.splitlines()
    segs = _segments(lines)
    if index >= len(segs):
        raise IndexError("%s: 只有 %d 个 English 段，请求第 %d 个" % (path, len(segs), index))
    a, b = segs[index]
    # 去掉段尾的连续空行，保留原有分隔
    end = b
    while end > a + 1 and not lines[end - 1].strip():
        end -= 1
    head = lines[a]
    rest = head[len("**English.**"):].strip()
    first = new_body.splitlines()[0]
    rebuilt = ["**English.** " + new_body.rstrip()]
    new_lines = lines[:a] + rebuilt + lines[end:]
    io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(new_lines) + "\n")
    return a + 1, end


if __name__ == "__main__":
    import sys
    p = sys.argv[1]
    t = io.open(p, encoding="utf-8").read()
    segs = _segments(t.splitlines())
    print("%s: %d 个 English 段" % (p, len(segs)))
