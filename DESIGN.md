---
name: "Griffel"
description: "A native macOS proof desk for turning speech into owned, legible work."
colors:
  proof-blue: "#0061FC"
  recording-red: "#FE534F"
  marker-green: "#BECD90"
  paper: "#F5F2ED"
  sidebar-paper: "#F1F1EF"
  ledger-paper: "#EBE9E6"
  selection-paper: "#EEF3FB"
  ink: "#1B1A18"
  hairline-rule: "rgba(0, 0, 0, 0.105)"
typography:
  editorial-title:
    fontFamily: "New York, Georgia, serif"
    fontSize: "29pt"
    fontWeight: 600
  editorial-body:
    fontFamily: "New York, Georgia, serif"
    fontSize: "16pt"
    fontWeight: 400
  workspace-heading:
    fontFamily: "New York, Georgia, serif"
    fontSize: "20pt"
    fontWeight: 600
  utility:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif"
    fontSize: "11pt"
    fontWeight: 400
  eyebrow:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif"
    fontSize: "9.5pt"
    fontWeight: 600
    letterSpacing: "0.8pt"
  control:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif"
    fontSize: "12pt"
    fontWeight: 600
rounded:
  keycap: "6pt"
  surface-sm: "8pt"
  surface-md: "12pt"
  surface-lg: "16pt"
  voice-popup: "30pt"
  capsule: "999pt"
spacing:
  micro: "4pt"
  xs: "6pt"
  sm: "8pt"
  md: "12pt"
  lg: "16pt"
  xl: "22pt"
  page: "38pt"
components:
  button-primary:
    backgroundColor: "{colors.proof-blue}"
    textColor: "#FFFFFF"
    typography: "{typography.control}"
    rounded: "{rounded.keycap}"
    padding: "6pt 13pt"
  button-capture:
    backgroundColor: "{colors.recording-red}"
    textColor: "#FFFFFF"
    typography: "{typography.control}"
    rounded: "{rounded.keycap}"
    padding: "3pt 9pt"
  search-field:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.utility}"
    rounded: "{rounded.keycap}"
    padding: "5pt 8pt"
  navigation-active:
    backgroundColor: "{colors.selection-paper}"
    textColor: "{colors.ink}"
    typography: "{typography.utility}"
    rounded: "{rounded.keycap}"
    padding: "5pt 8pt"
  proof-slip:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.surface-md}"
    padding: "12pt"
  marker-chip:
    backgroundColor: "{colors.marker-green}"
    textColor: "{colors.ink}"
    typography: "{typography.eyebrow}"
    rounded: "{rounded.capsule}"
    padding: "4pt 8pt"
---

# Design System: Griffel

## Overview

**Creative North Star: "The Native Proof Desk"**

Griffel combines the trust and restraint of a native macOS utility with the legibility of an editorial proof desk. The system should feel like warm uncoated stock held inside precise Mac chrome: calm enough to remain open all day, but unmistakably built for turning spoken material into text that can be reviewed, owned, and filed.

The interface is dense without becoming dashboard-like. Continuous ruled surfaces, a chronological ledger, serif reading typography, and sparse proof marks replace decorative cards. Native controls, SF Symbols, keyboard behavior, menus, focus, and sheets remain recognizable so the editorial character never comes at the cost of platform trust.

The shipped finish review verdict is **SHIP WITH NOTES**. The remaining note is behavioral rather than visual: audio opens in the user's default macOS app instead of playing inline inside the proof sheet.

**Key Characteristics:**

- Warm paper fields with faint, non-directional tooth
- A compact system-sans utility layer paired with an editorial serif reading layer
- Planar ledger surfaces separated by hairline rules
- Sparse blue, red, and marker-green proof accents with explicit labels
- Visible local/online processing truth and file ownership
- Keyboard-first native behavior with accessible reduced-motion and reduced-transparency fallbacks

## Colors

The palette is predominantly warm neutral paper and graphite ink; saturated color is reserved for proof-state meaning.

