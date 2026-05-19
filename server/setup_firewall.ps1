<#
.SYNOPSIS
    社内ダッシュボードサーバの受信ルールとURL ACLを設定する

.NOTES
    管理者PowerShellで実行する必要がある
#>

[CmdletBinding()]
param(
    [int]$Port = 8080,
    [string]$RuleName = "DashboardServer"
)

# 管理者権限チェック
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "管理者権限が必要です。PowerShellを管理者として実行してください。" -ForegroundColor Red
    exit 1
}

# ----- URL ACL設定（非管理者でもサーバ起動できるように） -----
Write-Host "URL ACL設定中..." -ForegroundColor Cyan
$existing = & netsh http show urlacl url="http://+:$Port/" 2>&1
if ($existing -match "Reserved URL") {
    Write-Host "  既に登録済み" -ForegroundColor Gray
} else {
    & netsh http add urlacl url="http://+:$Port/" user=Everyone
    Write-Host "  追加完了" -ForegroundColor Green
}

# ----- Firewall受信ルール -----
Write-Host "Firewall受信ルール設定中..." -ForegroundColor Cyan
$existingRule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if ($existingRule) {
    Write-Host "  既存ルールを更新" -ForegroundColor Gray
    Remove-NetFirewallRule -DisplayName $RuleName
}
New-NetFirewallRule -DisplayName $RuleName `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $Port `
    -Action Allow `
    -Profile Domain,Private `
    -Description "社内ダッシュボード用 HTTPサーバ" | Out-Null
Write-Host "  追加完了" -ForegroundColor Green

# ----- IPアドレス表示（共有用） -----
Write-Host ""
Write-Host "===== アクセス可能URL =====" -ForegroundColor Yellow
$hostName = $env:COMPUTERNAME
Write-Host "  http://${hostName}:$Port/"
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" } |
    ForEach-Object {
        Write-Host "  http://$($_.IPAddress):$Port/"
    }
Write-Host ""
Write-Host "設定完了。サーバを起動できます。" -ForegroundColor Green
