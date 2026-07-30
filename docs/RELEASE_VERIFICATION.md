# DexCleaner Release Verification

Date: 2026-07-28 (America/Detroit)

## 1.3.2 emergency responsiveness release — 2026-07-30

- Result: passed. DexCleaner 1.3.2 was built once, installed once, observed for
  5 minutes 12 seconds during production FSEvents replay, quit normally,
  relaunched once, and remained responsive.
- Evidence: the immutable originals remain at
  `/Users/andrew/Desktop/DexCleaner-Hang-20260730T073409Z`; the indexed copy is
  `/Users/andrew/Library/Application Support/DexCleaner/Diagnostics/Hang-20260730T073409Z`.
- Root cause: the 1.3.1 main thread spent 1,945 of 3,001 samples in
  `StorageIncidentRecorder.accept`, including 1,322 samples in
  `IncidentStore.save`/`JSONEncoder` and 641 checkpoint encodes. Each replay
  event also wrote evidence, published observable state, and inserted a
  recovery Activity item. There was no dispatch-sync or semaphore deadlock:
  valid production history amplified synchronous per-event main-actor
  persistence and publication into CPU starvation.
- The copied support fixture contained 152,797 valid event records
  (50,366,669 bytes), 72 capacity samples, four incidents, and no malformed
  record. Its checkpoint was valid but unclean, so the large replay was
  legitimate.
- Correction: a dedicated replay actor drains ordered 100-event batches,
  appends evidence once per batch before checkpointing, throttles main-actor
  publication to at most every 200 ms plus meaningful boundaries, and
  coalesces recovery into one Activity entry. `AppModel` yields before starting
  replay, and opening the full window explicitly dismisses the transient
  popover.
- Focused result: 103 tests discovered; 71 unique in-scope tests executed,
  71 passed, zero failed, zero skipped. Copied-state 10,000-event replay:
  0.110 seconds, 100 durable checkpoints, two UI publications, 0.000466625
  second initial main-actor stall, 0.015188125 second maximum heartbeat
  interval. Synthetic replay: 0.075 seconds and 0.014217459 second maximum
  interval. Menu and window harness command latencies were 0.066 and 0.070
  seconds.
- Installed UI: menu popover opened and closed during active replay; the main
  window opened, interacted, closed, and reopened from the popover without
  leaving it above other apps. Installed Quit completed in 0.59 seconds.
  Exactly one process remained after the required relaunch.
- Healthy 15-second sample:
  `/Users/andrew/Library/Application Support/DexCleaner/Diagnostics/Hang-20260730T073409Z/DexCleaner-1.3.2-healthy.sample.txt`.
  The main thread spent 9,761 of 10,020 samples waiting in the normal run loop;
  `StorageIncidentRecorder.accept` was absent.
- Installed version: 1.3.2; bundle ID: `ca.westcat.DexCleaner`; strict
  signature valid. Executable SHA-256:
  `d522044f88e21c7c68c488a5abb2339e85a6acd188cc0c6073acd35f8250e282`.
  Resource-bundle content-tree SHA-256:
  `cc6d9f0549e7408d9f6998e774d9e7faa1fbc80b09dcc0af66bbdb5e41d43e45`.
  Cleanup-manifest SHA-256:
  `1a43342d4d0787d5b3d5a91af63add0f3b52b181c6ea26b31c8bcea2ab94fe4d`.
- Rollbacks remain preserved and strictly signed: 1.0.0
  `20260728T003957Z`, 1.2.2 `20260730T000000Z`, 1.3.0
  `20260730T063952Z` and `20260730T081258Z`, and 1.3.1
  `20260730T071415Z` and `20260730T074246Z`, all beneath
  `/Users/andrew/Library/Application Support/DexCleaner/Backups/`.
- Limitation: a stale duplicate bundle elsewhere on the Mac was initially
  selected by Launch Services; it was identified by executable path, quit
  without alteration, and the installed app was then launched from its exact
  `/Applications` path.
