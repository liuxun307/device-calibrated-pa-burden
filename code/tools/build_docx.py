# -*- coding: utf-8 -*-
"""
build_docx.py — 由投稿包 markdown / csv 生成 Word（.docx）

产出：
  submission_eClinMed/word/02_Main_Manuscript.docx   主稿（Title Page + Abstract + IMRaD + References）
  submission_eClinMed/word/Tables_S13_S16.docx       投稿表（S13–S16，含表注 + 数据表）

依赖：python-docx（托管 venv：C:/Users/Lenovo/.workbuddy/binaries/python/envs/default/Scripts/python.exe）
用法：<venv>/Scripts/python.exe code/tools/build_docx.py
"""
import csv, io, os, re, sys

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Pt, Cm, RGBColor

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SUB = os.path.join(ROOT, "submission_eClinMed")
WORD = os.path.join(SUB, "word")
TAB = os.path.join(SUB, "tables")
SUP = os.path.join(SUB, "supplementary")

CJK = re.compile(r"[\u4e00-\u9fff]")
BOLD_RE = re.compile(r"\*\*(.+?)\*\*")
ITAL_RE = re.compile(r"(?<!\*)\*([^*\n]+)\*(?!\*)")

# 无法安全英文化、只以 CSV 形式提供的补充表（生成时填充，便于最终审计）
SKIPPED_TABLES = []


def read(p):
    return io.open(p, encoding="utf-8").read()


# ---------------------------------------------------------------- 文档基础设置
def new_doc():
    doc = Document()
    st = doc.styles["Normal"]
    st.font.name = "Times New Roman"
    st.font.size = Pt(12)
    st.element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")
    pf = st.paragraph_format
    pf.line_spacing_rule = WD_LINE_SPACING.DOUBLE
    pf.space_after = Pt(0)
    pf.space_before = Pt(0)
    for sec in doc.sections:
        sec.top_margin = sec.bottom_margin = Cm(2.54)
        sec.left_margin = sec.right_margin = Cm(2.54)
    return doc


def add_runs(par, text, base_bold=False, base_italic=False, size=None):
    """把 **bold** / *italic* 标记转成真实格式；`\\*` 视为字面星号。

    行内反引号（markdown 代码标记）在投稿正文中不应出现，统一剥离为纯文本。
    """
    text = text.replace("`", "")
    text = text.replace("\\*", "\u0000")

    def clean(s):
        return s.replace("\u0000", "*")

    tokens = []
    pos = 0
    for m in BOLD_RE.finditer(text):
        if m.start() > pos:
            tokens.append((text[pos:m.start()], False))
        tokens.append((m.group(1), True))
        pos = m.end()
    if pos < len(text):
        tokens.append((text[pos:], False))
    for seg, bold in tokens:
        for part_m in re.finditer(r"(?<!\*)\*([^*\n]+)\*(?!\*)", seg):
            if part_m.start() > 0:
                r = par.add_run(clean(seg[:part_m.start()]))
                r.bold = base_bold or bold
                r.italic = base_italic
                if size: r.font.size = Pt(size)
            r = par.add_run(clean(part_m.group(1)))
            r.bold = base_bold or bold
            r.italic = True
            if size: r.font.size = Pt(size)
            seg = seg[part_m.end():]
        if seg:
            r = par.add_run(clean(seg))
            r.bold = base_bold or bold
            r.italic = base_italic
            if size: r.font.size = Pt(size)


def _save(doc, path):
    """保存；若目标被 Word/WPS 占用，改写 *_new.docx 并显式报警，不静默失败。"""
    try:
        doc.save(path)
        return path
    except PermissionError:
        alt = path[:-5] + "_new.docx"
        doc.save(alt)
        print("!! %s is locked (open in Word/WPS); written to %s instead"
              % (os.path.basename(path), os.path.basename(alt)))
        return alt


