# Evidence-Driven Cleanup Campaign Plan

Last updated: 2026-08-25

## Delivery state

- Repository: `westkitty/DexCleaner_MacOS`
- Working branch: `codex/evidence-cleanup-campaign-20260825`
- Campaign baseline: `27d352c4c7d24f9106498c0dbeb15de72077011e`
- Remote default branch at preflight: `main@c1b68d424e72678e9ecdd34effb68496c2796f11`
- Original checkout: preserved with its recovery and storage-audit changes untouched
- Campaign worktree: `/Users/andrew/.codex/worktrees/dexcleaner-evidence-cleanup-20260825`

## Safety contract

The existing exact-manifest cleanup flow remains authoritative until a dedicated adapter proves a new candidate class. A name, age, size, hash, or location can propose investigation but cannot authorize cleanup.

Every actionable candidate must carry typed identity, ownership, protection, rebuildability, risk, evidence, and provenance. Unknown or incomplete evidence fails closed. Approval binds to an immutable plan and the complete plan is revalidated before the first Finder Trash move. Immediate per-item revalidation remains mandatory.

DexCleaner will not add generic permanent deletion, Trash emptying, process killing, background cleanup, launch-at-login cleanup, automatic destructive launch scans, telemetry, network requirements, or broad home-directory authority.

## Phase ledger

- [x] Phase 0: preflight, baseline, isolated worktree/branch, durable plan, operational-state correction
- [ ] Phase 1: evidence core, rule provenance, versioned JSON/Markdown reporting
- [ ] Phase 2: plan-wide preflight, typed stale reasons, exact open/active-owner blocking
- [ ] Phase 3: read-only project-artifact discovery with bounded traversal and cancellation
- [ ] Phase 4: narrowly proven Node `node_modules` and Rust `target` cleanup eligibility
- [ ] Phase 5: action receipts, truthful accounting, progress, freshness, safe retry, re-rank, STOP logic
- [ ] Phase 6: dedicated Homebrew staging adapter
- [ ] Phase 7: managed system, FileProvider, and cloud protection adapter
- [ ] Phase 8: backup and rollback restorability engine
- [ ] Phase 9: physical-identity-aware exact duplicate analyzer
- [ ] Phase 10: extended read-only ecosystem, model-store, and toolchain classification
- [ ] Phase 11: guided cleanup campaign orchestration and user interface
- [ ] Phase 12: adversarial hardening, documentation, release validation, and integration decision

## Phase gates

Each phase must add focused fixtures for its authority boundary, pass affected parser/static checks and focused tests, pass `git diff --check`, and preserve the safety contract. `make bug-sweep` runs at safety-boundary phases and final integration. Release tests, app-bundle construction, property-list validation, and strict code-sign verification run at the final gate.

Commits and pushes use explicit file staging. Project Sentinel generated evidence is reviewed separately and is never swept into a phase commit by broad staging.

## Baseline evidence

On macOS 26.6.2 with the Apple Swift 6.2 toolchain, `make bug-sweep` passed from the isolated campaign worktree on 2026-08-25. Swift Package Manager executed 104 tests with 0 failures and 3 intentionally gated skips. The user-interface contract, debug build, package description, Swift parser, manifest parser, shell syntax, cancellation wiring, resource packaging, and permanent-deletion/background-scan guards all passed.

## Known platform boundary

Finder Trash remains a platform-mediated operation. DexCleaner can minimize time-of-check/time-of-use exposure with plan-wide and immediate revalidation, but it cannot make another process incapable of replacing a path between the final check and the operating-system Trash call. Reports and documentation must state that residual boundary honestly.
