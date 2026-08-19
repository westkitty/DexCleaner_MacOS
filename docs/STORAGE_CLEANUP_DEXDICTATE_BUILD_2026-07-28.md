# DexDictate Swift Build Cleanup — 2026-07-28

## Executive result

**Cleanup succeeded.** Only the complete regeneratable Swift build-output directory was moved to Finder Trash.

- Original path: `/Users/andrew/DexDictate_MacOS.nosync/.build`
- Exact Finder Trash rollback path: `/Users/andrew/.Trash/.build--dexdictate-build--20260728T120000`
- Allocated size moved: 4,914,184,192 bytes (4,799,008 KiB; about 4.58 GiB)
- Logical size moved: 4,893,845,504 bytes (4,779,146 KiB; about 4.56 GiB)
- Expected eventual reclaim after the user empties this isolated Trash item: approximately 4,914,184,192 allocated bytes (about 4.58 GiB)
- Immediate available-space reading before move: 15,404,512 KiB
- Immediate available-space reading after move: 15,404,600 KiB
- The 88 KiB reading change is not a reclaim measurement: the item remains on the same APFS volume in Finder Trash. Actual reclaim is expected only after Empty Trash.
- Finder Trash is prepared for one normal Empty Trash action: it contains exactly this one DexDictate cleanup directory and no unrelated user items.
- Unrelated Trash items held elsewhere for this cleanup: 0 items, 0 bytes. No new holding folder or holding manifest was needed because Trash was empty at precheck.

## Safety verification

Precheck established that `/Users/andrew/DexDictate_MacOS.nosync/.build` was a real directory, not a symbolic link; it was ignored by the project’s `.gitignore` rule; and it had no open files. No Swift compiler, Xcode build, DexDictate, Visual Studio Code, Claude, Codex, or other build process had an open handle under the target. Background Xcode Git file-monitor daemons were present but did not hold the target and are not build processes.

The preflight and post-move measurements match exactly:

| Measure | Preflight | Trash item |
|---|---:|---:|
| Allocated size | 4,799,008 KiB | 4,799,008 KiB |
| Logical size | 4,779,146 KiB | 4,779,146 KiB |

Git state was unchanged across the move:

- Branch: `speech-engine-exploration-benchmarks`
- Status fingerprint: unchanged (`c2a1213874a3564fd8011175442e246f5a52e76e2a5444fceb5109976866524a`)
- Status line count: unchanged (5)
- Worktree fingerprint: unchanged (`b7eee9dc11837e5fb47d5e4925c948c150bce2acc582401f1af34cc7b988a858`)
- Registered worktree count: unchanged (6)

Confirmed:

- Only `.build` was moved.
- No permanent deletion occurred.
- Finder Trash was not emptied.
- No build or test was run.
- No source, asset, model, benchmark, log outside `.build`, `.claude`, `.resurrection`, Git, worktree, application-support, or installed-application state changed.
- The original `.build` path is absent; the exact Trash rollback path exists; Finder Trash contains one user item with one `--dexdictate-build--` marker.

## Consequence and rollback

`.build` is ignored standard Swift build output and is regeneratable. The next DexDictate build will recreate its dependencies and products, and may take longer than a warm/incremental build.

Before Empty Trash, restore this exact item in Finder:

`/Users/andrew/.Trash/.build--dexdictate-build--20260728T120000`

Move it back to:

`/Users/andrew/DexDictate_MacOS.nosync/.build`

No unrelated prior Trash items were present during this cleanup, so there is no holding-folder location for this pass.
