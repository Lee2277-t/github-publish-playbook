<#
.SYNOPSIS
    把本地项目发布到 GitHub：隐私扫描 → 提交 → 建仓 → 推 → 标签 → Release → 验收。

.EXAMPLE
    .\publish.ps1 -Name my-app -Description "一句话说明" -Tag v1.0.0 -DryRun

.EXAMPLE
    .\publish.ps1 -Name my-app -Description "一句话说明" -Tag v1.0.0

.NOTES
    隐私扫描命中时默认中止；确认无误再加 -Force。
    -DryRun 只做本地预演，不推送、不建仓、不发 Release。
    本文件请保存为 UTF-8 with BOM，否则 Windows PowerShell 5.1 会按 ANSI 解析导致语法错。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Description = '',
    [string]$Tag = '',
    [string]$Path = '.',
    [ValidateSet('public', 'private')][string]$Visibility = 'public',
    [string]$CommitMessage = '',
    [switch]$Force,
    [switch]$DryRun,
    [switch]$SkipRelease
)

$ErrorActionPreference = 'Continue'
$script:problems = @()

function Write-Step($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Ok($text) { Write-Host "  OK   $text" -ForegroundColor Green }
function Write-Warn($text) { Write-Host "  注意 $text" -ForegroundColor Yellow }
function Write-Bad($text) { Write-Host "  问题 $text" -ForegroundColor Red; $script:problems += $text }

$root = (Resolve-Path $Path).Path
$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) { throw '找不到 git，先安装：https://git-scm.com/downloads' }

function Invoke-PrivacyScan {
    <# 扫暂存区。--cached 必须排在模式前面，否则 git 直接 fatal，# 返回空看起来像"没命中"。 #>
    $patterns = [ordered]@{
        '用户名'      = [regex]::Escape($env:USERNAME)
        'C盘用户路径' = 'C:\\Users'
        '绝对路径'    = '[A-Za-z]:\\'
        'QQ邮箱'      = 'qq\.com'
        '手机号'      = '[^0-9]1[3-9][0-9]{9}[^0-9]'
        '邮箱通用'    = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
        'IM账号'      = 'wxid_[a-z0-9]+'
        '疑似密钥'    = 'ghp_|github_pat_|sk-[A-Za-z0-9]{20,}'
    }

    # 正例自检：扫不出东西就说明命令坏了，此时的 0 命中不算证据
    $control = & $git -C $root grep --cached -lIE '.' 2>$null
    if ($LASTEXITCODE -gt 1) { throw "隐私扫描无法运行（git grep 退出码 $LASTEXITCODE）" }
    if (-not $control) { throw '正例自检失败：暂存区里连一个字符都扫不到，结果不可信' }

    $hits = 0
    foreach ($key in $patterns.Keys) {
        $result = & $git -C $root grep --cached -nIE $patterns[$key] 2>$null
        if ($LASTEXITCODE -gt 1) { throw "扫描「$key」时出错（退出码 $LASTEXITCODE）" }
        if ($result) {
            $count = ($result | Measure-Object).Count
            $hits += $count
            Write-Bad "$key：$count 处"
            $result | Select-Object -First 4 | ForEach-Object {
                Write-Host "        $(if ($_.Length -gt 120) { $_.Substring(0,120) } else { $_ })" -ForegroundColor DarkGray
            }
        }
    }
    return $hits
}

function Ensure-File($path, $content) {
    if (-not (Test-Path $path)) {
        # .gitattributes / .gitignore 不能带 BOM：BOM 会被当成第一行内容，注释变属性名、首条规则失效
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($path, $content, $enc)
        Write-Ok "生成 $(Split-Path $path -Leaf)（无 BOM）"
    } else {
        Write-Ok "$(Split-Path $path -Leaf) 已存在"
    }
}

# ---------- 1. 仓库状态 ----------
Write-Step "目标：$root"
if ($DryRun) { Write-Warn 'DryRun：不推送、不建仓、不发 Release' }

if (-not (Test-Path (Join-Path $root '.git'))) {
    Write-Warn '还不是 git 仓库，现在初始化'
    & $git -C $root init -b main 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok '已 git init -b main' }
}

$branch = (& $git -C $root branch --show-current 2>$null | Select-Object -First 1)
if ($branch -and $branch -ne 'main') {
    Write-Warn "当前分支是 $branch，改名为 main"
    & $git -C $root branch -M main 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok '已改名' }
}

# ---------- 2. 忽略清单 ----------
Ensure-File (Join-Path $root '.gitattributes') @(
    '# 统一换行：源码 LF，Windows 脚本 CRLF，二进制不转换'
    '* text=auto eol=lf'
    '*.sh  text eol=lf'
    '*.bat text eol=crlf'
    '*.cmd text eol=crlf'
    '*.ps1 text eol=crlf'
    '*.png binary'
    '*.jpg binary'
    '*.pdf binary'
    '*.zip binary'
)

Ensure-File (Join-Path $root '.gitignore') @(
    '# 运行数据、构建产物、密钥、个人文档'
    '.venv/'
    'venv/'
    'node_modules/'
    '__pycache__/'
    '*.pyc'
    'dist/'
    'build/'
    'out/'
    '*.log'
    '*.zip'
    '*.key'
    '*.pem'
    '.env'
    '.env.*'
    '.DS_Store'
    'Thumbs.db'
)

# ---------- 3. 暂存 ----------
& $git -C $root -c core.autocrlf=false add -A 2>$null
$staged = @(& $git -C $root diff --cached --name-only 2>$null)
Write-Step "将提交 $($staged.Count) 个文件"
if ($staged.Count -eq 0) { Write-Warn '没有可提交的内容（已是最新，或都被 .gitignore 挡掉了）' }

