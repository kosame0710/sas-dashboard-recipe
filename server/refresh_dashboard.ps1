<#
.SYNOPSIS
    SAS実行 → JSON出力 → data.js変換 を一気通貫で行う

.DESCRIPTION
    sas\ フォルダ内のすべての .sas スクリプトを順に実行し、
    config.dashboards で定義された各JSONを data.js へ変換する。
    ログローテーション付き。

.PARAMETER ConfigPath
    設定ファイルのパス
.PARAMETER SasExe
    SAS実行ファイルのパス（環境に応じて変更）

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\refresh_dashboard.ps1
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "C:\dashboard\config\server.config.json",
    [string]$SasExe     = "C:\Program Files\SASHome\SASFoundation\9.4\sas.exe"
)

$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$logDir = $config.server.logDir
$dataDir = $config.server.dataDir
$webRoot = $config.server.rootDir
$refreshLog = Join-Path $logDir "refresh.log"

function Write-RefreshLog {
    param([string]$Msg, [string]$Level = "INFO")
    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Msg
    Add-Content -Path $refreshLog -Value $line -Encoding UTF8
    Write-Host $line
}

Write-RefreshLog "===== データ更新ジョブ開始 ====="
$jobStart = Get-Date
$hasError = $false

# ----- SAS実行 -----
$sasDir = Join-Path (Split-Path $ConfigPath -Parent) "..\sas" | Resolve-Path -ErrorAction SilentlyContinue
if (-not $sasDir) { $sasDir = "C:\dashboard\sas" }
$sasScripts = Get-ChildItem "$sasDir\*.sas" -ErrorAction SilentlyContinue

foreach ($sas in $sasScripts) {
    Write-RefreshLog "SAS実行中: $($sas.Name)"
    $logFile = Join-Path $logDir "sas_$($sas.BaseName).log"
    $lstFile = Join-Path $logDir "sas_$($sas.BaseName).lst"

    try {
        $proc = Start-Process -FilePath $SasExe `
            -ArgumentList "-SYSIN", "`"$($sas.FullName)`"", "-LOG", "`"$logFile`"", "-PRINT", "`"$lstFile`"", "-NOSPLASH" `
            -NoNewWindow -Wait -PassThru

        if ($proc.ExitCode -eq 0) {
            Write-RefreshLog "  成功: $($sas.Name)"
        } else {
            Write-RefreshLog "  異常終了: $($sas.Name) (ExitCode=$($proc.ExitCode))" "ERROR"
            $hasError = $true
        }
    } catch {
        Write-RefreshLog "  例外: $($sas.Name) - $_" "ERROR"
        $hasError = $true
    }
}

# ----- JSON → data.js 変換 -----
foreach ($dashboard in $config.dashboards) {
    $jsonPath = Join-Path $dataDir $dashboard.dataFile
    $jsDir    = Join-Path $webRoot "dashboards\$($dashboard.id)"
    $jsPath   = Join-Path $jsDir "data.js"

    if (-not (Test-Path $jsonPath)) {
        Write-RefreshLog "  JSON未生成: $jsonPath" "WARN"
        continue
    }

    try {
        if (-not (Test-Path $jsDir)) { New-Item -ItemType Directory -Path $jsDir -Force | Out-Null }
        $json = Get-Content $jsonPath -Raw -Encoding UTF8
        $jsContent = "window.DASHBOARD_DATA = $json;"
        Set-Content -Path $jsPath -Value $jsContent -Encoding UTF8
        Write-RefreshLog "  data.js更新: $($dashboard.id)"
    } catch {
        Write-RefreshLog "  data.js更新失敗: $($dashboard.id) - $_" "ERROR"
        $hasError = $true
    }
}

# ----- ログローテーション -----
$rotateDays = $config.logging.rotateDays
if ($rotateDays -gt 0) {
    $cutoff = (Get-Date).AddDays(-$rotateDays)
    Get-ChildItem $logDir -File | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-RefreshLog "  古いログ削除: $($_.Name)"
    }
}

$elapsed = (Get-Date) - $jobStart
Write-RefreshLog "===== ジョブ完了 (所要 $($elapsed.TotalSeconds.ToString('F1'))秒, エラー=$hasError) ====="

if ($hasError) { exit 1 }
exit 0