- Safety: no Quick Scan, candidate selection, Preview, cleanup, live cloud
  comparison or mutation, deep trace, reserve creation, user-content change,
  project deletion, unauthorized file movement, or Finder Trash action
  occurred. Normal launch changed only DexCleaner-owned checkpoint and
  coalesced Activity state.

## 1.3.1 final release verification — 2026-07-30

- Result: source and packaging certification passed; 1.3.1 was built once, installed once, and is running from `/Applications/DexCleaner.app`.
- Bundle ID: `ca.westcat.DexCleaner`; installed executable SHA-256: `8633ea8701094a2c880bd2a04ef0dcdc55eddb8deb7e411a21fe9f0bdbc602c8`.
- Sealed resource-bundle tree SHA-256: `4c0675a388908dd1d617cccd0c1873f88616b4c1ded05b4ba0acf70c9e52cd21`.
- Cleanup-manifest SHA-256: `1a43342d4d0787d5b3d5a91af63add0f3b52b181c6ea26b31c8bcea2ab94fe4d`.
- Signed staged and installed executables match exactly. The raw Swift product matched the staged executable before signing; ad-hoc signing legitimately changed the Mach-O hash.
- Strict signing passes for the installed app, its sealed SwiftPM resource bundle, and the 1.3.0, 1.2.2, and 1.0.0 rollback apps.
- The temporary build output was renamed away before direct candidate launch. Candidate and installed direct launches produced no resource-bundle fatal error.
- Final test inventory: 94 discovered; 63 in-scope executed; 63 passed; 0 failed; 0 skipped. Thirty-one cleanup/Trash or unrelated legacy discoveries were intentionally excluded.
- Native FSEvents stream construction and lifecycle are dependency-injected and production-used. Stream factory 6/6; recovery 5/5.
- Cancellation is production-wired for comparison, deep trace, reserve creation, and focused investigation. Atomic pattern/report operations do not expose a functional Cancel control.
- Patterns 6/6, comparator 5/5, reserve 7/7, deep trace 3/3, compatibility 3/3, Activity Center 1/1, operation state 1/1, separation 1/1, storage safety/monitoring 21/21.
- Eight actual production `StorageIncidentsView` PNGs render at fixed 1200×1800 with deterministic fixtures, fixed locale/timezone, Reduce Motion, accessibility metadata, distinct pixel payloads, and nonblank content. Rendered UI test 1/1.
- Installed recorder startup checkpoint: event ID `729573453` at `2026-07-30T06:42:09Z`; recovery Activity is Complete. Exactly one installed process remains.
- Launch at Login is disabled. No live emergency reserve exists; installed state is Pending Safe Conditions. Deep trace is functional but was not live-authorized.
- Rollbacks:
  - 1.3.0: `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260730T063952Z/DexCleaner.app`
  - 1.2.2: `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260730T000000Z/DexCleaner.app`
  - 1.0.0: `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260728T003957Z/DexCleaner.app`
- Installed proof limitations: the one accessibility bridge attempt timed out and was not retried; the installed executable ran isolated synthetic UI fixtures, while synthetic Markdown/JSON report output was certified in focused writer tests rather than by forcing a new installed live incident. Large FSEvents replay can fill the bounded 100-entry Activity retention window with per-event completions.
- No live cleanup, selection, Preview, Quick Scan, cloud comparison/mutation, broad disk crawl, privileged trace, live reserve creation, user-content change, project deletion, unauthorized file movement, or Finder Trash action occurred. Normal app launch updated only DexCleaner-owned checkpoint, capacity, and Activity state.

## Scope and identity

- Canonical worktree: `/Users/andrew/Library/Mobile Documents/com~apple~CloudDocs/Projects/DexCleaner_MacOS.nosync/repo`
- Branch and base commit: `codex/final-storage-forensics` at `9883f6b20929824c38226e6e7cf0850d1f144d17`
- Hardware and operating system: Apple Silicon Mac, macOS 26.5.2, 8 GB unified memory.
- Installed application: `/Applications/DexCleaner.app`, version `1.2.0`, bundle ID `ca.westcat.DexCleaner`.
- Installed executable SHA-256: `077de12894d1dbfccf46c343fd88386e7125e7c682c33d49a1aaecc68e38574e`.
- Installed manifest SHA-256: `1a43342d4d0787d5b3d5a91af63add0f3b52b181c6ea26b31c8bcea2ab94fe4d`.

