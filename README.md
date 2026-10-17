# Device-calibrated burden of low physical activity

**Recomputation of the GBD 2023 attributable burden of low physical activity using device-measured
(accelerometer) exposure instead of self-reported exposure.**

This repository contains the complete analysis pipeline, the derived result tables, and the figure outputs
for the manuscript:

> Zhang Z, Liu H, Zhao Z, Zhao Y, Liu X. *Device-calibrated physical activity and global attributable burden:
> a three-module recomputation of GBD 2023.* (manuscript, 2026)

---

## 1. What the pipeline does

A three-module chain links device-measured activity to country-level attributable burden.

| Module | Input | Method | Output |
|---|---|---|---|
| **M1** Device-scale dose–response and calibration | NHANES 2011–2014 (wrist accelerometry + mortality linkage) | Survey-weighted Cox models with restricted cubic splines, anchored at the device-equivalent absolute threshold for minimum recommended activity (13,222 MIMS/day); monotone natural-spline calibration of the GBD exposure distribution onto the device scale | Device-scale RR curve; calibration equation; reporting-bias quantification |
| **M2** Cross-cohort pooling | 5 device-based cohort datasets (21 exposure contrasts) | Multi-level Bayesian meta-regression with measurement-method and metric-definition covariates | Pooled device-scale RR curve, retained wear-site and metric axis |
| **M3** Burden recomputation | Calibrated device-scale exposure distribution + pooled RR curve + GBD 2023 cause-specific deaths/DALYs | Counterfactual PAF, deterministic posterior enumeration; 8 causes × 204 countries × 1990/2022 | Recomputed burden; decomposition of the gap versus GBD |

**Headline result.** For 2022 the recomputed global PAF is **0.174** (3,775,099 attributable deaths) against
GBD 2023's **0.030** (660,032 deaths) — a **5.7-fold** difference that holds in all 204 countries examined
(median 6.05; none ≤ 1). Two nameable definitional choices — relative-risk amplitude and the counterfactual
threshold — explain the gap to within a residual multiplier of **×1.007**.

---

## 2. Repository layout

```
.
├── code/                     # full pipeline (R), single entry point 00_run_all.R
│   ├── 00_setup.R            # environment, constants, paths (seed 20261011)
│   ├── 01_fetch_data.R       # NHANES download + SHA-256 pinning
│   ├── 02–03                 # accelerometry processing, exposure merge, survival
│   ├── 04*                   # dose–response, pooling, site/metric analyses
│   ├── 05–07                 # calibration, PAF, burden, waterfall decomposition
│   ├── 08a–08f               # figures 1–6
│   ├── 09_tables.R           # manuscript tables
│   ├── 10_captions.R         # captions + internal consistency self-checks
│   ├── 98_verify_reproducibility.R   # five-layer verification
│   ├── tools/                # lint + audit helpers
│   └── README.md             # detailed engineering notes (Chinese)
├── data/
│   ├── sources/              # NHANES file manifest, SHA-256 ledgers, official read-in program
│   ├── bop/                  # Burden-of-Proof extraction table (pooled input) + extraction log
│   ├── external/             # UN WPP 2024 population + OWID population (age 5-group)
│   └── README.md             # data-layer rules and manual acquisition steps
├── figures/                  # panel and combined figure files (PDF + PNG)
├── output/                   # result tables (CSV), manifest, reproducibility report
├── docs/
│   ├── DATA_DICTIONARY.md    # every released CSV, column by column
│   └── UPLOAD_CHECKLIST.md   # what is (and is not) in this repo, and why
├── REPRODUCIBILITY.md        # the reproduction protocol (Chinese, step by step)
└── LICENSE                   # MIT (code); see §6 for data
```

---

## 3. Quick start

Requirements: **R 4.5.2** (or ≥ 4.3), ~2 GB free disk for NHANES raw files, internet access for step 1.
Package versions are pinned by `00_setup.R` and recorded in `logs/pkg-versions_latest.csv`.

```bash
# 0) environment self-check (read-only, prints a report)
Rscript code/00_setup.R

# 1) fetch NHANES 2011–2014 files and pin SHA-256 (first run ~5–10 min, ~130 MB)
Rscript code/01_fetch_data.R

# 2) full pipeline (00 → 98), writes logs/<RUN_ID>/step_*.log
Rscript code/00_run_all.R

# 3) read the verdict
cat output/REPRODUCIBILITY_REPORT.txt
```