### Primary

- **Proof Blue:** Marks the current route or ledger selection, focus, primary non-recording actions, chart data, and the single rule connecting an entry to its open proof sheet.

### Secondary

- **Recording Red:** Names capture, stop, recording, and destructive or corrective urgency. It is not a general brand fill.

### Tertiary

- **Marker Green:** Highlights tags and Braindump filing moments. Its rarity gives it the character of a physical highlighter mark.

### Neutral

- **Warm Uncoated Paper:** The main reading field and opaque accessibility fallback.
- **Sidebar Paper:** A subtly cooler navigation field that separates hierarchy without elevation.
- **Ledger Paper:** The denser chronological working surface.
- **Selection Paper:** The quiet blue-tinted field under the active route or record.
- **Graphite Ink:** Primary copy and editorial rules, softened through opacity for secondary hierarchy.
- **Hairline Rule:** Separates columns, rows, ribbons, and action bars without creating boxes.

### Named Rules

**The Proof-Mark Rule.** Saturated color must communicate a real state, selection, workflow, or action; it never becomes decorative acreage.

**The Processing-Truth Rule.** Local and online processing are always named in text and reinforced with an icon; color alone never carries the privacy promise.

## Typography

**Display Font:** New York through SwiftUI's system serif design, with Georgia as the portable fallback
**Body Font:** New York through SwiftUI's system serif design, with Georgia as the portable fallback
**Utility Font:** SF Pro through the macOS system font, with platform-system fallbacks

**Character:** Serif type makes transcripts, excerpts, totals, and proof-sheet headings feel edited and worth reading. System sans keeps controls, dates, filters, status, provenance, and navigation compact and native.

### Hierarchy

- **Editorial Title:** The proof sheet's document title and decisive empty-state message.
- **Workspace Heading:** Ledger, Stats, and section headings below a small eyebrow.
- **Editorial Body:** Long transcripts and Braindump text, typically with six points of added line spacing and text selection enabled.
- **Utility:** Controls, metadata, search, status, and supporting explanations.
- **Eyebrow:** Uppercase section labels, workflow kinds, dates, and margin-note headings with restrained tracking.

### Named Rules

**The Reading/Operating Rule.** Use serif type for the material being considered and system sans for the interface used to act on it.

**The Quiet-Metadata Rule.** Metadata stays small, short, and secondary; when provenance is important, increase specificity before increasing visual weight.

## Layout

The main window is a fixed native workbench rather than a responsive web canvas. Its default size is 1220 × 760 points and its supported minimum is 1000 × 600 points. A 42-point shell header and a 40-point capture ribbon span the full width. Below them, a 206-point workspace sidebar leads into a 390-point ledger and a flexible proof sheet; the proof-sheet reading column caps at 720 points with 38-point page gutters.

The hierarchy is stable: Heute, Ablage, Braindump, and Statistik are top-level workspaces; real filesystem topic folders remain visible beneath them. **Heute** is a daily filter, not a separate store. It merges today's saved recordings with today's unprocessed Braindump entries, searches both kinds by text and capture context, and orders them newest-first. Tag filters apply to filed recordings because loose Braindump entries do not carry tags; every active filter remains visible with a result count and direct reset. Ablage applies folder, tag, and transcript-search filters without changing the underlying file model.

The selected ledger row and its detail are one interaction: a pale selection field and blue edge rule lead directly into the open transcript. The proof sheet keeps title, provenance, transcript, margin notes, tags, and ownership actions in one vertical reading flow. It does not grow a permanent inspector column.

The menu-bar popover is 340 points wide and concentrates processing readiness, microphone/model choice, permission guidance, and runnable workflows. The background hotkey HUD is 320 points wide and reports the current named phase, input device, live level, and clipboard-safe completion state. Window settings use a 200-point section rail and a readable control column capped at 620 points.

