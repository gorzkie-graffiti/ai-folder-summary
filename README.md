# Folder Summarizer with AI

> **Summarize folder contents instantly with AI**  
> *Finally make sense of mystery folders like `erfhfwhuwf` without opening a single file.*

![Folder Summarizer Logo](src/logo.jpg)

---

## Overview

**Folder Summarizer** adds a convenient **"Summarize with AI"** option to your Windows File Explorer context menu. When run on any directory, it scans the file structure, sends metadata to Google’s Gemini AI, and displays a plain-English summary in a dark-themed pop-up window.

Get instant descriptions of folder purposes, dominant file types, and structural patterns without sifting through subdirectories manually.

---

## How It Works

1. **Trigger**: Right-click a folder (or empty space inside a folder) and select **Summarize with AI**.
2. **Scan**: The script recursively analyzes the directory:
   - Counts total files, subfolders, and cumulative file size.
   - Groups files into categories (*Images, Documents, Video, Audio, Code, Archives*).
   - Samples up to 5 representative filenames per category.
3. **Prompt Generation**: Assembles directory stats and sample filenames into a structured prompt.
4. **AI Processing**: Queries the Google Gemini API (`gemini-3.5-flash`).
5. **Display**: Launches a dark-themed summary window showing folder stats and a concise 3–5 sentence analysis. *(If the window does not pop up automatically, click the PowerShell icon on your taskbar).*

---

## Installation (One-Time Setup)

### Prerequisites

* **OS**: Windows 10 or 11
* **Shell**: PowerShell (built-in)
* **Permissions**: Administrator privileges (for installation)
* **Network**: Active internet connection
* **API Key**: A valid [Google Gemini API Key](https://aistudio.google.com/apikey)

---

### Step 0: Get a Gemini API Key

1. Navigate to [Google AI Studio](https://aistudio.google.com/apikey).
2. Sign in with your Google account.
3. Click **Create API key** and copy your key to the clipboard.

---

### Step 1: Download the Scripts

Place both `FolderSummarizer.ps1` and `Install-ContextMenu.ps1` in the same directory.

---

### Step 2: Configure Your API Key

Open `FolderSummarizer.ps1` in a text editor (e.g., Notepad) and update the `$API_KEY` variable with your key:

```powershell
$API_KEY = "your-actual-api-key-here"
```

Save and close the file.

---

### Step 3: Run the Installer

Right-click `Install-ContextMenu.ps1` and select **Run with PowerShell** (or execute it in an elevated PowerShell terminal).

The installer automatically:

* Creates `C:\Scripts` and copies `FolderSummarizer.ps1` to that directory.
* Registers context menu entries for folder shortcuts and folder background menus.

> **Windows 11 Users:** This tool integrates with the classic Windows context menu. If you are using the default modern context menu, restore the classic menu first using [this guide](https://www.reddit.com/r/sysadmin/comments/1frq94l/guide_restore_old_rightclick_context_menu_in/).

---

## Usage

1. Open File Explorer and locate any directory.
2. Right-click the folder icon or empty space inside the folder.
3. Select **Summarize with AI**.
4. After a brief pause, a pop-up window will appear displaying:
* Directory metadata (Path, file/folder count, overall size).
* Category breakdowns and sampled filenames.
* Plain-English AI analysis.
5. Click **Close** when finished.

---

## Example Output

```text
  ==============================================================
    FOLDER SUMMARY  -  MyProject
  ==============================================================

  Path    : C:\Users\me\Documents\MyProject
  Files   : 142   |   Folders: 23   |   Size: 456.78 MB
  Model   : gemini-3.5-flash

  --------------------------------------------------------------
  FILES CHECKED (first 5 per type):
  --------------------------------------------------------------

    Images       [  12] : logo.png, screenshot1.jpg, icon.ico, banner.webp, bg.png
    Documents    [  34] : readme.md, specification.docx, budget.xlsx, notes.txt, plan.pdf
    Code         [  76] : main.py, utils.js, style.css, index.html, app.cs
    ...

  --------------------------------------------------------------
  AI SUMMARY:
  --------------------------------------------------------------

    This folder appears to be a software project for a web application.
    The majority of files consist of source code (Python, JavaScript, HTML)
    alongside relevant technical documentation. UI assets such as images
    and icons are also included. The structure is well-organized.
```

---

## Uninstallation

To remove context menu integration, delete the following registry keys:

* `HKLM\SOFTWARE\Classes\Directory\shell\FolderSummary`
* `HKLM\SOFTWARE\Classes\Directory\Background\shell\FolderSummary`

Run this command in an elevated PowerShell window:

```powershell
Remove-Item -Path "HKLM:\SOFTWARE\Classes\Directory\shell\FolderSummary" -Recurse -Force
Remove-Item -Path "HKLM:\SOFTWARE\Classes\Directory\Background\shell\FolderSummary" -Recurse -Force
```

Optionally, delete `C:\Scripts\FolderSummarizer.ps1`.

---

## Troubleshooting

| Problem                          | Cause                                                  | Solution                                                                                                                                                                             |
| -------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Context menu item missing**    | Windows 11 modern context menu active or missing setup | Enable the **classic right-click menu**. Re-run `Install-ContextMenu.ps1` as Administrator.                                                                                          |
| **"API Error" pop-up**           | Invalid key or network disconnect                      | Check internet connectivity and ensure `$API_KEY` in `FolderSummarizer.ps1` is accurate.                                                                                             |
| **Execution policy block error** | Restricted execution policy                            | Run scripts with `-ExecutionPolicy Bypass`, or right-click `FolderSummarizer.ps1` $\rightarrow$ **Properties** $\rightarrow$ check **Unblock**.![Proporties dialog](src/unblock.jpg) |
| **Pop-up window not visible**    | Window spawned in background                           | Click the PowerShell icon active on your Windows taskbar.                                                                                                                            |
| **No summary generated**         | Empty directory or rate limit                          | Ensure the target folder contains files. If hit by rate limits, wait a moment before trying again.                                                                                   |

---

## Technical Notes

* **Dependencies**: Native PowerShell and .NET assemblies only—no third-party modules required.
* **Model Configuration**: Default model is `gemini-3.5-flash`. You can modify the `$MODEL` string in `FolderSummarizer.ps1` if you prefer a different model.
* **Privacy**: All processing occurs locally. Only metadata (counts, sizes, file types, and sampled filenames) is sent to Google's API. No actual file contents are uploaded.

---

## License

Free to use, modify, and distribute as-is.