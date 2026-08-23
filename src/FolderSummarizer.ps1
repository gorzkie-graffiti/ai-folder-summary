# ============================================================
#  FolderSummarizer.ps1
# ============================================================
param(
    [string]$FolderPath,
    [string]$ConfigPath
)
# Resolve folder path when no argument was provided.
if ([string]::IsNullOrWhiteSpace($FolderPath)) {
    $FolderPath = (Get-Location).Path
}

# Normalize and verify the folder path.
try {
    $FolderPath = [System.IO.Path]::GetFullPath($FolderPath)
}
catch {
    throw "Invalid folder path: $FolderPath"
}

if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
    throw "Folder does not exist: $FolderPath"
}

# -- LOAD WINDOWS FORMS EARLY (for the warning dialog) -------
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# ============================================================
#  YAML CONFIG PARSER
# ============================================================

function Parse-YAML {
    <#
    .SYNOPSIS
        Minimal YAML parser supporting: nested dicts, arrays, quoted strings, comments.
    #>
    param([string[]]$Lines)

    $root = [ordered]@{}
    $stack = [System.Collections.Stack]::new()
    $current = $root
    $currentIndent = 0

    foreach ($line in $Lines) {
        # Skip blank lines and comments
        if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }

        # Detect indentation
        $trimmed = $line.TrimEnd()
        $leadingSpaces = $trimmed.Length - $trimmed.TrimStart().Length

        # Pop stack when we go back to a shallower indent
        while ($stack.Count -gt 0 -and $leadingSpaces -lt $currentIndent) {
            $pop = $stack.Pop()
            $current = $pop.Context
            $currentIndent = $pop.Indent
        }

        # Clean line (strip inline comment)
        $cleanLine = $trimmed -replace '\s*#.*$', ''

        # --- Array item: "  - value" or "  - key: value" ---
        if ($cleanLine -match '^(\s*)- (.+)$') {
            $arrayIndent = $Matches[1].Length
            $content = $Matches[2].Trim()

            # - key: value  (array of dicts)
            if ($content -match '^([^:]+):\s*(.+)$') {
                $k = $Matches[1].Trim().Trim('"')
                $v = $Matches[2].Trim().Trim('"')

                # Start a new dict in the current array
                $newObj = [ordered]@{ $k = $v }
                $current.Add($newObj)
                $stack.Push(@{ Context = $current; Indent = $currentIndent })
                $current = $newObj
                $currentIndent = $arrayIndent + 2
            }
            else {
                # Simple scalar: "  - value"
                $val = $content.Trim('"')
                $current.Add($val)
            }
            continue
        }

        # --- Nested key: "key:" or "key: value" ---
        if ($cleanLine -match '^([^:]+?):\s*(.*)$') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()

            if ([string]::IsNullOrEmpty($value)) {
                # Dict or array â€” peek ahead for "- " to decide
                $lookAheadIndex = [Array]::IndexOf($Lines, $line) + 1
                $isDict = $true
                while ($lookAheadIndex -lt $Lines.Count) {
                    $laLine = $Lines[$lookAheadIndex]
                    if ($laLine -match '^\s*$' -or $laLine -match '^\s*#') { $lookAheadIndex++; continue }
                    $laTrimmed = $laLine.TrimEnd()
                    $laClean = $laTrimmed -replace '\s*#.*$', ''
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
                # Simple key: value
                $current[$key] = $value.Trim('"')
            }
        }
    }

    return $root
}

# ============================================================
#  CONFIG LOADING
# ============================================================

