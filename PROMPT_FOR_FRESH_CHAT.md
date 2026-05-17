# Fresh-chat implementation prompt for DexCleaner

You are continuing DexCleaner, a conservative macOS disk-audit and safe-cache cleanup app written in SwiftUI + Swift Package Manager.

## Project purpose

DexCleaner helps a user understand real allocated disk usage and safely reclaim space from exact, regeneratable cache targets without destroying app state, session data, workspace data, cloud files, browser profiles, IDE profiles, or user content.

## Repository layout

This repository root is the Swift Package root:

```text
Package.swift
Sources/
Tests/
docs/
scripts/
Makefile
README.md
CODEX_BUILD_INSTRUCTIONS.md
PROMPT_FOR_FRESH_CHAT.md
BUG_SWEEP_REPORT.md
```

## Current strategic lane

DexCleaner should not become a broad cleaner clone. Keep it narrow:

- preview-first
- developer-aware
- local-only
- manifest-governed
- exact allowlist
- Finder Trash only
- audit-visible but deletion-stubborn

## Non-negotiable safety doctrine

Before adding features, preserve these rules:

1. `SafetyEngine` must use an exact canonical allowlist only.
2. Do not allow cleanup merely because a path is under `~/Library/Caches/` or `~/Library/Application Support/`.
3. Unknown Application Support app folders are audit-only or protected, never cleanable.
4. Cleanup candidates must start unselected.
5. Cleanup uses `FileManager.trashItem`, never `rm -rf`.
6. Audit-only, Caution, Forbidden, Protected, and cloud findings must never become cleanable without a separate safety review.
7. Symlinked cleanup targets must be rejected.
8. Git temp-pack cleanup is allowed only for regular files named `tmp_pack_*` directly under `.git/objects/pack/`, older than 10 minutes, with no Git process and no pack lock file.
9. The bundled manifest is the primary cleanup source of truth.
10. Unit tests must pass before feature work.

## First commands

```bash
make bug-sweep
```

On macOS, also run:

```bash
swift run DexCleaner
make app
make dmg
```

If you are not on macOS, `SwiftUI` may not be available. In that case, do not claim GUI build success. Validate core/package only.

## Files to inspect first

```text
CODEX_BUILD_INSTRUCTIONS.md
README.md
docs/SAFETY_POLICY.md
docs/IMPLEMENTATION_PLAN.md
docs/RESEARCH_LED_IMPROVEMENTS.md
docs/PRIVACY.md
Sources/DexCleanerCore/Resources/CleanupManifest.json
Sources/DexCleanerCore/SafetyEngine.swift
Sources/DexCleanerCore/CleanupRunner.swift
Sources/DexCleanerCore/DiskScanner.swift
Sources/DexCleaner/ContentView.swift
Tests/DexCleanerTests/SafetyEngineTests.swift
```

## Critical recent bug fix to preserve

A deep bug sweep found that Git temporary pack scanning must not rely on `FileManager.enumerator` to descend into hidden `.git` folders. The scanner now uses `/usr/bin/find` for `*/.git/objects/pack/tmp_pack_*` and has a regression test named `testGitTemporaryPackScannerFindsHiddenGitDirectoryPackFiles`. Do not reintroduce `.skipsHiddenFiles` or a hidden-directory-skipping enumerator in Git temp-pack scanning.

## Good next tasks

1. Verify the SwiftUI target on macOS with `swift run DexCleaner`.
2. Fix any compiler errors caused by Linux-invisible SwiftUI/macOS details.
3. Add a Finder reveal button for audit findings.
4. Add a user-chosen report destination picker.
5. Add configurable large-file thresholds.
6. Add a proper app icon and asset catalog.
7. Add hardened runtime and notarization workflow.
8. Consider typed confirmation for any future uninstall mode.

## Do not do yet

Do not add app uninstall mode, browser-profile cleanup, `~/Library/Application Support/<app>` cleanup, `~/.cache` cleanup, or cloud-file cleanup. Those are separate destructive workflows and require typed confirmation plus visible path review.
