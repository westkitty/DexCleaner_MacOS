# DexCleaner Operational State

Last updated: 2026-08-16
Baseline: `main@9883f6b20929824c38226e6e7cf0850d1f144d17`

## Purpose
DexCleaner is a conservative macOS disk-audit and exact-cache cleanup app. Cleanup authority comes only from the bundled validated manifest. The protected journey remains: explicit Scan -> visible Review -> immutable Preview -> exact confirmation -> revalidation -> Finder Trash.

## Protected invariants
- No background scanning, launch-at-login, automatic launch scan, fallback manifest, broad cleaner behavior, Git cleanup, permanent deletion, or Trash emptying.
- Selection alone never authorizes cleanup.
- Preview authority expires after fifteen minutes and selection/profile changes invalidate it.
- Every target is revalidated immediately before `FileManager.trashItem`.
- Moved-to-Trash bytes are never represented as freed space.
- Mandatory privacy exclusions remain additive and non-removable.
- Cancellation remains available and propagates to detached work.

## Current work state
- Exactly 25 UI/UX improvements are implemented and enumerated in `docs/UI_UX_POLISH_2026-08-16.md`.
- UI changes are limited to `AppModel`, `ContentView`, `DexCleanerApp`, and supporting QA/docs.
- Confirmed defects repaired in this pass: stale Preview-expiry presentation; hidden scan diagnostics; silent rejection of invalid optional audit exclusions; stale README branch posture.
- No cleanup-core authority or manifest semantics were changed.

## Verified before delivery
- Swift 5 parser passes on changed app sources.
- `scripts/verify_ui_contract.py` passes and proves exactly UIX-01 through UIX-25 are ledgered with required source contracts.
- Changed app sources contain no permanent-deletion call, background-scan/login implementation token, default Return-key destructive shortcut, added network API, or debug `print`.
- Original AppModel user-action functions remain present.
- Candidate-file whitespace/conflict-marker and obvious credential-pattern scans pass.
- Starting repository CI baseline was green on Linux core and macOS app jobs.

## Implemented but still requires native verification
- Post-change macOS semantic build and app launch.
- Narrow/wide layout, enlarged text, Reduce Motion, keyboard-only navigation, and VoiceOver.
- Finder Trash movement/restoration/cancellation on real macOS.
- Signing, Gatekeeper, and DMG install/launch.
- The pre-existing residual path-to-Trash race remains a platform boundary.

## Git delivery rule
The current task explicitly authorizes a single fast-forward commit to `main`. Before ref update, the remote head must still equal the baseline above. Force push, history rewrite, reset/clean, and unrelated file mutation are prohibited.
