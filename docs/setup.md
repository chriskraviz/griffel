# Setup

This guide is for people who want to build and inspect the preview themselves.

## 1. Requirements

- macOS 14 or newer on **Apple Silicon** — the app is arm64-only (MLX has no Intel backend, and the build fails without arm64)
- Full **Xcode 26 or newer**, selected via `xcode-select` — the Command Line Tools alone are not enough
- The **Metal toolchain** component, which MLX needs to compile its shaders; Xcode 26 no longer ships it:
  ```bash
  xcodebuild -downloadComponent MetalToolchain
  ```
- XcodeGen
- Homebrew, if you want to install XcodeGen with `brew install xcodegen`
- Optional for online workflows: an OpenAI API key
- Optional for secure local transcription: a local WhisperKit/CoreML model
- Optional for local rewriting: a Qwen3 MLX model, downloaded from the settings

Install XcodeGen manually if needed:

```bash
brew install xcodegen
```

## 2. Clone And Build

```bash
git clone https://github.com/chriskraviz/griffel.git
cd griffel
./build.sh --debug
```

To launch after building:

```bash
./build.sh --run
```

The app it builds is `Griffel.app`.

If the build stops with `cannot execute tool 'metal'`, the Metal toolchain is missing — MLX compiles its own shaders and Xcode 26 no longer ships the toolchain:

```bash
xcodebuild -downloadComponent MetalToolchain
```

If permissions misbehave after a rebuild — the app is listed under Accessibility but auto-paste still does nothing, or several stale "Griffel" entries have piled up — reset them with `./scripts/reset-app.sh`. See "A stable signing identity" in the README for why ad-hoc signed builds cause this.

## 3. Configure OpenAI For Online Workflows

Open the app settings and paste your own OpenAI API key if you want online transcription or rewriting workflows.

The preview currently uses:

- `whisper-1` for transcription
- `gpt-4o-mini` for lightweight rewriting and app-profile formatting
- `gpt-4o` for selection editing and braindump processing

You are responsible for API access, billing, and data handling in your own OpenAI account.

Never commit your API key into this repository, issues, logs, or screenshots.

You can skip this step if you only want to test local transcription with a local WhisperKit model.

## 4. Optional Local Transcription

To use secure local transcription, choose a compatible WhisperKit CoreML model in the app and click **Installieren**. Griffel stores models in:

```text
~/Library/Application Support/Griffel/models/whisperkit/
```

Recommended first model: `openai_whisper-small_216MB`.

See [local-models.md](local-models.md) for the exact command, model links, and expected folder layout.

## 5. Where The Settings Are

Two doors, the same settings behind both: the gear in the menu bar popover, and the app window — **⌘,** opens the window straight into them, and its header button switches between the Ablage and the settings. The window version has room for a sidebar and a wider column, so it is the more comfortable one for anything longer than a single toggle. Paths written as *Einstellungen → Anpassen → …* in this guide work in either.

The modes are not in the window. All of them but Braindump finish by pasting into whatever app you were in, and with the Griffel window in front, that app is Griffel — so they stay on the menu bar icon, where there is a real target behind them.

## 6. macOS Permissions

The app needs Microphone permission to record audio.

For automatic paste into the previous app, grant Accessibility permission in macOS System Settings. Without it, you can still copy and paste manually. **Auswahl bearbeiten** (voice-instructed selection editing) requires the Accessibility permission and will not start without it.

Griffel does not need Full Disk Access. Auto-paste uses the Accessibility permission because the app simulates Cmd+V after putting the result on the clipboard.

## 7. Upgrading From An Earlier Build

If you previously ran Blitztext on the same Mac, the first Griffel launch migrates your settings, models, and API key automatically. Because the bundle identifier changed:

- macOS asks again for **Mikrofon** and **Bedienungshilfen** (Accessibility).
- **Beim Anmelden starten** is off and needs to be re-enabled once in the settings.
- Stale "Blitztext" entries under Privacy & Security can be removed.

## 8. Optional Local Rewriting

Enable **Sicherer Lokaler Modus** and every rewriting feature runs on your own Mac instead of OpenAI, using a Qwen3 model through MLX. The model runs inside the app — there is no server to install.

1. In Griffel: set the mode card on the main page to **Lokal** — that *is* Sicherer Lokaler Modus.
2. Under **Umschreiben**, pick a model (Qwen3 4B is the default).
3. Click **Sprachmodell laden** on the card and wait for the download to finish.

Requires Apple Silicon — MLX has no Intel backend.

Troubleshooting:

- "Lokales Sprachmodell fehlt" means no weights are on disk yet — pick a model under **Umschreiben** on the main page and click **Sprachmodell laden**.
- The first rewrite after launching can be slow while several GB load into memory. Later calls are much faster.
- A failed download can simply be retried; the cache resumes from what is already there.

Model recommendations and details are in [local-rewriting.md](local-rewriting.md).

## Troubleshooting

- If `xcodebuild` reports that the active developer directory is only Command Line Tools, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- If the build cannot find XcodeGen, install it explicitly with `brew install xcodegen`.
- If online transcription fails immediately, check whether the API key is present and valid.
- If secure local mode is disabled, check whether a WhisperKit model is installed in the expected folder.
- If transcription works but paste does not, this is not an OpenAI billing issue. Check **Privacy & Security -> Accessibility**, restart Griffel after changing the permission, and make sure the cursor is focused in a text field before starting the workflow.
- If macOS shows multiple entries under Accessibility (including old Blitztext ones), remove or disable stale entries, run the app from the final location (`/Applications` if you used `./build.sh --install`), then grant the permission again.
- If the target app blocks synthetic paste or the target app was not detected, the result still stays on the clipboard so you can press Cmd+V manually.
- If **Auswahl bearbeiten** reports "Keine Auswahl gefunden", make sure text is actually selected in the frontmost app before holding the hotkey; password fields and some secure inputs cannot be read.
- If a specific microphone is selected under **Mikrofon** on the main page but has been unplugged, recording falls back to the system default. You do not have to guess whether that happened: while recording, the HUD and the popover name the device actually in use and append `· Standardgerät` when a pick was overridden.
- If audio is missing, check Microphone permission and macOS input settings.
- If you see OpenAI errors, verify model access and account billing.
