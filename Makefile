.PHONY: build run test app dmg audit preview bug-sweep clean

build:
	swift build

run:
	swift run DexCleaner

test:
	swift test

app:
	./scripts/build_app_bundle.sh

dmg:
	./scripts/package_dmg.sh

audit:
	./scripts/audit_read_only.sh

preview:
	./scripts/safe_cleanup_preview.sh

bug-sweep:
	swift test
	swift build
	swift package describe >/dev/null
	python3 -m json.tool Sources/DexCleanerCore/Resources/CleanupManifest.json >/dev/null
	bash -n scripts/*.sh
	! grep -RIn "\.skipsHiddenFiles" Sources/DexCleanerCore
	! grep -RIn "FileManager.default.removeItem" Sources

clean:
	rm -rf .build
