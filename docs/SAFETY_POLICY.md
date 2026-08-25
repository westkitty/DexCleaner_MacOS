# DexCleaner Safety Policy

## Authority model

Cleanup authority is fail-closed.

The bundled `CleanupManifest.json` is decoded and validated at runtime. Dedicated adapters may grant authority only to their exact candidate class after producing the typed identity, ownership, protection, rebuildability, risk, evidence, and provenance required by the safety engine. A name, location, age, size, or hash alone never grants authority.

Cleanup is disabled when the applicable authority source is missing, malformed, contradictory, broad, stale, incomplete, non-safe, or configured with default selections. Unknown evidence fails closed.

There is no fallback manifest.

## Mandatory cleanup sequence

A target may be moved only after all of the following occur:

1. It appears in the validated bundled manifest or is proven by a dedicated adapter for its exact candidate class.
2. It exists under the current user's home directory.
3. It is not a broad root.
4. It contains no protected fragment.
5. No path component is a symbolic link.
6. Its authority evidence is complete, internally consistent, and fingerprints the exact candidate identity.
7. The user explicitly selects it.
8. Preview captures its authority ID, provenance, evidence signature, path, measured size, and filesystem identity.
9. The complete selection produces an immutable cleanup plan.
10. The user reviews the exact plan in the confirmation sheet.
11. Whole-plan preflight revalidates every candidate before the first movement, including required open-file or active-owner checks.
12. The authority version/checksum and evidence signatures still match.
13. The target path, filesystem identity, and required open-file state still match immediately before movement.
14. `FileManager.trashItem` succeeds.

Failure during whole-plan preflight blocks the entire plan before mutation. Failure during immediate per-item revalidation blocks that item and records the typed reason.

## Forbidden authority

DexCleaner must not grant cleanup authority to:

- home or filesystem root
- broad cache roots
- broad Application Support roots
- user documents or media
- Downloads or Desktop
- cloud storage
- project source and metadata; only exact ignored/untracked Node `node_modules` and Rust `target` artifacts under approved project roots may be separately proven by their dedicated adapter
- Git internals
- browser profiles
- workspace history
- local/session storage
- IndexedDB or service-worker state
- credentials or keychains
- unknown app state
- managed system, FileProvider, cloud, installed toolchain, active capability, shared model-blob, caution, audit-only, forbidden, protected, unknown, or incompletely measured items

## Preview authorization

Preview authorization is bound to a signature of selected item IDs, authority IDs, provenance, paths, measured sizes, filesystem identities, evidence fingerprints, risk levels, and actions. Any selection change invalidates the authorization.

The plan also records applicable rule/manifest versions and checksums and expires after fifteen minutes. Campaign plans additionally bind the source scan and campaign identifiers. An authority change, evidence change, or expired plan invalidates cleanup authority.

## Dedicated adapter boundaries

- Project artifacts: only proven ignored and untracked Node `node_modules` and Rust `target` directories under `~/Projects`, `~/Developer`, or `~/src` can become actionable. Generic `build`/`dist`, tracked output, symlinks, and incomplete measurements remain non-actionable.
- Homebrew: only an exact descendant of a separately verified staging root can become actionable. Installed Cellar/Caskroom roots, active operations, open handles, unsupported layouts, and unknown detector state are blocked.
- Backups, duplicates, managed resources, model stores, and toolchains are validation or review classifiers. They do not grant generic cleanup authority.

## Cancellation

Shell commands poll task cancellation and receive termination followed by forced termination when needed. App operations use guaranteed state cleanup so cancellation cannot leave the interface permanently locked.

A cancelled cleanup preserves completed results, labels unprocessed items, and does not start a refresh scan.

## Scan honesty

The scanner distinguishes:

- complete
- partial
- cancelled
- failed
- not run

Timeouts, permission failures, command failures, and manifest failures are explicit `ScanIssue` records.

Protected paths are presence markers with no invented byte totals.

Audit measurements may overlap and are never presented as a reclaimable aggregate.

## Cache policy

Size cache records expire after fifteen minutes by default. A record is accepted only when:

- the target still exists
- its top-level modification time still matches
- the record is not expired

The moved target, descendant records, and affected ancestor measurements are invalidated after successful Trash movement. Cached values are visibly labeled with their measurement time. Guided campaign freshness and re-ranking require a new scan when their evidence is stale.

## Trash semantics

DexCleaner moves items to Finder Trash only. It does not empty Trash.

The app and reports must use the phrase **Moved to Trash**, not **Freed**, unless actual filesystem availability is separately measured and attributed.

## Residual filesystem race

The target is revalidated immediately before the path-based Trash call. The public API does not expose an atomic “validate this file descriptor and trash that same object” operation. This residual interval must remain documented and covered by conservative release testing.

## Mandatory audit exclusions

Large-file and top-level storage audits always prune protected user-content, cloud, project, app-state, hidden-cache, Trash, Library, and nested Git roots. User-supplied exclusions are additive only and cannot remove these mandatory privacy boundaries.
