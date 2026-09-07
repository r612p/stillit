$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$Name    = 'stillit'
$Source  = Join-Path $PSScriptRoot "dist\$Name"
$Target  = Join-Path $env:LOCALAPPDATA "Programs\$Name"
$Exe     = Join-Path $Target "$Name.exe"

if (-not (Test-Path $Source)) {
    throw "Nothing to install: $Source not found. Run build.ps1 first."
}

$running = Get-Process -Name $Name -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "Closing running $Name..." -ForegroundColor Yellow
    $running | Stop-Process -Force
    Start-Sleep -Seconds 2
}

if (Test-Path $Target) {
    Write-Host "Replacing existing install at $Target" -ForegroundColor Yellow
    Remove-Item -Recurse -Force $Target
}

Write-Host "Installing to $Target ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path (Split-Path $Target) | Out-Null
Copy-Item -Recurse $Source $Target

if (-not (Test-Path $Exe)) { throw "Install looks wrong: $Exe is missing." }

$shell     = New-Object -ComObject WScript.Shell
$startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$Name.lnk"
$desktop   = Join-Path ([Environment]::GetFolderPath('Desktop')) "$Name.lnk"

foreach ($linkPath in @($startMenu, $desktop)) {
    $lnk = $shell.CreateShortcut($linkPath)
    $lnk.TargetPath       = $Exe
    $lnk.WorkingDirectory = $Target
    $lnk.Description      = 'downloader'
    $lnk.Save()
    Write-Host "  shortcut: $linkPath"
}

$size = (Get-ChildItem -Recurse $Target | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host ''
Write-Host ('Installed {0} ({1:N0} MB). Search the Start Menu for "{0}".' -f $Name, $size) -ForegroundColor Green