def _keep_en(block):
    """投稿版只保留不含中文的块；表格逐格检查，含中文则整表剔除。"""
    kind, val = block[0], block[1]
    if kind == "table":
        return not any(CJK.search(c) for row in val for c in row)
    return not CJK.search(val)


def heading(doc, text, level=1):
    """使用 Word 内置标题样式（导航窗格/PDF 书签可跳转），再覆盖为投稿用字体。"""
    sizes = {1: 14, 2: 12, 3: 12}
    p = doc.add_paragraph(style="Heading %d" % level)
    p.paragraph_format.space_before = Pt(12)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE
    p.paragraph_format.keep_with_next = True
    r = p.add_run(text)
    r.bold = True
    r.font.size = Pt(sizes.get(level, 12))
    r.font.name = "Times New Roman"
    r.font.color.rgb = RGBColor(0, 0, 0)
    r.element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")
    return p


def para(doc, text, first_indent=False, size=None, align=None, space_after=6):
    p = doc.add_paragraph()
    if first_indent:
        p.paragraph_format.first_line_indent = Cm(0.75)
    p.paragraph_format.space_after = Pt(space_after)
    if align:
        p.alignment = align
    add_runs(p, text, size=size)
    return p


# ---------------------------------------------------------------- markdown 解析
def _split_row(s):
    """`| a | b |` -> ['a','b']（保留单元格内的转义竖线已被作者避免使用）。"""
    return [c.strip() for c in s.strip().strip("|").split("|")]


def md_blocks(text):
    """粗粒度解析：返回 [('h1'|'h2'|'h3'|'p'|'li'|'quote'|'table', 内容|行列表)]"""
    out, buf, tbl = [], [], []

    def flush_para():
        if buf:
            out.append(("p", " ".join(x.strip() for x in buf).strip()))
            del buf[:]

    def flush_table():
        if tbl:
            rows = [r for r in tbl if not re.match(r"^[\|\s:\-]+$", r)]
            out.append(("table", [_split_row(r) for r in rows]))
            del tbl[:]

    for raw in text.splitlines():
        s = raw.strip()
        if s.startswith("|"):
            flush_para()
            tbl.append(s)
            continue
        flush_table()
        if not s:
            flush_para(); continue
        if s.startswith("### "):
            flush_para(); out.append(("h3", s[4:].strip()))
        elif s.startswith("## "):
            flush_para(); out.append(("h2", s[3:].strip()))
        elif s.startswith("# "):
            flush_para(); out.append(("h1", s[2:].strip()))
        elif s.startswith(">"):
            flush_para(); out.append(("quote", s.lstrip("> ").strip()))
        elif s.startswith(("- ", "* ")):
            flush_para(); out.append(("li", s[2:].strip()))
        elif s.startswith("---"):
            flush_para()
        elif re.match(r"^\d{1,2}\.\s+\S", s):
            # 参考文献条目/编号行：每条独立成段，避免多条被合并成一大段
            flush_para(); out.append(("p", s))
        else:
            buf.append(s)
    flush_table(); flush_para()
    return out


def add_md_table(doc, rows, size=9):
    """markdown 行列表 -> Word 表（首行表头）。"""
    if not rows:
        return
    ncol = max(len(r) for r in rows)
    t = doc.add_table(rows=len(rows), cols=ncol)
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, row in enumerate(rows):
        for j in range(ncol):
            val = row[j] if j < len(row) else ""
            set_cell(t.rows[i].cells[j], val, bold=(i == 0), size=size)
    trPr = t.rows[0]._tr.get_or_add_trPr()
    el = OxmlElement("w:tblHeader")
    el.set(qn("w:val"), "true")
    trPr.append(el)
    doc.add_paragraph()


