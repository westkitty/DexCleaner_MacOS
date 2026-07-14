.PHONY: build run test app verify-app dmg audit preview bug-sweep

build:
	swift build

run:
	swift run DexCleaner

test:
	swift test

app:
	bash scripts/build_app_bundle.sh

verify-app:
	plutil -lint .build/DexCleaner.app/Contents/Info.plist
	codesign --verify --deep --strict .build/DexCleaner.app

dmg:
	bash scripts/package_dmg.sh

audit:
	bash scripts/audit_read_only.sh

preview:
	bash scripts/safe_cleanup_preview.sh

bug-sweep:
	swift test
	swift build
	swift package describe >/dev/null
	swiftc -parse Sources/DexCleaner/*.swift
	python3 -m json.tool Sources/DexCleanerCore/Resources/CleanupManifest.json >/dev/null
	bash -n scripts/*.sh
	! grep -RIn "FileManager.default.removeItem" Sources
	! grep -RIn "ServiceManagement\|SMAppService\|backgroundTimer\|Background scan" Sources
	! grep -RIn "\.skipsHiddenFiles" Sources/DexCleanerCore
	grep -q "withTaskCancellationHandler" Sources/DexCleaner/AppModel.swift
	grep -Eq "\*DexCleanerCore\.(resources|bundle)" scripts/build_app_bundle.sh
	grep -q "mandatoryExcludedLargeFileRelativePaths" Sources/DexCleanerCore/DiskScanner.swift
