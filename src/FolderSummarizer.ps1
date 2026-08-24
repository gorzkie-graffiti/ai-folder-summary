# ============================================================
#  FolderSummarizer.ps1 — Self-installing AI Folder Summarizer
# ============================================================
#  Compile to .exe with ps2exe, then just run the exe.
#  It copies itself to C:\Scripts\, registers the right-click
#  context menu, runs onboarding, and summarizes folders.
# ============================================================

param(
    [string]$FolderPath,
    [switch]$Uninstall,
    [switch]$Settings
)

# ============================================================
#  CONSTANTS
# ============================================================

$script:INSTALL_DIR   = "C:\Scripts"
$script:EXE_NAME      = "folder-summarizer.exe"
$script:INSTALL_PATH  = Join-Path $script:INSTALL_DIR $script:EXE_NAME
$script:CONFIG_DIR    = Join-Path $env:USERPROFILE ".folder-summarizer"
$script:CONFIG_FILE   = Join-Path $script:CONFIG_DIR "config.yaml"
$script:REGISTRY_BASE = "HKLM:\SOFTWARE\Classes\Directory\shell\FolderSummary"
$script:REGISTRY_BG   = "HKLM:\SOFTWARE\Classes\Directory\Background\shell\FolderSummary"

# ============================================================
#  ARG RESOLUTION
#  When compiled to .exe, named params may not bind.
#  ps2exe passes positional args via $args.
# ============================================================

if ([string]::IsNullOrWhiteSpace($FolderPath) -and $args.Count -gt 0) {
    # First positional arg could be a switch-like string or a path.
    $firstArg = $args[0]
    if ($firstArg -eq "--uninstall" -or $firstArg -eq "-Uninstall") {
        $Uninstall = $true
    }
    elseif ($firstArg -eq "--settings" -or $firstArg -eq "-Settings") {
        $Settings = $true
    }
    else {
        $FolderPath = $firstArg
    }
}

# ============================================================
#  DETECT RUNNING MODE
# ============================================================

$script:MyPath = $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($script:MyPath)) {
    $script:MyPath = $MyInvocation.MyCommand.Path
}
# When compiled to exe, $MyInvocation may not reflect the real path.
# Fall back to [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if ([string]::IsNullOrWhiteSpace($script:MyPath) -or 
    -not (Test-Path -LiteralPath $script:MyPath -ErrorAction SilentlyContinue)) {
    try {
        $script:MyPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    } catch { }
}

$script:IsInstalled = ($script:MyPath -eq $script:INSTALL_PATH)

# ============================================================
#  LOAD WINDOWS FORMS
# ============================================================

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# ============================================================
#  YAML PARSER (minimal, no dependencies)
# ============================================================

function Parse-YAML {
    param([string[]]$Lines)
    $root = [ordered]@{}
    $stack = [System.Collections.Stack]::new()
    $current = $root
    $currentIndent = 0

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }

        $trimmed = $line.TrimEnd()
        $leadingSpaces = $trimmed.Length - $trimmed.TrimStart().Length

        while ($stack.Count -gt 0 -and $leadingSpaces -lt $currentIndent) {
            $pop = $stack.Pop()
            $current = $pop.Context
            $currentIndent = $pop.Indent
        }

        $cleanLine = $trimmed -replace '\s*#.*$', ''

        if ($cleanLine -match '^(\s*)- (.+)$') {
            $arrayIndent = $Matches[1].Length
            $content = $Matches[2].Trim()

            if ($content -match '^([^:]+):\s*(.+)$') {
                $k = $Matches[1].Trim().Trim('"')
                $v = $Matches[2].Trim().Trim('"')
                $newObj = [ordered]@{ $k = $v }
                $current.Add($newObj)
                $stack.Push(@{ Context = $current; Indent = $currentIndent })
                $current = $newObj
                $currentIndent = $arrayIndent + 2
            }
            else {
                $val = $content.Trim('"')
                $current.Add($val)
            }
            continue
        }

        if ($cleanLine -match '^([^:]+?):\s*(.*)$') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()

            if ([string]::IsNullOrEmpty($value)) {
                $lookAheadIndex = $i + 1
                $isDict = $true
                while ($lookAheadIndex -lt $Lines.Count) {
                    $laLine = $Lines[$lookAheadIndex]
                    if ($laLine -match '^\s*$' -or $laLine -match '^\s*#') { $lookAheadIndex++; continue }
                    $laClean = ($laLine.TrimEnd() -replace '\s*#.*$', '')
                    if ($laClean -match '^\s*- ') { $isDict = $false }
                    break
                }

                if ($isDict) {
                    $newObj = [ordered]@{}
                    $current[$key] = $newObj
                    $stack.Push(@{ Context = $current; Indent = $currentIndent })
                    $current = $newObj
                    $currentIndent = $leadingSpaces + 2
                }
                else {
                    $arr = [System.Collections.ArrayList]::new()
                    $current[$key] = $arr
                    $stack.Push(@{ Context = $current; Indent = $currentIndent })
                    $current = $arr
                    $currentIndent = $leadingSpaces + 2
                }
            }
            else {
                $current[$key] = $value.Trim('"')
            }
        }
    }
    return $root
}

# ============================================================
#  CONFIG
# ============================================================

function Get-DefaultConfig {
    return [ordered]@{
        api_key = ""
        model   = "gemini-2.5-flash"
        sampling = [ordered]@{
            max_files_per_group = 5
            groups = [ordered]@{
                include = @("Images","Documents","Code","Audio","Video","Archives")
                exclude = @()
            }
            extensions = [ordered]@{
                whitelist = @()
                blacklist = @(".exe",".dll",".pyc",".class")
            }
        }
        video = [ordered]@{
            sample_frames        = 5
            sample_only_metadata = $true
        }
        security = [ordered]@{
            sensitive_patterns = @("credential","password","secret","token","recovery","key","\.pem$","\.key$","tax","financial","medical","bank","insurance","passport","id-","identity")
            content_regex      = @("BEGIN (RSA|OPENSSH|DSA) PRIVATE KEY","sk-[a-zA-Z0-9]{20,}","gh[pousr]_[a-zA-Z0-9]{36}")
            action             = "mask"
        }
        ui = [ordered]@{
            detect_windows_language = $true
            override_language       = ""
            warning_accepted        = $false
        }
    }
}

function Load-Config {
    if (-not (Test-Path -LiteralPath $script:CONFIG_FILE)) {
        return Get-DefaultConfig
    }
    try {
        $raw = [System.IO.File]::ReadAllText($script:CONFIG_FILE, [System.Text.Encoding]::UTF8)
        $config = Get-DefaultConfig

        $apiMatch = [regex]::Match($raw, '(?m)^\s*api_key\s*:\s*["'']?([^"''\r\n]+)["'']?\s*$')
        if ($apiMatch.Success) { $config["api_key"] = $apiMatch.Groups[1].Value.Trim() }

        $modelMatch = [regex]::Match($raw, '(?m)^\s*model\s*:\s*["'']?([^"''\r\n]+)["'']?\s*$')
        if ($modelMatch.Success) { $config["model"] = $modelMatch.Groups[1].Value.Trim() }

        try {
            $parsed = Parse-YAML ($raw -split "`r?\n")
            if ($parsed -is [System.Collections.IDictionary]) {
                foreach ($key in $parsed.Keys) {
                    if ($key -ne "api_key" -and $key -ne "model") {
                        $config[$key] = $parsed[$key]
                    }
                }
            }
        } catch { }

        return $config
    } catch {
        return Get-DefaultConfig
    }
}

