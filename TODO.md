# TODO

## High Priority

- [ ] Improve installer error handling and validation.
- [ ] Add safer API-key configuration using `GEMINI_API_KEY` env var.
- [ ] Prefer per-user installation where practical.
- [ ] Make installation fully idempotent.
- [ ] Add tests for configuration parsing and validation.
- [ ] Add tests for sensitive-file detection.
- [ ] Improve context-menu registration and removal.
- [ ] Add proper version/release packaging.

## Security & Privacy

- [x] Directory names are now scanned for sensitive patterns (not just files).
- [x] Full path sent to API is redacted per-segment for sensitive folder names.
- [x] Expanded default sensitive patterns (tax, financial, medical, bank, insurance, passport, identity).
- [ ] Document API-key handling and precedence clearly.
- [ ] Improve secret-pattern detection and configuration validation.

## UX

- [x] Privacy warning is now first-run only with "Don't show again" checkbox.
- [ ] Add copy-to-clipboard button on the summary window.

## Future

- [ ] Optional video frame analysis.
- [ ] Additional language controls.
- [ ] Better UI.
- [ ] Single-file installer/package.
- [ ] GitHub release automation.

## Cleanup

- [x] Split README into focused docs (README, INSTALL, CONFIGURATION, SECURITY).
- [ ] Keep generated binaries out of the Git repository.
- [ ] Add automated checks for documentation/config consistency.
