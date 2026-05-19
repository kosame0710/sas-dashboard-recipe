<#
.SYNOPSIS
    社内環境で本リポジトリ（SAS to Web Dashboard Recipe）が動作するかを
    実装着手前に網羅的に判定する環境チェックスクリプト。

.DESCRIPTION
    server\serve.ps1 / refresh_dashboard.ps1 / setup_firewall.ps1 /
    install_task.ps1 / convert_json_to_js.ps1 および sas\export_sample.sas
    の依存前提条件を読み取り、社内Windows端末で順に検査する。

    本スクリプトは「副作用なし（または最小・即時ロールバック）」で動作するよう設計してある。
    管理者権限は不要。Constrained Language Mode や ExecutionPolicy 制限下でも
    起動できるよう、外部から -ExecutionPolicy Bypass で呼ぶ前提とする。

    結果はコンソールに人間可読な形式で表示し、同時に
    tools\check-report.md にも保存する。
    各項目は OK / WARN / NG / SKIP のいずれかで判定する。

.PARAMETER ConfigPath
    server.config.json のパス。指定された場合はそこからポート等を読む。
    省略時は ..\config\server.config.json を試し、それも無ければ既定値 (8080) を使う。

.PARAMETER Port
    HTTPサーバが使うポート番号。ConfigPath より優先される。既定 8080。

.PARAMETER ReportPath
    レポートの保存先。省略時は本スクリプトと同じフォルダの check-report.md。

.PARAMETER NoFileReport
    レポートファイルを書き出さず、コンソール出力のみ行う。

.EXAMPLE
    # 推奨起動方法（実行ポリシー制限下でもOK）
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\check-environment.ps1

.EXAMPLE
    # ポートを明示
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\check-environment.ps1 -Port 9000

.NOTES
    本スクリプト自体は ExecutionPolicy を変更しない。
    Constrained Language Mode で起動された場合は冒頭で検知して致命的NGを報告し、
    可能な範囲のチェックを継続する。
#>

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [int]$Port = 0,
    [string]$ReportPath,
    [switch]$NoFileReport
)

# ====================================================================
# 内部状態
# ====================================================================
$script:Results = New-Object System.Collections.ArrayList
$script:StartTime = Get-Date

# Constrained Language Mode 下で New-Object が制限される可能性を考慮し、
# 早めに LanguageMode を捕捉しておく
$script:LangMode = try {
    $ExecutionContext.SessionState.LanguageMode.ToString()
} catch { "Unknown" }

# ====================================================================
# ユーティリティ
# ====================================================================
function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet("OK","WARN","NG","SKIP")][string]$Status,
        [string]$Detail = "",
        [string]$Recommend = ""
    )
    $obj = [PSCustomObject]@{
        Category  = $Category
        Name      = $Name
        Status    = $Status
        Detail    = $Detail
        Recommend = $Recommend
    }
    [void]$script:Results.Add($obj)

    $color = switch ($Status) {
        "OK"   { "Green" }
        "WARN" { "Yellow" }
        "NG"   { "Red" }
        "SKIP" { "DarkGray" }
    }
    $line = "  [{0,-4}] {1}" -f $Status, $Name
    Write-Host $line -ForegroundColor $color
    if ($Detail)    { Write-Host "         $Detail" -ForegroundColor DarkGray }
    if ($Recommend) { Write-Host "         -> $Recommend" -ForegroundColor DarkCyan }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host (" $Title") -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Invoke-Safe {
    <# 任意のスクリプトブロックを try/catch で包んで結果オブジェクトを返す #>
    param([scriptblock]$Block)
    try {
        $val = & $Block
        return @{ Ok = $true; Value = $val; Error = $null }
    } catch {
        return @{ Ok = $false; Value = $null; Error = $_.Exception.Message }
    }
}

# ====================================================================
# 設定読み込み（ポート決定）
# ====================================================================
function Resolve-Port {
    if ($Port -gt 0) { return @{ Port = $Port; Source = "コマンドライン引数" } }

    $candidates = @()
    if ($ConfigPath) { $candidates += $ConfigPath }
    $candidates += (Join-Path $PSScriptRoot "..\config\server.config.json")

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            try {
                $cfg = Get-Content $c -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($cfg.server.port) {
                    return @{ Port = [int]$cfg.server.port; Source = $c }
                }
            } catch { }
        }
    }
    return @{ Port = 8080; Source = "デフォルト値" }
}

