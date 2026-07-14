# DexCleaner Safety Policy

## Authority model

Cleanup authority is fail-closed.

The bundled `CleanupManifest.json` is decoded and validated at runtime. Cleanup is disabled when the resource is missing, malformed, contradictory, broad, overlapping, non-safe, or configured with default selections.

There is no fallback manifest.

## Mandatory cleanup sequence

A target may be moved only after all of the following occur:

1. It appears in the validated bundled manifest.
2. It exists under the current user's home directory.
3. It is not a broad root.
4. It contains no protected fragment.
5. No path component is a symbolic link.
6. Its manifest risk is `Safe` and action is `Move exact path to Trash`.
7. The user explicitly selects it.
8. Preview captures its manifest ID, path, estimated size, and filesystem identity.
9. The complete selection produces an immutable cleanup plan.
10. The user reviews the exact plan in the confirmation sheet.
11. The manifest version and checksum still match.
12. The target path and filesystem identity still match immediately before movement.
13. `FileManager.trashItem` succeeds.

Failure at any stage blocks that target and records the reason.

## Forbidden authority

DexCleaner must not grant cleanup authority to:

- home or filesystem root
- broad cache roots
- broad Application Support roots
- user documents or media
- Downloads or Desktop
- cloud storage
- project trees
- Git internals
- browser profiles
- workspace history
- local/session storage
- IndexedDB or service-worker state
- credentials or keychains
- unknown app state
- caution, audit-only, forbidden, or protected items

## Preview authorization

Preview authorization is bound to a signature of selected item IDs, manifest IDs, paths, measured sizes, risk levels, and actions. Any selection change invalidates the authorization.

The plan also records the manifest version and checksum and expires after fifteen minutes. A manifest change or expired plan invalidates cleanup authority.

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

The moved target, descendant records, and affected ancestor measurements are invalidated after successful Trash movement. Cached values are visibly labeled with their measurement time.

## Trash semantics

DexCleaner moves items to Finder Trash only. It does not empty Trash.

The app and reports must use the phrase **Moved to Trash**, not **Freed**, unless actual filesystem availability is separately measured and attributed.

## Residual filesystem race

The target is revalidated immediately before the path-based Trash call. The public API does not expose an atomic “validate this file descriptor and trash that same object” operation. This residual interval must remain documented and covered by conservative release testing.

## Mandatory audit exclusions

Large-file and top-level storage audits always prune protected user-content, cloud, project, app-state, hidden-cache, Trash, Library, and nested Git roots. User-supplied exclusions are additive only and cannot remove these mandatory privacy boundaries.
