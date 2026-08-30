# Security Policy

Griffel macOS Preview is experimental software.

It is provided as-is, without warranty, support guarantees, or production-readiness claims.

## Supported Versions

Only the current `main` branch is considered for security fixes.

## Reporting A Vulnerability

Please do not open a public issue with sensitive security details.

Use GitHub private vulnerability reporting for this repository. GitHub only offers it on public repositories, so maintainers enable it as soon as the repository becomes public.

If private vulnerability reporting is not available yet, open a minimal public issue titled `Security contact request` without technical details.

Do not include OpenAI API keys, access tokens, private recordings, or confidential transcripts in a report.

Include:

- what you found
- how to reproduce it
- what data or system access could be affected
- your suggested fix, if you have one

## Security Notes

- The app sends audio and text directly to OpenAI when you use the remote workflows.
- Your OpenAI API key is stored in the user's macOS Keychain.
- Temporary audio files may exist briefly during processing.
- Accessibility permission allows the app to paste text into the current app.
- The app currently runs **without** the macOS App Sandbox. This is a deliberate trade-off for the preview: the menubar workflow needs Accessibility-based paste into arbitrary frontmost apps, system-wide hotkeys, and Application Support paths for the local WhisperKit and MLX models, all of which are awkward or impossible inside a strict sandbox. The entitlements are exactly three: sandbox off, microphone input, outbound network access — see `GriffelMac/Resources/GriffelMac.entitlements`.
- **Hardened Runtime is configured but not present in the builds `build.sh` produces.** `project.yml` sets `ENABLE_HARDENED_RUNTIME`, but Xcode disables it when signing ad-hoc (which is the default), and `build.sh` re-signs afterwards without `--options runtime`, so a fixed signing identity does not restore it either. A build made here therefore carries an ordinary signature: verify with `codesign -dv Griffel.app` and look at `flags`. This is a preview-grade local build, not a hardened distribution artifact.
- Reworking these flows — hardened runtime in the signing step, and eventually the sandbox — is tracked in [ROADMAP.md](ROADMAP.md).

Do not use this preview for confidential or regulated data without your own review.
