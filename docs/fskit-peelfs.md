# PeelFS — open archives like Finder folders

**Full open/browse/extract interaction contract:** [`finder-open-interaction.md`](finder-open-interaction.md)

## Intended UX

Double-click a ZIP → the **archive behaves like a folder**: same Finder window shows the archive’s contents (Windows compressed-folder style). Not a peel UI, not a random `/tmp` tab.

## Implementation

1. **FSKit mount** (`mount -F -t PeelFS`) when macOS loads `io.snackstud.peel.PeelFS` — true archive-as-folder
2. Else **browse volume** (cache beside the archive when possible). Single top-level zip wrappers are promoted. Finder is **retargeted in the same window/tab** via AppleScript (`set target of …`) — never `open`/NSWorkspace when a window exists (those spawn a new tab).
3. Grant **System Settings → Privacy & Security → Automation → Peel → Finder** once so same-window navigation works.

## Enable FSKit (when OS allows)

1. Install Development-signed `/Applications/Peel.app` (`DEVELOPMENT_TEAM=PKH7G93GGD ./scripts/build-app.sh`)
2. System Settings → Extensions → Peel → **FSKit Modules** ON
3. `./scripts/enable-peelfs.sh`
4. `./scripts/mount-peelfs.sh file.zip`

If `mount` still prints `Module … is disabled`, the OS is not loading third-party FSKit modules yet; browse volumes still provide Finder navigation.

## Build

```bash
DEVELOPMENT_TEAM=PKH7G93GGD INSTALL=1 ./scripts/build-app.sh
```
