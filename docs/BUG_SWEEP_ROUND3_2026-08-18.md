# DexCleaner Bug Sweep - Round Three - 2026-08-18

## Executive summary

- Baseline: `main@c21a1bd566e5fc07243f7838e2ef2525fd44071a`
- Scope: current SwiftUI state/routing, result filtering, report preflight, scan-cache age handling, row controls, reveal behavior, transient feedback, workflow terminal state, adjacent selection-state transitions, tests, and deterministic UI contract.
- Cleanup authority: unchanged. No manifest, `SafetyEngine`, `CleanupRunner`, `PreviewAuthorization`, Finder Trash, or mandatory privacy-exclusion rule is relaxed.
- Confirmed defects repaired in this candidate: 9.
- Post-delivery gate: repository Linux and macOS CI must pass on the delivered commit before completion is claimed.

## Sweep history

| Pass | Focus | Confirmed defects | Result |
|---|---|---:|---|
| A | State-routing and user-feedback paths | 8 | All received bounded fixes |
| B | Adjacent state-machine resweep | 1 new | Selection now returns terminal workflows to Review when the user starts a new selection workflow |
| C | Regression-contract review | 0 new | Static contract and cache clock-skew test added |

## Complete repaired bug ledger

### BUG3-001 - Next-action routing could hide operation results
- Severity: medium
- Root cause: result handling was ordered after selection/plan branches, making the Results branch effectively unreachable in blocked Preview and post-cleanup states.
- Repair: valid Preview confirmation and stale Preview remain higher priority, then terminal operation results are surfaced before a new candidate workflow.
- Regression guard: `shouldReviewOperationResults` is required by `verify_ui_contract.py`.

### BUG3-002 - Result filter could hide a new result set
- Severity: medium
- Root cause: `resultFilter` persisted across replacement of `cleanupResults`.
- Repair: every new result set resets the filter to All.
- Regression guard: `onChange(of: model.cleanupResults)` is required by the UI contract.

### BUG3-003 - Future-dated cache records were accepted as fresh
- Severity: medium
- Root cause: cache age checked only the upper bound and accepted negative ages after clock rollback or corrupt timestamps.
- Repair: cache reads and pruning now require `age >= 0 && age <= maximumAge`.
- Regression guard: `ScanCacheClockRegressionTests` verifies future-dated records are rejected and removed before persistence.

### BUG3-004 - Report preflight could claim plan metadata that the report would omit
- Severity: medium
- Root cause: preflight used `cleanupPlan ?? lastCompletedPlan` for every non-scan mode while report construction selected plan state by report mode.
- Repair: a shared mode-aware `reportPlan(for:)` function now drives both preflight truth and report construction.
- Regression guard: the stale fallback expression is forbidden by `verify_ui_contract.py`.

### BUG3-005 - Selection-mutating controls could appear usable while work was locked
- Severity: medium
- Root cause: row checkbox/context-menu selection and the profile picker remained enabled while `AppModel.toggle` rejected selection changes during active work.
- Repair: row selection controls and the profile picker are disabled while `model.isWorking`.
- Safety note: this changes presentation/interaction only; active cleanup still uses the immutable captured plan.

### BUG3-006 - Reveal controls were shown for synthetic findings
- Severity: low
- Root cause: every scan row rendered Reveal even for `permission://` and `extension://` synthetic paths.
- Repair: one `canRevealPath` predicate now governs item/result reveal eligibility; row and context-menu Reveal actions are omitted when no filesystem path exists.

### BUG3-007 - Repeated copy feedback timers raced each other
- Severity: low
- Root cause: each click launched an independent delayed reset task.
- Repair: `FeedbackButton` cancels the prior reset task before starting a new one and cancels it on disappearance.

### BUG3-008 - Terminal cleanup could highlight a disabled confirmation step
- Severity: low
- Root cause: failed/cancelled cleanup used `lastCompletedPlan` to mark step four current even after confirmation had already been consumed.
- Repair: a cleanup outcome advances the four-step strip beyond confirmation (`current = 5`), while preview/scan failures retain their correct earlier step.
- Adjacent repair: step-three accessibility guidance now describes opening existing results when no selection exists.

### BUG3-009 - Starting a new selection workflow could leave a terminal phase visible
- Severity: medium
- Root cause: selection changes invalidated Preview but only `.previewed` transitioned back to `.reviewing`; `.complete`, `.failed`, and `.cancelled` could remain displayed while the user began a new selection.
- Repair: actual selection mutations call `selectionDidChange()`, which invalidates Preview and returns a non-working scanned session to Review.
- No-op `Clear Visible` now preserves state rather than invalidating anything when nothing is selected in scope.

## Protected surfaces

Unchanged by this repair:

- `Sources/DexCleanerCore/Resources/CleanupManifest.json`
- `Sources/DexCleanerCore/CleanupCatalog.swift`
- `Sources/DexCleanerCore/SafetyEngine.swift`
- `Sources/DexCleanerCore/CleanupRunner.swift`
- `Sources/DexCleanerCore/PreviewAuthorization.swift`
- Finder Trash-only cleanup
- selection-is-not-authority invariant
- mandatory privacy exclusions
- no-background-scan/no-network posture

`ScanCache.swift` changes only cache freshness acceptance; stale/future cache rejection can cause extra measurement work but cannot broaden cleanup authority.

## Validation contract

The delivered commit must pass:

1. `make bug-sweep`
2. `swift test -c release`
3. macOS `swift test`
4. macOS executable build
5. app-bundle construction/resource verification/plist validation/strict codesign verification
6. final diff review proving only the intended repair/test/docs surfaces changed

Native human interaction still remains required for final release proof of VoiceOver, enlarged text, Finder Trash restore/cancellation, Gatekeeper, and DMG install/launch.

## Verdict rule

Do not call the round complete until the delivered commit passes repository CI. If CI passes, the source-level verdict becomes: **No unresolved confirmed bugs in inspected scope; remaining native release risks need verification.**
