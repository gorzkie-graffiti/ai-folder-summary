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

# 