Settings use one recovery action per unresolved state. The popover header is navigation only; permission repair lives once in the access content. Access settings read in task order: direct insertion, optional OpenAI access, app installation with login-start, then removal. Customize settings group local models, storage, Braindump context, shortcuts, Griffel+, app profiles, and vocabulary as distinct operating areas. In both tabs, stronger uppercase section labels and full-width hairline rules separate task groups while preserving generous breathing room on both sides. Paths, build numbers, and manual-update details stay behind disclosure so operational choices remain scannable at 340 points.

Keyboard focus, native context menus, drag-and-drop, Escape cancellation, and descriptive help remain part of the layout contract. Main surfaces deliberately ship in a consistent light appearance. Reduce Motion removes travel, bounce, and continuous ornamental motion; Reduce Transparency replaces translucent material with opaque paper.

## Elevation & Depth

Griffel is flat by default. Depth comes primarily from tonal paper changes and hairline rules, not stacked shadows. Proof slips receive only a nearly invisible structural lift, keycaps get a tiny tactile shadow that collapses on press, and the floating HUD is the one surface allowed a stronger ambient shadow because it must separate from arbitrary desktop content. The uncoated-paper raster is a seamless generated material tile applied at low opacity; both shipped scales embed the originating Impeccable prompt directly in PNG metadata.

### Shadow Vocabulary

- **Keycap Lift:** A tiny resting shadow beneath interactive keycaps; it disappears when pressed.
- **Proof-Slip Lift:** A low-opacity one-point lift used on bounded secondary surfaces.
- **HUD Float:** A soft four-point offset shadow around the borderless capture popup; its thin material becomes opaque paper when Reduce Transparency is enabled.

### Named Rules

**The Planar-First Rule.** Use paper tone and rules to establish hierarchy; elevation is reserved for controls, small proof slips, and surfaces that physically float outside the window.

## Shapes

The dominant geometry is rectilinear and editorial: full-width ribbons, vertical column rules, ruled ledger rows, and open paper. Small continuous corners belong to controls and bounded utility slips. Keycaps and active navigation rows use the tightest radius; proof slips step through small, medium, and large radii only when containment is necessary. Metadata chips are capsules.

The hotkey HUD is the deliberate exception: a compact speech-popup silhouette with a maximum 30-point body radius and an integrated 26-point-wide, 9-point-deep tail. Its single continuous outline prevents a seam or doubled material where the tail meets the body.

**The Containment Rule.** Round a surface only when it needs to read as a discrete control, chip, or floating object; do not turn ledger sections into a wall of cards.

## Components

### Buttons

- **Shape:** Compact, continuous keycaps with one-line labels; regular controls use 13-point horizontal and 6-point vertical padding, while compact controls use 9 and 3 points.
- **Primary:** One commit action per local decision. Proof blue is the default action tint; capture uses recording red, while a Braindump filing action may use marker green.
- **Contrast:** Foreground is part of the semantic button token. Proof blue uses white; bright recording red and marker green use graphite ink rather than assuming every primary fill can support white text.
- **Hover / Focus:** Hover slightly softens the tint or adds neutral keycap chrome. Press removes the shadow, deepens the fill, and sinks by one point unless Reduce Motion is active. Native keyboard focus remains visible.
- **Secondary / Quiet:** Secondary actions use neutral or lightly tinted keycaps. Quiet navigation and dismissals have no resting chrome and reveal it on hover.
- **Settings Actions:** The leading recovery action uses its semantic tint and an SF Symbol. Refresh, paste, and Finder actions use compact neutral keycaps rather than visually ambiguous text links; cleanup remains explicitly red.

### Chips

- **Style:** Metadata sits in flat capsules with a faint neutral fill and hairline border. Tags in the proof sheet may use a restrained marker-green highlight.
- **State:** Chips are typographic and compact. A button inside a chip changes opacity on hover/press rather than adding another nested surface.

### Cards / Containers

