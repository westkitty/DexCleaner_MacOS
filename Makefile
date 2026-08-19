.PHONY: build run test app verify-app dmg audit preview ui-contract bug-sweep

build:
	swift build --scratch-path .build-final

run:
	swift run --scratch-path .build-final DexCleaner

test:
	swift test --scratch-path .build-final

app:
	bash scripts/build_app_bundle.sh

verify-app:
	plutil -lint "$(HOME)/Library/Application Support/DexCleaner/ReleaseCandidate/DexCleaner.app/Contents/Info.plist"
	codesign --verify --deep --strict "$(HOME)/Library/Application Support/DexCleaner/ReleaseCandidate/DexCleaner.app"

dmg:
	bash scripts/package_dmg.sh

audit:
	bash scripts/audit_read_only.sh

preview:
	bash scripts/safe_cleanup_preview.sh

ui-contract:
	python3 scripts/verify_ui_contract.py

bug-sweep:
	python3 scripts/verify_ui_contract.py
	swift test --scratch-path .build-final
	swift build --scratch-path .build-final
	swift package describe >/dev/null
	swiftc -parse Sources/DexCleaner/*.swift
	python3 -m json.tool Sources/DexCleanerCore/Resources/CleanupManifest.json >/dev/null
	bash -n scripts/*.sh
	! grep -RInE "FileManager\\.default\\.removeItem|(^|[[:space:]])unlink([[:space:]]|$$)|(^|[[:space:]])rm[[:space:]]+-[rRfF]" Sources Tests scripts
	! grep -RIn "backgroundTimer\|Background scan" Sources
	! grep -RIn "\.skipsHiddenFiles" Sources/DexCleanerCore
	grep -q "withTaskCancellationHandler" Sources/DexCleaner/AppModel.swift
	grep -Eq "\*DexCleanerCore\.(resources|bundle)" scripts/build_app_bundle.sh
	grep -q "mandatoryExcludedLargeFileRelativePaths" Sources/DexCleanerCore/DiskScanner.swift
