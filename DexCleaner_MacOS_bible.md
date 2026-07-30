# DexCleaner Project Bible

## Canonical state

- Canonical repository: `/Users/andrew/Library/Mobile Documents/com~apple~CloudDocs/Projects/DexCleaner_MacOS.nosync/repo`
- Working branch: `codex/final-storage-forensics`
- Starting commit: `9883f6b20929824c38226e6e7cf0850d1f144d17`
- Preserved user work: the pre-existing untracked `.resurrection/` files remain untouched.
- Competing copies:
  - `/Users/andrew/Documents/Codex/2026-06-14/clone-dexcleaner-for-me/work/DexCleaner_MacOS` is an older, partially inaccessible session checkout.
  - `/Users/andrew/Library/Application Support/GrokGitHubDaily/cache/repositories/DexCleaner_MacOS` is a clean application cache, not the canonical worktree.

## Installed application and rollback

- Original installed app: `/Applications/DexCleaner.app`
- Original version: `1.0.0`
- Bundle identifier: `ca.westcat.DexCleaner`
- Original executable SHA-256: `b858c26418f7a2cbeebbd1e56e454b765002be8d22571529a7ab43ccadb3e1d4`
- Verified rollback copy: `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260728T003957Z/DexCleaner.app`
- Rollback copy size: 1,863,680 bytes as measured by `du`
- Rollback validation: recursive comparison passed; code signature verification passed; executable hash matches the original.
- Rollback command after quitting DexCleaner:
  `ditto --rsrc --extattr --acl "/Users/andrew/Library/Application Support/DexCleaner/Backups/20260728T003957Z/DexCleaner.app" "/Applications/DexCleaner.app"`

## Capacity baseline

- APFS container capacity: 245,107,195,904 bytes.
- APFS container unallocated capacity at baseline: 12,797,050,880 bytes.
- Filesystem immediately free capacity at baseline: 12,813,844,480 bytes.
- Foundation general available capacity at baseline: 18,383,200,256 bytes.
- Foundation capacity available for important usage at baseline: 19,290,870,976 bytes.
- Foundation opportunistic capacity at baseline: 6,143,791,104 bytes.
- Build and rollback reserve is adequate. The existing repository including build artifacts measured about 326 MB.

## Release decisions

- The menu-bar metric is `Available for work`, sourced from
  `volumeAvailableCapacityForImportantUsage`.
- Immediately free capacity remains a separate figure.
- Native capacity APIs are the frequent-refresh source. Filesystem-stat values are a lightweight cross-check and disagreement is visible.
- Quick Scan is limited to exact manifest targets, protected/audit markers, capacity, and access checks.
- No background or threshold-triggered cleanup is permitted.
- Cleanup remains fail-closed, preview-bound, Finder Trash only, and initially unselected.
- A pending operation ledger entry must be durable before any Trash movement.
- The release candidate must preserve a single mutation authority and activate an existing instance when a duplicate launch occurs.
- Live user cleanup is outside this run. Only a newly created synthetic fixture may be moved and restored.

## Adversarial review pass 1

Release blockers found before implementation freeze:

1. Menu-bar title did not display capacity.
2. Capacity reporting used formatted `df` output rather than the shared native storage model.
3. Quick Scan included broad storage-map and large-file work.
4. Ledger records were appended only after operations and could not reconcile interruptions.
5. Duplicate-process mutation authority was not explicit.
6. Build/package scripts permanently removed prior artifacts.
7. The mandatory synthetic Trash and restoration evidence was absent.

The bounded implementation addresses those blockers without adding scheduling,
automatic cleanup, duplicate management, a disk image, telemetry, or cloud
features.

## Current state

DexCleaner 1.3.2 is installed at `/Applications/DexCleaner.app`, strictly
signed, and running as exactly one process. Its executable SHA-256 is
`d522044f88e21c7c68c488a5abb2339e85a6acd188cc0c6073acd35f8250e282`;
its sealed resource-bundle content-tree SHA-256 is
`cc6d9f0549e7408d9f6998e774d9e7faa1fbc80b09dcc0af66bbdb5e41d43e45`.
The certified cleanup-manifest SHA-256 remains
`1a43342d4d0787d5b3d5a91af63add0f3b52b181c6ea26b31c8bcea2ab94fe4d`.

The 1.3.1 installed hang was main-actor starvation during a valid large
FSEvents replay, not a lock deadlock or malformed support state. Version 1.3.2
moves replay work to a dedicated actor, persists ordered 100-event batches,
checkpoints after evidence, coalesces recovery into one Activity item, and
throttles observable publication. The copied 10,000-event production-state
fixture completed in 0.110 seconds with a 0.015188125-second maximum heartbeat
interval. The bounded release ledger is 71/71 passing from 103 discovered
tests.