## Completed evidence

- The one required `DEXCLEANER_RUN_TRASH_TEST=1 make bug-sweep` run passed: 30 tests, 0 failures.  It covered the controlled Finder Trash round trip, restoration, plan integrity and expiry, cancellation, manifest binding, exclusions, redaction, static no-permanent-delete guards, and the build/parser gates.
- A separately created synthetic cache fixture completed its allowed round trip.  Its final record is `final_state=restored` and `trash_was_emptied=false` at `/Users/andrew/Library/Application Support/DexCleaner/TestFixtures/roundtrip-9A7BBDB1-1E88-400E-AB69-60ED857E3DB5/FINAL_STATE.txt`.
- The installed bundle passed `codesign --verify --deep --strict` after installation.  The original 1.0.0 rollback bundle at `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260728T003957Z/DexCleaner.app` remains present and passes the same verification.  Its original executable SHA-256 is `b858c26418f7a2cbeebbd1e56e454b765002be8d22571529a7ab43ccadb3e1d4`.
- One installed app process is running from `/Applications/DexCleaner.app/Contents/MacOS/DexCleaner`.
- A deliberate installed-app Quick Scan completed without a broad disk audit: status `Partial`, 6 candidates, 4 audit items, 13 protected items, and 1 issue.  The interface states that the issue must be reviewed before relying on missing results.  No item was selected, previewed, or moved.
- The installed interface reports `Available for work`, immediately free capacity, total capacity, used estimate, and potentially purgeable capacity from the shared native capacity model.  The launch-at-login switch remained off.
- Continuation verification on 2026-07-27 23:27 EDT: a one-time release rebuild produced the installed executable hash above; the installed and release-candidate executables matched exactly; the installed bundle passed `plutil -lint` and strict signature verification.
- The obsolete visible estimator was identified as the standalone `/Users/andrew/.disk_monitor/DiskMonitor`, launched by `com.andrew.diskmonitor`.  That exact LaunchAgent is disabled and booted out; its executable and plist remain intact for reversal.  No other menu-bar utility was changed.  See `OBSOLETE_ESTIMATOR_RETIREMENT.md`.
- The two focused regressions passed: `testFreshCapacityExpiresToCachedAtTheDocumentedInterval` and `testCapacityTimestampsUseTheRequestedMacTimezoneConsistently`.  Fresh capacity expires to Cached after 60 seconds, and displayed timestamps use the Mac's autoupdating timezone consistently.
- The fixed installed app opened visibly.  A direct Refresh Capacity action produced a fresh 15.82 GB reading without starting a scan.  After the documented 60-second interval elapsed, the same installed UI changed its measurement label from `Fresh` to `Cached` without running a scan.  The subsequent deliberate Quick Scan remained bounded and safe: `Partial`, 6 candidates, 4 audit items, 13 protected items, 1 issue, zero selected, and no preview or move.
- The user-provided manual screen recording completed the status-bar popover check.  The popover presentation now requests only the lightweight capacity refresh; it does not invoke Quick Scan.

## Packaging note

The temporary release-candidate location was moved outside the iCloud-synchronised worktree because Finder/FileProvider metadata repeatedly attached extended attributes there and made a strict signature check unstable.  The application actually installed in `/Applications` was re-signed and strictly verified in place.  The installed bundle—not the transient staging copy—is the release authority.

## 1.2.0 bounded monitoring update

