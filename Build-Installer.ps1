param(
    [switch]$OpenOutputFolder,
    [string]$UpdateFeedUrl = 'https://unlimited-clipboard.cetle.cn/releases.json'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appVersion = '1.0.1'
$buildDir = Join-Path $root 'build\native'
$stagingDir = Join-Path $buildDir 'package'
$outputDir = Join-Path $root 'dist'
$siteDownloadDir = Join-Path $root 'website\download'
$releaseFeedPath = Join-Path $root 'website\releases.json'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$iexpress = Join-Path $env:WINDIR 'System32\iexpress.exe'

if (-not (Test-Path -LiteralPath $csc)) { throw 'The .NET Framework C# compiler is not available.' }
if (-not (Test-Path -LiteralPath $iexpress)) { throw 'IExpress is not available on this Windows installation.' }

New-Item -ItemType Directory -Path $buildDir, $stagingDir, $outputDir, $siteDownloadDir -Force | Out-Null

$psSource = Join-Path $root 'InfiniteClipboard.ps1'
$csSource = Join-Path $buildDir 'InfiniteClipboard.cs'
$mainExe = Join-Path $stagingDir 'InfiniteClipboard.exe'
$setupCs = Join-Path $root 'installer\SetupLauncher.cs'
$setupExe = Join-Path $stagingDir 'SetupLauncher.exe'
$updaterCs = Join-Path $root 'installer\UpdateLauncher.cs'
$updaterExe = Join-Path $stagingDir 'UpdateLauncher.exe'
$target = Join-Path $outputDir ("InfiniteClipboard-Setup-" + $appVersion + '.exe')
$legacyTarget = Join-Path $outputDir 'InfiniteClipboard-Setup.exe'
$sedPath = Join-Path $env:TEMP 'InfiniteClipboard-Native.sed'
$iconPath = Join-Path $buildDir 'UnlimitedClipboard.ico'

function New-AppIcon([string]$Path) {
    Add-Type -AssemblyName System.Drawing
    $bitmap = [System.Drawing.Bitmap]::new(64, 64)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $base = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(43, 103, 202))
        $paper = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
        $accent = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(140, 193, 255))
        $graphics.FillEllipse($base, 3, 3, 58, 58)
        $graphics.FillRectangle($paper, 16, 14, 32, 39)
        $graphics.FillRectangle($accent, 23, 9, 18, 11)
        $line = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(65, 127, 219))
        try {
            $graphics.FillRectangle($line, 23, 28, 19, 4)
            $graphics.FillRectangle($line, 23, 36, 15, 4)
            $graphics.FillRectangle($line, 23, 44, 11, 4)
        } finally {
            $line.Dispose()
            $base.Dispose()
            $paper.Dispose()
            $accent.Dispose()
        }
        $icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
        try {
            $stream = [System.IO.File]::Create($Path)
            try { $icon.Save($stream) } finally { $stream.Dispose() }
        } finally { $icon.Dispose() }
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

New-AppIcon $iconPath

$wrapper = [IO.File]::ReadAllText($psSource)
$match = [regex]::Match($wrapper, '(?s)\$source\s*=\s*@"\r?\n(?<code>.*?)\r?\n"@\r?\n\r?\nAdd-Type')
if (-not $match.Success) { throw 'Unable to extract the application source from InfiniteClipboard.ps1.' }
$feedForSource = if ([string]::IsNullOrWhiteSpace($UpdateFeedUrl)) { '' } else { $UpdateFeedUrl.Trim() }
if ($feedForSource -and -not $feedForSource.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) { throw 'UpdateFeedUrl must use HTTPS.' }
$feedForSource = $feedForSource.Replace('\', '\\').Replace('"', '\"')
$nativeSource = $match.Groups['code'].Value.Replace('__UPDATE_FEED_URL__', $feedForSource)
[IO.File]::WriteAllText($csSource, $nativeSource, (New-Object System.Text.UTF8Encoding($true)))

function Invoke-Csc([string[]]$Arguments) {
    $result = & $csc @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($result | Out-String) }
}

Invoke-Csc @('/nologo', '/target:winexe', ('/out:' + $mainExe), ('/win32icon:' + $iconPath), '/main:InfiniteClipboard.Program', '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll', '/reference:System.Xml.dll', '/reference:System.Core.dll', $csSource)
Invoke-Csc @('/nologo', '/target:winexe', ('/out:' + $setupExe), ('/win32icon:' + $iconPath), '/reference:System.Windows.Forms.dll', '/reference:System.dll', $setupCs)
Invoke-Csc @('/nologo', '/target:winexe', ('/out:' + $updaterExe), '/main:InfiniteClipboardUpdate.Program', '/reference:System.dll', $updaterCs)

if (-not (Test-Path -LiteralPath $mainExe) -or -not (Test-Path -LiteralPath $setupExe) -or -not (Test-Path -LiteralPath $updaterExe)) { throw 'Native executable compilation did not produce the expected files.' }

if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force -ErrorAction Stop }
if (Test-Path -LiteralPath $target) { throw 'The previous setup package is still in use. Close any Explorer preview or installer window and run the build again.' }
if (Test-Path -LiteralPath $legacyTarget) { Remove-Item -LiteralPath $legacyTarget -Force -ErrorAction Stop }
Get-ChildItem -LiteralPath $outputDir -Filter '~InfiniteClipboard-*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $outputDir -Filter 'RCXC*.tmp' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$sourcePath = $stagingDir + '\'
$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$target
FriendlyName=InfiniteClipboard Setup
AppLaunched=SetupLauncher.exe
PostInstallCmd=<None>
AdminQuietInstCmd=SetupLauncher.exe
UserQuietInstCmd=SetupLauncher.exe
SourceFiles=SourceFiles
[Strings]
FILE0="SetupLauncher.exe"
FILE1="InfiniteClipboard.exe"
FILE2="UpdateLauncher.exe"
[SourceFiles]
SourceFiles0=$sourcePath
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
"@

Set-Content -LiteralPath $sedPath -Value $sed -Encoding Default
& $iexpress /N /Q /M $sedPath
for ($attempt = 0; $attempt -lt 40 -and -not (Test-Path -LiteralPath $target); $attempt++) { Start-Sleep -Milliseconds 250 }
if (-not (Test-Path -LiteralPath $target)) { throw 'IExpress did not generate the setup package.' }
Start-Sleep -Seconds 1
if ((Get-Item -LiteralPath $target).Length -lt 1024) { throw 'The generated setup package is incomplete.' }

Remove-Item -LiteralPath $sedPath -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $outputDir -Filter '~InfiniteClipboard-*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $outputDir -Filter 'RCXC*.tmp' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$package = Get-Item -LiteralPath $target
Copy-Item -LiteralPath $target -Destination (Join-Path $siteDownloadDir $package.Name) -Force
$hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
$release = [ordered]@{
    version = $appVersion
    downloadUrl = ('download/' + $package.Name)
    sha256 = $hash
    notes = 'Stability improvements and usability updates.'
}
$release | ConvertTo-Json | Set-Content -LiteralPath $releaseFeedPath -Encoding UTF8
Write-Host ("Native setup package created: {0} ({1:N1} MB)" -f $package.FullName, ($package.Length / 1MB))
Write-Host ("Website download file updated: {0}" -f (Join-Path $siteDownloadDir $package.Name))
Write-Host ("Website release feed updated: {0}" -f $releaseFeedPath)
if ($OpenOutputFolder) { Start-Process explorer.exe -ArgumentList ('/select,"' + $target + '"') }
