# Feedback Assistant draft — PeelFS module disabled on mount

**Area:** macOS → File System / FSKit / Extensions  
**Title:** FSKit module enabled in PluginKit and Settings but `mount -F -t PeelFS` reports “Module … is disabled!”

## Summary

Third-party FSKit filesystem extension `io.snackstud.peel.PeelFS` is:

- Embedded in `/Applications/Peel.app`
- Signed with Apple Development (Team `PKH7G93GGD`)
- Entitlement `com.apple.developer.fskit.fsmodule` present on the appex **and** in the embedded Mac Team provisioning profile
- Shown as **enabled** (`+`) by `pluginkit -m -i io.snackstud.peel.PeelFS`
- Toggle ON under System Settings → Extensions → Peel → FSKit Modules

Yet:

```text
$ mount -F -t PeelFS /path/to/archive.zip /tmp/mnt
Module io.snackstud.peel.PeelFS is disabled!
mount: Unable to invoke task
```

`fskitd` logs show an entitled incoming connection, “About to get current agent for <uid>”, then the peer connection is invalidated when the client exits. No actionable deny reason is surfaced to the developer.

## Why it matters

Peel is building archive-as-folder (Windows compressed-folder style) via FSKit. Without a working path-URL mount, the product must fall back to materializing a browse cache, which is slower and less native.

## Environment

- See attached `diagnostics.txt` in this folder (and optionally a full **sysdiagnose**).
- macOS version: fill from `sw_vers` in diagnostics.
- App: `io.snackstud.peel` / extension `io.snackstud.peel.PeelFS`
- Extension point: `com.apple.fskit.fsmodule`
- Personality short name: `PeelFS`

## Reproduction

1. Install Development-signed `/Applications/Peel.app` containing `Contents/Extensions/PeelFSExtension.appex`.
2. System Settings → Extensions → Peel → enable **FSKit Modules**.
3. `pluginkit -e use -i io.snackstud.peel.PeelFS`
4. Confirm: `pluginkit -m -i io.snackstud.peel.PeelFS` shows `+`.
5. Confirm profile contains FSKit:

   ```bash
   codesign -d --entitlements :- /Applications/Peel.app/Contents/Extensions/PeelFSExtension.appex
   security cms -D -i …/embedded.provisionprofile   # com.apple.developer.fskit.fsmodule = true
   ```

6. Mount:

   ```bash
   mkdir -p /tmp/peelfs-mnt
   mount -F -t PeelFS -o rdonly "$HOME/Downloads/some.zip" /tmp/peelfs-mnt
   ```

**Expected:** mount succeeds; archive browsable at mount point.  
**Actual:** `Module io.snackstud.peel.PeelFS is disabled!`

## Attachments checklist

- [x] `diagnostics.txt` (pluginkit, codesign, profile, mount stderr)
- [ ] **sysdiagnose** (run below; attach the `.tar.gz`)
- [ ] Screenshot of Extensions → Peel → FSKit Modules ON
- [ ] Optional: Console export filtered to `fskitd` during mount

## sysdiagnose (run locally before submit)

```bash
# Takes several minutes; creates a large archive on Desktop (path may vary)
sudo sysdiagnose -f ~/Desktop -A PeelFS-mount-disabled
```

Or: Spotlight → **Feedback Assistant** → new feedback → attach sysdiagnose when prompted.

## Open questions for Apple

1. Is path-URL `mount -F -t <personality>` supported for third-party FSKit modules on this OS build, or only block devices?
2. If PluginKit shows `+` and the restricted entitlement is on the profile, what additional gate still marks a module “disabled” for mount?
3. Where should developers read a definitive enablement/denial reason (log key / API)?

## Project references

- Extension sources: `app/PeelFSExtension/`
- Report: `.reports/mac-004-fskit-spike.md`
- Interaction contract: `docs/finder-open-interaction.md` §10
