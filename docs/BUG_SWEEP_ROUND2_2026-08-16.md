# DexCleaner Bug Sweep - Production UI/UX Polish Round Two - 2026-08-16

## 1. Executive summary

- Target: `westkitty/DexCleaner_MacOS`, branch `main`
- Starting commit: `b5129fa06765cfb4e1d871b91d98c7f5d1520c05`
- Scope inspected: current macOS app state/model/UI/menu surfaces, first-pass UI contract, safety invariants, README, CI posture, and second-pass candidate changes
- Editing mode: confirmed in-scope defects repaired directly; cleanup-authority core intentionally untouched
- Validation mode: Swift parser, deterministic two-ledger UI contract, source guards, whitespace/conflict checks, secret-pattern checks, final GitHub diff review, then repository CI after delivery
- Confirmed bugs found: 6
- Confirmed bugs fixed: 6
- Remaining confirmed bugs: 0 in source-accessible changed scope
- Native risks: real macOS interaction, VoiceOver, Reduce Motion, Finder Trash, signing/Gatekeeper, and DMG behavior still require runtime evidence beyond source inspection/CI compilation
- Final source-level verdict: **No unresolved confirmed bugs in inspected scope; remaining risks need verification**

## 2. Sweep history

| Pass | Purpose | Bugs found | Fixes applied | Validation | Result |
|---|---|---:|---:|---|---|
| A | Adversarial baseline/state review | 3 | 3 | parser + source inspection | Selection/reporting feedback defects repaired |
| B | Independent post-implementation state review | 3 | 3 | parser + UI contract + targeted source checks | No unresolved confirmed source defect |

## 3. Complete bug ledger

### BUG2-001 - Select Visible silently replaced out-of-filter selections
- Status: fixed
- Severity: medium
- Location: `AppModel.selectVisibleCandidates`
- Evidence: the baseline mapped every item to `isSelected = isCleanable && visibleIDs.contains(id)`, so a search/filter could make previously selected exact targets disappear from the selection without the user choosing to clear them.
- Root cause: a scoped additive action was implemented as whole-selection replacement.
- Fix: `Add Visible` now only adds visible candidates; `Clear Visible` and `Clear All` make deselection scope explicit.
- Validation: source contract and parser; exact selection behavior remains subject to interactive macOS QA.

### BUG2-002 - Copy feedback overwrote operational status
- Status: fixed
- Severity: low
- Location: `AppModel.copyPath` and `copyResult`
- Evidence: copying a path/result replaced `statusText` with `Copied...`, temporarily hiding scan/cleanup state.
- Root cause: local micro-feedback reused the global operation-status channel.
- Fix: clipboard helpers no longer mutate operational status; `FeedbackButton` owns transient copy confirmation locally.
- Validation: source review and forbidden regression checks.

### BUG2-003 - Preview invalidation could leave stale dry-run results/report mode
- Status: fixed
- Severity: medium
- Location: `AppModel.invalidatePreview`
- Evidence: selection/profile changes cleared Preview authorization and plan but retained old Preview results with `lastReportMode == .dryRun`, allowing a later report to mix stale Preview outcomes with the changed selection.
- Root cause: authorization invalidation did not invalidate the dependent dry-run presentation/report state.
- Fix: invalidating an active dry-run now clears dry-run results and returns report mode to Scan while preserving completed cleanup results.
- Validation: parser, targeted source review, report-state reasoning against existing report construction.

### BUG2-004 - No-op Add Visible invalidated a valid Preview
- Status: fixed
- Severity: medium
- Location: `AppModel.addVisibleCandidates`
- Evidence: even when every visible item was already selected, the action still invalidated Preview authorization.
- Root cause: mutation/invalidation ran unconditionally instead of only after the selected set changed.
- Fix: no-op Add Visible leaves the selected set and existing Preview authorization unchanged.
- Validation: targeted source review and parser.

### BUG2-005 - Expired Preview guidance routed to stale results instead of re-preview
- Status: fixed
- Severity: medium
- Location: `ContentView.nextAction*` and workflow step 3
- Evidence: when a plan existed but exceeded its authorization window, the next-action card and Preview workflow step could route to old results rather than establish a fresh read-only Preview.
- Root cause: UI state distinguished plan presence from plan absence, but not plan validity.
- Fix: expired/invalid-time plan state explicitly offers `Preview Again`, and workflow step 3 reruns Preview when authorization is not currently valid.
- Validation: source contract, parser, time-aware state inspection.

### BUG2-006 - Selection copy mislabeled selection as cleanup authority
- Status: fixed
- Severity: medium
- Location: `ContentView.selectionImpact`
- Evidence: empty selection text said `No cleanup authority is selected`, contradicting the protected rule that selection alone never grants cleanup authority.
- Root cause: microcopy collapsed selection state and authorization state into one concept.
- Fix: wording now says `No cleanup candidates are selected`; Preview/confirmation remain the only authority language.
- Validation: safety-language source review.

## 4. Second-pass UI contract

The separate ledger `docs/UI_UX_POLISH_ROUND2_2026-08-16.md` contains exactly `UIX2-01` through `UIX2-25`. The original `UIX-01` through `UIX-25` ledger remains unchanged and protected.

## 5. Protected surfaces

No second-pass change is authorized for:

- `Sources/DexCleanerCore/Resources/CleanupManifest.json`
- `CleanupCatalog.swift`
- `SafetyEngine.swift`
- `CleanupRunner.swift`
- `DiskScanner.swift`
- `PreviewAuthorization.swift`
- `ReportWriter.swift`
- the Finder Trash mechanism or mandatory privacy exclusions

## 6. Remaining risks and blockers

- Interactive macOS layout at minimum/large window sizes is not directly renderable in the current Linux container.
- VoiceOver, keyboard focus restoration, native context-menu accessibility, Reduce Motion, and enlarged-text behavior need real macOS interaction evidence.
- Finder Trash move/restore/cancellation still requires real filesystem/runtime testing.
- Signing, Gatekeeper, and DMG install/launch remain release gates.
- `OPERATIONAL_STATE.md` is a legacy non-schema state file and names the earlier baseline; the Operational State workflow requires malformed legacy state to be preserved rather than silently rewritten in this implementation commit.

## 7. Final verdict

**No unresolved confirmed bugs in inspected scope; remaining risks need verification**
