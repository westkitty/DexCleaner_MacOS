# Codex Handoff: DexCleaner

Read this handoff and project_report.md first.

## Project Identity
- Name: DexCleaner
- Path: /Users/andrew/DexCleaner
- Purpose: Purpose could not be inferred confidently from filesystem signals.

## Current Git State
- Repo root: /Users/andrew/DexCleaner | Branch: codex/final-storage-forensics | Status: dirty | Remote: git@github.com:westkitty/DexCleaner_MacOS
- Latest commit: 7b4999ccd8ee6310e1c1452137cb463a4502fe93 chore: relocate DexCleaner project root

## Detected Project Type
- Type: swift_package
- Confidence: 0.75
- Evidence:
  - Found Package.swift

## Likely Commands
- [build] swift build
- [test] swift test

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

## Secret-Risk Warning Summary
No secret-risk matches detected.

## Top 5 Recommended Next Actions
1. Inspect the current uncommitted Git changes before making new edits.
2. Back up or review fragile configuration files before any risky changes.
3. Validate the project with the hinted test command: swift test
4. Validate the project with the hinted build command: swift build
5. Read `.resurrection/project_report.md` and make one bounded change at a time.

## Strict Codex Instruction Block

Read this handoff and project_report.md first.
Make one bounded change only.
Do not rewrite the project.
Do not delete or reorganize files.
Inspect existing files before editing.
Run the smallest relevant validation command available.
If validation cannot be run, explain why.
Report changed files, commands run, test results, and remaining risks.
