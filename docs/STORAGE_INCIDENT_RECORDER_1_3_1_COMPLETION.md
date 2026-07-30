# DexCleaner 1.3.1 completion and certification report

Date: 2026-07-30
Branch: `codex/final-storage-forensics`
Certification result: **Release gates passed; 1.3.1 built once, installed once, signed, launched, and verified with two bounded installed-proof limitations.**

## Post-release runtime finding

The certification result above records what passed at release time, but it is no
longer the current release disposition. Installed 1.3.1 later became
unresponsive while replaying a valid Filesystem Events backlog. The captured
sample proved that the main actor was performing per-event evidence,
checkpoint, and full Activity persistence. A copied real support-state fixture
reproduced a 20.582-second main-actor stall; a 10,000-event synthetic batch
reproduced a 24.823-second stall, 10,000 checkpoint writes, and 100 recovery
Activity entries.

DexCleaner 1.3.2 supersedes 1.3.1 with asynchronous shell-first startup, a
dedicated ordered replay actor, 100-event evidence/checkpoint batches, 200 ms
publication throttling, and one coalesced recovery Activity entry. The full
evidence, measurements, and release disposition are in
`docs/DEXCLEANER_1_3_2_RESPONSIVENESS_FIX.md`.

## Final release-gate closure

This section supersedes the earlier failed-attempt assessment retained below for audit history.

### Initial and final state

- Initial branch: `codex/final-storage-forensics`.
- Initial worktree: dirty with substantial user and prior-agent work; no reset, revert, stash, clean, rebase, branch change, or history rewrite occurred.
- Initial installed app: `/Applications/DexCleaner.app` version 1.3.0, executable SHA-256 `e802d786fa0ec068ba50eeee493a1854ad0e3dbf4b8f2695d1bf12239e8a9aa6`, one process.
- Final installed app: `/Applications/DexCleaner.app` version 1.3.1, bundle ID `ca.westcat.DexCleaner`, executable SHA-256 `8633ea8701094a2c880bd2a04ef0dcdc55eddb8deb7e411a21fe9f0bdbc602c8`, one process.
- Installed sealed resource-bundle tree SHA-256: `4c0675a388908dd1d617cccd0c1873f88616b4c1ded05b4ba0acf70c9e52cd21`.
- Installed cleanup-manifest SHA-256: `1a43342d4d0787d5b3d5a91af63add0f3b52b181c6ea26b31c8bcea2ab94fe4d`.
- Launch at Login: disabled.
- Installed reserve state: no live reserve created; Pending Safe Conditions.
- Installed deep-trace state: functional but not live-authorized during release validation.

### Files changed by the closure pass

- `Sources/DexCleanerCore/IncidentCompletion.swift`
- `Sources/DexCleanerCore/StorageIncidentRecorder.swift`
- `Sources/DexCleaner/AppModel.swift`
- `Sources/DexCleaner/DexCleanerApp.swift`
- `Sources/DexCleaner/StorageIncidentsView.swift`
- `Sources/DexCleaner/UICertificationRenderer.swift`
- `Tests/DexCleanerTests/DexCleanerTests.swift`
- `docs/verification/1.3.1/rendered/` — eight PNGs, eight accessibility metadata files, one manifest
- `docs/STORAGE_INCIDENT_RECORDER_1_3_1_COMPLETION.md`
- `docs/RELEASE_VERIFICATION.md`
- `DexCleaner_MacOS_bible.md`

All unrelated dirty and untracked paths were preserved, including `.resurrection/`.

### Native Filesystem Events stream factory

