# DexCleaner

DexCleaner is a conservative macOS SwiftUI disk-audit and safe-cache cleanup app.

It is not a broad cleaner. It is not a “delete everything suspicious” toy. DexCleaner is built around one boring, valuable rule:

> Show the user what is using disk space, but only offer cleanup for exact, manifest-approved, regeneratable cache targets.

Cleanup uses Finder Trash only. Audit findings are visible for diagnosis but are not cleanup candidates.

## Current status

This repository is Codex-ready, but macOS validation is still required.

Validated in Linux sandbox:

- `swift test`: PASS
- `swift build`: PASS
- `swift package describe`: PASS
- manifest JSON validation: PASS
- shell syntax validation: PASS
- core hidden-file scanner guard: PASS
- permanent-deletion source guard: PASS
- 14 XCTest tests, 0 failures

Not validated in Linux sandbox:

- macOS SwiftUI executable target
- Finder Trash behavior
- `.app` bundle launch
- DMG generation

The Linux sandbox cannot compile or run SwiftUI/AppKit. This is not a failure. It is reality, standing there with a clipboard.

## First commands

From the repository root:

```bash
make bug-sweep
```

On macOS 13 or later, also run:

```bash
swift test
swift build
swift run DexCleaner
make app
open .build/DexCleaner.app
make dmg
```

## What DexCleaner does

DexCleaner provides:

- disk pressure overview
- exact manifest-backed safe cleanup candidates
- dry-run preview before cleanup
- app/tool grouped findings
- audit-only large folder/file findings
- protected-path reporting
- Full Disk Access diagnostics
- storage summaries and extension breakdowns
- local Markdown reports
- menu bar status/actions
- app bundle and DMG helper scripts

## Safety doctrine

DexCleaner must preserve these rules:

1. Cleanup is exact manifest allowlist only.
2. Broad roots such as `~/Library/Caches`, `~/Library/Application Support`, and `~/.cache` are not cleanable merely because they are cache-looking.
3. Unknown app state, browser profiles, IDE workspace state, cloud storage, project folders, and user content are protected or audit-only.
4. Cleanup candidates start unselected.
5. Cleanup uses `FileManager.trashItem` on macOS. No permanent deletion in app code.
6. Dry-run preview remains available before cleanup.
7. Symlinked cleanup targets are rejected.
8. Git temp-pack cleanup is limited to strict abandoned `tmp_pack_*` files directly under `.git/objects/pack/`.
9. Do not reintroduce `.skipsHiddenFiles` into Git temp-pack scanning.

## Important files

```text
CODEX_BUILD_INSTRUCTIONS.md
PROMPT_FOR_FRESH_CHAT.md
BUG_SWEEP_REPORT.md
Package.swift
Makefile
Sources/DexCleanerCore/Resources/CleanupManifest.json
Sources/DexCleanerCore/SafetyEngine.swift
Sources/DexCleanerCore/DiskScanner.swift
Sources/DexCleanerCore/CleanupRunner.swift
Sources/DexCleanerCore/ReportWriter.swift
Sources/DexCleaner/AppModel.swift
Sources/DexCleaner/ContentView.swift
Sources/DexCleaner/DexCleanerApp.swift
Tests/DexCleanerTests/SafetyEngineTests.swift
docs/SAFETY_POLICY.md
docs/IMPLEMENTATION_PLAN.md
docs/PRIVACY.md
docs/DISTRIBUTION.md
```

## Development

Run the full bug sweep:

```bash
make bug-sweep
```

Run only tests:

```bash
swift test
```

Build package:

```bash
swift build
```

Run app on macOS:

```bash
swift run DexCleaner
```

Build `.app` bundle on macOS:

```bash
make app
```

Build DMG on macOS:

```bash
make dmg
```

## Privacy

DexCleaner is local-only. It has no telemetry, no analytics, no cloud upload, and no network dependency by design.

Reports are local Markdown files.

## Forbidden next work

Do not add these without a separate safety design:

- broad app uninstall
- browser cleanup
- cloud cleanup
- `~/.cache` cleanup
- unknown `Application Support` cleanup
- permanent deletion
- privileged helper cleanup

DexCleaner’s value is restraint. Try not to improve it into a hazard. That would be very on-brand for software, but no.