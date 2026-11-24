# Builds stillit into dist\ as a Windows app (app-image + zip + setup exe).
#
# The JDK, JavaFX SDK, yt-dlp, ffmpeg and Deno are found automatically (see below).
# The easiest setup is to drop yt-dlp.exe, ffmpeg.exe and deno.exe into tools\.
# To point at a specific copy, pass it in, e.g.:
#   .\build.ps1 -Jdk 'C:\Program Files\Java\jdk-26' -Fx 'C:\tools\javafx-sdk-26'
# or set STILLIT_JDK / STILLIT_JAVAFX / STILLIT_YTDLP / STILLIT_FFMPEG / STILLIT_DENO.
param(
    [string]$Jdk    = $env:STILLIT_JDK,
    [string]$Fx     = $env:STILLIT_JAVAFX,
    [string]$YtDlp  = $env:STILLIT_YTDLP,
    [string]$Ffmpeg = $env:STILLIT_FFMPEG,
    [string]$Deno   = $env:STILLIT_DENO
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$SevenZ  = 'C:\Program Files\7-Zip\7z.exe'
$Name    = 'stillit'
$Version = '1.0'

# Sort key that compares the numbers in a path as numbers, so jdk-26 sorts after jdk-9.
function Get-VersionKey([string]$s) {
    [regex]::Replace($s, '\d+', { param($m) $m.Value.PadLeft(6, '0') })
}

# Newest item matching a wildcard path, or $null.
function Find-Newest([string]$pattern) {
    Get-Item -Path $pattern -ErrorAction SilentlyContinue |
        Sort-Object { Get-VersionKey $_.FullName } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

# Full path of an exe on PATH, or $null.
function Find-OnPath([string]$exe) {
    $cmd = Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $cmd.Source } else { $null }
}

# First candidate that exists (and, if $inside is given, contains that file), or $null.
# A plain loop on purpose: piping a list with empty entries through Where-Object
# drops matches in Windows PowerShell 5.1.
function Select-First($candidates, [string]$inside = '') {
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $check = if ($inside) { Join-Path $c $inside } else { $c }
        if (Test-Path $check) { return $c }
    }
    return $null
}

# JDK: JAVA_HOME, then the newest JDK in C:\Program Files\Java. Must include jpackage.
if (-not $Jdk) {
    $Jdk = Select-First @(
        $env:JAVA_HOME,
        (Find-Newest 'C:\Program Files\Java\jdk-*'),
        'C:\Program Files\Java\latest'
    ) 'bin\jpackage.exe'
}

# JavaFX SDK: lib\ in this repo, then Downloads (unzipped there directly or one folder deep).
if (-not $Fx) {
    $Fx = Select-First @(
        (Find-Newest (Join-Path $PSScriptRoot 'lib\javafx-sdk-*')),
        (Find-Newest (Join-Path $HOME 'Downloads\javafx-sdk-*')),
        (Find-Newest (Join-Path $HOME 'Downloads\*\javafx-sdk-*'))
    ) 'lib\javafx.controls.jar'
}

$Tools = Join-Path $PSScriptRoot 'tools'

# yt-dlp: tools\, user folder, then PATH.
if (-not $YtDlp) {
    $YtDlp = Select-First @(
        (Join-Path $Tools 'yt-dlp.exe'),
        (Join-Path $HOME 'yt-dlp.exe'),
        (Find-OnPath 'yt-dlp.exe')
    )
}

