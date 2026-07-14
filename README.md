# DexCleaner

DexCleaner is a conservative macOS SwiftUI disk-audit and exact-cache cleanup app.

It is not a broad cleaner. It grants cleanup authority only to exact, validated, regeneratable cache targets in the bundled manifest.

> Scan explicitly. Review visibly. Preview an immutable plan. Confirm exact paths. Revalidate. Move to Finder Trash.

## Current release posture

The core safety refactor is implemented on the `implement/adversarial-safety-refactor` branch.

Validated in the available Linux Swift environment:

- `swift test`: 22 tests, 0 failures
- `swift build`: pass
- Swift parser check for all macOS app source files: pass
- manifest JSON validation: pass
- shell syntax and source guards: included in `make bug-sweep`

Still required on actual macOS before release:

- compile and launch the SwiftUI executable target
- verify Finder Trash movement and restoration
- verify cancellation during real scans and Trash moves
- verify Full Disk Access messaging
- verify keyboard and VoiceOver navigation
- build, sign, verify, install, and launch the app bundle and DMG
- run the clean-account release checklist

No claim of release readiness exists until those checks pass.

## Safety architecture

DexCleaner enforces these invariants:

1. The bundled JSON manifest is the only cleanup-authority source.
2. Missing or invalid manifest data disables cleanup.
3. Manifest entries must be exact, non-overlapping, safe, regeneratable, and initially unselected.
4. Broad roots, user content, cloud storage, project trees, browser profiles, app state, and Git internals are audit-only or protected.
5. Selection alone never authorizes cleanup.
6. Preview creates an immutable cleanup plan bound to the selection, manifest version, manifest checksum, and filesystem identities.
7. Selection changes invalidate the plan.
8. Every target is revalidated immediately before movement.
9. Cleanup uses `FileManager.trashItem` on macOS only.
10. DexCleaner never empties Trash and never claims moved bytes are freed bytes.
11. Preview authority expires after fifteen minutes.
12. Cancellation propagates into detached scanner and cleanup workers, terminates active shell commands where possible, and returns the application to a usable state.
13. Mandatory privacy exclusions cannot be removed by user configuration.
14. Timeouts, permission limits, command failures, and cancellations appear as scan issues rather than silent zeroes.

## Workflow

### 1. Scan

The app opens idle. Scanning starts only when the user requests it.

A scan reports:

- disk availability
- exact manifest-authorized candidates
- audit-only storage findings
- protected presence markers
- access-check results
- explicit completeness and issue status
- fresh versus cached measurement timestamps

### 2. Review

The user may filter and search findings. Selected targets remain visible in a dedicated Selected tab. Changing the cleanup profile clears selection to prevent hidden authority.

### 3. Preview

Preview performs no mutation. It creates an immutable cleanup plan only when every selected target passes the safety engine and has a readable filesystem identity.

### 4. Confirm and move

The confirmation sheet lists every exact path and estimated byte count. Cleanup revalidates the plan and then moves authorized targets to Finder Trash.

## Removed from the first trustworthy release

The following features were deliberately removed:

- background scanning
- launch at login
- automatic launch-time scanning
- fake percentage progress
- direct cleanup without preview
- Git temporary-pack cleanup
- fallback cleanup manifest

Git temporary packs remain visible as audit-only findings.

## Reports and ledger

DexCleaner writes local Markdown or JSON reports with optional home-path redaction. Reports include:

- app version
- manifest version and checksum
- scan completeness
- access limitations
- scan issues
- cleanup plan identifier
- per-item results
- moved-to-Trash bytes
- an explicit warning that moved bytes are not necessarily freed bytes

Preview and cleanup operations are appended to:

```text
~/Library/Application Support/DexCleaner/operation-ledger.jsonl
```

No telemetry, analytics, cloud upload, or network dependency is implemented.

## Development

Run the full local sweep:

```bash
make bug-sweep
```

Core tests:

```bash
swift test
```

On macOS:

```bash
swift build --product DexCleaner
swift run DexCleaner
make app
make verify-app
make dmg
```

## Important files

```text
Package.swift
Sources/DexCleanerCore/Resources/CleanupManifest.json
Sources/DexCleanerCore/CleanupCatalog.swift
Sources/DexCleanerCore/SafetyEngine.swift
Sources/DexCleanerCore/CleanupRunner.swift
Sources/DexCleanerCore/DiskScanner.swift
Sources/DexCleanerCore/PreviewAuthorization.swift
Sources/DexCleanerCore/OperationLedger.swift
Sources/DexCleanerCore/ReportWriter.swift
Sources/DexCleaner/AppModel.swift
Sources/DexCleaner/ContentView.swift
Tests/DexCleanerTests/DexCleanerTests.swift
docs/SAFETY_POLICY.md
docs/MANIFEST_SCHEMA.md
docs/RELEASE_CHECKLIST.md
BUG_SWEEP_REPORT.md
CHANGELOG.md
```

## Residual boundary

DexCleaner revalidates filesystem identity immediately before calling Finder Trash, but the public path-based Trash API cannot provide a mathematical guarantee that no filesystem change occurs in the tiny interval between final validation and movement. Release review must treat that as a residual platform boundary, not pretend it does not exist.
