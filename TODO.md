## Todo 1: Proper UI

- Keep your CLI/TUI for power users (you).
- Build a **config file** (`~/.folder-summarizer/config.yaml`) where all settings live.
- Later, wrap it in a **HTML/Electron** or **Tauri** UI

**Immediate action:** Add `--config` flag to point to a YAML file. That's 20 lines of `yaml.safe_load()`.

---

## Todo 2 & 4: Sampling control + video limits

These go together. Define a config schema like this:

```yaml
# config.yaml
sampling:
  max_files_per_group: 5          # already doing this
  groups:
    include: ["Images", "Documents", "Code", "Audio", "Video", "Archives"]
    exclude: []                   # optional: e.g., ["Archives"]
  extensions:
    whitelist: []                 # empty = all allowed
    blacklist: [".exe", ".dll", ".pyc", ".class"]

video:
  sample_frames: 5                # number of frames to extract
  sample_only_metadata: false     # if true, skip frame extraction entirely

security:
  sensitive_patterns:
    - "credential"
    - "password"
    - "secret"
    - "token"
    - "recovery"
    - "key"
    - "\\.pem$"
    - "\\.key$"
  content_regex:
    - "BEGIN (RSA|OPENSSH|DSA) PRIVATE KEY"
    - "sk-[a-zA-Z0-9]{20,}"      # OpenAI API keys
    - "gh[pousr]_[a-zA-Z0-9]{36}" # GitHub tokens
  action: "mask"                 # or "skip" (skip entirely) or "warn"
```

---

## Todo 3: Sensitive file handling (critical)

### Step 1: Filename filtering (fast)

Check the filename against `sensitive_patterns` from config. If matched:

- If `action: "skip"` → don't include in the summary at all.
- If `action: "mask"` → replace the filename with `[REDACTED]` and don't read its content.

### Step 2: Content scanning for text files

For files that are text-based (`.txt`, `.md`, `.json`, `.yaml`, `.py`, `.js`, etc.):

- Read first 1KB (or entire file if small) and scan with `content_regex` regexes.
- If a match is found, either skip the file entirely or redact the matched lines.

### Implementation snippet (drop into your existing scanner):

```python
import re
import yaml

def load_config():
    with open("config.yaml") as f:
        return yaml.safe_load(f)

CONFIG = load_config()

def is_sensitive_filename(filename: str) -> bool:
    patterns = CONFIG["security"]["sensitive_patterns"]
    for pat in patterns:
        if re.search(pat, filename, re.IGNORECASE):
            return True
    return False

def has_sensitive_content(filepath: str) -> bool:
    # Only check text files (extensions set)
    text_exts = {".txt", ".md", ".json", ".yaml", ".yml", ".py", ".js", ".html", ".css", ".xml", ".csv", ".log", ".conf", ".ini"}
    if Path(filepath).suffix.lower() not in text_exts:
        return False
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read(4096)  # first 4KB enough for most secrets
    except:
        return False
    for pattern in CONFIG["security"]["content_regex"]:
        if re.search(pattern, content, re.IGNORECASE):
            return True
    return False

# When scanning a file:
if is_sensitive_filename(filename) or has_sensitive_content(full_path):
    if CONFIG["security"]["action"] == "skip":
        continue  # don't even list it
    else:  # mask
        display_name = "[REDACTED]"
        content_preview = "[REDACTED]"
        # still count it in the group, but don't reveal details
```

---

## Step 3: Video frame sampling

Use `ffmpeg-python` or `opencv-python` to extract frames:

