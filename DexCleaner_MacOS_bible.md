# DexCleaner macOS Project Bible

## 2026-08-16 — Production UI/UX polish

### Governing purpose
DexCleaner is not a broad cleaner. Its authority model is exact manifest target -> explicit selection -> immutable Preview -> explicit confirmation -> final revalidation -> Finder Trash. Any future UI work must make that model clearer, never bypass it.

### Baseline
- Repository: `westkitty/DexCleaner_MacOS`
- Branch: `main`
- Starting commit: `9883f6b20929824c38226e6e7cf0850d1f144d17`
- Baseline GitHub Actions: Linux deterministic bug sweep and macOS app build/bundle verification passed.
- No local Git checkout is exposed in the active runtime; committed remote state is the observable authority.

### Production-polish decision
Exactly 25 UI/UX improvements were accepted. They are frozen in `docs/UI_UX_POLISH_2026-08-16.md`; reduced-motion support is cross-cutting and is not counted as a twenty-sixth item.

### Defects repaired
1. Preview expiry could become visually stale because authorization was time-dependent without a clock-driven UI refresh.
2. Scanner warnings, storage summaries, and permission diagnostics existed in state/reports but were hidden from the main interface.
3. Invalid optional audit exclusions were safely ignored but silently, creating misleading configuration feedback.
4. README release posture still named the pre-integration safety-refactor branch.

### Safety preservation
No manifest, SafetyEngine, CleanupRunner authority rule, Trash mechanism, mandatory privacy exclusion, or report-redaction rule was relaxed. Background scanning, permanent deletion, direct cleanup, broad roots, and freed-space claims remain prohibited.

### Validation added
`scripts/verify_ui_contract.py` enforces exactly UIX-01 through UIX-25 and checks key UI/model/menu source contracts. `make bug-sweep` runs this gate before the existing tests/build/parser/manifest/shell/source guards.

### Remaining release proof
Repository CI should be checked on the delivered commit. Public release still requires clean-account macOS visual/keyboard/VoiceOver, Finder Trash restore/cancellation, signing/Gatekeeper, and DMG verification.

## 2026-08-16 - Production UI/UX polish round two

### Repository state
- Repository: `westkitty/DexCleaner_MacOS`
- Branch: `main`
- Starting commit: `b5129fa06765cfb4e1d871b91d98c7f5d1520c05`
- Starting CI: completed successfully on both Linux and macOS.
- Container network could not resolve GitHub, so repository reads/writes use the authenticated GitHub connector; local Swift parsing is available.

### Goals and frozen scope
- Implement exactly 25 new UI/UX improvements beyond the first 25.
- Preserve the exact cleanup-authority model and all existing safety boundaries.
- Limit runtime edits to `AppModel.swift`, `ContentView.swift`, and `DexCleanerApp.swift`; no cleanup-core or manifest change is authorized.

### Accepted change groups
1. State legibility and safe action guidance: scan freshness, next action, actionable workflow, scoped selection, keyboard acceleration.
2. Review ergonomics: grouped/collapsible findings, progressive row details, measurement age, adaptive review navigation, result/issue triage.
3. Auditability and confirmation: copyable diagnostics/results/issues, report preflight, Preview countdown, exact plan-path copy.

### Confirmed defects repaired
1. `Select Visible` replaced the entire selection, silently dropping selected candidates outside the active search filter. It is now additive, with explicit `Clear Visible` and `Clear All` controls.
2. Copy Path and Copy Result changed the global operational status to `Copied`, hiding more important scan/cleanup state. Copy confirmation is now local to the button only.
3. Invalidating a dry-run Preview could retain old Preview results and `dryRun` report mode while the selected items changed, allowing a later report to mix stale Preview outcomes with a new selection. Preview invalidation now clears dry-run results and returns report mode to Scan.
4. A no-op `Add Visible` could invalidate an otherwise valid Preview even when the selected set did not change; no-op addition now preserves authorization.
5. Expired Preview guidance could route to stale results instead of establishing a fresh read-only Preview; next-action and workflow guidance now offer Preview Again.
6. Selection microcopy incorrectly used the term cleanup authority for selection state; wording now preserves the invariant that selection alone never authorizes cleanup.

### Validation
- Swift parser pass on all changed app sources.
- Round-two UI contract verifies the original exact 25 plus exactly `UIX2-01` through `UIX2-25`.
- Whitespace/conflict-marker scan passes.
- Source guards find no permanent deletion, background scan/login service, added networking, destructive default Return shortcut, or debug `print`.
- Native interactive macOS visual/VoiceOver/Finder Trash behavior remains a release-time proof requirement.

### Delivery
- One descriptive fast-forward commit to `main` is authorized by the current user request.
- Final commit hash and post-push CI status are reported externally to avoid a recursive self-hash documentation commit.

## 2026-08-18 - Bug sweep round three

### Baseline and purpose
- Repository: `westkitty/DexCleaner_MacOS`
- Branch: `main`
- Starting commit: `c21a1bd566e5fc07243f7838e2ef2525fd44071a`
- Goal: close the eight confirmed BUG3 defects from the fresh production sweep and any directly adjacent state defect found during resweep without broadening cleanup authority.

### Confirmed repair set
- Next-action routing now surfaces blocked/failed/cancelled/completed operation results instead of routing past them.
- Result filters reset when a new result set arrives.
- Scan-cache records with future timestamps are rejected and pruned rather than treated as fresh.
- Report preflight and report construction share one mode-aware cleanup-plan selector.
- Selection-mutating row controls and the profile picker are disabled while work is active.
- Reveal controls are omitted for synthetic non-filesystem findings.
- Copy-feedback reset tasks are cancellation-safe across rapid repeated clicks and view disappearance.
- Terminal cleanup outcomes advance the workflow beyond confirmation rather than highlighting a disabled confirmation step.
- Adjacent resweep found one additional state defect: an actual selection change after terminal state could leave Complete/Needs attention/Cancelled visible. Selection mutation now returns a scanned idle session to Review.

### Regression protection
- Added `ScanCacheClockRegressionTests.swift` for future-dated cache rejection and persistence pruning.
- Extended `scripts/verify_ui_contract.py` with round-three state/routing/reveal/feedback/report/cache guards while preserving the exact two 25-item UI ledgers.
- Added `docs/BUG_SWEEP_ROUND3_2026-08-18.md` as the source-level defect and validation ledger.

### Protected surfaces
- Cleanup manifest, `SafetyEngine`, `CleanupRunner`, `PreviewAuthorization`, Finder Trash behavior, mandatory privacy exclusions, and no-background/no-network doctrine remain unchanged.
- `ScanCache.swift` is changed only to reject invalid clock-skewed cache ages; this can increase remeasurement but cannot expand cleanup authority.

### Delivery rule
- Final completion still requires repository Linux and macOS CI on the delivered commit.
- Final commit hash and post-push CI outcome remain external to this append-only entry to avoid a recursive documentation commit.
