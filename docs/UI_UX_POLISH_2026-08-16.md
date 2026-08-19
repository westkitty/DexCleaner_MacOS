# DexCleaner Production UI/UX Polish — 2026-08-16

This ledger is the inspectable count contract for the production-polish pass. It contains exactly 25 UI/UX improvements. Cross-cutting reduced-motion behavior supports these improvements and is not counted as an additional item.

### UIX-01 — Persistent status banner
`ContentView.statusBanner` consolidates operation phase, scan completeness, current status copy, and manifest authority into one durable, accessible status surface.

### UIX-02 — Problem escalation actions
The status surface exposes direct `Review Issues` and `Scan Details` actions whenever scan issues, warnings, or access diagnostics require attention.

### UIX-03 — Stateful responsive workflow stepper
`workflowStrip` now distinguishes complete, current, and upcoming Scan → Review → Preview → Confirm stages and falls back from horizontal to vertical layout when space is constrained.

### UIX-04 — Working-state progress and cancellation panel
Active work receives a dedicated progress surface with plain-language operation context, Command-Period cancellation, and a reduced-motion static indicator when continuous animation is undesirable.

### UIX-05 — Deliberate primary-action hierarchy
Scan, Selection, Preview, and Cleanup commands are grouped by intent, with the destructive path spatially separated rather than presented as one flat row of equal-looking actions.

### UIX-06 — Live cleanup-readiness explanation
The cleanup action and readiness text re-evaluate periodically so a fifteen-minute Preview expiration is reflected in the interface without waiting for another unrelated state change.

### UIX-07 — Context-rich metric cards
Available space, cleanable bytes, selected bytes, moved-to-Trash bytes, access state, target counts, capacity, and scan duration are presented with icons, details, and explicit accessibility values.

### UIX-08 — Progressive storage-summary disclosure
Previously collected `storageSummaries` are now visible in Scan Details without inventing an overlapping audit reclaim total.

### UIX-09 — Progressive access-diagnostic disclosure
Previously collected protected-folder permission diagnostics are visible with status, detail, remediation, and an adjacent Access Settings action.

### UIX-10 — Visible scan warnings
Scanner warnings are surfaced as a dedicated warning section instead of remaining report-only state.

### UIX-11 — Command-F search focus
A keyboard-accessible search-focus action uses `@FocusState` and Command-F so filtering does not require pointer travel.

### UIX-12 — Clear-search and Escape recovery
A visible clear affordance and Escape behavior remove the active query while keeping the user in the review workflow.

### UIX-13 — Filter-context summary
The filter surface reports visible candidates versus all candidates, current selection count, and issue count so the user can tell when a view is filtered rather than empty.

### UIX-14 — Profile safety microcopy
Each cleanup profile explains its scope and the interface explicitly warns that changing profiles clears selection to prevent hidden cleanup targets.

### UIX-15 — Context-aware empty states
Selected, Candidates, Audit, and Protected tabs distinguish not-scanned, filtered-empty, profile-empty, and genuinely empty states and offer safe next actions where useful.

### UIX-16 — Count-aware bulk selection controls
Select Visible, Clear, and Preview controls expose the number of affected items before activation, reducing ambiguity about bulk operations.

### UIX-17 — Scan-row risk and authority badges
Risk, category, and manifest ID are separated into readable labeled pills rather than compressed into one delimiter-heavy metadata line.

### UIX-18 — Owning-process warning treatment
Candidates whose owning application appears active now receive a dedicated warning with a practical close-before-Preview instruction.

### UIX-19 — Measurement provenance treatment
Fresh, cached, and unmeasured findings receive distinct icon-and-text provenance with timestamps where available.

### UIX-20 — Row-action ergonomics and copy feedback
Reveal and Copy Path are persistent bordered controls with larger hit areas, help text, and temporary `Copied` confirmation that respects reduced-motion preference.

### UIX-21 — Result outcome summary
The Results tab summarizes Authorized, Moved, Blocked, Failed, and Cancelled counts before the detailed ledger and reiterates moved-to-Trash byte semantics.

### UIX-22 — Structured result rows and copy feedback
Each result uses an explicit status pill, selectable path/detail text, and inline Copy Result confirmation rather than relying on the distant global status line.

### UIX-23 — Reports and privacy hierarchy
Report destination, format, path redaction, write/open actions, local-only privacy guidance, and success/failure feedback are grouped into a single coherent reports surface.

### UIX-24 — Audit-exclusion validation feedback
Additional large-file exclusions now expose accepted and rejected input, eliminating silent dropping of invalid absolute, traversal, or non-canonical entries.

### UIX-25 — Safer confirmation sheet
The confirmation sheet presents plan identity, item count, size, creation time, fifteen-minute lifetime, exact-path list, revalidation/Trash guarantees, live stale-plan blocking, and initial keyboard focus on Cancel.

## Cross-cutting motion and accessibility contract

- State changes use short, interruptible native SwiftUI transitions only where they clarify feedback.
- `accessibilityReduceMotion` disables custom transition animation and replaces the active spinner with a static functional indicator.
- Status, metrics, workflow steps, badges, selection toggles, buttons, and result/issue structures use text and symbols rather than color alone.
- The destructive confirmation action intentionally has no default Return-key shortcut.
