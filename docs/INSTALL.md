# Installation

## The Easy Way

1. Download `folder-summarizer.exe` from `build/`
2. Double-click it
3. Follow the onboarding wizard:
   - Paste your [Google Gemini API key](https://aistudio.google.com/api-keys)
   - Optionally install ffmpeg for video metadata
4. Right-click any folder → **Summarize with AI**

That's it. The exe handles everything: copies itself to `%LOCALAPPDATA%\FolderSummarizer\`, creates the config, and registers the current-user context menu without requiring administrator rights.

## What Happens During Setup

| Step | What it does |
|------|-------------|
| 1. API Key | Saved to `%USERPROFILE%\.folder-summarizer\config.yaml` |
| 2. FFmpeg | Installed via `winget` if you opted in |
| 3. Copy exe | Copied to `%LOCALAPPDATA%\FolderSummarizer\folder-summarizer.exe` |
| 4. Context menu | Current-user registry entries added; no UAC prompt |

## Prerequisites

| Requirement | Details |
|-------------|--------|
| OS | Windows 10 or 11 |
| Network | Active internet connection |
| API Key | [Google Gemini API Key](https://aistudio.google.com/api-keys) (free) |
| Optional | `ffmpeg` / `ffprobe` for video metadata (offered during setup) |

## Windows 11 Context Menu

On Windows 11, the "Summarize with AI" option is in the classic context menu:

- Right-click a folder → click **"Show more options"** (or press **Shift+F10**)
- Or restore the full classic right-click menu using tools like [ExplorerPatcher](https://github.com/valinet/ExplorerPatcher)

## Compiling from Source

If you want to build the exe yourself:

```powershell
# Install ps2exe
Install-Module ps2exe -Scope CurrentUser

# Compile (no console window)
Invoke-PS2EXE -InputFile .\src\FolderSummarizer.ps1 -OutputFile .\build\folder-summarizer.exe -noConsole
```

## After Installation

### Change settings
Double-click `%LOCALAPPDATA%\FolderSummarizer\folder-summarizer.exe` to open the Settings window.

### Change API key
Open Settings, paste a new key, click Save.

### Edit advanced config
Open `%USERPROFILE%\.folder-summarizer\config.yaml` in any text editor.

## Uninstall

### Via Settings
Double-click `%LOCALAPPDATA%\FolderSummarizer\folder-summarizer.exe` → Settings → Uninstall.

### Manually

```powershell
# 1. Remove context menu
Remove-Item -Path 'HKCU:\Software\Classes\Directory\shell\FolderSummary' -Recurse -Force
Remove-Item -Path 'HKCU:\Software\Classes\Directory\Background\shell\FolderSummary' -Recurse -Force

# 2. Remove the exe
Remove-Item -Path "$env:LOCALAPPDATA\FolderSummarizer\folder-summarizer.exe" -Force

# 3. Remove config (optional - your settings)
Remove-Item -Path "$env:USERPROFILE\.folder-summarizer" -Recurse -Force
```

## Troubleshooting

| Problem | Solution |
|---------|--------|
| Context menu item missing | Re-run the exe, it will re-register |
| "API Error" in summary | Check your API key in Settings |
| AI Studio shows "Available Regions" | Try a different Google account |
| No summary generated | Ensure the folder has files and your API key is valid |
| Video metadata missing | Install ffmpeg via Settings or from [ffmpeg.org](https://ffmpeg.org/download.html) |
| Sensitive file not detected | Add the pattern to `security.sensitive_patterns` in config |
| Want to re-run onboarding | Delete `%USERPROFILE%\.folder-summarizer\config.yaml` and double-click the exe |
