# DexCleaner Operational State

Last updated: 2026-08-25
Baseline: `codex/evidence-cleanup-campaign-20260825@27d352c4c7d24f9106498c0dbeb15de72077011e`

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
- The evidence-driven cleanup campaign is active on `codex/evidence-cleanup-campaign-20260825`.
- The durable phase ledger and safety contract are in `docs/EVIDENCE_DRIVEN_CLEANUP_CAMPAIGN_PLAN.md`.
- Phase 0 established the live repository and toolchain baseline in an isolated worktree; the original dirty recovery/audit checkout remains untouched.
- Phases 1 and 2 add typed evidence/provenance, report schema `2.0.0`, evidence-bound preview plans, whole-plan preflight, and exact open-file blocking.
- Phases 3 and 4 add bounded read-only project discovery and a dedicated adapter for proven ignored/untracked Node `node_modules` and Rust `target` directories under dedicated project roots.
- Phase 5 adds versioned action receipts, scan/campaign identifiers, truthful reclaim accounting, terminal-state progress, safe retry selection, and reproducible STOP recommendations.
- Generic `build`/`dist`, tracked artifacts, symlinks, incomplete measurements, missing workspace authority, and unavailable Git state remain non-actionable.

## Verified campaign baseline
- `make bug-sweep` passed on macOS 26.6.2 using the Apple Swift 6.2 toolchain.
- Swift Package Manager executed 104 tests with 0 failures and 3 explicitly gated skips.
- UI contract, Swift test/build, package description, parser, manifest, shell, cancellation, resource, and destructive-authority guards passed.
- `origin/main` was `c1b68d424e72678e9ecdd34effb68496c2796f11`; the campaign baseline contains six additional committed changes already published on `codex/final-storage-forensics`.
- After Phases 1 and 2, focused evidence/preflight fixtures passed 8 tests and `make bug-sweep` passed 112 tests with 0 failures and 3 explicitly gated skips.
- After Phases 3 and 4, focused project fixtures passed 6 tests and `make bug-sweep` passed 118 tests with 0 failures and 3 explicitly gated skips.
- After Phase 5, focused campaign/receipt fixtures passed 5 tests and `make bug-sweep` passed 123 tests with 0 failures and 3 explicitly gated skips.

## Implemented but still requires native verification
- Post-change macOS semantic build and app launch.
- Narrow/wide layout, enlarged text, Reduce Motion, keyboard-only navigation, and VoiceOver.
- Finder Trash movement/restoration/cancellation on real macOS.
- Signing, Gatekeeper, and DMG install/launch.
- The pre-existing residual path-to-Trash race remains a platform boundary.

## Git delivery rule
Commit and push each validated phase to `codex/evidence-cleanup-campaign-20260825` with explicit staging. Do not force push, rewrite history, reset/clean, or mutate unrelated recovery/audit material. Integrate only after the complete campaign is green and the final branch-base diff is reviewed; use the repository's ordinary pull-request or fast-forward path.
