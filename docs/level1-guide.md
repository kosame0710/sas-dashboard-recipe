# レベル1：実用ミニマム ガイド

> **位置づけ**: レベル0が動いた後、本格運用への昇格手順
> **想定**: 5〜20人の部門で日常的に使うレベル
> **想定所要時間**: 1〜3日（環境による）
> **方針**: PowerShell + HTML/JS で完結。追加ソフトなし

本リポジトリの `sas/`、`server/`、`web/`、`config/` に格納されているサンプルコードは、本ガイドのレベル1構成と整合している。

---

## レベル0との差分

| 観点 | レベル0 | レベル1 |
|------|---------|---------|
| アクセス | file:// 単一ユーザー | http:// 複数ユーザー同時 |
| URL共有 | × | ◎ メール/Teamsで配布 |
| データ更新 | 手動 | 自動（タスクスケジューラ） |
| ログ | なし | ファイルログ |
| 設定 | コード内ハードコード | 外部設定ファイル |
| 複数ダッシュボード | 個別HTML | 1サーバで多ダッシュボード |
| エラー耐性 | サーバ概念なし | リトライ・障害通知 |
| Firewall | 不要 | 受信ルール設定 |

---

## 全体構成

```
[SASバッチサーバ or 共有マシン]
   │
   │ ① タスクスケジューラ（朝7時）
   ▼
   refresh_dashboard.ps1
   │
   │ ② SAS実行 → JSON出力
   ▼
   C:\dashboard\data\*.json
   │
   │ ③ JSON → data.js変換
   ▼
   C:\dashboard\web\dashboards\*\data.js
   │
[常時稼働Windowsマシン]
   │
   │ ④ システム起動時に自動実行
   ▼
   serve.ps1（HTTPサーバ）
   │
   │ ⑤ ポート 8080 でリッスン
   ▼
[各社員のブラウザ]
   http://[ホスト名]:8080/
```

---

## 1. ディレクトリ構造

```
C:\dashboard\
├── config\
│   └── server.config.json
├── sas\
│   ├── export_sales.sas
│   └── ...
├── data\                          ← SASが出力するJSON
├── web\
│   ├── index.html                 ← ダッシュボード一覧
│   ├── shared\                    ← 共通CSS/JS
│   │   ├── chart.umd.min.js
│   │   ├── dashboard.css
│   │   └── dashboard.js
│   └── dashboards\
│       ├── sales\
│       │   ├── index.html
│       │   └── data.js
│       └── ...
├── server\
│   ├── serve.ps1
│   ├── refresh_dashboard.ps1
│   ├── install_task.ps1
│   └── setup_firewall.ps1
└── logs\
```

作成コマンド:

```powershell
$root = "C:\dashboard"
$paths = @(
    "$root\config",
    "$root\sas",
    "$root\data",
    "$root\web\shared",
    "$root\web\dashboards\sales",
    "$root\server",
    "$root\logs"
)
foreach ($p in $paths) {
    New-Item -ItemType Directory -Path $p -Force | Out-Null
}
```

---

## 2. 設定ファイル

`C:\dashboard\config\server.config.json`:

```json
{
  "server": {
    "port": 8080,
    "bindAddress": "+",
    "rootDir": "C:\\dashboard\\web",
    "dataDir": "C:\\dashboard\\data",
    "logDir": "C:\\dashboard\\logs"
  },
  "logging": { "level": "INFO", "rotateDays": 7 },
  "security": { "enableBasicAuth": false, "allowedIps": [] },
  "dashboards": [
    { "id": "sales", "name": "月次売上", "dataFile": "sales_monthly.json" }
  ]
}
```

---

## 3. サンプルコードの配置

本リポジトリのルートから配置:

```
リポジトリ/sas/export_sample.sas       → C:\dashboard\sas\
リポジトリ/server/*.ps1                 → C:\dashboard\server\
リポジトリ/web/index.html               → C:\dashboard\web\
リポジトリ/web/shared/*                 → C:\dashboard\web\shared\
リポジトリ/web/dashboards/sales/*       → C:\dashboard\web\dashboards\sales\
リポジトリ/config/server.config.json    → C:\dashboard\config\
```

PowerShellで一括コピーする例:

```powershell
$src = "<repository-root>"
$dst = "C:\dashboard"
Copy-Item "$src\sas\*"     "$dst\sas\"    -Recurse -Force
Copy-Item "$src\server\*"  "$dst\server\" -Recurse -Force
Copy-Item "$src\web\*"     "$dst\web\"    -Recurse -Force
Copy-Item "$src\config\*"  "$dst\config\" -Recurse -Force
```

