#!/usr/bin/env bash
# 把本地项目发布到 GitHub：隐私扫描 → 提交 → 建仓 → 推 → 标签 → Release → 验收
#
# 用法：
#   ./publish.sh --name my-app --description "一句话说明" --tag v1.0.0 --dry-run
#   ./publish.sh --name my-app --description "一句话说明" --tag v1.0.0
#
# 依赖：git、gh（可选，没有就退化到手动提示）、python3 或 zip（打源码包）

set -euo pipefail

NAME=""
DESC=""
TAG=""
VISIBILITY="public"
COMMIT_MSG=""
DRY_RUN=0
FORCE=0
SKIP_RELEASE=0
ROOT="$(pwd)"

usage() {
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)        NAME="$2"; shift 2 ;;
        --description) DESC="$2"; shift 2 ;;
        --tag)         TAG="$2"; shift 2 ;;
        --message)     COMMIT_MSG="$2"; shift 2 ;;
        --path)        ROOT="$2"; shift 2 ;;
        --private)     VISIBILITY="private"; shift ;;
        --public)      VISIBILITY="public"; shift ;;
        --dry-run)     DRY_RUN=1; shift ;;
        --force)       FORCE=1; shift ;;
        --skip-release) SKIP_RELEASE=1; shift ;;
        -h|--help)     usage ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[36m=== %s ===\033[0m\n' "$1"; }
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$1"; }
warn() { printf '  \033[33m注意\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m问题\033[0m %s\n' "$1"; PROBLEMS=$((PROBLEMS + 1)); }

PROBLEMS=0

cd "$ROOT"
step "目标：$ROOT"
[[ $DRY_RUN -eq 1 ]] && warn "dry-run：不推送、不建仓、不发 Release（本地 git init / add 照做，否则没法预演）"

command -v git >/dev/null || { echo "找不到 git"; exit 1; }

# ---------- 1. 仓库状态 ----------
if [[ ! -d .git ]]; then
    warn "这里还不是 git 仓库，现在初始化"
    git init -b main >/dev/null
    ok "已 git init -b main"
fi

branch="$(git branch --show-current || true)"
if [[ -n "$branch" && "$branch" != "main" ]]; then
    warn "当前分支是 $branch，改名为 main"
    git branch -M main
    ok "已改名"
fi

# ---------- 2. 忽略清单 ----------
ensure_file() {
    local path="$1" content="$2"
    if [[ ! -f "$path" ]]; then
        printf '%s\n' "$content" > "$path"
        ok "生成 $path"
    else
        ok "$path 已存在"
    fi
}

ensure_file .gitattributes '# 统一换行：源码 LF，Windows 脚本 CRLF
* text=auto eol=lf
*.sh  text eol=lf
*.bat text eol=crlf
*.cmd text eol=crlf
*.ps1 text eol=crlf
*.png binary
*.jpg binary
*.pdf binary
*.zip binary'

ensure_file .gitignore '# 运行数据、构建产物、密钥、个人文档
.venv/
venv/
node_modules/
__pycache__/
*.pyc
dist/
build/
out/
*.log
*.zip
*.key
*.pem
.env
.env.*
.DS_Store
Thumbs.db'

# ---------- 3. 暂存 ----------
git add -A
STAGED=$(git diff --cached --name-only | wc -l | tr -d ' ')
step "将提交 $STAGED 个文件"
[[ "$STAGED" -eq 0 ]] && warn "没有可提交的内容（已是最新，或都被 .gitignore 挡掉了）"

# ---------- 4. 隐私扫描 ----------
step "隐私扫描（暂存区）"

USERNAME_PAT="$(printf '%s' "${USER:-user}" | sed 's/[.[\*^$()+?{|]/\\&/g')"
PATTERNS=(
    "用户名|$USERNAME_PAT"
    "C盘用户目录|C:\\\\Users"
    "绝对路径|[A-Za-z]:\\\\"
    "QQ邮箱|qq\\.com"
    "手机号|[^0-9]1[3-9][0-9]{9}[^0-9]"
    "邮箱通用|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
    "IM账号|wxid_[a-z0-9]+"
    "疑似密钥|ghp_|github_pat_|sk-[A-Za-z0-9]{20,}"
)

# 正例自检：扫不出东西说明命令本身坏了
if ! git grep --cached -lIE '.' >/dev/null 2>&1; then
    CODE=$?
    if [[ $CODE -gt 1 ]]; then
        echo "隐私扫描无法运行（git grep 退出码 $CODE）——先修命令，别信 0 命中" >&2
        exit 1
    fi
fi
CONTROL=$(git grep --cached -lIE '.' 2>/dev/null | head -1 || true)
if [[ -z "$CONTROL" ]]; then
    echo "正例自检失败：暂存区里连一个字符都扫不到，结果不可信" >&2
    exit 1
fi

HITS=0
for entry in "${PATTERNS[@]}"; do
    label="${entry%%|*}"
    pat="${entry#*|}"
    out="$(git grep --cached -nIE "$pat" 2>/dev/null || true)"
    code=$?
    if [[ $code -gt 1 ]]; then
        echo "扫描「$label」时出错（退出码 $code）" >&2
        exit 1
    fi
    if [[ -n "$out" ]]; then
        n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
        HITS=$((HITS + n))
        bad "$label：$n 处"
        printf '%s\n' "$out" | head -4 | sed 's/^/        /'
    fi
done

if [[ $HITS -gt 0 ]]; then
    if [[ $FORCE -eq 1 ]]; then
        warn "命中 $HITS 处，--force 已指定，继续"
    else
        bad "命中 $HITS 处疑似隐私，已中止（确认无误加 --force）"
        exit 1
    fi
else
    ok "全部模式 0 命中（已过正例自检）"
fi

# ---------- 5. 大文件提醒 ----------
step "大文件检查"
BIG=$(git diff --cached --name-only | while read -r f; do
    [[ -f "$f" ]] || continue
    size=$(wc -c < "$f" | tr -d ' ')
    [[ "$size" -gt 5242880 ]] && printf '%s\t%s\n' "$((size / 1048576))" "$f"
done | sort -rn | head -5)
if [[ -n "$BIG" ]]; then
    warn "有文件超过 5 MB："
    printf '%s\n' "$BIG" | sed 's/^/        /'
else
    ok "没有超过 5 MB 的文件"
fi

# ---------- 6. 提交 ----------
if [[ "$STAGED" -gt 0 ]]; then
    MSG="${COMMIT_MSG:-发布 ${NAME:-$(basename "$ROOT")}}"
    if [[ $DRY_RUN -eq 1 ]]; then
        ok "会提交：$MSG"
    else
        git commit -q -m "$MSG"
        ok "已提交：$MSG"
    fi
fi

# ---------- 7. 建仓并推 ----------
step "建仓与推送"
HAS_GH=0
command -v gh >/dev/null && HAS_GH=1

REMOTE="$(git remote get-url origin 2>/dev/null || true)"
if [[ -n "$REMOTE" ]]; then
    ok "已有远端：$REMOTE"
    if [[ $DRY_RUN -eq 0 ]]; then
        git push -q origin main
        ok "已推送"
    fi
elif [[ $HAS_GH -eq 1 && -n "$NAME" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
        ok "会执行：gh repo create $NAME --source . --$VISIBILITY --push"
    else
        args=(repo create "$NAME" --source "$ROOT" --push "--$VISIBILITY")
        [[ -n "$DESC" ]] && args+=(-d "$DESC")
        gh "${args[@]}"
        ok "仓库已创建：https://github.com/$(gh api user --jq .login)/$NAME"
    fi
else
    warn "没有 gh 也没有远端。手动执行："
    echo "        gh repo create $NAME --source . --$VISIBILITY --push"
    echo "     或先在网页建仓，然后 git remote add origin <url> && git push -u origin main"
fi

# ---------- 8. Release ----------
if [[ -n "$TAG" && $SKIP_RELEASE -eq 0 ]]; then
    step "Release $TAG"
    if [[ $DRY_RUN -eq 1 ]]; then
        ok "会打标签 $TAG、生成源码包、gh release create"
    else
        git tag -a "$TAG" -m "${NAME:-project} $TAG" 2>/dev/null || true
        git push -q origin --tags 2>/dev/null || warn "标签推送失败（远端还没建好？）"

        PKG="${NAME:-project}-src-${TAG}.zip"
        git archive --prefix="${NAME:-project}/" -o "$PKG" HEAD
        ok "源码包 $(du -h "$PKG" | cut -f1) · $(unzip -l "$PKG" 2>/dev/null | tail -1 | awk '{print $2}') 个文件"

        if [[ $HAS_GH -eq 1 ]]; then
            gh release create "$TAG" "$PKG" --title "${NAME:-project} $TAG" \
               --notes "${DESC:-$TAG}" >/dev/null
            ok "Release 已发布"
        else
            warn "没有 gh，手动上传 $PKG"
        fi
        rm -f "$PKG"
    fi
fi

# ---------- 9. 验收 ----------
step "验收"
if [[ $DRY_RUN -eq 1 ]]; then
    warn "dry-run 跳过远端核对"
elif [[ $HAS_GH -eq 1 && -n "$NAME" ]]; then
    LOGIN=$(gh api user --jq .login)
    VIEW=$(gh repo view "$LOGIN/$NAME" --json name,defaultBranchRef,description,isPrivate 2>/dev/null || true)
    if [[ -n "$VIEW" ]]; then
        ok "仓库 $LOGIN/$(echo "$VIEW" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)"
        DESC_REMOTE=$(echo "$VIEW" | grep -o '"description":"[^"]*"' | cut -d'"' -f4 || true)
        if [[ "$DESC_REMOTE" == \?* ]]; then
            bad "描述是乱码，用 gh repo edit 重设"
        else
            ok "描述：$DESC_REMOTE"
        fi
    fi
    REMOTE_COUNT=$(gh api "repos/$LOGIN/$NAME/git/trees/main?recursive=1" \
        --jq '[.tree[]|select(.type=="blob")]|length' 2>/dev/null || echo "?")
    ok "远端文件数 $REMOTE_COUNT（本地追踪 $(git ls-files | wc -l | tr -d ' ')）"
    gh run list --limit 1 --json conclusion,workflowName \
        --jq '.[]|"  OK   CI：\(.workflowName) → \(.conclusion)"' 2>/dev/null || true
fi

step "完成"
if [[ $PROBLEMS -gt 0 ]]; then
    printf '\033[33m有 %d 个问题需要处理\033[0m\n' "$PROBLEMS"
    exit 1
fi
printf '\033[32m全部通过。\033[0m\n'
