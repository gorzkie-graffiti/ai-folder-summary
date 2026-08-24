# ============================================================
#  Build-Exe.ps1
#  Compiles FolderSummarizer.ps1 into a standalone .exe
#  Requires: ps2exe module (Install-Module ps2exe -Scope CurrentUser)
# ============================================================

$ErrorActionPreference = "Stop"

# -- Locate the source script -------------------------------------
$scriptDir  = $PSScriptRoot
$sourcePs1  = Join-Path $scriptDir "FolderSummarizer.ps1"
$outputDir  = Join-Path (Split-Path -Parent $scriptDir) "build"
$outputExe  = Join-Path $outputDir "folder-summarizer.exe"

if (-not (Test-Path -LiteralPath $sourcePs1)) {
    Write-Error "FolderSummarizer.ps1 not found at: $sourcePs1"
    exit 1
}

# -- Ensure ps2exe is available ------------------------------------
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing ps2exe module..." -ForegroundColor Cyan
    Install-Module ps2exe -Scope CurrentUser -Force
}

Import-Module ps2exe

# -- Create output directory ---------------------------------------
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Host "[+] Created: $outputDir" -ForegroundColor Green
}

# -- Compile ------------------------------------------------------
Write-Host ""
Write-Host "Compiling..." -ForegroundColor Cyan
Write-Host "  Source: $sourcePs1" -ForegroundColor DarkGray
Write-Host "  Output: $outputExe" -ForegroundColor DarkGray
Write-Host ""

Invoke-ps2exe `
    -InputFile  $sourcePs1 `
    -OutputFile $outputExe `
    -noConsole `
    -title "Folder Summarizer" `
    -iconFile  ""

if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $outputExe)) {
    $size = [math]::Round(((Get-Item $outputExe).Length / 1KB), 1)
    Write-Host "" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "  Build successful!" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "  Output: $outputExe" -ForegroundColor White
    Write-Host "  Size:   ${size} KB" -ForegroundColor White
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "To install:" -ForegroundColor White
    Write-Host "  1. Right-click folder-summarizer.exe > Run as administrator" -ForegroundColor Yellow
    Write-Host "  2. The onboarding wizard will handle everything." -ForegroundColor DarkGray
    Write-Host ""
}
else {
    Write-Error "Build failed. Check errors above."
    exit 1
}
