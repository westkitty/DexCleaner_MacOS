# DexCleaner 1.3.2 responsiveness fix

Date: 2026-07-30
Branch: `codex/final-storage-forensics`

## User-observed failure

Installed DexCleaner 1.3.1 displayed its menu-bar popover but stopped responding
to popover dismissal, window commands, or Quit. The process remained alive. No
Quick Scan, cleanup, cloud comparison, deep trace, reserve creation, file move,
or Trash operation was involved.

## Captured evidence

- Original evidence:
  `/Users/andrew/Desktop/DexCleaner-Hang-20260730T073409Z`
- Indexed exact copy:
  `/Users/andrew/Library/Application Support/DexCleaner/Diagnostics/Hang-20260730T073409Z`
- Original sample SHA-256:
  `f40786f69f32e044d492b8fadfb935bc60ea9aed17e74ae7f10c6bfcbaf06c01`
- Original log SHA-256:
  `8398e0dfdcf8ce57584c96b4c0753f9d6c5130e78c679a914f1927b73ac12523`

The 3,001-sample process capture shows the main thread in the asynchronous
closure created by `StorageIncidentRecorder.startFSEvents`. It contains:

- 2,990 samples in the callback body;
- 1,993 in `StorageIncidentRecorder.accept`;
- 1,945 in `recordRecoveryActivity`;
- 1,322 in `IncidentStore.save` and `JSONEncoder` while encoding the complete
  `[DiagnosticOperation]` array;
- a further 641 around checkpoint save/encoding;
- 338 in event-evidence append.

The native `DexCleaner.FSEvents.Native` queue had only 117 samples, mainly
coalescing and delivering paths. The event thread was in its normal Mach wait.
There was no semaphore wait or `dispatch_sync` cycle. This was main-actor
saturation, not a deadlock.

## Real support-state contribution

An isolated copy was created at
`/private/tmp/dexcleaner-1_3_2-support-fixture.6309qq/home`. It contains 23
selected recorder/monitoring files and occupies 49,604 KiB. The relevant state
is valid:

- 152,797 JSONL event records, 50,366,669 bytes;
- zero malformed event records;
- maximum event line 573 bytes;
- 100 Activity records, including one Running record;
- four incident records;
- checkpoint event ID 765,165,155;
- checkpoint time `2026-07-30T07:34:19Z`;
- `cleanShutdown=false`.

The copied state reproduced the failure without modifying the real support
directory. Its 10,000-event replay stalled the main actor for 20.582349458
seconds and performed 10,000 checkpoint writes. The equivalent synthetic batch
stalled for 24.822581334 seconds, performed 10,000 checkpoint writes, and filled
all 100 retained Activity slots.

## Architecture correction

- SwiftUI constructs the AppModel shell and yields once before recorder startup.
- Native callbacks enqueue ordered work on a dedicated replay actor.
- The actor processes 100 events per persistence batch.
- One batch append opens and synchronizes the event log once.
- The batch checkpoint is saved only after the evidence append succeeds.
- In-memory resume state advances only after checkpoint persistence succeeds.
- Replay publishes at the first meaningful update, the end of a delivered
  batch, failure, or at most once per 200 ms.
- Main-actor publication applies one compact checkpoint/recovery snapshot.
- Recovery Activity updates one session entry; it does not insert one entry per
  event.
- Persistence failure retains the last durable checkpoint, publishes
  Partial/Failed state, stops the immediate batch drain, and leaves the
  application shell responsive.
- Opening the full window explicitly orders out the transient popover window.
  No recorder state changes an application window level.

## Responsiveness results

Post-fix 10,000-event results:

| Fixture | Completion | Initial main-actor stall | Maximum heartbeat interval | Checkpoints | UI publications |
|---|---:|---:|---:|---:|---:|
| Copied support state | 0.110 s test case | 0.000466625 s | 0.015188125 s | 100 | 2 |
| Synthetic | 0.075 s test case | 0.000353250 s | 0.014217459 s | 100 | 2 |

The main-thread threshold is 0.250 seconds. The observed maximum scheduling
interval was 0.015188125 seconds. Harness menu, window, and Quit command
heartbeats completed within one second during active replay. Real installed
menu/window/Quit latency is recorded in the release-verification document.

## Test ledger

Tests discovered: 103.

Focused responsiveness and safety command:

```text
DEXCLEANER_SUPPORT_FIXTURE_HOME=/private/tmp/dexcleaner-1_3_2-support-fixture.6309qq/home swift test --scratch-path .build-1_3_2-responsiveness --filter 'HangReproductionTests|MainThreadResponsivenessTests|MenuBarResponsivenessTests|WindowResponsivenessTests|FSEventsReplayStressTests|FSEventsStreamFactoryTests|FSEventsRecoveryTests|ActivityCenterCoalescingTests|SupportStateCompatibilityTests|UICertificationTests|DiagnosticCleanupSeparationTests|DexCleanerSafetyTests'
```

Result: 43 executed, 43 passed, zero failed, zero skipped.

Retained 1.3.1 diagnostic command:

```text
swift test --scratch-path .build-1_3_2-responsiveness --filter 'RepeatedPatternTests|LocalCloudComparisonTests|EmergencyReserveTests|DiagnosticCancellationTests|DeepTraceTests|IncidentCompatibilityTests|OperationStateTests|ActivityCenterTests'
```

Result: 28 executed, 28 passed, zero failed, zero skipped. Combined final ledger:
71 unique executed, 71 passed, zero failed, zero skipped. The remaining 32
discoveries are cleanup/Trash or unrelated legacy tests outside this emergency
gate.

Discovery command:

```text
swift test list --scratch-path .build-1_3_2-responsiveness
```

## Release and safety disposition

Certification and packaging passed. Version 1.3.2 was built once and installed
once. The installed app passed strict signature verification, 5 minutes 12
seconds of production replay observation, menu/window interaction, a
0.59-second Quit, one relaunch, and a healthy 15-second process sample.
Executable, resource-bundle, rollback, and installed evidence are recorded in
`docs/RELEASE_VERIFICATION.md`.

No live cleanup, Quick Scan, candidate selection, Preview, cloud comparison,
cloud mutation, deep trace, reserve creation, user-content change, project
deletion, unauthorized file movement, or Finder Trash action occurred.
