# Git 排错手册

> 「我干了某件事，怎么救？」
>
> 主手册：[把本地项目发布到 GitHub](../README.md) · 本文是它的排错分册，可以单独看。

---

## 0. 怎么用

**最快的用法：直接搜报错原文。**

按 `Ctrl+F` 搜你屏幕上那段红字（`fatal:` 后面那半句），[§1 索引](#1-报错原文索引)里大多数都有。

**找不到就按场景找**：忘了提交、推错分支、丢了东西、文件太大……
[§2](#2-提交相关) 到 [§7](#7-仓库设置与-release) 是按「你干了什么」分的组。

**实在救不回来**，看 [§9](#9-还是不行时)——多数情况还有兜底手段。

> 先说最重要的一条：**只要提交过（`git commit` 过），几乎什么都能救**。
> `git reflog` 记录了你每一个 HEAD 位置，保留 90 天。
> 救不回来的只有「从未提交过」的改动。

---

## 1. 报错原文索引

| 报错片段 | 章节 |
|---|---|
| `fatal: not a git repository` | [§2.1](#21-在错误的目录里执行了-git-命令) |
| `nothing to commit, working tree clean` | [§2.3](#23-忘了把文件加进去) |
| `fatal: pathspec 'xxx' did not match any files` | [§5.6](#56-文件名里有空格或特殊字符) |
| `Updates were rejected because the remote contains work` | [§3.1](#31-push-被拒non-fast-forward) |
| `Updates were rejected because the tip of your current branch is behind` | [§3.1](#31-push-被拒non-fast-forward) |
| `src refspec main does not match any` | [§3.2](#32-src-refspec-main-does-not-match-any) |
| `error: failed to push some refs` | [§3.1](#31-push-被拒non-fast-forward) |
| `! [rejected] ... (fetch first)` | [§3.1](#31-push-被拒non-fast-forward) |
| `fatal: refusing to merge unrelated histories` | [§3.7](#37-合并两个不相关的历史) |
| `CONFLICT (content): Merge conflict in xxx` | [§4.5](#45-合并冲突了) |
| `fatal: You have not concluded your merge` | [§4.5](#45-合并冲突了) |
| `error: Your local changes would be overwritten` | [§4.7](#47-切换分支时提示本地改动会被覆盖) |
| `remote: error: File xxx is 128.00 MB; this exceeds GitHub's file size limit` | [§5.1](#51-大文件推不上去) |
| `GH001: Large files detected` | [§5.1](#51-大文件推不上去) |
| `fatal: Authentication failed` | [§6.1](#61-一直要输密码或认证失败) |
| `Permission denied (publickey)` | [§6.2](#62-permission-denied-publickey) |
| `schannel: failed to receive handshake` | [§6.3](#63-tls-连接被中断) |
| `OpenSSL SSL_read: ... unexpected eof` | [§6.3](#63-tls-连接被中断) |
| `RPC failed; curl 56` | [§6.3](#63-tls-连接被中断) |
| `ssh: connect to host github.com port 22: Connection timed out` | [§6.4](#64-22-端口被封) |
| `Support for password authentication was removed` | [§6.1](#61-一直要输密码或认证失败) |
| `warning: LF will be replaced by CRLF` | [§5.4](#54-换行符导致整个文件都改了) |
| `\346\226\207\344\273\266` 之类的中文乱码 | [§5.5](#55-中文文件名显示成转义序列) |
| `is not a valid attribute name: .gitattributes:1` | [§5.8](#58-gitattributes-或-gitignore-带-bom) |

---

## 2. 提交相关

### 2.1 在错误的目录里执行了 git 命令

```
fatal: not a git repository (or any of the parent directories): .git
```

**原因**：当前目录不在任何仓库里。

```bash
pwd                  # 确认在哪
git rev-parse --show-toplevel    # 这个目录属于哪个仓库（不在仓库里会报错）
```

**常见诱因**：`cd` 到子目录时多退了一层；或者仓库其实还没 `git init`。

---

### 2.2 提交到了错误的分支

**症状**：本该提到 `feature`，结果提在 `main` 上。

**先看有没有推**：

```bash
git log origin/main..HEAD --oneline      # 这些是还没推的
```

**没推**（最省事）：

```bash
git branch feature            # 在当前位置建分支（保住提交）
git reset --hard HEAD~1       # main 退回一个提交
git switch feature            # 切过去，提交还在
```

**已经推了**：

```bash
git branch feature <sha>      # 在正确分支保住提交
git switch main
git revert <sha>              # 用反向提交撤销（安全，不改历史）
git push
```

> 别在共享分支上 `reset --hard` 后强推，会把别人的提交一起冲掉。

---

### 2.3 忘了把文件加进去

```
nothing to commit, working tree clean
```

但有文件明明改了？两种可能：

```bash
git status --ignored          # 是不是被 .gitignore 挡了
git check-ignore -v 文件      # 看是哪条规则挡的
```

确实漏了：

```bash
git add 文件
git commit --amend --no-edit     # 补进上一次提交（没推过才能用）
```

已经推了，就正常再来一个提交：

```bash
git add 文件 && git commit -m "补上遗漏的文件"
```

---

### 2.4 提交信息写错了

```bash
# 最近一条，且没推过
git commit --amend -m "正确的信息"

# 更早的
git rebase -i HEAD~5      # 把目标行的 pick 改成 reword
```

**已经推送了**：

- 私有仓库 / 自己的分支 → `amend` + `push --force-with-lease` 可以
- 共享分支 → **别改**。历史是别人已经拉过的，改了所有人要重新同步。将错就错，下一个提交写清楚

---

### 2.5 想把一个提交拆成两个

```bash
git reset HEAD~1          # 撤销提交，改动回到工作区
git add -p                # 逐块挑，一次只加一部分
git commit -m "第一部分"
git add -A
git commit -m "第二部分"
```

---

### 2.6 提交里混进了不该要的文件

```bash
# 还没推
git rm --cached 不该要的.txt
git commit --amend --no-edit

# 已经推了
git rm --cached 不该要的.txt
printf '不该要的.txt\n' >> .gitignore
git commit -m "移除不该提交的文件"
```

⚠️ **历史里还在**。要真清见 [§5.2](#52-历史里有密钥或密码)。

---

## 3. 推送与拉取

### 3.1 push 被拒（non-fast-forward）

```
! [rejected]        main -> main (fetch first)
error: failed to push some refs to '...'
hint: Updates were rejected because the remote contains work that you do not have locally.
```

**原因**：远端有你本地没有的提交（别人推过，或你在网页上改过文件）。

**标准解法**：

```bash
git pull --rebase origin main
git push
```

**如果 rebase 冲突**：解决冲突 → `git add <文件>` → `git rebase --continue`。

**如果本地确实是对的、远端那些提交不要了**（只有自己的仓库才这么干）：

```bash
git push --force-with-lease
```

> 用 `--force-with-lease` 不用 `--force`：前者在远端有你不认识的新提交时会拒绝，
> 后者无脑覆盖。这一个字母的差别救过很多人。

---

### 3.2 src refspec main does not match any

```
error: src refspec main does not match any
error: failed to push some refs
```

**三个原因，按可能性排序**：

**① 本地分支不叫 `main`**（最常见）

```bash
git branch --show-current     # 多半显示 master
git branch -M main
git push -u origin main
```

**② 还没有任何提交**

```bash
git log --oneline             # 报 "does not have any commits yet" 就是空的
git add -A && git commit -m "初始提交"
```

**③ 拼错了分支名**

```bash
git branch -a                 # 看实际叫什么
```

---

### 3.3 远端有我不要的提交

```bash
git fetch origin
git log origin/main --oneline -5      # 看清是什么

# 只撤销某一个（安全）
git revert <sha>
git push

# 把远端整体退回某个位置（危险，会改历史）
git reset --hard <good-sha>
git push --force-with-lease
```

---

### 3.4 推错了要回滚远端

**安全做法**（不改历史，推荐）：

```bash
git revert <坏提交的 sha>
git push
```

会产生一个「反向提交」。好处：谁都不用重新拉，审计记录还在。

**改历史做法**（只在私有仓库或自己的分支用）：

```bash
git reset --hard <好的 sha>
git push --force-with-lease
```

> 强推之后，别人的本地分支就分叉了，他们得 `git fetch && git reset --hard origin/main`。
> 团队协作里这是要打招呼的操作。

---

### 3.5 拉取后出现一堆 "Merge branch 'main' of ..." 提交

**原因**：`git pull` 默认是 merge，每次拉取都产生一个合并提交。

**改成 rebase**：

```bash
git config --global pull.rebase true
```

已经产生的那堆可以压缩掉：

```bash
git rebase -i HEAD~5      # 把多余的 merge 提交 squash 掉（只对没推的做）
```

---

### 3.6 想拉取但本地有未提交的改动

```bash
git stash                 # 收起
git pull --rebase
git stash pop             # 取回（可能有冲突，正常解决）
```

或者：

```bash
git commit -m "wip"       # 先提交
git pull --rebase
```

---

### 3.7 合并两个不相关的历史

```
fatal: refusing to merge unrelated histories
```

**原因**：两边没有共同祖先。常见于「本地建了仓库，远端也初始化过」。

```bash
git pull origin main --allow-unrelated-histories
```

然后解决冲突、提交。

---

## 4. 历史与找回

### 4.1 误删了分支

```bash
git reflog                              # 找删除前的 sha
git checkout -b 恢复的分支名 <sha>
```

`reflog` 输出长这样：

```
a1b2c3d HEAD@{0}: checkout: moving from feature to main
9f8e7d6 HEAD@{1}: commit: 最后一个提交
```

找到 `feature` 分支最后一刻的 sha，就能救回来。

---

### 4.2 误 reset --hard，提交没了

```bash
git reflog
git reset --hard HEAD@{2}      # 回到出事之前的位置
```

**关键区别**：

- **已提交**的内容 → `reflog` 里都在，能救
- **没提交**的内容 → `reset --hard` 直接删除，救不回来

这也是「勤提交」的真正理由——不是强迫症，是保险。

---

### 4.3 想撤销已推送的提交

```bash
git revert <sha>      # 推荐
git push
```

对比：

| 方式 | 改历史 | 别人要重新拉 | 适用 |
|---|---|---|---|
| `revert` | 否 | 否 | 共享分支，推荐 |
| `reset --hard` + 强推 | 是 | 是 | 私有仓库、自己的分支 |

---

### 4.4 rebase 搞乱了

```bash
git rebase --abort        # 回到 rebase 开始前
```

已经 rebase 完但结果不对：

```bash
git reflog                # 找 rebase 之前的位置
git reset --hard HEAD@{5}
```

---

### 4.5 合并冲突了

**先看清状态**：

```bash
git status                        # 哪些文件冲突
git diff --name-only --diff-filter=U    # 只列冲突文件
```

**放弃这次合并**：

```bash
git merge --abort         # merge 时
git rebase --abort        # rebase 时
git cherry-pick --abort   # cherry-pick 时
```

**逐个解决**：编辑文件（搜 `<<<<<<<`），然后：

```bash
git add <文件>
git rebase --continue     # 或 git merge --continue
```

**整份文件要某一方**：

```bash
git checkout --ours <文件>      # 保留当前分支版本
git checkout --theirs <文件>    # 保留对方版本
git add <文件>
```

⚠️ **rebase 时 ours/theirs 是反的**：rebase 中 `--ours` 指的是「你正在变基到的那个分支」
（通常是 main），`--theirs` 才是你正在变基的提交。不确定就打开文件看内容。

---

### 4.6 撤销一次 cherry-pick

```bash
git cherry-pick --abort          # 还没完成时
git reset --hard HEAD~1          # 已经完成、没推
git revert <sha>                 # 已经完成、推了
```

---

### 4.7 切换分支时提示本地改动会被覆盖

```
error: Your local changes to the following files would be overwritten by checkout
```

三选一：

```bash
git stash && git switch 目标分支 && git stash pop    # 保留改动
git commit -m "wip"                                  # 先提交
git restore <文件>                                   # 丢弃（改动不要了）
```

---

## 5. 文件与内容

### 5.1 大文件推不上去

```
remote: error: File xxx.zip is 128.00 MB; this exceeds GitHub's file size limit of 100.00 MB
remote: error: GH001: Large files detected.
```

**如果文件还没进历史**：

```bash
git rm --cached 大文件.zip
printf '大文件.zip\n' >> .gitignore
git commit -m "移除大文件"
```

**如果已经进历史**（推不上去就说明在历史里）：

```bash
pip install git-filter-repo
git filter-repo --path 大文件.zip --invert-paths
git push --force --all
```

**想保留文件但换成 LFS**：

```bash
git lfs install
git lfs migrate import --include="*.zip" --everything
git push --force --all
```

**检查谁是大头**：

```bash
git rev-list --objects --all \
  | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
  | awk '/^blob/ {print $3, $4}' | sort -rn | head -10
```

---

### 5.2 历史里有密钥或密码

**顺序：先撤销密钥，再清理历史。**（清理期间密钥可能已被扫走）

1. 去对应平台**作废**这个密钥
2. 从当前文件删掉，提交
3. 洗历史：

```bash
pip install git-filter-repo
git filter-repo --replace-text <(echo 'literal:AKIAIOSFODNN7EXAMPLE==>REMOVED')
git push --force --all
```

4. 检查对应账号有没有异常操作 / 账单变化
5. 情形严重时请求 GitHub 清理缓存：<https://github.com/contact>

**预防**：装 [`gitleaks`](https://github.com/gitleaks/gitleaks) 或
[`pre-commit`](https://github.com/pre-commit/pre-commit)，提交前就拦住。

---

### 5.3 想让已追踪文件不再被追踪（但保留本地）

```bash
git rm --cached config.local.json
printf 'config.local.json\n' >> .gitignore
git commit -m "不再追踪本地配置"
```

注意：这是**多人**场景（配置文件对所有人生效）。只想忽略**自己**的修改见 [§5.7](#57-只想忽略自己对本文件的修改)。

---

### 5.4 换行符导致"整个文件都改了"

```
warning: LF will be replaced by CRLF in xxx
```

**原因**：Windows 默认 `core.autocrlf=true`，把 LF 转成 CRLF 存进工作区，
提交时再转回 LF——两边不一致时，整个文件都显示被改。

**修法**：

```bash
# 1. 加 .gitattributes（治本）
cat > .gitattributes <<'EOF'
* text=auto eol=lf
*.bat  text eol=crlf
*.cmd  text eol=crlf
*.ps1  text eol=crlf
*.png  binary
EOF

# 2. 重新规范化
git add --renormalize .
git commit -m "统一换行为 LF"
```

```bash
# 3. 关掉自动转换（治标，只影响本机）
git config --global core.autocrlf false
```

---

### 5.5 中文文件名显示成转义序列

```
"\346\226\207\346\241\243.md"
```

```bash
git config --global core.quotepath false
```

只影响显示，不影响实际文件名。

---

### 5.6 文件名里有空格或特殊字符

```
fatal: pathspec 'my file.txt' did not match any files
```

加引号：

```bash
git add "my file.txt"
git add 'a[b].txt'
```

批量处理时用 `-z`（NUL 分隔）避免空格问题：

```bash
git ls-files -z | xargs -0 某个命令
```

---

### 5.7 只想忽略自己对本文件的修改

```bash
git update-index --skip-worktree config.local.json      # 忽略
git update-index --no-skip-worktree config.local.json   # 恢复
git ls-files -v | grep '^S'                             # 列出被忽略的
```

对比 `--assume-unchanged`：那个是**性能优化**用途，`git pull` 会覆盖它；
配置类文件用 `--skip-worktree` 更稳。

---

### 5.8 .gitattributes 或 .gitignore 带 BOM

```
统一换行 is not a valid attribute name: .gitattributes:1
```

**原因**：文件开头有 UTF-8 BOM（`EF BB BF`）。这两个文件是逐行纯文本解析的，
BOM 会被当成第一行的一部分，于是注释变成属性名、第一条规则变成带前缀的模式。

**怎么来的**：Windows PowerShell 5.1 的 `Set-Content -Encoding UTF8` 默认写 BOM。

**修法**：

```powershell
$enc = New-Object System.Text.UTF8Encoding($false)     # $false = 不加 BOM
[System.IO.File]::WriteAllLines('C:\path\.gitattributes', $lines, $enc)
```

**注意**：`.ps1` **要** BOM（否则 5.1 按 ANSI 解析成乱码），
`.gitattributes`/`.gitignore` **不能**要。两类文件要求相反。

---

### 5.9 空目录没被提交

git 不追踪空目录。想保留就在里面放个占位文件：

```bash
touch 空目录/.gitkeep
git add 空目录/.gitkeep
```

---

## 6. 认证与网络

### 6.1 一直要输密码或认证失败

```
fatal: Authentication failed for 'https://github.com/...'
remote: Support for password authentication was removed
```

**GitHub 早就不接受账号密码了，必须用 token。**

检查凭据助手：

```bash
git config --global credential.helper
```

- 空 → 没配，配一个：`git config --global credential.helper manager`（Windows）/
  `osxkeychain`（macOS）/ `cache --timeout=3600`（Linux）
- 配了但还是问 → 凭据存错了，清掉重来：

```bash
# Windows
cmdkey /list | findstr github
cmdkey /delete:git:https://github.com

# macOS
git credential-osxkeychain erase <<< $'protocol=https\nhost=github.com\n'
```

再来一次 `git push`，按提示输入**用户名 + token 当密码**。

---

### 6.2 Permission denied (publickey)

```
git@github.com: Permission denied (publickey).
fatal: Could not read from remote repository.
```

**排查顺序**：

```bash
ssh -T git@github.com          # 看具体提示
ssh-add -l                     # 密钥加载了吗
```

**① 没有密钥** → 生成一个（见主手册 §1.2）

**② 有密钥但没加到 GitHub** → `cat ~/.ssh/id_ed25519.pub`，粘到 <https://github.com/settings/keys>

**③ 密钥没被 SSH agent 加载**：

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

**④ 有多个密钥，用错了**：`~/.ssh/config` 里指定

```
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

---

### 6.3 TLS 连接被中断

```
schannel: failed to receive handshake, SSL/TLS connection failed
schannel: server closed abruptly (missing close_notify)
OpenSSL SSL_read: error:0A000126:SSL routines::unexpected eof while reading
error: RPC failed; curl 56 ... Recv failure: Connection reset by peer
```

**但浏览器能打开 GitHub** —— 说明是 git 单独的问题，通常与**代理**有关。

**① 检查代理设置**

```bash
git config --global --get http.proxy
git config --global --get https.proxy
echo $HTTP_PROXY $HTTPS_PROXY          # PowerShell: $env:HTTP_PROXY
```

系统代理开着但 git 没走，或者走了但代理不支持 git 的 TLS 握手——两种都会失败。

**② 试三种组合**

```bash
# 显式走代理
git config --global http.https://github.com.proxy http://127.0.0.1:7890

# 或者绕过代理直连
git config --global --unset http.https://github.com.proxy
git config --global http.https://github.com.proxy ""

# 临时换 TLS 后端
git -c http.sslBackend=openssl fetch
git -c http.version=HTTP/1.1 fetch
```

**③ 换协议**：HTTPS 不行试 SSH

```bash
git remote set-url origin git@github.com:用户名/仓库.git
```

**④ 换工具**：如果 `curl` 能访问 GitHub 但 git 不行，试试用 API 绕过 git 传输
（见主手册 §8.4）。

---

### 6.4 22 端口被封

```
ssh: connect to host github.com port 22: Connection timed out
```

公司/校园网常见。SSH 也能走 443：

`~/.ssh/config`：

```
Host github.com
  HostName ssh.github.com
  Port 443
  User git
```

验证：`ssh -T git@github.com`

---

### 6.5 同一台机器多个 GitHub 账号

**SSH 方式**——配多个 Host 别名：

```
# ~/.ssh/config
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
git remote set-url origin git@github-work:公司/仓库.git
```

**HTTPS 方式**——按 URL 存不同凭据：

```bash
git config --global credential.https://github.com.username 个人用户名
```

更彻底的做法是用 `includeIf` 按目录区分配置：

```
# ~/.gitconfig
[includeIf "gitdir:~/work/"]
  path = ~/.gitconfig-work
```

---

### 6.6 token 权限不足

```
remote: Permission to xxx denied to yyy.
```

**原因**：token 的 scope 不够。经典 token 需要：

- `repo` — 读写仓库（私有仓库必需）
- `workflow` — 推送 `.github/workflows/` 下的文件
- `read:org` — 操作组织仓库

**注意**：改 scope 要重新生成 token，旧 token 不会自动升级。

细粒度 token（fine-grained）还需要在仓库选择里**显式勾上目标仓库**，漏勾就是 403。

---

## 7. 仓库设置与 Release

### 7.1 中文描述变成问号

见主手册坑 1。修：`gh repo edit --description "中文描述"`。

### 7.2 Release 资产名被吃掉

中文在 URL 里被替换（`源码包.zip` → `-.-.zip`）。资产名用 ASCII，中文写正文。

### 7.3 默认分支不对

```bash
gh repo edit --default-branch main
```

或网页 Settings → Default branch。

本地同步：

```bash
git branch -M main
git push -u origin main
git remote set-head origin -a      # 更新本地的 origin/HEAD
```

### 7.4 想删 Release 或标签

```bash
# 只删 Release（标签保留）
gh release delete v1.0.0 --yes

# 标签一起删
git push origin --delete v1.0.0
git tag -d v1.0.0
```

### 7.5 仓库改名后本地推不动

```bash
git remote set-url origin https://github.com/用户名/新名字.git
git fetch origin
git branch --set-upstream-to=origin/main main
```

旧地址 GitHub 会重定向一段时间，但别依赖它。

### 7.6 fork 后同步上游

```bash
git remote add upstream https://github.com/原作者/仓库.git
git fetch upstream
git switch main
git merge upstream/main        # 或 rebase
git push origin main
```

想连 tag 一起同步：`git fetch upstream --tags && git push origin --tags`。

### 7.7 仓库太大，克隆很慢

```bash
git clone --depth 1 <url>              # 只拉最新一次提交
git clone --filter=blob:none <url>     # 部分克隆，按需拉文件
git clone --single-branch --branch main <url>
```

已克隆的可以瘦身：

```bash
git gc --prune=now --aggressive
```

---

## 8. 急救卡

一行命令，按需自取。

```bash
# 我在哪？这个目录属于哪个仓库？
pwd && git rev-parse --show-toplevel

# 我干了什么？（后悔药第一站）
git reflog -20

# 有什么没提交 / 没推送？
git status -sb && git log origin/main..HEAD --oneline

# 撤销上一次提交但保留改动
git reset --soft HEAD~1

# 撤销上一次提交并丢弃改动（危险）
git reset --hard HEAD~1

# 撤销已推送的提交（安全）
git revert <sha> && git push

# 放弃某文件的所有本地改动
git restore <file>

# 临时收起所有改动
git stash -u

# 拉取被拒后的标准动作
git pull --rebase && git push

# 找回误删分支
git reflog | grep <分支名>

# 撤回一次 rebase
git rebase --abort

# 看谁改的这行
git blame -L 10,20 <file>

# 哪个提交引入了这个 bug
git log -S "某个函数名" --oneline
```

---

## 9. 还是不行时

**① 先看清楚报错。** 九成的"救不回来"是因为只看了一半的报错。
把命令的完整输出贴出来，别用 `| grep` 滤掉——错误信息往往就在被滤掉的部分。

**② 确认状态，别看感觉。**

```bash
git log --oneline --graph --all -20
git status
git remote -v
git branch -vv
```

**③ 保底：先备份再折腾。**

```bash
cp -r 项目目录 项目目录.backup          # 粗暴但有效
# 或
git bundle create backup.bundle --all   # 完整历史打成一个文件
```

**④ 真的要重来。** 内容都在工作区的话，最干净的做法是重新开始：

```bash
rm -rf .git
git init -b main
git add -A && git commit -m "重新开始"
git remote add origin <url>
git push --force-with-lease
```

历史没了，但文件都在。**确认工作区是想要的内容再执行。**

**⑤ 查文档 / 问人。**

- [git-flight-rules](https://github.com/k88hudson/git-flight-rules) — 同样是「我干了 XX 怎么救」，场景更多
- [Oh Shit, Git!?!](https://ohshitgit.com/zh/) — 中文版，短平快
- Stack Overflow 搜报错原文（去掉具体路径和分支名）
- `git help <命令>` — 本地就有，比网上旧文章准

---

## 相关

- [主手册：把本地项目发布到 GitHub](../README.md)
- [命令速查（主手册 §9）](../README.md#9-命令速查)

## 许可

本手册采用 [AGPL-3.0-only](../LICENSE)。
