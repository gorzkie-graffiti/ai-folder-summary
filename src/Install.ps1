# ============================================================
#  Install.ps1 — One-step setup for Folder Summarizer
#  Run: .\Install.ps1
#  Run: .\Install.ps1 -RegisterContextMenu
# ============================================================

param(
    [switch]$RegisterContextMenu
)

# -- Create config directory and default config ----------------

$homeConfig = Join-Path $env:USERPROFILE ".folder-summarizer"
$configFile = Join-Path $homeConfig "config.yaml"

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Folder Summarizer - Setup" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -LiteralPath $homeConfig)) {
    New-Item -ItemType Directory -Path $homeConfig -Force | Out-Null
    Write-Host "[+] Created config directory: $homeConfig" -ForegroundColor Green
}
else {
    Write-Host "[=] Config directory exists: $homeConfig" -ForegroundColor DarkGray
}

if (-not (Test-Path -LiteralPath $configFile)) {

    # Single-quoted here-string:
    # everything inside is treated as literal text.
    $default = @'
# ============================================================
#  Folder Summarizer - Configuration
#  Edit this file to customize behavior.
# ============================================================

# Google Gemini API key (required)
api_key: "YOUR_KEY_HERE"

# AI model to use
model: "gemini-3.5-flash"

# Sampling: how many files to include per category
sampling:
  max_files_per_group: 5

  # Which file categories to scan
  groups:
    include: ["Images", "Documents", "Code", "Audio", "Video", "Archives"]
    exclude: []            # e.g., ["Archives"] to skip archives

  # Extension filtering
  extensions:
    whitelist: []          # empty = all extensions allowed
    blacklist: [".exe", ".dll", ".pyc", ".class"]

# Video file handling
video:
  sample_frames: 5
  sample_only_metadata: true  # true = just get duration/resolution/codec

# Security: sensitive file detection & redaction
security:
  # Files matching these filename patterns are flagged
  sensitive_patterns:
    - "credential"
    - "password"
    - "secret"
    - "token"
    - "recovery"
    - "key"
    - "\\.pem$"
    - "\\.key$"

  # Text files are scanned for these content patterns
  content_regex:
    - "BEGIN (RSA|OPENSSH|DSA) PRIVATE KEY"
    - "sk-[a-zA-Z0-9]{20,}"       # OpenAI API keys
    - "gh[pousr]_[a-zA-Z0-9]{36}" # GitHub tokens

  # What to do with sensitive files:
  # "mask" = show [REDACTED]
  # "skip" = hide entirely
  action: "mask"

# UI language
ui:
  detect_windows_language: true
  override_language: ""           # e.g. "pl-PL"
'@

    $default | Set-Content -LiteralPath $configFile -Encoding UTF8

    Write-Host "[+] Wrote default config to: $configFile" -ForegroundColor Green
    Write-Host "    Edit this file to set your API key and preferences." -ForegroundColor DarkGray
}
else {
    Write-Host "[=] Config file exists: $configFile" -ForegroundColor DarkGray
}

# -- Check runtime dependencies ---------------------------------

Write-Host ""
Write-Host "Checking dependencies..." -ForegroundColor Cyan

# ffmpeg
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    Write-Host "  [OK] ffmpeg found" -ForegroundColor Green
}
else {
    Write-Host "  [!!] ffmpeg NOT found - video metadata will be unavailable" -ForegroundColor Yellow
    Write-Host "       Install: https://ffmpeg.org/download.html" -ForegroundColor DarkGray
}

# Python (optional)
if (Get-Command python -ErrorAction SilentlyContinue) {
    Write-Host "  [OK] Python found (optional)" -ForegroundColor Green
}
else {
    Write-Host "  [--] Python not found (optional, not required)" -ForegroundColor DarkGray
}

# -- Context menu registration ----------------------------------

$contextMenuRegistered = $false

if ($RegisterContextMenu) {
    Write-Host ""
    Write-Host "Registering Windows context menu..." -ForegroundColor Cyan

    $installScript = Join-Path $PSScriptRoot "Install-ContextMenu.ps1"

    if (Test-Path -LiteralPath $installScript) {

        powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $installScript

        if ($LASTEXITCODE -eq 0) {
            $contextMenuRegistered = $true
        }
        else {
            Write-Host ""
            Write-Host "  [!!] Context menu registration failed." -ForegroundColor Red
        }
    }
    else {
        Write-Host "  [!!] Install-ContextMenu.ps1 not found alongside Install.ps1" -ForegroundColor Red
    }
}
# -- Final instructions -----------------------------------------

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
if ($RegisterContextMenu -and $contextMenuRegistered) {
    Write-Host "  Setup complete!" -ForegroundColor Green
}
elseif ($RegisterContextMenu) {
    Write-Host "  Setup completed with errors." -ForegroundColor Yellow
}
else {
    Write-Host "  Setup complete!" -ForegroundColor Green
}
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Next steps:" -ForegroundColor White

Write-Host "  1. Edit your config:" -ForegroundColor White
Write-Host "     $configFile" -ForegroundColor Yellow
Write-Host "     Set 'api_key' to your Google Gemini API key." -ForegroundColor DarkGray
Write-Host ""

Write-Host "  2. To add the right-click context menu:" -ForegroundColor White
Write-Host "     .\Install.ps1 -RegisterContextMenu" -ForegroundColor Yellow
Write-Host "     (Run as Administrator)" -ForegroundColor DarkGray
Write-Host ""

Write-Host "  3. Right-click any folder > 'Summarize with AI'" -ForegroundColor White
Write-Host ""