# -*- coding: utf-8 -*-
"""
_csv_en.py — 投稿表英文化清洗层

项目输出的 CSV 保留了内部中文标签（情景名、单位说明、备注列）。这些不能直接
进入投稿 Word。本模块做三件事，且不静默丢弃信息：

1. 删除内部备注列（列名属于 DROP_COLS）
2. 对结构性枚举列（情景名 / 轴名 / 单位）套用固定英文映射
3. 清洗后仍含中文的表 —— 返回 None 并给出原因，由调用方报警并跳过

用法：
    from _csv_en import load_rows_clean
    rows, why = load_rows_clean(path)
    if rows is None: ...   # why 说明原因
"""
import csv
import io
import os
import re

CJK = re.compile(r"[\u4e00-\u9fff]")

# 内部备注列：不承载可投稿信息
DROP_COLS = {"note", "notes", "comment", "comments", "remark", "remarks"}

# 结构性枚举的固定英译（值集合封闭，翻译不改变科学含义）
LABEL_MAP = {
    # Table9 / Table4_m3_decomp —— Module 3 情景标签
    "主分析：绝对口径 TMREL + M1 + 原 SIGMA（= s1p 主结果）":
        "Main analysis: absolute TMREL + M1 + original SIGMA (= s1p main result)",
    "M2 | 保秩映射 + 绝对口径 TMREL":
        "M2 | rank-preserving mapping + absolute TMREL",
    "M2 | 保秩映射 + TMREL 第 85 百分位":
        "M2 | rank-preserving mapping + 85th-percentile TMREL",
    "GBD 口径对齐 A：RR 幅度对齐（s 自动求解；TMREL 保持绝对口径）":
        "GBD alignment A: RR amplitude aligned (s solved; absolute TMREL retained)",
    "GBD 口径对齐 B（完整）：TMREL 第 85 百分位 + RR 幅度对齐（预期 fold ≈ 1）":
        "GBD alignment B (full): 85th-percentile TMREL + RR amplitude aligned (expected fold ≈ 1)",
    "L1 | TMREL 移到暴露分布第 70 百分位":
        "L1 | TMREL moved to the 70th percentile of the exposure distribution",
    "L1 | TMREL 移到暴露分布第 85 百分位（= GBD 定义）":
        "L1 | TMREL moved to the 85th percentile (= GBD definition)",
    "L2 | SIGMA_MIMS 3335 → 1600（半衰减）":
        "L2 | SIGMA_MIMS 3335 → 1600 (half attenuation)",
    "L2 | SIGMA_MIMS 3335 → 800":
        "L2 | SIGMA_MIMS 3335 → 800",
    "L2 | SIGMA_MIMS 3335 → 100（≈取消抹平，避免退化点质量）":
        "L2 | SIGMA_MIMS 3335 → 100 (deconvolution effectively removed; degenerate point mass avoided)",
    "L3 | RR 超额幅度缩到 GBD 水平（s = 0.0954，首版固定系数）":
        "L3 | RR excess compressed to the GBD level (s = 0.0954, fixed coefficient)",
    "上界 | TMREL 第 85 百分位 + 取消卷积（fold 最高）":
        "Upper bound | 85th-percentile TMREL + deconvolution removed (highest fold)",
    # Table10_m3_robustness —— 稳健性轴与水平
    "CV 网格（MET 尺度，主分析=cell 级 S1′）":
        "CV grid (MET scale; main analysis = cell-level S1′)",
    "人口加权（A6）":
        "Population weighting (A6)",
    "S1′ 主分析（cell 级）":
        "S1′ main analysis (cell-level)",
    "关（年龄组等权）":
        "Off (age groups equally weighted)",
    "开（主分析）":
        "On (main analysis)",
    # Table8 —— 曲线单位
    "counts/day（体量型）":
        "counts/day (volume-type)",
    "counts/day（体量型，限该强度带）":
        "counts/day (volume-type, restricted to the intensity band)",
    "MIMS/day（体量型）":
        "MIMS/day (volume-type)",
    # Table8_metric_axis_check —— 指标轴
    "MVPA 体量 >=2020":
        "MVPA volume >=2020",
    "总量 counts（R0）":
        "Total counts (R0)",
    "轻强度体量 LPA 100-2020":
        "Light-intensity volume LPA 100-2020",
    "静坐体量 <100":
        "Sedentary volume <100",
    # Table8_metric_axis_check —— 列名
    "降幅_off80_vs_off30":
        "reduction_off80_vs_off30",
    "降幅_off80_vs_off30(%)":
        "reduction_off80_vs_off30_pct",
    # Table8b_site_metric_compare —— 腕式来源标签
    "Ko2025 锚点（UKB；offset 与 EK19 完全对齐）":
        "Ko2025 anchor (UKB; offsets fully aligned with EK19)",
    "Ko2025 + Inan-Eroglu2024 合并（旁证；offset 网格不同）":
        "Ko2025 + Inan-Eroglu2024 combined (corroborative; offset grids differ)",
    "Sun2025 池内（UKB）":
        "Sun2025 in-pool (UKB)",
    "（参照指标）":
        "(reference metric)",
    "Ko2025 + InanEroglu2024（旁证）":
        "Ko2025 + Inan-Eroglu2024 (corroborative)",
    # Table3_sd_mean_age_map
    "GBD 85+ 组截断到 NHANES 上限组(80+)":
        "GBD 85+ group truncated to the NHANES upper band (80+)",
}


def load_rows_clean(path):
    """返回 (rows, reason)。rows 为 None 表示该表无法安全英文化。"""
    rows = list(csv.reader(io.open(path, encoding="utf-8-sig")))
    if not rows:
        return None, "empty file"
    header, body = rows[0], rows[1:]

    keep = [j for j, h in enumerate(header) if h.strip().lower() not in DROP_COLS]
    dropped = [header[j] for j in range(len(header)) if j not in keep]
    header = [header[j] for j in keep]
    body = [[r[j] if j < len(r) else "" for j in keep] for r in body]

    # 表头本身也可能带中文（列名），同样必须过映射
    residual = set()
    for h in header:
        if h in LABEL_MAP:
            continue
        if CJK.search(h):
            residual.add(h[:60])
    if residual:
        return None, "unmapped Chinese column name(s): %r" % sorted(residual)
    header = [LABEL_MAP.get(h, h) for h in header]

    residual = set()
    for r in body:
        for c in r:
            if c in LABEL_MAP:
                continue
            if CJK.search(c):
                residual.add(c[:60])
    if residual:
        return None, "unmapped Chinese in %d cell(s), e.g. %r" % (len(residual), sorted(residual)[0])

    body = [[LABEL_MAP.get(c, c) for c in r] for r in body]
    return ([header] + body), ("dropped internal column(s): %s" % ", ".join(dropped) if dropped else "")
