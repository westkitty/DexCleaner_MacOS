# Storage Forensics — 2026-07-28

## Scope and safety boundary

One bounded, read-only inspection was performed on 2026-07-28 (America/Detroit). No files were deleted, moved, renamed, compressed, mounted, rebuilt, installed, scanned by DexCleaner, sent to Trash, or otherwise changed. No cleanup utility, provider reset, Git cleanup, or application feature was launched.

Sizes below are allocated directory measurements unless noted. Decimal gigabytes (GB) are shown alongside binary gibibytes (GiB) where useful. A directory total can overlap another row; nested totals are explicitly marked and must not be added twice.

## Executive assessment

The largest measured discretionary growth source is the 1132 Fixer backup history: 3.33 GiB retained in timestamped directories created by an upstream app that appears to make a full backup at every Zoom start and has no observed retention policy. The largest immediately regeneratable opportunity, on the evidence collected, is GrokGitHubDaily's 1.70 GiB cache of read-only repository clones. Its own documentation states that the cache can be recreated.

The largest high-value opportunities needing review rather than deletion are Claude's 6.37 GiB virtual-machine bundle, DexDictate's 4.58 GiB Swift build output, and Codex's 1.51 GiB runtime cache. Cloud/FileProvider state, active worktrees, sessions, Gemini/Antigravity state, Homebrew, and APFS volumes are not safe manual-cleanup targets.

