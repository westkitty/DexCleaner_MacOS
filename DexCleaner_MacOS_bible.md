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
