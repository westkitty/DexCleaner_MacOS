# Project Resurrection Report: DexCleaner

## Identity
- Name: DexCleaner
- Path: /Users/andrew/DexCleaner
- Project type: swift_package
- Confidence: 0.75
- Inferred purpose: Purpose could not be inferred confidently from filesystem signals.
- Evidence:
  - Found Package.swift

## Git State
- Summary: Repo root: /Users/andrew/DexCleaner | Branch: codex/final-storage-forensics | Status: dirty | Remote: git@github.com:westkitty/DexCleaner_MacOS
- Latest commit: 7b4999ccd8ee6310e1c1452137cb463a4502fe93 chore: relocate DexCleaner project root
- Tracked modified count: 1
- Untracked count: 18
- Staged count: 1

## Commands Detected
- [build] swift build (Package.swift)
- [test] swift test (Package.swift)

## Fragile Files
- .build-1_3_0/arm64-apple-macosx/debug/DexCleaner-entitlement.plist
- .build-1_3_0/arm64-apple-macosx/debug/DexCleaner.dSYM/Contents/Info.plist
- .build-1_3_1-final/arm64-apple-macosx/debug/DexCleaner-entitlement.plist
- .build-1_3_1-final/arm64-apple-macosx/debug/DexCleaner.dSYM/Contents/Info.plist
- .build-1_3_1-final/arm64-apple-macosx/debug/DexCleanerPackageTests.xctest/Contents/MacOS/DexCleanerPackageTests.dSYM/Contents/Info.plist
- .build-1_3_1-release-gate/arm64-apple-macosx/debug/DexCleaner-entitlement.plist
- .build-1_3_1-release-gate/arm64-apple-macosx/debug/DexCleaner.dSYM/Contents/Info.plist
- .build-1_3_1-release-gate/arm64-apple-macosx/debug/DexCleanerPackageTests.xctest/Contents/MacOS/DexCleanerPackageTests.dSYM/Contents/Info.plist
- .build-1_3_1-sprint-a/arm64-apple-macosx/debug/DexCleaner-entitlement.plist
- .build-1_3_1-sprint-a/arm64-apple-macosx/debug/DexCleaner.dSYM/Contents/Info.plist
- .build-1_3_1-sprint-a/arm64-apple-macosx/debug/DexCleanerPackageTests.xctest/Contents/MacOS/DexCleanerPackageTests.dSYM/Contents/Info.plist
- .build-1_3_1/arm64-apple-macosx/debug/DexCleaner-entitlement.plist
- .build-1_3_1/arm64-apple-macosx/debug/DexCleaner.dSYM/Contents/Info.plist
- .build-1_3_2-responsiveness/arm64-apple-macosx/debug/DexCleaner-entitlement.plist
- .build-1_3_2-responsiveness/arm64-apple-macosx/debug/DexCleaner.dSYM/Contents/Info.plist
- .build-1_3_2-responsiveness/arm64-apple-macosx/debug/DexCleanerPackageTests.xctest/Contents/MacOS/DexCleanerPackageTests.dSYM/Contents/Info.plist
- .build-final/arm64-apple-macosx/debug/DexCleaner-entitlement.plist
- .build-final/arm64-apple-macosx/debug/DexCleaner.dSYM/Contents/Info.plist
- .build-final/arm64-apple-macosx/debug/DexCleanerPackageTests.xctest/Contents/MacOS/DexCleanerPackageTests.dSYM/Contents/Info.plist
- .build-final/arm64-apple-macosx/release/DexCleaner.dSYM/Contents/Info.plist
- .build-fsevents-deps-foundation/arm64-apple-macosx/debug/DexCleaner-entitlement.plist
- .build-fsevents-deps-foundation/arm64-apple-macosx/debug/DexCleaner.dSYM/Contents/Info.plist
- .build-fsevents-deps-foundation/arm64-apple-macosx/debug/DexCleanerPackageTests.xctest/Contents/MacOS/DexCleanerPackageTests.dSYM/Contents/Info.plist
- .build-fsevents-recovery/arm64-apple-macosx/debug/DexCleaner-entitlement.plist
- .build-fsevents-recovery/arm64-apple-macosx/debug/DexCleaner.dSYM/Contents/Info.plist
- .build-fsevents-report/arm64-apple-macosx/debug/DexCleaner-entitlement.plist
- .build-fsevents-report/arm64-apple-macosx/debug/DexCleaner.dSYM/Contents/Info.plist
- .build-fsevents-report/arm64-apple-macosx/debug/DexCleanerPackageTests.xctest/Contents/MacOS/DexCleanerPackageTests.dSYM/Contents/Info.plist
- .build/arm64-apple-macosx/debug/DexCleaner-entitlement.plist
- .build/arm64-apple-macosx/debug/DexCleaner.dSYM/Contents/Info.plist
- .build/arm64-apple-macosx/debug/DexCleanerPackageTests.xctest/Contents/MacOS/DexCleanerPackageTests.dSYM/Contents/Info.plist
- .build/arm64-apple-macosx/release/DexCleaner.dSYM/Contents/Info.plist
- .build/DexCleaner.app/Contents/Info.plist
- CHANGELOG.md
- DexCleaner_MacOS_bible.md
- README.md

## Duplicate Or Stale Candidates
- .build-1_3_1-final
- .build-final
- sibling-near-duplicate: dex

## Secret-Risk Findings
No secret-risk matches detected.

## Recommended Next Actions
1. Inspect the current uncommitted Git changes before making new edits.
2. Back up or review fragile configuration files before any risky changes.
3. Validate the project with the hinted test command: swift test
4. Validate the project with the hinted build command: swift build
5. Read `.resurrection/project_report.md` and make one bounded change at a time.

## Scan Metadata
- Timestamp: 2026-07-30T12:01:49+00:00
- Scanner version: 1.1.0
