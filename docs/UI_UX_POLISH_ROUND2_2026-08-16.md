# DexCleaner Production UI/UX Polish Round Two - 2026-08-16

This ledger is the inspectable count contract for the second production-polish pass. It contains exactly 25 new UI/UX improvements beyond the first `UIX-01` through `UIX-25` ledger. Cross-cutting reduced-motion handling supports these changes and is not counted as an additional item.

### UIX2-01 - Scan freshness visibility
The status surface and menu bar now retain the latest scan timestamp, show human-readable scan age, and flag scans older than thirty minutes without pretending freshness affects cleanup authority.

### UIX2-02 - Guided next-safe-action card
A persistent next-action surface translates current state into the safest useful action: Scan, Review Issues, Review Candidates, Preview, open confirmation, cancel active work, or review results.

### UIX2-03 - Actionable workflow steps
The Scan -> Review -> Preview -> Confirm stepper is now interactive, with each enabled step navigating to or performing the corresponding safe workflow action instead of serving as passive decoration.

### UIX2-04 - Primary keyboard accelerators
Command-R starts an explicit scan and Command-Shift-P runs Preview for the current selection, complementing the existing Command-F search and Command-Period cancellation shortcuts.

### UIX2-05 - Additive visible selection
`Add Visible` now adds the currently filtered candidates without silently deselecting valid selections that happen to be outside the active search filter.

### UIX2-06 - Scoped clear controls
Bulk deselection is split into `Clear Visible` and `Clear All`, making the scope of a selection-changing action explicit before activation.

### UIX2-07 - Selection impact summary
A dedicated selection summary reports selected item count, estimated bytes, represented groups, and whether owning applications appear active.

### UIX2-08 - Selected running-app preflight
When selected targets belong to applications that appear active, the interface raises a focused preflight warning and offers a direct route to the Selected review area.

### UIX2-09 - Grouped review lists
Candidate, Selected, Audit, and Protected findings are grouped by their owning product/group with per-group item counts and byte totals instead of one undifferentiated list.

### UIX2-10 - Collapsible review groups
Each review group can be collapsed or expanded in-place so large scans remain navigable without losing group context.

### UIX2-11 - Progressive row detail disclosure
Rows default to a compact summary and expose explanation, recovery guidance, and stale-measurement context through an explicit Details control.

### UIX2-12 - Strong selected-state communication
Selected cleanup rows receive a visible Selected badge plus an accessibility value that states selection, risk, size, and measurement provenance without relying on the checkbox alone.

### UIX2-13 - Row context menus
Review rows now expose Select/Deselect, Reveal in Finder, and Copy Path through a native context menu for efficient secondary-click access while keeping persistent visible controls for keyboard and pointer users.

### UIX2-14 - Measurement age and stale indication
Measurement provenance now includes relative age, and measurements older than the fifteen-minute scanner cache window receive an explicit stale marker with safe explanatory copy.

### UIX2-15 - Non-crushing review navigation
The six-area segmented control is replaced by horizontally scrollable pill navigation so review destinations remain readable at the minimum supported window width.

### UIX2-16 - Command-number review navigation
Command-1 through Command-6 switch among Selected, Candidates, Audit, Protected, Results, and Issues without pointer travel.

### UIX2-17 - Result status filtering
The Results area can filter the operation ledger by Authorized, Moved, Blocked, Failed, or Cancelled outcomes while preserving an All view and status counts.

### UIX2-18 - Copy-visible-results action
The active result filter can be copied as a concise multi-line diagnostic payload with one action and local success feedback.

### UIX2-19 - Reveal surviving result paths
Results whose filesystem source path still exists expose a Reveal action; moved or non-filesystem result identifiers never pretend they can be revealed.

### UIX2-20 - Copyable issue diagnostics
Every scan issue receives a local Copy Issue action containing kind, area, and detail for troubleshooting without overwriting the global operational status.

### UIX2-21 - Issue recovery actions
The Issues area now offers an explicit re-scan action and conditionally exposes Full Disk Access settings when permission failures are present.

### UIX2-22 - Copyable diagnostic summary
Scan Details can copy one local troubleshooting summary containing completeness, access state, duration, issue count, warnings, issues, and permission diagnostics.

### UIX2-23 - Report preflight summary
Before a report is written, the reports surface states current report mode, finding/result counts, format, path-redaction mode, and whether cleanup-plan metadata will be included.

### UIX2-24 - Live confirmation countdown
The destructive confirmation sheet displays a one-second live countdown to Preview expiry so authorization lifetime is understandable before it becomes invalid.

### UIX2-25 - Copy exact plan paths
The confirmation sheet can copy the exact immutable plan paths as a plain-text audit list without authorizing or performing cleanup.

## Cross-cutting motion and accessibility contract

- Existing reduced-motion behavior remains controlling; new collapsible rows/groups use no custom motion when Reduce Motion is active.
- The new next-action and workflow controls use native buttons, labels, disabled states, and explicit accessible values.
- Review navigation remains readable without color-only meaning and does not depend on hover.
- The destructive confirmation action still has no default Return-key shortcut.
