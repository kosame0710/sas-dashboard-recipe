<#
.SYNOPSIS
    JSON ファイルを data.js に変換する（レベル0 / file:// 利用時に必要）

.DESCRIPTION
    file:// でブラウザを開くと fetch() が制限されるため、
    JSONを <script src="data.js"> で読み込めるよう window 変数に埋め込む。
#>

[CmdletBinding()]
param(
    [string]$JsonPath = "C:\dashboard\data\sales_monthly.json",
    [string]$OutputJsPath = "C:\dashboard\web\dashboards\sales\data.js"
)

$json = Get-Content $JsonPath -Raw -Encoding UTF8
$jsContent = "window.DASHBOARD_DATA = $json;"
Set-Content -Path $OutputJsPath -Value $jsContent -Encoding UTF8
Write-Host "data.js を更新しました: $OutputJsPath" -ForegroundColor Green