```python
import subprocess
import tempfile
from pathlib import Path

def sample_video_frames(video_path, num_frames=5):
    """Extract num_frames evenly spaced frames from video, return base64 or just count them."""
    # Use ffmpeg to extract thumbnails into temp dir
    with tempfile.TemporaryDirectory() as tmpdir:
        cmd = [
            "ffmpeg", "-i", str(video_path),
            "-vf", f"fps=1/{num_frames}",  # or select frames by time
            "-frames:v", str(num_frames),
            "-s", "320x240",  # small thumbnails
            f"{tmpdir}/frame_%03d.jpg"
        ]
        subprocess.run(cmd, capture_output=True, check=False)
        # Count how many frames were actually extracted
        frame_count = len(list(Path(tmpdir).glob("*.jpg")))
    return frame_count  # or return list of base64 if you want to show them later
```

Put this behind a config flag:

- If `video.sample_only_metadata: true` → just get duration, resolution, codec (using `ffprobe`) and skip frame extraction.
- If `false` → extract `video.sample_frames` frames and report "sampled X frames".

---

## Todo 4: Detect Windows language and inject $language into API prompt

- Query Windows user/UI language at runtime and set a variable (e.g. `$language`) that is added to the prompt or request payload sent to the summarization API.
- Use `$language` to request the summary in that language OR to pass as an explicit parameter to your backend (preferred).

Example PowerShell snippets:

```powershell
# Option A: get UI culture name
$language = (Get-UICulture).Name  # e.g. "en-US" or "pl-PL"

# Option B: prefer user languages (Windows 10+)
$langList = Get-WinUserLanguageList
if ($langList -and $langList.Count -gt 0) { $language = $langList[0].LanguageTag } else { $language = (Get-Culture).Name }

# Inject into prompt / request body:
$prompt = "Summarize the selected folder. Output language: $language. Keep it concise."
$body = @{
  prompt = $prompt
  language = $language
  # other fields...
} | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri $apiUrl -Body $body -ContentType "application/json"
```

Notes:

- Prefer passing language as a separate field to your API so the model/system prompt can condition on it reliably (e.g. system: "You are a summarizer. Always answer in the requested language: $language").
- Fall back to a default (e.g., "en") if detection fails.
- Make this behavior configurable in config.yaml (e.g., ui.detect_windows_language: true/false and ui.override_language: "pl-PL").

---

## Todo 5: Simpler setup

Make onboarding a one-step script that:

- Creates config directory and default config if missing.
- Installs/checks runtime deps (ffmpeg, python libs or required modules).
- Optionally registers the Windows context-menu entry (or outputs instructions if admin rights are required).

Example install PowerShell (skeleton):

```powershell
param(
  [switch]$RegisterContextMenu
)

$homeConfig = Join-Path $env:USERPROFILE ".folder-summarizer"
$configFile = Join-Path $homeConfig "config.yaml"

if (-not (Test-Path $homeConfig)) { New-Item -ItemType Directory -Path $homeConfig | Out-Null }

if (-not (Test-Path $configFile)) {
  $default = @"
sampling:
  max_files_per_group: 5
video:
  sample_frames: 5
  sample_only_metadata: false
security:
  sensitive_patterns:
    - "credential"
    - "password"
  content_regex: []
  action: "mask"
ui:
  detect_windows_language: true
"@
  $default | Out-File -FilePath $configFile -Encoding utf8
  Write-Host "Wrote default config to $configFile"
}

# Check ffmpeg
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
  Write-Host "ffmpeg not found in PATH. Please install ffmpeg or add it to PATH."
  # Optionally download / suggest choco install
}

if ($RegisterContextMenu) {
  Write-Host "Registering context menu (requires admin)..."
  # Add registry changes here or call a helper function
}
```

Also:

- Add README snippet: "Run .\install.ps1 -RegisterContextMenu" or just "run install.ps1" to get started.
- Consider publishing a single EXE/installer later, but for now keep the script minimal and idempotent.

---

This is my language so I can read it more clearly/Dla mnie żeby mógł przeczytać wyraźniej

---

## Polish / PL — Tłumaczenie i dodatkowe Todo

## Todo 1: Właściwy interfejs użytkownika