Installed verification covered 5 minutes 12 seconds of replay, popover
open/close, window interaction and reopen, a 0.59-second Quit, one relaunch,
one process, and a healthy 15-second sample dominated by normal run-loop wait.
No Quick Scan, cleanup, candidate selection, Preview, cloud mutation,
privileged trace, reserve creation, user-content movement, or Finder Trash
action occurred.

Strictly signed rollbacks remain at:

- 1.0.0: `Backups/20260728T003957Z/DexCleaner.app`
- 1.2.2: `Backups/20260730T000000Z/DexCleaner.app`
- 1.3.0: `Backups/20260730T063952Z/DexCleaner.app` and
  `Backups/20260730T081258Z/DexCleaner.app`
- 1.3.1: `Backups/20260730T071415Z/DexCleaner.app` and
  `Backups/20260730T074246Z/DexCleaner.app`

All paths above are beneath
`/Users/andrew/Library/Application Support/DexCleaner/`.

Historical 1.2.0 state follows.

The 1.2.0 bounded monitoring update was installed at `/Applications/DexCleaner.app`.
It adds local capacity history, capacity-only sampling triggers, read-only Storage
Drivers, explicit local export, persisted low-storage alerts, and history UI.
Opening the menu-bar popover remains capacity-refresh-only; it does not start a
Quick Scan. Fresh capacity expires after the documented 60-second interval and
the display uses the current Mac timezone. The obsolete DiskMonitor LaunchAgent
remains disabled and unloaded, leaving DexCleaner as the one custom storage utility.
The installed 1.2.0 bundle and the 1.0.0 rollback bundle both passed strict
signature verification. No 1.2.0 validation action selected, previewed, moved,
or deleted user data.

## Hash provenance checkpoint

- The prior `c5df4ae0f9aed801e0bb54eb3747452585b62f1a2b2183298d1ff77ac0fd3e4f`
  value was copied forward from 1.1.0 documentation. It was not the installed
  1.2.0 executable.
- Installed 1.2.0 executable SHA-256:
  `077de12894d1dbfccf46c343fd88386e7125e7c682c33d49a1aaecc68e38574e`.
- Current raw release-build executable SHA-256:
  `bfd3bcc7d78cd78b06d0283f374491eefd1115efb163ab40d4e5fc07e4f7029a`.
  It differs only because installation copies then ad-hoc-signs the raw product;
  the installed binary has the Mach-O code-signature payload. No rebuild was
  needed.
- The installed binary itself contains the 1.2.0 Storage History, Storage
  Drivers, Find What Changed, low-storage-threshold, and launch-sampling logic
  markers also present in the raw release product. There are no embedded app
  frameworks or helper executables.
- The installed UI bridge was unavailable for the detailed history/driver
  interaction check. Obtain a brief manual confirmation of those controls before
  treating their presentation as runtime-proven. No scan, cleanup, file movement,
  or Trash action occurred during the hash checkpoint.

## 1.2.1 correction checkpoint

- `/Applications/DexCleaner.app` is version 1.2.1, executable SHA-256
  `d27a2eb6f6a8f3e89e8f7d5b52078165adb4c02161cc64db813b4b3df933b189`.
- Storage History now uses explicit independent Available-for-work and
  Immediately-free series, a legend, GB axis/rule labels, a measurement
  inspector, unambiguous summary cards, and cadence-tolerant material-gap logic.
- Low-storage state records both current Immediately free and the episode-start
  value. Button feedback is native and restrained, honors Reduce Motion, and
  does not affect disabled controls or cleanup authority.
- Reports obtain the active bundle version and use state-aware Status/Scan/
  Preview/Cleanup naming. Storage Drivers remain read-only and explicit.
- One focused monitoring test run and one successful packaging-only correction
  followed the initial compiled-but-unpackaged release attempt. Exactly one
  installed 1.2.1 process is running; DiskMonitor remains absent. No live scan,
  cleanup, file movement, or Trash emptying occurred. The 1.0.0 rollback bundle
  remains strictly signature-valid.
- Manual UI confirmation is still needed for hover presentation, pointer row
  interaction, notification delivery/actions, and complete Storage Drivers
  interactions because the desktop UI bridge was unavailable.

## 1.2.2 packaging repair

- The 1.2.1 crash came from a SwiftPM resource-bundle lookup mismatch after the
  temporary build directory disappeared. A root-level bundle was tested but is
  incompatible with strict macOS app signing because root content is unsealed.