function Save-Config {
    param([object]$Config)

    if (-not (Test-Path -LiteralPath $script:CONFIG_DIR)) {
        New-Item -ItemType Directory -Path $script:CONFIG_DIR -Force | Out-Null
    }

    $apiKey = $Config["api_key"]
    if ([string]::IsNullOrWhiteSpace($apiKey)) { $apiKey = "" }

    # Read existing file to preserve comments and unknown keys, then patch known values
    if (Test-Path -LiteralPath $script:CONFIG_FILE) {
        $existing = [System.IO.File]::ReadAllText($script:CONFIG_FILE, [System.Text.Encoding]::UTF8)
        # Patch api_key
        if ($existing -match '(?m)^(\s*api_key\s*:\s*)["'']?[^
]*["'']?(\s*(?:#.*)?)$') {
            $existing = $existing -replace '(?m)^(\s*api_key\s*:\s*)["'']?[^
]*["'']?(\s*(?:#.*)?)$', ("`$1\"$apiKey\"`$2")
        }
        else {
            $existing = "api_key: `"$apiKey`"`n" + $existing
        }
        [System.IO.File]::WriteAllText($script:CONFIG_FILE, $existing, [System.Text.Encoding]::UTF8)
    }
    else {
        $default = Get-DefaultConfig
        $default["api_key"] = $apiKey
        # Write a clean default config with the api key set
        $yaml = @"
# Folder Summarizer - Configuration
# Edit this file to customize behavior.

# Google Gemini API key (required)
api_key: "$apiKey"

# AI model to use
model: "$($default.model)"

# Sampling: how many files to include per category
sampling:
  max_files_per_group: $($default.sampling.max_files_per_group)
  groups:
    include: $(($default.sampling.groups.include | ForEach-Object { "`"$_`"" }) -join ', ')
    exclude: []
  extensions:
    whitelist: []
    blacklist: $(($default.sampling.extensions.blacklist | ForEach-Object { "`"$_`"" }) -join ', ')

# Video file handling (requires ffprobe in PATH)
video:
  sample_frames: $($default.video.sample_frames)
  sample_only_metadata: $($default.video.sample_only_metadata.ToString().ToLower())

# Security: sensitive file detection & redaction
security:
  sensitive_patterns:
$(($default.security.sensitive_patterns | ForEach-Object { "    - `"$_`"" }) -join "`n")
  content_regex:
$(($default.security.content_regex | ForEach-Object { "    - `"$_`"" }) -join "`n")
  action: "$($default.security.action)"

# UI settings
ui:
  detect_windows_language: $($default.ui.detect_windows_language.ToString().ToLower())
  override_language: "$($default.ui.override_language)"
  warning_accepted: $($default.ui.warning_accepted.ToString().ToLower())
"@
        [System.IO.File]::WriteAllText($script:CONFIG_FILE, $yaml, [System.Text.Encoding]::UTF8)
    }
}

function Get-ConfigValue {
    param(
        [object]$Config,
        [string]$Path,
        [object]$Default = $null
    )
    $keys = $Path -split '\.'
    $current = $Config
    foreach ($k in $keys) {
        if ($null -eq $current -or -not ($current -is [System.Collections.IDictionary])) { return $Default }
        if (-not $current.Contains($k)) { return $Default }
        $current = $current[$k]
    }
    return $current
}

# ============================================================
#  SENSITIVE FILE HANDLING
# ============================================================

$script:SensitivePatterns = $null
$script:ContentRegexes    = $null

function Init-SensitivePatterns {
    param([object]$Config)
    $script:SensitivePatterns = Get-ConfigValue $Config "security.sensitive_patterns" @()
    $script:ContentRegexes    = Get-ConfigValue $Config "security.content_regex" @()
}

function Test-SensitiveName {
    param([string]$Name)
    foreach ($pat in $script:SensitivePatterns) {
        try { if ($Name -match "(?i)$pat") { return $true } } catch { continue }
    }
    return $false
}

function Get-SensitivePathComponents {
    param([string]$Path)
    $segments = @($Path -split '[\\/]')
    $sensitiveIndices = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $segments.Count; $i++) {
        if (Test-SensitiveName $segments[$i]) { $sensitiveIndices.Add($i) }
    }
    return @{ Segments = $segments; SensitiveIndices = $sensitiveIndices }
}

function Get-RedactedPath {
    param([string]$Path)
    $analysis = Get-SensitivePathComponents -Path $Path
    $result = @($analysis.Segments | ForEach-Object { $_ })
    foreach ($idx in $analysis.SensitiveIndices) { $result[$idx] = "[REDACTED]" }
    return $result -join '\'
}

function Test-SensitiveContent {
    param([string]$FilePath)
    $textExts = @(".txt",".md",".json",".yaml",".yml",".py",".js",".ts",".html",".css",".xml",".csv",".log",".conf",".ini",".ps1",".sh",".bat",".cmd",".cs",".java",".go",".rs",".rb",".php",".toml",".cfg")
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    if ($textExts -notcontains $ext) { return $false }
    try {
        $rawText = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
        $content = if ($rawText.Length -gt 4096) { $rawText.Substring(0, 4096) } else { $rawText }
        foreach ($regex in $script:ContentRegexes) {
            try { if ($content -match $regex) { return $true } } catch { continue }
        }
    } catch { }
    return $false
}

# ============================================================
#  FILE CATEGORIZATION & SAMPLING
# ============================================================

function Get-CategoryFileGroups {
    param([array]$AllFiles, [object]$Config)

    $samplingConfig = Get-ConfigValue $Config "sampling" @()
    $maxFiles = if ($samplingConfig -and $samplingConfig.Contains('max_files_per_group')) {
        [int]$samplingConfig['max_files_per_group']
    } else { 5 }

    $includeGroups = if ($samplingConfig -and $samplingConfig.Contains('groups') -and $samplingConfig['groups'].Contains('include')) {
        $samplingConfig['groups']['include']
    } else { @("Images","Documents","Code","Audio","Video","Archives") }

    $excludeGroups = if ($samplingConfig -and $samplingConfig.Contains('groups') -and $samplingConfig['groups'].Contains('exclude')) {
        $samplingConfig['groups']['exclude']
    } else { @() }

    $extConfig = Get-ConfigValue $Config "sampling.extensions" @()
    $whitelist = if ($extConfig -and $extConfig.Contains('whitelist')) { $extConfig['whitelist'] } else { @() }
    $blacklist  = if ($extConfig -and $extConfig.Contains('blacklist')) { $extConfig['blacklist'] } else { @() }

    $extMap = [ordered]@{
        "Images"    = @(".jpg",".jpeg",".png",".gif",".bmp",".webp",".tiff",".svg",".raw",".heic",".avif",".ico")
        "Documents" = @(".pdf",".docx",".doc",".txt",".xlsx",".xls",".pptx",".ppt",".md",".csv",".rtf",".odt",".pages")
        "Video"     = @(".mp4",".avi",".mkv",".mov",".wmv",".flv",".webm",".m4v",".mpg",".mpeg")
        "Audio"     = @(".mp3",".wav",".flac",".aac",".ogg",".wma",".m4a",".opus",".aiff")
        "Code"      = @(".py",".js",".ts",".cs",".cpp",".c",".java",".go",".rs",".php",".html",".css",".ps1",".sh",".bat",".json",".yaml",".toml",".lua",".rb",".swift",".kt")
        "Archives"  = @(".zip",".rar",".7z",".tar",".gz",".bz2",".xz",".cab",".iso")
    }

    $result = [ordered]@{
        CategoryLines    = [System.Collections.Generic.List[string]]::new()
        PromptCategories = [System.Collections.Generic.List[string]]::new()
    }

    foreach ($cat in $extMap.GetEnumerator()) {
        if ($includeGroups -notcontains $cat.Key) { continue }
        if ($excludeGroups -contains $cat.Key) { continue }

        $filteredExts = @($cat.Value | Where-Object {
            $ext = $_.ToLower()
            if ($whitelist.Count -gt 0 -and $whitelist -notcontains $ext) { return $false }
            if ($blacklist.Count -gt 0 -and $blacklist -contains $ext) { return $false }
            return $true
        })

        $matched = @($AllFiles | Where-Object {
            $filteredExts -contains $_.Extension.ToLower() -and
            -not (Test-SensitiveName $_.Name) -and
            -not (Test-SensitiveContent $_.FullName)
        })
        if ($matched.Count -gt 0) {
            $sample = ($matched | Select-Object -First $maxFiles | ForEach-Object { $_.Name }) -join ", "
            $result.CategoryLines.Add("  $($cat.Key.PadRight(12)) [$($matched.Count.ToString().PadLeft(4))] : $sample")
            $result.PromptCategories.Add("$($cat.Key) ($($matched.Count) total) - checked: $sample")
        }
    }
    return $result
}

# ============================================================
#  WINDOWS LANGUAGE DETECTION
# ============================================================

function Get-WindowsLanguage {
    param([object]$Config)
    $detectLanguage = Get-ConfigValue $Config "ui.detect_windows_language" $true
    $override       = Get-ConfigValue $Config "ui.override_language" ""
    if (-not [string]::IsNullOrEmpty($override)) { return $override }
    if (-not $detectLanguage) { return "en" }
    try {
        $langList = Get-WinUserLanguageList -ErrorAction SilentlyContinue
        if ($langList -and $langList.Count -gt 0) { return $langList[0].LanguageTag }
    } catch { }
    try { return (Get-UICulture).Name } catch { }
    return "en"
}

# ============================================================
#  VIDEO METADATA (ffprobe)
# ============================================================

function Get-VideoMetadata {
    param([string]$VideoPath, [object]$Config)
    $videoConfig = Get-ConfigValue $Config "video" @()
    $sampleOnlyMetadata = if ($videoConfig -and $videoConfig.Contains('sample_only_metadata')) {
        [bool]$videoConfig['sample_only_metadata']
    } else { $true }
    $sampleFrames = if ($videoConfig -and $videoConfig.Contains('sample_frames')) {
        [int]$videoConfig['sample_frames']
    } else { 5 }

    $result = [ordered]@{ Duration = ""; Resolution = ""; Codec = ""; FramesExtracted = 0 }

    if (Get-Command ffprobe -ErrorAction SilentlyContinue) {
        try {
            $duration = & ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$VideoPath" 2>$null
            if ($duration) { $result.Duration = [math]::Round([double]$duration, 1).ToString() + "s" }
            $resolution = & ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$VideoPath" 2>$null
            if ($resolution) { $result.Resolution = $resolution.Replace(",", "x") }
            $codec = & ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$VideoPath" 2>$null
            if ($codec) { $result.Codec = $codec }
        } catch { }
    }

    if (-not $sampleOnlyMetadata -and $sampleFrames -gt 0 -and (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        try {
            $tmpdir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $tmpdir -Force | Out-Null
            & ffmpeg -i "$VideoPath" -vf "fps=1/$sampleFrames" -frames:v $sampleFrames -s "320x240" "$tmpdir/frame_%03d.jpg" 2>$null
            $frames = (Get-ChildItem "$tmpdir/*.jpg" -ErrorAction SilentlyContinue).Count
            $result.FramesExtracted = $frames
            Remove-Item $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
        } catch { }
    }
    return $result
}

# ============================================================
#  CONTEXT MENU REGISTRATION
# ============================================================

function Register-ContextMenu {
    $needsAdmin = $true
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $needsAdmin = $true
        } else {
            $needsAdmin = $false
        }
    } catch { $needsAdmin = $true }

    if ($needsAdmin) {
        # Relaunch as admin
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $script:INSTALL_PATH
            $psi.Arguments = "--register-context-menu"
            $psi.Verb = "runas"
            $psi.UseShellExecute = $true
            $psi.WindowStyle = "Hidden"
            [System.Diagnostics.Process]::Start($psi) | Out-Null
            return $true
        } catch {
            return $false
        }
    }

    # We are admin — do the registration
    $escapedExe = $script:INSTALL_PATH.Replace('"', '""')
    $command = "`"$escapedExe`" `"%V`""

    try {
        # Right-click ON a folder
        $base = "HKLM:\SOFTWARE\Classes\Directory\shell\FolderSummary"
        $cmd  = "$base\command"
        New-Item -Path $base -Force | Out-Null
        New-Item -Path $cmd  -Force | Out-Null
        Set-ItemProperty -Path $base -Name "(Default)" -Value "Summarize with AI"
        Set-ItemProperty -Path $base -Name "Icon" -Value "shell32.dll,21"
        Set-ItemProperty -Path $cmd  -Name "(Default)" -Value $command

        # Right-click INSIDE a folder (background)
        $bgBase = "HKLM:\SOFTWARE\Classes\Directory\Background\shell\FolderSummary"
        $bgCmd  = "$bgBase\command"
        New-Item -Path $bgBase -Force | Out-Null
        New-Item -Path $bgCmd  -Force | Out-Null
        Set-ItemProperty -Path $bgBase -Name "(Default)" -Value "Summarize with AI"
        Set-ItemProperty -Path $bgBase -Name "Icon" -Value "shell32.dll,21"
        Set-ItemProperty -Path $bgCmd  -Name "(Default)" -Value $command

        return $true
    } catch {
        return $false
    }
}

function Unregister-ContextMenu {
    try {
        Remove-Item -Path "HKLM:\SOFTWARE\Classes\Directory\shell\FolderSummary" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "HKLM:\SOFTWARE\Classes\Directory\Background\shell\FolderSummary" -Recurse -Force -ErrorAction SilentlyContinue
    } catch { }
}

# ============================================================
#  UNINSTALL
# ============================================================

function Invoke-Uninstall {
    Unregister-ContextMenu

    if (Test-Path -LiteralPath $script:INSTALL_PATH) {
        Remove-Item -LiteralPath $script:INSTALL_PATH -Force -ErrorAction SilentlyContinue
    }

    $result = [System.Windows.Forms.MessageBox]::Show(
        "Folder Summarizer has been uninstalled.`n`nContext menu entries removed.`nFile deleted from $script:INSTALL_PATH`n`nConfig folder at:`n$script:CONFIG_DIR`nwas NOT deleted (your settings are preserved).`n`nDelete it manually if you want.",
        "Uninstalled",
        "OK",
        "Information"
    )
}

# ============================================================
#  ONBOARDING WIZARD
# ============================================================

function Show-Onboarding {
    # ---- Theme colors ----
    $bgDark   = [System.Drawing.Color]::FromArgb(24, 24, 28)
    $bgPanel  = [System.Drawing.Color]::FromArgb(32, 32, 38)
    $bgInput  = [System.Drawing.Color]::FromArgb(42, 42, 50)
    $fgText   = [System.Drawing.Color]::FromArgb(215, 215, 220)
    $fgDim    = [System.Drawing.Color]::FromArgb(140, 140, 150)
    $fgLink   = [System.Drawing.Color]::FromArgb(90, 150, 255)
    $fgWarn   = [System.Drawing.Color]::FromArgb(255, 200, 80)
    $bgBtn    = [System.Drawing.Color]::FromArgb(55, 55, 65)
    $bgBtnHov = [System.Drawing.Color]::FromArgb(70, 70, 82)
    $bgBtnAcc = [System.Drawing.Color]::FromArgb(50, 110, 200)
    $fgBtnAcc = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $fontMain = New-Object System.Drawing.Font("Segoe UI", 9)
    $fontBold = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $fontTitle = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $fontMono = New-Object System.Drawing.Font("Consolas", 9)

    # ---- Main form ----
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Folder Summarizer — Setup"
    $form.Size = New-Object System.Drawing.Size(520, 620)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = $bgDark
    $form.TopMost = $true

    $y = 20

    # ---- Title ----
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Location = New-Object System.Drawing.Point(24, $y)
    $lblTitle.Size = New-Object System.Drawing.Size(470, 30)
    $lblTitle.Font = $fontTitle
    $lblTitle.ForeColor = $fgText
    $lblTitle.Text = "Folder Summarizer"
    $form.Controls.Add($lblTitle)
    $y += 38

    # ---- What it does ----
    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Location = New-Object System.Drawing.Point(24, $y)
    $lblDesc.Size = New-Object System.Drawing.Size(470, 52)
    $lblDesc.Font = $fontMain
    $lblDesc.ForeColor = $fgDim
    $lblDesc.Text = "Right-click any folder in Windows Explorer to get an AI-powered summary of its contents. Only file names and folder structure are sent to the API — never file contents."
    $form.Controls.Add($lblDesc)
    $y += 62

    # ---- Separator ----
    $sep1 = New-Object System.Windows.Forms.Panel
    $sep1.Location = New-Object System.Drawing.Point(24, $y)
    $sep1.Size = New-Object System.Drawing.Size(470, 1)
    $sep1.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 70)
    $form.Controls.Add($sep1)
    $y += 12

    # ---- API Key section ----
    $lblApiKeyTitle = New-Object System.Windows.Forms.Label
    $lblApiKeyTitle.Location = New-Object System.Drawing.Point(24, $y)
    $lblApiKeyTitle.Size = New-Object System.Drawing.Size(470, 22)
    $lblApiKeyTitle.Font = $fontBold
    $lblApiKeyTitle.ForeColor = $fgText
    $lblApiKeyTitle.Text = "1. Google Gemini API Key (required)"
    $form.Controls.Add($lblApiKeyTitle)
    $y += 26

    $lblApiKeyDesc = New-Object System.Windows.Forms.Label
    $lblApiKeyDesc.Location = New-Object System.Drawing.Point(24, $y)
    $lblApiKeyDesc.Size = New-Object System.Drawing.Size(470, 36)
    $lblApiKeyDesc.Font = $fontMain
    $lblApiKeyDesc.ForeColor = $fgDim
    $lblApiKeyDesc.Text = "You need a free API key from Google AI Studio. Click the link below, copy your key, and paste it here."
    $form.Controls.Add($lblApiKeyDesc)
    $y += 40

    # Link label to AI Studio
    $linkAIStudio = New-Object System.Windows.Forms.LinkLabel
    $linkAIStudio.Location = New-Object System.Drawing.Point(24, $y)
    $linkAIStudio.Size = New-Object System.Drawing.Size(400, 20)
    $linkAIStudio.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Underline)
    $linkAIStudio.LinkColor = $fgLink
    $linkAIStudio.Text = "https://aistudio.google.com/api-keys"
    $linkAIStudio.Add_LinkClicked({
        Start-Process "https://aistudio.google.com/api-keys"
    })
    $form.Controls.Add($linkAIStudio)
    $y += 24

    # Note about AI Studio bug
    $lblAIStudioNote = New-Object System.Windows.Forms.Label
    $lblAIStudioNote.Location = New-Object System.Drawing.Point(24, $y)
    $lblAIStudioNote.Size = New-Object System.Drawing.Size(470, 30)
    $lblAIStudioNote.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblAIStudioNote.ForeColor = $fgWarn
    $lblAIStudioNote.Text = "If the page redirects to an "Available Regions" error, try a different Google account — AI Studio can be buggy with region availability."
    $form.Controls.Add($lblAIStudioNote)
    $y += 36

    # API key input
    $txtApiKey = New-Object System.Windows.Forms.TextBox
    $txtApiKey.Location = New-Object System.Drawing.Point(24, $y)
    $txtApiKey.Size = New-Object System.Drawing.Size(410, 28)
    $txtApiKey.Font = $fontMono
    $txtApiKey.BackColor = $bgInput
    $txtApiKey.ForeColor = $fgText
    $txtApiKey.BorderStyle = "FixedSingle"
    $txtApiKey.UseSystemPasswordChar = $true
    $txtApiKey.PlaceholderText = "Paste your API key here..."
    $form.Controls.Add($txtApiKey)

    $btnShowKey = New-Object System.Windows.Forms.Button
    $btnShowKey.Location = New-Object System.Drawing.Point(440, $y)
    $btnShowKey.Size = New-Object System.Drawing.Size(54, 28)
    $btnShowKey.Text = "Show"
    $btnShowKey.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $btnShowKey.BackColor = $bgBtn
    $btnShowKey.ForeColor = $fgDim
    $btnShowKey.FlatStyle = "Flat"
    $btnShowKey.Add_Click({
        if ($btnShowKey.Text -eq "Show") {
            $txtApiKey.UseSystemPasswordChar = $false
            $btnShowKey.Text = "Hide"
        } else {
            $txtApiKey.UseSystemPasswordChar = $true
            $btnShowKey.Text = "Show"
        }
    })
    $form.Controls.Add($btnShowKey)
    $y += 42

    # ---- Separator ----
    $sep2 = New-Object System.Windows.Forms.Panel
    $sep2.Location = New-Object System.Drawing.Point(24, $y)
    $sep2.Size = New-Object System.Drawing.Size(470, 1)
    $sep2.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 70)
    $form.Controls.Add($sep2)
    $y += 12

    # ---- Windows 11 note ----
    $lblWin11Title = New-Object System.Windows.Forms.Label
    $lblWin11Title.Location = New-Object System.Drawing.Point(24, $y)
    $lblWin11Title.Size = New-Object System.Drawing.Size(470, 22)
    $lblWin11Title.Font = $fontBold
    $lblWin11Title.ForeColor = $fgText
    $lblWin11Title.Text = "2. Windows 11 Context Menu"
    $form.Controls.Add($lblWin11Title)
    $y += 26

    $lblWin11Note = New-Object System.Windows.Forms.Label
    $lblWin11Note.Location = New-Object System.Drawing.Point(24, $y)
    $lblWin11Note.Size = New-Object System.Drawing.Size(470, 50)
    $lblWin11Note.Font = $fontMain
    $lblWin11Note.ForeColor = $fgDim
    $lblWin11Note.Text = "On Windows 11, the ""Summarize with AI"" option appears in the classic context menu. To see it, either click ""Show more options"" (Shift+F10) in the new menu, or restore the classic right-click menu with tools like W11ContextBack or registry tweaks."
    $form.Controls.Add($lblWin11Note)
    $y += 58

    # ---- Separator ----
    $sep3 = New-Object System.Windows.Forms.Panel
    $sep3.Location = New-Object System.Drawing.Point(24, $y)
    $sep3.Size = New-Object System.Drawing.Size(470, 1)
    $sep3.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 70)
    $form.Controls.Add($sep3)
    $y += 12

    # ---- FFmpeg section ----
    $lblFfmpegTitle = New-Object System.Windows.Forms.Label
    $lblFfmpegTitle.Location = New-Object System.Drawing.Point(24, $y)
    $lblFfmpegTitle.Size = New-Object System.Drawing.Size(470, 22)
    $lblFfmpegTitle.Font = $fontBold
    $lblFfmpegTitle.ForeColor = $fgText
    $lblFfmpegTitle.Text = "3. FFmpeg (optional)"
    $form.Controls.Add($lblFfmpegTitle)
    $y += 26

    $lblFfmpegDesc = New-Object System.Windows.Forms.Label
    $lblFfmpegDesc.Location = New-Object System.Drawing.Point(24, $y)
    $lblFfmpegDesc.Size = New-Object System.Drawing.Size(400, 36)
    $lblFfmpegDesc.Font = $fontMain
    $lblFfmpegDesc.ForeColor = $fgDim
    $lblFfmpegDesc.Text = "FFmpeg lets the tool read video metadata (duration, resolution, codec). Without it, video files are still counted but no details are shown."
    $form.Controls.Add($lblFfmpegDesc)

    $chkFfmpeg = New-Object System.Windows.Forms.CheckBox
    $chkFfmpeg.Location = New-Object System.Drawing.Point(428, $y - 2)
    $chkFfmpeg.Size = New-Object System.Drawing.Size(80, 24)
    $chkFfmpeg.Text = "Install"
    $chkFfmpeg.ForeColor = $fgText
    $chkFfmpeg.BackColor = $bgDark
    $chkFfmpeg.FlatStyle = "Flat"
    $chkFfmpeg.Font = $fontMain
    $form.Controls.Add($chkFfmpeg)
    $y += 46

    # ---- Separator ----
    $sep4 = New-Object System.Windows.Forms.Panel
    $sep4.Location = New-Object System.Drawing.Point(24, $y)
    $sep4.Size = New-Object System.Drawing.Size(470, 1)
    $sep4.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 70)
    $form.Controls.Add($sep4)
    $y += 16

    # ---- Status label (shows progress/errors) ----
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Location = New-Object System.Drawing.Point(24, $y)
    $lblStatus.Size = New-Object System.Drawing.Size(470, 20)
    $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblStatus.ForeColor = $fgDim
    $lblStatus.Text = ""
    $form.Controls.Add($lblStatus)
    $y += 28

    # ---- Buttons ----
    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Location = New-Object System.Drawing.Point(310, $y)
    $btnInstall.Size = New-Object System.Drawing.Size(184, 38)
    $btnInstall.Text = "Install"
    $btnInstall.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnInstall.BackColor = $bgBtnAcc
    $btnInstall.ForeColor = $fgBtnAcc
    $btnInstall.FlatStyle = "Flat"
    $btnInstall.Cursor = "Hand"
    $form.Controls.Add($btnInstall)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Location = New-Object System.Drawing.Point(220, $y)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 38)
    $btnCancel.Text = "Cancel"
    $btnCancel.Font = $fontMain
    $btnCancel.BackColor = $bgBtn
    $btnCancel.ForeColor = $fgDim
    $btnCancel.FlatStyle = "Flat"
    $form.AcceptButton = $btnInstall
    $form.CancelButton = $btnCancel
    $form.Controls.Add($btnCancel)

    # ---- Install logic ----
    $btnInstall.Add_Click({
        $apiKey = $txtApiKey.Text.Trim()
        $installFfmpeg = $chkFfmpeg.Checked

        # Validate API key
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 100)
            $lblStatus.Text = "Please enter your API key."
            $txtApiKey.Focus()
            return
        }

        if ($apiKey.Length -lt 10) {
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 100)
            $lblStatus.Text = "That doesn't look like a valid API key."
            $txtApiKey.Focus()
            return
        }

        $btnInstall.Enabled = $false
        $btnCancel.Enabled = $false
        $txtApiKey.Enabled = $false
        $chkFfmpeg.Enabled = $false

        # Step 1: Save config
        $lblStatus.ForeColor = $fgDim
        $lblStatus.Text = "Saving configuration..."
        $form.Refresh()

        try {
            $config = Get-DefaultConfig
            $config["api_key"] = $apiKey
            Save-Config -Config $config
        } catch {
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 100)
            $lblStatus.Text = "Failed to save config: $($_.Exception.Message)"
            $btnInstall.Enabled = $true
            $btnCancel.Enabled = $true
            $txtApiKey.Enabled = $true
            $chkFfmpeg.Enabled = $true
            return
        }

        # Step 2: Install ffmpeg (optional)
        if ($installFfmpeg) {
            $lblStatus.Text = "Installing ffmpeg..."
            $form.Refresh()

            try {
                if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                    $lblStatus.ForeColor = $fgWarn
                    $lblStatus.Text = "winget not found. Install ffmpeg manually from ffmpeg.org"
                }
                else {
                    $proc = Start-Process -FilePath "winget" -ArgumentList "install", "Gyan.FFmpeg", "--accept-source-agreements", "--accept-package-agreements" -Wait -PassThru -NoNewWindow -ErrorAction Stop
                    if ($proc.ExitCode -ne 0) {
                        $lblStatus.ForeColor = $fgWarn
                        $lblStatus.Text = "winget ffmpeg install may have failed. Check manually."
                    }
                }
            } catch {
                $lblStatus.ForeColor = $fgWarn
                $lblStatus.Text = "Could not install ffmpeg automatically. Install it manually from ffmpeg.org"
            }
        }

        # Step 3: Copy exe to C:\Scripts\
        $lblStatus.ForeColor = $fgDim
        $lblStatus.Text = "Installing to $script:INSTALL_DIR..."
        $form.Refresh()

        try {
            if (-not (Test-Path -LiteralPath $script:INSTALL_DIR)) {
                New-Item -ItemType Directory -Path $script:INSTALL_DIR -Force | Out-Null
            }
            Copy-Item -LiteralPath $script:MyPath -Destination $script:INSTALL_PATH -Force
        } catch {
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 100)
            $lblStatus.Text = "Failed to copy to $script:INSTALL_DIR : $($_.Exception.Message)"
            $btnInstall.Enabled = $true
            $btnCancel.Enabled = $true
            return
        }

        # Step 4: Register context menu (needs admin — will UAC prompt)
        $lblStatus.Text = "Registering context menu (you may see a UAC prompt)..."
        $form.Refresh()

        $registered = $false
        try {
            # Try direct registration first (in case we're already admin)
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                $escapedExe = $script:INSTALL_PATH.Replace('"', '""')
                $command = "`"$escapedExe`" `"%V`""

                $base = "HKLM:\SOFTWARE\Classes\Directory\shell\FolderSummary"
                $cmd  = "$base\command"
                New-Item -Path $base -Force | Out-Null
                New-Item -Path $cmd  -Force | Out-Null
                Set-ItemProperty -Path $base -Name "(Default)" -Value "Summarize with AI"
                Set-ItemProperty -Path $base -Name "Icon" -Value "shell32.dll,21"
                Set-ItemProperty -Path $cmd  -Name "(Default)" -Value $command

                $bgBase = "HKLM:\SOFTWARE\Classes\Directory\Background\shell\FolderSummary"
                $bgCmd  = "$bgBase\command"
                New-Item -Path $bgBase -Force | Out-Null
                New-Item -Path $bgCmd  -Force | Out-Null
                Set-ItemProperty -Path $bgBase -Name "(Default)" -Value "Summarize with AI"
                Set-ItemProperty -Path $bgBase -Name "Icon" -Value "shell32.dll,21"
                Set-ItemProperty -Path $bgCmd  -Name "(Default)" -Value $command
                $registered = $true
            }
            else {
                # Relaunch self as admin to register
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $script:INSTALL_PATH
                $psi.Arguments = "--register-context-menu"
                $psi.Verb = "runas"
                $psi.UseShellExecute = $true
                $psi.WindowStyle = "Hidden"
                $adminProc = [System.Diagnostics.Process]::Start($psi)
                if ($null -ne $adminProc) {
                    $adminProc.WaitForExit(30000)
                    if ($adminProc.ExitCode -eq 0) { $registered = $true }
                }
            }
        } catch {
            # Silently fail — user can register later
        }

        # Done
        if ($registered) {
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 220, 120)
            $lblStatus.Text = "Done! Right-click any folder > ""Summarize with AI"" (Win11: Shift+F10 or 'Show more options')"
        }
        else {
            $lblStatus.ForeColor = $fgWarn
            $lblStatus.Text = "Installed but context menu not registered. Re-run as Administrator to register."
        }

        $btnInstall.Text = "Done"
        $btnInstall.Add_Click({ $form.Close() })
    })

    $btnCancel.Add_Click({ $form.Close() })

    # If already have a config with an API key, pre-fill it
    if (Test-Path -LiteralPath $script:CONFIG_FILE) {
        $existingConfig = Load-Config
        $existingKey = Get-ConfigValue $existingConfig "api_key" ""
        if (-not [string]::IsNullOrWhiteSpace($existingKey) -and $existingKey -ne "YOUR_KEY_HERE") {
            $txtApiKey.Text = $existingKey
        }
        # Pre-check ffmpeg if it's already installed
        if (Get-Command ffprobe -ErrorAction SilentlyContinue) {
            $chkFfmpeg.Checked = $false
            $chkFfmpeg.Text = "Installed"
            $chkFfmpeg.Enabled = $false
        }
    }

    [void]$form.ShowDialog()
}

