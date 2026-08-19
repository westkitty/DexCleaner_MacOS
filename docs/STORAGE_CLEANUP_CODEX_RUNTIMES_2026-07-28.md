# Codex Runtime Cache Review — 2026-07-28

## Executive result

- **Classification:** Unresolved — left untouched.
- **Cleanup succeeded:** No move was authorized; the target remains in place.
- **Target:** `/Users/andrew/.cache/codex-runtimes`
- **Items moved:** none.
- **Allocated bytes moved:** 0 bytes.
- **Logical bytes moved:** 0 bytes.
- **Expected eventual reclaim:** 0 bytes now. The measured target allocation is 1,621,073,920 bytes (1,583,080 KiB; about 1.51 GiB), but it is not approved for removal.
- **Trash rollback paths:** none; no item was moved to Finder Trash.
- **Trash prepared for one-click Empty Trash:** No. Finder Trash was empty at precheck, but no verified Codex cleanup item was placed there.
- **Unrelated Trash items held:** none; no holding folder or holding manifest was needed.
- **Unresolved questions:** the supported removal/rebuild mechanism for this exact cache path; whether the active Codex application will need the current primary runtime on a later operation; whether `codex-primary-runtime/plugins` is entirely downloaded runtime material; and the exact automatic re-download/recreation behavior and cost.

## Evidence

### Runtime-cache structure and age

`/Users/andrew/.cache/codex-runtimes` is a real directory, not a symbolic link.

- Created: 2026-07-02 03:16:29 -0400
- Last modified: 2026-07-27 20:37:16 -0400
- Allocated size: 1,583,080 KiB (1,621,073,920 bytes)
- Logical size: 1,525,977 KiB (1,562,600,448 bytes)

Its direct children are:

| Direct child | Type | Allocated size | Created | Last modified |
|---|---|---:|---|---|
| `.DS_Store` | regular file | 8 KiB | 2026-07-10 05:48:04 -0400 | 2026-07-20 23:00:29 -0400 |
| `codex-primary-runtime` | directory | 1,583,072 KiB | 2026-07-27 17:41:12 -0400 | 2026-07-27 17:41:12 -0400 |

The shallow layout of `codex-primary-runtime` contains `dependencies` and `plugins`. There are no multiple version directories and no proven obsolete runtime version. The only substantial runtime is recent and appears to be the current primary runtime.

### Open handles and active processes

- A target-scoped `lsof` check found no process with an open file under `codex-runtimes`.
- Codex desktop/application-service processes are currently active, including the app server serving this task, but their command lines and the handle check do not establish that they currently use this cache.
- No standalone `codex-runtime` process or process command line rooted in `codex-runtimes` was found.

### Regeneratability and user-state evidence

The direct structure is consistent with a runtime bundle, but that alone does not prove that the whole current primary runtime is safely disposable. The permitted official OpenAI documentation check used the current Codex manual. It documents runtime concepts and pinned runtimes for published SDKs, but it does not document this local cache path, a user-supported purge/reset operation, automatic re-download behavior, or the contents of `codex-primary-runtime/plugins`.

No session, worktree, credential, or configuration path was inspected. Shallow metadata baselines for `/Users/andrew/.codex/sessions`, `/Users/andrew/.codex/worktrees`, and `/Users/andrew/.codex/config.toml` were recorded without changing them. Their existence cannot prove that this cache contains no coupled user state. Because the required positive proof is absent, the safe decision is to retain the cache.

## Safety verification

- No sessions changed.
- No worktrees changed.
- No credentials or configuration changed.
- No repository, Git state, or project state was touched.
- No build, test, installation, update, Codex launch, or cache recreation was performed.
- No permanent deletion occurred.
- Finder Trash was not emptied.
- No Finder Trash item, holding folder, or holding manifest was created for this pass.

## Consequence and rollback

No runtime cache was moved, so no rollback action is required.

If a future focused review establishes a supported purge/rebuild mechanism and proves the current primary runtime is fully regeneratable, a later Codex use may need to recreate or download runtime files. That behavior, its cost, and the exact safe removal path were not established here and must not be assumed.