def build_from_md(doc, text, skip_cjk=True):
    for kind, body in md_blocks(text):
        if skip_cjk and CJK.search(body) and kind == "p":
            continue
        if kind == "h1":
            heading(doc, body, 1)
        elif kind == "h2":
            heading(doc, body, 2)
        elif kind == "h3":
            heading(doc, body, 3)
        elif kind == "li":
            p = doc.add_paragraph(style="List Bullet")
            p.paragraph_format.space_after = Pt(2)
            add_runs(p, body)
        elif kind == "quote":
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Cm(0.75)
            p.paragraph_format.space_after = Pt(4)
            add_runs(p, body, size=10)
        else:
            para(doc, body, first_indent=True)


# ---------------------------------------------------------------- 主稿
def emit(doc, blocks, size=None):
    for kind, body in blocks:
        if kind == "table":
            add_md_table(doc, body)
        elif kind == "pagebreak":
            doc.add_page_break()
        elif kind == "doctitle":
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_before = Pt(0)
            p.paragraph_format.space_after = Pt(14)
            p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE
            r = p.add_run(body)
            r.bold = True
            r.font.size = Pt(15)
            r.font.name = "Times New Roman"
        elif kind == "h1":
            heading(doc, body, 1)
        elif kind == "h2":
            heading(doc, body, 2)
        elif kind == "h3":
            heading(doc, body, 3)
        elif kind == "li":
            p = doc.add_paragraph(style="List Bullet")
            p.paragraph_format.space_after = Pt(2)
            add_runs(p, body)
        elif kind == "quote":
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Cm(0.75)
            p.paragraph_format.space_after = Pt(4)
            add_runs(p, body, size=10)
        else:
            is_ref = re.match(r"^\d+\.\s", body) is not None
            is_label = re.match(r"^\*\*(Background|Methods|Findings|Interpretation|Funding)\.\*\*", body) is not None
            p = doc.add_paragraph()
            p.paragraph_format.space_after = Pt(4 if not is_label else 2)
            if is_ref:
                p.paragraph_format.left_indent = Cm(0.75)
                p.paragraph_format.first_line_indent = Cm(-0.75)
            elif not is_label:
                p.paragraph_format.first_line_indent = Cm(0.75)
            add_runs(p, body, size=size)


def build_main(out_path=None):
    doc = new_doc()
    body = []

    # --- Title page（已改写为纯投稿版式，全量收录）---
    tp = read(os.path.join(SUB, "manuscript", "01_Title_Page.md"))
    tp_blocks = [b for b in md_blocks(tp) if _keep_en(b)]
    if tp_blocks and tp_blocks[0][0] == "h1":
        tp_blocks[0] = ("doctitle", tp_blocks[0][1])   # 标题居中大字，不占标题层级
    body.extend(tp_blocks)
    body.append(("pagebreak", ""))

    # --- Main manuscript（纯英文；去掉与标题页重复的标题行与 running head）---
    mm = read(os.path.join(SUB, "manuscript", "02_Main_Manuscript.md"))
    mm_blocks = [b for b in md_blocks(mm) if _keep_en(b)]
    title_txt = tp_blocks[0][1].strip() if tp_blocks else ""
    rh_txt = ""
    for k, v in tp_blocks:
        if "Running head:" in v:
            rh_txt = v.split("Running head:")[-1].replace("*", "").strip()
            break
    while mm_blocks and (
        mm_blocks[0][1].strip() == title_txt
        or mm_blocks[0][1].strip().lower().startswith("running head")
        or (rh_txt and mm_blocks[0][1].strip() == rh_txt)
    ):
        mm_blocks.pop(0)
    for i, (k, v) in enumerate(mm_blocks):
        if k == "p" and v.strip().startswith("**Background.**"):
            mm_blocks.insert(i, ("h1", "Abstract"))
            break
    body.extend(mm_blocks)

    # --- References（文件自带 `# References` 标题，勿重复添加）---
    rf = read(os.path.join(SUB, "manuscript", "03_References.md"))
    body.extend([b for b in md_blocks(rf) if _keep_en(b)])

    emit(doc, body)

    # 页码
    for sec in doc.sections:
        p = sec.footer.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        fld = OxmlElement("w:fldSimple")
        fld.set(qn("w:instr"), "PAGE")
        p._p.append(fld)

    out = out_path or os.path.join(WORD, "02_Main_Manuscript.docx")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    return _save(doc, out)


