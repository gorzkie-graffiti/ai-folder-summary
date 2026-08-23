# ============================================================
#  Install-ContextMenu.ps1
#  Run this ONCE as Administrator
# ============================================================

#Requires -RunAsAdministrator

param(
    # FIX: install directory is now a configurable parameter instead of
    # being hardcoded to C:\Scripts. Defaults to Program Files\FolderSummarizer.
    [string]$InstallDir = (Join-Path $env:ProgramFiles "FolderSummarizer")
)

$ErrorActionPreference = "Stop"

$srcScript  = Join-Path $PSScriptRoot "FolderSummarizer.ps1"
$srcWrapper = Join-Path $PSScriptRoot "Run-FolderSummarizer.cmd"

$dstScript  = Join-Path $InstallDir "FolderSummarizer.ps1"
$dstWrapper = Join-Path $InstallDir "Run-FolderSummarizer.cmd"

# ------------------------------------------------------------
# 1. Validate source files
# ------------------------------------------------------------

if (!(Test-Path -LiteralPath $srcScript)) {
    Write-Error "FolderSummarizer.ps1 not found next to this installer."
    exit 1
}

if (!(Test-Path -LiteralPath $srcWrapper)) {
    Write-Error "Run-FolderSummarizer.cmd not found next to this installer."
    exit 1
}

# ------------------------------------------------------------
# 2. Create install directory
# ------------------------------------------------------------

if (!(Test-Path -LiteralPath $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "[+] Created $InstallDir" -ForegroundColor Green
}
else {
    Write-Host "[=] Install directory exists: $InstallDir" -ForegroundColor DarkGray
}

# ------------------------------------------------------------
# 3. Copy application files
# ------------------------------------------------------------

Copy-Item -LiteralPath $srcScript  -Destination $dstScript  -Force
Write-Host "[+] Copied $dstScript" -ForegroundColor Green

Copy-Item -LiteralPath $srcWrapper -Destination $dstWrapper -Force
Write-Host "[+] Copied $dstWrapper" -ForegroundColor Green

# ------------------------------------------------------------
# 4. Registry command
# ------------------------------------------------------------

# cmd.exe launches the wrapper; use the resolved install path
$escapedWrapper = $dstWrapper.Replace('"', '""')
$wrapperCommand = "cmd.exe /d /c `"`"$escapedWrapper`" `"%V`"`""

# ------------------------------------------------------------
# 5. Right-click ON a folder
# ------------------------------------------------------------

$base = "HKLM:\SOFTWARE\Classes\Directory\shell\FolderSummary"
$cmd  = "$base\command"

New-Item -Path $base -Force | Out-Null
New-Item -Path $cmd  -Force | Out-Null

Set-ItemProperty -Path $base -Name "(Default)" -Value "Summarize with AI"
Set-ItemProperty -Path $base -Name "Icon" -Value "shell32.dll,21"
Set-ItemProperty -Path $cmd  -Name "(Default)" -Value $wrapperCommand

Write-Host "[+] Context menu added for: right-click ON a folder" -ForegroundColor Green

# ------------------------------------------------------------
# 6. Right-click INSIDE a folder
# ------------------------------------------------------------

$bgBase = "HKLM:\SOFTWARE\Classes\Directory\Background\shell\FolderSummary"
$bgCmd  = "$bgBase\command"

New-Item -Path $bgBase -Force | Out-Null
New-Item -Path $bgCmd  -Force | Out-Null

Set-ItemProperty -Path $bgBase -Name "(Default)" -Value "Summarize with AI"
Set-ItemProperty -Path $bgBase -Name "Icon" -Value "shell32.dll,21"
Set-ItemProperty -Path $bgCmd  -Name "(Default)" -Value $wrapperCommand

Write-Host "[+] Context menu added for: right-click INSIDE a folder" -ForegroundColor Green

# ------------------------------------------------------------
# 7. Done
# ------------------------------------------------------------

Write-Host ""
Write-Host "Done. Right-click any folder > 'Summarize with AI'" -ForegroundColor Cyan
Write-Host ""
Write-Host "Installed files:"
Write-Host "  $dstScript"
Write-Host "  $dstWrapper"
Write-Host ""
Write-Host "To remove the context menu later, run from an elevated PowerShell:"
Write-Host "  Remove-Item -Path 'HKLM:\SOFTWARE\Classes\Directory\shell\FolderSummary' -Recurse -Force"
Write-Host "  Remove-Item -Path 'HKLM:\SOFTWARE\Classes\Directory\Background\shell\FolderSummary' -Recurse -Force"
Write-Host "  Remove-Item -Path '$InstallDir' -Recurse -Force"
Write-Host ""

exit 0