# ============================================================
#  SETTINGS FORM
# ============================================================

function Show-Settings {
    $config = Load-Config

    $bgDark   = [System.Drawing.Color]::FromArgb(24, 24, 28)
    $bgInput  = [System.Drawing.Color]::FromArgb(42, 42, 50)
    $fgText   = [System.Drawing.Color]::FromArgb(215, 215, 220)
    $fgDim    = [System.Drawing.Color]::FromArgb(140, 140, 150)
    $fgLink   = [System.Drawing.Color]::FromArgb(90, 150, 255)
    $bgBtn    = [System.Drawing.Color]::FromArgb(55, 55, 65)
    $bgBtnAcc = [System.Drawing.Color]::FromArgb(50, 110, 200)
    $fgBtnAcc = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $fontMain = New-Object System.Drawing.Font("Segoe UI", 9)
    $fontBold = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $fontTitle = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $fontMono = New-Object System.Drawing.Font("Consolas", 9)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Folder Summarizer — Settings"
    $form.Size = New-Object System.Drawing.Size(480, 400)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = $bgDark
    $form.TopMost = $true

    $y = 20

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Location = New-Object System.Drawing.Point(24, $y)
    $lblTitle.Size = New-Object System.Drawing.Size(430, 28)
    $lblTitle.Font = $fontTitle
    $lblTitle.ForeColor = $fgText
    $lblTitle.Text = "Settings"
    $form.Controls.Add($lblTitle)
    $y += 40

    # API Key
    $lblApiKey = New-Object System.Windows.Forms.Label
    $lblApiKey.Location = New-Object System.Drawing.Point(24, $y)
    $lblApiKey.Size = New-Object System.Drawing.Size(430, 20)
    $lblApiKey.Font = $fontBold
    $lblApiKey.ForeColor = $fgText
    $lblApiKey.Text = "API Key"
    $form.Controls.Add($lblApiKey)
    $y += 26

    $txtApiKey = New-Object System.Windows.Forms.TextBox
    $txtApiKey.Location = New-Object System.Drawing.Point(24, $y)
    $txtApiKey.Size = New-Object System.Drawing.Size(340, 28)
    $txtApiKey.Font = $fontMono
    $txtApiKey.BackColor = $bgInput
    $txtApiKey.ForeColor = $fgText
    $txtApiKey.BorderStyle = "FixedSingle"
    $txtApiKey.UseSystemPasswordChar = $true
    $txtApiKey.Text = (Get-ConfigValue $config "api_key" "")
    $form.Controls.Add($txtApiKey)

    $btnShowKey = New-Object System.Windows.Forms.Button
    $btnShowKey.Location = New-Object System.Drawing.Point(372, $y)
    $btnShowKey.Size = New-Object System.Drawing.Size(80, 28)
    $btnShowKey.Text = "Show"
    $btnShowKey.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $btnShowKey.BackColor = $bgBtn
    $btnShowKey.ForeColor = $fgDim
    $btnShowKey.FlatStyle = "Flat"
    $btnShowKey.Add_Click({
        if ($btnShowKey.Text -eq "Show") {
            $txtApiKey.UseSystemPasswordChar = $false
            $btnShowKey.Text = "Hide"
        } else {
            $txtApiKey.UseSystemPasswordChar = $true
            $btnShowKey.Text = "Show"
        }
    })
    $form.Controls.Add($btnShowKey)
    $y += 42

    # Config file path
    $lblConfigPath = New-Object System.Windows.Forms.Label
    $lblConfigPath.Location = New-Object System.Drawing.Point(24, $y)
    $lblConfigPath.Size = New-Object System.Drawing.Size(430, 20)
    $lblConfigPath.Font = $fontMain
    $lblConfigPath.ForeColor = $fgDim
    $lblConfigPath.Text = "Config file: $script:CONFIG_FILE"
    $form.Controls.Add($lblConfigPath)
    $y += 26

    # Model
    $lblModel = New-Object System.Windows.Forms.Label
    $lblModel.Location = New-Object System.Drawing.Point(24, $y)
    $lblModel.Size = New-Object System.Drawing.Size(430, 20)
    $lblModel.Font = $fontBold
    $lblModel.ForeColor = $fgText
    $lblModel.Text = "Model"
    $form.Controls.Add($lblModel)
    $y += 26

    $txtModel = New-Object System.Windows.Forms.TextBox
    $txtModel.Location = New-Object System.Drawing.Point(24, $y)
    $txtModel.Size = New-Object System.Drawing.Size(428, 28)
    $txtModel.Font = $fontMono
    $txtModel.BackColor = $bgInput
    $txtModel.ForeColor = $fgText
    $txtModel.BorderStyle = "FixedSingle"
    $txtModel.Text = (Get-ConfigValue $config "model" "gemini-2.5-flash")
    $form.Controls.Add($txtModel)
    $y += 42

    # Info
    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Location = New-Object System.Drawing.Point(24, $y)
    $lblInfo.Size = New-Object System.Drawing.Size(430, 40)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblInfo.ForeColor = $fgDim
    $ffprobeStatus = if (Get-Command ffprobe -ErrorAction SilentlyContinue) { "Installed" } else { "Not found" }
    $lblInfo.Text = "FFmpeg/ffprobe: $ffprobeStatus  |  Installed to: $script:INSTALL_PATH"
    $form.Controls.Add($lblInfo)
    $y += 50

    # Status
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Location = New-Object System.Drawing.Point(24, $y)
    $lblStatus.Size = New-Object System.Drawing.Size(430, 20)
    $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblStatus.ForeColor = $fgDim
    $lblStatus.Text = ""
    $form.Controls.Add($lblStatus)
    $y += 28

    # Buttons
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Location = New-Object System.Drawing.Point(300, $y)
    $btnSave.Size = New-Object System.Drawing.Size(152, 36)
    $btnSave.Text = "Save"
    $btnSave.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnSave.BackColor = $bgBtnAcc
    $btnSave.ForeColor = $fgBtnAcc
    $btnSave.FlatStyle = "Flat"
    $form.Controls.Add($btnSave)

    $btnUninstall = New-Object System.Windows.Forms.Button
    $btnUninstall.Location = New-Object System.Drawing.Point(24, $y)
    $btnUninstall.Size = New-Object System.Drawing.Size(100, 36)
    $btnUninstall.Text = "Uninstall"
    $btnUninstall.Font = $fontMain
    $btnUninstall.BackColor = $bgBtn
    $btnUninstall.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 100)
    $btnUninstall.FlatStyle = "Flat"
    $form.Controls.Add($btnUninstall)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Location = New-Object System.Drawing.Point(136, $y)
    $btnClose.Size = New-Object System.Drawing.Size(80, 36)
    $btnClose.Text = "Close"
    $btnClose.Font = $fontMain
    $btnClose.BackColor = $bgBtn
    $btnClose.ForeColor = $fgDim
    $btnClose.FlatStyle = "Flat"
    $form.Controls.Add($btnClose)

    $btnSave.Add_Click({
        $config["api_key"] = $txtApiKey.Text.Trim()
        $config["model"] = $txtModel.Text.Trim()
        Save-Config -Config $config
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 220, 120)
        $lblStatus.Text = "Saved."
    })

    $btnUninstall.Add_Click({
        $form.Close()
        Invoke-Uninstall
    })

    $btnClose.Add_Click({ $form.Close() })

    [void]$form.ShowDialog()
}