# ---------------------------------------------------------------- 表格
def set_cell(cell, text, bold=False, size=9, align=WD_ALIGN_PARAGRAPH.LEFT):
    cell.text = ""
    text = text.replace("`", "")
    p = cell.paragraphs[0]
    p.alignment = align
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE
    r = p.add_run(text)
    r.bold = bold
    r.font.size = Pt(size)


def add_csv_table(doc, path, size=9, max_rows=None):
    rows = list(csv.reader(io.open(path, encoding="utf-8-sig")))
    if max_rows:
        rows = rows[:max_rows]
    if not rows:
        return
    ncol = len(rows[0])
    t = doc.add_table(rows=len(rows), cols=ncol)
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for j, h in enumerate(rows[0]):
        set_cell(t.rows[0].cells[j], h, bold=True, size=size)
    for i, row in enumerate(rows[1:], start=1):
        for j in range(ncol):
            val = row[j] if j < len(row) else ""
            al = WD_ALIGN_PARAGRAPH.RIGHT if j > 0 and re.match(r"^[\d.,<>−\-×]+", val or "") else WD_ALIGN_PARAGRAPH.LEFT
            set_cell(t.rows[i].cells[j], val, size=size, align=al)
    # 表头重复
    tr = t.rows[0]._tr
    trPr = tr.get_or_add_trPr()
    el = OxmlElement("w:tblHeader")
    el.set(qn("w:val"), "true")
    trPr.append(el)


def caption_english(captions_text, tag):
    """抽取 `### Table Sxx.` 段的 English 表注正文（到 Definitions 前）。"""
    lines = captions_text.splitlines()
    start = None
    for i, l in enumerate(lines):
        if l.strip().startswith("### Table %s." % tag):
            start = i
            break
    if start is None:
        return None
    cap, on = [], False
    for l in lines[start + 1:]:
        s = l.strip()
        if s.startswith("### ") or s.startswith("**Definitions"):
            break
        if s.startswith("**English.**"):
            on = True
            cap.append(s[len("**English.**"):].strip())
            continue
        if s.startswith("**中文.**"):
            on = False
            continue
        if s.startswith("**Files"):
            continue
        if on and s:
            cap.append(s)
    return " ".join(cap).strip() or None


def table_title(captions_text, tag):
    for l in captions_text.splitlines():
        if l.strip().startswith("### Table %s." % tag):
            return l.strip()[4:].strip()
    return "Table %s" % tag


def build_tables():
    doc = new_doc()
    doc.styles["Normal"].font.size = Pt(10)
    cap = read(os.path.join(SUP, "CAPTIONS_figures_tables.md"))

    spec = [
        ("S13", [("Table1_baseline_manuscript.csv", None)], None),
        ("S14", [("Table2_hr_manuscript.csv", None)], None),
        ("S15", [("Table3_calibration_coefs_manuscript.csv", "Calibration coefficients"),
                 ("Table3_reporting_bias.csv", "Reporting-bias comparison")], None),
        ("S16", [("Table4_burden_manuscript.csv", None)], None),
    ]

    h = doc.add_paragraph()
    h.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = h.add_run("Tables S13\u2013S16")
    r.bold = True
    r.font.size = Pt(14)

    note = doc.add_paragraph()
    note.paragraph_format.space_after = Pt(12)
    add_runs(note, "The main text carries figures only (Fig 1\u20136); Tables S13\u2013S16 are supplementary tables "
                   "moved from the former main-text Tables 1\u20134. Values are reproduced verbatim from the "
                   "computational outputs listed under each table.", size=9)

    for tag, csvs, _ in spec:
        doc.add_page_break()
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(4)
        rr = p.add_run(table_title(cap, tag))
        rr.bold = True
        rr.font.size = Pt(11)

        ctext = caption_english(cap, tag)
        if ctext:
            cp = doc.add_paragraph()
            cp.paragraph_format.space_after = Pt(8)
            cp.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
            add_runs(cp, ctext, size=9)

        for k, (c, label) in enumerate(csvs):
            path = os.path.join(TAB, c)
            if not os.path.exists(path):
                continue
            if len(csvs) > 1:
                lab = doc.add_paragraph()
                lab.paragraph_format.space_before = Pt(8)
                lab.paragraph_format.space_after = Pt(4)
                rr2 = lab.add_run("(%s) %s" % ("abc"[k], label or c))
                rr2.bold = True
                rr2.font.size = Pt(9)
            add_csv_table(doc, path)
            doc.add_paragraph()

    out = os.path.join(WORD, "Tables_S13_S16.docx")
    return _save(doc, out)


