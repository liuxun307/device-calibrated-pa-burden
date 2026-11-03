# GitHub 上传指南（device-calibrated-pa-burden）

> **目标**：把「分析代码 + 派生结果 + 可复现证据」推送到公开仓库，使稿件 Data availability 的承诺成立。
> **适用**：Windows 10/11 + Git for Windows（本机 `git 2.55.0`），仓库已初始化并有 5 个本地 commit。
> **日期**：2026-11-01。本文件与 `.gitignore`、`docs/UPLOAD_CHECKLIST.md` 三者必须一致。

---

## 0. 先回答两个问题

### 0.1 上传的是哪个文件夹？

**上传整个项目根目录**：

```
E:/WorkBuddy/2026-10-11-00-17-56/范式A_低体力活动_加速度计/
```

但**不是所有文件都会上去**。`.gitignore` 决定实际内容，最终只有约 330 个文件、约 23 MB 进入仓库。

### 0.2 上传哪些、不上传哪些

| 上传（进 GitHub） | 内容 | 体积 |
|---|---|---|
| `code/` | 主链 R 脚本 00–98 + `tools/`（含建包脚本）+ 工程笔记 | ~1.3 MB |
| `output/` | 全部结果 CSV、PNG/PDF 图、`manifest.csv`、`REPRODUCIBILITY_REPORT.txt` | ~8.9 MB |
| `figures/` | 主图与逐面板 PDF/PNG（可手动重组） | ~6.7 MB |
| `data/sources/` `data/bop/` `data/external/` | 下载清单 + SHA-256 台账 + 池化输入 + 人口分母 | ~7.3 MB |
| `docs/` | `DATA_DICTIONARY.md`、`UPLOAD_CHECKLIST.md`、本文件 | ~30 KB |
| 根目录 | `README.md` `LICENSE` `CITATION.cff` `REPRODUCIBILITY.md` `.gitignore` | ~25 KB |

| **不上传**（已被 `.gitignore` 排除） | 原因 |
|---|---|
| `manuscript/` `submission_eClinMed/` `投稿包_eClinMed_*/` | **未发表稿件**。公开即等于预印本，违反期刊首发政策，且会破坏双盲/单盲审稿 |
| `data/raw/` `data/derived/` `data/scratch/` | 可由 `01_fetch_data.R` 与 02/03 重建，体积 1.4 GB / 50 MB / 5.2 GB |
| `data/gbd/` | **IHME 使用条款禁止再分发**原始提取件；只留 `gbd_checksums.csv`（文件名+指纹） |
| `logs/` | 本机绝对路径等运行痕迹 |
| `00_完整研究方案.md`、选刊评估、文献传递邮件等 | 内部工作文档 |

> **红线**：`投稿包_eClinMed_2026-11-01/` 一旦被 `git add -A` 带上去，等于把整篇未发表稿件公开。本仓库已用 `投稿包_*/` 规则硬性排除，**不要删除这条规则**。

---

## 1. 准备 PAT（Personal Access Token）

GitHub 自 2021-08 起禁用密码推送，必须用 PAT。

1. 浏览器登录 GitHub → 右上头像 → **Settings**
2. 左栏最下 **Developer settings** → **Personal access tokens** → **Tokens (classic)**
3. **Generate new token (classic)**
   - Note：`local-push-2026-11`
   - Expiration：30 days（够用；到期再生成）
   - Scopes：勾 **`repo`**（整块），其余不勾
4. **Generate token** → 复制 `ghp_xxxxxxxx`（**只显示一次**，先存到密码管理器）

> 若仓库属于组织且开了 SSO，还需点 token 旁的 **Configure SSO** → Authorize。

---

## 2. 配置网络（中国网络环境必读）

先测一下本机能不能连上 GitHub：

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://github.com
```

- 返回 `200` / `301` → 直连可用，跳到第 3 步。
- 返回 `000`、超时、`Failed to connect` → 需要代理或加速器。

**若本机有代理**（Clash / V2Ray 等，假设本地端口 7890）：

```bash
# 只对本次仓库生效（推荐，不污染全局配置）
git config http.proxy  http://127.0.0.1:7890
git config https.proxy http://127.0.0.1:7890

# 验证
git ls-remote https://github.com/liuxun307/device-calibrated-pa-burden.git
```

**若用 SSH 而不是 HTTPS**（可选，免去每次输 PAT）：

```bash
ssh-keygen -t ed25519 -C "liuxun@sj-hospital.org"     # 一路回车
cat ~/.ssh/id_ed25519.pub                              # 复制内容
# GitHub → Settings → SSH and GPG keys → New SSH key → 粘贴
ssh -T git@github.com                                  # 看到 "Hi liuxun307!" 即成功
git remote set-url origin git@github.com:liuxun307/device-calibrated-pa-burden.git
```

> 国内 SSH 的 22 端口常被拦。若 `ssh -T` 卡住，改用 HTTPS + PAT，或配置 `~/.ssh/config` 走 443 端口：
> ```
> Host github.com
>   Hostname ssh.github.com
>   Port 443
>   User git
> ```

---

## 3. 提交前自检（3 条命令，务必看输出）

```bash
cd "E:/WorkBuddy/2026-10-11-00-17-56/范式A_低体力活动_加速度计"

# ① 现在有哪些改动待提交
git status --short

