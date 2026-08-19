# Claude Desktop VM Bundle Review — 2026-07-28

## Executive result

- **What the bundle is:** a Claude Cowork local-execution virtual-machine (VM) bundle. Its `.cowork-adopted` marker, Linux-root image files, EFI variables, VM IP, machine identifier, and gVisor MAC address identify it as the local Cowork VM, not a generic Claude cache.
- **Feature owner:** Claude Cowork local execution. Anthropic documents that Cowork code execution runs in an isolated Linux VM on macOS through Apple Virtualization.framework.
- **Active at inspection:** no. No Claude Desktop process, Claude helper, Claude Code/VM process, virtualization-related matching process, open handle on the bundle or its direct image files, or mounted-image indicator was present in the one grouped inspection.
- **Regeneratable:** unproven. Anthropic’s official documentation confirms the VM dependency and the consequence of an unavailable VM, but the one permitted documentation check found no supported macOS procedure to delete, reset, download, or rebuild `claudevm.bundle`.
- **Moved to Trash:** no.
- **Bytes moved:** 0 bytes.
- **Expected eventual reclaim:** 0 bytes now. The bundle currently consumes 6,843,224,064 allocated bytes (6,682,836 KiB; about 6.37 GiB), but this is only a potential future reclaim if a supported reconstruction path and non-unique-state proof are established.
- **Rollback path:** not applicable; the original bundle remains in place at `/Users/andrew/Library/Application Support/Claude/vm_bundles/claudevm.bundle`. No Trash item was created.
- **Unresolved questions:** whether `sessiondata.img` contains any uniquely retained local VM/session state; the supported macOS reset/removal/re-download mechanism; the exact download/rebuild cost; and whether Cowork/local execution remains enabled for this account or device.

## Evidence

### Application identity

- Application: `/Applications/Claude.app`
- Bundle identifier: `com.anthropic.claudefordesktop`
- Version/build: `1.24012.9`

### Bundle structure, type, and sizes

All direct children are regular files; the containing item is a directory bundle. Logical size is the file length. Allocated size is filesystem blocks multiplied by 512 bytes.

| Item | Logical bytes | Allocated bytes | Created | Last modified |
|---|---:|---:|---|---|
| `rootfs.img` | 10,737,418,240 | 5,533,450,240 | 2026-07-22 18:38:28 -0400 | 2026-07-22 23:44:44 -0400 |
| `rootfs.img.zst` | 1,282,869,201 | 1,282,871,296 | 2026-07-22 18:38:28 -0400 | 2026-07-22 18:40:47 -0400 |
| `sessiondata.img` | 48,058,368 | 26,746,880 | 2026-07-22 18:40:48 -0400 | 2026-07-22 23:44:44 -0400 |
| `efivars.fd` | 131,072 | 131,072 | 2026-07-22 23:31:30 -0400 | 2026-07-22 23:31:30 -0400 |
| `.cowork-adopted`, origin markers, VM identity/IP/MAC metadata | 178 combined | 20,480 combined | 2026-07-22 | 2026-07-22 |
| **Whole `claudevm.bundle`** | **12,068,480,000** (apparent, `du -A`) | **6,843,224,064** (allocated, `du`) | 2026-07-22 18:38:28 -0400 | directory 2026-07-22 23:31:36 -0400 |

The expanded `rootfs.img` is sparse: it has a 10.0 GiB logical length but 5.15 GiB allocated. The compressed `rootfs.img.zst` separately consumes about 1.19 GiB. They are not established as duplicate disposable files: both are integral members of the one Cowork VM bundle, and the origin markers indicate the compressed and expanded images have distinct VM-runtime roles. Their exact reconstruction relationship was not documented by Anthropic in the permitted check.

### Activity, mounting, and duplication

- `lsof` returned no open handles for the bundle or its direct images.
- Process inspection returned no Claude, Claude helper, Claude Code/VM, or matching virtualization process.
- `mount` and `hdiutil info` returned no indicator that this bundle or its images are mounted.
- A bounded search of the immediate `vm_bundles` parent found exactly one `.bundle`: `claudevm.bundle`. No duplicate or obsolete VM-bundle version was found there.
- The last file modifications were 2026-07-22. This matches the prior forensic report’s date and gives no sign of activity after that date. A single current measurement plus the prior approximate total cannot prove a no-growth trend, so continued-growth status remains unproven.

### Feature dependency and current enablement

- The `.cowork-adopted` file directly associates the bundle with Cowork.
- Anthropic states that Claude Cowork runs code in an isolated VM on the computer and that, for local desktop sessions on macOS, the isolated Linux VM uses Apple Virtualization.framework. [Install Claude Desktop](https://support.claude.com/en/articles/10065433-install-claude-desktop) and [Claude Cowork architecture overview](https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview).
- Anthropic states that if the VM cannot start, local Cowork file and web tools can continue, but shell commands and code execution report that the workspace is unavailable. [Claude Cowork architecture overview](https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview).
- The marker proves prior Cowork VM adoption, not that Cowork is currently enabled in account/device policy. Preference and session contents were intentionally not inspected.
- Computer use is available in Cowork/Claude Code, but the evidence does not tie this bundle specifically to computer-use activity rather than Cowork’s general local code-execution sandbox. [Let Claude use your computer in Cowork](https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork).

### Supported removal, rebuild, and download behavior

The sole official Anthropic documentation check confirmed the VM’s Cowork function and the consequence of VM unavailability. It did **not** provide a supported macOS UI, command, reset, deletion, redownload, or rebuild procedure for this path. Therefore:

- automatic re-download after removal: unverified;
- expected download/rebuild cost: unverified;
- safe supported removal mechanism: unverified;
- exclusivity of local state: unverified, particularly because `sessiondata.img` exists and its contents were deliberately not read.

## Decision

**Review required — left untouched**

The bundle was inactive at the inspection moment and is confirmed to belong to Cowork’s local VM. However, the mandatory cleanup conditions were not all established: there is no documented supported reconstruction/removal mechanism, no verified re-download behavior or cost, and no proof that `sessiondata.img` holds no unique user/session state. Moving it to Trash would be an unsupported state change with an unknown recovery path. No conditional move was performed.

## Rollback

No rollback is needed because nothing was moved.

- Original destination, still present: `/Users/andrew/Library/Application Support/Claude/vm_bundles/claudevm.bundle`
- Finder Trash rollback path: none; no Trash item was created.

## Safety confirmation

- No permanent deletion occurred.
- Finder Trash was not emptied.
- No conversation or session contents were inspected.
- No unrelated Claude state changed; no sessions, credentials, preferences, logs, `local-agent-mode-sessions`, `claude-code`, `claude-code-vm`, caches, or other Claude directories were modified.
- No other application or storage category changed.
- No broad storage scan, build, update, reinstall, application-bundle modification, image mount/edit, or application launch occurred.
