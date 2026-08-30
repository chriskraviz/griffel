# Local Rewriting With MLX

Griffel can run every text-rewriting feature on your own machine instead of OpenAI, using [MLX](https://github.com/ml-explore/mlx-swift) with a Qwen3 model. The model runs *inside* the app — there is no server to install, no port to configure, and nothing listening on localhost.

Local rewriting is tied to **Sicherer Lokaler Modus**. Turn it on and *all* LLM features run on-device: Griffel+, Auswahl bearbeiten, Braindump-Ordnen, and App-Profile formatting. Outside that mode, rewriting goes to OpenAI.

Earlier versions delegated this to a user-installed [Ollama](https://ollama.com) server, selected through a **KI-Anbieter** setting. Both are gone: the engine now follows Sicherer Lokaler Modus, so there is one switch instead of two. Older versions before that also had a separate "Griffel Lokal+" workflow on `fn + Ctrl + Option`, which became the **Bearbeitungsgrad** setting.

Scope: this is **post-processing only**. Transcription is a separate step — either the OpenAI Audio API (online mode) or WhisperKit/CoreML (local mode, see [local-models.md](local-models.md)).

**Apple Silicon only.** MLX computes through Metal against unified memory and has no x86_64 backend.

## Setup

1. Set the mode card on the main page to **Lokal** — that is Sicherer Lokaler Modus.
2. Under **Umschreiben**, pick a model (see the table below).
3. Click **Sprachmodell laden**. The weights download once from Hugging Face into:

   ```text
   ~/Library/Application Support/Griffel/models/mlx/
   ```

4. Wait for the progress to finish. The model is then loaded and stays warm for the first rewrite.

No model files ship in the app bundle — the download is yours, and you can delete the folder to reclaim the space.

## Available Models

| Model | Download | Notes |
|---|---|---|
| Qwen3 1.7B | ~1.0 GB | Fastest; fine for cleanup and punctuation, weaker on structured tasks |
| Qwen3 4B | ~2.3 GB | Default; the best balance of German phrasing and speed |
| Qwen3 8B | ~4.7 GB | Best quality; noticeably more RAM and a slower first token |

Smaller models are faster but follow instructions less reliably; larger models rewrite more fluently but take longer, especially on the first call after a cold start while the weights load into memory.

Qwen3 is a hybrid reasoning model. Griffel switches the thinking pass off in the chat template, so a rewrite returns the text and nothing else — a `<think>` block never reaches your clipboard.

## Customizing The Prompt

**Einstellungen → Anpassen → Griffel+ → Bearbeitungsgrad** picks how far a rewrite may go: *Korrektur* cleans the dictation up and leaves the wording alone, *Lektorat* rephrases and additionally honours Schreibstil and Kontext.

The wording of the instructions themselves lives under **Einstellungen → Anpassen → Prompts → Bearbeiten**. Four prompts are editable — Korrektur, Lektorat, Auswahl bearbeiten and Braindump ordnen — each prefilled with the text that actually runs, so you edit a real prompt rather than a blank box. **Zurücksetzen** hands one back to its default, and a prompt you never touched keeps following the built-in text when the app improves it.

The same page carries **Zusatz für das lokale Modell**: a line appended only when the on-device model does the work. It ships enabled with *"Lasse keine inhaltlichen Angaben weg und erfinde nichts dazu."* — small 4-bit models paraphrase and compress more freely than GPT-4o, which is wrong for Korrektur in particular. Its card has its own switch: turn it off and the local model gets no addendum at all. Emptying the text box is not an off switch — like the other prompts, an empty box means "use the default".

Glossary terms, Denglish handling, and the filler-word setting flow into the prompt automatically. If you had a custom prompt on the old Griffel Lokal+ or the Ollama integration, it is carried over into the matching Prompts entry once on first launch.

## Sicherer Lokaler Modus

With a WhisperKit model and a Qwen3 model installed, **every** workflow stays available and the whole pipeline is local:

```text
Microphone -> WhisperKit/CoreML (on device) -> Qwen3 via MLX (on device) -> Paste
```

OpenAI is never contacted in this mode. If no Qwen3 model is installed, the rewriting workflows pause (plain transcription and braindump capture keep working) and the app tells you to download one.

Expectation check: small local models rewrite less reliably than GPT-4o, especially for structured tasks like braindump organizing and selection editing. If output quality matters more than staying offline, pick a larger model from the table above, or leave Sicherer Lokaler Modus off and use OpenAI.

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| "Lokales Sprachmodell fehlt …" | No weights on disk — pick a model under **Umschreiben** on the main page and click **Sprachmodell laden** |
| Download fails partway | Usually a network drop; click **Installieren** again, the cache resumes from what is already there |
| First run very slow / seems hung | Cold load of several GB into memory; later calls in the same session are much faster |
| "Das lokale Sprachmodell hat keinen Text zurückgegeben." | The model returned empty output — try again or pick a larger model |
| Workflow failed mid-run | The raw transcript is placed on the clipboard so the dictation is not lost |