# ====================================================================
# === Section 1: PowerShell 環境 ===
# ====================================================================
function Test-PowerShellEnv {
    Write-Section "1. PowerShell 環境"

    # 1-1. バージョン
    $v = $PSVersionTable
    $ver = $v.PSVersion
    $detail = "PSVersion=$ver, Edition=$($v.PSEdition), OS=$($v.OS), CLR=$($v.CLRVersion)"
    if ($ver.Major -ge 5) {
        Add-Result "PowerShell" "PSVersion (>= 5.1)" "OK" $detail
    } else {
        Add-Result "PowerShell" "PSVersion (>= 5.1)" "NG" $detail `
            "本リポジトリのスクリプトは PowerShell 5.1 以上を前提とする。Windows Management Framework 5.1 を導入するか PowerShell 7 を別途インストールすること。"
    }

    # 1-2. LanguageMode
    switch ($script:LangMode) {
        "FullLanguage" {
            Add-Result "PowerShell" "LanguageMode" "OK" "FullLanguage"
        }
        "ConstrainedLanguage" {
            Add-Result "PowerShell" "LanguageMode" "NG" "ConstrainedLanguage が有効" `
                "ConstrainedLanguage 下では Add-Type / New-Object [System.Net.HttpListener] 等が制限され、HTTPサーバが起動できない。WDAC/AppLocker の言語制限を解除するか、許可リスト署名対応の代替実装が必要。"
        }
        "RestrictedLanguage" {
            Add-Result "PowerShell" "LanguageMode" "NG" "RestrictedLanguage" `
                "RestrictedLanguage 下では本リポジトリの実装は動作しない。IT管理者へエスカレーション。"
        }
        default {
            Add-Result "PowerShell" "LanguageMode" "WARN" "判定不能: $($script:LangMode)" `
                "本来は FullLanguage が期待される。値を IT管理者と確認すること。"
        }
    }

    # 1-3. ExecutionPolicy (全スコープ)
    $r = Invoke-Safe { Get-ExecutionPolicy -List }
    if ($r.Ok) {
        $policies = $r.Value
        $effective = (Get-ExecutionPolicy)
        $detail = ($policies | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }) -join ", "
        $detail = "Effective=$effective | $detail"

        if ($effective -in "Restricted","AllSigned") {
            Add-Result "PowerShell" "ExecutionPolicy" "WARN" $detail `
                "実行ポリシーが厳しい。本リポジトリのスクリプトは powershell.exe -ExecutionPolicy Bypass -File で都度起動する運用にすること。タスクスケジューラ登録時の -ExecutionPolicy Bypass も同様に必要。"
        } elseif ($effective -in "RemoteSigned","Unrestricted","Bypass") {
            Add-Result "PowerShell" "ExecutionPolicy" "OK" $detail
        } else {
            Add-Result "PowerShell" "ExecutionPolicy" "WARN" $detail
        }
    } else {
        Add-Result "PowerShell" "ExecutionPolicy" "SKIP" $r.Error
    }

    # 1-4. ユーザーと管理者権限
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $userDetail = "User=$($id.Name), Admin=$isAdmin"
        if ($isAdmin) {
            Add-Result "PowerShell" "実行ユーザー / 管理者権限" "OK" $userDetail `
                "管理者として起動済み。setup_firewall.ps1 / install_task.ps1 もこのまま実行可能。"
        } else {
            Add-Result "PowerShell" "実行ユーザー / 管理者権限" "WARN" $userDetail `
                "非管理者で起動。setup_firewall.ps1 (urlacl/Firewall) と install_task.ps1 (タスク登録) は管理者で再実行する必要がある。serve.ps1 自体は urlacl 登録後なら非管理者で起動可。"
        }
    } catch {
        Add-Result "PowerShell" "実行ユーザー / 管理者権限" "SKIP" $_.Exception.Message
    }
}

# ====================================================================
# === Section 2: .NET / Assembly ===
# ====================================================================
function Test-DotNet {
    Write-Section "2. .NET / 必須アセンブリ"

    # 2-1. .NET Framework バージョン
    $r = Invoke-Safe {
        Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction Stop |
            Select-Object Release, Version, TargetVersion
    }
    if ($r.Ok -and $r.Value) {
        $rel = [int]$r.Value.Release
        $approx = switch ($true) {
            ($rel -ge 533320) { "4.8.1+" }
            ($rel -ge 528040) { "4.8" }
            ($rel -ge 461808) { "4.7.2" }
            ($rel -ge 461308) { "4.7.1" }
            ($rel -ge 460798) { "4.7" }
            ($rel -ge 394802) { "4.6.2" }
            ($rel -ge 393295) { "4.6" }
            default { "< 4.6" }
        }
        $detail = "Release=$rel ($approx), Version=$($r.Value.Version)"
        if ($rel -ge 393295) {
            Add-Result ".NET" ".NET Framework" "OK" $detail
        } else {
            Add-Result ".NET" ".NET Framework" "WARN" $detail `
                "PowerShell 5.1 は .NET Framework 4.5+ を必要とする。古いビルドだと挙動が異なる場合あり。"
        }
    } else {
        Add-Result ".NET" ".NET Framework" "WARN" "レジストリ読込失敗: $($r.Error)"
    }

    # 2-2. PowerShell 7+ で動かす場合の .NET (Core/5+) 表示（参考）
    if ($PSVersionTable.PSEdition -eq "Core") {
        try {
            $rt = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
            Add-Result ".NET" ".NET (Core/5+) ランタイム" "OK" $rt
        } catch {
            Add-Result ".NET" ".NET (Core/5+) ランタイム" "SKIP" $_.Exception.Message
        }
    } else {
        Add-Result ".NET" ".NET (Core/5+) ランタイム" "SKIP" "PSEdition=Desktop のため不要"
    }

    # 2-3. System.Web (serve.ps1 が Add-Type で読み込む)
    $r = Invoke-Safe { Add-Type -AssemblyName System.Web -ErrorAction Stop; [System.Web.HttpUtility]::UrlDecode("/test") }
    if ($r.Ok) {
        Add-Result ".NET" "System.Web (HttpUtility)" "OK" "Add-Type 成功"
    } else {
        Add-Result ".NET" "System.Web (HttpUtility)" "NG" $r.Error `
            "serve.ps1 の URLデコードに必要。.NET Framework 完全版が入っていない可能性。Server Core では未搭載のことがあるので Windows のエディションを確認。"
    }

    # 2-4. System.Net.HttpListener 型の存在確認
    $r = Invoke-Safe {
        $t = [System.Net.HttpListener]
        $t.FullName
    }
    if ($r.Ok) {
        Add-Result ".NET" "System.Net.HttpListener 型" "OK" $r.Value
    } else {
        Add-Result ".NET" "System.Net.HttpListener 型" "NG" $r.Error `
            "serve.ps1 の根幹。HttpListener が無効化されている環境では本構成は動かない。"
    }
}