# ============================================================
#  MAIN SUMMARIZATION LOGIC
# ============================================================

function Invoke-Summarize {
    param([string]$TargetFolder)

    # Normalize and verify the folder path
    try {
        $TargetFolder = [System.IO.Path]::GetFullPath($TargetFolder)
    } catch {
        Show-ErrorPopup "Invalid folder path: $TargetFolder"
        return
    }

    if (-not (Test-Path -LiteralPath $TargetFolder -PathType Container)) {
        Show-ErrorPopup "Folder does not exist: $TargetFolder"
        return
    }

    # Load config
    $config = Load-Config
    $API_KEY        = Get-ConfigValue $config "api_key" ""
    $MODEL          = Get-ConfigValue $config "model" "gemini-2.5-flash"
    $API_URL        = "https://generativelanguage.googleapis.com/v1beta/models/$MODEL`:generateContent"
    $securityAction = Get-ConfigValue $config "security.action" "mask"

    Init-SensitivePatterns -Config $config

    # Check API key
    if ([string]::IsNullOrWhiteSpace($API_KEY)) {
        Show-ErrorPopup "No API key configured. Run the exe without arguments to open setup."
        return
    }

    $language = Get-WindowsLanguage -Config $config

    # First-run privacy warning
    $warningAccepted = Get-ConfigValue $config "ui.warning_accepted" $false
    if (-not $warningAccepted) {
        $warnForm                 = New-Object System.Windows.Forms.Form
        $warnForm.Text            = "Folder Summarizer — Privacy Notice"
        $warnForm.Size            = New-Object System.Drawing.Size(440, 340)
        $warnForm.StartPosition   = "CenterScreen"
        $warnForm.FormBorderStyle = "FixedDialog"
        $warnForm.MaximizeBox     = $false
        $warnForm.MinimizeBox     = $false
        $warnForm.BackColor       = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $warnForm.TopMost         = $true

        $warnLabel               = New-Object System.Windows.Forms.Label
        $warnLabel.Location      = New-Object System.Drawing.Point(16, 16)
        $warnLabel.Size          = New-Object System.Drawing.Size(408, 210)
        $warnLabel.ForeColor     = [System.Drawing.Color]::FromArgb(220, 220, 220)
        $warnLabel.Font          = New-Object System.Drawing.Font("Segoe UI", 9)
        $warnLabel.Text          = @"
This tool sends folder/file names and directory structure
to Google Gemini API to generate a summary.

File contents are NOT uploaded. Filenames and folder names
matching your security patterns are redacted.

However, folder names like "tax-returns" or "passwords" can
still reveal information even when contents are not sent.

Review scanned folders before sharing results.
"@

        $dontShowCb             = New-Object System.Windows.Forms.CheckBox
        $dontShowCb.Location     = New-Object System.Drawing.Point(16, 238)
        $dontShowCb.Size        = New-Object System.Drawing.Size(300, 24)
        $dontShowCb.ForeColor   = [System.Drawing.Color]::FromArgb(180, 180, 180)
        $dontShowCb.Font        = New-Object System.Drawing.Font("Segoe UI", 9)
        $dontShowCb.Text        = "Don't show this again"
        $dontShowCb.BackColor   = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $dontShowCb.FlatStyle   = "Flat"

        $btnYes                 = New-Object System.Windows.Forms.Button
        $btnYes.DialogResult    = [System.Windows.Forms.DialogResult]::Yes
        $btnYes.Location        = New-Object System.Drawing.Point(160, 270)
        $btnYes.Size            = New-Object System.Drawing.Size(120, 34)
        $btnYes.Text            = "Continue"
        $btnYes.BackColor       = [System.Drawing.Color]::FromArgb(45, 45, 45)
        $btnYes.ForeColor       = [System.Drawing.Color]::FromArgb(220, 220, 220)
        $btnYes.FlatStyle       = "Flat"
        $btnYes.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

        $btnNo                  = New-Object System.Windows.Forms.Button
        $btnNo.DialogResult     = [System.Windows.Forms.DialogResult]::No
        $btnNo.Location         = New-Object System.Drawing.Point(288, 270)
        $btnNo.Size             = New-Object System.Drawing.Size(120, 34)
        $btnNo.Text             = "Cancel"
        $btnNo.BackColor        = [System.Drawing.Color]::FromArgb(45, 45, 45)
        $btnNo.ForeColor        = [System.Drawing.Color]::FromArgb(220, 220, 220)
        $btnNo.FlatStyle        = "Flat"
        $btnNo.Font             = New-Object System.Drawing.Font("Segoe UI", 9)

        $warnForm.Controls.Add($warnLabel)
        $warnForm.Controls.Add($dontShowCb)
        $warnForm.Controls.Add($btnYes)
        $warnForm.Controls.Add($btnNo)
        $warnForm.AcceptButton  = $btnYes
        $warnForm.CancelButton  = $btnNo

        $result = $warnForm.ShowDialog()
        if ($result -eq "No" -or $result -eq "Cancel") { return }

        if ($dontShowCb.Checked) {
            try {
                $configDir = Split-Path -Parent $script:CONFIG_FILE
                if (-not (Test-Path -LiteralPath $configDir)) {
                    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
                }
                Add-Content -LiteralPath $script:CONFIG_FILE -Encoding UTF8 -Value "`nui:`n  warning_accepted: true"
            } catch { }
        }
    }

    # Scan folder
    $allFiles = Get-ChildItem -Path $TargetFolder -Recurse -File -ErrorAction SilentlyContinue
    $topItems = Get-ChildItem -Path $TargetFolder -ErrorAction SilentlyContinue

    $redactedPath = Get-RedactedPath -Path $TargetFolder
    $dirCount = (Get-ChildItem -Path $TargetFolder -Recurse -Directory -ErrorAction SilentlyContinue).Count
    $rawSize  = ($allFiles | Measure-Object Length -Sum).Sum
    $totalSize = if ($rawSize) { [math]::Round($rawSize / 1MB, 2) } else { 0 }

    $groups     = Get-CategoryFileGroups -AllFiles $allFiles -Config $config
    $catLines   = $groups.CategoryLines
    $promptCats = $groups.PromptCategories

    # Top-level contents
    $topStr = ($topItems | ForEach-Object {
        $item = $_
        $isSensitiveName    = Test-SensitiveName $item.Name
        $isSensitiveContent = if (-not $item.PSIsContainer) { Test-SensitiveContent $item.FullName } else { $false }

        if ($isSensitiveName -or $isSensitiveContent) {
            if ($securityAction -eq 'skip') { return }
            if ($item.PSIsContainer) { "  [DIR]  [REDACTED]" } else { "  [FILE] [REDACTED]" }
        }
        elseif ($item.PSIsContainer) {
            if (Test-SensitiveName $item.Name) {
                if ($securityAction -eq 'skip') { return }
                "  [DIR]  [REDACTED]"
            } else { "  [DIR]  $($item.Name)" }
        }
        else { "  [FILE] $($item.Name)" }
    }) -join "`n"

    # Video metadata
    $videoFiles = @($allFiles | Where-Object { @(".mp4",".avi",".mkv",".mov",".wmv",".flv",".webm",".m4v",".mpg",".mpeg") -contains $_.Extension.ToLower() })
    $videoSummary = ""
    if ($videoFiles.Count -gt 0) {
        $meta = Get-VideoMetadata -VideoPath $videoFiles[0].FullName -Config $config
        $metaParts = @()
        if ($meta.Duration)               { $metaParts += "Duration: $($meta.Duration)" }
        if ($meta.Resolution)             { $metaParts += "Resolution: $($meta.Resolution)" }
        if ($meta.Codec)                  { $metaParts += "Codec: $($meta.Codec)" }
        if ($meta.FramesExtracted -gt 0)  { $metaParts += "Frames sampled: $($meta.FramesExtracted)" }
        if ($metaParts.Count -gt 0) {
            $videoSummary = "`nVIDEO METADATA ($($videoFiles.Count) video files):`n  $($metaParts -join ' | ')"
        }
    }

    # Build API prompt
    $prompt = @"
You are analyzing a folder on a Windows PC. Based only on the file and folder names below, write a 3-5 sentence summary that answers: what is this folder likely used for, what types of content dominate, and are there any notable patterns?

Use very simple, plain, everyday language. Short sentences. No fancy words. Imagine you're explaining this to a non-technical friend in one breath.

Output language: $language

FOLDER: $redactedPath
TOTAL FILES: $($allFiles.Count) | SUBDIRS: $dirCount | SIZE: $totalSize MB

TOP-LEVEL CONTENTS:
$topStr

SAMPLED FILES BY CATEGORY (first 5 per type):
$($promptCats -join "`n")
$videoSummary

Keep it concise, informative, and plain. No bullet points or markdown headers.
"@

    # Call API
    $bodyJson = @{
        contents = @(@{ parts = @(@{ text = $prompt }) })
        generationConfig = @{ maxOutputTokens = 8192 }
    } | ConvertTo-Json -Depth 8

    try {
        $resp = Invoke-RestMethod `
            -Uri $API_URL `
            -Method POST `
            -Headers @{
                "x-goog-api-key" = $API_KEY
                "Content-Type"   = "application/json"
            } `
            -Body $bodyJson `
            -ErrorAction Stop

        if (-not $resp.candidates -or -not $resp.candidates[0].content.parts[0].text) {
            throw "Gemini returned an empty response."
        }
        $aiSummary = $resp.candidates[0].content.parts[0].text.Trim()
    } catch {
        $aiSummary = "API error: $($_.Exception.Message)"
    }

    # Display result
    $folderName = Split-Path -Leaf $TargetFolder.TrimEnd('\')
    $div = "=" * 62

    $output = @"

  $div
    FOLDER SUMMARY  -  $folderName
  $div

  Path    : $TargetFolder
  Files   : $($allFiles.Count)   |   Folders: $dirCount   |   Size: $totalSize MB
  Model   : $MODEL
  Language: $language

  $("-" * 62)
  FILES CHECKED (first 5 per type):
  $("-" * 62)

$($catLines -join "`n")

  $("-" * 62)
  AI SUMMARY:
  $("-" * 62)

  $($aiSummary -replace "`n", "`n  ")

  $("-" * 62)
  Sensitive file/folder names were redacted before sending to API.
  Local output shows the real path. Review before sharing.
  $div

"@

    Show-SummaryPopup -Title "Folder Summary — $folderName" -Content $output
}

# ============================================================
#  UI HELPERS
# ============================================================

function Show-ErrorPopup {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, "Folder Summarizer", "OK", "Warning") | Out-Null
}

