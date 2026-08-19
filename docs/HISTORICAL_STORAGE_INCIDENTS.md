# Historical Storage Incidents

## Antigravity state loss

- What happened: previous cleanup removed Antigravity conversation or application state.
- Permanent invariant: Antigravity support data, hidden state, archives, conversations, authentication, sessions, identity, workspace history, databases, and browser-style stores are never cleanup authority.
- Regression coverage: protected-fragment, exact-allowlist, session/authentication, and application-state tests.
- User interface behavior: Antigravity locations appear only as protected presence markers; they cannot be selected or previewed.

## Documents asset loss

- What happened: `~/Documents/assets` was permanently deleted.
- Permanent invariant: Documents, assets, projects, and user-content trees are protected and never automatic cleanup targets.
- Regression coverage: explicit `Documents` and `Documents/assets` rejection tests.
- User interface behavior: Documents appears as a protected marker with no invented reclaimable byte count.

## Permission-blind scanning

- What happened: inaccessible locations were previously represented as empty or zero bytes.
- Permanent invariant: access denial is Partial or Failed, never zero, absent, clean, or safely scanned.
- Regression coverage: permission/measurement failures produce scan issues and incomplete status.
- User interface behavior: access status and issues remain visible in both the menu surface and full window.

## Duplicate mounts

- What happened: two mount paths exposing one underlying filesystem could be counted twice.
- Permanent invariant: capacity totals are sourced from the startup volume, and mount inventory is deduplicated by filesystem identity.
- Regression coverage: duplicate device-and-filesystem identities collapse to one record.
- User interface behavior: duplicate mount aliases never increase internal capacity or reclaim estimates.

## Unfinished utility

- What happened: reports and partial implementations did not leave a reliable daily tool.
- Permanent invariant: reports support the installed app; they do not substitute for installation and runtime proof.
- Regression coverage: bundle, launch, menu-bar, Quick Scan, preview, synthetic Trash, restoration, ledger, and rollback gates.
- User interface behavior: one menu-bar utility exposes the full safe workflow and current measurement status.
