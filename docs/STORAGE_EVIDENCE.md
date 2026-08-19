# Storage Evidence

Measured on 2026-07-27/28 on this Mac. Figures from `du` are allocated/logical
directory measurements and may not equal physically reclaimable APFS blocks,
especially for clones and cloud-provider data.

## Capacity baseline

- Internal APFS container: 245.1 GB total.
- APFS container unallocated: 12.8 GB.
- Filesystem immediately free: 12.8 GB.
- Foundation general available capacity: 18.4 GB.
- Foundation available for important usage: 19.3 GB.
- Foundation opportunistic capacity: 6.1 GB.
- Selected menu-bar metric: `Available for work`, backed by
  `volumeAvailableCapacityForImportantUsage`.
- Measurement status: **Disputed**. Foundation general available capacity and
  the filesystem immediately-free cross-check differ by about 5.6 GB, above the practical
  2% of capacity or 1 GiB tolerance.
- The discrepancy is exposed; the app does not collapse the values into one
  unexplained number.

## Ranked storage causes

| Rank | Measured area | Size | Likely cause | Recurrence | Reclaim estimate | Risk / action | Confidence |
|---|---|---:|---|---|---|---|---|
| 1 | `~/Library/Application Support` | 33.3 GB | Application state and provider data | Recurring | Not asserted | Protected or audit-only | High |
| 2 | `~/DexDictate_MacOS.nosync` | 14.3 GB | Large development checkout/build artifacts | Project-driven | Not asserted | Audit-only project tree | High |
| 3 | `~/orbital tomb` | 7.3 GB | Project/content tree | Project-driven | Not asserted | Audit-only user/project content | High |
| 4 | `~/Library/Caches` | 5.9 GB | Mixed application and developer caches | Recurring | 974 MB manifest-authorized | Exact targets only | High |
| 5 | `~/.codex` | 5.2 GB | Codex local state and tooling data | Recurring | Not asserted | Protected application state | High |
| 6 | `~/.gemini` | 4.5 GB | Gemini local state | Recurring | Not asserted | Protected application state | High |
| 7 | `~/Westcat_Familiar` | 4.3 GB | Project tree | Project-driven | Not asserted | Audit-only | High |
| 8 | `~/clearcut` | 3.8 GB | Project tree | Project-driven | Not asserted | Audit-only | High |
| 9 | `~/frens` | 3.8 GB | Project tree | Project-driven | Not asserted | Audit-only | High |
| 10 | `~/esp` | 3.2 GB | Developer/project root | Project-driven | Not asserted | Audit-only | High |

Other material home roots include `~/Movies` (2.3 GB), `~/.gradle` (2.3 GB),
`~/grok_for_animation` (2.2 GB), `~/.cache` (2.2 GB), `~/.espressif`
(2.1 GB), and `~/wallpapers` (2.0 GB). Broad hidden caches and project roots
are not cleanup authority.

## Application Support detail

The largest measured children are:

- Claude: 8.4 GB
- 1132Fixer: 3.4 GB
- FileProvider: 3.4 GB
- CloudDocs: 3.3 GB
- DexDictate: 2.3 GB
- Google: 2.2 GB
- GrokGitHubDaily: 1.8 GB
- DexTalker: 1.6 GB
- BraveSoftware: 1.4 GB
- FluidAudio: 1.1 GB
- Code: 951 MB

These are application state, browser/provider data, or mixed support roots.
They are not routine cleanup candidates.

## Verified manifest targets

Exact measured candidates:

- `~/Library/Caches/Homebrew`: 288.2 MB
- `~/Library/Caches/pip`: 257.8 MB
- `~/Library/Caches/org.swift.swiftpm`: 426.0 MB
- `~/Library/Caches/com.apple.dt.Xcode`: 135 KB
- `~/Library/Developer/CoreSimulator/Caches`: empty
- `~/Library/Application Support/Code/Cache`: 2.2 MB

Total manifest-authorized estimate: approximately **974 MB**. Every target is
initially unselected and still requires a fresh scan, immutable preview,
confirmation, and immediate revalidation. No live target was moved during this
assignment.

## Other evidence

- Installed applications on the Data volume measured about 24.9 GB.
- System Library measurement returned at least 3.5 GB but was Partial because
  protected subpaths denied access.
- `/private` returned at least 6.9 GB but was Partial for the same reason.
- Trash measured empty at the audit point.
- No Time Machine local snapshot was listed. The sealed operating-system update
  snapshot is present and is not cleanup authority.
- The only observed open-but-unlinked regular file was a small logging
  preference cache of roughly 73 KB; it does not explain storage pressure.
- A recent large BetterCapture movie was found under `~/Movies`. Recent-file
  searches under Desktop and Documents timed out and are explicitly Partial.
- `/Volumes/wc2tb` is an SMB network mount and was excluded from internal
  capacity totals.

## Conclusion

Repeated pressure is primarily a cumulative workload pattern: large local
projects, AI/developer tool state, application support, cloud-provider local
state, and several cache families. Routine manifest cleanup can reduce about
1 GB today, but it cannot honestly solve the larger pressure without separate,
target-specific review of protected application state and project content.
