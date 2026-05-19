<#
.SYNOPSIS
    タスクスケジューラに自動実行タスクを登録する

.DESCRIPTION
    1. データ更新タスク（毎朝7時）
    2. サーバ起動タスク（システム起動時、自動再起動付き）

.NOTES
    管理者PowerShellで実行する必要がある
#>

[CmdletBinding()]
param(
    [string]$Root = "C:\dashboard"
)

# ----- タスク1: データ更新（毎朝7時） -----
$taskName1 = "Dashboard-DataRefresh"
$action1 = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Root\server\refresh_dashboard.ps1`""
$trigger1 = New-ScheduledTaskTrigger -Daily -At "7:00AM"
$settings1 = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)

Unregister-ScheduledTask -TaskName $taskName1 -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask `
    -TaskName $taskName1 `
    -Action $action1 `
    -Trigger $trigger1 `
    -Settings $settings1 `
    -RunLevel Highest `
    -Description "社内ダッシュボードのデータ自動更新"

Write-Host "登録: $taskName1 (毎朝7:00)" -ForegroundColor Green

# ----- タスク2: サーバ起動（システム起動時） -----
$taskName2 = "Dashboard-Server"
$action2 = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Root\server\serve.ps1`""
$trigger2 = New-ScheduledTaskTrigger -AtStartup
$settings2 = New-ScheduledTaskSettingsSet `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable

Unregister-ScheduledTask -TaskName $taskName2 -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask `
    -TaskName $taskName2 `
    -Action $action2 `
    -Trigger $trigger2 `
    -Settings $settings2 `
    -RunLevel Highest `
    -Description "社内ダッシュボードのHTTPサーバ常駐起動"

Write-Host "登録: $taskName2 (システム起動時)" -ForegroundColor Green

Write-Host ""
Write-Host "登録完了。タスクスケジューラで確認できます。" -ForegroundColor Cyan
Write-Host "今すぐ実行してテスト:" -ForegroundColor Yellow
Write-Host "  Start-ScheduledTask -TaskName $taskName1"
Write-Host "  Start-ScheduledTask -TaskName $taskName2"
