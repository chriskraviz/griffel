# Privacy Notes

Griffel macOS Preview does not include a hosted backend.

When you use the online workflows, your Mac sends data directly to OpenAI:

- audio recordings for transcription
- audio files you drop into the app window, and filed recordings you re-transcribe later — sent as a copy under a neutral file name (`audio.<ext>`), so the original file name and path stay on your Mac
- transcribed or typed text for rewriting
- the captured text selection and your spoken instruction for **Auswahl bearbeiten**
- your collected braindump entries when you press **Ordnen**
- the transcript for an extra formatting pass when **App-Profile** matches the target app
- glossary terms, custom terms, and prompt context if you configured them

**Sicherer Lokaler Modus** decides where every text-rewriting feature runs (the rewriting workflows, **Auswahl bearbeiten**, braindump **Ordnen**, and app-profile formatting): OpenAI while the mode is off, an on-device Qwen3 model while it is on.

When **Sicherer Lokaler Modus** is enabled and a WhisperKit/CoreML model is installed, transcription runs on your Mac and does not send audio to OpenAI. In this mode the app never uses OpenAI for rewriting either: all rewriting features run on-device through MLX, and they are paused when no local language model is installed. Braindump *capture* always keeps working locally. The app bundles no model files — you download them once from the mode card on the main page.

You are responsible for your OpenAI account, API usage, costs, and data handling.

## Local Data

The app stores:

- your OpenAI API key in the user's macOS Keychain
- workflow settings, glossary entries, and app-profile rules in local app support storage
- braindump entries in `braindump.json` in local app support storage — they never leave your Mac until you explicitly process them with OpenAI
- usage statistics in `stats.json` in local app support storage — word counts, durations, and workflow types only, never transcript content; this file never leaves your Mac
- frequent-phrase counts in `phrases.json` in local app support storage — aggregated 2–4-word phrase counts derived from your dictations, never full transcripts; computed and stored only on your Mac, can be disabled and deleted in the app
- your selected local language model in local settings
- optional WhisperKit/CoreML model folders in local app support storage
- temporary audio files while a transcription is being processed; the app attempts to delete each recording when the workflow ends or is cancelled. A file you drop into the window is copied to a temporary path for the run and that copy is deleted afterwards — the original file is never modified or deleted.
- recordings and transcripts in the **Ablage** folder — by default `~/Library/Application Support/Griffel/Aufnahmen`, or wherever you point it in Einstellungen › Ablage. An imported file is copied there (your original is never moved or changed) and its transcript is written next to it as a plain `.md` file. Topic folders are real folders. Two things are worth being precise about:

  - Griffel does not sync, back up or upload this folder as such, and the `.md` transcripts in it are never uploaded. But **transcription reads a recording out of this folder** — when you import it, and again every time you press *Transkribieren* or *Nochmal* on a filed recording. Unless Sicherer Lokaler Modus is on, that recording is sent to OpenAI at that moment, exactly as described at the top of this page. A recording filed here is therefore one button press away from being uploaded again.
  - It is an ordinary folder on your disk, so if you point it at one another service syncs (iCloud Drive, Dropbox, a backup tool), that service will copy your recordings wherever it copies things. The default location is deliberately one that Desktop & Documents sync does not touch. Deleting a recording in the app moves both files to the Trash. Imports are excluded from `stats.json` and `phrases.json`, since an imported recording may not be your own voice.
- for a Braindump, optionally the app you were in and the title of its focused window (Einstellungen › Braindump-Kontext, three settings: *Aus*, *Nur App*, *App und Fenstertitel*, default *App und Fenstertitel*). Window titles are verbatim text out of other apps and routinely contain document names, email subjects, URLs and file names. This is stored only in `braindump.json` and in the transcript's `.md` file on your Mac, is never included in anything sent to OpenAI or to a local language model, and never enters `stats.json` or `phrases.json`. The window title is read through the Accessibility permission the app already uses for auto-paste; without that permission only the app name is recorded. Griffel deliberately does not use the Screen Recording permission for this.

Workflow output may also be placed on your clipboard so it can be pasted into another app. Auto-paste marks the clipboard entry as concealed for compatible clipboard managers, but the generated text intentionally remains on the clipboard as a fallback if automatic paste is blocked. Clipboard managers, macOS, or other apps may still observe clipboard contents while they are present.

**Auswahl bearbeiten** briefly uses the clipboard to read your selection (a synthetic Cmd+C). The previous clipboard contents are snapshotted and restored if the edit is cancelled or fails; only plain-text clipboard contents are preserved by that snapshot.

The in-app cleanup ("Lokale Daten bereinigen") never deletes an Ablage folder you chose yourself. The default Ablage folder inside Application Support is only deleted when you tick "Aufnahmen und Transkripte ebenfalls löschen"; otherwise it is kept and the app tells you where it stayed.

The app uses the system TLS trust store for OpenAI and Hugging Face requests. It does not currently pin certificates. A user-installed or managed root certificate can therefore affect HTTPS trust decisions on that Mac.

Settings such as custom prompts, glossary terms, and context are stored in local app support storage as plain JSON. Do not put secrets into those fields.

## Local Rewriting Data Flow

While secure local mode is active, rewriting runs inside the app through MLX on the GPU. The text is never written to a socket — there is no server, no port, and no loopback hop. The only network traffic the feature causes is the one-time model download from Hugging Face, before the first run.

## Migration From An Earlier Name

On first launch, Griffel moves a legacy `~/Library/Application Support/Blitztext` folder to `~/Library/Application Support/Griffel` and copies the API key to its new Keychain entry. Nothing is uploaded during migration; the legacy Keychain entry is only deleted by the in-app uninstaller.

## Offline Scope

Transcription (with an installed WhisperKit model, from the microphone or from a dropped file), braindump capture, statistics, and frequent-phrase detection can run fully local. Every rewriting, editing, formatting, and organizing feature can run locally too, on-device via MLX, while secure local mode is active; with the mode off those features send text to OpenAI. The app itself is not offline-complete: model downloads come from Hugging Face.

## Sensitive Content

Do not use this preview with confidential, regulated, or highly sensitive content unless you have reviewed the code, your OpenAI settings, and your legal/privacy requirements.