| Path or category | Allocated size | Owner / purpose | State and growth mechanism | Confidence | Safe reclaim now | Possible reclaim after review | Risk / next action |
|---|---:|---|---|---|---:|---:|---|
| `~/Library/Application Support/1132Fixer/Backups` | 3.33 GiB (3.57 GB) | 1132 Fixer; Zoom preference backups | Timestamped backups from 2026-06-06 through late July; repeated full-backup behavior, no retention observed | High on size/pattern; medium on restore safety | 0 | about 2.8 GiB if complete restore points are validated and newest three retained | Opaque app data. Establish app-supported retention or a conservative validated retention helper; do not manually prune first. |
| `~/Library/Application Support/Claude` | 7.79 GiB (8.37 GB) | Claude Desktop 1.24012.9 state | `claudevm.bundle` is 6.37 GiB; local-agent sessions and VM state are also present. Bundle last modified 2026-07-22. | High on contents; medium on feature dependency | 0 | up to 6.37 GiB only after confirming Claude local-agent/Cowork VM can be intentionally rebuilt or re-downloaded | Protected application state. Confirm supported removal/rebuild path with Claude, quit it, then act only if the feature is no longer required. |
| CloudDocs session database + FileProvider | 6.25 GiB combined, non-overlapping roots | Apple `bird` / iCloud Drive and File Provider services | `CloudDocs/session/db` is 3.07 GiB; FileProvider is 3.18 GiB. Provider domains were recently refreshed. | High | 0 | Unknown; provider-controlled only | Do not delete databases or UUID roots. Use supported “remove download”/eviction controls only after sync and file-availability checks. |
| Google Drive local state | about 1.13 GiB, included in cloud-related roots above | Google Drive File Provider / DriveFS | DriveFS 0.86 GiB and CloudStorage 0.27 GiB. Registered domain for `digitalghosts269@gmail.com` sampled `Enabled=true`, `Replicated=true`, `Connected=false`. | High on allocation/domain state | 0 | Provider-dependent | A registered but disconnected domain is not evidence that its local state is disposable. Reconnect or inspect through Google Drive before any supported eviction/reset. |
| GrokGitHubDaily cache | 1.70 GiB (1.82 GB) | Local scheduled read-only repository clones | 1.69 GiB is under `repositories`; largest is a cached DexDictate clone at about 0.99 GiB. Recent log activity shows the scheduled daily run on 2026-07-27. Config uses a 90-day cache retention period. | High | 1.70 GiB, after pausing/disabling the service and using its supported cache handling | 1.70 GiB | Re-creatable clone cache, but active scheduled service will regrow it. Set a smaller supported retention/budget or exclude large duplicate repositories before clearing it. |
| `~/DexDictate_MacOS.nosync` | 13.31 GiB (14.29 GB) | Active development checkout | `.build` is 4.58 GiB; `.claude` is 4.20 GiB. Branch is `speech-engine-exploration-benchmarks`; tracked `.resurrection` files are modified; several Git worktrees exist. | High | 0 | 4.58 GiB for `.build` after worktree/session review; more only after inventory | Active and dirty project. Preserve checkout, altered recovery metadata, and worktrees. A normal rebuild would recreate `.build`, but it is not a safe unattended deletion target today. |
| `~/.codex` | 4.82 GiB (5.18 GB) | Codex sessions, worktrees, and runtime cache | Sessions 1.76 GiB; worktrees 1.64 GiB; runtimes 1.51 GiB. Existing DexDictate worktrees are visible in this state. | High on totals; medium on individual retention | 0 | about 1.51 GiB runtimes after confirming a supported cache policy; orphan worktrees require separate review | Protect sessions and active worktrees. Do not remove by age alone; verify worktree ownership and Codex-supported runtime cleanup first. |
| Gemini / Antigravity state | about 4.84 GiB combined | Gemini and Antigravity application/agent state | `~/.gemini` is 4.20 GiB and contains `antigravity` (2.11 GiB, nested); `~/.antigravity_archive` is 0.58 GiB. | High on totals; low on internal retention semantics | 0 | Unknown | Treat as protected until vendor-supported cache/archive controls and active-session status are known. |
| `/opt/homebrew` | about 12 GB (prior supplied breakdown) | Homebrew package manager | Cellar about 7.6 GB, `lib` 1.9 GB, `share` 1.2 GB, Caskroom 0.74 GB. The bounded output did not capture a Homebrew dry-run reclaim total. | Medium | Unknown | Unknown, pending `brew cleanup -n` in a future authorized pass | Do not manually remove formula, cask, or library directories. Use Homebrew's own dry-run, then its supported cleanup only if approved. |
| APFS non-Data volumes | about 27.2 GB, not a cleanup estimate | System, Preboot, Recovery, VM | System 12.6 GB, Preboot 9.0 GB, Recovery 1.3 GB, VM 4.3 GB. | High | 0 | 0 by this investigation | System-managed. Do not attempt volume or snapshot surgery. No local Time Machine snapshots were listed in this sample. |
| DexCleaner Cloud local-state measurement | 154.55 GB reported logical/partial; not a physical allocation measurement | DexCleaner Storage Drivers | Current code recursively totals regular-file `fileSize` below `~/Library/CloudStorage`; it does not use allocated/resident size and may count dataless cloud placeholders' logical length. | High on code path; high that report is not comparable to physical allocation | Not applicable | Measurement correction, not disk reclamation | Change future measurement to distinguish logical, allocated/resident, and incomplete/provider metadata. Do not treat 154.55 GB as local reclaimable storage. |

## A. 1132 Fixer backup history

`~/Library/Application Support/1132Fixer/Backups` occupies 3,484,796 KiB (3.33 GiB). The directory contains timestamped backup points beginning 2026-06-06 and continuing into late July. The sampled layouts contain Zoom preference files, which is consistent with a full preference snapshot rather than a lightweight log.

Both `/Applications/1132 Fixer.app` and a separate build artifact were located. This investigation did not read or modify the installed app's configuration, did not run the app, and did not attempt a restore. The evidence supports the stated recurrence mechanism: a complete backup is created on each Start Zoom event without observed retention.

Recommended recurrence fix: add retention to the upstream app if it has a supported setting. Otherwise, use a narrowly scoped helper only after a separate approval: validate that a backup is complete, refuse to act while 1132 Fixer is open, retain at least the newest three valid backup points, preserve a 30-day recovery window, and cap the directory at 1 GB. That policy would likely free roughly 2.8 GiB from the current history, but it is **not** an immediate safe-deletion recommendation until a restore point has been validated.