function Show-SummaryPopup {
    param([string]$Title, [string]$Content)

    $form                 = New-Object System.Windows.Forms.Form
    $form.Text            = $Title
    $form.Size            = New-Object System.Drawing.Size(760, 560)
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox     = $false
    $form.BackColor       = [System.Drawing.Color]::FromArgb(16, 16, 16)

    $tb             = New-Object System.Windows.Forms.RichTextBox
    $tb.Dock        = "Fill"
    $tb.ReadOnly    = $true
    $tb.BackColor   = [System.Drawing.Color]::FromArgb(16, 16, 16)
    $tb.ForeColor   = [System.Drawing.Color]::FromArgb(210, 210, 210)
    $tb.Font        = New-Object System.Drawing.Font("Consolas", 10)
    $tb.Text        = $Content
    $tb.ScrollBars  = "Vertical"
    $tb.BorderStyle = "None"

    $btn            = New-Object System.Windows.Forms.Button
    $btn.Text       = "Close"
    $btn.Dock       = "Bottom"
    $btn.Height     = 32
    $btn.BackColor  = [System.Drawing.Color]::FromArgb(35, 35, 35)
    $btn.ForeColor  = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $btn.FlatStyle  = "Flat"
    $btn.Add_Click({ $form.Close() })

    $form.Controls.Add($tb)
    $form.Controls.Add($btn)
    [void]$form.ShowDialog()
}

