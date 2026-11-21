# 把本地项目发布到 GitHub

> **一份就够。** 不用同时翻十篇文档、十几个仓库。
>
> 这份手册把三样东西合在了一起：
> ① 从本地到 Release 的完整流程（社区里少见，多数教程到 `push` 就结束了）
> ② 天天要用的命令速查（撤销、改写、找回、冲突）
> ③ 出事时的排错手册（"我干了 XX，怎么救"）
>
> 每条命令都跑过，每个坑都真踩过。

---

## 怎么用这份手册

**赶时间，只想传上去** → [§0 五分钟](#0-五分钟快速通道)

**第一次发布，不想出事** → 从 [§1](#1-准备工作) 顺序读到 [§6](#6-验收清单)，重点是 [§2.4 隐私扫描](#24-隐私扫描)

**已经会了，只想要命令** → [§9 命令速查](#9-命令速查)

**搞砸了** → [§8 急诊室](#8-急诊室出事了怎么办) 或 [§10 排错手册](#10-排错手册我干了xx怎么救)

**想知道这些内容从哪来** → [§13 来源与致谢](#13-来源与致谢)

---

## 目录

- [0. 五分钟快速通道](#0-五分钟快速通道)
- [1. 准备工作](#1-准备工作)
- [2. 发布前：把东西整理干净](#2-发布前把东西整理干净)
- [3. 建仓与推送](#3-建仓与推送)
- [4. 打 Release](#4-打-release)
- [5. 持续集成（CI）](#5-持续集成ci)
- [6. 验收清单](#6-验收清单)
- [7. 十二个坑](#7-十二个坑)
- [8. 急诊室：出事了怎么办](#8-急诊室出事了怎么办)
- [9. 命令速查](#9-命令速查)
- [10. 排错手册：我干了XX，怎么救](#10-排错手册我干了xx怎么救)
- [11. 许可证怎么选](#11-许可证怎么选)
- [12. 常见问题](#12-常见问题)
- [13. 来源与致谢](#13-来源与致谢)
- [附录 A：发布脚本](#附录-a发布脚本)
- [附录 B：提交信息怎么写](#附录-b提交信息怎么写)

---

## 0. 五分钟快速通道

只想赶紧传上去，照这个顺序做，细节回头再补：

```bash
cd ~/projects/my-app

# 1. 先看有什么不该传
ls -la
find . -type f -size +5M -not -path './.git/*'

# 2. 写忽略清单（四类：运行数据、构建产物、密钥、个人文档）
curl -s https://raw.githubusercontent.com/github/gitignore/main/Python.gitignore > .gitignore
printf '\n.venv/\nout/\n*.log\n.env\n' >> .gitignore

# 3. 建仓并推送
git init -b main
git add -A
git status --short          # ← 停一下，看清要传什么
git commit -m "初始提交"
gh repo create my-app --source . --public --push
```

⚠️ 第 3 步的 `git status --short` **别跳过**。这一步花 10 秒，能省掉后面洗历史的几小时。

**公开仓库撤不回来**——被搜索引擎、镜像站、爬虫抓到之后，删库也没用。

---

## 1. 准备工作

### 1.1 装什么

| 工具 | 用途 | 安装 |
|---|---|---|
| **git** | 版本控制本身 | [git-scm.com](https://git-scm.com/downloads) |
| **GitHub CLI (`gh`)** | 建仓、发 Release、查 CI，比手搓 API 省事 | 见下 |
| **curl** | 传 Release 资产 | 系统自带 |

```bash
# Windows
winget install --id GitHub.cli
# macOS
brew install gh
# Debian / Ubuntu
sudo apt install gh
```

验证：`git --version`、`gh --version`。

### 1.2 认证：三选一

| 方式 | 适合 | 缺点 |
|---|---|---|
| **HTTPS + Token** | 大多数情况，尤其公司网络只放行 443 | token 要自己管好 |
| **SSH 密钥** | 长期使用，免输密码 | 公司网络可能封 22 端口 |
| **`gh auth login`** | 最省事，自动配好 git 凭据 | 需要浏览器 |

#### 方式 A：HTTPS + Token

1. <https://github.com/settings/tokens> → **Generate new token (classic)**
2. 勾 scope：`repo`（私有仓库必需）、`workflow`（要推 CI 文件时必需）
3. 生成后**立刻复制**（只显示一次）
4. 首次 `git push`：用户名填 GitHub 用户名，密码栏**粘贴 token**

记住凭据：

```bash
git config --global credential.helper store     # ⚠️ 明文存 ~/.git-credentials
git config --global credential.helper 'cache --timeout=3600'   # 更安全，1 小时过期
```

Windows 装 Git for Windows 时自带 `manager`，走系统凭据管理器，比 `store` 安全。

#### 方式 B：SSH

```bash
ssh-keygen -t ed25519 -C "you@example.com"     # 一路回车
cat ~/.ssh/id_ed25519.pub                      # 复制到 github.com/settings/keys
ssh -T git@github.com                          # 看到 Hi <username>! 就成了
```

#### 方式 C：`gh auth login`（推荐）

```bash
gh auth login    # 选 GitHub.com → HTTPS → 浏览器登录
```

它会自动配好 git 的凭据助手。

### 1.3 用已有凭据让 `gh` 免登录

`gh` 没登录、但 git 已经存了凭据时，别重新授权——把凭据喂给它：

```bash
export GH_TOKEN=$(printf 'protocol=https\nhost=github.com\n\n' \
  | git credential fill | sed -n 's/^password=//p')

gh auth status
# ✓ Logged in to github.com account <username> (GH_TOKEN)
```

Windows PowerShell：

```powershell
$cred = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
$env:GH_TOKEN = ($cred | Where-Object { $_ -like 'password=*' }) -replace '^password=',''
```

只管当前终端，关掉就没了，不往磁盘写第二份凭据。

> 提示 `Missing required token scopes: 'read:org'` 不影响个人仓库，只在操作组织仓库时要补。

### 1.4 身份与匿名邮箱

```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

**邮箱会公开**——提交记录里任何人可见。想藏就用 GitHub 匿名邮箱：

```
<你的数字ID>+<用户名>@users.noreply.github.com
```

数字 ID 在 <https://github.com/settings/emails> 能看到。

---

## 2. 发布前：把东西整理干净

这一步比后面所有步骤都重要。

### 2.1 三分钟体检

```bash
# 顶层清单 + 各目录体积
du -sh */ 2>/dev/null | sort -rh | head -20

# 大文件（>5 MB）
find . -type f -size +5M -not -path './.git/*' -exec ls -lh {} \;
```

要警惕的：

| 类型 | 例子 | 处理 |
|---|---|---|
| **真实数据** | 客户资料、聊天记录、导出的表格 | 绝不入库 |
| **运行产物** | `out/`、`dist/`、`build/`、`*.log` | 加 `.gitignore` |
| **密钥令牌** | `.env`、`*.key`、`*.pem`、config 里的 token | 绝不入库 |
| **个人文档** | 交接文档、工作笔记、内部备注 | 加 `.gitignore` |
| **模型权重** | `*.onnx`、`*.pt`、`*.safetensors` | Release 资产 / LFS |
| **依赖目录** | `.venv/`、`node_modules/` | 加 `.gitignore` |

### 2.2 `.gitignore`：别自己编

用官方模板库 <https://github.com/github/gitignore>（CC0，随便抄）：

```bash
# Python
curl -s https://raw.githubusercontent.com/github/gitignore/main/Python.gitignore > .gitignore

# Node
curl -s https://raw.githubusercontent.com/github/gitignore/main/Node.gitignore > .gitignore

# 再加项目自己的
printf '\n.venv/\nout/\nsamples/\n*.log\n.env\n' >> .gitignore
```

通用补充（几乎每个项目都该有）：

```gitignore
# 编辑器
.vscode/
.idea/
*.swp

# 系统
.DS_Store
Thumbs.db
desktop.ini

# 密钥
.env
.env.*
*.key
*.pem
secrets.json

# 运行数据
*.log
tmp/
temp/
```

> 已经误提交的文件，加 `.gitignore` **不会**让它消失——见 [§10.13](#1013-想让某文件不被追踪但保留本地)。

### 2.3 `.gitattributes`：统一换行

不写这个，Windows 的 CRLF 和 Linux 的 LF 互相污染，每个提交都显示"整个文件都改了"。

```gitattributes
* text=auto eol=lf

# 源码
*.py   text eol=lf
*.js   text eol=lf
*.ts   text eol=lf
*.css  text eol=lf
*.html text eol=lf
*.md   text eol=lf
*.json text eol=lf
*.yml  text eol=lf
*.sh   text eol=lf

# Windows 脚本必须 CRLF
*.bat  text eol=crlf
*.cmd  text eol=crlf
*.ps1  text eol=crlf

# 二进制，不转换
*.png  binary
*.jpg  binary
*.gif  binary
*.pdf  binary
*.zip  binary
*.onnx binary
```

### 2.4 隐私扫描

**这一步最容易假干净。**

#### 先扫描，再提交

```bash
git add -A

for pat in '1[3-9][0-9]{9}' 'qq\.com' 'wxid_[a-z0-9]+' \
           'ghp_[A-Za-z0-9]+' 'sk-[A-Za-z0-9]{20,}' \
           'C:\\Users' 'D:\\'; do
  echo "--- $pat ---"
  git grep --cached -nIE "$pat" | head -5
done
```

#### 三条硬规矩

**① `--cached` 必须排在模式前面。**

```bash
git grep -nIE 'pattern' --cached    # ❌ fatal: option '--cached' must come before non-option arguments
git grep --cached -nIE 'pattern'    # ✅
```

错误写法退出码 128、stdout 空。如果再把 stderr 丢掉（`2>/dev/null`），看到的就是"0 命中"——
**而实际上一个文件都没扫**。

这不是假设：曾因此漏掉一个 IM 账号 ID，在公开仓库里躺了一整天才发现。

**② 检查退出码。**

| 退出码 | 含义 |
|---|---|
| `0` | 有命中 |
| `1` | 真的没有命中 |
| `≥2` | **命令本身出错了**，结果无效 |

**③ 先跑正例自检。**

```bash
git grep --cached -lIE '.' | head -3    # 必须能扫出东西
```

扫不出来就说明命令坏了，此时的"0 命中"不能当证据。

#### 用专门工具

```bash
# gitleaks：按规则库扫密钥，能扫历史提交
gitleaks detect --source . --verbose

# trufflehog
trufflehog git file://. --only-verified
```

手写正则只能覆盖你想到的模式；工具覆盖几百种真实泄漏形态。

#### 看位置，不看数量

- 在 `README.md` 的示例里 → 正常（但要用明显假的：`13800000000`、`example@example.com`）
- 在 `scripts/*.py` 的**硬编码路径**里 → 通常真泄漏
- 在测试夹具里 → 确认是合成数据

### 2.5 体积

| 项目 | 限制 |
|---|---|
| 单文件 | 100 MB 硬限制（超过直接拒绝推送） |
| 单文件提醒 | 50 MB |
| 仓库建议 | < 1 GB |
| Release 单个资产 | 2 GB |

超过 50 MB 先问：**它该不该进 git？**

```bash
git lfs install
git lfs track "*.onnx"
git add .gitattributes
```

> LFS 免费额度 1 GB 存储 / 1 GB 月流量。

---

## 3. 建仓与推送

### 3.1 初始化

```bash
git init -b main        # 关键：指定 main，否则老版本 git 建成 master
```

### 3.2 第一次提交并推送

#### 方式 A：`gh`（最简单）

```bash
git add -A
git commit -m "初始提交"
gh repo create my-app --source . --public --push --description "一句话说明"
```

| 参数 | 作用 |
|---|---|
| `--public` / `--private` | 可见性 |
| `-d, --description` | 描述（支持中文，`gh` 自己处理编码） |
| `--push` | 推送本地提交 |
| `--add-readme` | 顺便建 README（本地已有就别加） |

#### 方式 B：网页建仓 + 手动关联

1. 网页 New repository，**不要**勾 "Initialize with README"（否则推送冲突）
2. 本地：

```bash
git remote add origin https://github.com/<username>/my-app.git
git push -u origin main
```

#### 方式 C：纯 REST API

```bash
curl -s -X POST https://api.github.com/user/repos \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -d '{"name":"my-app","private":false,"description":"一句话说明"}'
```

**中文描述要小心**：PowerShell 的 `Invoke-RestMethod -Body "<字符串>"` 用系统 ANSI 编码发送，
中文变 `??????`。先转 UTF-8 字节：

```powershell
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
Invoke-RestMethod -Uri $url -Method Patch -Headers $h -Body $bytes `
  -ContentType 'application/json; charset=utf-8'
```

或者直接用 `gh`——它按 UTF-8 发。

### 3.3 补充仓库信息

```bash
gh repo edit --description "中文描述" --add-topic python --add-topic cli
gh repo edit --homepage "https://example.com"
```

话题（topics）能让别人搜到，花两分钟想 3–5 个。

---

## 4. 打 Release

Release 是"给外面人下载的东西"。构建产物、模型权重放这里，别塞进 git 历史。

### 4.1 标签规范

语义化版本 `v主.次.修`：

| 场景 | 版本变化 |
|---|---|
| 修 bug，不改接口 | `v1.0.0` → `v1.0.1` |
| 加功能，向后兼容 | `v1.0.1` → `v1.1.0` |
| 不兼容改动 | `v1.1.0` → `v2.0.0` |

```bash
git tag -a v1.0.0 -m "第一个可用版本"
git push origin v1.0.0          # 或 --tags 推全部
```

### 4.2 发 Release

```bash
gh release create v1.0.0 --title "v1.0.0" --notes "第一个可用版本"
gh release create v1.0.0 --title "v1.0.0" --notes-file RELEASE_NOTES.md
gh release create v1.0.0 --generate-notes        # 按提交自动生成
```

### 4.3 挂资产

```bash
gh release create v1.0.0 ./dist/my-app.zip ./dist/my-app.tar.gz \
  --title "v1.0.0" --notes-file RELEASE_NOTES.md
```

**资产名只能用 ASCII。**

真实教训：上传 `项目-源码分享包.zip`，GitHub 上变成 `-.-.zip`——中文在 URL 拼接时被吃掉。
用拼音或英文命名（`myapp-src-v1.0.0.zip`），中文说明写正文里。

### 4.4 源码包：用 `git archive`

想让"下载包 == 仓库内容"，别手写文件清单：

```bash
git archive --prefix=my-app/ -o my-app-src-v1.0.0.zip HEAD
```

只打包已追踪文件，天然排除 `.gitignore` 里的东西。

### 4.5 更新已发布的 Release

```bash
gh release edit v1.0.0 --notes-file NEW_NOTES.md    # 改说明
gh release upload v1.0.0 ./dist/extra.zip           # 补资产
gh api -X DELETE repos/<owner>/<repo>/releases/assets/<id>   # 删资产
```

**资产不能覆盖，只能删了重传。** 名字带版本号能省事。

---

## 5. 持续集成（CI）

CI 的价值：**证明这个仓库在别人的机器上也能跑起来。**

### 5.1 最小工作流

`.github/workflows/tests.yml`：

```yaml
name: tests

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
          cache: pip
      - run: pip install -r requirements.txt
      - run: python -m unittest discover -s tests -v
```

Node 版：

```yaml
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm test
```

### 5.2 跨平台

**办法一：矩阵**

```yaml
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
    runs-on: ${{ matrix.os }}
```

**办法二：让测试自己跳过**（推荐，代价小）

```python
import unittest
from pathlib import Path

CJK_FONTS = Path("C:/Windows/Fonts/simhei.ttf").exists()

@unittest.skipUnless(CJK_FONTS, "需要系统中文字体，CI 上没有")
class ChinesePdfTests(unittest.TestCase):
    ...
```

### 5.3 "本地绿、CI 红"的三个原因

| 现象 | 原因 | 改法 |
|---|---|---|
| 导入阶段 `ImportError`/`FileNotFoundError` | 模块顶层就打开系统字体、读配置 | 改惰性加载 |
| "仓库里应该有某文件"失败 | 那是生成物，没进仓库 | `skipUnless(文件存在, "先跑生成命令")` |
| 时间断言失败 | 写死 `+08:00` | 加环境守卫，或改 UTC 比较 |

**最值钱的验证**：推完之后在**另一个目录**克隆下来跑一遍。

```bash
git clone https://github.com/<username>/<repo>.git /tmp/clone_test
cd /tmp/clone_test && <跑你的测试>
```

能抓到的都是本地抓不到的：绝对路径、缺字体、缺语料、时区假设、`.gitignore` 漏掉的依赖。

---

## 6. 验收清单

### 仓库

- [ ] 默认分支是 `main`
- [ ] 描述是正常中文/英文，不是 `??????`
- [ ] 有话题（topics）
- [ ] LICENSE 存在且 GitHub 侧识别正确（仓库页右上角显示）
- [ ] README 写了"这是什么、怎么跑、许可证"

### 内容

- [ ] 远端文件数 == 本地 `git ls-files`
- [ ] 没有 `.env` / `*.key` / 密钥
- [ ] 没有个人路径、真实数据、真实联系方式
- [ ] 大文件检查过

### 功能

- [ ] 干净克隆能装依赖
- [ ] 干净克隆测试能过（或明确跳过并说明原因）
- [ ] CI 是绿的

### Release

- [ ] 标签格式对（`v1.0.0`）
- [ ] 资产名是 ASCII
- [ ] 资产大小和本地一致
- [ ] 说明写了"这个版本能干什么"

核对命令：

```bash
gh api repos/<owner>/<repo>/git/trees/main?recursive=1 \
  --jq '[.tree[]|select(.type=="blob")]|length'      # 远端文件数
git ls-files | wc -l                                  # 本地文件数
gh run list --limit 3                                 # CI
gh release view v1.0.0 --json assets --jq '.assets[]|"\(.name) \(.size)"'
```

---

## 7. 十二个坑

### 坑 1 · 中文描述变成 `??????`

**原因**：PowerShell 的 `Invoke-RestMethod -Body "<字符串>"` 用系统 ANSI 编码发送。

```powershell
gh repo edit --description "中文描述"       # ✅ 用 gh
# 或
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
Invoke-RestMethod ... -Body $bytes -ContentType 'application/json; charset=utf-8'
```

已写坏的原地改：`gh repo edit --description "正确的描述"`。

### 坑 2 · Release 资产名被吃掉

中文进 URL 被替换。资产名用 ASCII，中文说明放正文。

### 坑 3 · `src refspec main does not match any`

本地分支叫 `master`。`git branch -M main` 再推；新建时用 `git init -b main`。

### 坑 4 · 改许可证改变不了已经发出去的授权

授权一旦给出不能撤销，改许可证只管之后的版本。
**推论**：fork 别人仓库不要改 LICENSE，对上游毫无作用。

### 坑 5 · 干净克隆里测试全红

三类原因、三种改法见 [§5.3](#53-本地绿ci-红的三个原因)。

反面教材：

```python
# ❌ 模块顶层打开字体，任何 import 都会崩
_FONTS = {"song": fitz.Font(fontfile="C:/Windows/Fonts/simsun.ttc")}

# ✅ 第一次真正用到时才打开
_FONT_CACHE = {}
def _font(name):
    if name not in _FONT_CACHE:
        path = FONT_PATHS[name]
        if not os.path.exists(path):
            raise RuntimeError(f"缺少字体 {path}：Windows 自带，Linux 装 fonts-wqy-zenhei")
        _FONT_CACHE[name] = fitz.Font(fontfile=path)
    return _FONT_CACHE[name]
```

前者的后果不是"生成报错"，而是**连测试都跑不起来**。

### 坑 6 · 私有文件混进仓库

1. **先写 `.gitignore`**，再 `git add`
2. `git add -A` 后先看清单：`git status --short`
3. 预演：`git add --dry-run .`
4. 已提交：`git rm -r --cached <路径>`——**历史里还在**，要真清见 [§8.2](#82-误传了个人文件非密钥)

### 坑 7 · PowerShell 读 `.ps1` 报一堆语法错

Windows PowerShell 5.1 读**无 BOM 的 UTF-8** `.ps1` 时按系统 ANSI（中文是 GBK）解析，
中文变乱码、引号配对被破坏。

```powershell
$text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($true)))
```

PowerShell 7（`pwsh`）没这问题，但别人可能用 5.1，存 BOM 更稳。

### 坑 8 · `git grep` 写了"0 命中"，其实命令根本没跑

`--cached` 位置写错。详见 [§2.4](#24-隐私扫描)。

### 坑 9 · 推完不算完，要验远端实际内容

把输出管道给 `Select-String` / `grep` 过滤，错误信息也被滤掉，屏幕上却一片空白。

1. 别用过滤器处理推送输出——看 `$LASTEXITCODE` / `$?`，或看全量
2. 验收读远端：`gh api .../git/ref/heads/main`，或克隆下来看

### 坑 10 · 用 API 建提交，会把账号主邮箱写进去

`POST /git/commits` 不指定 `author`/`committer` 时，GitHub 用账号主邮箱兜底，公开可见。

```powershell
author    = @{ name='Your Name'; email='<数字ID>+<用户名>@users.noreply.github.com'; date=$now }
committer = @{ name='Your Name'; email='<同上>'; date=$now }
```

自查：

```bash
gh api repos/<owner>/<repo>/commits --jq '.[].commit.author.email' | sort -u
```

### 坑 11 · 本地和远端提交哈希对不上

`git status` 干净，但 `HEAD` 和远端不同。**先比树**：

```bash
git write-tree                                        # 本地
gh api repos/<o>/<r>/git/commits/HEAD --jq .tree.sha   # 远端
```

一样就说明内容完全一致，只差提交元数据；`git fetch && git reset --hard origin/main` 对齐。

**别手工拼提交对象凑哈希**——tree、作者、时间戳、消息尾换行、时区全对齐也未必匹配，实测 8 种组合都失败。

---

### 坑 12 · `.gitattributes` / `.gitignore` 带了 BOM，第一行失效

**症状**：git 报 `统一换行 is not a valid attribute name: .gitattributes:1`，
或者 `.gitignore` 的第一条规则明明写了却不起作用。

**原因**：文件开头有 UTF-8 BOM（`EF BB BF`）。`.gitattributes` / `.gitignore` 是**逐行纯文本解析**的，
BOM 会被当成第一行内容的一部分，于是注释变成"属性名"、第一条规则变成"带前缀的模式"。

**怎么来的**：Windows PowerShell 5.1 的 `Set-Content -Encoding UTF8` **默认写 BOM**。
写 `.md`、`.py` 没事（大多数工具能跳过 BOM），但这两个点文件不行。

**修法**：写成无 BOM 的 UTF-8。

```powershell
$enc = New-Object System.Text.UTF8Encoding($false)     # $false = 不加 BOM
[System.IO.File]::WriteAllLines('C:\path\.gitattributes', $lines, $enc)
```

或者用 PowerShell 6+（`pwsh`）的 `Set-Content -Encoding utf8NoBOM`。

**注意跟[坑 7](#坑-7--powershell-读-ps1-报一堆语法错)的区别**：
`.ps1` **要** BOM（否则 5.1 按 ANSI 解析），`.gitattributes` / `.gitignore` **不能**要 BOM。
两类文件要求相反，别一刀切。

---
## 8. 急诊室：出事了怎么办

### 8.1 误传了密钥 / token

**顺序很重要：先撤销，再清理。**

1. **立刻作废**：GitHub → Settings → Developer settings → Tokens → Revoke；
   云服务密钥去对应控制台禁用
2. 删除文件并提交
3. **洗历史**（旧提交里还在）：

```bash
pip install git-filter-repo

# 把字符串从所有历史换掉
git filter-repo --replace-text <(echo 'literal:AKIAIOSFODNN7EXAMPLE==>REMOVED')

# 或删掉某文件的所有历史
git filter-repo --path secrets.json --invert-paths

git push --force --all
```

4. **假设它已泄露**：查该密钥对应账号的异常操作、账单变化
5. 涉及很多人时可请求 GitHub 清理缓存：<https://github.com/contact>

> 私有仓库也当公开处理——协作者、GitHub 员工、曾 fork 过的人都能看到。

### 8.2 误传了个人文件（非密钥）

```bash
git rm --cached path/to/private.pdf
printf 'path/to/private.pdf\n' >> .gitignore
git commit -m "移除个人文件"
git push

# 历史里还在，要真清：
git filter-repo --path path/to/private.pdf --invert-paths
git push --force --all
```

`filter-repo` 会自动清备份引用，`filter-branch` 不会，需手动：

```bash
git for-each-ref --format='%(refname)' refs/original | xargs -n1 git update-ref -d
git reflog expire --expire=now --all
git gc --prune=now
```

### 8.3 想删仓库

```bash
gh repo delete <owner>/<repo> --yes
```

删之前想清楚：fork 出去的副本、别人本地的克隆、搜索引擎缓存都不会消失。

### 8.4 网络把 git 打死

**症状**：`schannel: failed to receive handshake`、`OpenSSL SSL_read: unexpected eof`、
`RPC failed; curl 56`，但浏览器能打开 GitHub。

**排查顺序**：

1. **代理**。系统代理开着但 git 没走，或代理不支持 git 的 TLS 握手。关掉代理试，或给 `github.com` 设直连
2. **换协议**：`git remote set-url origin git@github.com:...`
3. **换端口**（公司封 22）：`~/.ssh/config` 里写
   ```
   Host github.com
     Hostname ssh.github.com
     Port 443
   ```
4. **临时降级**：`git -c http.sslBackend=openssl fetch`、`git -c http.version=HTTP/1.1 fetch`

**实在不行，用 API 绕过 git 传输**：

```powershell
# 1) 给改动文件建 blob（base64，避开编码坑）
POST /repos/{o}/{r}/git/blobs        @{ content = $base64; encoding = 'base64' }
# 2) base_tree + 覆盖项 + 删除项（sha = null）建树
POST /repos/{o}/{r}/git/trees        @{ base_tree = $old; tree = @(...) }
# 3) 建提交（parents = @() 就是全新的根提交）
POST /repos/{o}/{r}/git/commits      @{ message = ...; tree = $tree.sha; parents = @() }
# 4) 强制更新引用
PATCH /repos/{o}/{r}/git/refs/heads/main   @{ sha = $commit.sha; force = $true }
```

**动引用前先比树**：`/git/trees/<sha>?recursive=1` 数文件，只少掉该少的再动手。

> 被换掉的历史成为**不可达对象**，只有知道旧 SHA 才能取到；要彻底清只能删库重建。

---

## 9. 命令速查

### 9.1 每天都会用

```bash
git status -sb                 # 简短状态 + 分支
git add -p                     # 逐块暂存（比 -A 安全）
git commit -m "msg"            # 提交
git commit --amend             # 改上一次提交（没推过才能用）
git push                       # 推
git pull --rebase              # 拉并变基（历史干净）
git log --oneline --graph -20  # 看历史
git diff --stat                # 改了哪些文件
git switch -c feature          # 建分支并切过去
```

### 9.2 撤销

| 想做的事 | 命令 |
|---|---|
| 丢弃工作区某文件的改动 | `git restore <file>` |
| 取消暂存（保留改动） | `git restore --staged <file>` |
| 改上一条提交信息 | `git commit --amend -m "新信息"` |
| 补文件到上一条提交 | `git add <file> && git commit --amend --no-edit` |
| 撤销最近一次提交（保留改动） | `git reset --soft HEAD~1` |
| 撤销最近一次提交（连暂存一起） | `git reset HEAD~1` |
| 撤销最近一次提交（**丢弃改动**） | `git reset --hard HEAD~1` |
| 撤销**已推送**的提交 | `git revert <sha>`（产生反向提交，安全） |
| 撤销已推送的提交并强推 | `git reset --hard <sha> && git push --force-with-lease` |

> 已推送优先用 `revert`：不改历史，别人不用重新拉。
> 必须改历史时用 `--force-with-lease`，别用 `--force`（前者会在别人有新提交时拒绝）。

### 9.3 找回

```bash
git reflog                     # 所有 HEAD 移动记录，找回误删分支/误 reset 的第一站
git reset --hard HEAD@{3}      # 回到 reflog 里的某个位置
git checkout -b rescue <sha>   # 从某个 sha 建分支救回来
git fsck --lost-found          # 找游离对象
```

### 9.4 分支

```bash
git branch -a                  # 本地 + 远端分支
git branch -d old              # 删本地（已合并）
git branch -D old              # 强删（未合并）
git push origin --delete old   # 删远端分支
git push -u origin feature     # 首次推送并建立追踪
```

### 9.5 远程

```bash
git remote -v                        # 看远端地址
git remote set-url origin <url>      # 换地址（HTTPS ↔ SSH）
git fetch --prune                    # 拉取并清理已删除的远端分支
git remote add upstream <url>        # 加原仓库（fork 后同步上游用）
```

### 9.6 搜索

```bash
git grep -n "关键词"                  # 当前工作区
git grep --cached -n "关键词"          # 暂存区（发布前扫描用这个）
git log -S "关键词" --oneline         # 哪些提交增删了这个词
git log -G "正则" --oneline           # 同上，支持正则
git log --author="名字" --oneline      # 按作者
git blame <file>                     # 每行是谁改的
```

### 9.7 清理

```bash
git clean -n                   # 预演：会删哪些未追踪文件
git clean -fd                  # 真删（不可恢复）
git stash                      # 临时收起改动
git stash pop                  # 取回
git gc --prune=now             # 清理游离对象、压缩仓库
```

### 9.8 `gh` 常用

```bash
gh repo view --web                    # 浏览器打开当前仓库
gh repo clone <owner>/<repo>
gh repo edit --add-topic cli
gh pr create --fill                   # 从当前分支开 PR
gh pr checks                          # 看 CI
gh run list --limit 5                 # 最近的 workflow
gh run watch                          # 实时跟一个 run
gh release list
gh api repos/{owner}/{repo}/commits --jq '.[].commit.author.email' | sort -u
```

---

## 10. 排错手册：我干了XX，怎么救

### 10.1 提交到了错误的分支

```bash
git branch correct-branch        # 在新分支上留个标记
git reset --hard HEAD~1          # 当前分支回退
git switch correct-branch
```

### 10.2 忘记了 push / 忘记 commit

```bash
git status          # 看有什么没提交
git log origin/main..HEAD --oneline    # 看有什么没推送
```

### 10.3 提交信息写错了

```bash
git commit --amend -m "正确的信息"        # 最近一条，且没推过
# 更早的：
git rebase -i HEAD~3                     # 把目标行改成 reword
```

### 10.4 推错了，远端要回滚

```bash
git revert <sha> && git push             # 安全，推荐
# 或（会改历史，需强推）
git reset --hard <good-sha> && git push --force-with-lease
```

### 10.5 误删了分支

```bash
git reflog                       # 找到删除前的 sha
git checkout -b recovered <sha>
```

### 10.6 误 `reset --hard` 丢了提交

```bash
git reflog                       # 找 ORIG_HEAD 之前的位置
git reset --hard HEAD@{1}
```

> `reset --hard` 丢的是**工作区改动**，已提交的内容在 reflog 里通常还能找回。
> 但**从未提交过**的改动找不回来——这也是为什么勤提交。

### 10.7 合并冲突搞乱了

```bash
git merge --abort                # 回到合并前
git rebase --abort               # rebase 同理
# 想重来：
git reset --hard ORIG_HEAD
```

逐文件解决时：

```bash
git diff --name-only --diff-filter=U     # 列出冲突文件
# 编辑后
git add <file>
git rebase --continue    # 或 git merge --continue
```

一方全要：

```bash
git checkout --ours <file>       # rebase 时 ours/theirs 是反的，注意
git checkout --theirs <file>
```

### 10.8 `push` 被拒（non-fast-forward）

```bash
git pull --rebase origin main    # 先变基到最新
git push
```

**别直接 `--force`**——会把别人的提交冲掉。

### 10.9 大文件推不上去

```
remote: error: File xxx is 128.00 MB; this exceeds GitHub's file size limit of 100.00 MB
```

```bash
git rm --cached bigfile.zip
printf 'bigfile.zip\n' >> .gitignore
git commit -m "移除大文件"
# 历史里还在：
git filter-repo --path bigfile.zip --invert-paths
```

或转 LFS：`git lfs migrate import --include="*.zip"`。

### 10.10 换行符导致"整个文件都改了"

```bash
# 规范化
git add --renormalize .
git commit -m "统一换行为 LF"
```

同时确认 `.gitattributes` 存在（见 [§2.3](#23-gitattributes统一换行)）。

### 10.11 中文文件名显示成 `\346\226\207...`

```bash
git config --global core.quotepath false
```

### 10.12 fork 后同步上游更新

```bash
git remote add upstream https://github.com/ORIGINAL/REPO.git
git fetch upstream
git switch main
git merge upstream/main        # 或 git rebase upstream/main
git push origin main
```

### 10.13 想让某文件不被追踪但保留本地

```bash
git rm --cached config.local.json
printf 'config.local.json\n' >> .gitignore
git commit -m "不再追踪本地配置"
```

### 10.14 想让已追踪文件的本地修改被忽略

```bash
git update-index --skip-worktree config.local.json      # 忽略修改
git update-index --no-skip-worktree config.local.json   # 恢复
```

> `--assume-unchanged` 是性能优化用途，会被 `git pull` 覆盖；配置类用 `--skip-worktree`。

### 10.15 同一台机器多个 GitHub 账号

`~/.ssh/config`：

```
Host github-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_work

Host github-personal
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_personal
```

用的时候改远端地址：

```bash
git remote set-url origin git@github-work:company/repo.git
```

### 10.16 撤销一个 Release

```bash
gh release delete v1.0.0 --yes          # 删 Release
git push origin --delete v1.0.0         # 删远端标签
git tag -d v1.0.0                        # 删本地标签
```

---

## 11. 许可证怎么选

| 许可证 | 别人能做什么 | 典型场景 |
|---|---|---|
| **MIT** | 随便用、改、闭源卖，保留版权声明 | 希望尽可能多人用 |
| **Apache-2.0** | 同 MIT，另加专利授权 | 企业项目 |
| **GPL-3.0** | 分发修改版必须开源 | 希望改进回流 |
| **AGPL-3.0** | 同 GPL，**且通过网络提供服务也要开源** | 防止被做成闭源 SaaS |
| **CC0 / Unlicense** | 完全放弃权利 | 公共领域素材 |
| **CC-BY-4.0** | 署名即可随意用 | 文档、教程、数据集 |

**放哪里**：

```
LICENSE            ← 全文
README.md          ← 末段写一句"本项目采用 XXX 许可证"
package.json       ← Node 项目再加 "license": "AGPL-3.0-only"
```

**AGPL 一句话**：管的是"改了代码 + 通过网络给别人用 + 不公开源码"；
自己用、给同事拷、公司内网搭、收钱做服务，都不受影响。

**文档类项目**用 **CC-BY-4.0** 比代码许可证更合适——它按"署名"授权，
不涉及"源码""分发"这些代码概念。想彻底放开用 **CC0**。

---

## 12. 常见问题

**Q：仓库能改私有吗？改了之后公开的内容会消失吗？**
能改（Settings → Danger Zone）。改后新访客看不到，但已 fork / 克隆 / 缓存的内容不会消失。

**Q：`gh` 提示 token 缺 `read:org`？**
个人仓库不需要。组织仓库时才补：`gh auth refresh -h github.com`。

**Q：`git push` 一直要输密码？**
凭据助手没配好。Windows 用 `manager`，Linux 用 `credential.helper cache`。

**Q：历史里有个大文件，删了文件还是推不上去？**
历史里的 blob 还在。`git filter-repo --path <file> --invert-paths`，
或 `git lfs migrate import`。

**Q：Release 资产能覆盖吗？**
不能。删了重传，或用不同文件名。

**Q：怎么知道别人下载了多少次？**

```bash
gh api repos/<o>/<r>/releases --jq '.[].assets[].download_count'
```

**Q：Actions 免费额度？**
公开仓库免费无限。私有仓库 GitHub Free 每月 2000 分钟（Windows runner ×2，macOS ×10）。

**Q：必须写 README 吗？**
技术上不必，实际上不写等于没人会用。最低限度：一句话说明 + 一条能跑起来的命令 + 许可证。

---

## 13. 来源与致谢

这份手册的内容分两类，来源都标清楚：

### 原创：实测得来

§2.4 隐私扫描的三条硬规矩、§5.3 本地绿 CI 红的三类原因、§7 十二个坑、
§8.4 网络不通时用 API 绕过 git 传输、附录 A 的脚本——**都是实际操作中踩出来的**，
在别处找不到同样的记录。

### 整合：把散在各处的知识收拢

| 主题 | 主要来源 | 许可 |
|---|---|---|
| `.gitignore` 模板 | [github/gitignore](https://github.com/github/gitignore) | CC0 |
| 命令速查（§9） | [tiimgreen/github-cheat-sheet](https://github.com/tiimgreen/github-cheat-sheet)、[521xueweihan/git-tips](https://github.com/521xueweihan/git-tips) | MIT |
| 排错思路（§10） | [k88hudson/git-flight-rules](https://github.com/k88hudson/git-flight-rules) | CC BY-NC-SA 4.0 |
| 系统讲解 | [zhongyi-tong/git-recipes](https://github.com/zhongyi-tong/git-recipes) | 见仓库 |
| `gh` 用法 | [cli/cli](https://github.com/cli/cli) | MIT |

**重要说明**：上表列的是"概念来源"，不是逐字转载。
所有文字都是按本项目结构和场景重写的，没有复制原文段落——
这样既避免许可证冲突（git-flight-rules 是 NC 协议，原文转载会有问题），
也让内容贴合"发布"这个具体场景而不是泛泛讲 git。

### 官方文档（最权威）

- GitHub CLI 手册：<https://cli.github.com/manual/>
- GitHub REST 文档：<https://docs.github.com/rest>
- 从已有源码建仓：<https://docs.github.com/repositories/creating-and-managing-repositories/creating-a-repository-from-an-existing-source-code>
- 管理 Release：<https://docs.github.com/repositories/releasing-projects-on-github>
- Actions：<https://docs.github.com/actions>
- 许可证选择：<https://choosealicense.com>

### 工具

| 用途 | 工具 |
|---|---|
| 洗历史（替代 filter-branch） | [git-filter-repo](https://github.com/newren/git-filter-repo) |
| 密钥扫描 | [gitleaks](https://github.com/gitleaks/gitleaks)、[trufflehog](https://github.com/trufflesecurity/trufflehog) |
| 提交前拦截 | [pre-commit](https://github.com/pre-commit/pre-commit) |
| 大文件 | [Git LFS](https://git-lfs.com/) |

---

## 附录 A：发布脚本

仓库带两个跨平台脚本：

- `scripts/publish.sh` — macOS / Linux / WSL / Git Bash
- `scripts/publish.ps1` — Windows PowerShell

```bash
# 先预演，看它准备做什么
./scripts/publish.sh --name my-app --description "一句话说明" --tag v1.0.0 --dry-run

# 确认没问题再真跑
./scripts/publish.sh --name my-app --description "一句话说明" --tag v1.0.0
```

流程：隐私扫描（带正例自检）→ 检查忽略清单 → 提交 → 建仓 → 推 → 打标签 →
生成源码包 → 发 Release → 打印验收结果。

隐私扫描命中时**默认中止**，确认无误加 `--force` 才继续。

---

## 附录 B：提交信息怎么写

### 最小要求

说清"这次改了什么"，别写 `update`、`fix bug`。

```
❌ 修复 bug
❌ update
✅ 修复导出 CSV 时中文乱码：改用 UTF-8-SIG 编码
```

### Conventional Commits（可选，但很值）

```
<type>(<scope>): <subject>

<body>
```

| type | 含义 | 版本影响 |
|---|---|---|
| `feat` | 新功能 | 次版本 +1 |
| `fix` | 修 bug | 修订号 +1 |
| `docs` | 只改文档 | — |
| `refactor` | 重构，不改行为 | — |
| `perf` | 性能优化 | 修订号 +1 |
| `test` | 加测试 | — |
| `chore` | 构建、依赖、杂项 | — |
| `BREAKING CHANGE:` | 不兼容改动（写 body） | 主版本 +1 |

示例：

```
feat(export): 支持导出为 PDF

原来只能导 CSV。加了 PDF 导出，用 pdfkit，中文字体走系统字体，
找不到时退回内置子集。

Closes #42
```

好处：`gh release create --generate-notes` 能按 type 自动分类生成 Release 说明。

---

## 许可

本手册采用 [AGPL-3.0-only](LICENSE)。

发现新坑欢迎提 Issue——尤其是上面没列到的。