- `FSEventsRecoveryDependencies.makeStream` is the single production construction boundary.
- The native implementation wraps actual CoreServices stream creation, watched roots, starting event ID, latency, flags, dispatch queue, callback delivery, start, stop, invalidation, and release.
- The recorder retains recovery policy: normalization, duplicate suppression, evidence-before-checkpoint persistence, resume advancement, gap classification, incident updates, and Activity Center results.
- Replacement deterministically stops, invalidates, and releases the prior stream before creating another.
- Creation/start failure is visible and Partial/failed without crashing or disabling later restart.
- Sleep/wake replacement and changed-volume since-now behavior are production wired.
- User-dropped, kernel-dropped, and root-changed flags accumulate rather than being overwritten by later clean events.
- Stream callbacks cannot create cleanup authority.
- Final stream-factory tests: 6/6. Final recovery tests: 5/5.

### Cancellation

- Local/cloud comparison, bounded deep trace, emergency-reserve creation, and focused incident investigation poll a shared cancellation token at safe boundaries.
- App cancellation requests first persist `Cancelling`, then stop optional enumeration/hashing/process work.
- Reserve cancellation removes its sibling temporary file and cannot atomically finalize `reserve.bin`.
- Focused investigation retains completed measurements, marks evidence Partial/Cancelled, and writes Activity Center completion.
- Repeated-pattern refresh and report writing remain atomic and do not expose a functional Cancel button.
- Final cancellation tests: 3/3 across `DiagnosticCancellationTests` and `ShellCancellationTests`; deep-trace production cancellation is also covered in `DeepTraceTests`.

### Repeated patterns, comparator, reserve, and compatibility

- Repeated-pattern production classification now emits Recurrence reduced and Recurrence stopped, preserves installed retention controls, recognizes changing child paths at one owner root, refuses coincidental overlap, preserves contradictory evidence, and ranks simultaneous roots deterministically.
- Comparator metadata, resident reads, stable identifiers, placeholders, dataless state, filesystem identity, provider mode, low-space state, clock, limits, and cancellation are injectable. Stable identity can strengthen a bounded result; disagreement never does. Placeholder/dataless/boundary entries are not opened.
- Emergency reserve has deterministic before-write and after-partial-write cancellation, temporary cleanup, atomic finalization, physical-allocation verification, exact-path/ownership/symlink/regular-file checks, measured capacity restoration, and explicit Partial capacity evidence when remeasurement is unavailable.
- Old incidents without optional completion fields decode. Incidents with every optional field, maximum-range event IDs and byte values, Partial/Failed/Cancelled subsystems, and all Markdown/JSON sections round-trip. A malformed optional field fails closed under the current schema policy.
- Final results: patterns 6/6; comparator 5/5; reserve 7/7; compatibility 3/3; deep trace 3/3.

### Rendered production SwiftUI certification

- `UICertificationRenderer` launches only when `DEXCLEANER_UI_CERTIFICATION_OUTPUT` is present.
- It instantiates the production `AppModel` in an isolated no-startup-side-effect mode and renders the actual production `StorageIncidentsView` through `NSHostingView`.
- Fixed inputs: 1200×1800, `en_US_POSIX`, GMT, fixed dates/capacity values, light appearance, Reduce Motion enabled, animations avoided.
- The harness fails for missing, zero-sized, undersized, or insufficiently non-background output and requires eight materially distinct PNG payloads.
- Accessibility metadata includes the actual production labels for recorder status, comparison fields, Cancel, indeterminate progress, and Reduce Motion.
- Visual inspection confirmed readable production controls, determinate and indeterminate progress, elapsed time, processed counts, retained summaries, Complete/Partial/Cancelled/Failed text, diagnostic-only language, and disabled operation controls.
- Final rendered UI test: 1/1 in 31.260 seconds.

Rendered artifacts:

1. `docs/verification/1.3.1/rendered/01-recorder-armed.png`
2. `docs/verification/1.3.1/rendered/02-active-incident.png`
3. `docs/verification/1.3.1/rendered/03-fsevents-partial.png`
4. `docs/verification/1.3.1/rendered/04-strong-pattern.png`
5. `docs/verification/1.3.1/rendered/05-local-cloud-comparison.png`
6. `docs/verification/1.3.1/rendered/06-emergency-reserve.png`
7. `docs/verification/1.3.1/rendered/07-deep-trace.png`
8. `docs/verification/1.3.1/rendered/08-activity-center.png`

