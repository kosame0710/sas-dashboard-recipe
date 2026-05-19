<#
.SYNOPSIS
    ローカルgitリポジトリの初期化を一発で行うスクリプト

.DESCRIPTION
    1. 残骸の .git フォルダを削除
    2. git init
    3. user.email / user.name 設定
    4. 全ファイル add & 初回 commit

.NOTES
    実行後、GitHubで空リポジトリを作成して以下を実行:
        git remote add origin https://github.com/<username>/<reponame>.git
        git push -u origin main
#>

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# 残骸の .git を削除
if (Test-Path .git) {
    Write-Host "既存の .git フォルダを削除中..." -ForegroundColor Yellow
    Remove-Item .git -Recurse -Force
    Write-Host "  削除完了" -ForegroundColor Gray
}

# init
Write-Host ""
Write-Host "git init..." -ForegroundColor Cyan
git init -b main
git config user.email "soutakobayashi1007@gmail.com"
git config user.name "こばやし"

# add & commit
Write-Host ""
Write-Host "ファイル追加・初回コミット..." -ForegroundColor Cyan
git add .
git status --short
git commit -m "Initial commit: SAS to Web Dashboard Recipe"

Write-Host ""
Write-Host "===== ローカル初期化完了 =====" -ForegroundColor Green
Write-Host ""
Write-Host "次の手順:" -ForegroundColor Yellow
Write-Host "  1. ブラウザで https://github.com/new を開いて空リポジトリを作成"
Write-Host "     - Repository name: sas-dashboard-recipe（推奨）"
Write-Host "     - Add README/`.gitignore/License は すべて チェックしない"
Write-Host ""
Write-Host "  2. 作成したリポジトリURLを使って以下を実行:"
Write-Host "     git remote add origin https://github.com/<your-username>/sas-dashboard-recipe.git" -ForegroundColor Cyan
Write-Host "     git push -u origin main" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ※ push時に認証を求められた場合:" -ForegroundColor Gray
Write-Host "     - GitHub CLIを使う: gh auth login" -ForegroundColor Gray
Write-Host "     - またはPATを発行: https://github.com/settings/tokens" -ForegroundColor Gray
