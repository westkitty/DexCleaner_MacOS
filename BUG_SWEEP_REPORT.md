# Bug Sweep Report — 1.0.0 Safety Refactor

## 1. Executive summary

- Target: `westkitty/DexCleaner_MacOS`
- Branch: `implement/adversarial-safety-refactor`
- Scope inspected: manifest authority, cleanup plans, safety decisions, cache, scanner, shell cancellation, AppModel state, SwiftUI controls, reports, ledger, scripts, CI, tests, and release documentation
- Editing mode: confirmed defects repaired directly
- Validation mode: Linux Swift debug/release/parallel tests, warnings-as-errors build, parser checks, manifest validation, shell syntax checks, and source-contract guards
- Confirmed bugs found: 18
- Confirmed bugs fixed: 18
- Remaining confirmed bugs: 0 in the inspected and executable scope
- Suspected risks: 4 macOS/platform integration risks requiring real hardware or CI verification
- Blockers: SwiftUI runtime, Finder Trash, signing/Gatekeeper, DMG installation, VoiceOver, and the residual non-atomic path-to-Trash interval cannot be exercised in this Linux environment
- Final verdict: **No unresolved confirmed bugs in inspected scope; remaining risks need verification**

## 2. Sweep history

| Pass | Purpose | Areas inspected | Bugs found | Fixes applied | Validation performed | New issues discovered | Result |
|---|---|---|---:|---:|---|---:|---|
| 1 | Adversarial implementation audit | Authority, scanner, state, reports, UI, scripts | 18 | 18 | Targeted tests and parser checks | 18 | All confirmed defects repaired |
| 2 | Independent regression sweep | Adjacent state, privacy, packaging, documentation | 0 unresolved | 4 adjacent hardening refinements | Full debug sweep, release tests, parallel tests, warnings-as-errors | 0 confirmed | No unresolved confirmed defects in inspected scope |

## 3. Complete bug ledger

### BUG-001: Detached work ignored AppModel cancellation
- Status: fixed
- Severity: high
- Location / affected area: `Sources/DexCleaner/AppModel.swift`
- Evidence: scan, cleanup, and refresh used detached tasks whose cancellation was not tied to the parent operation.
- Root cause: detached tasks do not inherit later cancellation from their creator.
- Exact fix required: wrap each detached worker in `withTaskCancellationHandler` and cancel the worker explicitly.
- Validation method: source-contract check, shell cancellation test, parser check, debug/release tests.
- Fix result: applied and validated in available scope.

### BUG-002: Manifest ID could authorize a different allowlisted path
- Status: fixed
- Severity: critical
- Location / affected area: `SafetyEngine.decision(for: CleanupPlanItem)`
- Evidence: the plan path was checked against the global allowed-path set but not against the path belonging to its stated manifest ID.
- Root cause: authority was validated as two independent memberships rather than one bound ID/path pair.
- Exact fix required: resolve the manifest entry by ID and require its exact canonical path to equal the plan path.
- Validation method: `testPlanManifestIDMustMatchItsExactPath`.
- Fix result: applied and validated.

### BUG-003: App bundle script searched for the wrong SwiftPM resource name
- Status: fixed
- Severity: high
- Location / affected area: `scripts/build_app_bundle.sh`
- Evidence: the script expected only `DexCleanerCore_DexCleanerCore.resources`; SwiftPM may emit package-prefixed `.resources` or `.bundle` directories.
- Root cause: hard-coded artifact name and fixed build path.
- Exact fix required: obtain `--show-bin-path` and search for `*DexCleanerCore.resources` or `*DexCleanerCore.bundle`.
- Validation method: shell syntax, Makefile source contract, macOS CI app-bundle resource assertion.
- Fix result: applied; runtime packaging still requires macOS verification.

### BUG-004: User exclusions could replace mandatory privacy exclusions
- Status: fixed
- Severity: high
- Location / affected area: `DiskScanner` initialization
- Evidence: callers could supply a custom exclusion list without a structural guarantee that protected defaults remained present.
- Root cause: privacy exclusions and preferences shared one ungoverned input.
- Exact fix required: define mandatory exclusions and union only canonical user additions.
- Validation method: `testMandatoryLargeFileExclusionsCannotBeRemoved`.
- Fix result: applied and validated.

