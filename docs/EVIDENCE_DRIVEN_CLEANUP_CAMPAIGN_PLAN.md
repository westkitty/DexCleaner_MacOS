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
- [x] Phase 1: evidence core, rule provenance, versioned JSON/Markdown reporting
- [x] Phase 2: plan-wide preflight, typed stale reasons, exact open/active-owner blocking
- [x] Phase 3: read-only project-artifact discovery with bounded traversal and cancellation
- [x] Phase 4: narrowly proven Node `node_modules` and Rust `target` cleanup eligibility
- [x] Phase 5: action receipts, truthful accounting, progress, freshness, safe retry, re-rank, STOP logic
- [x] Phase 6: dedicated Homebrew staging adapter
- [x] Phase 7: managed system, FileProvider, and cloud protection adapter
- [x] Phase 8: backup and rollback restorability engine
- [x] Phase 9: physical-identity-aware exact duplicate analyzer
- [x] Phase 10: extended read-only ecosystem, model-store, and toolchain classification
- [ ] Phase 11: guided cleanup campaign orchestration and user interface
- [ ] Phase 12: adversarial hardening, documentation, release validation, and integration decision

## Phase gates

Each phase must add focused fixtures for its authority boundary, pass affected parser/static checks and focused tests, pass `git diff --check`, and preserve the safety contract. `make bug-sweep` runs at safety-boundary phases and final integration. Release tests, app-bundle construction, property-list validation, and strict code-sign verification run at the final gate.

Commits and pushes use explicit file staging. Project Sentinel generated evidence is reviewed separately and is never swept into a phase commit by broad staging.

## Baseline evidence

On macOS 26.6.2 with the Apple Swift 6.2 toolchain, `make bug-sweep` passed from the isolated campaign worktree on 2026-08-25. Swift Package Manager executed 104 tests with 0 failures and 3 intentionally gated skips. The user-interface contract, debug build, package description, Swift parser, manifest parser, shell syntax, cancellation wiring, resource packaging, and permanent-deletion/background-scan guards all passed.

## Phase 1-2 evidence

The evidence core now records typed ownership, protection, rebuildability, risk, filesystem identity, evidence records, rule source, rule version, and manifest checksum. A deterministic fingerprint binds those fields, and preview plans bind the complete evidence set with a separate evidence signature. JSON reports use schema `2.0.0`; the bundled manifest and rule set use schema/version `1.0.0`. Markdown and JSON are generated from the same `ScanReport`, and home-relative redaction covers evidence paths and details.

Cleanup now runs a typed whole-plan preflight before the first mutation. It validates plan age, unique canonical paths, selection and evidence signatures, manifest state, every candidate identity/evidence bundle, and an exact path/subtree open-file check. Detector failure is a blocking unknown. Immediate identity and open-file revalidation remains directly before each Finder Trash call.

Focused evidence/preflight fixtures passed 8 of 8. The repository-wide gate then passed 112 tests with 0 failures and 3 intentionally gated skips. The stale-fourth-item fixture proves the first item is not moved; open-after-preview and detector-unavailable fixtures fail closed.

## Phase 3-4 evidence

`ProjectArtifactAnalyzer` performs bounded, cancellable discovery without traversing `.git`, `.hg`, `.svn`, hidden metadata, or artifact contents during discovery. It records complete/partial/cancelled coverage and separately bounds measurement entries. Matching names without valid workspace authority remain review-only; symlinks and incomplete measurements fail closed.

The dedicated project adapter promotes only default Node `node_modules` and Rust `target` directories inside `~/Projects`, `~/Developer`, or `~/src`. Promotion requires a valid adjacent `package.json` or `Cargo.toml`, a containing Git repository, exact ignored and untracked state, complete measurement, physical identity, no symlink component, dedicated adapter provenance, immutable preview, whole-plan preflight, and immediate revalidation. Generic `build` and `dist` findings remain review-only; tracked findings are protected.

Six focused fixtures cover Node, Rust, monorepo authority, tracked generic build output, missing workspace authority, symlink refusal, hidden-metadata pruning, incomplete measurement, cancellation, preview, and preflight. The repository-wide gate passed 118 tests with 0 failures and 3 intentionally gated skips.

## Phase 5 evidence

Versioned action receipts now distinguish attempted, completed, skipped, stale, blocked, and failed candidates while preserving completed and remaining work separately. New scan reports receive a scan identifier by default; campaign-linked plans and receipts preserve their source-scan and campaign identifiers. Retry decisions are derived from terminal candidate state so already-completed or idempotently absent targets are not retried.

Reclaim accounting separates logical candidate bytes, allocated bytes, moved-to-Trash bytes, and observed free-space samples. Physical reclaim remains explicitly unknown unless both filesystem samples exist; moving an item to Finder Trash is never reported as freed space. Progress snapshots count candidate terminal states rather than estimating from bytes. STOP recommendations expose their inputs and rule version and can be recomputed from the same values.

Five focused fixtures cover idempotent absence, partial completion, transparent STOP recomputation, campaign freshness/re-ranking, and versioned Codable progress/receipts. The repository-wide `make bug-sweep` gate passed 123 tests with 0 failures and 3 intentionally gated skips, followed by the build, parser, manifest, shell, cancellation, resource, and destructive-authority checks.

## Phase 6-10 evidence

The Homebrew adapter grants authority only to an exact descendant of a separately verified staging root after prefix/layout identity, installed-root exclusion, symlink refusal, inactive-manager state, closed handles, and object identity are proven. Cellar/Caskroom/installed roots, broad roots, active operations, unavailable open-state checks, and unsupported layouts fail closed. Homebrew findings still enter the ordinary immutable Preview and final-preflight path.

Typed managed-resource classification protects FileProvider/FPCK, CloudDocs, Mobile Documents, CloudStorage, DriveFS, Dropbox, OneDrive, and established system-service state before generic authority is considered. Age and size cannot override that ownership classification, and no process-termination path exists.

Backup validators now require isolated Git-bundle restoration plus required ref/object coverage, or configured macOS application identity/structure/executable/version proof. Integrity alone is insufficient; a broken retained generation blocks removal, and different semantic fingerprints preserve unique historical versions. Retention output is review-oriented and contains no private absolute-path profile.

Exact duplicate analysis is bounded and cancellable, groups by size, collapses confirmed device/inode aliases, hashes only physical-object collisions, and reports equal content separately from caller-supplied semantic role. All generic sets remain review-only and physical reclaim remains unknown. When physical identity is unavailable, paths remain distinct rather than being falsely collapsed.

Gradle/Android, Xcode, Kotlin/Native, Python, artificial-intelligence model, and toolchain classifications are read-only. Installed, active, default, project-referenced, and shared-blob capabilities remain protected or review-only; no new cleanup authority was granted.

Eight focused adapter fixtures passed. The repository-wide `make bug-sweep` gate passed 131 tests with 0 failures and 3 intentionally gated skips, followed by all existing build and static safety checks.

## Known platform boundary

Finder Trash remains a platform-mediated operation. DexCleaner can minimize time-of-check/time-of-use exposure with plan-wide and immediate revalidation, but it cannot make another process incapable of replacing a path between the final check and the operating-system Trash call. Reports and documentation must state that residual boundary honestly.
