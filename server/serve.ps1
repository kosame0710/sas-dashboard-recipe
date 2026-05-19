<#
.SYNOPSIS
    社内ダッシュボード用 簡易HTTPサーバ（マルチスレッド対応）

.DESCRIPTION
    PowerShell 5.1+ で動作する軽量HTTPサーバ。
    Runspace Pool による並行処理で複数同時接続に対応する。
    設定ファイル（server.config.json）でポート、認証、ダッシュボード定義を管理する。

.PARAMETER ConfigPath
    設定ファイルのパス。既定値: C:\dashboard\config\server.config.json

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\serve.ps1
    powershell -ExecutionPolicy Bypass -File .\serve.ps1 -ConfigPath D:\custom\config.json
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "C:\dashboard\config\server.config.json"
)

# ========== 初期化 ==========
Add-Type -AssemblyName System.Web

$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$port      = $config.server.port
$bindAddr  = $config.server.bindAddress
$rootDir   = $config.server.rootDir
$dataDir   = $config.server.dataDir
$logDir    = $config.server.logDir

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$accessLog = Join-Path $logDir "access.log"
$serverLog = Join-Path $logDir "server.log"

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO", [string]$LogFile = $serverLog)
    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Level, $Msg
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    if ($Level -in "ERROR","WARN") { Write-Host $line -ForegroundColor Yellow }
    else { Write-Host $line }
}

# MIMEマッピング
$mime = @{
    ".html" = "text/html; charset=utf-8"
    ".htm"  = "text/html; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
    ".woff" = "font/woff"
    ".woff2"= "font/woff2"
}

# ========== HTTPサーバ起動 ==========
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://${bindAddr}:${port}/")

try {
    $listener.Start()
    Write-Log "サーバ起動 http://${bindAddr}:${port}/ (rootDir=$rootDir)"
} catch {
    Write-Log "サーバ起動失敗: $_" "ERROR"
    Write-Host "ヒント: 管理者PowerShellで以下を実行してください:" -ForegroundColor Yellow
    Write-Host "  netsh http add urlacl url=http://+:$port/ user=Everyone" -ForegroundColor Yellow
    exit 1
}

# ========== Runspace Poolで並行処理 ==========
$pool = [runspacefactory]::CreateRunspacePool(1, 8)
$pool.Open()

$requestHandler = {
    param($ctx, $rootDir, $dataDir, $mimeMap, $accessLog, $config)

    function Write-AccessLog {
        param($Msg)
        $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Msg
        Add-Content -Path $accessLog -Value $line -Encoding UTF8
    }

    $req = $ctx.Request
    $res = $ctx.Response

    try {
        # Basic認証チェック（有効時のみ）
        if ($config.security.enableBasicAuth) {
            $auth = $req.Headers["Authorization"]
            if (-not $auth -or -not $auth.StartsWith("Basic ")) {
                $res.StatusCode = 401
                $res.Headers.Add("WWW-Authenticate", 'Basic realm="Dashboard"')
                $res.OutputStream.Close()
                return
            }
            # 実運用ではここで認証ロジックを実装
        }

        # IPホワイトリスト（設定時のみ）
        if ($config.security.allowedIps.Count -gt 0) {
            $clientIp = $req.RemoteEndPoint.Address.ToString()
            if ($clientIp -notin $config.security.allowedIps) {
                $res.StatusCode = 403
                $res.OutputStream.Close()
                Write-AccessLog "$clientIp BLOCKED $($req.Url.LocalPath)"
                return
            }
        }

        # パス解決
        $urlPath = [System.Web.HttpUtility]::UrlDecode($req.Url.LocalPath)
        if ($urlPath -eq "/") { $urlPath = "/index.html" }

        # ヘルスチェックエンドポイント
        if ($urlPath -eq "/health") {
            $res.ContentType = "application/json; charset=utf-8"
            $payload = @{ status = "ok"; time = (Get-Date -Format "o") } | ConvertTo-Json
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            Write-AccessLog "$($req.RemoteEndPoint.Address) 200 /health"
            return
        }

        # データAPIエンドポイント /api/data/{filename}
        if ($urlPath -like "/api/data/*") {
            $fname = ($urlPath -replace "^/api/data/", "")
            $filePath = Join-Path $dataDir $fname
            if (Test-Path $filePath -PathType Leaf) {
                $res.ContentType = "application/json; charset=utf-8"
                $bytes = [System.IO.File]::ReadAllBytes($filePath)
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                Write-AccessLog "$($req.RemoteEndPoint.Address) 200 $urlPath"
            } else {
                $res.StatusCode = 404
                Write-AccessLog "$($req.RemoteEndPoint.Address) 404 $urlPath"
            }
            return
        }

        # 静的ファイル
        $filePath = Join-Path $rootDir ($urlPath.TrimStart("/").Replace("/","\"))

        # パストラバーサル対策
        $fullRoot = (Resolve-Path $rootDir).Path
        try {
            $fullPath = [System.IO.Path]::GetFullPath($filePath)
        } catch {
            $res.StatusCode = 400
            $res.OutputStream.Close()
            return
        }
        if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $res.StatusCode = 403
            Write-AccessLog "$($req.RemoteEndPoint.Address) 403 $urlPath (path traversal)"
            return
        }

        if (Test-Path $filePath -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            $res.ContentType = if ($mimeMap.ContainsKey($ext)) { $mimeMap[$ext] } else { "application/octet-stream" }
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            Write-AccessLog "$($req.RemoteEndPoint.Address) 200 $urlPath"
        } else {
            $res.StatusCode = 404
            $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $urlPath")
            $res.OutputStream.Write($msg, 0, $msg.Length)
            Write-AccessLog "$($req.RemoteEndPoint.Address) 404 $urlPath"
        }
    } catch {
        $res.StatusCode = 500
        Write-AccessLog "$($req.RemoteEndPoint.Address) 500 $($req.Url.LocalPath) ERROR: $_"
    } finally {
        try { $res.OutputStream.Close() } catch {}
    }
}

# ========== メインループ ==========
Write-Log "リクエスト受付開始"
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()

        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($requestHandler).AddArgument($ctx).AddArgument($rootDir).AddArgument($dataDir).AddArgument($mime).AddArgument($accessLog).AddArgument($config)
        [void]$ps.BeginInvoke()
    }
} finally {
    Write-Log "サーバ停止処理中"
    $listener.Stop()
    $listener.Close()
    $pool.Close()
    $pool.Dispose()
    Write-Log "サーバ停止完了"
}
