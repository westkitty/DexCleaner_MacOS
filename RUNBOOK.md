# DexCleaner Runbook

Use these commands after cloning the repository.

## Bug sweep

```bash
swift test
swift build
swift package describe >/dev/null
python3 -m json.tool Sources/DexCleanerCore/Resources/CleanupManifest.json >/dev/null
bash -n scripts/*.sh
! grep -RIn "\\.skipsHiddenFiles" Sources/DexCleanerCore
! grep -RIn "FileManager.default.removeItem" Sources
```

## Script targets without executable-bit assumptions

GitHub connector uploads may not preserve executable bits. Use `bash` explicitly:

```bash
bash scripts/audit_read_only.sh
bash scripts/safe_cleanup_preview.sh
bash scripts/build_app_bundle.sh
bash scripts/package_dmg.sh
```

## macOS validation

Run on macOS 13 or later:

```bash
swift test
swift build
swift run DexCleaner
bash scripts/build_app_bundle.sh
open .build/DexCleaner.app
bash scripts/package_dmg.sh
```

## Safety reminder

Do not broaden cleanup rules, do not add permanent deletion, and do not weaken `SafetyEngine`.
