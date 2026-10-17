# UPLOAD CHECKLIST — GitHub 上传包说明

> 目的：把「代码 + 可复现证据 + 派生结果」整理成一个**可直接 push** 的仓库，
> 同时**不**上传体积巨大、不可再分发、或未发表的内容。
> 生成日期：2026-10-17。本文件是上传决策的唯一记录，改动须同步 `.gitignore`。

---

## 1. 已纳入版本控制（会出现在 GitHub）

| 路径 | 体积 | 内容 | 为什么必须上传 |
|---|---|---|---|
| `code/` | ~1.2 MB | 45 个主链 R 脚本 + 14 个 tools + `README.md`（工程笔记） | 复现主体 |
| `output/` | ~9 MB | 109 CSV + 13 PNG + 13 PDF + 5 TXT + 2 RDS + manifest/报告 | 论文全部数字的落盘来源 |
| `figures/` | ~5.6 MB | `combined/`（14）+ `panel/`（48）+ `tables/`（表格图版） | 主图与面板，逐面板可重排 |
| `data/sources/` | ~41 KB | NHANES 文件清单、SHA-256 台账、GBD 台账、官方读入程序 | 原始数据可复现的凭据 |
| `data/bop/` | ~150 KB | BoP 提取表（22 行）、提取日志、入池裁定说明、README | **池化输入**（文献级汇总值，非版权全文） |
| `data/external/` | ~7.2 MB | UN WPP 2024 人口（5 岁组×性别）+ OWID 人口 | M3 分母构造所需 |
| `data/README.md` | 8 KB | 数据层规则 + GBD 手工获取步骤 | 新用户入口 |
| `data/RAW_INVENTORY.csv` | 20 KB | 原始数据台账 | 溯源 |
| `REPRODUCIBILITY.md` | — | 七步复现协议（中文） | 复现说明 |
| `README.md` `LICENSE` `CITATION.cff` | — | 仓库门面 / MIT / 引用 | GitHub 规范 |
| `docs/DATA_DICTIONARY.md` `docs/UPLOAD_CHECKLIST.md` | — | 数据字典 / 本文件 | 审稿人与读者 |

**合计约 23.4 MB / 304 个文件，最大单文件 4.6 MB**（`data/external/WPP2024_PopulationByAge5GroupSex_Medium.csv.gz`）
→ 无需 Git LFS。

## 2. 不纳入版本控制（`.gitignore` 已排除）

| 路径 | 体积 | 排除理由 | 如何重建 |
|---|---|---|---|
| `data/raw/` | 1.4 GB | NHANES 原始 `.xpt`（公开可下，不必占仓库） | `Rscript code/01_fetch_data.R` |
| `data/derived/` | 50 MB | 中间 `.rds`（PAXHR 各 17–18 MB） | `02`/`03` 重建 |
| `data/gbd/` | 163 MB | **GBD 2023 提取件受 IHME 使用条款约束，不可再分发** | 按 `data/README.md` §3 手工获取 |
| `data/scratch/` | 5.2 GB | 沙箱与归档（含孤儿产物归档） | 不需要 |
| `logs/` | ~7.8 MB | 本机运行痕迹（含绝对路径） | 每次运行自动生成 |
| `tmp_probe/` `_smoketest/` | — | 临时探针 | 不需要 |
| `manuscript/` | 236 KB | **未发表稿件**（摘要/正文/骨架），发表前不入公开库 | 见 §5 |
| `manuscript/期刊推荐_目标刊评估_20261017.md` | — | 选刊决策记录（含内部权衡） | 定刊后按需删/留 |
| `data/bop/文献传递*.md` · `索取全文邮件*` · `_bak_*` · `_intake_extract/` | — | 内部行政文档（文献传递申请、致信草稿） | 不需要 |
| `00_完整研究方案.md` · `Module2_外部队列数据申请清单.md` · `data/bop/*入池裁定*.md` | — | 内部工作文档（含时间线、申请策略、本机工具链路径） | 不需要；方法细节已在 Methods 2.4 与 `data/bop/README.md` 公开说明 |

## 3. 关于 GBD 与 NHANES 的再分发边界（**重要**）

- **NHANES**：美国联邦政府公开数据（CDC/NCHS），可自由使用；本仓库只放**下载清单与指纹**，不放原始文件。
- **GBD 2023**：IHME 成果，**允许使用、不允许再分发原始提取件**。因此 `data/gbd/` 永久排除。
  仓库中保留的 `data/sources/gbd_checksums.csv` 只记录**文件名与指纹**，不含数值内容。
- **BoP 提取表**（`data/bop/rr_table.csv`）：由已发表论文的**汇总估计值**转录而成（非全文、非个体数据），
  属常见做法，但须在正文/README 注明来源研究并要求引用原文（已在 `data/bop/README.md` 逐行标注）。