## B. Claude Desktop virtual machine and state

Claude Desktop is present as `/Applications/Claude.app`, bundle identifier `com.anthropic.claudefordesktop`, version 1.24012.9. Its application-support root is 7.79 GiB. The principal item is:

- `vm_bundles/claudevm.bundle`: 6.37 GiB
- `rootfs.img`: 5.15 GiB
- `rootfs.img.zst`: 1.19 GiB
- `sessiondata.img`: about 25 MiB
- local-agent-mode sessions: about 0.50 GiB

The simultaneous compressed and expanded root filesystem strongly indicates a local VM/runtime image. It may be required by Claude's local-agent or Cowork capability and could need a large re-download/rebuild if removed. It was last modified 2026-07-22, while other Claude state is more recent. No conclusion is made about current use or open handles from this bounded collection.

Treat this as **review required**. The viable future path is to determine whether the feature is still needed, establish the supported way to reconstruct it, quit Claude, then remove it only through that documented mechanism. It is potentially the largest individual reclaim, but not a safe one.

## C. CloudDocs, FileProvider, and Google Drive

The cloud-related on-disk state is real local allocation, but it is mostly provider metadata/database state rather than a reliable list of user files:

- `~/Library/Application Support/CloudDocs/session/db`: 3.07 GiB
- `~/Library/Application Support/FileProvider`: 3.18 GiB
- `~/Library/CloudStorage`: 0.27 GiB
- `~/Library/Application Support/Google/DriveFS`: 0.86 GiB

Apple iCloud Drive, Photos, and Google Drive File Provider domains exist. Their provider roots were freshly touched during the sampled day. The Google domain is enabled and replicated but was sampled with `Connected=false`; that is a reason to review the account/provider state, not an authorization to erase its storage. The dated Google Drive directory is tiny and not the cause of the allocation.

There is no safe manual cleanup here. Do not delete FileProvider UUID directories, CloudDocs session databases, DriveFS data, provider plists, or cloud-placeholder files. A future approved pass may use provider-supported removal of downloaded copies after confirming that every intended file remains synced and retrievable. The current evidence does not establish which UUID database maps to each provider, nor a safe physical reclaim estimate.

## D. GrokGitHubDaily local repository cache

`~/Library/Application Support/GrokGitHubDaily/Cache` occupies 1.70 GiB, nearly all in `repositories`. The largest cached clone is DexDictate at about 0.99 GiB; other clones include c_chase and Spanish repositories. The service is active: its log records a run on 2026-07-27, and its supplied schedule is daily at 23:45 America/Detroit.

The tool's local README describes these as read-only automation clones that can be recreated. This is therefore the only reclaim category classified as safely regeneratable from the collected evidence. It still must be paused/disabled first, otherwise it will return with the next scheduled run. Its existing 90-day retention explains the accumulation.

Future recurrence fix: reduce cache retention and/or impose a cache-size budget through GrokGitHubDaily's own configuration, and exclude large repositories that already have a local working checkout. Clear the cache only after the schedule is paused and only through the tool's intended mechanism.

## E. DexDictate checkout, build artifacts, and worktrees

`~/DexDictate_MacOS.nosync` uses 13.31 GiB. The straightforward build-output candidate is `.build` at 4.58 GiB; it is ordinary Swift build output and would be regenerated by a later local build. That recovery cost was not measured.

This is not a safe immediate cleanup target because the checkout is on `speech-engine-exploration-benchmarks`, has modified tracked `.resurrection` files, and has multiple Codex and Claude Git worktrees. `.claude` itself is 4.20 GiB and contains workflow/worktree state that cannot be classified as cache without a separate inventory.

Future sequence: preserve a Git/worktree inventory and dirty-state record, close or explicitly retain each worktree, then decide whether to remove only `.build`. Do not use `git clean`, remove `.resurrection`, or delete worktree roots as a substitute for this review.

