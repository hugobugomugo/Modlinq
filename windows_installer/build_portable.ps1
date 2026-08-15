# builds the portable windows zip

param(
    [string]$Version = "0.0.0"
)

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "error: flutter not found in PATH" -ForegroundColor Red
    exit 1
}

Write-Host "[1/3] building flutter windows release" -ForegroundColor Green
Set-Location -Path "mod_manager_flutter"
flutter build windows --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "error: flutter build failed" -ForegroundColor Red
    Set-Location -Path ".."
    exit $LASTEXITCODE
}

Set-Location -Path ".."

Write-Host "[2/3] staging portable tree" -ForegroundColor Green

$buildPath = "mod_manager_flutter\build\windows\x64\runner\Release"
$outputDir = "windows_installer\output"
$portableName = "modlinq-$Version-windows-x64"
$portablePath = "$outputDir\$portableName"

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

if (Test-Path $portablePath) {
    Remove-Item -Path $portablePath -Recurse -Force
}

New-Item -ItemType Directory -Path $portablePath | Out-Null
Copy-Item -Path "$buildPath\*" -Destination $portablePath -Recurse -Force

if (Test-Path "assets\icon.png") {
    $assetsPath = "$portablePath\data\flutter_assets\assets"
    if (-not (Test-Path $assetsPath)) {
        New-Item -ItemType Directory -Path $assetsPath -Force | Out-Null
    }
    Copy-Item -Path "assets\icon.png" -Destination $assetsPath -Force
}

$readmeContent = @"
Modlinq $Version (portable)

Unpack anywhere and run modlinq.exe. No installation required.

Mod symlinks need administrator rights. Either run Run_As_Admin.bat,
or enable Developer Mode in Windows settings to allow symlinks without admin.

Requires Windows 10 or newer (x64).

To uninstall, delete this folder. Settings live in %APPDATA%\modlinq.

https://github.com/hugobugomugo/Modlinq
"@

Set-Content -Path "$portablePath\README.txt" -Value $readmeContent -Encoding UTF8

$runAsAdminContent = @"
@echo off
net session >nul 2>&1
if %errorLevel% == 0 (
    start "" "%~dp0modlinq.exe"
) else (
    powershell -Command "Start-Process '%~dp0modlinq.exe' -Verb RunAs"
)
"@

Set-Content -Path "$portablePath\Run_As_Admin.bat" -Value $runAsAdminContent -Encoding ASCII

Write-Host "[3/3] creating zip" -ForegroundColor Green

$zipPath = "$outputDir\$portableName.zip"
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}

# zip the contents, not the wrapper folder, so the updater can swap in place
Compress-Archive -Path "$portablePath\*" -DestinationPath $zipPath -CompressionLevel Optimal

Remove-Item -Path $portablePath -Recurse -Force

$zipSize = (Get-Item $zipPath).Length / 1MB
Write-Host "done: $zipPath ($([math]::Round($zipSize, 2)) MB)" -ForegroundColor Green