# ---------- 4. 隐私扫描 ----------
Write-Step '隐私扫描（暂存区）'
$hits = Invoke-PrivacyScan
if ($hits -gt 0) {
    if (-not $Force) {
        Write-Bad "命中 $hits 处疑似隐私，已中止。确认无误再加 -Force"
        throw '隐私扫描未通过'
    }
    Write-Warn "命中 $hits 处，-Force 已指定，继续"
} else {
    Write-Ok '全部模式 0 命中（已过正例自检）'
}

# ---------- 5. 大文件 ----------
Write-Step '大文件检查'
$big = $staged | ForEach-Object {
    $p = Join-Path $root ($_ -replace '/', '\')
    if (Test-Path $p) { Get-Item $p }
} | Where-Object { $_.Length -gt 5MB } | Sort-Object Length -Descending
if ($big) {
    Write-Warn "有 $($big.Count) 个文件超过 5 MB"
    $big | Select-Object -First 5 | ForEach-Object {
        Write-Host ("        {0}  {1} MB" -f $_.Name, [math]::Round($_.Length / 1MB, 1)) -ForegroundColor DarkGray
    }
} else {
    Write-Ok '没有超过 5 MB 的文件'
}

# ---------- 6. 提交 ----------
if ($staged.Count -gt 0) {
    $msg = if ($CommitMessage) { $CommitMessage } else { "发布 $Name" }
    if ($DryRun) { Write-Ok "会提交：$msg" }
    else {
        & $git -C $root -c core.autocrlf=false commit -q -m $msg
        if ($LASTEXITCODE -eq 0) { Write-Ok "已提交：$msg" } else { Write-Bad '提交失败' }
    }
}

# ---------- 7. 建仓并推 ----------
Write-Step '建仓与推送'
$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
$remote = (& $git -C $root remote get-url origin 2>$null)
if ($remote) {
    Write-Ok "已有远端：$remote"
    if (-not $DryRun) {
        & $git -C $root push -q origin main
        if ($LASTEXITCODE -eq 0) { Write-Ok '已推送' } else { Write-Bad '推送失败，看完整输出' }
    }
} elseif ($gh) {
    if ($DryRun) { Write-Ok "会执行：gh repo create $Name --source . --$Visibility --push" }
    else {
        $ghArgs = @('repo', 'create', $Name, '--source', $root, '--push', "--$Visibility")
        if ($Description) { $ghArgs += @('--description', $Description) }
        & $gh @ghArgs
        if ($LASTEXITCODE -eq 0) {
            $login = & $gh api user --jq .login
            Write-Ok "仓库已创建：https://github.com/$login/$Name"
        } else { Write-Bad '建仓失败' }
    }
} else {
    Write-Warn '没有 gh 也没有远端，手动执行：'
    Write-Host "        gh repo create $Name --source . --$Visibility --push"
    Write-Host '     或网页建仓后：git remote add origin <url> && git push -u origin main'
}

# ---------- 8. Release ----------
if ($Tag -and -not $SkipRelease) {
    Write-Step "Release $Tag"
    if ($DryRun) {
        Write-Ok "会打标签 $Tag、生成源码包、发 Release"
    } else {
        if (-not (& $git -C $root tag --list $Tag)) {
            & $git -C $root tag -a $Tag -m "$Name $Tag"
        }
        & $git -C $root push -q origin --tags 2>$null

        $pkg = Join-Path $env:TEMP "$Name-src-$Tag.zip"
        & $git -C $root archive --prefix="$Name/" -o $pkg HEAD
        if (Test-Path $pkg) {
            Write-Ok "源码包 $([math]::Round((Get-Item $pkg).Length / 1KB, 1)) KB"
            if ($gh) {
                & $gh release create $Tag $pkg --title "$Name $Tag" --notes $(if ($Description) { $Description } else { $Tag })
                if ($LASTEXITCODE -eq 0) { Write-Ok 'Release 已发布' } else { Write-Bad 'Release 失败' }
            } else { Write-Warn "没有 gh，手动上传 $pkg" }
            Remove-Item $pkg -Force -ErrorAction SilentlyContinue
        } else { Write-Bad '源码包生成失败' }
    }
}

# ---------- 9. 验收 ----------
Write-Step '验收'
if ($DryRun) {
    Write-Warn 'DryRun 跳过远端核对'
} elseif ($gh) {
    $login = & $gh api user --jq .login
    $view = & $gh repo view "$login/$Name" --json name,defaultBranchRef,description 2>$null | ConvertFrom-Json
    if ($view) {
        Write-Ok "仓库 $login/$($view.name) · 默认分支 $($view.defaultBranchRef.name)"
        if ($view.description -match '^\?') { Write-Bad '描述是乱码，用 gh repo edit 重设' }
        else { Write-Ok "描述：$($view.description)" }
    }
    $treeCount = & $gh api "repos/$login/$Name/git/trees/main?recursive=1" --jq '[.tree[]|select(.type=="blob")]|length' 2>$null
    if ($treeCount) {
        Write-Ok "远端文件数 $treeCount（本地追踪 $((& $git -C $root ls-files | Measure-Object).Count)）"
    }
    $run = & $gh run list --limit 1 --json workflowName,conclusion 2>$null | ConvertFrom-Json
    if ($run) { Write-Ok "最近 CI：$($run[0].workflowName) → $($run[0].conclusion)" }
}

Write-Step '完成'
if ($script:problems.Count -gt 0) {
    Write-Host "有 $($script:problems.Count) 个问题需要处理：" -ForegroundColor Yellow
    $script:problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    exit 1
}
Write-Host '全部通过。' -ForegroundColor Green