## F. Codex sessions, worktrees, and runtimes

`~/.codex` is 4.82 GiB: sessions 1.76 GiB, worktrees 1.64 GiB, and runtimes 1.51 GiB. Session history and existing worktrees are evidence/provenance and may support currently active work. They are protected in this assessment.

The runtime portion is plausibly regeneratable, but no confirmed supported retention/cleanup control was collected. The conservative reclaim estimate is zero until that mechanism is established. A future focused review may recover approximately 1.51 GiB of runtimes and separately identify genuinely orphaned worktrees; it must not age-prune session history or delete worktrees by directory name.

## G. Gemini and Antigravity

The combined non-overlapping total is approximately 4.84 GiB: `~/.gemini` is 4.20 GiB (including nested `antigravity` at 2.11 GiB), `~/.antigravity` is 83 MiB, and `~/.antigravity_archive` is 0.58 GiB. The contents and supported retention semantics were intentionally not explored beyond these directory totals.

Classify all of this as high-protection application/agent state. No storage estimate here is approved for removal. First establish whether the archive is vendor-managed history, whether either agent has active sessions, and whether a supported cache/archive control exists.

## H. Homebrew

The supplied prior breakdown places `/opt/homebrew` at roughly 12 GB, including Cellar 7.6 GB, `lib` 1.9 GB, `share` 1.2 GB, and Caskroom 0.74 GB. This bounded collection did not produce a dry-run Homebrew cleanup total, so no reclaim number is claimed.

Homebrew is a package-manager-owned tree. In a future approved maintenance pass, run `brew cleanup -n`, review the exact candidates, and then use Homebrew's own cleanup command if approved. Do not manually remove Cellar, Caskroom, libraries, or shared resources.

## APFS reconciliation

APFS reports a 245.1 GB container with 234.0 GB in use and 11.1 GB unallocated. The Data volume alone reports 206.7 GB in use, while the prior ordinary live-file total was about 185 GB. That leaves roughly 21.7 GB within the Data-volume accounting that ordinary file traversal did not explain. Likely contributors include hidden or permission-limited data, filesystem metadata/allocation behavior, indexes, purgeable/provider-managed material, and other files not represented by a simple live-file sum. This investigation did not run a full-disk or privileged traversal, so that portion remains unresolved.

The remaining APFS use is not in the Data volume and therefore should not be compared to a home-directory/file-tree total:

| APFS volume | In-use size |
|---|---:|
| System (sealed) | 12.6 GB |
| Preboot | 9.0 GB |
| Recovery | 1.3 GB |
| VM | 4.3 GB |
| **Non-Data total** | **about 27.2 GB** |

No local Time Machine snapshots were listed in the captured APFS snapshot sample. Do not attempt to reduce System, Preboot, Recovery, or VM volumes manually.

## DexCleaner Cloud-local-state defect

DexCleaner's Storage Driver catalog defines Cloud local state as `~/Library/CloudStorage`. Its driver measurement recursively enumerates regular files and sums `fileSize`. That is logical file length, not physical allocated/resident size; it can therefore count cloud placeholders whose full remote content is not downloaded. The implementation also caps enumeration at 100,000 entries and reports partial state. It does not follow symbolic links, so alias-following is not the identified cause.

That makes the displayed **154.55 GB “Cloud local state / Partial”** unsuitable as a local reclaim estimate and explains why it conflicts with the approximately 1.13 GB of physically allocated Google Drive-related storage measured here. It may reflect logical cloud content across provider roots, plus incomplete enumeration; it does not demonstrate 154.55 GB of resident bytes.

Required future correction:

1. Report logical bytes (`fileSize`) separately from allocated/resident bytes (`totalFileAllocatedSize` or the platform-equivalent allocated-size resource value).
2. Identify ubiquitous items and their downloaded status, then present placeholder logical bytes separately from locally resident bytes.
3. Keep provider database/cache state as a separate, non-user-file category.
4. Surface entry-limit/incomplete status clearly and never label a logical total as “local state.”
5. Test against a provider root containing dataless placeholders and a locally pinned file before relying on the driver for cleanup decisions.

