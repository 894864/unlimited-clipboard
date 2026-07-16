param(
    [switch]$OpenOutputFolder,
    [string]$UpdateFeedUrl = 'https://unlimited-clipboard.cetle.cn/releases.json'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appVersion = '1.0.2'
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
$iconSourcePath = Join-Path $root 'assets\app-icon-12.png'

function Convert-BitmapToIconDib([System.Drawing.Bitmap]$Bitmap) {
    $size = $Bitmap.Width
    $xorBytes = $size * $size * 4
    $maskStride = [int]([Math]::Ceiling($size / 32.0) * 4)
    $maskBytes = $maskStride * $size
    $memory = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($memory)
    try {
        $writer.Write([uint32]40)
        $writer.Write([int32]$size)
        $writer.Write([int32]($size * 2))
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]0)
        $writer.Write([uint32]$xorBytes)
        $writer.Write([int32]0)
        $writer.Write([int32]0)
        $writer.Write([uint32]0)
        $writer.Write([uint32]0)
        for ($y = $size - 1; $y -ge 0; $y--) {
            for ($x = 0; $x -lt $size; $x++) {
                $pixel = $Bitmap.GetPixel($x, $y)
                $writer.Write([byte]$pixel.B)
                $writer.Write([byte]$pixel.G)
                $writer.Write([byte]$pixel.R)
                $writer.Write([byte]$pixel.A)
            }
        }
        $writer.Write([byte[]]::new($maskBytes))
        $writer.Flush()
        return ,$memory.ToArray()
    } finally {
        $writer.Dispose()
        $memory.Dispose()
    }
}

function New-AppIcon([string]$Path, [string]$SourcePath) {
    Add-Type -AssemblyName System.Drawing
    if (-not (Test-Path -LiteralPath $SourcePath)) { throw "App icon source is missing: $SourcePath" }
    $source = [System.Drawing.Image]::FromFile($SourcePath)
    $entries = @()
    try {
        foreach ($size in @(16, 24, 32, 48, 64, 256)) {
            $bitmap = [System.Drawing.Bitmap]::new($size, $size)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.DrawImage($source, [System.Drawing.Rectangle]::new(0, 0, $size, $size))
                $entries += [pscustomobject]@{ Size = $size; Data = (Convert-BitmapToIconDib $bitmap) }
            } finally {
                $graphics.Dispose()
                $bitmap.Dispose()
            }
        }
    } finally {
        $source.Dispose()
    }

    $stream = [System.IO.File]::Create($Path)
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$entries.Count)
        $offset = 6 + (16 * $entries.Count)
        foreach ($entry in $entries) {
            $dimension = if ($entry.Size -eq 256) { [byte]0 } else { [byte]$entry.Size }
            $writer.Write($dimension)
            $writer.Write($dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$entry.Data.Length)
            $writer.Write([uint32]$offset)
            $offset += $entry.Data.Length
        }
        foreach ($entry in $entries) { $writer.Write([byte[]]$entry.Data) }
    } finally {
        $writer.Dispose()
    }
}

New-AppIcon $iconPath $iconSourcePath

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
Invoke-Csc @('/nologo', '/target:winexe', ('/out:' + $setupExe), ('/win32icon:' + $iconPath), '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll', '/reference:System.dll', $setupCs)
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
    notes = 'Adds a guided installer, custom conflict-checked hotkeys, in-app uninstall, UI font sizes, and usability fixes.'
}
$release | ConvertTo-Json | Set-Content -LiteralPath $releaseFeedPath -Encoding UTF8
Write-Host ("Native setup package created: {0} ({1:N1} MB)" -f $package.FullName, ($package.Length / 1MB))
Write-Host ("Website download file updated: {0}" -f (Join-Path $siteDownloadDir $package.Name))
Write-Host ("Website release feed updated: {0}" -f $releaseFeedPath)
if ($OpenOutputFolder) { Start-Process explorer.exe -ArgumentList ('/select,"' + $target + '"') }
