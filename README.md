# Folder Summarizer with AI

> Right-click any folder in Windows Explorer, get an instant AI summary.

## How It Works

1. Download `folder-summarizer.exe`
2. Double-click it - a setup wizard appears
3. Paste your free Google Gemini API key
4. Done. Right-click any folder → **Summarize with AI**

The exe copies itself to `%LOCALAPPDATA%\FolderSummarizer\`, registers a Windows Explorer context menu entry for the current user, and from that point on it lives there. Double-click the installed exe anytime to change settings.

No dependencies. No PowerShell scripts to run. No separate installer. The exe is the whole thing.

## What It Does

Scans a folder's file structure, sends metadata to Google Gemini, and shows a concise summary in a dark-themed popup. No file contents are uploaded - only file names, folder names, extensions, and counts.

### Key Features

- **Single exe** - self-installs, self-registers, no external scripts needed
- **Onboarding wizard** - guides you through API key setup on first run
- **Context menu integration** - right-click any folder → "Summarize with AI"
- **Sensitive name redaction** - file/folder names matching security patterns are redacted before sending to the API
- **Config file** - all settings in `~/.folder-summarizer/config.yaml`
- **Sampling control** - include/exclude categories, set max files per group
- **Content scanning** - text files are inspected locally for private keys, tokens, and other secrets
- **Video metadata** - duration, resolution, codec via `ffprobe` (optional, offered during setup)
- **Language detection** - auto-detects Windows language for the summary output
- **No dependencies** - pure PowerShell + built-in .NET, no third-party modules

## Quick Start

1. Grab `folder-summarizer.exe` from `build/` (or compile from `src/FolderSummarizer.ps1`)
2. Double-click the exe
3. Paste your [Google Gemini API key](https://aistudio.google.com/api-keys) in the setup wizard
4. Optionally install ffmpeg for video metadata
5. Right-click any folder → **Summarize with AI**

### Windows 11 Users

On Windows 11, the context menu option appears under the classic menu. To see it:
- Right-click a folder, then click **"Show more options"** (or press **Shift+F10**)
- Or restore the classic right-click menu with tools like [Windows 11 Context Menu Back](https://github.com/valinet/ExplorerPatcher)

## Getting an API Key

1. Go to [https://aistudio.google.com/api-keys](https://aistudio.google.com/api-keys)
2. Sign in with a Google account
3. Click **"Create API Key"**
4. Copy the key and paste it into the setup wizard

> **Note:** If the AI Studio page redirects to an "Available Regions" error, try a different Google account - AI Studio can be buggy with region availability.

## Compiling from Source

The exe is compiled from `src/FolderSummarizer.ps1` using [ps2exe](https://github.com/MScholtes/Ps2Exe):

```powershell
# Install ps2exe
Install-Module ps2exe -Scope CurrentUser

# Compile
Invoke-PS2EXE -InputFile .\src\FolderSummarizer.ps1 -OutputFile .\build\folder-summarizer.exe -noConsole
```

## Documentation

| File | What's in it |
|------|-------------|
| [docs/INSTALL.md](docs/INSTALL.md) | Installation, prerequisites, uninstallation |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | All `config.yaml` options with examples |
| [docs/SECURITY.md](docs/SECURITY.md) | What data is sent, how redaction works, sensitive patterns |

## Direct Usage (without context menu)

```powershell
# Via the exe directly
.\folder-summarizer.exe "C:\MyFolder"

# Or via PowerShell
.\src\FolderSummarizer.ps1 -FolderPath "C:\MyFolder"
```

## Uninstall

Double-click the installed exe (`%LOCALAPPDATA%\FolderSummarizer\folder-summarizer.exe`), go to Settings, and click **Uninstall**.

Or manually:

```powershell
# Remove context menu
Remove-Item -Path 'HKCU:\Software\Classes\Directory\shell\FolderSummary' -Recurse -Force
Remove-Item -Path 'HKCU:\Software\Classes\Directory\Background\shell\FolderSummary' -Recurse -Force

# Remove the exe
Remove-Item -Path "$env:LOCALAPPDATA\FolderSummarizer\folder-summarizer.exe" -Force

# Remove config (optional)
Remove-Item -Path "$env:USERPROFILE\.folder-summarizer" -Recurse -Force
```

## License

This project is **source-available, not open source**. It is licensed under the
[Noncommercial Copyleft License 1.1](LICENSE).

- **No paid commercial use.** You may not sell it, charge for access or hosting,
  offer paid support based on it, or bundle it into a paid product. Internal use,
  evaluation, and personal/hobby projects are fine — including at for-profit
  companies.
- **No closed source.** Any modified version you distribute must be released in full
  under the same license, with complete source code.

Commercial rights are available only under a separate written agreement with the
maintainer.

Required Notice: Copyright (c) 2026 gorzkie-graffiti
