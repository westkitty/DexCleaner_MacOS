# Storage Finalization — 2026-07-28

## Final result

This final bounded pass completed the only newly established safe action: npm’s official package-content-cache cleanup.

- **Actions completed:** npm package-content cache verified and cleaned through npm’s supported command; recurrence controls verified.
- **Permanent reclaim in this pass:** 505,856,000 bytes (494,000 KiB; about 482 MiB) of npm package-content cache.
- **Final immediately free space:** 18,042,364 KiB (about 17.21 GiB) on the Data volume.
- **Final available-for-work space:** 18,042,364 KiB (about 17.21 GiB), as reported by the Data-volume filesystem available-block count.
- **Finder Trash:** no verified Trash targets were created in this pass. Finder Trash had zero direct items before finalization and remained empty afterward. A normal Finder empty-Trash request was issued, returned Finder error `-128` because there was nothing to empty, and did not delete anything.
- **Unrelated Trash items held:** none. The final holding folder was not created because Trash was empty before this pass.
- **Final holding-folder path:** not applicable.

The pre-pass available-space reading was 18,848,320 KiB. The final reading is lower despite the 494,000 KiB npm cache removal, so the free-space delta is not used as a reclaim calculation; unrelated APFS/background activity occurred during the pass. The managed-item measurement is the reclaim figure above.

For context only, the earlier cleanup report recorded 9,715,452 KiB available before the initial Grok/1132 cleanup. The current reading is 8,326,912 KiB higher (about 7.94 GiB). This is an observed filesystem reading, not an attribution of every intervening change to this cleanup project.

## Homebrew

- Homebrew version: `6.0.12`
- Formulae before/after: 264 / 264
- Casks before/after: 53 / 53
- `/opt/homebrew` allocation before/after: 12,295,344 KiB / 12,295,344 KiB
- Homebrew cache allocation before/after: 22,832 KiB / 22,832 KiB
- Dry run used: `brew cleanup -n`
- Result: the dry run produced only warnings that the most recent versions of many formulae were not installed; it did not produce an eligible, exact removal list.
- Supported cleanup command used: none.
- Items removed: none.
- Bytes reclaimed: 0 bytes.
- Skipped: `brew cleanup` and `brew autoremove`, because no fully established eligible candidate set was available. No update, upgrade, uninstall, or manual Homebrew-tree removal occurred.

## npm

- Precheck: `~/.npm` was a real directory; target-scoped open-handle inspection found no writer; no npm, pnpm, Yarn, or package-install/build process was active.
- Supported verification used: `npm cache verify`
- Verification result: 979 content entries verified, representing 499,804,967 content bytes in `~/.npm/_cacache`.
- Supported cleanup command used: `npm cache clean --force`
- Package-content cache allocation before: 494,000 KiB.
- Package-content cache allocation after: absent (0 KiB).
- Whole `~/.npm` allocation before/after: 1,359,632 KiB / 865,632 KiB.
- Reclaimed: 494,000 KiB (505,856,000 bytes).
- Untouched: `~/.npmrc`, credentials, authentication tokens, repositories, project `node_modules`, package lockfiles, and source trees. `_logs`, `_npx`, `_libvips`, `_prebuilds`, and other non-cache/uncertain state were left in place. Future npm package operations may re-download cached dependencies.

## Application backups

Six visibly named backup bundles were inspected using shallow app-bundle metadata only. None met the required canonical-current-app condition, so none was removed.

| Candidate retained | Bundle identifier | Version | Allocated size | Reason retained |
|---|---|---:|---:|---|
| `/Applications/Draw Things.app.bak-20260326` | `com.liuliu.draw-things` | 1.20260207.0 | 312,488 KiB | No canonical `/Applications/Draw Things.app` exists. |
| `/Applications/Hermes Agent.app.backup-20260516-115724` | `com.nousresearch.hermes` | 0.4.1 | 324,448 KiB | No canonical `/Applications/Hermes Agent.app` exists. |
| `/Applications/Hermes Agent.app.backup-20260525-163500` | `com.nousresearch.hermes` | 0.4.3 | 335,740 KiB | No canonical `/Applications/Hermes Agent.app` exists. |
| `/Applications/Hermes Agent.app.backup-before-token-badge-asar-patch-20260526_151326` | `com.nousresearch.hermes` | 0.5.1 | 394,812 KiB | No canonical `/Applications/Hermes Agent.app` exists. |
| `/Applications/Hermes Agent.app.backup-before-token-badge-patch-20260526_151105` | `com.nousresearch.hermes` | 0.5.1 | 394,812 KiB | No canonical `/Applications/Hermes Agent.app` exists. |
| `/Applications/Hermes Agent.app.backup-suspect-fathah-20260607-120417` | `com.nousresearch.hermes` | 0.5.6 | 483,312 KiB | No canonical `/Applications/Hermes Agent.app` exists. |

All six had only the standard top-level `Contents` directory, no shallow `Documents` directory, no open handles, and no backup-executable process. Those facts do not override the missing canonical-app requirement. Application-backup bytes reclaimed: 0 bytes.

## DexCleaner-authorized caches

The installed DexCleaner application (`ca.westcat.DexCleaner` 1.2.2) contains a sealed exact-path cleanup manifest. Its manifest is safe in principle, but the installed application requires an interactive preview and durable authorization ledger before cleanup; no supported noninteractive manifest-only path was established.

- Candidates cleaned: none.
- Bytes reclaimed: 0 bytes.
- Result: skipped without modifying DexCleaner or creating a cleanup plan.

## Recurrence controls

- `com.andrew.grok-github-daily-cache-retention`: enabled.
- `com.andrew.1132-fixer-backup-retention`: enabled.
- Grok’s DexDictate exclusion remains present in the owner’s configuration records.
- Grok repository cache: 0 KiB, within the 512,000 KiB (500 MiB) cap.
- Structurally valid retained 1132 backups: 6 directories, 686,308 KiB, within the 1 GiB cap.

No recurrence configuration was changed in this pass.

## Protected and unresolved areas

| Classification | Areas left untouched |
|---|---|
| Completed | Grok cache retention, 1132 backup retention, DexDictate Swift build cleanup, npm package-content-cache cleanup. |
| Protected | Claude VM/session state, Codex sessions/worktrees/configuration, Gemini/Antigravity state, DexDictate source and worktrees, current Homebrew packages, application backups without canonical replacements. |
| System-managed | CloudDocs, FileProvider and Google DriveFS state, cloud placeholders, APFS volumes and snapshots. |
| Unresolved | `~/.cache/codex-runtimes` and non-cache npm temporary state such as `_npx`; neither was modified. |

## Safety confirmation

- No current package or application was intentionally removed.
- No user session, credential, repository, worktree, cloud database, or unique application state changed.
- No updates or upgrades occurred.
- No unrelated Trash item was permanently deleted; none existed in Trash during this pass.
- No holding folder was needed; no held item was modified.
- No broad disk scan occurred.
- No Git cleanup command, build, test, installation, application launch, or redesign was performed.

This storage-maintenance process is complete. No further cleanup action is required by this finalization pass.