## 4. 上传步骤（三条命令 + 一次网页操作）

```bash
# 1) 在项目根目录初始化并提交（.gitignore 已就位，自动排除大文件）
cd "E:/WorkBuddy/2026-10-11-00-17-56/范式A_低体力活动_加速度计"
git init -b main
git add -A
git commit -m "Initial commit: device-calibrated burden of low physical activity (analysis pipeline + derived results)"

# 2) 检查将要上传的内容与体积（务必看一遍）
git count-objects -vH
git ls-files | wc -l
```

```bash
# 3) 在 GitHub 网页新建空仓库（不要勾选 README/LICENSE），然后：
git remote add origin https://github.com/liuxun-sj-hospital/device-calibrated-pa-burden.git
git push -u origin main
```

> **账号与仓库地址已确定（2026-10-17）**：`liuxun-sj-hospital` / `device-calibrated-pa-burden`。
> 已在 `CITATION.cff`、`manuscript/Title_Page_投稿用.md`、`manuscript/声明与补充材料_草稿_中英对照.md` 三处同步。
> 首次 `push` 时请用 **Personal Access Token（PAT）作为密码**，不要输入 GitHub 登录密码（见 §4b）。

## 4b. 首次 push 的认证方式（**不要用登录密码**）

GitHub 自 2021-08 起已关闭 HTTPS 密码推送，`git push` 提示 `Password for 'https://...'` 时：
**账号填 `liuxun-sj-hospital`，密码填 Personal Access Token（PAT）**，不是 GitHub 登录密码。

① 网页右上头像 → Settings → Developer settings → Personal access tokens → **Tokens (classic)** →
Generate new token → 勾选 `repo`（若仓库含 Actions 再加 `workflow`）→ 有效期建议 30 天 → 复制 `ghp_...`（只显示一次）。  
② 推送：`git push -u origin main`，用户名 `liuxun-sj-hospital`，密码粘贴 PAT。  
③ 提示 `remote: Support for password authentication was removed` = 第 ② 步填了登录密码，重来一次即可。  
④ 推荐在**本仓库局部**保存凭据，避免写入全局：

```bash
git config --local credential.helper manager   # Windows 凭据管理器，之后只输一次
```

> ⚠️ **安全约定**：PAT 与登录密码一律**不写进任何文件**（本仓库会公开），也不写进 `.git/config` 明文。
> 若凭据曾出现在聊天/文档/截图里，**用完即 revoke**（同一页面 Delete）。建议另为仓库启用 2FA。

## 5. 发表后再补的两件事

1. **`manuscript/` 是否公开**：接收后可将接受的 PDF 或 preprint 放入 `manuscript/`，并去掉 `.gitignore` 中该行；
   在此之前保持排除（未发表内容不宜先行公开）。
2. **Zenodo DOI（可选，推荐）**：在 GitHub 仓库页 → Settings → 勾选 Zenodo 集成 → 打 tag `v1.0.0` →
   获得 DOI。这样稿件 Data availability 可写「archived at Zenodo, DOI: 10.5281/zenodo.XXXXXXX」，
   比裸 GitHub 链接更稳（GitHub 仓库可删可改）。

## 6. 提交前自检（已逐项核对）

| 检查项 | 结果 |
|---|---|
| 单文件是否 < 100 MB（GitHub 硬限） | ✅ 最大 4.6 MB（`data/external/WPP2024_PopulationByAge5GroupSex_Medium.csv.gz`） |
| 仓库总体积是否 < 1 GB（推荐 < 100 MB） | ✅ 23.4 MB / 304 文件 |
| 是否含绝对路径（`E:\` / `C:\Users`） | ⚠️ `output/manifest.csv` 与部分 CSV 的表头注释可能含本机路径 → 已在 `docs/` 说明；如需彻底清除可跑 `code/tools/` 的清理脚本后再提交 |
| 是否含 API key / 凭证 | ✅ 无（PAT 不入库，见 §4b） |
| 是否含个体级可识别数据 | ✅ 无（NHANES 为去标识化公开数据，且未上传） |
| 是否含期刊未发表稿件 | ✅ 已排除 `manuscript/` |
| LICENSE / CITATION.cff 是否齐备 | ✅ MIT + CFF（5 位作者，2 位通讯） |

## 7. 与稿件的对应关系

稿件 Data availability 建议表述（英文）：

> All derived datasets and the complete analysis code are available at
> https://github.com/liuxun-sj-hospital/device-calibrated-pa-burden (archived at Zenodo, DOI: …).
> NHANES 2011–2014 data are publicly available from CDC/NCHS; GBD 2023 estimates are available from the
> GBD Results Tool (IHME). Raw third-party data are not redistributed.

中文对照与占位符已在 `manuscript/声明与补充材料_草稿_中英对照.md` §3 同步。