function Load-Config {
    param([string]$ConfigPath)

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path $env:USERPROFILE ".folder-summarizer\config.yaml"
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return Get-DefaultConfig
    }

    try {
        $raw = [System.IO.File]::ReadAllText(
            $ConfigPath,
            [System.Text.Encoding]::UTF8
        )

        # Start with defaults so missing optional values still work.
        $config = Get-DefaultConfig

        # --------------------------------------------------------
        # Reliable scalar values
        # --------------------------------------------------------

        $apiMatch = [regex]::Match(
            $raw,
            '(?m)^\s*api_key\s*:\s*["'']?([^"''\r\n]+)["'']?\s*$'
        )

        if ($apiMatch.Success) {
            $config["api_key"] = $apiMatch.Groups[1].Value.Trim()
        }

        $modelMatch = [regex]::Match(
            $raw,
            '(?m)^\s*model\s*:\s*["'']?([^"''\r\n]+)["'']?\s*$'
        )

        if ($modelMatch.Success) {
            $config["model"] = $modelMatch.Groups[1].Value.Trim()
        }

        # --------------------------------------------------------
        # Use existing parser for the rest when possible
        # --------------------------------------------------------

        try {
            $parsed = Parse-YAML ($raw -split "`r?`n")

            if ($parsed -is [System.Collections.IDictionary]) {
                foreach ($key in $parsed.Keys) {
                    if ($key -ne "api_key" -and $key -ne "model") {
                        $config[$key] = $parsed[$key]
                    }
                }
            }
        }
        catch {
            # Keep the reliably parsed scalar values and defaults.
        }

        return $config
    }
    catch {
        return Get-DefaultConfig
    }
}
function Get-DefaultConfig {
    return [ordered]@{
        api_key = "YOUR_KEY_HERE"
        model   = "gemini-3.5-flash"
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
            sample_frames       = 5
            sample_only_metadata = $true
        }
        security = [ordered]@{
            sensitive_patterns = @("credential","password","secret","token","recovery","key","\.pem$","\.key$")
            content_regex      = @("BEGIN (RSA|OPENSSH|DSA) PRIVATE KEY","sk-[a-zA-Z0-9]{20,}","gh[pousr]_[a-zA-Z0-9]{36}")
            action             = "mask"
        }
        ui = [ordered]@{
            detect_windows_language = $true
            override_language       = ""
        }
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

function Test-SensitiveFilename {
    param([string]$Filename)
    foreach ($pat in $script:SensitivePatterns) {
        try {
            if ($Filename -match "(?i)$pat") { return $true }
        }
        catch { continue }
    }
    return $false
}

function Test-SensitiveContent {
    param([string]$FilePath)
    $textExts = @(".txt",".md",".json",".yaml",".yml",".py",".js",".ts",".html",".css",".xml",".csv",".log",".conf",".ini",".ps1",".sh",".bat",".cmd",".cs",".java",".go",".rs",".rb",".php",".toml",".cfg")
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    if ($textExts -notcontains $ext) { return $false }
    try {
        $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8).Substring(0, [Math]::Min(4096, [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8).Length))
        foreach ($regex in $script:ContentRegexes) {
            try {
                if ($content -match $regex) { return $true }
            }
            catch { continue }
        }
    }
    catch { }
    return $false
}

# ============================================================
#  FILE CATEGORIZATION & SAMPLING
# ============================================================

