$ErrorActionPreference = 'Stop'

$Name   = 'stillit'
$Target = Join-Path $env:LOCALAPPDATA "Programs\$Name"

$running = Get-Process -Name $Name -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "Closing running $Name..." -ForegroundColor Yellow
    $running | Stop-Process -Force
    Start-Sleep -Seconds 2
}

$shortcuts = @(
    (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$Name.lnk"),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) "$Name.lnk")
)

foreach ($s in $shortcuts) {
    if (Test-Path $s) { Remove-Item -Force $s; Write-Host "removed $s" }
}

if (Test-Path $Target) {
    Remove-Item -Recurse -Force $Target
    Write-Host "removed $Target"
    Write-Host "$Name uninstalled." -ForegroundColor Green
} else {
    Write-Host "$Name was not installed at $Target." -ForegroundColor Yellow
}