- **Corner Style:** Legacy `glassCard` call sites now render as planar proof slips rather than glass dashboard cards.
- **Background:** A translucent white wash over warm paper, with an opaque paper fallback for Reduce Transparency.
- **Shadow Strategy:** Use only the proof-slip lift defined above.
- **Border:** A sub-point hairline, optionally tinted for warnings.
- **Internal Padding:** Most proof slips use 10–12 points.

### Inputs / Fields

- **Style:** Search and compact text fields use a six-point continuous corner, restrained material or opaque fallback, small system text, and a leading SF Symbol when helpful.
- **Focus:** The hairline becomes a stronger proof-blue stroke. Search clear controls appear only when there is content to clear.
- **Error / Disabled:** State remains explicit in nearby copy; unavailable actions are removed when they cannot be meaningfully used or rendered with native disabled semantics when context must remain visible.

### Navigation

Workspace routes are exclusive, full-row targets with system icons, semibold active labels, a selection-paper field, and a two-point proof-blue leading rule. Folder scopes sit beneath the routes, use middle truncation for long names, show monospaced counts, and remain valid drag-and-drop destinations. Creating, renaming, and deleting areas uses native fields, context menus, and confirmation dialogs.

### Capture Ribbon

The ribbon is persistent when idle and transforms in place for live workflow state. It pairs a red status dot with an uppercase readiness label, the actual shortcut instruction, and one capture action. That single action follows the active workspace: on Braindump it records a thought and uses the Braindump shortcut; elsewhere it starts normal transcription. The Braindump content view therefore shows its own capture header only in the compact menu-bar popover, never beneath the main-window ribbon. During a run the ribbon names the workflow and phase, shows level or progress, and exposes Stop; status is never encoded by animation or color alone.

### Today's Ledger

Rows combine time, a two-point source mark, source icon and label, title, excerpt, audio presence, and any queued, active, or failed transcription state. Hairline rules maintain chronology. The selected row gains a pale blue field and a blue trailing edge; the detail pane opens the same record rather than navigating to a new visual world. Storage and import failures stay above the ledger until dismissed or resolved, and failed jobs expose retry and removal without impersonating ongoing progress.

### Proof Sheet

The transcript surface uses a masthead, editorial title, concrete capture/filing/engine metadata, a strong ink rule, selectable body text, and a narrow blue-ruled margin note. The footer keeps Copy, audio, Ablegen, Finder, and Trash close to the owned file. **Current implementation note:** the audio action explicitly says that it opens the native default player; embedded inline playback remains future work.

### Braindump and Statistics

Braindump uses the same paper workbench for quick capture, local organization, selection, and loss-safe filing. Filing removes processed inbox entries only after the Markdown note succeeds; Copy never empties the inbox. Statistics reuse serif numerals, blue chart marks, and rules instead of boxed KPI cards, and explicitly state that counts stay local.

## Do's and Don'ts

### Do:

- **Do** preserve native macOS controls, keyboard focus, menus, sheets, drag-and-drop, and SF Symbol semantics.
- **Do** make Lokal/Online, active microphone, workflow phase, permission state, clipboard fallback, and file ownership legible in words.
- **Do** use the serif layer for transcripts and other content under review, and the system-sans layer for operating the app.
- **Do** keep Today a chronological view over real stored items and Braindump entries, not a duplicate database.
- **Do** treat empty, loading, success, permission, missing-model, missing-file, paste-blocked, and error conditions as named, recoverable states.
- **Do** retain the paper texture as a low-contrast material with embedded generation provenance.

### Don't:

- **Don't** rebuild the interface as a colorful card dashboard or a permanent three-inspector workspace.
- **Don't** use proof blue, recording red, or marker green as decoration without state meaning.
- **Don't** imply cloud privacy, hosted storage, or automatic paste when the current mode or permission state cannot guarantee it.
- **Don't** hide destructive filing or deletion outcomes; keep ordinary files recoverable and explain what moves or remains.
- **Don't** animate through Reduce Motion or depend on translucency when Reduce Transparency is enabled.
- **Don't** present audio as embedded playback until the proof sheet actually owns that behavior.