function Get-CategoryFileGroups {
    param(
        [array]$AllFiles,
        [object]$Config
    )

    $samplingConfig = Get-ConfigValue $Config "sampling" @()
    $maxFiles = if ($samplingConfig -and $samplingConfig.Contains('max_files_per_group')) {
        [int]$samplingConfig['max_files_per_group']
    } else { 5 }

    # Include/exclude groups
    $includeGroups = if ($samplingConfig -and $samplingConfig.Contains('groups') -and $samplingConfig['groups'].Contains('include')) {
        $samplingConfig['groups']['include']
    } else { @("Images","Documents","Code","Audio","Video","Archives") }

    $excludeGroups = if ($samplingConfig -and $samplingConfig.Contains('groups') -and $samplingConfig['groups'].Contains('exclude')) {
        $samplingConfig['groups']['exclude']
    } else { @() }

    # Extension whitelist/blacklist
    $extConfig = Get-ConfigValue $Config "sampling.extensions" @()
    $whitelist = if ($extConfig -and $extConfig.Contains('whitelist')) { $extConfig['whitelist'] } else { @() }
    $blacklist = if ($extConfig -and $extConfig.Contains('blacklist')) { $extConfig['blacklist'] } else { @() }

    $extMap = [ordered]@{
        "Images"    = @(".jpg",".jpeg",".png",".gif",".bmp",".webp",".tiff",".svg",".raw",".heic",".avif",".ico")
        "Documents" = @(".pdf",".docx",".doc",".txt",".xlsx",".xls",".pptx",".ppt",".md",".csv",".rtf",".odt",".pages")
        "Video"     = @(".mp4",".avi",".mkv",".mov",".wmv",".flv",".webm",".m4v",".mpg",".mpeg")
        "Audio"     = @(".mp3",".wav",".flac",".aac",".ogg",".wma",".m4a",".opus",".aiff")
        "Code"      = @(".py",".js",".ts",".cs",".cpp",".c",".java",".go",".rs",".php",".html",".css",".ps1",".sh",".bat",".json",".yaml",".toml",".lua",".rb",".swift",".kt")
        "Archives"  = @(".zip",".rar",".7z",".tar",".gz",".bz2",".xz",".cab",".iso")
    }

    $result = [ordered]@{
        CategoryLines = [System.Collections.Generic.List[string]]::new()
        PromptCategories = [System.Collections.Generic.List[string]]::new()
    }

    foreach ($cat in $extMap.GetEnumerator()) {
        # Apply include/exclude filter
        if ($includeGroups -notcontains $cat.Key) { continue }
        if ($excludeGroups -contains $cat.Key) { continue }

        # Filter extensions by whitelist/blacklist
        $filteredExts = @($cat.Value | Where-Object {
            $ext = $_.ToLower()
            if ($whitelist.Count -gt 0 -and $whitelist -notcontains $ext) { return $false }
            if ($blacklist.Count -gt 0 -and $blacklist -contains $ext) { return $false }
            return $true
        })

        $matched = @($AllFiles | Where-Object {
            $filteredExts -contains $_.Extension.ToLower() -and
            -not (Test-SensitiveFilename $_.Name) -and
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

    if (-not [string]::IsNullOrEmpty($override)) {
        return $override
    }

    if (-not $detectLanguage) { return "en" }

    try {
        # Windows 10+ preferred method
        $langList = Get-WinUserLanguageList -ErrorAction SilentlyContinue
        if ($langList -and $langList.Count -gt 0) {
            return $langList[0].LanguageTag
        }
    }
    catch { }

    try {
        # Fallback: UI culture
        return (Get-UICulture).Name
    }
    catch { }

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

    $result = [ordered]@{
        Duration = ""
        Resolution = ""
        Codec = ""
        FramesExtracted = 0
    }

    # Try ffprobe for metadata
    if (Get-Command ffprobe -ErrorAction SilentlyContinue) {
        try {
            $duration = & ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$VideoPath" 2>$null
            if ($duration) { $result.Duration = [math]::Round([double]$duration, 1).ToString() + "s" }

            $resolution = & ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$VideoPath" 2>$null
            if ($resolution) { $result.Resolution = $resolution.Replace(",", "x") }

            $codec = & ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$VideoPath" 2>$null
            if ($codec) { $result.Codec = $codec }
        }
        catch { }
    }

    # Frame extraction (if not metadata-only and ffmpeg is available)
    if (-not $sampleOnlyMetadata -and $sampleFrames -gt 0 -and (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        try {
            $tmpdir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $tmpdir -Force | Out-Null
            & ffmpeg -i "$VideoPath" -vf "fps=1/$sampleFrames" -frames:v $sampleFrames -s "320x240" "$tmpdir/frame_%03d.jpg" 2>$null
            $frames = (Get-ChildItem "$tmpdir/*.jpg" -ErrorAction SilentlyContinue).Count
            $result.FramesExtracted = $frames
            Remove-Item $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch { }
    }

    return $result
}

# ============================================================
#  MAIN
# ============================================================

# -- Load config ------------------------------------------------
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path (Join-Path $env:USERPROFILE ".folder-summarizer") "config.yaml"
}

$config = Load-Config -ConfigPath $ConfigPath
$API_KEY  = Get-ConfigValue $config "api_key" "YOUR_KEY_HERE"
$MODEL    = Get-ConfigValue $config "model" "gemini-3.5-flash"
$API_URL  = "https://generativelanguage.googleapis.com/v1beta/models/$MODEL`:generateContent"
$securityAction = Get-ConfigValue $config "security.action" "mask"

# -- Initialize sensitive file patterns -------------------------
Init-SensitivePatterns -Config $config

# -- Detect Windows language ------------------------------------
$language = Get-WindowsLanguage -Config $config

# -- SECURITY WARNING -------------------------------------------
$warningMessage = @"
!  PRIVACY & SECURITY WARNING  !

This tool scans file names and folder structures and sends
selected metadata to the Google Gemini API (cloud).

The following information may be sent:
  - Folder paths and directory names
  - Non-sensitive file names
  - File extensions and file counts
  - Folder/file structure used to generate the summary

Sensitive files matching your configured security patterns
are excluded from the data sent to Gemini.

This tool does NOT intentionally upload file contents.
Text files are only inspected locally to detect configured
sensitive patterns.

However, filenames and folder structures may still contain
personal or sensitive information.

By proceeding, you assume FULL RESPONSIBILITY for any data
you choose to process. This tool provides no warranty or
privacy guarantee.

Do you accept this risk and wish to continue?
"@

$userChoice = [System.Windows.Forms.MessageBox]::Show(
    $warningMessage,
    "! SECURITY WARNING - Read Carefully",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Warning
)

if ($userChoice -eq "No") {
    Write-Host "Scan cancelled by user."
    exit
}

# -- Scan folder ------------------------------------------------
$allFiles = Get-ChildItem -Path $FolderPath -Recurse -File -ErrorAction SilentlyContinue
$topItems = Get-ChildItem -Path $FolderPath -ErrorAction SilentlyContinue
$dirCount = (Get-ChildItem -Path $FolderPath -Recurse -Directory -ErrorAction SilentlyContinue).Count
$rawSize  = ($allFiles | Measure-Object Length -Sum).Sum
$totalSize = if ($rawSize) { [math]::Round($rawSize / 1MB, 2) } else { 0 }

# -- Categorize & sample with sensitive filtering ----------------
$groups = Get-CategoryFileGroups -AllFiles $allFiles -Config $config
$catLines   = $groups.CategoryLines
$promptCats = $groups.PromptCategories

# -- Top-level contents -----------------------------------------
$topStr = ($topItems | ForEach-Object {

    if (Test-SensitiveFilename $_.Name) {
        "  [REDACTED]"
        return
    }

    if ($_.PSIsContainer) {
        "  [DIR]  $($_.Name)"
    }
    else {
        if (Test-SensitiveContent $_.FullName) {
            "  [FILE] [REDACTED]"
        }
        else {
            "  [FILE] $($_.Name)"
        }
    }

}) -join "`n"

# -- Video summary line -----------------------------------------
$videoFiles = @($allFiles | Where-Object { @(".mp4",".avi",".mkv",".mov",".wmv",".flv",".webm",".m4v",".mpg",".mpeg") -contains $_.Extension.ToLower() })
$videoSummary = ""
if ($videoFiles.Count -gt 0) {
    $meta = Get-VideoMetadata -VideoPath $videoFiles[0].FullName -Config $config
    $metaParts = @()
    if ($meta.Duration)   { $metaParts += "Duration: $($meta.Duration)" }
    if ($meta.Resolution) { $metaParts += "Resolution: $($meta.Resolution)" }
    if ($meta.Codec)      { $metaParts += "Codec: $($meta.Codec)" }
    if ($meta.FramesExtracted -gt 0) { $metaParts += "Frames sampled: $($meta.FramesExtracted)" }
    if ($metaParts.Count -gt 0) {
        $videoSummary = "`nVIDEO METADATA ($($videoFiles.Count) video files):`n  $($metaParts -join ' | ')"
    }
}

# -- Build API prompt -------------------------------------------
$prompt = @"
You are analyzing a folder on a Windows PC. Based only on the file and folder names below, write a 3-5 sentence summary that answers: what is this folder likely used for, what types of content dominate, and are there any notable patterns?

Use very simple, plain, everyday language. Short sentences. No fancy words. Imagine you're explaining this to a non-technical friend in one breath.

Output language: $language

FOLDER: $FolderPath
TOTAL FILES: $($allFiles.Count) | SUBDIRS: $dirCount | SIZE: $totalSize MB

TOP-LEVEL CONTENTS:
$topStr

SAMPLED FILES BY CATEGORY (first 5 per type):
$($promptCats -join "`n")
$videoSummary

Keep it concise, informative, and plain. No bullet points or markdown headers.
"@

# -- Call API ---------------------------------------------------
$bodyJson = @{
    contents = @(
        @{
            parts = @(
                @{
                    text = $prompt
                }
            )
        }
    )
    generationConfig = @{
        maxOutputTokens = 8192
    }
} | ConvertTo-Json -Depth 8

try {
    if ([string]::IsNullOrWhiteSpace($API_KEY) -or $API_KEY -eq "YOUR_KEY_HERE") {
        throw "Gemini API key is missing. Config loaded from: $ConfigPath. Set 'api_key' in that file."
    }

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
}
catch {
    $aiSummary = "API error: $($_.Exception.Message)"
}

# -- Format output ----------------------------------------------
$folderName = Split-Path -Leaf $FolderPath.TrimEnd('\')
$div        = "=" * 62

$output = @"

  $div
    FOLDER SUMMARY  -  $folderName
  $div

  Path    : $FolderPath
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
  !!  DISCLAIMER:
  File names and folder structures were analyzed for this summary.
  Files matching configured sensitive patterns are excluded from
  the data sent to Google Gemini API.
  User assumes all responsibility for any remaining data disclosed.
  Do NOT share this output publicly unless you have verified
  the scanned folder contains no sensitive filenames.
  $div

"@

# -- Display in dark-themed form --------------------------------
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "Folder Summary - $folderName"
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
$tb.Text        = $output
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











