# DexCleaner Release Checklist

A release is blocked until every required item is checked on actual macOS hardware.

## Automated gates

- [x] `make bug-sweep` passes
- [x] Linux CI passes
- [x] macOS CI passes
- [x] executable product compiles
- [x] app source parser check passes
- [x] manifest validation tests pass
- [x] cancellation tests pass
- [x] preview-plan expiry and duplicate-plan tests pass
- [x] manifest ID/path binding tests pass
- [x] mandatory exclusion tests pass
- [x] report free-text redaction and filename-collision tests pass
- [x] preview authorization tests pass
- [x] filesystem identity-change tests pass
- [x] whole-plan preflight and evidence-tampering tests pass
- [x] project, Homebrew, managed-resource, backup, and duplicate adapter fixtures pass
- [x] report Markdown and JSON tests pass
- [x] production UI render certifications pass on macOS
- [x] source guard finds no permanent deletion
- [x] source guard finds no background scanning or launch-at-login implementation

## Clean-account functional pass

- [ ] app launches idle without scanning
- [ ] Scan starts only after user action
- [ ] Complete, Partial, Cancelled, and Failed states are distinguishable
- [ ] selected items remain visible in Selected
- [ ] changing profile clears selection
- [ ] cleanup button remains disabled before Preview
- [ ] Preview performs no mutation
- [ ] changing selection invalidates Preview
- [ ] confirmation lists every exact path
- [ ] changed target identity is blocked
- [ ] valid exact target moves to Finder Trash
- [ ] moved item restores successfully from Trash
- [ ] app never empties Trash
- [ ] moved bytes are not described as freed bytes
- [ ] partial and failed results remain fully visible
- [ ] cancellation returns controls to a usable state
- [ ] no refresh scan begins after cleanup cancellation

## Access and scan behavior

- [ ] Access Settings opens the correct macOS pane
- [ ] the app does not claim Full Disk Access was granted
- [ ] protected sample failures appear as access limitations
- [ ] cloud roots are not recursively scanned by large-file audit
- [ ] project roots are not recursively scanned by large-file audit
- [ ] nested `.git` directories are pruned from large-file audit
- [ ] additional excluded roots setting applies on the next scan
- [ ] mandatory privacy exclusions cannot be removed

## Accessibility and layout

- [ ] window works at 760 × 620
- [ ] enlarged text remains usable
- [ ] all cleanup actions work by keyboard
- [ ] Return does not trigger the destructive confirmation action by default
- [ ] VoiceOver identifies selection controls and workflow stage
- [ ] Reveal and Copy Path do not require hover
- [ ] color is not the only status indicator
- [ ] all results and issues are navigable

## Reports and ledger

- [ ] Markdown report opens and contains plan metadata
- [ ] JSON report decodes
- [ ] home-path redaction removes the absolute home prefix from paths, warnings, issues, diagnostics, and result details
- [ ] repeated reports in the same second receive distinct filenames
- [ ] operation ledger appends one JSON object per line
- [ ] report failure does not overwrite cleanup status

## Packaging

- [ ] `make app` succeeds at the release destination
- [ ] `make verify-app` succeeds at the release destination
- [x] staged app-bundle construction succeeds
- [x] `plutil -lint` passes
- [x] SwiftPM resource bundle exists inside app Resources
- [x] `codesign --verify --deep --strict` passes
- [ ] signed identity is recorded
- [ ] app launches outside the build directory
- [ ] `make dmg` succeeds
- [ ] DMG checksum is generated
- [ ] DMG mounts, app copies, launches, scans, previews, and quits
- [ ] Gatekeeper behavior is recorded
- [ ] notarization is completed before public distribution when required

## Release record

Record:

- commit SHA
- app version
- manifest version
- manifest checksum
- signing identity
- macOS version and hardware used
- CI run links
- known residual risks

Automated release record for the evidence-driven campaign:

- code commit: `0eeb4c35a282577ab2d8671aaef21340e7ad3752`
- CI: [DexCleaner CI run 32830483705](https://github.com/westkitty/DexCleaner_MacOS/actions/runs/32830483705)
- result: Linux sweep/release tests and macOS build/tests/app verification passed
- residual risk: the path-based Finder Trash time-of-check/time-of-use interval remains
- human-only clean-account, accessibility, Trash restoration/cancellation, distribution signing, DMG, and Gatekeeper items above remain unchecked
