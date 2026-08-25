# DexCleaner

DexCleaner is a conservative macOS SwiftUI disk-audit and evidence-driven cleanup app.

It is not a broad cleaner. It grants cleanup authority only to exact, validated, regeneratable targets proven by the bundled manifest or a dedicated candidate-class adapter. Generic findings remain review-only.

> Scan explicitly. Review visibly. Preview an immutable plan. Confirm exact paths. Revalidate. Move to Finder Trash.

## Current release posture

The evidence-driven cleanup campaign is complete on `codex/evidence-cleanup-campaign-20260825`. It adds typed evidence and provenance, whole-plan preflight, bounded project discovery, narrowly proven Node and Rust cleanup, versioned action receipts, truthful reclaim accounting, protected storage adapters, and a guided campaign interface while preserving the original exact-manifest workflow.

CI run [32830483705](https://github.com/westkitty/DexCleaner_MacOS/actions/runs/32830483705) is green for code commit `0eeb4c35a282577ab2d8671aaef21340e7ad3752`:

- Linux `make bug-sweep` and release-mode tests passed.
- macOS executable build and 133-test suite passed with 3 intentionally gated skips.
- Both production UI render certifications passed on macOS.
- App-bundle property list, embedded resources, and strict code-sign verification passed.

`make ui-contract` now verifies both exact UI/UX ledgers: the original `UIX-01` through `UIX-25` set and the second-pass `UIX2-01` through `UIX2-25` set, plus key source contracts.

Still required on actual interactive macOS hardware before public release:

- launch and exercise the SwiftUI app at narrow and wide window sizes
- verify Finder Trash movement and restoration
- verify cancellation during real scans and Trash moves
- verify Full Disk Access messaging
- verify keyboard, enlarged-text, reduced-motion, and VoiceOver behavior
- build, sign, verify, install, and launch the app bundle and DMG
- run the clean-account release checklist

No claim of public release readiness exists until those checks pass.

## Safety architecture

DexCleaner enforces these invariants:

1. Cleanup authority comes only from the validated bundled manifest or an explicit dedicated adapter with typed proof for its candidate class.
2. Missing, invalid, incomplete, stale, or contradictory authority evidence blocks cleanup.
3. Manifest and adapter candidates must be exact, safe, regeneratable, and initially unselected.
4. Broad roots, user content, cloud storage, project trees, browser profiles, app state, and Git internals are audit-only or protected.
5. Selection alone never authorizes cleanup.
6. Preview creates an immutable cleanup plan bound to the selection, manifest version, manifest checksum, and filesystem identities.
7. Selection changes invalidate the plan.
8. The complete plan is revalidated before the first movement, and every target is revalidated immediately before its own movement.
9. Cleanup uses `FileManager.trashItem` on macOS only.
10. DexCleaner never empties Trash and never claims moved bytes are freed bytes.
11. Preview authority expires after fifteen minutes.
12. Cancellation propagates into detached scanner and cleanup workers, terminates active shell commands where possible, and returns the application to a usable state.
13. Mandatory privacy exclusions cannot be removed by user configuration.
14. Timeouts, permission limits, command failures, and cancellations appear as scan issues rather than silent zeroes.

## Workflow

### 1. Scan

The app opens idle. Scanning starts only when the user requests it.

A scan or guided campaign reports:

- disk availability
- exact manifest- or adapter-authorized candidates
- typed actionable, review-only, protected, and unknown classifications
- audit-only storage findings
- protected presence markers
- access-check results
- explicit completeness and issue status
- fresh versus cached measurement timestamps

Warnings, measured cleanable summaries, and representative access diagnostics are visible in the main interface through Scan Details rather than being report-only state. The latest scan time remains visible, and audit freshness is called out when the displayed scan is older than thirty minutes.

### 2. Review

The user may filter and search findings. Selected targets remain visible in a dedicated Selected review area. Changing the cleanup profile clears selection to prevent hidden authority.

Command-F focuses search. Command-1 through Command-6 switch review areas. Search can be cleared explicitly or with Escape while focused. Findings are grouped by owning product, groups and row details can be collapsed, and measurement age is visible without changing cleanup authority.

`Add Visible` is additive: filtering no longer causes the bulk selection action to silently drop already selected items outside the current search. `Clear Visible` and `Clear All` make deselection scope explicit.

### 3. Preview

Preview performs no mutation. It creates an immutable cleanup plan only when every selected target passes its authority adapter and the safety engine, has a readable filesystem identity, and carries a complete evidence bundle. The plan is bound to the evidence fingerprint and, for guided campaigns, the source scan and campaign identifiers.

The interface explains why cleanup is unavailable, warns when selected owning applications appear active, and re-evaluates the Preview authorization window so an expired plan does not continue to look ready. If a Preview is invalidated by a selection change, stale Preview results are cleared so a later report cannot mix old Preview outcomes with a new selection.

### 4. Confirm and move

The confirmation sheet lists every exact path and estimated byte count, shows plan identity and a live authorization countdown, can copy the exact plan paths for audit, and initially focuses the non-destructive Cancel action. Cleanup revalidates the plan and then moves authorized targets to Finder Trash.

## Removed from the first trustworthy release

The following features remain deliberately absent:

- background scanning
- launch at login
- automatic launch-time scanning
- fake percentage progress
- direct cleanup without preview
- Git temporary-pack cleanup
- fallback cleanup manifest

Git temporary packs remain visible as audit-only findings.

## Reports and ledger

DexCleaner writes local Markdown or JSON reports with optional home-path redaction. The interface previews the current report mode, finding/result counts, format, path treatment, and cleanup-plan metadata state before writing.

Reports and campaign receipts include:

- app version
- manifest version and checksum
- scan completeness
- access limitations
- scan issues
- cleanup plan identifier
- source scan and campaign identifiers when applicable
- typed evidence, provenance, and evidence completeness
- per-item results
- moved-to-Trash bytes
- separate logical, allocated, and observed free-space accounting
- an explicit warning that moved bytes are not necessarily freed bytes

Preview and cleanup operations are appended to:

```text
~/Library/Application Support/DexCleaner/operation-ledger.jsonl
```

No telemetry, analytics, cloud upload, or network dependency is implemented.

## Development

Run both UI/UX count and source contracts:

```bash
make ui-contract
```

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
Sources/DexCleanerCore/CleanupCampaign.swift
Sources/DexCleanerCore/CleanupEvidence.swift
Sources/DexCleanerCore/GuidedCleanupCampaign.swift
Sources/DexCleanerCore/HomebrewAndManagedAdapters.swift
Sources/DexCleanerCore/ProjectArtifactAnalyzer.swift
Sources/DexCleanerCore/SafetyEngine.swift
Sources/DexCleanerCore/CleanupRunner.swift
Sources/DexCleanerCore/DiskScanner.swift
Sources/DexCleanerCore/PreviewAuthorization.swift
Sources/DexCleanerCore/OperationLedger.swift
Sources/DexCleanerCore/ReportWriter.swift
Sources/DexCleaner/AppModel.swift
Sources/DexCleaner/ContentView.swift
Sources/DexCleaner/DexCleanerApp.swift
Tests/DexCleanerTests/DexCleanerTests.swift
docs/SAFETY_POLICY.md
docs/MANIFEST_SCHEMA.md
docs/RELEASE_CHECKLIST.md
docs/EVIDENCE_DRIVEN_CLEANUP_CAMPAIGN_PLAN.md
docs/UI_UX_POLISH_2026-08-16.md
docs/UI_UX_POLISH_ROUND2_2026-08-16.md
scripts/verify_ui_contract.py
OPERATIONAL_STATE.md
DexCleaner_MacOS_bible.md
BUG_SWEEP_REPORT.md
CHANGELOG.md
```

## Residual boundary

DexCleaner revalidates filesystem identity immediately before calling Finder Trash, but the public path-based Trash API cannot provide a mathematical guarantee that no filesystem change occurs in the tiny interval between final validation and movement. Release review must treat that as a residual platform boundary, not pretend it does not exist.
