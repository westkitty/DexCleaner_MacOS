# Changelog

## 1.0.0 safety refactor — unreleased

### Cleanup authority changes

- Removed fallback manifest; invalid or missing manifest now disables cleanup.
- Added manifest validation for duplicate IDs, duplicate paths, overlaps, broad roots, non-safe risks, default selections, and missing metadata.
- Removed caution and protected targets from the cleanup-authority manifest.
- Downgraded Git temporary packs to audit-only findings.
- Added immutable cleanup plans bound to selection, manifest version, manifest checksum, and filesystem identity.
- Added mandatory preview and exact-path confirmation before cleanup.
- Added immediate target revalidation before Finder Trash movement.
- Added cache invalidation for moved targets and affected ancestor measurements after successful Trash movement.
- Added exact manifest-ID-to-path binding and fifteen-minute preview-plan expiry.
- Hardened manifest canonical-path and forbidden-fragment validation.

### State and cancellation

- Removed automatic launch-time scanning.
- Removed background scanning and launch-at-login.
- Replaced fake percentage progress with indeterminate operation state.
- Added shell cancellation with process termination.
- Added guaranteed operation-state cleanup.
- Prevented hidden profile selection by clearing selection on profile changes and keeping a persistent Selected tab.

### Scan and reporting

- Added explicit scan completeness and issue records.
- Added timeout, command-failure, permission, manifest, cancellation, and filesystem issue categories.
- Added non-removable pruning for Library, cloud storage, Trash, hidden caches, project roots, user-content roots, applications, and nested `.git` directories during large-file audit.
- Prevented read-only audit scripts and top-level usage scans from recursively measuring protected roots.
- Added fresh/cached measurement labels and timestamps.
- Removed protected byte totals and audit reclaim aggregates.
- Added Markdown and JSON reports, comprehensive free-text home-path redaction, collision-resistant filenames, plan identifiers, manifest checksums, and moved-to-Trash semantics.
- Added an append-only JSON Lines operation ledger.

### Interface

- Rebuilt the workflow around Scan → Review → Preview → Confirm Trash Move.
- Added responsive layout, search, profile filtering, sort-within-groups wording, Selected, Results, and Issues tabs.
- Made recovery notes, Reveal, Copy Path, and Copy Result permanently accessible.
- Added complete result display and explicit Open Trash action.
- Lowered minimum window size to 760 × 620 and added an outer scroll fallback.
- Removed the default Return-key shortcut from the destructive confirmation action.

### Validation

- Expanded the suite to 22 core tests.
- Added Linux and macOS CI jobs.
- Added app-bundle resource discovery for SwiftPM `.resources` and `.bundle` outputs, signing verification, and release checklist documentation.
