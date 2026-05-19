# SAS to Web Dashboard Recipe

> SAS で集計しているデータを、社内ネットワーク内限定の Web ダッシュボードへ最小コストで橋渡しするためのレシピ集。
> PowerShell + HTML/JS のみで構成し、追加ソフト・新規サーバ・クラウド利用なしに動かせる構成を目指す。

A practical recipe for bridging SAS-aggregated data to lightweight, intranet-only web dashboards — using only PowerShell and plain HTML/JS, with no new software or cloud dependencies.

---

## なぜこれを書いたか

社内環境で SAS を業務利用しているケースは多いが、その出力先は依然として Excel 帳票が中心という現場が少なくない。Excel の限界（同時参照性、最新性、可視化）に直面したとき、本格的な BI ツール（Tableau / Power BI / SAS Visual Analytics 等）の導入は、コスト・承認プロセス・運用負荷の壁が大きい。

一方で、PowerShell が現場で利用可能であれば、追加ソフト導入ゼロで「動くダッシュボード」を立ち上げることが可能。本リポジトリは、その最小構成と段階的な昇格パスを、コピペで動くサンプルコード付きで記述する。

設計思想として、データ取得（SAS）、配信（PowerShell HTTP サーバ）、表示（HTML/JS）の関心を明確に分離し、将来データソース・配信方式・表示技術いずれが変わっても、他層への影響を最小化することを志向する。

---

## 構成

```
sas-dashboard-recipe/
├── docs/                      ドキュメント
│   ├── concept.md              アーキテクチャ構想・DDDの適用
│   ├── quickstart-level0.md    最速着手版（半日〜1日）
│   └── level1-guide.md         本格運用版（1〜3日）
├── sas/                       SAS スクリプト
│   └── export_sample.sas
├── web/                       フロントエンド
│   ├── index.html
│   ├── shared/
│   │   ├── dashboard.css
│   │   └── dashboard.js
│   └── dashboards/
│       └── sales/
│           └── index.html
└── server/                    PowerShell スクリプト
    ├── serve.ps1               HTTPサーバ本体
    ├── refresh_dashboard.ps1   データ更新ジョブ
    ├── setup_firewall.ps1      Firewall・URL ACL設定
    ├── install_task.ps1        タスクスケジューラ登録
    └── convert_json_to_js.ps1  JSON → data.js 変換（レベル0用）
```

---

## レベル別の構成

本リポジトリは段階的な3レベル構成を提示する。最初から本格構成を作るのではなく、**「必要になったら昇格する」** ことを推奨する。

| レベル | 概要 | 想定規模 | 着手 |
|--------|------|----------|------|
| 0 | `file://` で開く静的HTML | 1〜数人、PoC | 半日〜1日 |
| 1 | PowerShell HTTPサーバ | 5〜20人、部門利用 | 1〜3日 |
| 2 | IIS + AD認証 | 全社・本格運用 | 1〜数週 |

このリポジトリはレベル 0 と 1 を対象とする。レベル 2 への昇格時に作業をやり直さなくて済むよう、関心分離を意識した構成を取っている。

詳細は [docs/concept.md](docs/concept.md) を参照。

---

## クイックスタート

### 最速ルート（レベル 0）

[docs/quickstart-level0.md](docs/quickstart-level0.md) に沿って、コピペで動かす。
半日で「ブラウザで開くダッシュボード」までたどり着くことを目標としている。

### 実用構成（レベル 1）

[docs/level1-guide.md](docs/level1-guide.md) に沿って、PowerShell HTTP サーバを立ち上げる。
複数ユーザーでの同時参照、自動更新、ログ、サービス化までを含む。

---

## 動作環境

- Windows Server / Windows 10/11
- PowerShell 5.1 以上
- SAS 9.4 以降（`PROC JSON` を使用するため）
- モダンブラウザ（Edge / Chrome 推奨）

---

## 設計の考え方

詳細は [docs/concept.md](docs/concept.md) を参照。要点のみ：

- **ドメイン層は SAS を知らない** — 「指標」「帳票」「断面」といった業務概念のみを扱う
- **SAS と Web 層の境界に契約（スキーマ）を置く** — `meta` ブロックを必ず含める
- **PowerShell をグルー言語兼簡易バックエンドとして活用** — 追加ランタイム不要
- **静的ファイル→簡易HTTP→IISの3段階で漸進的に昇格** — 作り直しではなく積み増し

---

## ライセンス

MIT License。詳細は [LICENSE](LICENSE) を参照。

---

## 想定されない用途・注意事項

- 機密データを扱う場合、本構成のセキュリティは十分ではない。レベル 2 への昇格、または別途の暗号化・認証実装を要する。
- HTTPS 化は本構成では扱っていない（社内ネットワーク内限定を前提）。
- 本リポジトリのコードは「動くサンプル」であり、本番運用時はそれぞれの現場の制約・要件に応じた調整が必要。