### BUG-005: Read-only storage audits recursively measured protected roots
- Status: fixed
- Severity: high
- Location / affected area: `DiskScanner.auditChildren`, `scripts/audit_read_only.sh`
- Evidence: top-level `du` operations entered Library, projects, user-content, cloud, and app-state roots despite their protected status.
- Root cause: protection affected cleanup authority but not audit traversal.
- Exact fix required: prune protected children before measurement and mirror the exclusions in the script.
- Validation method: `testAuditChildrenPrunesProtectedHomeRootsBeforeMeasuring`, script review, shell syntax.
- Fix result: applied and validated.

### BUG-006: Home-path redaction leaked through free-text fields
- Status: fixed
- Severity: medium
- Location / affected area: `ReportWriter.redact`
- Evidence: only explicit path properties were redacted; warnings, issues, result details, diagnostics, summaries, explanations, and recovery notes could contain the absolute home path.
- Root cause: redaction was field-specific rather than report-wide.
- Exact fix required: redact every user-visible free-text field and reconstruct immutable cleanup-plan items with redacted values.
- Validation method: expanded Markdown and JSON report test.
- Fix result: applied and validated.

### BUG-007: Report mode was inferred from outcomes rather than operation intent
- Status: fixed
- Severity: medium
- Location / affected area: `AppModel.writeReport` and report state
- Evidence: a cleanup with no successful move could be mislabeled as a preview report.
- Root cause: report mode depended on moved bytes instead of the operation that produced the results.
- Exact fix required: persist explicit last report mode and attach a plan appropriate to scan, preview, or cleanup.
- Validation method: source review and parser/build validation.
- Fix result: applied.

### BUG-008: Cleanup cache invalidation left stale ancestor measurements
- Status: fixed
- Severity: medium
- Location / affected area: `ScanCache`, `CleanupRunner`
- Evidence: moving a target invalidated only its exact record; cached parent audit measurements could remain stale.
- Root cause: cache invalidation did not model affected tree ancestry.
- Exact fix required: invalidate target, descendants, and ancestors up to the home root.
- Validation method: `testCacheInvalidationRemovesTargetAndAncestorMeasurements`.
- Fix result: applied and validated.

### BUG-009: Manifest validator accepted path aliases and weak fragment metadata
- Status: fixed
- Severity: high
- Location / affected area: `ManifestValidator`
- Evidence: dot segments, repeated separators, whitespace-padded metadata, duplicate fragments, and forbidden-fragment conflicts were insufficiently rejected.
- Root cause: validation normalized conceptually without requiring canonical input representation.
- Exact fix required: require exact canonical relative paths, trimmed metadata, unique rooted fragments, and no target/fragment conflicts.
- Validation method: manifest regression tests and JSON validation.
- Fix result: applied and validated.

### BUG-010: Cleanup plans were described as immutable but were mutable structs
- Status: fixed
- Severity: medium
- Location / affected area: `Models.swift`
- Evidence: cleanup plan and plan-item properties were declared with `var`.
- Root cause: semantic promise was not represented in the type system.
- Exact fix required: make plan authority fields immutable with `let`.
- Validation method: build, report redaction reconstruction, plan tests.
- Fix result: applied and validated.

### BUG-011: Failed scan state was unreachable
- Status: fixed
- Severity: medium
- Location / affected area: `DiskScanner.scan`
- Evidence: issue-bearing scans were classified partial even when no usable data existed.
- Root cause: completeness was derived only from cancellation and issue presence.
- Exact fix required: classify no-usable-data plus issues as failed.
- Validation method: `testScanCompletenessCanRepresentFailurePartialAndCancellation`.
- Fix result: applied and validated.

### BUG-012: Return key activated the destructive confirmation action
- Status: fixed
- Severity: medium
- Location / affected area: cleanup confirmation sheet
- Evidence: the destructive button used the default-action keyboard shortcut.
- Root cause: convenience shortcut was inappropriate for an irreversible workflow step.
- Exact fix required: remove default Return-key activation.
- Validation method: source review; macOS keyboard QA remains required.
- Fix result: applied.

### BUG-013: Minimum window could clip the fixed vertical interface
- Status: fixed
- Severity: medium
- Location / affected area: `ContentView`
- Evidence: the vertical stack could exceed the declared minimum height under larger text or narrower layout fallbacks.
- Root cause: responsive width logic lacked a vertical overflow strategy.
- Exact fix required: add an outer scroll fallback while preserving an internal review-panel minimum.
- Validation method: parser check; macOS layout and VoiceOver QA remain required.
- Fix result: applied.

