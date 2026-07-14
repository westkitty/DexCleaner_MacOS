# DexCleaner Release Checklist

A release is blocked until every required item is checked on actual macOS hardware.

## Automated gates

- [ ] `make bug-sweep` passes
- [ ] Linux CI passes
- [ ] macOS CI passes
- [ ] executable product compiles
- [ ] app source parser check passes
- [ ] manifest validation tests pass
- [ ] cancellation tests pass
- [ ] preview-plan expiry and duplicate-plan tests pass
- [ ] manifest ID/path binding tests pass
- [ ] mandatory exclusion tests pass
- [ ] report free-text redaction and filename-collision tests pass
- [ ] preview authorization tests pass
- [ ] filesystem identity-change tests pass
- [ ] report Markdown and JSON tests pass
- [ ] source guard finds no permanent deletion
- [ ] source guard finds no background scanning or launch-at-login implementation

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

- [ ] `make app` succeeds
- [ ] `make verify-app` succeeds
- [ ] `plutil -lint` passes
- [ ] SwiftPM resource bundle exists inside app Resources
- [ ] `codesign --verify --deep --strict` passes
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