# ② 确认投稿包与稿件被正确忽略（应当有输出，说明被忽略）
git check-ignore -v "投稿包_eClinMed_2026-11-01/01_Main_Manuscript.docx"
git check-ignore -v manuscript/Abstract_结构化_中英对照.md

# ③ 确认没有 >50 MB 的大文件混进来（应当无输出）
git ls-files -z | xargs -0 -I{} du -k "{}" 2>/dev/null | awk '$1>51200'
```

---

## 4. 提交并推送

```bash
# 4.1 暂存全部（.gitignore 会自动挡掉稿件与大文件）
git add -A

# 4.2 再确认一次将提交什么、总体积多少
git status --short | head -30
git count-objects -vH

# 4.3 提交
git commit -m "Release v1.0.0: submission-ready pipeline, abstract trimmed to 249 words, package build scripts"

# 4.4 推送（首次会提示输入用户名与密码）
git push -u origin main
#    Username: liuxun307
#    Password: 粘贴 PAT（ghp_...，不显示字符是正常的）
```

**如果提示 `remote: Repository not found`**：

- 仓库还没在 GitHub 网页上创建 → 先去 New repository，名字必须是
  `device-calibrated-pa-burden`，**不要**勾选 Add README / .gitignore / license（会与本地冲突）。
- 或 PAT 没有 `repo` 权限 / 不属于该账号。

**如果提示 `Updates were rejected`**：远端已有提交（比如网页初始化过）。

```bash
git pull --rebase origin main    # 把远端提交接到本地之后
git push -u origin main
```

---

## 5. 推送后验证（5 项）

| # | 检查 | 期望 |
|---|---|---|
| 1 | 网页仓库首页 | 显示 README 渲染、许可证 MIT、约 330 个文件 |
| 2 | 网页 `code/` 目录 | 能看到 `00_run_all.R`、`98_verify_reproducibility.R`、`tools/` |
| 3 | 网页 `output/REPRODUCIBILITY_REPORT.txt` | 内容为 PASS，0 FAIL |
| 4 | 网页搜索 `投稿包` / `manuscript` | **搜不到任何结果**（确认稿件没被公开） |
| 5 | 本地 `git log --oneline -3` | 最新一条是 v1.0.0 提交 |

命令行版：

```bash
git log --oneline -3
git ls-files | wc -l          # 约 330
git ls-files | grep -c "投稿包\|^manuscript/"   # 必须是 0
```

---

## 6. 打版本标签 + Zenodo DOI（Data availability 需要）

稿件里写的是「a permanent archive with a DOI will be deposited in Zenodo upon acceptance」，所以**投稿阶段不必**先有 DOI。若想现在就拿到 DOI（更稳）：

1. 用 GitHub 账号登录 <https://zenodo.org>（Sign in with GitHub）
2. 右上头像 → **Settings** → **GitHub** → 找到本仓库 → 开关拨到 **ON**
3. 回到本地打标签并推送：

```bash
git tag -a v1.0.0 -m "Submission version 1.0.0 (eClinicalMedicine)"
git push origin v1.0.0
```

4. Zenodo 会自动抓取该 release，几分钟后在该仓库的 Zenodo 页面出现 **DOI**（形如 `10.5281/zenodo.xxxxxxx`）
5. 拿到 DOI 后，若稿件仍在校稿阶段，可把 Data availability 的措辞改为
   `archived at Zenodo (DOI: 10.5281/zenodo.xxxxxxx)`；**若已投稿，不必改**，接收后再补。

---

## 7. 常见错误对照表

| 报错 | 原因 | 处理 |
|---|---|---|
| `Authentication failed` | 用了登录密码 | 改用 PAT |
| `Support for password authentication was removed` | 同上 | 同上 |
| `Repository not found` | 仓库未建 / 名字不符 / PAT 无 `repo` | 核对拼写、重建 token |
| `Failed to connect to github.com port 443` | 网络被墙 | 配代理或 SSH 443 |
| `fatal: refusing to merge unrelated histories` | 远端有独立提交（网页建库时勾了 README） | `git pull --rebase origin main --allow-unrelated-histories` |
| `error: File ... is 120 MB; this exceeds GitHub's file size limit` | 大文件混入 | 检查 `.gitignore` 是否被删；`git rm --cached <file>` 后重提交 |
| `Permission denied (publickey)` | SSH key 未加到账号 | 重做第 2 节 SSH 部分 |

---

## 8. 上传后的维护约定

- 任何改动 `output/` 或 `README.md` 的操作，必须**先** `Rscript code/06_manifest.R`，**再** `Rscript code/98_verify_reproducibility.R`，确认 0 FAIL 后才 commit。
- 稿件文本（`manuscript/`）永远不进仓库，直到论文正式接收；接收后可另开 `paper/` 目录放排版稿。
- 审稿意见涉及数字改动时，同步更新：`output/` → manifest → 98 → 提交信息里写明「reproducibility re-verified」。

---

## 9. 需要你本人执行的三件事

1. 生成 PAT（第 1 节），有效期 30 天；
2. 若直连不通，配好代理或 SSH（第 2 节）；
3. 执行第 4 节的 `git add -A` → `commit` → `push`，把 `git push` 的完整输出发我，我核对是否全部成功。

> 我这边运行环境对外网有沙箱限制（`curl https://github.com` 返回空、代理 502），**无法代你 push**；
> 但仓库内容、忽略规则、提交信息都已经准备好，你复制命令即可。
