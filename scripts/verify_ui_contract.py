#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
first_ledger = (root / "docs/UI_UX_POLISH_2026-08-16.md").read_text(encoding="utf-8")
second_ledger = (root / "docs/UI_UX_POLISH_ROUND2_2026-08-16.md").read_text(encoding="utf-8")
content = "\n".join(path.read_text(encoding="utf-8") for path in sorted((root / "Sources/DexCleaner").glob("ContentView*.swift")))
model = (root / "Sources/DexCleaner/AppModel.swift").read_text(encoding="utf-8")
app = (root / "Sources/DexCleaner/DexCleanerApp.swift").read_text(encoding="utf-8")

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
]
required_app = [
    "scanFreshnessText",
    "Preview stale or expired",
    "Cancel Active Operation",
]

for token in required_content:
    if token not in content:
        raise SystemExit(f"Missing round-two UI contract token in ContentView.swift: {token}")
for token in required_model:
    if token not in model:
        raise SystemExit(f"Missing round-two UI contract token in AppModel.swift: {token}")
for token in required_app:
    if token not in app:
        raise SystemExit(f"Missing round-two UI contract token in DexCleanerApp.swift: {token}")

for forbidden in [
    "keyboardShortcut(.defaultAction)",
    "FileManager.default.removeItem",
    "ServiceManagement",
    "SMAppService",
    "backgroundTimer",
    "Background scan",
]:
    if forbidden in content or forbidden in model or forbidden in app:
        raise SystemExit(f"Forbidden app-source contract token present: {forbidden}")

print("UI/UX contract: PASS - first 25 preserved and exactly 25 round-two improvements ledgered")
