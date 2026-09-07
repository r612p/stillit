$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$Jdk    = 'C:\Program Files\Java\jdk-25.0.2'
$Fx     = 'C:\Users\ryanp\Downloads\openjfx-25.0.2_windows-x64_bin-sdk\javafx-sdk-25.0.2'
$YtDlp  = 'C:\Users\ryanp\yt-dlp.exe'
$Ffmpeg = 'C:\Users\ryanp\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-9.0-full_build\bin\ffmpeg.exe'
$SevenZ = 'C:\Program Files\7-Zip\7z.exe'
$Name    = 'stillit'
$Version = '1.0'

foreach ($p in @($Jdk, $Fx, $YtDlp, $Ffmpeg)) {
    if (-not (Test-Path $p)) { throw "Missing required path: $p" }
}

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