### Final test ledger

- Tests discovered by `swift test list`: **94**
- Unique in-scope tests executed in the final ledger: **63**
- Passed: **63**
- Failed: **0**
- Skipped by the runner: **0**
- Discovered but deliberately excluded: **31** cleanup/Trash or unrelated legacy tests outside this bounded gate.
- The prior 42 relevant recorder/monitoring/report tests are included in the 63-test final ledger.

Exact final commands:

```text
swift test list --scratch-path .build-1_3_1-release-gate
swift test --scratch-path .build-1_3_1-release-gate --filter FSEventsStreamFactoryTests
swift test --scratch-path .build-1_3_1-release-gate --filter FSEventsRecoveryTests
swift test --scratch-path .build-1_3_1-release-gate --filter RepeatedPatternTests
swift test --scratch-path .build-1_3_1-release-gate --filter LocalCloudComparisonTests
swift test --scratch-path .build-1_3_1-release-gate --filter EmergencyReserveTests
swift test --scratch-path .build-1_3_1-release-gate --filter DeepTraceTests
swift test --scratch-path .build-1_3_1-release-gate --filter DiagnosticCancellationTests
swift test --scratch-path .build-1_3_1-release-gate --filter ShellCancellationTests
swift test --scratch-path .build-1_3_1-release-gate --filter IncidentCompatibilityTests
swift test --scratch-path .build-1_3_1-release-gate --filter ActivityCenterTests
swift test --scratch-path .build-1_3_1-release-gate --filter OperationStateTests
swift test --scratch-path .build-1_3_1-release-gate --filter UICertificationTests
swift test --scratch-path .build-1_3_1-release-gate --filter DiagnosticCleanupSeparationTests
swift test --scratch-path .build-1_3_1-release-gate --filter DexCleanerSafetyTests
```

Compile corrections used: **2 of 3** — actor-safe native stream teardown; macOS read-only Reduce Motion environment injection replaced by a production-view certification initializer.

Behavior corrections used: **3 of 3** — accumulated dropped/root flags; stable-identifier comparison ordering; production-render fixture isolation and opaque background after visual inspection exposed invalid transparent artifacts.

### Packaging and installation

- Release builds: **1**.
- Packaging corrections: **0**.
- Installations: **1**.
- Installed-runtime corrections: **0**.
- Build script preflight passed generated resource-bundle presence, readability, manifest presence, pre-sign executable/manifest equality, nested sealing, app sealing, and strict signature verification.
- Raw Swift product and staged executable matched before signing. Ad-hoc signing changes Mach-O bytes; the signed staged and installed executables match exactly at SHA-256 `8633ea8701094a2c880bd2a04ef0dcdc55eddb8deb7e411a21fe9f0bdbc602c8`.
- The temporary build directory was renamed away before staged direct launch. Direct launch exited 0, rendered eight production views, and produced no resource-bundle fatal error.
- 1.3.0 rollback: `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260730T063952Z/DexCleaner.app`.
- 1.2.2 rollback: `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260730T000000Z/DexCleaner.app`.
- 1.0.0 rollback: `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260728T003957Z/DexCleaner.app`.
- Installed app, sealed resource bundle, and all three rollback apps pass strict signing.
- Launch Services started exactly one installed process. Direct installed execution after installation produced no fatal error and left one installed process.
- Recorder startup is directly evidenced by checkpoint event ID `729573453`, checkpoint time `2026-07-30T06:42:09Z`, and Complete duplicate-suppressed recovery Activity entries.

### Installed verification limitations

- The installed executable ran the isolated synthetic production-view fixtures. The focused compatibility test generated and validated synthetic Markdown and JSON reports through the same 1.3.1 writer, but a new persisted installed-app synthetic incident report was not created: doing so after installation would have required forcing a live incident or adding another release build/installation.
- The one installed-app accessibility attempt resolved `/Applications/DexCleaner.app` but timed out. It was not retried.
- The installed Activity Center can fill its 100-entry retention window with per-event FSEvents recovery completions during a large replay. This is bounded and does not affect cleanup authority, but can crowd older diagnostic summaries.

