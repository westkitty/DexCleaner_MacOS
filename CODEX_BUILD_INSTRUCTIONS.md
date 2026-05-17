# Codex Build Instructions for DexCleaner

You are building and verifying DexCleaner, a conservative macOS SwiftUI disk-audit and safe-cache cleanup app.

## What this repository is

This repository root is the Swift Package root. `Package.swift`, `Sources/`, `Tests/`, `docs/`, and `scripts/` are all at the top level.

DexCleaner shows disk pressure and offers cleanup only for exact, manifest-approved, regeneratable cache targets. Cleanup uses Finder Trash only. Audit findings are visible for diagnosis but are not cleanup candidates.

## Non-negotiable safety rules

1. Do not broaden cleanup to `~/Library/Caches`, `~/Library/Application Support`, `~/.cache`, user folders, project folders, cloud folders, browser profiles, IDE state, Local Storage, Session Storage, IndexedDB, Service Worker, keychains, or unknown app state.
2. `SafetyEngine` must continue requiring exact manifest-approved Safe paths, plus only strictly validated abandoned Git `tmp_pack_*` files under `.git/objects/pack/`.
3. Cleanup must continue using `FileManager.trashItem` on macOS. Do not use `rm -rf` or permanent deletion in app code.
4. Dry-run preview must remain available before cleanup.
5. Cleanup candidates must start unselected.
6. AuditOnly, Caution, Forbidden, Protected, and Cloud findings must never be selectable for cleanup.
7. Symlinked cleanup targets must stay rejected.
8. Do not reintroduce `.skipsHiddenFiles` or hidden-directory-skipping enumeration into Git temp-pack scanning. It breaks `.git` pack detection.

## First command sequence

From the repository root:

```bash
make bug-sweep
```

That must pass before feature work.

## macOS validation sequence

Run this on macOS 13 or later:

```bash
swift test
swift build
swift run DexCleaner
make app
open .build/DexCleaner.app
make dmg
```

If any macOS-only SwiftUI build error appears, fix it without weakening `DexCleanerCore` safety rules.

## Files to inspect first

```text
CODEX_BUILD_INSTRUCTIONS.md
PROMPT_FOR_FRESH_CHAT.md
README.md
docs/SAFETY_POLICY.md
docs/IMPLEMENTATION_PLAN.md
docs/RESEARCH_LED_IMPROVEMENTS.md
docs/PRIVACY.md
docs/DISTRIBUTION.md
Sources/DexCleanerCore/Resources/CleanupManifest.json
Sources/DexCleanerCore/SafetyEngine.swift
Sources/DexCleanerCore/DiskScanner.swift
Sources/DexCleanerCore/CleanupRunner.swift
Sources/DexCleanerCore/ReportWriter.swift
Sources/DexCleaner/AppModel.swift
Sources/DexCleaner/ContentView.swift
Sources/DexCleaner/DexCleanerApp.swift
Tests/DexCleanerTests/SafetyEngineTests.swift
BUG_SWEEP_REPORT.md
```

## Expected current validation status

In the Linux sandbox, the core package validates with:

```bash
make bug-sweep
```

Expected result after the deep sweep:

- `swift test`: PASS
- `swift build`: PASS
- `swift package describe`: PASS
- manifest JSON validation: PASS
- shell syntax validation: PASS
- no `.skipsHiddenFiles` in `Sources/DexCleanerCore`
- no `FileManager.default.removeItem` in `Sources`
- 14 XCTest tests, 0 failures

Linux cannot validate the macOS SwiftUI executable target because `Package.swift` intentionally excludes it off macOS. Do not claim GUI success until the macOS validation sequence passes.

## Best next work

1. Run the macOS validation sequence.
2. Fix SwiftUI-only compiler/runtime issues, if any.
3. Add Finder Reveal buttons for audit-only findings.
4. Add a report destination picker.
5. Add configurable large-file thresholds.
6. Add app icon/asset catalog.
7. Add signing/notarization workflow.

## Forbidden next work

Do not add broad app uninstall, browser cleanup, cloud cleanup, `~/.cache` cleanup, or unknown Application Support cleanup. Those require a separate design and typed confirmation workflow.
