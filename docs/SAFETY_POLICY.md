# DexCleaner safety policy

DexCleaner exists because careless low-disk cleanup can destroy app state when anything named “cache” is treated as disposable.

## Hard rule

DexCleaner is read-only until the user approves exact paths. Approved paths go to Finder Trash. Nothing is permanently deleted by default.

## Cleanup source of truth

The bundled cleanup manifest is:

```text
Sources/DexCleanerCore/Resources/CleanupManifest.json
```

The manifest is the primary cleanup source of truth. Swift fallback entries exist only so the app does not crash if the manifest cannot load.

## Allowed cleanup

A cleanup target must pass all of these:

- listed as `Safe` in the manifest
- exact canonical path match
- under the current user's home directory
- not a broad root
- not a symlink path
- not containing protected state fragments
- selected by the user
- moved to Finder Trash only

## Forbidden cleanup

Never clean these automatically:

- `~/Library/Application Support` broadly
- unknown app support folders
- `~/.cache` broadly
- browser profiles
- IDE workspace/global state
- `Local Storage`, `Session Storage`, `IndexedDB`, `Service Worker`
- keychains
- cloud storage folders
- user content folders
- project/source folders

## Git temporary packs

Git `tmp_pack_*` cleanup is allowed only when:

- file is directly under `.git/objects/pack/`
- filename starts with `tmp_pack_`
- file is regular
- file is older than 10 minutes
- no pack lock file exists
- no Git process is running
- path has no symlink component

Do not reintroduce hidden-directory-skipping scans. `.git` is hidden; skipping hidden paths breaks detection.
