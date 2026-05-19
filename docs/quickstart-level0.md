# クイックスタート（レベル0）

> **対象**: 最速で動くダッシュボードを作る
> **想定所要時間**: 半日〜1日
> **方針**: 動くものを最速で作って、業務担当者に「見せて」反応を見る
> **構成**: `file://` でブラウザを開く静的版（サーバ不要）

---

## 0. 事前準備（5分）

以下のフォルダを作成:

```
C:\dashboard-poc\
├── sas\          ← SASスクリプト置き場
├── data\         ← SASが出力するJSON置き場
├── web\          ← HTML/JS/CSS置き場
└── server\       ← PowerShell補助スクリプト
```

PowerShell:

```powershell
New-Item -ItemType Directory -Path `
    "C:\dashboard-poc\sas", `
    "C:\dashboard-poc\data", `
    "C:\dashboard-poc\web", `
    "C:\dashboard-poc\server" -Force
```

---

## 1. SAS側：JSON出力スクリプト

`C:\dashboard-poc\sas\export_sample.sas` として保存（[sas/export_sample.sas](../sas/export_sample.sas) と同等内容）:

```sas
/* サンプル：売上データの月次集計を JSON 出力 */
data work.sales_monthly;
    length category $20;
    do category = "食品", "日用品", "家電", "衣料";
        do month = 1 to 12;
            yyyymm = put(year(today())*100 + month, 6.);
            amount = round(ranuni(0)*1000000 + 500000, 1000);
            output;
        end;
    end;
run;

filename outjson "C:\dashboard-poc\data\sales_monthly.json" encoding="utf-8";

proc json out=outjson pretty nosastags;
    write open object;
    write values "meta";
    write open object;
    write values "report_name" "月次売上";
    write values "generated_at" "%sysfunc(datetime(), E8601DT.)";
    write values "row_count";
    write values 48;
    write close;
    write values "data";
    export work.sales_monthly;
    write close;
run;

filename outjson clear;
```

SAS で実行 → `C:\dashboard-poc\data\sales_monthly.json` ができていればOK。

---

## 2. JSON → data.js 変換（file:// 対応）

`file://` で開く場合、ブラウザの `fetch()` が制限されるため、JSONを `data.js` として読めるようにする。

`C:\dashboard-poc\server\convert_json_to_js.ps1`:

```powershell
$json = Get-Content "C:\dashboard-poc\data\sales_monthly.json" -Raw -Encoding UTF8
$jsContent = "window.DASHBOARD_DATA = $json;"
Set-Content -Path "C:\dashboard-poc\web\data.js" -Value $jsContent -Encoding UTF8
Write-Host "data.js を更新しました"
```

実行:
```powershell
powershell -ExecutionPolicy Bypass -File "C:\dashboard-poc\server\convert_json_to_js.ps1"
```

---

## 3. HTML

`C:\dashboard-poc\web\index.html`:

```html
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <title>月次売上ダッシュボード</title>
    <style>
        body { font-family: "Yu Gothic UI", "Meiryo", sans-serif; margin: 24px; background: #f5f7fa; color: #222; }
        h1 { font-size: 20px; margin: 0 0 4px; }
        .meta { color: #666; font-size: 12px; margin-bottom: 16px; }
        .card { background: white; border-radius: 8px; padding: 16px; box-shadow: 0 1px 3px rgba(0,0,0,.08); margin-bottom: 16px; }
        table { border-collapse: collapse; width: 100%; font-size: 13px; }
        th, td { border-bottom: 1px solid #eee; padding: 6px 10px; text-align: left; }
        th { background: #f0f4f8; }
        td.num { text-align: right; font-variant-numeric: tabular-nums; }
        canvas { max-height: 320px; }
        select { padding: 4px 8px; }
    </style>
</head>
<body>
    <h1 id="title">月次売上ダッシュボード</h1>
    <div class="meta" id="meta"></div>

    <div class="card">
        <div>
            カテゴリ：
            <select id="categoryFilter"><option value="all">すべて</option></select>
        </div>
        <canvas id="chart"></canvas>
    </div>

    <div class="card">
        <table id="dataTable">
            <thead><tr><th>カテゴリ</th><th>年月</th><th class="num">金額</th></tr></thead>
            <tbody></tbody>
        </table>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <script src="data.js"></script>
    <script>
        function summarizeByMonth(rows) {
            const map = new Map();
            for (const r of rows) {
                map.set(r.yyyymm, (map.get(r.yyyymm) || 0) + Number(r.amount));
            }
            return [...map.entries()].sort().map(([k, v]) => ({ yyyymm: k, amount: v }));
        }

        let chartInstance;
        function renderChart(summary) {
            const ctx = document.getElementById('chart').getContext('2d');
            if (chartInstance) chartInstance.destroy();
            chartInstance = new Chart(ctx, {
                type: 'bar',
                data: {
                    labels: summary.map(s => s.yyyymm),
                    datasets: [{ label: '売上', data: summary.map(s => s.amount) }]
                },
                options: { responsive: true, maintainAspectRatio: false }
            });
        }

        function renderTable(rows) {
            const tbody = document.querySelector('#dataTable tbody');
            tbody.innerHTML = '';
            for (const r of rows) {
                const tr = document.createElement('tr');
                tr.innerHTML = `<td>${r.category}</td><td>${r.yyyymm}</td><td class="num">${Number(r.amount).toLocaleString()}</td>`;
                tbody.appendChild(tr);
            }
        }

        (async () => {
            const payload = window.DASHBOARD_DATA;
            document.getElementById('meta').textContent =
                `${payload.meta.report_name} / 生成: ${payload.meta.generated_at} / 行数: ${payload.meta.row_count}`;

            const select = document.getElementById('categoryFilter');
            const cats = [...new Set(payload.data.map(r => r.category))].sort();
            for (const c of cats) {
                const opt = document.createElement('option');
                opt.value = c; opt.textContent = c;
                select.appendChild(opt);
            }

            function update(filter) {
                const rows = filter === 'all' ? payload.data : payload.data.filter(r => r.category === filter);
                renderChart(summarizeByMonth(rows));
                renderTable(rows);
            }

            update('all');
            select.addEventListener('change', e => update(e.target.value));
        })();
    </script>
</body>
</html>
```

`index.html` をダブルクリック（or ブラウザにドラッグ）すれば表示される。

---

## 4. 確認のチェックリスト

- [ ] PowerShellのバージョン確認: `$PSVersionTable.PSVersion`（5.1以上推奨）
- [ ] PowerShell実行ポリシー: `Get-ExecutionPolicy`（`Restricted` なら起動時に `-ExecutionPolicy Bypass`）
- [ ] SASのインストール先パス（`sas.exe` の場所）
- [ ] SASバージョン（PROC JSONは9.4以降）
- [ ] ブラウザ（Edge/Chrome）

---

## 5. トラブルシューティング

| 症状 | 原因と対処 |
|------|----------|
| SAS実行で文字化け | `encoding="utf-8"` を指定（サンプルに記載済） |
| ブラウザでJSONが読めない | `file://` のfetch制限。`data.js` 方式に切り替え |
| Chart.jsが表示されない | 社内CDN禁止の可能性。`chart.umd.min.js` をローカル保存して `<script src="chart.umd.min.js">` に変更 |
| 文字エンコーディングの問題 | PowerShellで `-Encoding UTF8` を明示 |

---

## 6. 次のステップ

レベル0が動いたら、[level1-guide.md](level1-guide.md) に進む。
複数人での同時参照、自動更新、ログ、サービス化までを扱う。
