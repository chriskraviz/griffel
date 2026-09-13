# Product

<!-- impeccable:product-schema 1 -->

## Platform

macOS

## Users

Griffel is a daily productivity tool for macOS knowledge workers who want to turn spoken thoughts into usable text without breaking focus. Its primary users dictate in German or Denglish, work across multiple Mac apps, and value both fast keyboard-driven capture and control over where their audio and text are processed.

## Product Purpose

Griffel makes speech a practical input method throughout macOS. A user invokes a workflow from the keyboard, speaks, and gets a transcript, a refined draft, an edited selection, or a captured Braindump without having to move their work into a separate service.

The product should evolve from its current preview state into a polished end-user dictation product. Success means the core workflows feel dependable, immediate, understandable, and comfortable enough for everyday use rather than merely demonstrating how an AI workflow works.

## Positioning

Griffel combines system-wide dictation, writing refinement, voice-directed editing, and a local Braindump inbox in one native macOS tool. Users can choose fully local processing or direct OpenAI processing with their own key, while retaining transparent, file-based ownership of saved recordings and transcripts. Its German and Denglish workflows, explicit privacy model, and ability to act on text inside other apps are central differentiators.

## Operating Context

- Griffel primarily lives in the macOS menu bar and is invoked with global hotkeys while another app remains the user's active work context.
- The floating HUD and menu-bar popover report recording and processing state. Completed text is pasted back into the target app when Accessibility permission allows it and remains available on the clipboard otherwise.
- The main window contains the Ablage, Braindump inbox, statistics, and settings. Topic folders map to real folders on disk.
- Users may dictate live, import existing audio, refine rough speech, edit selected text by voice instruction, or collect thoughts for later processing and filing.
- Users choose between online processing through OpenAI and Sicherer Lokaler Modus using on-device WhisperKit and MLX models.

## Capabilities and Constraints

- Native SwiftUI menu-bar application for macOS 14 or newer on Apple Silicon.
- German user interface; current public documentation is English.
- Four core workflows: Griffel transcription, Griffel+ rewriting, Braindump capture and organization, and Auswahl bearbeiten.
- Local transcription uses WhisperKit/CoreML. Local rewriting uses MLX with downloadable Qwen3 models.
- Online operation uses a user-provided OpenAI API key and direct API calls. Griffel has no hosted backend.
- Microphone permission is required for recording. Accessibility permission enables automatic paste, selection editing, and optional window-title capture, but basic results remain recoverable without it.
- Imported originals are never moved or modified. Saved transcripts remain plain Markdown beside copied audio files, and topic folders remain ordinary filesystem folders.
- Current builds are locally signed development builds; public signing, notarization, and release distribution remain open product decisions.
- The current implementation describes itself as an experimental preview. Future product and interface work should deliberately close that gap rather than preserve roughness as part of the identity.

## Brand Commitments

- Product name: Griffel.
- Preserve the established German workflow names and terminology unless a later product decision explicitly changes them.
- The voice should be direct, calm, transparent, and specific about processing location, permissions, fallback behavior, and data handling.
- Privacy must be communicated as concrete behavior rather than as an unsupported promise.
- The existing app icon is at `GriffelMac/Resources/AppIcon.icns`, with source variants in `GriffelMac/Resources/Assets.xcassets/AppIcon.appiconset/`.

## Evidence on Hand

- The repository contains working SwiftUI implementations of the menu-bar popover, hotkey HUD, Ablage window, settings, Braindump, statistics, transcription, rewriting, selection editing, local models, and storage workflows.
- Current interface screenshots live in `docs/screenshots/`.
- Architecture and data-flow documentation live in `docs/architecture.md`, `docs/privacy.md`, and the README.
- The repository contains no confirmed testimonials, customer logos, usage benchmarks, paid plans, or production-service claims. Future work must not fabricate them.

## Product Principles

1. **Optimize for daily flow.** Starting, understanding, and completing a dictation should feel faster than reaching for a separate editor or service.
2. **Make privacy a visible choice.** Users should always understand whether processing is local or online and what, if anything, leaves the Mac.
3. **Keep users in control of their work.** Preserve clipboard fallbacks, plain files, original recordings, and reversible organization wherever possible.
4. **Handle failure honestly.** Missing permissions, unavailable devices, absent models, and processing errors should be explicit and recoverable rather than silent.
5. **Earn native trust.** Follow macOS interaction conventions, keyboard expectations, accessibility behavior, and system feedback while giving Griffel a distinctive product identity.

## Accessibility & Inclusion

The app must remain fully usable with keyboard-driven workflows and should respect macOS accessibility settings, including Reduce Motion. Controls, status changes, permission guidance, and processing-location choices must be understandable without relying on color alone. Core capture remains useful when Accessibility permission is unavailable by keeping results on the clipboard for manual paste.
