# Contributing

Thanks for taking a look at Griffel macOS Preview.

This repository is intentionally a preview. Contributions should make it easier to learn from, build, fork, or safely extend.

## Good First Contributions

- improve build instructions
- fix confusing UI text
- improve error messages
- add tests around parsing or quality filters
- document local model experiments
- simplify setup

## Before Opening A Pull Request

Please include:

- what changed
- why it changed
- how you tested it
- whether you used AI-assisted coding tools

Keep changes small when possible. Avoid unrelated cleanup in the same PR.

## Local Build

```bash
./build.sh --debug
```

To run what CI runs — the secret hygiene scan and the debug build — in one go:

```bash
./scripts/ci-local.sh
```

`--scan-only` skips the build and takes seconds; `--install-hook` puts that short version into a `pre-push` hook. The scan runs against a clean export of `HEAD`, so nothing untracked in your working tree can trip it.

## Security And Privacy

- Never commit API keys, tokens, private audio, or confidential transcripts.
- Avoid adding telemetry, hosted services, or external dependencies without a clear issue first.
- Call out privacy-impacting changes in the pull request description.
- Keep the preview honest: do not describe remote OpenAI workflows as offline or local, and do not claim local rewriting works before the user has downloaded an on-device model.

## Project Boundaries

This preview currently does not include:

- other platforms
- a hosted backend
- packaged releases
- bundled local model files (the MLX rewrite model and the WhisperKit model are downloaded by the user at runtime, never shipped in the bundle)

Those can be discussed in issues, but please keep PRs focused on the current macOS preview unless a maintainer agrees on a larger direction first.
