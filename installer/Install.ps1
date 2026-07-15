$ErrorActionPreference = 'Stop'

$appName = ([char]0x65E0).ToString() + [char]0x9650 + [char]0x526A + [char]0x8D34 + [char]0x677F
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\InfiniteClipboard'
$launchPath = Join-Path $installDir 'Launch.vbs'
$compatLaunchName = ([char]0x542F).ToString() + [char]0x52A8 + $appName + '.vbs'
$compatLaunchPath = Join-Path $installDir $compatLaunchName
$programsDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$menuDir = Join-Path $programsDir $appName
$desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) ($appName + '.lnk')
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\InfiniteClipboard'

try {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    foreach ($file in @('InfiniteClipboard.ps1', 'Launch.vbs', 'Uninstall.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $installDir $file) -Force
    }
    # InfiniteClipboard.ps1 uses this original launcher name when it refreshes the startup entry.
    Copy-Item -LiteralPath $launchPath -Destination $compatLaunchPath -Force

    $shell = New-Object -ComObject WScript.Shell
    New-Item -ItemType Directory -Path $menuDir -Force | Out-Null

    $startLink = $shell.CreateShortcut((Join-Path $menuDir ($appName + '.lnk')))
    $startLink.TargetPath = $launchPath
    $startLink.WorkingDirectory = $installDir
    $startLink.Description = 'Clipboard history manager'
    $startLink.Save()

    $uninstallLink = $shell.CreateShortcut((Join-Path $menuDir ('Uninstall ' + $appName + '.lnk')))
    $uninstallLink.TargetPath = 'powershell.exe'
    $uninstallLink.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $installDir 'Uninstall.ps1') + '"'
    $uninstallLink.WorkingDirectory = $installDir
    $uninstallLink.Description = 'Uninstall InfiniteClipboard'
    $uninstallLink.Save()

    $desktop = $shell.CreateShortcut($desktopLink)
    $desktop.TargetPath = $launchPath
    $desktop.WorkingDirectory = $installDir
    $desktop.Description = 'Clipboard history manager'
    $desktop.Save()

    New-Item -Path $uninstallKey -Force | Out-Null
    New-ItemProperty -Path $uninstallKey -Name DisplayName -Value $appName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $uninstallKey -Name DisplayVersion -Value '1.0.1' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $uninstallKey -Name Publisher -Value 'InfiniteClipboard' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $uninstallKey -Name InstallLocation -Value $installDir -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $uninstallKey -Name UninstallString -Value ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $installDir 'Uninstall.ps1') + '"') -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $uninstallKey -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $uninstallKey -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null

    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $runKey -Force | Out-Null
    Set-ItemProperty -Path $runKey -Name 'InfiniteClipboard' -Value ('wscript.exe "' + $launchPath + '"')

    Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $launchPath + '"') -WorkingDirectory $installDir
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($appName + " installed successfully.`r`n`r`nIt has started and will run from the system tray after you sign in.", $appName + ' Setup', 'OK', 'Information') | Out-Null
}
catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show('Installation failed: ' + $_.Exception.Message, $appName + ' Setup', 'OK', 'Error') | Out-Null
    exit 1
}