- Capacity history is local-only at `~/Library/Application Support/DexCleaner/CapacityHistory/`, with raw recent history, hourly/daily compaction, malformed-line recovery, a 64 MiB growth guard, and explicit JSON/CSV export.
- Capacity samples use the lightweight native provider only. Launch, popover, manual refresh, periodic, wake, Quick Scan completion, cleanup completion, and synthetic triggers are recorded; sampling never starts a broad scan or cleanup.
- The focused `StorageMonitoringTests` run completed using an isolated compiler cache after a stale path-bound Swift cache prevented the first attempt from reaching tests. It covers history persistence/recovery/compaction, sampling coalescing, alert episodes, watchlist comparison/significant-drop logic, and forecast guards.
- Alert configuration persists locally. Defaults are warning below 10 GB immediately free, recovery at or above 12 GB, and critical below 5 GB. Alerts are hysteretic, rate-limited, snoozable, and never invoke cleanup.
- Storage Drivers are read-only diagnostics and explicit watchlist measurements only. They do not create cleanup candidates or mutation authority.
- `/Applications/DexCleaner.app` version 1.2.0 passed version inspection and `codesign --verify --deep --strict`. One running process was confirmed from that bundle. Its launch sample was Fresh at `2026-07-28T04:27:55Z`, equivalent to `2026-07-28 00:27:55 EDT`; display formatting uses the Mac's current timezone.
- Installed accessibility inspection confirmed that DexCleaner opened visibly, exposed Refresh Capacity and Quick Scan, and kept Move to Trash disabled before preview. No Quick Scan, preview, cleanup, or Trash action was invoked during this validation. The desktop control bridge lost its native pipe while switching to Storage History, while the app process remained alive.
- The rollback bundle remains `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260728T003957Z/DexCleaner.app`, version 1.0.0, and passed strict signature verification after the 1.2.0 installation.

## Hash provenance and bounded installed-UI check

- The previously recorded `c5df4ae0f9aed801e0bb54eb3747452585b62f1a2b2183298d1ff77ac0fd3e4f` was a copied 1.1.0 documentation value, not the 1.2.0 installed executable hash. The installed 1.2.0 executable is `077de12894d1dbfccf46c343fd88386e7125e7c682c33d49a1aaecc68e38574e`.
- The raw current release-build executable is `bfd3bcc7d78cd78b06d0283f374491eefd1115efb163ab40d4e5fc07e4f7029a`. It differs because the installation script copies that raw Swift product into the app bundle and applies ad-hoc code signing twice; the installed hash therefore includes the Mach-O signature. No rebuild or replacement was required.
- The preserved 1.0.0 rollback executable is `b858c26418f7a2cbeebbd1e56e454b765002be8d22571529a7ab43ccadb3e1d4`. Strict verification still passes.
- The installed bundle has no embedded framework, helper executable, or private library containing application logic: its only executable is `Contents/MacOS/DexCleaner` with hash `077de…574e`; its only app resource is the cleanup manifest. Installed and raw release executable both contain the matching 1.2.0 logic markers `Storage History`, `Storage Drivers`, `Find What Changed`, `Low-storage thresholds`, `Application launch`, and `Open Storage History`.
- Direct installed inspection confirmed version 1.2.0 metadata, a strict valid signature, and exactly one process from `/Applications/DexCleaner.app`. The prior visible-window inspection confirmed Refresh Capacity, Quick Scan, disabled Move to Trash before preview, and no active scan or cleanup.
- The desktop UI-control bridge failed before it could inspect Storage History or Storage Drivers in this pass. Manual confirmation remains required for the 24-hour sparkline/insufficient-history presentation, all range choices, both plotted series, watchlist and Find What Changed controls, JSON/CSV export buttons, default threshold controls, row-body toggling, Close Preview, tactile pressed feedback, and inert disabled Move to Trash. No Quick Scan, driver crawl, selection, preview, cleanup, file movement, or Trash action occurred in this pass.

## Safety boundary and residual risk

- No live user cleanup was performed.  No real user cache, Homebrew, package-manager, cloud, project, or protected data was moved.  The user's existing Trash was not emptied.
- The desktop accessibility service still does not expose status-bar extras for independent automation on this host.  The completed manual recording is the direct popover evidence; automated coverage proves its refresh-only wiring and freshness/timestamp policy.
- Capacity remains a live, filesystem-dependent measurement.  The baseline showed a material difference between immediate-free and Foundation available-for-work capacity; the app deliberately displays these as separate values rather than claiming they are interchangeable.
- Revalidation before a move is path and filesystem-identity based.  It substantially narrows, but cannot eliminate, a race with an external process changing a target between checks.

## Release disposition