### BUG-014: Read-only audit script contradicted application privacy claims
- Status: fixed
- Severity: medium
- Location / affected area: `scripts/audit_read_only.sh`
- Evidence: the script measured protected roots that the application intentionally pruned.
- Root cause: script behavior drifted from scanner policy.
- Exact fix required: use the same mandatory exclusion doctrine and avoid empty-input `xargs` behavior.
- Validation method: shell syntax and manual source review.
- Fix result: applied.

### BUG-015: Reports could overwrite one another within the same second
- Status: fixed
- Severity: medium
- Location / affected area: `ReportWriter.write`
- Evidence: filename uniqueness depended only on operation mode and second-resolution timestamp.
- Root cause: repeated writes shared one deterministic destination.
- Exact fix required: add a short UUID suffix.
- Validation method: expanded report test verifies distinct filenames.
- Fix result: applied and validated.

### BUG-016: Blocked previews were absent from the operation ledger
- Status: fixed
- Severity: medium
- Location / affected area: `AppModel.previewSelected`
- Evidence: ledger append occurred only when a plan existed.
- Root cause: preview failure was treated as non-operation rather than important safety evidence.
- Exact fix required: append all preview outcomes, including blocked ones.
- Validation method: source review and ledger tests.
- Fix result: applied.

### BUG-017: Preview authorization had no expiry or duplicate-plan guard
- Status: fixed
- Severity: high
- Location / affected area: `PreviewAuthorization`, `CleanupRunner`
- Evidence: an old plan could remain valid indefinitely and a constructed plan could repeat a target.
- Root cause: authority checked selection and manifest state but not age or plan uniqueness.
- Exact fix required: expire plans after fifteen minutes and reject empty, future, expired, or duplicate-path plans.
- Validation method: `testExpiredAndDuplicatePlansAreBlocked`.
- Fix result: applied and validated.

### BUG-018: Documentation and CI drifted from the actual package
- Status: fixed
- Severity: low
- Location / affected area: README, changelog, release checklist, CI, Makefile
- Evidence: stale test count, obsolete test filename, and missing source-contract assertions.
- Root cause: implementation advanced without a synchronized release record.
- Exact fix required: update docs to 22 tests, correct paths, and add cancellation/resource/exclusion guards.
- Validation method: repository grep, `make bug-sweep`, CI workflow review.
- Fix result: applied.

## 4. Fixes applied

- Bound every cleanup plan item to its exact manifest ID and canonical target path.
- Added immutable, expiring cleanup plans with duplicate and empty-plan rejection.
- Propagated AppModel cancellation into detached scanner and cleanup workers.
- Made privacy exclusions mandatory and user exclusions additive only.
- Pruned protected roots from application and script audits.
- Added ancestor-aware cache invalidation.
- Hardened manifest canonicalization and fragment validation.
- Expanded report redaction to all free-text surfaces and prevented filename collisions.
- Removed default-key destructive confirmation.
- Added vertical overflow handling.
- Fixed SwiftPM resource-bundle discovery.
- Expanded regression coverage from 15 to 22 tests.

## 5. Remaining risks and blockers

### RISK-001: macOS SwiftUI and AppKit runtime
- Status: needs verification
- Required evidence: successful macOS CI and clean-account launch.

### RISK-002: Finder Trash and restoration
- Status: needs verification
- Required evidence: move, partial failure, cancellation, and restore tests on macOS.

### RISK-003: Signing, Gatekeeper, DMG, and bundled resource loading
- Status: needs verification
- Required evidence: signed app build, resource presence, Gatekeeper launch, DMG install and launch.

### RISK-004: Residual path-based filesystem race and child-process termination
- Status: platform boundary requiring stress testing
- Required evidence: adversarial mutation test around `trashItem` and cancellation tests involving subprocess trees. The current commands are direct system utilities, but the shell wrapper does not establish a dedicated process group.

## 6. Validation checklist

- [x] `make bug-sweep`
- [x] 22 debug tests, 0 failures
- [x] 22 release tests, 0 failures
- [x] 22 parallel tests completed
- [x] warnings-as-errors core build
- [x] Swift parser check for macOS app sources
- [x] manifest JSON parse
- [x] shell syntax validation
- [x] permanent-deletion source guard
- [x] background automation source guard
- [x] hidden-Git scanner guard
- [x] cancellation propagation source guard
- [x] resource-bundle discovery source guard
- [ ] macOS executable compile and launch
- [ ] Finder Trash move and restore
- [ ] app signing and Gatekeeper
- [ ] DMG install and launch
- [ ] keyboard and VoiceOver QA

## 7. Final verdict

**No unresolved confirmed bugs in inspected scope; remaining risks need verification**