# ffmpeg: tools\, the winget package (winget install Gyan.FFmpeg), then PATH.
if (-not $Ffmpeg) {
    $Ffmpeg = Select-First @(
        (Join-Path $Tools 'ffmpeg.exe'),
        (Find-Newest (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Gyan.FFmpeg*\ffmpeg-*\bin\ffmpeg.exe')),
        (Find-OnPath 'ffmpeg.exe')
    )
}

# Deno: yt-dlp needs a JavaScript runtime to get past YouTube's challenges (without one,
# downloads fail with HTTP 403). It's bundled next to yt-dlp.exe, where yt-dlp looks for it.
# Looks in tools\, the official installer's folder, the winget package (winget install DenoLand.Deno), then PATH.
if (-not $Deno) {
    $Deno = Select-First @(
        (Join-Path $Tools 'deno.exe'),
        (Join-Path $HOME '.deno\bin\deno.exe'),
        (Find-Newest (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\DenoLand.Deno*\deno.exe')),
        (Find-OnPath 'deno.exe')
    )
}

$missing = @()
if (-not $Jdk    -or -not (Test-Path $Jdk))    { $missing += 'JDK 25+ with jpackage - install one, set JAVA_HOME, or pass -Jdk <folder>' }
if (-not $Fx     -or -not (Test-Path $Fx))     { $missing += 'JavaFX SDK (Windows x64) - download it from https://gluonhq.com/products/javafx/ and unzip it into lib\, or pass -Fx <folder>' }
if (-not $YtDlp  -or -not (Test-Path $YtDlp))  { $missing += 'yt-dlp.exe - put it in your user folder or on PATH, or pass -YtDlp <file>' }
if (-not $Ffmpeg -or -not (Test-Path $Ffmpeg)) { $missing += 'ffmpeg.exe - run "winget install Gyan.FFmpeg", or pass -Ffmpeg <file>' }
if (-not $Deno   -or -not (Test-Path $Deno))   { $missing += 'deno.exe (YouTube needs it) - get deno-x86_64-pc-windows-msvc.zip from https://github.com/denoland/deno/releases and put deno.exe in tools\, run "winget install DenoLand.Deno", or pass -Deno <file>' }
if ($missing) { throw ("Missing requirements:`n  - " + ($missing -join "`n  - ")) }

Write-Host "JDK:     $Jdk"
Write-Host "JavaFX:  $Fx"
Write-Host "yt-dlp:  $YtDlp"
Write-Host "ffmpeg:  $Ffmpeg"
Write-Host "deno:    $Deno"

foreach ($d in 'build', 'dist') {
    if (Test-Path $d) { Remove-Item -Recurse -Force $d }
}
New-Item -ItemType Directory -Force -Path build\classes, build\app, dist | Out-Null

Write-Host 'Compiling...' -ForegroundColor Cyan
& "$Jdk\bin\javac.exe" -cp "$Fx\lib\*" -d build\classes src\Main.java src\Launcher.java
if ($LASTEXITCODE -ne 0) { throw 'javac failed' }

Copy-Item src\style.css build\classes\
& "$Jdk\bin\jar.exe" --create --file "build\app\$Name.jar" -C build\classes .
if ($LASTEXITCODE -ne 0) { throw 'jar failed' }

Write-Host 'Staging JavaFX + tools...' -ForegroundColor Cyan
foreach ($j in 'javafx.base.jar', 'javafx.controls.jar', 'javafx.graphics.jar', 'javafx.properties') {
    Copy-Item "$Fx\lib\$j" build\app\
}

$skip = 'jfxwebkit.dll', 'jfxmedia.dll', 'gstreamer-lite.dll', 'fxplugins.dll', 'glib-lite.dll'
Get-ChildItem "$Fx\bin\*.dll" | Where-Object { $skip -notcontains $_.Name } |
    ForEach-Object { Copy-Item $_.FullName build\app\ }

Copy-Item $YtDlp  build\app\yt-dlp.exe
Copy-Item $Ffmpeg build\app\ffmpeg.exe
Copy-Item $Deno   build\app\deno.exe

Write-Host 'Running jpackage (this takes a minute)...' -ForegroundColor Cyan
& "$Jdk\bin\jpackage.exe" `
    --type app-image `
    --name $Name `
    --app-version $Version `
    --vendor 'Ryan Pham' `
    --description 'stillit - video and audio downloader' `
    --input build\app `
    --main-jar "$Name.jar" `
    --main-class Launcher `
    --dest dist `
    --add-modules java.base,java.desktop,java.prefs,java.logging,java.scripting,java.xml,jdk.unsupported `
    --java-options '-Djava.library.path=$APPDIR' `
    --java-options '-Dapp.dir=$APPDIR' `
    --java-options '--enable-native-access=ALL-UNNAMED'
if ($LASTEXITCODE -ne 0) { throw 'jpackage failed' }

Copy-Item README.md "dist\$Name\" -ErrorAction SilentlyContinue

if (Test-Path $SevenZ) {
    Write-Host 'Creating zip...' -ForegroundColor Cyan
    & $SevenZ a -tzip -mx=5 "dist\$Name-$Version-portable.zip" ".\dist\$Name" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '7z zip failed' }

    Write-Host 'Creating one-file self-extractor...' -ForegroundColor Cyan
    $archive = "dist\$Name.7z"
    & $SevenZ a -t7z -mx=5 $archive ".\dist\$Name" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '7z archive failed' }

    $sfx = Join-Path (Split-Path $SevenZ) '7z.sfx'
    $out = "dist\$Name-$Version-Setup.exe"
    $dst = [System.IO.File]::Create((Join-Path $PWD $out))
    try {
        foreach ($part in @($sfx, (Join-Path $PWD $archive))) {
            $src = [System.IO.File]::OpenRead($part)
            try { $src.CopyTo($dst) } finally { $src.Dispose() }
        }
    } finally { $dst.Dispose() }
    Remove-Item $archive
} else {
    Write-Warning "7-Zip not found at $SevenZ - falling back to Compress-Archive."
    Compress-Archive -Path "dist\$Name" -DestinationPath "dist\$Name-$Version-portable.zip" -Force
}

Write-Host ''
Write-Host 'Done. Output in dist\:' -ForegroundColor Green
Get-ChildItem dist | Select-Object Name,
    @{n = 'Size'; e = { if ($_.PSIsContainer) { '(folder)' } else { '{0:N1} MB' -f ($_.Length / 1MB) } } } |
    Format-Table -AutoSize