Expected end state: `PASS` for environment, raw data, intermediate data and deliverables, with zero `FAIL`.
A complete cold run takes about **65 minutes** on a 8-core laptop (the Bayesian pooling step dominates).

**GBD 2023 inputs are not redistributed** (see `docs/UPLOAD_CHECKLIST.md` §3). They must be obtained from the
public GBD Results Tool following the query specification in `data/README.md` §3; `code/00_setup.R` verifies
their presence and shape before any downstream step runs.

---

## 4. Mapping results to the manuscript

| Manuscript item | File in `output/` |
|---|---|
| Table 1 (baseline) | `Table1_baseline_manuscript.csv` |
| Table 2 (hazard ratios) | `Table2_hr_manuscript.csv` |
| Table 3 (calibration + reporting bias) | `Table3_calibration.txt`, `Table3_reporting_bias.csv` |
| Table 4 (recomputed vs GBD) | `Table4_burden_manuscript.csv` |
| Table S1–S12 | `Table5_*` … `Table14_*`, `TableS4_*` (mapping in `docs/DATA_DICTIONARY.md`) |
| Fig 1 | `figures/combined/Fig1.pdf`, `figures/panel/Fig1_study_design.*` |
| Fig 2 | `Fig2a_flow_numbers.csv`, `Fig2b_exposure_summary.csv`, `Fig2c_crosstab_weighted.csv`; panels `Fig2a_screening_flow`, `Fig2b1_reported_density`, `Fig2b2_device_density`, `Fig2c_reported_vs_device_crosstab` |
| Fig 3 | `Fig3_reference_points.csv`; panels `Fig3a–f` (6 panels) |
| Fig 4 | `QC_08d_calibration_check.csv`; panels `Fig4a–c` |
| Fig 5 | `Table4_m3_decomp.csv`, `M3_BYCOUNTRY_*`, `Fig5d_waterfall_data.csv`; combined `Fig5_a_b_c_d`, `Fig5_a_d` |
| Fig 6 | `Table9_m3_scenario_summary.csv`, `Table10_m3_robustness.csv`, `Table12_m3_loo_paf.csv`, `Table13_evalues.csv`; panels `Fig6a–c` |
| Extended Data / reproof | `manifest.csv`, `REPRODUCIBILITY_REPORT.txt`, `QC_98_checks.csv` |

---

## 5. Reproducibility contract

Three hard standards, each with a machine-checkable artefact:

1. **Raw data reproducible** — `data/sources/nhanes_files.csv` + `checksums.csv`; `01_fetch_data.R` re-downloads
   and re-verifies every file.
2. **Code reproducible** — single entry point, fixed seed (20261011), R/package versions recorded per run.
3. **Process reproducible** — one log per step, a content manifest with SHA-256 for every artefact
   (`output/manifest.csv`), and a five-layer verification report (`output/REPRODUCIBILITY_REPORT.txt`):
   environment → raw data → intermediate data → deliverables → cross-run fingerprints.

Module 3 point estimates are **fully deterministic** (enumeration over posterior draws; no Monte Carlo
resampling), so repeated runs reproduce the same PAF to machine precision. PDF outputs embed a creation
timestamp; their content identity is established by the corresponding PNG (byte-identical across runs).

---

## 6. License and data terms

- **Code** (`code/`, `docs/`, pipeline scripts): **MIT** — see `LICENSE`.
- **Derived tables and figures** (`output/`, `figures/`): **CC BY 4.0**, attribution required.
- **Third-party data are not redistributed.** NHANES is public-domain US government data (CDC/NCHS);
  GBD 2023 estimates are subject to IHME's terms of use and must be downloaded by the user. The Burden-of-Proof
  extraction table in `data/bop/` contains study-level summary estimates transcribed from published papers
  (citation of the source studies is required; see `data/bop/README.md`).

---

## 7. Citation

`CITATION.cff` is provided. Until the manuscript is published, please cite the repository:

```
Zhang Z, Liu H, Zhao Z, Zhao Y, Liu X. Device-calibrated burden of low physical activity
(analysis pipeline and derived results). GitHub repository, 2026.
https://github.com/liuxun-sj-hospital/device-calibrated-pa-burden
```

## 8. Contact

Xun Liu — liuxun@sj-hospital.org · Yang Zhao — treezy@163.com
Department of General Surgery / Department of Emergency Medicine, Shengjing Hospital of China Medical University,
Shenyang, China
