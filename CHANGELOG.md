# Changelog

All notable changes to Griffel are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/). The version
lives in `GriffelMac/project.yml` (`MARKETING_VERSION`) and is shown in the
app under Einstellungen → Zugang → Installation & Updates. Releases are
source-only — no binary is attached; build from the tag with `./build.sh`.

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