The installed application is signed, running, and safe to use for review and preview.  Exactly one custom storage menu-bar utility remains: DexCleaner.  A future real cleanup requires an explicit user-approved batch and should begin with the app's fresh scan and immutable preview.  Do not infer freed bytes from items merely moved to Finder Trash.

## 1.2.2 resource-bundle packaging repair

- Root cause: the 1.2.1 script copied `DexCleaner_DexCleanerCore.bundle` only to `Contents/Resources` while the generated SwiftPM accessor used an app-root fallback and then a temporary build path. The installed app could therefore fatal after that build path disappeared.
- A root-level arbitrary bundle cannot pass strict macOS app signing: it is rejected as unsealed. The repair uses a valid, independently sealed bundle at `/Applications/DexCleaner.app/Contents/Resources/DexCleaner_DexCleanerCore.bundle`, with `CleanupManifest.json` at `Contents/Resources/CleanupManifest.json`, and an installed-app manifest resolver that selects that sealed location. Package-test and CLI builds retain `Bundle.module`.
- The release script now fails closed before replacement if the generated bundle or manifest is absent, unreadable, absent after signing, or differs from the release product before signing. It seals the nested resource bundle before sealing the app.
- Installed version: `1.2.2`; executable SHA-256: `0e740229d8285cef47acdee70b4ec6956f57bd56809b158cd10a7cae0cdbf785`; installed manifest SHA-256: `1a43342d4d0787d5b3d5a91af63add0f3b52b181c6ea26b31c8bcea2ab94fe4d`.
- Two focused packaging-resource checks were invoked (the second after the signing-compatible layout correction). The final traced packaging run completed one installation. Earlier packaging invocations stopped before replacement or failed fail-closed during signing; no failed attempt changed `/Applications`.
- The temporary release-build path was moved aside and is not used by the installed launch. Direct invocation of `/Applications/DexCleaner.app/Contents/MacOS/DexCleaner` produced no resource-bundle fatal error. One installed process remains running. Strict signatures pass for the installed bundle and preserved 1.0.0 rollback bundle.
- Direct UI inspection opened the main window and exposed Storage History and Storage Drivers navigation. The desktop UI bridge closed its native pipe after the History selection attempt; manual confirmation remains required that History and Drivers finish rendering in this repaired build. No scan, Preview, cleanup, driver operation, file movement, or Trash action occurred.

## 1.2.1 correction and polish

- Installed version: `1.2.1`; installed executable SHA-256: `d27a2eb6f6a8f3e89e8f7d5b52078165adb4c02161cc64db813b4b3df933b189`.
- Chart marks now carry explicit metric series identities, so Available for work and Immediately free cannot connect as one alternating line. Available is solid; Immediately free is dashed; the chart has a legend, GB axis labels, labeled warning/critical rules, raw-versus-aggregate styling, and a keyboard/VoiceOver-friendly measurement inspector.
- History cards name both current and starting metrics and their individual net changes. Normal five-minute cadence and modest drift are not material gaps; gaps longer than two cadences plus one minute remain visible without invented samples.
- The low-storage banner now separates the episode-start value from the current Immediately free value. Alerts remain non-destructive and preserve the persisted episode state.
- Menu-bar actions have full labels in a wider bounded popover. The reusable native button style provides restrained hover/pressed contrast, depth, and motion while Reduce Motion suppresses scale motion. Preview has a visible styled Close action and Escape dismissal remains wired.
- Candidate rows retain the checkbox and have expanded selection semantics; embedded Reveal/Copy controls remain separate. No protected or audit row is made selectable.
- Reports now derive their version from the active application bundle and use Status, Scan, Preview, or Cleanup naming according to actual state; a no-scan report no longer claims to be a scan report.
- Storage Drivers gained an explicit user-triggered Refresh Storage Drivers control; it remains read-only and was not invoked for verification.
- One grouped focused `StorageMonitoringTests` run completed after the correction. It covers series separation, gap tolerance, alert-episode start/reset, report naming, and prior local monitoring cases. No broad suite, scan, cleanup, driver crawl, file movement, or Trash action ran.
- Two release-build invocations occurred: the first compiled but did not complete packaging; the permitted packaging-only correction completed one replacement installation. The installed bundle and preserved 1.0.0 rollback bundle both pass strict signature verification. One `/Applications/DexCleaner.app` process is running; DiskMonitor is absent.
- Manual confirmation remains required for detailed popover/history hover appearance, button hover/press rendering, full-row pointer interaction, notification delivery/action routing, and Storage Drivers add/remove/reveal behavior because the desktop UI bridge was unavailable. Synthetic alert-engine and driver-comparison coverage remains local and non-destructive.

