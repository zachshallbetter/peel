# MAC-004 — PeelFS enablement status

**Updated:** 2026-10-11 (after browse-on-open commit)

## Goal

True native open: `mount -F -t PeelFS archive.zip mountpoint` succeeds so double-click does not materialize a browse cache.

## Current machine state

| Check | Result |
| --- | --- |
| macOS | 27.0 (26A428) |
| appex embedded | `/Applications/Peel.app/Contents/Extensions/PeelFSExtension.appex` |
| codesign | Apple Development: Zach Shallbetter (7A6YC359BE), Team `PKH7G93GGD` |
| codesign entitlements | `com.apple.developer.fskit.fsmodule` = true |
| embedded provision profile | **Mac Team Provisioning Profile: io.snackstud.peel.PeelFS** |
| profile entitlements | **`com.apple.developer.fskit.fsmodule` = True** |
| pluginkit | **`+ io.snackstud.peel.PeelFS(0.2.0)`** (enabled) |
| Settings FSKit Modules | User reports ON |
| `mount -F -t PeelFS …` | **`Module io.snackstud.peel.PeelFS is disabled!`** / Unable to invoke task |
| fskitd log on mount | `Incoming connection, entitled 1` → `About to get current agent for 501` → peer connection invalidated (client exits). No clearer deny reason in stream. |

### Conclusion

This is **not** a missing entitlement or a pluginkit off state. Signing + profile + PluginKit enablement all look correct. **fskitd still refuses to run the module for path mounts.** That matches third-party FSKit “enabled but unmountable” behavior on some OS builds.

Product must keep **browse-volume fallback** as the shipping open path until mount works.

## Duplicates

Also present:

- `/Applications/Peel.app` (canonical)
- `~/Projects/peel/dist/Peel.app` (build output)

Prefer a single Applications install for Settings/Automation coherence. `dist/` is expected build artifact; avoid opening it as the daily app.

## What we already ship around the blocker

1. Try FSKit mount first (`PeelFSMount`).
2. Else sibling browse cache + single-root promote + same-window Finder retarget.
3. Docs: `docs/finder-open-interaction.md` §10 path-to-native; `docs/fskit-peelfs.md`.

## Next actions (Gate A)

1. **Apple Developer / FSKit program** — confirm third-party FSKit modules are permitted for team `PKH7G93GGD` on this OS train; request capability review if needed (profile already contains the key, so this may be OS policy not portal).
2. **Feedback Assistant** — sysdiagnose + mount reproduction + note pluginkit `+` and profile has `fskit.fsmodule` yet mount says disabled.
3. **Re-test each OS update** — `./scripts/enable-peelfs.sh` then `./scripts/mount-peelfs.sh sample.zip`.
4. **Do not** invest in a second long-term ZIP parser in the appex until mount works; production PeelFS still targets peel-core over XPC (interaction doc §10.3).
5. Optional: unregister `dist/Peel.app` from Launch Services so only Applications is claimed.

## Commands

```bash
DEVELOPMENT_TEAM=PKH7G93GGD INSTALL=1 ./scripts/build-app.sh
./scripts/enable-peelfs.sh
./scripts/mount-peelfs.sh ~/path/to/file.zip
pluginkit -m -i io.snackstud.peel.PeelFS
codesign -d --entitlements :- /Applications/Peel.app/Contents/Extensions/PeelFSExtension.appex
```
