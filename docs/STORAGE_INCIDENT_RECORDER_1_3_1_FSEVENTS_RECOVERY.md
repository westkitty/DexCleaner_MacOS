# DexCleaner 1.3.1 FSEvents Recovery Progress

## Initial state

- Branch: `codex/final-storage-forensics`.
- The worktree was already dirty with uninstalled partial 1.3.1 sources, including `IncidentCompletion.swift`.
- Installed DexCleaner remains version 1.3.0. No packaging or installation was attempted.

## Production wiring added in this pass

- `StorageIncidentRecorder.start` now loads a diagnostic-store checkpoint and starts the production FSEvents stream from its durable event ID when the stored volume identity and watched roots match.
- Event acceptance now writes and synchronizes JSONL evidence before saving the checkpoint and only then updates the in-memory resume ID. Failed evidence persistence leaves the checkpoint unchanged.
- Checkpoints contain schema, volume/device identity, roots, event ID/timestamp, checkpoint timestamp, session identity, clean-shutdown marker, and recovery result.
- Corrupt or invalid checkpoint input is copied aside beneath the diagnostic store before a fresh baseline checkpoint is created. Sleep persists a clean checkpoint; wake rejects a changed volume ID and records partial coverage.
- Replay IDs at or below the durable ID are suppressed and reflected in coverage text. Activity Center receives recovery-start/completion entries.

## Validation result

The bounded focused build completed with the existing recorder/safety target after one compile correction. The required deterministic recovery matrix was not added, and recovered event fields have not yet been represented in the incident JSON/Markdown schema. This pass is therefore **not complete** and not certification evidence.

## Recovery-report serialization update

- Production incidents now carry the optional, backward-compatible `filesystemEventRecovery` object. Its JSON representation is emitted by the production incident report writer and retains typed `UInt64` event IDs.
- Production Markdown reports now append `## Filesystem event recovery`, including outcome, checkpoint/resume IDs, recovered range, volume, interval, duplicate and dropped-event state, root/volume change state, missing interval, fallback baseline, completeness, and the explicit limitation that FSEvents locates changes but does not measure byte growth.
- Eight deterministic production report tests were added: complete rendering, bounded gap, dropped-event rendering, byte-measurement limitation, JSON presence, exact large-ID round trip, legacy record decoding, and failure/unavailable report generation.
- Initial blockers were an inaccessible `temporaryHome` fixture helper, an optional timestamp fixture, initializer argument order, immutable legacy JSON fixture, and test-class filter mismatch. A private per-test temporary-directory helper now registers teardown cleanup; no production home or app store is touched.
- Focused command: `swift test --scratch-path .build-fsevents-report --filter 'DexCleanerSafetyTests/(testRecoveryReport|testOlderIncident)'`. It discovered and executed 8 tests: 8 passed, 0 failed, 0 skipped.
- Smallest report regression: `swift test --scratch-path .build-fsevents-report --filter DexCleanerSafetyTests/testIncidentReportPersistenceAndDiagnosticCleanupSeparation`. It executed 1 test: 1 passed, 0 failed.
- Production correction required: the incident writer appends the recovery section and serializes the existing optional recovery object; no FSEvents stream, checkpoint, cleanup, or installed-app behavior changed. The broader checkpoint/replay matrix remains a later pass.
- Installed DexCleaner remains 1.3.0; this source-only pass did not package or install anything.

## Safety

No app was packaged or installed. No live scan, cleanup, cloud mutation, user-data change, file movement, or Finder Trash action occurred. Recovery code has no cleanup-authority access.

## Remaining 1.3.1 areas

1. Complete deterministic FSEvents tests and incident/report recovery fields.
2. Repeated-pattern classifier integration.
3. Local/cloud comparison integration.
4. Deep-trace integration.
5. Emergency-reserve integration.
6. UI certification harness.
