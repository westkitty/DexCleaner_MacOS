# DexCleaner 1.3.0 Storage Incident Recorder

## Delivered recorder boundary

The recorder is local-only and diagnostic-only. It stores capacity samples, incident records, event evidence, activity records, and generated reports below `~/Library/Application Support/DexCleaner/IncidentRecorder/`. It has no network, cloud-provider mutation, file-cleanup, Finder Trash, or automatic-remediation authority.

- Capacity samples use the existing lightweight native capacity provider. The recorder is started at app launch, samples at the configured five-minute cadence, checkpoints for sleep/wake, and records manual and synthetic trigger labels.
- Threshold evaluation uses immediately-free capacity, staged warning/critical thresholds, hysteresis, consecutive-sample loss detection, and a sleep/wake comparison. A manual `Investigate Now` creates an explicitly labelled investigation.
- FSEvents evidence is coalesced to meaningful parent roots and retained as diagnostic evidence. Focused allocation measurement is bounded by item count and deadline; it refuses symlinks and cross-filesystem traversal.
- Allocation evidence distinguishes logical bytes, physical allocated bytes, sparse/shared-file indicators, and cloud placeholders. Cloud placeholders never become allocated storage merely because their logical representation is large.
- Storage Incidents exposes recorder state, coverage, active diagnostic operation/progress, recent incidents, activity records, a cloud inspector, and an explicit finish/report action. It never makes diagnostic rows cleanup candidates.
- Markdown, JSON, and CSV incident reports are written only when an incident is finished. The focused synthetic test writes reports through an isolated temporary store, not user data.

## Safety invariants

- Cleanup retains its prior manifest, preview, single-authority, revalidation, and Finder-Trash gates. No incident trigger can start a scan, select a candidate, move a file, or empty Trash.
- Cloud inspection reads filesystem metadata only. It does not materialize, hydrate, unpin, delete, migrate, sign out, or alter any provider setting.
- The emergency-reserve controller presently provides only a fixed-path eligibility model at `Library/Application Support/DexCleaner/EmergencyReserve/reserve.bin`. It does not allocate or release a reserve in 1.3.0; therefore no user or app space was consumed by reserve validation.

## Focused regression evidence

`swift test --scratch-path .build-1_3_0 --filter DexCleanerSafetyTests` completed after the recorder compile corrections. The focused additions cover threshold/hysteresis and sleep/wake triggering, changed-path coalescing, symlink-safe allocated-size measurement, zero-allocation cloud-placeholder accounting, isolated incident-report persistence, diagnostic/cleanup separation, and fixed reserve-path refusal.

## Installed release verification — 2026-07-30 EDT

- Installed app: `/Applications/DexCleaner.app`, version `1.3.0`, bundle ID `ca.westcat.DexCleaner`.
- Installed executable SHA-256: `e802d786fa0ec068ba50eeee493a1854ad0e3dbf4b8f2695d1bf12239e8a9aa6`.
- Installed sealed resource-bundle archive SHA-256: `6ca0e57a10c41ced843ef058347a931a9df19309f03ea3ec7d91915aa7b94091`.
- Installed cleanup manifest SHA-256: `1a43342d4d0787d5b3d5a91af63add0f3b52b181c6ea26b31c8bcea2ab94fe4d`.
- The installed application and its 1.2.2 and 1.0.0 rollback copies pass `codesign --verify --deep --strict`.
- Direct executable launch produced no resource-bundle error. Launch Services then kept exactly one installed DexCleaner process alive.
- The native desktop accessibility bridge timed out before it could inspect the new Storage Incidents UI. Manual confirmation remains required for its visual presentation and interaction. No UI action was substituted with a destructive operation.

## Explicit limitations

The following requested analysis remains deliberately incomplete rather than misrepresented as proven: a full local-versus-cloud duplicate comparator, a repeated-pattern classifier, optional deep-trace attribution, persistent FSEvents resume-id recovery, and actual emergency-reserve allocation/release. The current implementation is a bounded diagnostic foundation, not authority to perform any cleanup.
