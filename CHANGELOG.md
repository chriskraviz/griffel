# Changelog

All notable changes to Griffel are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/). The version
lives in `GriffelMac/project.yml` (`MARKETING_VERSION`) and is shown in the
app under Einstellungen → Zugang → Installation & Updates. Releases are
source-only — no binary is attached; build from the tag with `./build.sh`.

## [Unreleased]

### Added

- `docs/architecture.md`: an illustrated architecture overview — the
  dictation pipeline end to end, the four-modes/three-classes workflow
  mapping, AppState as the switchboard, the on-disk layout, and the build
  chain. The figures are hand-drawn SVGs in `docs/diagrams/` that adapt to
  light and dark mode; the pipeline figure also opens the README's Data
  Flow section. Linked from the README and CONTRIBUTING.

## [1.5.1] - 2026-09-01

### Fixed

- The picked microphone is no longer silently overridden by the macOS default
  input device. The recorder now verifies after starting that the engine
  really opened the requested device, rebuilds the engine once when the pin
  did not take, re-applies the device after Core Audio configuration changes
  (e.g. Bluetooth devices connecting mid-recording), and labels an
  unavoidable fallback honestly as "· Standardgerät" instead of claiming the
  picked microphone.
- A dictation ended by the silence auto-stop can no longer be lost. While the
  transcript was still being produced, releasing the hold hotkey — or
  pressing it again for the next dictation — cancelled the in-flight
  transcription: nothing was pasted and nothing reached the clipboard. Both
  gestures now leave the transcription alone; a follow-up dictation lets the
  previous one finish on the side and paste its own result.

## [1.5.0] - 2026-08-30

Initial public release.

- Speech-to-text menu bar app for macOS 14+ on Apple Silicon: press a hotkey,
  speak, get the transcript pasted into the app you were using.
- Four workflows: Griffel (transcription), Griffel+ (transcription plus
  rewriting with Korrektur/Lektorat levels), Braindump (spoken notes into a
  local inbox), and Auswahl bearbeiten (voice-instructed selection editing).
- Online mode with a user-provided OpenAI API key, or Sicherer Lokaler Modus
  running WhisperKit (transcription) and a Qwen3 MLX model (rewriting)
  entirely on-device.
- Ablage window: topic folders as real folders on disk, plain-Markdown
  transcript sidecars, tags, search, drag-and-drop audio import, and the
  Braindump inbox side by side.
- Hotkey HUD with live waveform, optional live partial transcript, optional
  silence auto-stop, glossary with Denglish mode, filler-word removal,
  per-app format profiles, local-only statistics and frequent phrases.