## 1.3.0 Storage Incident Recorder installation

- Installed app: `/Applications/DexCleaner.app`, version `1.3.0`, bundle ID `ca.westcat.DexCleaner`; installed executable SHA-256: `e802d786fa0ec068ba50eeee493a1854ad0e3dbf4b8f2695d1bf12239e8a9aa6`.
- The sealed SwiftPM resource bundle is present at `Contents/Resources/DexCleaner_DexCleanerCore.bundle`; its archived SHA-256 is `6ca0e57a10c41ced843ef058347a931a9df19309f03ea3ec7d91915aa7b94091`. Its cleanup-manifest SHA-256 remains `1a43342d4d0787d5b3d5a91af63add0f3b52b181c6ea26b31c8bcea2ab94fe4d`.
- One release build completed after a Swift compiler correction. The one replacement installation first preserved 1.2.2 at `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260730T000000Z/DexCleaner.app`, then installed 1.3.0. The 1.2.2 and original 1.0.0 rollback bundles both pass strict signature verification.
- The focused recorder test command completed after its earlier compile-correction attempts. It covers synthetic threshold/sleep-wake behaviour, coalescing, symlink-safe allocation measurement, cloud-placeholder accounting, isolated incident report persistence, diagnostic/cleanup separation, and the fixed emergency-reserve path.
- Direct executable launch showed no resource-bundle fatal error. A launch-services relaunch kept exactly one `/Applications/DexCleaner.app/Contents/MacOS/DexCleaner` process alive. The installed app, both rollback copies, and the packaged resource bundle passed strict signing/presence checks.
- The UI accessibility bridge timed out before it could inspect the Storage Incidents presentation. This leaves the new visual UI interaction as manual-confirmation work; it does not invalidate the direct installed-launch, signing, or focused-core evidence.
- No storage audit, Quick Scan, driver crawl, preview, cleanup, candidate selection, file movement, cloud-state change, user-data change, or Finder Trash operation occurred during the 1.3.0 release validation. See `docs/STORAGE_INCIDENT_RECORDER_1_3_0.md` for scope and deliberate limitations.

## 1.3.1 completion attempt — release gate failed closed

- Source declares 1.3.1 and the affected production/test targets compile.
- Forty-two unique relevant tests pass with zero failures, including 5 production-path recovery tests, the existing 8-test recovery-report baseline, the existing diagnostic/cleanup-separation regression, patterns, local/cloud comparison, emergency reserve, deep trace, compatibility, Activity Center, operation state, UI-state certification, and 21 relevant safety/monitoring/report regressions.
- Release certification did not pass because native FSEvent stream construction is not yet behind the required injected stream factory and the eight UI artifacts are deterministic state documents rather than rendered actual SwiftUI production views. Additional exhaustive requested fixture gaps are recorded in `docs/STORAGE_INCIDENT_RECORDER_1_3_1_COMPLETION.md`.
- No release build, package, replacement, or relaunch occurred. Installed `/Applications/DexCleaner.app` remains signed version 1.3.0 with executable SHA-256 `e802d786fa0ec068ba50eeee493a1854ad0e3dbf4b8f2695d1bf12239e8a9aa6`; exactly one installed process was running at final inspection.
- The 1.2.2 rollback at `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260730T000000Z/DexCleaner.app` and 1.0.0 rollback at `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260728T003957Z/DexCleaner.app` remain strictly signature-valid.
- No live cleanup, cloud mutation, broad disk scan, privileged trace, live reserve creation, user-data change, project deletion, unauthorized file movement, or Finder Trash action occurred.
