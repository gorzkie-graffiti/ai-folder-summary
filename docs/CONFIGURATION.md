# Configuration

All settings live in:

```
%USERPROFILE%\.folder-summarizer\config.yaml
```

Open Settings by double-clicking `C:\Scripts\folder-summarizer.exe`, or edit the YAML file directly.

## Full Example

```yaml
api_key: "AQ...."
model: "gemini-3.5-flash"

sampling:
  max_files_per_group: 5
  groups:
    include: ["Images", "Documents", "Code", "Audio", "Video", "Archives"]
    exclude: []
  extensions:
    whitelist: []
    blacklist: [".exe", ".dll", ".pyc", ".class"]

video:
  sample_frames: 5
  sample_only_metadata: true

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
    - "sk-[a-zA-Z0-9]{20,}"
    - "gh[pousr]_[a-zA-Z0-9]{36}"
  action: "mask"

ui:
  detect_windows_language: true
  override_language: ""
  warning_accepted: false
```

## Options

### `api_key`

Your Google Gemini API key. **Required.** Set during onboarding.

```yaml
api_key: "AQ...."
```

### `model`

Gemini model for summarization. Defaults to `gemini-3.5-flash`.

```yaml
model: "gemini-3.5-flash"
```

### `sampling.max_files_per_group`

How many representative filenames to include per category. Default: `5`.

```yaml
sampling:
  max_files_per_group: 5
```

### `sampling.groups`

Which file categories to include or exclude.

```yaml
groups:
  include: ["Images", "Documents", "Code", "Audio", "Video", "Archives"]
  exclude: ["Archives"]  # skip archive files
```

### `sampling.extensions`

Optional extension whitelist and blacklist. Empty whitelist means all extensions are allowed.

```yaml
extensions:
  whitelist: []  # empty = allow all
  blacklist: [".exe", ".dll", ".pyc", ".class"]
```

### `video`

Controls video metadata extraction. Requires `ffprobe` in PATH.

```yaml
video:
  sample_frames: 5
  sample_only_metadata: true  # true = duration/resolution/codec only
```

When `sample_only_metadata` is `false`, frames are extracted via `ffmpeg` and the count is reported.

### `security`

See [SECURITY.md](SECURITY.md) for full details.

```yaml
security:
  sensitive_patterns:
    - "password"
    - "secret"
  content_regex:
    - "BEGIN (RSA|OPENSSH|DSA) PRIVATE KEY"
  action: "mask"  # "mask" or "skip"
```

### `ui`

```yaml
ui:
  detect_windows_language: true  # auto-detect OS language for summaries
  override_language: ""           # force a specific language, e.g. "pl-PL"
  warning_accepted: false          # set to true to skip the first-run privacy notice
```

`warning_accepted` is set automatically when you check "Don't show again" on the privacy dialog.