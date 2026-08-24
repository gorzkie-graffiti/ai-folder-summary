# Security & Privacy

## What is sent to the API

The following data is included in the Gemini API request:

- File names (non-sensitive)
- Folder names (non-sensitive, **redacted per path segment**)
- File extensions and counts per category
- Total file count, directory count, and cumulative size
- Top-level directory contents
- Video metadata (duration, resolution, codec) if `ffprobe` is available

**File contents are never uploaded.**

Text files (`.txt`, `.py`, `.json`, etc.) are read locally up to 4096 bytes to check for secret patterns, but the contents are never sent anywhere.

## What is NOT sent

- File contents
- File sizes of individual files
- Modification dates
- Any data from files or folders matching security patterns

## Redaction: how it works

Redaction operates at three levels:

### 1. Filename matching

File names are tested against `security.sensitive_patterns`. Matching files are either:

- **`mask`** (default) — shown as `[REDACTED]` locally and excluded from the API prompt
- **`skip`** — omitted entirely, not even a placeholder

### 2. Directory name matching

Same pattern matching is applied to **directory names** at every level — not just files. A folder named `passwords` or `tax-returns` will be redacted even if none of its individual files trigger the filter.

### 3. Path segment redaction

The full folder path sent to the API is scanned per-segment. If any component of the path (e.g., `C:\Users\john\financial-records\project`) contains a sensitive name, that segment is replaced with `[REDACTED]` in the API prompt:

```
Sent to API:    C:\Users\john\[REDACTED]\project
Shown locally:  C:\Users\john\financial-records\project
```

The local display always shows the real path.

## Content scanning

Text files are inspected locally for patterns in `security.content_regex`:

```yaml
content_regex:
  - "BEGIN (RSA|OPENSSH|DSA) PRIVATE KEY"
  - "sk-[a-zA-Z0-9]{20,}"       # OpenAI API keys
  - "gh[pousr]_[a-zA-Z0-9]{36}" # GitHub tokens
```

Only the first 4096 bytes of each text file are checked. If a match is found, the file is treated as sensitive regardless of its name.

## Configuring patterns

Add your own patterns to `security.sensitive_patterns`:

```yaml
security:
  sensitive_patterns:
    - "password"
    - "secret"
    - "credential"
    - "tax"
    - "financial"
    - "medical"
    - "\.pem$"
    - "\.key$"
```

Patterns are case-insensitive regex.

## Limitations

- **Folder names are the biggest risk.** A folder called `tax-returns-2024` reveals information even when contents are not sent. Add patterns for your sensitive folder names.
- **Redaction is pattern-based.** If a sensitive folder doesn't match any configured pattern, its name will be sent to the API.
- **The API receives anonymized metadata.** Google's API terms and privacy policy apply to any data sent.
- **Results are displayed locally.** The summary window shows the real path. Do not share screenshots of the output without reviewing them.

## Privacy notice

On first run, a one-time privacy dialog is shown with a "Don't show again" option. This sets `ui.warning_accepted: true` in your config file. You can reset it by setting it back to `false`.