These are proof limitations, not evidence of cleanup or storage mutation. The source, packaging, signing, direct launch, production rendering, recorder startup, and rollback gates passed.

### Safety confirmation

No live cleanup, cleanup selection, cleanup Preview, Quick Scan, live cloud comparison, cloud-provider mutation, broad disk scan, privileged deep trace, live 1 GiB reserve creation, project deletion, user-content change, unauthorized file movement, or Finder Trash action occurred. The installation moved only the old signed app bundle into its authorized rollback path and copied the signed candidate into `/Applications`. Normal DexCleaner launch updated its own capacity/FSEvents checkpoint and Activity records.

## Prior failed attempt retained for history

## Initial state

- The worktree was already dirty and contained substantial uninstalled 1.3.1 work. No reset, revert, stash, clean, rebase, branch change, or history rewrite occurred.
- The source build script already declared `VERSION="1.3.1"` before this pass.
- Installed `/Applications/DexCleaner.app` was and remains version 1.3.0, bundle identifier `ca.westcat.DexCleaner`.
- Initial and final installed executable SHA-256: `e802d786fa0ec068ba50eeee493a1854ad0e3dbf4b8f2695d1bf12239e8a9aa6`.
- The installed app remained strictly signature-valid and one installed process was running at final inspection.

## Files changed in this pass

- `Sources/DexCleanerCore/IncidentCompletion.swift`
- `Sources/DexCleanerCore/StorageIncidentRecorder.swift`
- `Sources/DexCleaner/AppModel.swift`
- `Sources/DexCleaner/StorageIncidentsView.swift`
- `Tests/DexCleanerTests/DexCleanerTests.swift`
- `docs/verification/1.3.1/01-armed-recorder.md` through `08-activity-and-completion.md`
- `docs/STORAGE_INCIDENT_RECORDER_1_3_1_COMPLETION.md`
- `docs/RELEASE_VERIFICATION.md`
- `DexCleaner_MacOS_bible.md`

All other pre-existing dirty and untracked paths were preserved.

## Architecture completed

### Filesystem Events recovery

- Expanded the existing `FSEventsRecoveryDependencies` rather than introducing a competing container.
- Routed recovery clock, volume identity, checkpoint load/save, synchronized evidence append, corrupt-checkpoint preservation, replay availability, bounded fallback baseline, incident update, and Activity Center entry creation through the container.
- Enforced evidence synchronization before checkpoint persistence and checkpoint persistence before in-memory resume advancement.
- Evidence-write and checkpoint-write failures leave the recorder operational, mark recovery failed/Partial, and do not silently advance the resume identifier.
- Added explicit volume, root, history-unavailable, invalid-checkpoint, corrupt-checkpoint, fresh-baseline, sleep, wake, duplicate, and missing-interval states.
- Added 64 MiB rotating raw-event retention with one retained prior segment.

Remaining release blocker: native FSEvent stream construction and callback delivery still live inside `StorageIncidentRecorder.startFSEvents`; it was not moved behind the required injected stream factory. Dropped-user, dropped-kernel, and root-change callback flags also lack the full deterministic production-level fixture matrix.

### Repeated patterns

- Expanded the existing structured Codable pattern model with normalized path, application, executable, bundle identifier, schedule, launch, time, wake, provider, category, swap, retention, trend, supporting/contradictory observations, analysis time, history revision, completeness, and explanation.
- Added path, build output, application, schedule, launch, wake, provider, swap, time-bucket, insufficient-history, no-pattern, and conflicting-evidence classification paths.
- Persisted the current result on the incident; completion and explicit refresh use the persisted value for reports, AppModel, UI, and Activity Center.
- Added Markdown and JSON reporting and diagnostic-only UI.

