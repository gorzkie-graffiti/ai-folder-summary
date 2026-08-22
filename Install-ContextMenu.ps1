# ============================================================
#  Install-ContextMenu.ps1
#  Run this ONCE as Administrator
#  Put both scripts in the same folder before running
# ============================================================

#Requires -RunAsAdministrator

$scriptDir  = "C:\Scripts"
$scriptPath = "$scriptDir\FolderSummarizer.ps1"
$src        = Join-Path $PSScriptRoot "FolderSummarizer.ps1"

# 1. Create C:\Scripts and copy the script there
if (!(Test-Path $scriptDir)) {
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
    Write-Host "[+] Created $scriptDir"
}

if (!(Test-Path $src)) {
    Write-Error "FolderSummarizer.ps1 not found next to this installer. Put both scripts in the same folder."
    exit 1
}

Copy-Item $src $scriptPath -Force
Write-Host "[+] Copied script to $scriptPath"

# 2. Registry — right-click ON a folder
$base = "HKLM:\SOFTWARE\Classes\Directory\shell\FolderSummary"
$cmd  = "$base\command"
New-Item -Path $base -Force | Out-Null
New-Item -Path $cmd  -Force | Out-Null
Set-ItemProperty -Path $base -Name "(Default)" -Value "Summarize with AI"
Set-ItemProperty -Path $base -Name "Icon"      -Value "shell32.dll,21"
Set-ItemProperty -Path $cmd  -Name "(Default)"  `
    -Value "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" `"%V`""

Write-Host "[+] Context menu added for: right-click ON a folder"

# 3. Registry — right-click INSIDE a folder (background)
$bgBase = "HKLM:\SOFTWARE\Classes\Directory\Background\shell\FolderSummary"
$bgCmd  = "$bgBase\command"
New-Item -Path $bgBase -Force | Out-Null
New-Item -Path $bgCmd  -Force | Out-Null
Set-ItemProperty -Path $bgBase -Name "(Default)" -Value "Summarize with AI"
Set-ItemProperty -Path $bgBase -Name "Icon"      -Value "shell32.dll,21"
Set-ItemProperty -Path $bgCmd  -Name "(Default)"  `
    -Value "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" `"%V`""

Write-Host "[+] Context menu added for: right-click INSIDE a folder (background)"

Write-Host ""
Write-Host "Done. Right-click any folder > 'Summarize with AI'"
Write-Host ""
Write-Host "If you want to remove it later, delete these registry keys:"
Write-Host "  HKLM:\SOFTWARE\Classes\Directory\shell\FolderSummary"
Write-Host "  HKLM:\SOFTWARE\Classes\Directory\Background\shell\FolderSummary"