def build_all_captions():
    """S1–S16 全表注（纯英文），作为补充材料的可编辑索引。"""
    doc = new_doc()
    doc.styles["Normal"].font.size = Pt(10)
    cap = read(os.path.join(SUP, "CAPTIONS_figures_tables.md"))

    h = doc.add_paragraph()
    h.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = h.add_run("Supplementary Tables S1\u2013S16: captions")
    r.bold = True
    r.font.size = Pt(14)

    order = ["S%d" % i for i in range(1, 17)]
    for tag in order:
        ctext = caption_english(cap, tag)
        title = table_title(cap, tag)
        p = doc.add_paragraph()
        p.paragraph_format.space_before = Pt(10)
        p.paragraph_format.space_after = Pt(3)
        rr = p.add_run(title)
        rr.bold = True
        rr.font.size = Pt(10)
        if ctext:
            cp = doc.add_paragraph()
            cp.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
            cp.paragraph_format.space_after = Pt(4)
            add_runs(cp, ctext, size=9)

    out = os.path.join(WORD, "Supplementary_Tables_S1_S16_captions.docx")
    return _save(doc, out)


# ---------------------------------------------------------------- S1–S12 数据表
# 映射依据：CAPTIONS_figures_tables.md 第 258–271 行的编号对应表
S1_S12_SPEC = [
    ("S1", "Pooled relative-risk curves from external cohorts (Burden of Proof)", [
        ("Table5_bop_pooled_RR.csv", "Pooled relative-risk curve"),
        ("Table5_bop_slopes.csv", "Fitted slopes"),
        ("Table5_bop_method_effect.csv", "Measurement-method effect"),
        ("Table5_bop_wear_site.csv", "Wear-site effect"),
        ("Table5_m1_vs_m2.csv", "Model 1 versus Model 2"),
        ("Table5_bop_fit_diagnostic.csv", "Fit diagnostics"),
        ("Table5_bop_sensitivity_curvature.csv", "Curvature sensitivity"),
    ]),
    ("S2", "Within-NHANES hip-versus-wrist site effect", [
        ("Table6_nhanes_hip_wrist_RR.csv", "Hip versus wrist relative risk"),
        ("Table6_pam_percentile_map.csv", "Percentile mapping across metrics"),
    ]),
    ("S3", "NHANES arms in the pooled curve (controlled sensitivity)", [
        ("Table7_bop_nhanes_pooled_curve.csv", "Pooled curve with NHANES arms"),
        ("Table7_bop_nhanes_paf_impact.csv", "Impact on PAF"),
        ("Table7_bop_nhanes_paf_impact_by_cause.csv", "Impact on PAF by cause"),
        ("Table7_bop_nhanes_site_sensitivity.csv", "Wear-site sensitivity"),
        ("Table7_bop_nhanes_weight_share.csv", "Weight share carried by NHANES arms"),
    ]),
    ("S4", "Hip wear-rule x wrist criterion grid, and the literature-side site decomposition", [
        ("Table8_site_ratio_matrix.csv", "Site-ratio matrix"),
        ("Table8_site_ratio_summary.csv", "Site-ratio summary"),
        ("Table8_hip_wear_rule_curves.csv", "Hip wear-rule curves"),
        ("Table8_wrist_criterion_curves.csv", "Wrist criterion curves"),
        ("Table8_metric_axis_check.csv", "Metric-axis check"),
        ("Table8_lit_site_compatibility.csv", "Literature site compatibility"),
        ("Table8_lit_site_contrast.csv", "Literature site contrast"),
        ("Table8_lit_site_leverage.csv", "Literature site leverage"),
        ("Table8_lit_site_metric_license.csv", "Metric licence by study"),
        ("Table8_lit_design_incompat.csv", "Design incompatibility"),
        ("Table8b_site_anchor_slopes.csv", "External-anchor slopes"),
        ("Table8b_site_anchor_totalPA.csv", "Total-activity anchor"),
        ("Table8b_site_anchor_vs_nhanes.csv", "Anchor versus NHANES"),
        ("Table8b_site_metric_compare.csv", "Metric-aligned comparison"),
    ]),
    ("S5", "Module 3 scenario ladder (formal grading table)", [
        ("Table9_m3_scenario_summary.csv", "Scenario summary"),
        ("Table4_m3_decomp.csv", "Decomposition by location and cause"),
    ]),
    ("S6", "Module 3 robustness (exposure CV grid and population weighting)", [
        ("Table10_m3_robustness.csv", None),
    ]),
    ("S7", "Country-scale homogeneity of the device metric", [
        ("Table10_m3_country_homogeneity.csv", None),
    ]),
    ("S8", "Hip intensity metrics (Peak-30, MVPA): quartiles and per-IQR contrasts", [
        ("Table11_pam_intensity_RR.csv", "Relative risks"),
        ("Table11_pam_intensity_per_IQR.csv", "Per-IQR contrasts"),
        ("Table11_pam_intensity_quartiles.csv", "Quartiles"),
    ]),
    ("S9", "Leave-one-study-out", [
        ("Table12_bop_loo_RR.csv", "Pooled relative risk"),
        ("Table12_m3_loo_paf.csv", "Recomputed PAF"),
    ]),
    ("S10", "E-values for unmeasured confounding", [
        ("Table13_evalues.csv", None),
    ]),
    ("S11", "SDI anchor table (205 locations)", [
        ("Table14_sdi_anchor.csv", None),
    ]),
    ("S12", "Per-country burden comparison (204 countries)", [
        ("TableS4_burden_bycountry_manuscript.csv", None),
    ]),
]


