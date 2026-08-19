#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
first_ledger = (root / "docs/UI_UX_POLISH_2026-08-16.md").read_text(encoding="utf-8")
second_ledger = (root / "docs/UI_UX_POLISH_ROUND2_2026-08-16.md").read_text(encoding="utf-8")
content = "\n".join(path.read_text(encoding="utf-8") for path in sorted((root / "Sources/DexCleaner").glob("ContentView*.swift")))
model = (root / "Sources/DexCleaner/AppModel.swift").read_text(encoding="utf-8")
app = (root / "Sources/DexCleaner/DexCleanerApp.swift").read_text(encoding="utf-8")
cache = (root / "Sources/DexCleanerCore/ScanCache.swift").read_text(encoding="utf-8")
clock_test = (root / "Tests/DexCleanerTests/ScanCacheClockRegressionTests.swift").read_text(encoding="utf-8")

expected = [f"{number:02d}" for number in range(1, 26)]
first_ids = re.findall(r"^### UIX-(\d{2}) ", first_ledger, re.MULTILINE)
second_ids = re.findall(r"^### UIX2-(\d{2}) ", second_ledger, re.MULTILINE)
if first_ids != expected:
    raise SystemExit(f"First UI/UX ledger must contain exactly UIX-01 through UIX-25; found {first_ids}")
if second_ids != expected:
    raise SystemExit(f"Round-two UI/UX ledger must contain exactly UIX2-01 through UIX2-25; found {second_ids}")

required_content = [
    "nextActionCard",
    "performWorkflowStep",
    "Add Visible",
    "Clear Visible",
    "selectionImpact",
    "groupedItems",
    "collapsedGroups",
    "expandedRows",
    "ResultFilter",
    "Copy Visible Results",
    "Copy Issue",
    "Copy Diagnostics",
    "reportPreflightText",
    "previewRemainingText",
    "Copy Plan Paths",
    "keyboardShortcut(\"r\"",
    "keyboardShortcut(\"p\"",
    "tabShortcut",
    "accessibilityReduceMotion",
    ".onChange(of: model.cleanupResults)",
    "shouldReviewOperationResults",
    ".labelsHidden().toggleStyle(.checkbox)\n                .disabled(model.isWorking)",
    "if model.canReveal(item) {",
    "feedbackResetTask?.cancel()",
    "case .complete: current = 5",
]
required_model = [
    "lastScanDate",
    "scanFreshnessText",
    "scanIsStale",
    "addVisibleCandidates",
    "clearVisibleSelection",
    "selectedRunningProcessCount",
    "measurementAgeText",
    "measurementIsStale",
    "copyResults",
    "canRevealResult",
    "copyIssue",
    "copyDiagnosticsSummary",
    "reportPreflightText",
    "previewRemainingText",
    "copyPlanPaths",
    "hasCleanupOutcome",
    "selectionDidChange",
    "reportPlan(for:",
    "canReveal(_ item:",
]
required_app = [
    "scanFreshnessText",
    "Preview stale or expired",
    "Cancel Active Operation",
]
required_cache = [
    "guard age >= 0, age <= maximumAge else { return nil }",
    "return age >= 0 && age <= maximumAge",
]
required_clock_test = [
    "testFutureDatedCacheRecordIsRejectedAndPrunedBeforeSave",
    "XCTAssertNil(cache.cachedRecord(path: target.path, now: now))",
]

for token in required_content:
    if token not in content:
        raise SystemExit(f"Missing UI/bug-regression contract token in ContentView sources: {token}")
for token in required_model:
    if token not in model:
        raise SystemExit(f"Missing UI/bug-regression contract token in AppModel.swift: {token}")
for token in required_app:
    if token not in app:
        raise SystemExit(f"Missing UI contract token in DexCleanerApp.swift: {token}")
for token in required_cache:
    if token not in cache:
        raise SystemExit(f"Missing cache clock-skew guard in ScanCache.swift: {token}")
for token in required_clock_test:
    if token not in clock_test:
        raise SystemExit(f"Missing cache clock regression fixture: {token}")

for forbidden in [
    "keyboardShortcut(.defaultAction)",
    "FileManager.default.removeItem",
    "ServiceManagement",
    "SMAppService",
    "backgroundTimer",
    "Background scan",
    "(cleanupPlan ?? lastCompletedPlan)",
]:
    if forbidden in content or forbidden in model or forbidden in app:
        raise SystemExit(f"Forbidden app-source contract token present: {forbidden}")

print("UI/UX contract: PASS - first 25 and round-two 25 preserved; round-three bug regression guards present")
