# Roadmap

This is a preview roadmap, not a promise.

## Current Scope

- macOS menubar app
- local recording, hotkeys, and a floating hotkey HUD
- direct OpenAI API calls with a user-provided API key
- transcription and rewriting workflows (rewriting has a Korrektur/Lektorat Bearbeitungsgrad)
- braindump inbox (local capture, OpenAI-assisted processing on demand, or on-device in Sicherer Lokaler Modus)
- braindump capture context: the app — and optionally the window title — you were in, stored locally and never sent to a language model
- an app window holding the Ablage: topic folders as real folders on disk, an audio plus a `.md` sidecar per recording, tags and search
- drag-and-drop import of existing audio files, transcribed by the same engine a spoken run uses
- the settings in that window as well as in the popover, laid out for the wider frame
- voice-instructed selection editing
- local transcription with user-installed WhisperKit/CoreML models (secure local mode)
- live partial-transcript preview while recording (local WhisperKit only; cosmetic, the final text comes from the batch pass)
- optional silence auto-stop that ends a recording after a configurable pause
- local rewriting on-device via MLX with a Qwen3 model (active in Sicherer Lokaler Modus, applies to all rewriting features)
- glossary with definitions, Denglish mode, and filler-word removal
- per-app format profiles
- local-only usage statistics
- local-only frequent-phrase detection (counts feeding statistics, glossary suggestions, and result highlighting)
- microphone input device selection, with the device actually in use named while recording
- one-time data migration from Blitztext installations
- no hosted backend
- no other platforms
- no packaged public release

## UI Redesign Track

The menu bar popover and the Ablage window are being reworked toward focused,
navigable panels. One minor version per phase, each tagged and released
(source-only) so the increments stay visible:

- **v1.6.0** — the Ablage becomes a prominent card on the popover's main page.
- **v1.7.0** — design-system groundwork: a selected state for keycap buttons,
  named type/spacing tokens, workflow accent colors on the enum.
- **v1.8.0** — an icon tab rail in the popover (Start · Braindump · Statistik ·
  Einstellungen) replaces back-button navigation.
- **v1.9.0** — the window header gains real sections (Ablage · Statistik ·
  Einstellungen), bringing statistics into the window.
- **v1.10.0** — the settings split into real categories with a sidebar that
  actually navigates.
- **v1.11.0** — polish: keycap-styled toggles, deduplicated recording views,
  calmer library rows.

## Next Useful Work

- Make first-run setup clearer.
- Improve credential setup, validation, and recovery UX.
- Add a small automated test layer around prompt construction and text quality filters.
- ~~Add provider boundaries so OpenAI and future local models can be swapped more cleanly.~~ Done: `TextGenerationService` routes every LLM feature to OpenAI or the on-device MLX model.
- Reduce the Accessibility blast radius, ideally by moving synthetic paste into a smaller helper with narrower responsibilities.
- Make Hardened Runtime actually reach the artifact: `build.sh` re-signs after the Xcode build without `--options runtime`, so the flag is absent even when a fixed signing identity is used.
- Revisit the App Sandbox once the paste, hotkey and model-storage flows allow it.
- Add stronger supply-chain checks around downloaded local speech models.
- Add signed and notarized release builds when the project is ready for non-developer users.

## Not In Scope Yet

- Production support.
- Accounts, sync, teams, or hosted infrastructure.
- Claims that the app is offline or privacy-complete.
- App Store distribution.
- Bundled model files (both the WhisperKit and the MLX model are downloaded by the user at runtime).