- Zachowaj CLI/TUI dla zaawansowanych użytkowników (ciebie).
- Zbuduj **plik konfiguracyjny** (`~/.folder-summarizer/config.yaml` gdzie będą przechowywane wszystkie ustawienia).
- Później opakuj to w **HTML/Electron** lub **Tauri** UI.

**Natychmiastowe działanie:** Dodaj flagę `--config`, aby wskazywać plik YAML. To ~20 linijek z `yaml.safe_load()`.

---

## Todo 2 & 4: Kontrola próbkowania + limity video

To idzie razem. Zdefiniuj schemat konfiguracji jak poniżej:

(ten sam blok YAML co wyżej — patrz sekcja English)

---

## Todo 3: Obsługa plików wrażliwych (krytyczne)

### Krok 1: Filtrowanie po nazwie pliku (szybkie)

Sprawdź nazwę pliku względem `sensitive_patterns` z konfiguracji. Jeśli pasuje:

- (odpytuje z configu)
  Jeśli `action: "skip"` → nie uwzględniaj w podsumowaniu.
- Jeśli `action: "mask"` → zastąp nazwę pliku `[REDACTED]` i nie czytaj jego zawartości.

### Krok 2: Skanowanie zawartości dla plików tekstowych

Dla plików tekstowych (`.txt`, `.md`, `.json`, `.yaml`, `.py`, `.js`, itp.):

- Przeczytaj pierwsze 1KB (lub cały plik jeśli jest mały) i przeskanuj za pomocą `content_regex`.
- Jeśli wykryjesz dopasowanie — pomiń plik lub zredaguj dopasowane linie.

(ten sam snippet implementacyjny Python — patrz sekcja English)

---

## Krok 3: Próbkowanie klatek wideo

(Użyj tego samego przykładu ffmpeg co w sekcji English — patrz wyżej)

---

## Todo 4: Wykrywanie języka Windows i wstrzykiwanie $language do promptu API

- Odczytaj język UI/użytkownika Windows w czasie wykonywania i ustaw zmienną (np. `$language`), którą dodasz do promptu lub ciała żądania wysyłanego do API podsumowującego.
- Użyj `$language`, by poprosić o podsumowanie w tym języku LUB przekaż jako osobne pole do backendu (zalecane).

Przykładowe PowerShell:

```powershell
$language = (Get-UICulture).Name
# lub preferowane:
$langList = Get-WinUserLanguageList
if ($langList -and $langList.Count -gt 0) { $language = $langList[0].LanguageTag } else { $language = (Get-Culture).Name }

# Wstrzyknięcie do promptu / body:
$prompt = "Summarize the selected folder. Output language: $language. Keep it concise."
$body = @{
  prompt = $prompt
  language = $language
} | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri $apiUrl -Body $body -ContentType "application/json"
```

Uwaga:

- Lepiej przekazywać język jako oddzielne pole, żeby system prompt mógł się nim konsekwentnie posługiwać.
- Zapewnij fallback (np. "en") jeśli wykrywanie się nie powiedzie.
- Dodaj opcję w config.yaml: `ui.detect_windows_language: true/false` i `ui.override_language`.

---

## Todo 5: Prostszy setup

Uprość onboarding jednym skryptem:

- Tworzy katalog konfiguracyjny i domyślny config jeśli go brakuje.
- Sprawdza/instaluje zależności (ffmpeg, biblioteki).
- Opcjonalnie rejestruje wpis w menu kontekstowym Windows (albo wypisuje instrukcję jeśli wymagane są prawa admina).

Przykład instalacyjny PowerShell (szkic wyżej) — skrypt tworzy domyślny config i sprawdza ffmpeg.

Dodatkowo:

- Dodaj README z instrukcją „Uruchom .\install.ps1 -RegisterContextMenu” lub po prostu „run install.ps1”.
- Rozważ pojedynczy instalator/EXE później, ale na razie zachowaj prosty, idempotentny skrypt.
