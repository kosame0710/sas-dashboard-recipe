# GitHubへの公開手順

このリポジトリをGitHubに公開する手順です。Windows PowerShell から実行してください。

---

## 前提

- Windows に git がインストール済みであること
  - 確認: `git --version`
  - 未インストールなら: https://git-scm.com/download/win からインストール
- GitHub アカウントを持っていること

---

## ステップ1: 中途半端な .git フォルダを削除（重要）

このフォルダは Linux 環境からの初期化途中で残った `.git` フォルダがあるため、まず削除します。

PowerShell（このリポジトリのフォルダを開いて）:

```powershell
cd "C:\Users\tamak\Desktop\IDEA\public-sas-dashboard"
Remove-Item .git -Recurse -Force -ErrorAction SilentlyContinue
```

---

## ステップ2: ローカルgitリポジトリを初期化

```powershell
git init -b main
git config user.email "soutakobayashi1007@gmail.com"
git config user.name "こばやし"
git add .
git status
git commit -m "Initial commit: SAS to Web Dashboard Recipe"
```

`git status` で意図しないファイル（個人情報を含むファイル等）が含まれていないことを確認してください。

---

## ステップ3: GitHubで空のリポジトリを作成

ブラウザで https://github.com/new を開いて、以下を設定:

| 項目 | 推奨値 |
|------|--------|
| Repository name | `sas-dashboard-recipe`（お好みで） |
| Description | `SAS to intranet web dashboard recipe with PowerShell + HTML/JS` |
| Public / Private | **Public**（公開したい場合） |
| Add README | **チェックしない**（既にあるため） |
| Add .gitignore | **None**（既にあるため） |
| Choose a license | **None**（既にあるため） |

「Create repository」を押す。

---

## ステップ4: リモート登録とpush

GitHubで作成したリポジトリのURLを使って、PowerShellで:

```powershell
# 自分のユーザー名とリポジトリ名に置き換える
git remote add origin https://github.com/<your-username>/sas-dashboard-recipe.git
git branch -M main
git push -u origin main
```

初回push時に認証を求められる場合があります。
- GitHub CLI（`gh auth login`）または
- パーソナルアクセストークン（PAT） を使用してください

GitHubのパスワード認証は2021年に廃止されているため、PATが必要です:
https://github.com/settings/tokens から `repo` 権限を持つトークンを発行 → push時にパスワードの代わりに使用。

---

## ステップ5: 公開確認

```
https://github.com/<your-username>/sas-dashboard-recipe
```

をブラウザで開いて、README.md が表示されればOK。

---

## ステップ6（任意）: トピック・説明の追加

GitHubのリポジトリページ右上の歯車アイコンから:

- **Topics**: `sas`, `powershell`, `dashboard`, `intranet`, `ddd`, `business-intelligence` などを追加
- **Description**: README の冒頭から1行サマリをコピー
- **Website**: 関連ブログがあれば

これで検索性が上がります。

---

## トラブルシューティング

### `git push` が "Permission denied" になる
PATを使うかGitHub CLIで認証してください。
```powershell
gh auth login
```

### push時に大量のWarning（CRLF/LF）が出る
無視してOK。または `.gitattributes` でルールを統一できます。

### 後から `.gitignore` 漏れに気付いた
```powershell
git rm --cached <file>
git commit -m "Remove accidentally committed file"
git push
```
※ 完全な履歴削除は `git filter-repo` 等が必要です。**機密情報を間違えてpushした場合は、まずトークン等のローテーションを行い、その後リポジトリ自体を作り直すのが最も安全です。**

---

## 一括スクリプト（オプション）

ステップ1〜2を一発で実行したい場合、以下を `setup_local_git.ps1` として保存して実行:

```powershell
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# 残骸の .git を削除
if (Test-Path .git) {
    Remove-Item .git -Recurse -Force
    Write-Host "既存の .git を削除しました" -ForegroundColor Yellow
}

# init
git init -b main
git config user.email "soutakobayashi1007@gmail.com"
git config user.name "こばやし"

# add & commit
git add .
git commit -m "Initial commit: SAS to Web Dashboard Recipe"

Write-Host ""
Write-Host "ローカル初期化完了。次:" -ForegroundColor Green
Write-Host "  1. https://github.com/new で空リポジトリを作成" -ForegroundColor Cyan
Write-Host "  2. git remote add origin https://github.com/<username>/<reponame>.git" -ForegroundColor Cyan
Write-Host "  3. git push -u origin main" -ForegroundColor Cyan
```

実行:
```powershell
powershell -ExecutionPolicy Bypass -File .\setup_local_git.ps1
```
