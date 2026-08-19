# Bounded Cleanup and Prevention — GrokGitHubDaily and 1132 Fixer

Date: 2026-07-28, America/Detroit.

## Executive result

| Measure | Result |
|---|---:|
| GrokGitHubDaily repository-cache directories moved to Finder Trash | 41 directories; 1,777,936 KiB (1,820,606,464 bytes) |
| 1132 Fixer valid backups moved to Finder Trash | 33 directories; 2,778,132 KiB (2,844,807,168 bytes) |
| Total moved to Finder Trash | 4,556,068 KiB (4,665,413,632 bytes; about 4.35 GiB) |
| Current Grok cache / repository-cache size | 2,692 KiB / 0 KiB |
| Current 1132 backup-root size | 706,680 KiB |
| Structurally valid 1132 backups retained | 6; 686,308 KiB |
| Immediate available-space change | -7,136 KiB (9,715,452 KiB before; 9,708,316 KiB after) |

The immediate free-space reading did not rise because all candidates remain in Finder Trash on the same APFS volume; background filesystem activity also occurred during the pass. The expected eventual reclaim if the user later empties only these verified Trash items is about **4.35 GiB**. Finder Trash was not emptied.

Two recurrence mechanisms are installed and enabled:

1. Grok's existing daily LaunchAgent remains enabled and resumed at 23:45. A new, separate daily cache-budget LaunchAgent runs at 23:55 and enforces a 500 MiB ceiling on only `cache/repositories`, refusing to act while Grok is active.
2. A 1132 backup-retention LaunchAgent runs once daily at 12:15. It validates only permitted structural metadata, refuses to act if 1132 Fixer or Zoom has a file open in the backup tree, retains the newest three valid backups plus permitted weekly representatives, and moves other valid candidates to Finder Trash.

Both helper LaunchAgents were loaded, enabled, and not running at validation. Grok's scheduler pause marker was removed only after the budget helper had been validated.

## GrokGitHubDaily

### Owner, scheduler, and prior policy

Owner: the local GrokGitHubDaily automation at `~/Library/Application Support/GrokGitHubDaily`.

The exact active scheduler is the enabled user LaunchAgent `com.andrew.grok-github-daily`, loaded from `~/Library/LaunchAgents/com.andrew.grok-github-daily.plist`. It invokes `bin/run_daily_review.sh` daily at 23:45 local time. The supported `bin/pause.sh` control was used before cache movement; no Grok process was active. `bin/resume.sh` restored the scheduler after prevention was enabled.

The configuration declared `cache_retention_days: 90`. The field is documented but no implementation consumed it for cache pruning, so it was not relabeled as an effective policy. The application does implement `exclude_repositories` during inventory selection.

### Effective prevention policy

- Added the verified repository identifier `DexDictate_MacOS` to the supported `exclude_repositories` list. This prevents the large active DexDictate checkout from being cloned into Grok's cache on future inventory runs.
- Installed `maintenance/enforce-cache-budget.zsh`, scoped exclusively to `cache/repositories`.
- Installed and enabled `com.andrew.grok-github-daily-cache-retention`, scheduled daily at 23:55.
- The helper requires a valid non-symlink cache root, refuses while Grok's review/sync processes are active, moves only direct cached repository directories, chooses oldest directories first, uses collision-safe Finder Trash names, records only path/size/timestamp/result, and enforces a 512,000 KiB (500 MiB) cap.

The source tool did not provide a working retention implementation. The helper is therefore the effective bounded-retention mechanism; it does not invent an unsupported configuration field.

### Exact paths moved to Finder Trash

All items below were moved from `~/Library/Application Support/GrokGitHubDaily/cache/repositories/` to uniquely named paths in `~/.Trash/` and remain there for rollback:

```text
westkitty
Starsilk_Chronicles
starlight-acre
Impossible_Physics_Arcade
Homo_Goetia
Image_Gen
spanish_translator
SpaceWise_Android
DexDictate_MacOS
DexCleaner_MacOS
Westcat_Familiar
StarSilk_Maker
orbital_tomb_tour
ClearCut
Causal-Civilization-Engine
SpaceWise
c_chase
DexKeeper_Bot
S-mores-Katamari
OSINT_Box
Guy_Cast
Parable
welcome_to_vibe_coding
ChatGPT_Bible_Repo
DexDictate_Android
He-Maker
DexDraw_vNext
DexCast
BigMac_Voice_Tools
AnimateDex
Project_Sentinel
Fixer_Fixed
DexGate
EndlessGrok
DexSort_App
DexSort
AndrewOS_Dashboard
AndrewOS_MacBridge
Starsilk_Cartographer
SelfSame
AndrewOS
```

The cache itself is now 2,692 KiB, with `cache/repositories` at 0 KiB. No refresh, fetch, or repository operation was triggered. All 41 logged Trash rollback paths exist.

### Rollback and uninstall

To restore a clone, use Finder to move its uniquely named `--grok-cache--` item from `~/.Trash` back into `~/Library/Application Support/GrokGitHubDaily/cache/repositories/`, restoring its original directory name. The cache is non-authoritative and may also be recreated by a later normal Grok run.

To disable the cap policy, boot out `com.andrew.grok-github-daily-cache-retention` from the current user's launchd domain, then remove its plist and `maintenance/enforce-cache-budget.zsh`. To stop Grok altogether, use its supported `bin/pause.sh`; the original scheduler remains independently managed by its existing pause/resume scripts.

