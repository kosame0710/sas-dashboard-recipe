// ===================================================================
// 共通ダッシュボードロジック（SAS非依存・複数ダッシュボードで再利用）
// ===================================================================

const Dashboard = (() => {
    /**
     * データ読み込み:
     *   1. data.js が先に読まれていれば window.DASHBOARD_DATA を使う
     *   2. なければ apiPath から fetch
     */
    async function loadData(apiPath) {
        if (window.DASHBOARD_DATA) return window.DASHBOARD_DATA;
        if (apiPath) {
            const res = await fetch(apiPath);
            if (!res.ok) throw new Error(`データ取得失敗: ${res.status}`);
            return await res.json();
        }
        throw new Error("データソースが設定されていません");
    }

    /** メタ情報レンダリング */
    function renderMeta(payload, elementId = "meta") {
        const el = document.getElementById(elementId);
        if (!el) return;
        const m = payload.meta || {};
        el.textContent = `${m.report_name || ''} / 生成: ${m.generated_at || '-'} / 行数: ${m.row_count || '-'}`;
    }

    /** カテゴリフィルタの自動生成 */
    function buildFilter(rows, fieldName, selectId, onChange) {
        const select = document.getElementById(selectId);
        if (!select) return;
        const cats = [...new Set(rows.map(r => r[fieldName]))].sort();
        select.innerHTML = '<option value="all">すべて</option>';
        for (const c of cats) {
            const opt = document.createElement('option');
            opt.value = c; opt.textContent = c;
            select.appendChild(opt);
        }
        select.addEventListener('change', e => onChange(e.target.value));
    }

    /** Chart.js グラフを統一インタフェースで描画 */
    let chartInstances = {};
    function renderChart(canvasId, type, labels, datasets) {
        const ctx = document.getElementById(canvasId).getContext('2d');
        if (chartInstances[canvasId]) chartInstances[canvasId].destroy();
        chartInstances[canvasId] = new Chart(ctx, {
            type, data: { labels, datasets },
            options: { responsive: true, maintainAspectRatio: false }
        });
    }

    /** テーブル描画 */
    function renderTable(tableId, rows, columns) {
        const tbody = document.querySelector(`#${tableId} tbody`);
        const thead = document.querySelector(`#${tableId} thead`);
        if (thead) {
            thead.innerHTML = '<tr>' + columns.map(c => `<th>${c.label}</th>`).join('') + '</tr>';
        }
        tbody.innerHTML = '';
        for (const r of rows) {
            const tr = document.createElement('tr');
            tr.innerHTML = columns.map(c => {
                const v = r[c.field];
                const isNum = typeof v === 'number';
                const formatted = isNum ? v.toLocaleString() : (v ?? '');
                return `<td class="${isNum ? 'num' : ''}">${formatted}</td>`;
            }).join('');
            tbody.appendChild(tr);
        }
    }

    /** 集計関数（汎用） */
    function groupSum(rows, groupBy, sumField) {
        const map = new Map();
        for (const r of rows) {
            map.set(r[groupBy], (map.get(r[groupBy]) || 0) + Number(r[sumField] || 0));
        }
        return [...map.entries()].sort().map(([k, v]) => ({ key: k, value: v }));
    }

    return { loadData, renderMeta, buildFilter, renderChart, renderTable, groupSum };
})();
