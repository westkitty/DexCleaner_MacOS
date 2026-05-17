# DexCleaner Bug Sweep Report

Date: 2026-05-17

## Scope

This pass re-opened the latest Codex-ready DexCleaner package, ran the bug sweep locally in the Linux sandbox, adjusted repository-root instructions, and pushed the project to `westkitty/DexCleaner_MacOS` through the GitHub connector.

## Local validation performed before push

From the local extracted project root:

```bash
make clean
make bug-sweep
```

The `bug-sweep` target ran:

```bash
swift test
swift build
swift package describe >/dev/null
python3 -m json.tool Sources/DexCleanerCore/Resources/CleanupManifest.json >/dev/null
bash -n scripts/*.sh
! grep -RIn "\.skipsHiddenFiles" Sources/DexCleanerCore
! grep -RIn "FileManager.default.removeItem" Sources
```

## Local result

- `swift test`: PASS
- `swift build`: PASS
- `swift package describe`: PASS
- manifest JSON validation: PASS
- shell script syntax validation: PASS
- hidden-file scanner guard: PASS
- permanent deletion guard: PASS
- 14 XCTest tests, 0 failures

## Important bug preserved by tests

A prior deep sweep found that Git temporary-pack scanning can miss `.git` directories if hidden directory enumeration is used. `DiskScanner.gitTemporaryPackItems` must use `/usr/bin/find` or another method that does not skip hidden `.git` directories.

Regression test:

```text
testGitTemporaryPackScannerFindsHiddenGitDirectoryPackFiles
```

## Repository push caveat

The available GitHub connector exposes direct file writes, not a normal local `git stage && git commit && git push` flow. The repository was therefore populated through multiple connector commits instead of a single staged commit.

The local package used for validation remains the source of truth for the bug sweep. Codex should run the validation sequence again after cloning.

## Required next macOS validation

Linux cannot validate the macOS SwiftUI executable target. On macOS, run:

```bash
swift test
swift build
swift run DexCleaner
make app
open .build/DexCleaner.app
make dmg
```

Do not claim GUI success until this passes on macOS.

## Safety invariants

- Exact manifest allowlist only.
- Finder Trash only.
- Cleanup candidates start unselected.
- Dry-run preview remains available.
- Audit-only, Caution, Forbidden, Protected, cloud, browser, IDE state, keychain, user content, and project folders must never become selectable cleanup candidates.
- Do not add `rm -rf` or `FileManager.default.removeItem` to app source.