## 1132 Fixer

### Baseline and structural validation

Before cleanup, `~/Library/Application Support/1132Fixer/Backups` occupied 3,484,796 KiB. The permitted inspection was limited to direct-child directory names, timestamps, allocated sizes, owner/permissions, top-level filenames, and open-file status. No backup file contents or private records were opened.

There were 39 structurally valid current-format timestamped backups. Validity required the current timestamp name pattern and a nonempty top-level `us.zoom.xos.plist`; this is a structural existence/size check only. Two timestamp-style directories did not meet that check and were left untouched. Two legacy-format directories were outside the expected current pattern and were also left untouched.

The active 1132 Fixer process was observed, but no 1132 Fixer or Zoom file open inside the backup tree was found. The retention helper independently repeats that open-file guard and fails closed if it becomes true.

### Retained set

The helper retained the newest three valid backups:

```text
2026-07-28T08-44-21Z
2026-07-26T07-51-21Z
2026-07-26T06-54-27Z
```

It also retained one valid representative for each applicable prior calendar week, without duplicating a newest-three backup:

```text
2026-07-19T11-27-04Z
2026-07-12T08-28-46Z
2026-07-03T16-44-02Z
```

The July 20–26 representative is already within the newest-three protection. The six valid retained backups total 686,308 KiB, below the 1 GiB cap.

The following were intentionally left untouched because they are malformed under the current structural rule or use the older naming format:

```text
2026-06-06T10-46-53Z
2026-07-03T16-44-48Z
20260606-071403
20260606-074443
```

### Exact valid backup directories moved to Finder Trash

All items below were moved from `~/Library/Application Support/1132Fixer/Backups/` to uniquely named `--1132-backup--` paths in `~/.Trash/`. Their logged rollback paths were verified to exist.

```text
2026-06-06T10-35-34Z
2026-06-06T12-05-40Z
2026-06-25T01-39-27Z
2026-06-25T01-55-07Z
2026-06-25T02-00-21Z
2026-06-25T10-17-54Z
2026-06-27T02-54-08Z
2026-06-27T06-20-04Z
2026-06-29T06-11-23Z
2026-06-29T12-28-24Z
2026-06-29T19-35-46Z
2026-06-29T23-13-09Z
2026-06-30T09-51-34Z
2026-06-30T10-26-32Z
2026-07-03T11-27-32Z
2026-07-03T16-43-45Z
2026-07-06T08-16-59Z
2026-07-06T12-56-28Z
2026-07-07T09-47-58Z
2026-07-09T09-41-25Z
2026-07-09T14-21-57Z
2026-07-10T06-40-34Z
2026-07-11T14-03-04Z
2026-07-14T15-23-59Z
2026-07-18T05-09-18Z
2026-07-18T07-38-02Z
2026-07-18T07-38-33Z
2026-07-18T17-32-23Z
2026-07-19T06-29-04Z
2026-07-19T06-30-10Z
2026-07-22T10-10-29Z
2026-07-25T04-48-16Z
2026-07-25T14-24-41Z
```

### Prevention, validation, and rollback

The installed external helper is `Backups/.retention/enforce-retention.zsh`; it was chosen instead of modifying the opaque installed application or rebuilding it. It:

- operates only in the exact backup root;
- ignores nonmatching directory names;
- requires at least three structurally valid current-format backups;
- checks for open 1132 Fixer/Zoom files in that tree and refuses if found;
- preserves newest three and at most one valid representative for each of the preceding four calendar weeks;
- removes oldest weekly representatives first if the retained set would exceed 1 GiB;
- fails closed if newest three alone would exceed the cap;
- moves only valid nonretained backup directories to collision-safe Finder Trash paths; and
- logs only timestamp, backup path, size, retained count, and result.

`com.andrew.1132-fixer-backup-retention` is enabled as a daily 12:15 user LaunchAgent. Its post-cleanup dry-run reported `valid=6`, `invalid=2`, `retained=6`, `retained-size=686308KiB`, and no further eligible candidate.

To roll back, use Finder to move a desired `--1132-backup--` item from `~/.Trash` back into `~/Library/Application Support/1132Fixer/Backups/`, restoring its original directory name. To disable prevention, boot out `com.andrew.1132-fixer-backup-retention` from the current user's launchd domain, then remove its plist and the `Backups/.retention` helper directory. Neither action touches live Zoom data.

## Safety confirmation

- No permanent deletion occurred. Finder Trash was not emptied.
- No live Zoom data changed, and Zoom was not launched.
- No private 1132 backup contents were inspected; only permitted top-level structural metadata was used.
- No actual development repository or Git checkout outside Grok's cache was modified. No fetch or cache refresh was run.
- No cloud-provider, system, Homebrew, Claude, DexDictate, Codex, Gemini, Antigravity, APFS, or unrelated application state was changed.
- No unrelated build, cleanup, update, installation, storage audit, or application launch occurred.
- The only persistent changes were the authorized Grok exclusion, the two narrowly scoped retention helpers, their user LaunchAgents, their minimal logs, the requested report, and the target directories moved into Finder Trash.

## Remaining limitations

- The 90-day Grok configuration field remains present but is not an effective pruning implementation; the 500 MiB helper is the effective retention bound.
- The four untouched 1132 directories require a future, separately authorized compatibility review if their status is to be determined. They are not included in the retained-valid-backup count.
- Space will not be reliably returned to the filesystem until the user elects to empty the verified Finder Trash items. This pass intentionally did not do that.
