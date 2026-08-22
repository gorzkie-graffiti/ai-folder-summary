# ============================================================
#  FolderSummarizer.ps1
# ============================================================
param([string]$FolderPath)

# -- LOAD WINDOWS FORMS EARLY (for the warning dialog) -------
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# ============================================================
#  !  CRITICAL PRIVACY & SECURITY WARNING  !
# ============================================================
$warningMessage = @"
!  PRIVACY & SECURITY WARNING  !

This tool scans file NAMES and folder structures, then sends that
text to the Google Gemini API (cloud).

While it does NOT upload the actual file contents, the following
IS transmitted to Google's servers:
  - Full file paths and file names
  - Folder hierarchy and directory names
  - File sizes, extensions, and modification dates

File names may contain sensitive information such as:
  - Passwords, credentials, or recovery keys in the filename
  - Usernames, emails, or project codenames
  - API keys or tokens (e.g., "secret-key.txt")

By proceeding, you assume FULL RESPONSIBILITY for any data
exposure. This tool provides no warranty or privacy guarantee.

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
# ============================================================

# -- CONFIGURE -----------------------------------------------
$API_KEY = "YOUR_KEY_HERE"
$API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent"
$MODEL   = "gemini-3.5-flash"
# ------------------------------------------------------------

$extMap = [ordered]@{
    "Images"    = @(".jpg",".jpeg",".png",".gif",".bmp",".webp",".tiff",".svg",".raw",".heic",".avif",".ico")
    "Documents" = @(".pdf",".docx",".doc",".txt",".xlsx",".xls",".pptx",".ppt",".md",".csv",".rtf",".odt",".pages")
    "Video"     = @(".mp4",".avi",".mkv",".mov",".wmv",".flv",".webm",".m4v",".ts",".mpg",".mpeg")
    "Audio"     = @(".mp3",".wav",".flac",".aac",".ogg",".wma",".m4a",".opus",".aiff")
    "Code"      = @(".py",".js",".ts",".cs",".cpp",".c",".java",".go",".rs",".php",".html",".css",".ps1",".sh",".bat",".json",".yaml",".toml",".lua",".rb",".swift",".kt")
    "Archives"  = @(".zip",".rar",".7z",".tar",".gz",".bz2",".xz",".cab",".iso")
}

$allFiles  = Get-ChildItem -Path $FolderPath -Recurse -File      -ErrorAction SilentlyContinue
$topItems  = Get-ChildItem -Path $FolderPath                      -ErrorAction SilentlyContinue
$dirCount  = (Get-ChildItem -Path $FolderPath -Recurse -Directory -ErrorAction SilentlyContinue).Count
$rawSize   = ($allFiles | Measure-Object Length -Sum).Sum
$totalSize = if ($rawSize) { [math]::Round($rawSize / 1MB, 2) } else { 0 }

$catLines   = [System.Collections.Generic.List[string]]::new()
$promptCats = [System.Collections.Generic.List[string]]::new()

foreach ($cat in $extMap.GetEnumerator()) {
    $matched = @($allFiles | Where-Object { $cat.Value -contains $_.Extension.ToLower() })
    if ($matched.Count -gt 0) {
        $sample = ($matched | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ", "
        $catLines.Add("  $($cat.Key.PadRight(12)) [$($matched.Count.ToString().PadLeft(4))] : $sample")
        $promptCats.Add("$($cat.Key) ($($matched.Count) total) - checked: $sample")
    }
}

$topStr = ($topItems | ForEach-Object {
    if ($_.PSIsContainer) { "  [DIR]  $($_.Name)" }
    else                  { "  [FILE] $($_.Name)" }
}) -join "`n"

$prompt = @"
You are analyzing a folder on a Windows PC. Based only on the file and folder names below, write a 3-5 sentence summary that answers: what is this folder likely used for, what types of content dominate, and are there any notable patterns?

Use very simple, plain, everyday language. Short sentences. No fancy words. Imagine you're explaining this to a non-technical friend in one breath.

FOLDER: $FolderPath
TOTAL FILES: $($allFiles.Count) | SUBDIRS: $dirCount | SIZE: $totalSize MB

TOP-LEVEL CONTENTS:
$topStr

SAMPLED FILES BY CATEGORY (first 5 per type):
$($promptCats -join "`n")

Keep it concise, informative, and plain. No bullet points or markdown headers.
"@

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
        maxOutputTokens = 999999
    }
} | ConvertTo-Json -Depth 8

try {
    $resp      = Invoke-RestMethod $API_URL -Method POST -Headers @{
        "x-goog-api-key" = $API_KEY
        "Content-Type"   = "application/json"
    } -Body $bodyJson -ErrorAction Stop
    $aiSummary = $resp.candidates[0].content.parts[0].text.Trim()
} catch {
    $aiSummary = "API error: $($_.Exception.Message)"
}

$folderName = [System.IO.Path]::GetFileName($FolderPath.TrimEnd('\'))
$div        = "=" * 62

$output = @"

  $div
    FOLDER SUMMARY  -  $folderName
  $div

  Path    : $FolderPath
  Files   : $($allFiles.Count)   |   Folders: $dirCount   |   Size: $totalSize MB
  Model   : $MODEL

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
  File names and folder structures were sent to Google Gemini API.
  User assumes all responsibility for any data disclosed.
  Do NOT share this output publicly unless you have verified
  the scanned folder contains no sensitive filenames.
  $div

"@

# The form is already created here, but we need to re-add the controls
# since we moved the Add-Type to the top. The rest is unchanged.
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