# ====================================================================
# === Section 3: HTTP サーバ要件（実バインドテスト） ===
# ====================================================================
function Test-HttpListener {
    param([int]$TestPort)

    Write-Section "3. HTTP サーバ要件 (ポート $TestPort)"

    # 3-1. localhost (127.0.0.1) バインド
    $listener = $null
    $r = Invoke-Safe {
        $l = New-Object System.Net.HttpListener
        $l.Prefixes.Add("http://127.0.0.1:$TestPort/")
        $l.Start()
        $l
    }
    if ($r.Ok) {
        Add-Result "HTTP" "127.0.0.1:$TestPort バインド" "OK" "Start() 成功 (即時 Stop)"
        try { $r.Value.Stop(); $r.Value.Close() } catch {}
    } else {
        # ポート使用中 vs 権限不足を分けて判定
        $msg = $r.Error
        if ($msg -match "拒否|denied|アクセス|access") {
            Add-Result "HTTP" "127.0.0.1:$TestPort バインド" "NG" $msg `
                "HttpListener へのアクセスが拒否された。urlacl 未登録の状態で + バインドを試みたか、AppLocker/Defender がブロックしている可能性。"
        } elseif ($msg -match "使用中|in use|別のプロセス") {
            Add-Result "HTTP" "127.0.0.1:$TestPort バインド" "WARN" $msg `
                "ポート $TestPort は既に使用中。-Port で別ポートを指定するか、占有プロセスを停止すること。"
        } else {
            Add-Result "HTTP" "127.0.0.1:$TestPort バインド" "NG" $msg
        }
    }

    # 3-2. 全インターフェース (+) バインド  ※ urlacl/管理者必須
    $r = Invoke-Safe {
        $l = New-Object System.Net.HttpListener
        $l.Prefixes.Add("http://+:$TestPort/")
        $l.Start()
        $l
    }
    if ($r.Ok) {
        Add-Result "HTTP" "+:$TestPort (全IF) バインド" "OK" "urlacl 登録済みまたは管理者起動と推定"
        try { $r.Value.Stop(); $r.Value.Close() } catch {}
    } else {
        Add-Result "HTTP" "+:$TestPort (全IF) バインド" "WARN" $r.Error `
            "想定内のことが多い。setup_firewall.ps1 を管理者で実行すれば netsh http add urlacl url=http://+:$TestPort/ user=Everyone が登録され、serve.ps1 が非管理者で起動できるようになる。"
    }

    # 3-3. netsh http show urlacl
    $r = Invoke-Safe {
        $out = & netsh http show urlacl url="http://+:$TestPort/" 2>&1
        ($out -join "`n").Trim()
    }
    if ($r.Ok) {
        $hasReserved = ($r.Value -match "Reserved URL|予約された URL")
        if ($hasReserved) {
            Add-Result "HTTP" "netsh http urlacl 登録状況" "OK" "url=http://+:$TestPort/ は予約済み"
        } else {
            Add-Result "HTTP" "netsh http urlacl 登録状況" "WARN" "url=http://+:$TestPort/ は未予約" `
                "管理者PowerShellで: netsh http add urlacl url=http://+:$TestPort/ user=Everyone"
        }
    } else {
        Add-Result "HTTP" "netsh http urlacl 登録状況" "SKIP" $r.Error
    }

    # 3-4. Windows Firewall プロファイル
    $r = Invoke-Safe { Get-NetFirewallProfile -ErrorAction Stop }
    if ($r.Ok) {
        $detail = ($r.Value | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ", "
        Add-Result "HTTP" "Windows Firewall プロファイル" "OK" $detail `
            "Enabled=True のプロファイルでは setup_firewall.ps1 で受信ルールを追加する必要がある。"
    } else {
        Add-Result "HTTP" "Windows Firewall プロファイル" "SKIP" $r.Error `
            "Get-NetFirewallProfile が無い環境 (古い Windows / Server Core 未モジュール) の可能性。"
    }

    # 3-5. ポート $TestPort の既存受信ルール検出
    $r = Invoke-Safe {
        Get-NetFirewallPortFilter -ErrorAction Stop |
            Where-Object { $_.LocalPort -eq $TestPort -and $_.Protocol -eq "TCP" } |
            Select-Object -First 3
    }
    if ($r.Ok -and $r.Value) {
        $count = @($r.Value).Count
        Add-Result "HTTP" "ポート $TestPort の既存ルール" "OK" "$count 件の TCP/$TestPort ルールが既存"
    } elseif ($r.Ok) {
        Add-Result "HTTP" "ポート $TestPort の既存ルール" "WARN" "TCP/$TestPort 受信ルールなし" `
            "setup_firewall.ps1 を管理者で実行して受信ルールを追加すること。"
    } else {
        Add-Result "HTTP" "ポート $TestPort の既存ルール" "SKIP" $r.Error
    }
}

# ====================================================================
# === Section 4: タスクスケジューラ ===
# ====================================================================
function Test-ScheduledTasks {
    Write-Section "4. タスクスケジューラ (refresh_dashboard / serve 自動起動)"

    # 4-1. schtasks.exe の存在
    $r = Invoke-Safe { (Get-Command schtasks.exe -ErrorAction Stop).Source }
    if ($r.Ok) {
        Add-Result "Schtasks" "schtasks.exe" "OK" $r.Value
    } else {
        Add-Result "Schtasks" "schtasks.exe" "NG" $r.Error `
            "schtasks.exe が無い環境では自動更新が組めない。"
    }

    # 4-2. ScheduledTasks モジュール
    $r = Invoke-Safe {
        Get-Module -ListAvailable ScheduledTasks -ErrorAction Stop | Select-Object -First 1 -ExpandProperty Version
    }
    if ($r.Ok -and $r.Value) {
        Add-Result "Schtasks" "ScheduledTasks モジュール" "OK" "Version=$($r.Value)"
    } else {
        Add-Result "Schtasks" "ScheduledTasks モジュール" "WARN" "見つからない" `
            "install_task.ps1 は New-ScheduledTask* / Register-ScheduledTask を使用する。代替として schtasks.exe での登録に書き換える必要がある。"
    }

    # 4-3. 自ユーザー権限でタスク登録できるか（dummy で実テスト → 即削除）
    $dummyName = "Dashboard-EnvCheck-Probe-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0,8))
    $r = Invoke-Safe {
        $action  = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c exit 0"
        # 過去日付ではなく、未来日付の OnceTrigger を使う（実行されないように遠い未来）
        $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddYears(10))
        $set     = New-ScheduledTaskSettingsSet -DisallowDemandStart -StartWhenAvailable:$false
        $null = Register-ScheduledTask -TaskName $dummyName -Action $action -Trigger $trigger -Settings $set -ErrorAction Stop
        "OK"
    }
    if ($r.Ok) {
        try { Unregister-ScheduledTask -TaskName $dummyName -Confirm:$false -ErrorAction Stop } catch {}
        Add-Result "Schtasks" "自ユーザー権限でタスク登録" "OK" "$dummyName を登録→即削除に成功"
    } else {
        # クリーンアップ試行
        try { Unregister-ScheduledTask -TaskName $dummyName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
        $msg = $r.Error
        if ($msg -match "拒否|denied|アクセス|access|管理者") {
            Add-Result "Schtasks" "自ユーザー権限でタスク登録" "WARN" $msg `
                "非管理者ではタスク登録が拒否される構成。install_task.ps1 は管理者で起動すること。"
        } else {
            Add-Result "Schtasks" "自ユーザー権限でタスク登録" "NG" $msg
        }
    }
}

# ====================================================================
# === Section 5: ファイルシステム / 配置 ===
# ====================================================================
function Test-FileSystem {
    Write-Section "5. ファイルシステム / 配置先"

    # 5-1. スクリプト自身のディレクトリへの書き込み
    $r = Invoke-Safe {
        $probe = Join-Path $PSScriptRoot ".write-probe-$([guid]::NewGuid().ToString('N').Substring(0,8)).tmp"
        "probe" | Out-File -FilePath $probe -Encoding UTF8
        Remove-Item $probe -Force
        $PSScriptRoot
    }
    if ($r.Ok) {
        Add-Result "FS" "スクリプトディレクトリ書込" "OK" $r.Value
    } else {
        Add-Result "FS" "スクリプトディレクトリ書込" "WARN" $r.Error `
            "レポートを書き出せない。-NoFileReport を付けるか、別の場所にコピーして実行すること。"
    }

    # 5-2. C:\dashboard 想定の各サブパス
    $defaultRoot = "C:\dashboard"
    $sub = @("config","data","logs","sas","web","server")
    foreach ($s in $sub) {
        $p = Join-Path $defaultRoot $s
        if (Test-Path $p) {
            $r = Invoke-Safe {
                $probe = Join-Path $p ".write-probe-$([guid]::NewGuid().ToString('N').Substring(0,8)).tmp"
                "probe" | Out-File -FilePath $probe -Encoding UTF8
                Remove-Item $probe -Force
                "存在 + 書込OK"
            }
            if ($r.Ok) {
                Add-Result "FS" "$p" "OK" $r.Value
            } else {
                Add-Result "FS" "$p" "WARN" "存在するが書込不可: $($r.Error)" `
                    "サービスアカウント or 実行ユーザーに書込権限を付与すること。"
            }
        } else {
            Add-Result "FS" "$p" "SKIP" "未作成（level1-guide.md の New-Item で作成想定）"
        }
    }

    # 5-3. UTF-8 BOM の挙動チェック
    # serve.ps1 や refresh_dashboard.ps1 は Set-Content -Encoding UTF8 を使う。
    # PS 5.1 では BOM 付き、PS 7+ では BOM なし、と挙動が違う。
    # SAS の filename 〜 encoding="utf-8" は BOM ありを正しく扱う前提ではない。
    try {
        $tmp = Join-Path $env:TEMP "dashboard-encoding-probe.txt"
        "abc" | Set-Content -Path $tmp -Encoding UTF8
        $bytes = [System.IO.File]::ReadAllBytes($tmp)
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            Add-Result "FS" "Set-Content -Encoding UTF8 のBOM" "WARN" "BOM 付き (PS 5.1 既定挙動)" `
                "data.js / JSON 出力先で BOM が問題になる可能性。CSV を SAS が読み戻すパイプラインがあるなら BOM なし固定にする ([System.IO.File]::WriteAllText を使う) のが安全。"
        } else {
            Add-Result "FS" "Set-Content -Encoding UTF8 のBOM" "OK" "BOM なし"
        }
    } catch {
        Add-Result "FS" "Set-Content -Encoding UTF8 のBOM" "SKIP" $_.Exception.Message
    }
}

# ====================================================================
# === Section 6: セキュリティ製品 (Defender / AppLocker) ===
# ====================================================================
function Test-Security {
    Write-Section "6. セキュリティ製品 (Defender / AppLocker / WDAC)"

    # 6-1. Windows Defender 全体
    $r = Invoke-Safe { Get-MpComputerStatus -ErrorAction Stop }
    if ($r.Ok) {
        $s = $r.Value
        $detail = "AMRunningMode=$($s.AMRunningMode), RealTimeProtection=$($s.RealTimeProtectionEnabled), TamperProtection=$($s.IsTamperProtected)"
        Add-Result "Security" "Windows Defender 状態" "OK" $detail
    } else {
        Add-Result "Security" "Windows Defender 状態" "SKIP" $r.Error
    }

    # 6-2. ASR ルール（PowerShell 系のスクリプトをブロックするルールがあると致命的）
    $r = Invoke-Safe { Get-MpPreference -ErrorAction Stop }
    if ($r.Ok) {
        $ids = @($r.Value.AttackSurfaceReductionRules_Ids)
        $acts = @($r.Value.AttackSurfaceReductionRules_Actions)
        if ($ids.Count -eq 0) {
            Add-Result "Security" "Defender ASR ルール" "OK" "ASR ルール未設定"
        } else {
            $blocking = 0
            for ($i=0; $i -lt $ids.Count; $i++) {
                if ($acts[$i] -eq 1) { $blocking++ }  # 1=Block
            }
            $detail = "総ルール=$($ids.Count), ブロック設定=$blocking"
            if ($blocking -gt 0) {
                Add-Result "Security" "Defender ASR ルール" "WARN" $detail `
                    "ASR でスクリプト実行/子プロセス起動が制限されていると、serve.ps1 の Start-Process や Runspace が止まる可能性。Get-MpPreference の AttackSurfaceReductionRules_Ids/Actions を確認すること。"
            } else {
                Add-Result "Security" "Defender ASR ルール" "OK" $detail
            }
        }
    } else {
        Add-Result "Security" "Defender ASR ルール" "SKIP" $r.Error
    }

    # 6-3. AppLocker 有効ポリシー
    $r = Invoke-Safe {
        $xml = Get-AppLockerPolicy -Effective -Xml -ErrorAction Stop
        # ScriptRules セクションが存在し、かつ allow 以外のルールが含まれるかを大まかに見る
        $hasScriptDeny = $xml -match "<RuleCollection Type=`"Script`"" -and $xml -match "Action=`"Deny`""
        @{ XmlLen = $xml.Length; HasScriptDeny = $hasScriptDeny }
    }
    if ($r.Ok) {
        if ($r.Value.HasScriptDeny) {
            Add-Result "Security" "AppLocker (Script ルール)" "WARN" "Script ルールに Deny を検出 ($($r.Value.XmlLen) bytes)" `
                "AppLocker が .ps1 をブロックしている可能性。IT管理者に許可ルール追加を依頼。"
        } else {
            Add-Result "Security" "AppLocker (Script ルール)" "OK" "Script Deny ルール未検出 ($($r.Value.XmlLen) bytes)"
        }
    } else {
        Add-Result "Security" "AppLocker (Script ルール)" "SKIP" $r.Error
    }

    # 6-4. WDAC (Code Integrity) 簡易チェック
    $r = Invoke-Safe {
        $ci = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
        @{
            CodeIntegrityPolicyEnforcementStatus = $ci.CodeIntegrityPolicyEnforcementStatus
            UMCIPolicyEnforcementStatus          = $ci.UsermodeCodeIntegrityPolicyEnforcementStatus
        }
    }
    if ($r.Ok) {
        $val = $r.Value
        $detail = "CI={0}, UMCI={1}" -f $val.CodeIntegrityPolicyEnforcementStatus, $val.UMCIPolicyEnforcementStatus
        # 2 = Enforced
        if ($val.UMCIPolicyEnforcementStatus -ge 2) {
            Add-Result "Security" "WDAC (Code Integrity)" "WARN" $detail `
                "WDAC が UMCI を強制中。未署名 .ps1 が ConstrainedLanguage で動かされ、本リポジトリの実装は致命的に止まる可能性。"
        } else {
            Add-Result "Security" "WDAC (Code Integrity)" "OK" $detail
        }
    } else {
        Add-Result "Security" "WDAC (Code Integrity)" "SKIP" $r.Error
    }
}

# ====================================================================
# === Section 7: ネットワーク ===
# ====================================================================
function Test-Network {
    Write-Section "7. ネットワーク"

    # 7-1. ホスト名
    Add-Result "Net" "ホスト名" "OK" $env:COMPUTERNAME

    # 7-2. IPv4 アドレス一覧（loopback / APIPA 除外）
    $r = Invoke-Safe {
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
            ForEach-Object { "$($_.InterfaceAlias) -> $($_.IPAddress)" }
    }
    if ($r.Ok -and $r.Value) {
        Add-Result "Net" "LAN IPv4 アドレス" "OK" (($r.Value) -join " ; ")
    } elseif ($r.Ok) {
        Add-Result "Net" "LAN IPv4 アドレス" "WARN" "有効な IPv4 アドレスなし" `
            "LAN に接続されていない、または APIPA のみ。"
    } else {
        Add-Result "Net" "LAN IPv4 アドレス" "SKIP" $r.Error
    }

    # 7-3. デフォルトゲートウェイ
    $r = Invoke-Safe {
        Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
            Sort-Object RouteMetric | Select-Object -First 1 -ExpandProperty NextHop
    }
    if ($r.Ok -and $r.Value) {
        Add-Result "Net" "デフォルトゲートウェイ" "OK" $r.Value
    } else {
        Add-Result "Net" "デフォルトゲートウェイ" "WARN" "取得できず" `
            "オフライン端末 or NIC 未接続の可能性。社内LANに繋がっていることを確認。"
    }

    # 7-4. DNS
    $r = Invoke-Safe {
        Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.ServerAddresses } |
            ForEach-Object { "$($_.InterfaceAlias): $($_.ServerAddresses -join ',')" }
    }
    if ($r.Ok -and $r.Value) {
        Add-Result "Net" "DNS サーバ" "OK" (($r.Value) -join " ; ")
    } else {
        $msg = if ($r.Error) { $r.Error } else { "情報なし" }
        Add-Result "Net" "DNS サーバ" "SKIP" $msg
    }
}

# ====================================================================
# === Section 8: その他（ブラウザ / SAS 検出） ===
# ====================================================================
function Test-Misc {
    Write-Section "8. その他 (ブラウザ / SAS 検出)"

    # 8-1. Microsoft Edge
    $edgePaths = @(
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
    )
    $found = $edgePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) {
        Add-Result "Misc" "Microsoft Edge" "OK" $found
    } else {
        Add-Result "Misc" "Microsoft Edge" "WARN" "規定パスに未検出" `
            "ダッシュボードはモダンブラウザを前提とする。IE のみの環境では Chart.js 等の挙動に注意。"
    }

    # 8-2. Google Chrome
    $chromePaths = @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    $found = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) {
        Add-Result "Misc" "Google Chrome" "OK" $found
    } else {
        Add-Result "Misc" "Google Chrome" "SKIP" "規定パスに未検出 (Edge があれば必須ではない)"
    }

    # 8-3. SAS Foundation 検出（任意）
    $sasPaths = @(
        "C:\Program Files\SASHome\SASFoundation\9.4\sas.exe",
        "C:\Program Files\SASHome\SASFoundation\9.3\sas.exe",
        "C:\Program Files (x86)\SASHome\SASFoundation\9.4\sas.exe"
    )
    $found = $sasPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) {
        Add-Result "Misc" "SAS Foundation (sas.exe)" "OK" $found
    } else {
        # レジストリ
        $r = Invoke-Safe {
            Get-ChildItem "HKLM:\SOFTWARE\SAS Institute Inc." -ErrorAction Stop |
                Select-Object -First 1 -ExpandProperty Name
        }
        if ($r.Ok -and $r.Value) {
            Add-Result "Misc" "SAS Foundation (sas.exe)" "WARN" "exe 未検出だがレジストリ存在: $($r.Value)" `
                "SAS は別パスにインストールされている可能性。refresh_dashboard.ps1 の -SasExe を環境に合わせて指定すること。"
        } else {
            Add-Result "Misc" "SAS Foundation (sas.exe)" "WARN" "規定パスにもレジストリにも未検出" `
                "本リポジトリは SAS 9.4+ の PROC JSON を前提とする。SAS をインストールしていない端末ではこのチェックは想定通り。SAS が存在する端末で再実行すること。"
        }
    }
}

# ====================================================================
# レポート生成
# ====================================================================
function Build-Summary {
    $by = $script:Results | Group-Object Status
    $h = @{}
    foreach ($g in $by) { $h[$g.Name] = $g.Count }
    foreach ($k in @("OK","WARN","NG","SKIP")) {
        if (-not $h.ContainsKey($k)) { $h[$k] = 0 }
    }
    return $h
}

function Write-Summary {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host " サマリ" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    $s = Build-Summary
    $elapsed = ((Get-Date) - $script:StartTime).TotalSeconds
    Write-Host ("  OK   : {0}" -f $s["OK"])   -ForegroundColor Green
    Write-Host ("  WARN : {0}" -f $s["WARN"]) -ForegroundColor Yellow
    Write-Host ("  NG   : {0}" -f $s["NG"])   -ForegroundColor Red
    Write-Host ("  SKIP : {0}" -f $s["SKIP"]) -ForegroundColor DarkGray
    Write-Host ("  所要時間: {0:F1} 秒" -f $elapsed) -ForegroundColor DarkCyan

    $ngs = $script:Results | Where-Object { $_.Status -eq "NG" }
    if (@($ngs).Count -gt 0) {
        Write-Host ""
        Write-Host " 致命的NG (要対応)" -ForegroundColor Red
        Write-Host ("-" * 70) -ForegroundColor Red
        foreach ($n in $ngs) {
            Write-Host ("  - [{0}] {1}" -f $n.Category, $n.Name) -ForegroundColor Red
            if ($n.Detail)    { Write-Host "      $($n.Detail)" -ForegroundColor DarkGray }
            if ($n.Recommend) { Write-Host "      -> $($n.Recommend)" -ForegroundColor DarkCyan }
        }
    } else {
        Write-Host ""
        Write-Host " 致命的NGなし。WARN を確認の上、実装着手可能。" -ForegroundColor Green
    }
}

function Save-Report {
    param([string]$Path, [hashtable]$PortInfo)

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("# SAS to Web Dashboard - 環境チェックレポート")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("- 実行日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $null = $sb.AppendLine("- 実行ユーザー: $env:USERDOMAIN\$env:USERNAME")
    $null = $sb.AppendLine("- ホスト名: $env:COMPUTERNAME")
    $null = $sb.AppendLine("- PSVersion: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))")
    $null = $sb.AppendLine("- LanguageMode: $($script:LangMode)")
    $null = $sb.AppendLine("- 検査ポート: $($PortInfo.Port) (取得元: $($PortInfo.Source))")
    $null = $sb.AppendLine("")

    $s = Build-Summary
    $null = $sb.AppendLine("## サマリ")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("| 区分 | 件数 |")
    $null = $sb.AppendLine("|------|------|")
    $null = $sb.AppendLine("| OK   | $($s['OK'])   |")
    $null = $sb.AppendLine("| WARN | $($s['WARN']) |")
    $null = $sb.AppendLine("| NG   | $($s['NG'])   |")
    $null = $sb.AppendLine("| SKIP | $($s['SKIP']) |")
    $null = $sb.AppendLine("")

    $null = $sb.AppendLine("## 詳細")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("| 区分 | 項目 | 判定 | 詳細 | 推奨アクション |")
    $null = $sb.AppendLine("|------|------|------|------|----------------|")
    foreach ($r in $script:Results) {
        $det  = ($r.Detail    -replace '\|','\|' -replace '`n',' ')
        $rec  = ($r.Recommend -replace '\|','\|' -replace '`n',' ')
        $null = $sb.AppendLine("| $($r.Category) | $($r.Name) | $($r.Status) | $det | $rec |")
    }
    $null = $sb.AppendLine("")

    $ngs = $script:Results | Where-Object { $_.Status -eq "NG" }
    if (@($ngs).Count -gt 0) {
        $null = $sb.AppendLine("## 致命的NG (要対応)")
        $null = $sb.AppendLine("")
        foreach ($n in $ngs) {
            $null = $sb.AppendLine("### [$($n.Category)] $($n.Name)")
            $null = $sb.AppendLine("")
            if ($n.Detail)    { $null = $sb.AppendLine("- 詳細: $($n.Detail)") }
            if ($n.Recommend) { $null = $sb.AppendLine("- 推奨: $($n.Recommend)") }
            $null = $sb.AppendLine("")
        }
    } else {
        $null = $sb.AppendLine("## 致命的NGなし")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("WARN/SKIP の内容を確認の上、実装着手可能。")
        $null = $sb.AppendLine("")
    }

    # PowerShell 5.1 でも 7+ でも BOM なし UTF-8 で書き出す
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ""
    Write-Host "レポート保存: $Path" -ForegroundColor Green
}

# ====================================================================
# メイン
# ====================================================================
Write-Host ""
Write-Host "SAS to Web Dashboard - 環境チェックスクリプト" -ForegroundColor White
Write-Host "実行日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host "ホスト名: $env:COMPUTERNAME" -ForegroundColor DarkGray
Write-Host "ユーザー: $env:USERDOMAIN\$env:USERNAME" -ForegroundColor DarkGray

$portInfo = Resolve-Port
Write-Host "検査ポート: $($portInfo.Port) (取得元: $($portInfo.Source))" -ForegroundColor DarkGray

Test-PowerShellEnv
Test-DotNet
Test-HttpListener -TestPort $portInfo.Port
Test-ScheduledTasks
Test-FileSystem
Test-Security
Test-Network
Test-Misc

Write-Summary

if (-not $NoFileReport) {
    if (-not $ReportPath) {
        $ReportPath = Join-Path $PSScriptRoot "check-report.md"
    }
    try {
        Save-Report -Path $ReportPath -PortInfo $portInfo
    } catch {
        Write-Host "レポート保存に失敗: $_" -ForegroundColor Red
        Write-Host "  (コンソール出力は上記をそのまま参照可能)" -ForegroundColor DarkGray
    }
}

# 致命的NGがあれば終了コード 1
$ngCount = @($script:Results | Where-Object { $_.Status -eq "NG" }).Count
if ($ngCount -gt 0) { exit 1 } else { exit 0 }
