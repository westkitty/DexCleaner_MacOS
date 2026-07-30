# Obsolete DiskMonitor Retirement Record

Date: 2026-07-28 (America/Detroit)

## Identified owner

- Visible legacy menu-bar utility: `DiskMonitor`.
- Running process before disablement: PID `32367`, parent PID `1`, executable `/Users/andrew/.disk_monitor/DiskMonitor`.
- Executable: unsigned standalone arm64 Mach-O, 95,512 bytes, SHA-256 `0f952b72b171f26af5a532d5fcec22bb3230f72dbf97e7fd4c7cfe73dfb7e313`.
- Launch mechanism: user LaunchAgent `/Users/andrew/Library/LaunchAgents/com.andrew.diskmonitor.plist`, label `com.andrew.diskmonitor`, with both `RunAtLoad` and `KeepAlive`.
- Background-item registration: legacy agent `8.com.andrew.diskmonitor`, enabled before disablement.

## Retirement boundary

Only the `com.andrew.diskmonitor` service is disabled and booted out.  Its executable and LaunchAgent plist remain in place, unmodified, as the rollback evidence.  No unrelated menu-bar process, app, login item, or LaunchAgent is changed.

Post-disable verification: `launchctl print-disabled gui/501` reports
`com.andrew.diskmonitor => disabled`; the PID is absent; the preserved
executable still has the SHA-256 recorded above.  The only remaining custom
storage utility process is `/Applications/DexCleaner.app/Contents/MacOS/DexCleaner`.

## Reversal

If the legacy utility must be restored deliberately, enable and bootstrap only this label:

```sh
launchctl enable gui/501/com.andrew.diskmonitor
launchctl bootstrap gui/501 /Users/andrew/Library/LaunchAgents/com.andrew.diskmonitor.plist
```