Remaining release blocker: `Recurrence reduced` and `Recurrence stopped` are modeled but not emitted as top-level classifications; the exhaustive requested fixture matrix for backup, virtual machine/database, stopped/reduced, and conflicting-candidate precedence is incomplete.

### Local/cloud comparison

- Expanded the existing comparator and persisted result model with provider mode, bounds, file/directory counts, refused item counts, allocations, logical bytes, bounded paths, metadata/hash matches, coverage, limits, cancellation, low-space state, and passive disposition.
- Enforced a total 1,000-file limit, 1 GiB hash-read limit, 60-second limit, 100-difference limit, low-space refusal, symlink refusal, placeholder/dataless refusal, and filesystem-boundary refusal.
- Normalized `/var` and `/private/var` aliases before relative matching.
- Already-resident files may be hashed; provider state is never changed. Git checkouts never become duplicates based on ancestry.
- Persisted comparison results and passive dispositions in active/latest incidents and exposed them through reports, AppModel, UI, and Activity Center.

Remaining release blocker: stable-identifier matching is currently metadata agreement rather than a durable file-identifier comparison; synthetic placeholder, dataless, and cross-volume boundary fixtures are not yet injectable, and UI cancellation is not wired.

### Emergency reserve

- Implemented the exact path `~/Library/Application Support/DexCleaner/EmergencyReserve/reserve.bin`.
- Production target is 1 GiB; tests inject small targets under temporary homes.
- Creation uses a sibling temporary file, bounded nonzero writes, free-capacity checks, physical-allocation verification, regular-file and symlink checks, atomic rename, and a durable DexCleaner ownership/state record.
- Release validates the fixed path, ownership record, regular-file identity, and symlink state; it removes only `reserve.bin`, records restored bytes, and enters Waiting to Rebuild.
- App sampling may automatically release only a ready DexCleaner reserve below 2 GB. Creation remains explicit and requires 15 GB free, 30-minute stability, no active incident/operation, and safe projected capacity.
- DexCleaner self-storage is included in incident system accounting and reports.

Remaining release blocker: the requested exhaustive failure matrix for interrupted creation cleanup and injected before/after capacity remeasurement is incomplete.

### Deep trace

- Implemented a disabled-by-default, explicitly triggered, maximum-60-second `/usr/bin/fs_usage` runner with a 1 MiB output cap.
- No credentials or permanent helper are stored. Authorization failure leaves normal recording armed.
- Filtering retains write metadata related to incident paths, discards unrelated events, redacts sensitive arguments, and stores bounded summaries.
- Added authorization-required/denied, timeout, cancellation, redaction, filtering, Codable, report, UI, and Activity Center paths.

Remaining release blocker: installed authorization was deliberately not attempted, and production UI cancellation/stopping is not wired.

## Unified incident, reports, and UI

- `StorageIncident` now has backward-compatible optional `filesystemEventRecovery`, `repeatedPatterns`, `localCloudComparisons`, `emergencyReserveActivity`, and `deepTraceEvidence`.
- Markdown and JSON use the production incident model. Markdown includes incident summary, measured growth, new/expanded files, process/task/cloud evidence, Filesystem Events recovery, repeated patterns, local/cloud comparison, APFS/system state, reserve, deep trace, recommended action, limitations, and safety.
- Copy for ChatGPT uses the persisted Markdown report; Export Report reveals the persisted report.
- Activity Center retains 100 operations and exposes phase, state, elapsed time, real counts/totals, bytes, last meaningful progress, cancellation capability metadata, and completion summary.
- The Storage Incidents view exposes recorder, launch-at-login, two capacity metrics, recovery, patterns, comparison controls/results, reserve, deep trace, reports, progress, Reduce Motion, and diagnostic-only labels.
- Eight deterministic state artifacts exist under `docs/verification/1.3.1/`.

Remaining release blocker: those artifacts are deterministic production-state documents, not rendered instances of the actual SwiftUI production view. The requested rendered production-view harness was not completed, so UI certification did not pass.