def add_csv_table_transposed(doc, path, size=8):
    """宽而短的表（列>20、行<=8）转置呈现：原表头成为首列，原数据行成为列。"""
    rows = list(csv.reader(io.open(path, encoding="utf-8-sig")))
    if not rows:
        return
    header, body = rows[0], rows[1:]
    ncol = len(body) + 1
    nrow = len(header)
    t = doc.add_table(rows=nrow + 1, cols=ncol)
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    set_cell(t.rows[0].cells[0], "Field", bold=True, size=size)
    for j, rlab in enumerate(body):
        set_cell(t.rows[0].cells[j + 1], "Row %d" % (j + 1), bold=True, size=size)
    for i, h in enumerate(header):
        set_cell(t.rows[i + 1].cells[0], h, bold=True, size=size)
        for j, rlab in enumerate(body):
            val = rlab[i] if i < len(rlab) else ""
            al = WD_ALIGN_PARAGRAPH.RIGHT if re.match(r"^[\d.,<>−\-×]+", val or "") else WD_ALIGN_PARAGRAPH.LEFT
            set_cell(t.rows[i + 1].cells[j + 1], val, size=size, align=al)
    tr = t.rows[0]._tr
    trPr = tr.get_or_add_trPr()
    el = OxmlElement("w:tblHeader")
    el.set(qn("w:val"), "true")
    trPr.append(el)