## Recommended future cleanup sequence

This is an ordered plan for a separately authorized maintenance pass. None of these actions were performed.

1. Preserve this report, take a fresh APFS free-space reading, and confirm which development/agent sessions are active.
2. Pause GrokGitHubDaily, reduce its retention/budget or exclude oversized duplicate repositories, then clear its recreatable cache through the tool's supported path. Expected reclaim: about 1.70 GiB.
3. Validate at least one 1132 Fixer restore point, add conservative retention, and retain the newest three valid backups. Likely reclaim: about 2.8 GiB.
4. Review Claude's local-agent/Cowork dependency and documented rebuild behavior. Only then consider removing the 6.37 GiB VM bundle.
5. Inventory DexDictate and Codex worktrees and dirty state. Once intentionally preserved or closed, consider only DexDictate `.build` (4.58 GiB) and a supported Codex runtime-cache cleanup (about 1.51 GiB).
6. Address cloud providers only through their user-facing supported eviction/sync controls; do not reset databases to chase space.
7. Run `brew cleanup -n` as a separate dry-run before deciding on Homebrew cleanup.

## Immediate high-value actions, ranked

1. **GrokGitHubDaily retention and cache budget** — 1.70 GiB confidently regeneratable after pause; prevents daily recurrence.
2. **1132 Fixer backup retention** — likely about 2.8 GiB after restore validation; fixes the clearest uncontrolled growth source.
3. **Claude VM decision** — up to 6.37 GiB, but only after confirming feature dependency and rebuild support.
4. **DexDictate build/worktree review** — 4.58 GiB in `.build` may be recoverable once active work is explicitly protected.
5. **Codex runtime/worktree review** — about 1.51 GiB runtime cache may be recoverable through a supported path; worktree space is separate review work.

## Estimates and uncertainty

- **Confidently reclaimable, after pausing the owning scheduler:** about **1.70 GiB** (GrokGitHubDaily cache).
- **Likely recoverable after targeted validation, without touching protected cloud/system state:** roughly **14–16 GiB** (Grok cache, conservative 1132 retention, Claude VM only if intentionally dispensable, DexDictate `.build`, and Codex runtimes). This is a review-dependent estimate, not an action list.
- **Broader possible opportunity:** roughly **20–23 GiB** only if separate worktree/archive/app-state reviews establish that additional stale material is safely disposable. This number is intentionally not treated as a forecast.
- **Unresolved accounting:** about **21.7 GB** between the prior ordinary live Data-tree total and APFS Data-volume use; additional system volumes consume about **27.2 GB** and are not ordinary user-file reclaim.

## Do not touch without a separate, specific authorization

- `~/Library/Application Support/CloudDocs/`, `~/Library/Application Support/FileProvider/`, Google DriveFS, provider UUID roots, or cloud placeholders.
- Claude VM/session state until its supported reconstruction path and feature dependency are confirmed.
- DexDictate's dirty checkout, `.resurrection` files, Claude/Codex worktrees, or any Git history; do not run Git cleanup.
- `~/.codex/sessions` or active/orphan-unknown worktrees.
- Gemini or Antigravity state/archive without vendor-supported controls.
- `/opt/homebrew` contents except via a reviewed Homebrew dry-run and supported cleanup.
- APFS System, Preboot, Recovery, VM volumes, snapshots, or Finder Trash.

## Evidence limitations

This was intentionally not a full-disk scan, privileged traversal, SQLite/provider-database analysis, Git object analysis, Homebrew cleanup dry-run, or application launch test. Open-handle/current-process status for several application-owned directories was not established by the bounded output and is recorded as unknown rather than assumed inactive. The report is therefore suitable for prioritizing a narrow future maintenance pass, not for unattended deletion.