- The installed app now resolves its sealed resource bundle at
  `DexCleaner.app/Contents/Resources/DexCleaner_DexCleanerCore.bundle`, with
  `CleanupManifest.json` inside its `Contents/Resources`. Installed-app manifest
  resolution uses that exact path; SwiftPM tests and CLI builds still use
  `Bundle.module`.
- Version 1.2.2 executable SHA-256:
  `0e740229d8285cef47acdee70b4ec6956f57bd56809b158cd10a7cae0cdbf785`.
  Manifest SHA-256: `1a43342d4d0787d5b3d5a91af63add0f3b52b181c6ea26b31c8bcea2ab94fe4d`.
- Packaging now preflights bundle presence, manifest presence, staged-product
  equality, nested-bundle sealing, and signed-bundle retention before replacement.
  The direct installed executable launch succeeded without the prior fatal error
  while the release build directory was disregarded.
- One installed process remains and both installed and preserved 1.0.0 rollback
  bundles pass strict signature verification. No DexCleaner data, scan target,
  operation ledger, report, watchlist, cleanup target, or Trash item was touched.
- Main-window navigation was directly exposed; manual History/Drivers render
  confirmation remains because the desktop UI bridge closed after selecting
  Storage History.

## 1.3.0 Storage Incident Recorder checkpoint

- Installed app: `/Applications/DexCleaner.app`, version `1.3.0`, executable SHA-256 `e802d786fa0ec068ba50eeee493a1854ad0e3dbf4b8f2695d1bf12239e8a9aa6`.

## 1.3.1 completion attempt

- The unified `StorageIncident` source model now carries optional backward-compatible Filesystem Events recovery, repeated-pattern, local/cloud comparison, emergency-reserve, and deep-trace evidence.
- Recovery commits synchronize event evidence before the durable checkpoint and advance in-memory state only afterward. The dependency container owns clocks, volume identity, persistence, corruption preservation, replay availability, fallback baseline, incident attachment, and Activity Center entry construction.
- The comparator is resident-only and bounded to 1,000 files, 1 GiB of optional hash reads, 60 seconds, and 100 differences. It refuses low-space hashing, placeholders/dataless files, symlinks, and filesystem crossings.
- The emergency reserve owns only `~/Library/Application Support/DexCleaner/EmergencyReserve/reserve.bin`, uses a durable ownership record, verifies physical allocation, and is the only automatic release path.
- Deep trace is explicit, metadata-only, output-capped, redacted, and limited to 60 seconds; denial does not disable normal recording.
- Raw event retention is two 64 MiB segments; incidents remain capped at 730 and Activity Center at 100.
- Forty-two relevant tests pass. The release gate remains failed because the native stream factory is not injected and UI artifacts are not rendered actual production SwiftUI. Installed 1.3.0 was intentionally preserved. See `docs/STORAGE_INCIDENT_RECORDER_1_3_1_COMPLETION.md`.
- The recorder is local-only, diagnostic-only, and separate from cleanup authority. It provides lightweight five-minute capacity sampling, incident thresholds/hysteresis and sleep/wake comparison, coalesced FSEvents evidence, bounded allocated-size measurement, placeholder-aware cloud accounting, per-incident reports, and Activity Center/progress state.
- Reports and evidence remain in the app-owned IncidentRecorder store. Diagnostic results cannot select candidates, invoke Quick Scan, or move user files. Cloud inspection does not materialize or alter provider state.
- The emergency reserve is intentionally eligibility-only in this checkpoint: it has one fixed DexCleaner-owned path and no allocation/release implementation. Local/cloud duplicate comparison, repeated-pattern classification, deep trace, and persistent FSEvents resume-id recovery remain follow-up work rather than release claims.
- One release build and one installation completed after compiler-only corrections. The 1.2.2 app is preserved at `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260730T000000Z/DexCleaner.app`; it and the original 1.0.0 rollback pass strict signature verification. The installed bundle and its sealed resource bundle pass strict signature/presence checks.
- Direct executable launch had no resource-bundle error; Launch Services kept one installed process alive. The desktop accessibility bridge timed out before it could inspect the Storage Incidents UI, so that presentation remains manual confirmation. No validation action ran a scan, driver crawl, preview, cleanup, file move, cloud-state change, or Trash operation.
The verified 1.0.0 rollback bundle remains available.  See
`docs/RELEASE_VERIFICATION.md` and `docs/OBSOLETE_ESTIMATOR_RETIREMENT.md`.

Do not run live cleanup without a newly approved, explicitly reviewed batch.
The manual recording completed the visible menu-bar check; desktop accessibility
still cannot enumerate status-bar extras for a duplicate automated click-through.