Chart.js のローカル版が必要な場合（社内でCDN制限がある場合）:

```powershell
Invoke-WebRequest `
    -Uri "https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js" `
    -OutFile "C:\dashboard\web\shared\chart.umd.min.js"
```

---

## 4. セットアップ手順（順番通り）

### Step 1: 環境準備

```powershell
Get-ExecutionPolicy
# Restricted の場合（必要なら）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Step 2: ディレクトリ作成・コード配置

上述のとおり。

### Step 3: Firewall・URL ACL設定（管理者）

```powershell
powershell -ExecutionPolicy Bypass -File "C:\dashboard\server\setup_firewall.ps1"
```

これで他PCからのHTTPアクセスと、非管理者でのサーバ起動が可能になる。

### Step 4: 手動でデータ更新テスト

```powershell
powershell -ExecutionPolicy Bypass -File "C:\dashboard\server\refresh_dashboard.ps1"
```

`C:\dashboard\logs\refresh.log` を確認。`data.js` が更新されていればOK。

### Step 5: HTTPサーバ手動起動・動作確認

```powershell
powershell -ExecutionPolicy Bypass -File "C:\dashboard\server\serve.ps1"
```

ブラウザで `http://localhost:8080/` を開く。
別PCから `http://[ホスト名]:8080/` でアクセスできるか確認。
`http://localhost:8080/health` でヘルスチェック応答確認。

### Step 6: タスクスケジューラ登録（管理者）

```powershell
powershell -ExecutionPolicy Bypass -File "C:\dashboard\server\install_task.ps1"
```

- データ更新タスク（毎朝7:00）
- サーバ起動タスク（システム起動時、落ちたら自動再起動）

---

## 5. 運用上のポイント

### ログ確認

```powershell
Get-Content C:\dashboard\logs\server.log -Tail 50
Get-Content C:\dashboard\logs\access.log -Tail 50
Get-Content C:\dashboard\logs\refresh.log -Tail 50

# ライブ監視
Get-Content C:\dashboard\logs\access.log -Wait -Tail 20
```

### サーバ停止・再起動

```powershell
Stop-ScheduledTask -TaskName "Dashboard-Server"
Start-ScheduledTask -TaskName "Dashboard-Server"
```

### ダッシュボード追加

1. `C:\dashboard\sas\export_xxx.sas` を追加
2. `C:\dashboard\config\server.config.json` の `dashboards` 配列に追記
3. `C:\dashboard\web\dashboards\xxx\index.html` を作成（既存をコピーして編集）
4. 次回データ更新（または手動実行）で反映

---

## 6. レベル2への昇格ポイント

以下が必要になったらレベル2（IIS + AD認証）への昇格を検討:

- 同時接続が20を超える
- 「誰が見た」の監査ログが必要になる
- HTTPS化が必要になる
- 既存IT運用プロセス（バックアップ、監視）に統合したい
- データ機密度が上がる

レベル1で構築した以下はレベル2でも**そのまま再利用**できる:

- HTMLダッシュボード一式
- 共通JS/CSS
- データスキーマ（JSON形式）
- SASスクリプト
- データ更新スクリプト

→ 移行コストは「サーバ層」のみ。DDDで関心を分離しておく価値。

---

## 7. トラブルシューティング

| 症状 | 原因と対処 |
|------|----------|
| 他PCからアクセス不可 | Firewall受信ルール確認、ホスト名解決確認、`netstat -an \| findstr 8080` |
| サーバが時々落ちる | `server.log` で例外確認。Runspace Poolが詰まっている可能性 |
| 同時アクセスで遅い | `serve.ps1` の `[runspacefactory]::CreateRunspacePool(1, 8)` の `8` を増やす |
| タスクスケジューラから動かない | 実行ユーザの権限確認、「最上位の特権で実行する」を有効化 |
| SASは動くが.json生成されない | SASログ確認、PROC JSONの出力先パスの書き込み権限 |
| 文字化け | すべてのファイルでUTF-8（BOMなし）統一、PowerShellは `-Encoding UTF8` 明示 |
| ログが肥大化 | `rotateDays` を短くする |

---

## 関連

- [構想と設計思想](concept.md)
- [クイックスタート（レベル0）](quickstart-level0.md)