# ============================================================
#  ENTRY POINT
# ============================================================

# Handle --register-context-menu (called from UAC elevation)
if ($args.Count -gt 0 -and $args[0] -eq "--register-context-menu") {
    try {
        $escapedExe = $script:INSTALL_PATH.Replace('"', '""')
        $command = "`"$escapedExe`" `"%V`""

        $base = "HKLM:\SOFTWARE\Classes\Directory\shell\FolderSummary"
        $cmd  = "$base\command"
        New-Item -Path $base -Force | Out-Null
        New-Item -Path $cmd  -Force | Out-Null
        Set-ItemProperty -Path $base -Name "(Default)" -Value "Summarize with AI"
        Set-ItemProperty -Path $base -Name "Icon" -Value "shell32.dll,21"
        Set-ItemProperty -Path $cmd  -Name "(Default)" -Value $command

        $bgBase = "HKLM:\SOFTWARE\Classes\Directory\Background\shell\FolderSummary"
        $bgCmd  = "$bgBase\command"
        New-Item -Path $bgBase -Force | Out-Null
        New-Item -Path $bgCmd  -Force | Out-Null
        Set-ItemProperty -Path $bgBase -Name "(Default)" -Value "Summarize with AI"
        Set-ItemProperty -Path $bgBase -Name "Icon" -Value "shell32.dll,21"
        Set-ItemProperty -Path $bgCmd  -Name "(Default)" -Value $command

        exit 0
    } catch {
        exit 1
    }
}

# Route based on mode
if ($Uninstall) {
    Invoke-Uninstall
}
elsif (-not [string]::IsNullOrWhiteSpace($FolderPath)) {
    Invoke-Summarize -TargetFolder $FolderPath
}
elseif ($Settings -or $script:IsInstalled) {
    # Running from installed location with no args → show settings
    # But also check if we got a folder from the context menu via %V
    Show-Settings
}
else {
    # Portable / first run → onboarding
    Show-Onboarding
}
