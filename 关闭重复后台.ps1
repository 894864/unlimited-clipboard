$ErrorActionPreference = "SilentlyContinue"

$scriptPath = Join-Path $PSScriptRoot "InfiniteClipboard.ps1"
$escaped = [regex]::Escape($scriptPath)
$current = $PID

$targets = Get-CimInstance Win32_Process |
    Where-Object {
        $_.ProcessId -ne $current -and
        $_.CommandLine -match "powershell" -and
        $_.CommandLine -match $escaped
    }

foreach ($p in $targets) {
    try {
        Stop-Process -Id $p.ProcessId -Force
        Write-Host "已关闭重复后台 PID $($p.ProcessId)"
    } catch {
        Write-Host "关闭 PID $($p.ProcessId) 失败：$($_.Exception.Message)"
    }
}

if (-not $targets -or $targets.Count -eq 0) {
    Write-Host "没有发现重复后台。"
}