def _landscape(doc):
    from docx.enum.section import WD_ORIENT
    for sec in doc.sections:
        sec.orientation = WD_ORIENT.LANDSCAPE
        w, h = sec.page_width, sec.page_height
        if w < h:
            sec.page_width, sec.page_height = h, w
        sec.top_margin = sec.bottom_margin = Cm(1.8)
        sec.left_margin = sec.right_margin = Cm(1.5)


def build_tables_s1_s12():
    """S1–S12 补充数据表：横版，表注 + 数据表，字号随列数自适应。

    项目 CSV 保留了内部中文标签，投稿版必须英文化；无法安全英文化的表
    只出表注 + CSV 指向说明，并记入 SKIPPED_TABLES 供最终报警。
    """
    from _csv_en import load_rows_clean

    doc = new_doc()
    _landscape(doc)
    st = doc.styles["Normal"]
    st.font.size = Pt(9)
    st.paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE
    cap = read(os.path.join(SUP, "CAPTIONS_figures_tables.md"))

    clean_dir = os.path.join(WORD, "_clean")
    os.makedirs(clean_dir, exist_ok=True)
    SKIPPED_TABLES[:] = []

    h = doc.add_paragraph()
    h.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = h.add_run("Supplementary Tables S1\u2013S12: data tables")
    r.bold = True
    r.font.size = Pt(14)

    note = doc.add_paragraph()
    note.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    note.paragraph_format.space_after = Pt(10)
    add_runs(note, "Each table is preceded by its caption. Values are reproduced verbatim from the "
                   "computational outputs; machine-readable CSV files for every table are provided "
                   "separately in the submission package. The main text carries figures only "
                   "(Fig 1\u20136); former main-text Tables 1\u20134 are supplied as Tables S13\u2013S16.",
             size=9)

    for tag, fallback_title, csvs in S1_S12_SPEC:
        doc.add_page_break()
        title = table_title(cap, tag)
        if title.startswith("Table %s" % tag) and len(title) <= len("Table %s" % tag) + 2:
            title = "Table %s. %s" % (tag, fallback_title)
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(4)
        rr = p.add_run(title)
        rr.bold = True
        rr.font.size = Pt(11)

        ctext = caption_english(cap, tag)
        if ctext:
            cp = doc.add_paragraph()
            cp.paragraph_format.space_after = Pt(8)
            cp.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
            add_runs(cp, ctext, size=9)

        for k, (c, label) in enumerate(csvs):
            path = os.path.join(TAB, c)
            if not os.path.exists(path):
                warn = doc.add_paragraph()
                add_runs(warn, "(%s) file not found: %s" % ("abcdefghijklmn"[k], c), size=8)
                continue

            rows, why = load_rows_clean(path)
            if rows is None:
                SKIPPED_TABLES.append((c, why))
                miss = doc.add_paragraph()
                miss.paragraph_format.space_after = Pt(6)
                add_runs(miss, "(%s) %s — supplied as machine-readable CSV (see submission package); "
                               "not reproduced here because it carries internal working annotations."
                          % ("abcdefghijklmn"[k], label or c), size=8.5)
                continue

            if len(csvs) > 1:
                lab = doc.add_paragraph()
                lab.paragraph_format.space_before = Pt(8)
                lab.paragraph_format.space_after = Pt(3)
                rr2 = lab.add_run("(%s) %s" % ("abcdefghijklmn"[k], label or c))
                rr2.bold = True
                rr2.font.size = Pt(9)

            tmp = os.path.join(clean_dir, c)
            with io.open(tmp, "w", encoding="utf-8", newline="") as fh:
                csv.writer(fh).writerows(rows)

            ncol, nrow = len(rows[0]), len(rows) - 1
            if ncol > 20 and nrow <= 8:
                note2 = doc.add_paragraph()
                note2.paragraph_format.space_after = Pt(2)
                add_runs(note2, "This panel is transposed for legibility "
                                "(%d fields x %d rows)." % (nrow, ncol), size=7.5)
                add_csv_table_transposed(doc, tmp, size=8)
            else:
                size = 6.5 if ncol > 14 else (7.5 if ncol > 10 else 8.5)
                add_csv_table(doc, tmp, size=size)
            doc.add_paragraph()

    out = os.path.join(WORD, "Tables_S1_S12_data.docx")
    return _save(doc, out)



