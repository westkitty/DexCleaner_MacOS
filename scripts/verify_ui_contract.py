#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
ledger = (root / "docs/UI_UX_POLISH_2026-08-16.md").read_text(encoding="utf-8")
content = (root / "Sources/DexCleaner/ContentView.swift").read_text(encoding="utf-8")
model = (root / "Sources/DexCleaner/AppModel.swift").read_text(encoding="utf-8")
app = (root / "Sources/DexCleaner/DexCleanerApp.swift").read_text(encoding="utf-8")

ids = re.findall(r"^### UIX-(\d{2}) —", ledger, re.MULTILINE)
expected = [f"{number:02d}" for number in range(1, 26)]
if ids != expected:
    raise SystemExit(f"UI/UX ledger must contain exactly UIX-01 through UIX-25; found {ids}")

required_content = [
    "accessibilityReduceMotion",
    "@FocusState",
    "TimelineView(.periodic",
    "statusBanner",
    "workflowStrip",
    "storageSummarySection",
    "accessDiagnosticsSection",
    "warningsSection",
    "EmptyState",
    "ResultRow",
    "FeedbackButton",
    "confirmationCancelFocused",
]
required_model = [
    "exclusionInputValidation",
    "cleanupReadinessText(at",
    "canClean(at",
    "PreviewAuthorization.maximumPlanAge",
]
required_app = [
    "Cancel Active Operation",
    "Preview stale or expired",
]

for token in required_content:
    if token not in content:
        raise SystemExit(f"Missing UI contract token in ContentView.swift: {token}")
for token in required_model:
    if token not in model:
        raise SystemExit(f"Missing UI contract token in AppModel.swift: {token}")
for token in required_app:
    if token not in app:
        raise SystemExit(f"Missing UI contract token in DexCleanerApp.swift: {token}")

for forbidden in ["keyboardShortcut(.defaultAction)", "FileManager.default.removeItem"]:
    if forbidden in content or forbidden in model or forbidden in app:
        raise SystemExit(f"Forbidden app-source contract token present: {forbidden}")

print("UI/UX contract: PASS — exactly 25 ledgered improvements and required source contracts present")
