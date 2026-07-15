$ErrorActionPreference = 'SilentlyContinue'

$appName = ([char]0x65E0).ToString() + [char]0x9650 + [char]0x526A + [char]0x8D34 + [char]0x677F
$installDir = $PSScriptRoot
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\InfiniteClipboard'

Add-Type -AssemblyName System.Windows.Forms
$answer = [System.Windows.Forms.MessageBox]::Show('Uninstall ' + $appName + "?`r`n`r`nYour clipboard history in AppData will be kept for a future reinstall.", 'Uninstall ' + $appName, 'YesNo', 'Question')
if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { exit 0 }

Remove-ItemProperty -Path $runKey -Name 'InfiniteClipboard' -ErrorAction SilentlyContinue
Remove-Item -Path $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue

$shell = New-Object -ComObject WScript.Shell
$desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) ($appName + '.lnk')
if (Test-Path -LiteralPath $desktopLink) {
    try {
        $target = $shell.CreateShortcut($desktopLink).TargetPath
        if ($target -like ($installDir + '*')) { Remove-Item -LiteralPath $desktopLink -Force }
    } catch { }
}

$menuDir = Join-Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs') $appName
Remove-Item -LiteralPath $menuDir -Recurse -Force -ErrorAction SilentlyContinue

$cleanup = Join-Path $env:TEMP ('InfiniteClipboard-uninstall-' + $PID + '.cmd')
$cleanupLines = @('@echo off', 'timeout /t 2 /nobreak >nul', 'rmdir /s /q "' + $installDir + '"', 'del "%~f0"')
Set-Content -LiteralPath $cleanup -Value $cleanupLines -Encoding Ascii
Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c "' + $cleanup + '"') -WindowStyle Hidden

[System.Windows.Forms.MessageBox]::Show($appName + ' was uninstalled. Your clipboard history was kept.', 'Uninstall complete', 'OK', 'Information') | Out-Null