def fig_legend(captions_text, n):
    """抽取 `## Fig N.` 段的标题与 English 图注（到下一个 ## 或 ### 为止）。"""
    lines = captions_text.splitlines()
    pat = re.compile(r"^## Fig %d\.\s" % n)
    start = None
    for i, l in enumerate(lines):
        if pat.match(l.strip()):
            start = i
            break
    if start is None:
        return None, None
    title = lines[start].strip()[3:].strip()
    cap, on = [], False
    for l in lines[start + 1:]:
        s = l.strip()
        if s.startswith("## ") or s.startswith("### "):
            break
        if s.startswith("**English.**"):
            on = True
            cap.append(s[len("**English.**"):].strip())
            continue
        if s.startswith("**中文.**"):
            on = False
            continue
        if s.startswith("**Files"):
            continue
        if on and s:
            cap.append(s)
    return title, " ".join(cap).strip()


def build_figure_legends():
    """Fig 1-6 英文图注单独成篇，供投稿系统 Figure legends 项使用。"""
    doc = new_doc()
    st = doc.styles["Normal"]
    st.font.size = Pt(11)
    st.paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE
    cap = read(os.path.join(SUP, "CAPTIONS_figures_tables.md"))

    h = doc.add_paragraph()
    h.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = h.add_run("Figure legends")
    r.bold = True
    r.font.size = Pt(14)

    missing = []
    for n in range(1, 7):
        title, text = fig_legend(cap, n)
        if title is None:
            missing.append(n)
            continue
        p = doc.add_paragraph()
        p.paragraph_format.space_before = Pt(10)
        p.paragraph_format.space_after = Pt(3)
        rr = p.add_run(title)
        rr.bold = True
        rr.font.size = Pt(11)
        if text:
            cp = doc.add_paragraph()
            cp.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
            cp.paragraph_format.space_after = Pt(4)
            add_runs(cp, text, size=11)

    out = os.path.join(WORD, "Figure_Legends.docx")
    if missing:
        print("!! figure legends missing for Fig", missing)
    return _save(doc, out)


def build_md_docx(md_path, out_path, size=11, double=False, landscape=False):
    """通用：把一份投稿用 markdown（标题/段落/表格/列表）转成 docx。

    跳过 blockquote（内部批注），数字大小随版面设置；表格统一用小一号字。
    """
    doc = new_doc()
    st = doc.styles["Normal"]
    st.font.size = Pt(size)
    st.paragraph_format.line_spacing_rule = (
        WD_LINE_SPACING.DOUBLE if double else WD_LINE_SPACING.SINGLE)
    st.paragraph_format.space_after = Pt(4)
    if landscape:
        _landscape(doc)
    blocks = [b for b in md_blocks(read(md_path)) if b[0] != "quote"]
    emit(doc, blocks, size=size)
    tsize = Pt(max(7.5, size - 2))
    for t in doc.tables:
        for row in t.rows:
            for cell in row.cells:
                for p in cell.paragraphs:
                    for r in p.runs:
                        r.font.size = tsize
    return _save(doc, out_path)


if __name__ == "__main__":
    os.makedirs(WORD, exist_ok=True)
    a = build_main()
    b = build_tables()
    c = build_all_captions()
    d = build_tables_s1_s12()
    e = build_figure_legends()
    for p in (a, b, c, d, e):
        print("OK  %s  (%.1f KB)" % (p, os.path.getsize(p) / 1024.0))
    if SKIPPED_TABLES:
        print("\n仅以 CSV 提供（含内部中文标注，未进 Word）:")
        for n, why in SKIPPED_TABLES:
            print("   %-46s %s" % (n, why))