## Low-space, retention, privacy, and compatibility

- Raw Filesystem Events: two bounded 64 MiB segments.
- Capacity samples: existing 210,000-record cap.
- Incidents: existing 730-record cap.
- Activity Center: 100-operation cap.
- Comparator: 1,000 files, 1 GiB hash reads, 60 seconds, 100 differences.
- Deep trace: 60 seconds and 1 MiB retained raw command output before summary.
- UI artifacts: exactly eight.
- Optional comparator hashing is disabled under critical low-space backoff.
- Reserve creation fails closed under unsafe capacity/incident/operation/stability conditions.
- Legacy incidents without any new optional fields decode successfully.
- No diagnostic model imports or receives cleanup authorization.

## Test ledger

Unique relevant tests discovered: **42**
Unique relevant tests executed: **42**
Unique passed: **42**
Unique failed: **0**
Skipped discovered tests: **0**

Focused groups:

- FSEventsRecoveryTests: 5/5
- RepeatedPatternTests: 3/3
- LocalCloudComparisonTests: 3/3
- EmergencyReserveTests: 3/3
- DeepTraceTests: 2/2
- IncidentCompatibilityTests: 1/1
- ActivityCenterTests: 1/1
- OperationStateTests: 1/1
- UICertificationTests: 1/1
- DiagnosticCleanupSeparationTests: 1/1
- DexCleanerSafetyTests relevant regression target: 21/21
- Existing recovery-report baseline: 8/8
- Existing separation regression: 1/1

Exact commands:

```text
swift test --scratch-path .build-1_3_1-final --filter FSEventsRecoveryTests
swift test --scratch-path .build-1_3_1-final --filter RepeatedPatternTests
swift test --scratch-path .build-1_3_1-final --filter LocalCloudComparisonTests
swift test --scratch-path .build-1_3_1-final --filter EmergencyReserveTests
swift test --scratch-path .build-1_3_1-final --filter DeepTraceTests
swift test --scratch-path .build-1_3_1-final --filter IncidentCompatibilityTests
swift test --scratch-path .build-1_3_1-final --filter ActivityCenterTests
swift test --scratch-path .build-1_3_1-final --filter OperationStateTests
swift test --scratch-path .build-1_3_1-final --filter UICertificationTests
swift test --scratch-path .build-1_3_1-final --filter DiagnosticCleanupSeparationTests
swift test --scratch-path .build-1_3_1-final --filter 'DexCleanerSafetyTests/(testRecoveryReport|testOlderIncident)'
swift test --scratch-path .build-1_3_1-final --filter DexCleanerSafetyTests/testIncidentReportPersistenceAndDiagnosticCleanupSeparation
swift test --scratch-path .build-1_3_1-final --filter DexCleanerSafetyTests
swift test list --scratch-path .build-1_3_1-final
```

Compile corrections: three bounded passes.
Behavior corrections: two bounded passes (resident zero-allocation handling; canonical relative-path matching).

## Packaging and installation

- Release gate: **failed closed**.
- Release build: not run.
- Packaging: not run.
- Installation: not run.
- Installed version remains 1.3.0.
- Installed process count at final inspection: 1.
- No new 1.3.0 rollback was created because replacement was forbidden by the failed gate; `/Applications/DexCleaner.app` remains the working 1.3.0 copy.
- 1.2.2 rollback: `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260730T000000Z/DexCleaner.app` — strict signature valid.
- 1.0.0 rollback: `/Users/andrew/Library/Application Support/DexCleaner/Backups/20260728T003957Z/DexCleaner.app` — strict signature valid.

## Safety confirmation

No live cleanup, cleanup selection, cleanup Preview, cloud comparison, cloud mutation, broad disk scan, privileged deep trace, live reserve creation, user-data change, project deletion, unauthorized file movement, Finder Trash action, or application replacement occurred. Temporary tests used controlled roots and small files only.
