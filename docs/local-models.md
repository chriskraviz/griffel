# Local Models

Griffel can run transcription locally with WhisperKit/CoreML. The app does not bundle a speech model, but it can download the selected compatible model from Hugging Face into the local cache.

## Recommended First Model

Use Whisper Small for the first local test. It is multilingual, supports German, and is much lighter than the large variants.

- [argmaxinc/whisperkit-coreml: openai_whisper-small_216MB](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small_216MB)

Local cache path:

```text
~/Library/Application Support/Griffel/models/whisperkit/openai_whisper-small_216MB
```

## Other Compatible Models

You can also install larger WhisperKit CoreML models into the same cache directory:

- [openai_whisper-large-v3-v20240930_626MB](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_626MB)
- [openai_whisper-large-v3-v20240930_turbo_632MB](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_turbo_632MB)

The app detects installed model folders that contain `AudioEncoder.mlmodelc`, `MelSpectrogram.mlmodelc`, and `TextDecoder.mlmodelc`.

## Install From The App

Open Griffel and switch the mode card on the main page to **Lokal**. If the selected model is missing, Griffel starts the download right away and installs it into the local cache. To pick a different one, choose it under **Aufnahme** and click **Installieren** on the card. Einstellungen → Anpassen → **Lokale Modelle** is a read-only inventory of what is already there.

After the model is installed, the Griffel transcription workflow can run in local mode. Rewriting needs an LLM, so in secure local mode it runs on-device through MLX — download a language model too (see [local-rewriting.md](local-rewriting.md)) or the rewriting workflows stay unavailable while the mode is active.

## Optional Manual Install

If you prefer the CLI path, install the Hugging Face CLI so the `hf` command is available:

```bash
python3 -m pip install --upgrade "huggingface_hub[cli]"
```

Create the local model cache:

```bash
mkdir -p "$HOME/Library/Application Support/Griffel/models/whisperkit"
```

Download the recommended first model:

```bash
hf download argmaxinc/whisperkit-coreml \
  --include 'openai_whisper-small_216MB/*' \
  --local-dir "$HOME/Library/Application Support/Griffel/models/whisperkit" \
  --max-workers 4
```

Expected folder layout:

```text
~/Library/Application Support/Griffel/models/whisperkit/
  openai_whisper-small_216MB/
    AudioEncoder.mlmodelc/
    MelSpectrogram.mlmodelc/
    TextDecoder.mlmodelc/
```

If the folder is nested differently, the app will not detect the model.

## Notes

- First use can be slower because the model has to load and prewarm.
- Local transcription avoids sending audio to OpenAI for the Griffel workflow.
- The app supports local transcription via WhisperKit and local rewriting on-device via MLX (see [local-rewriting.md](local-rewriting.md)); outside secure local mode the rewriting workflows remain remote.
- Models are downloaded on demand so the repository and app package stay small and auditable.
