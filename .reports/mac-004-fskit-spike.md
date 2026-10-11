# MAC-004 — PeelFS enablement status

## What you saw

- **Three “Peel / FSKit Modules” rows** → multiple `Peel.app` copies registered the same extension (Applications + `dist/` + DerivedData builds). Clean DerivedData; keep **one** `/Applications/Peel.app`.
- **FSKit Modules toggle ON** under Peel Extensions → correct UI action.
- **`mount` still: `Module io.snackstud.peel.PeelFS is disabled!`** even when `pluginkit` shows `+` and Development signing is applied.

## Diagnosis on this machine

| Check | Result |
| --- | --- |
| appex embedded | `/Applications/Peel.app/Contents/Extensions/PeelFSExtension.appex` |
| pluginkit | `+ io.snackstud.peel.PeelFS` after `pluginkit -e use` |
| Settings toggle | ON |
| codesign | Apple Development, Team `PKH7G93GGD` |
| fskitd log | `Incoming connection, entitled 1` then client exits — module still disabled for mount |
| mount | code 69 / “disabled” |

So the toggle is **not lying about category enablement**, but **fskitd will not start the module** for path mounts. That matches known third-party FSKit pain (restricted entitlement must be on the provisioning profile; some macOS builds also leave modules inert after UI enable).

## Product mitigation (shipped in code)

Double-click browse path:

1. Try FSKit `mount -F -t PeelFS`
2. If disabled → **materialize browse cache** under `~/Library/Caches/Peel/Browse/…` via peel engine and **open that folder in Finder**

User still gets “open like a folder”; Services remain full extract. When Apple/FSKit enablement works, step 1 succeeds and no cache is needed for ZIP.

## What you should do

1. Leave **FSKit Modules** ON (done).
2. Run `./scripts/enable-peelfs.sh` after each reinstall.
3. Delete extra Peel apps so only one Settings row remains:
   - Keep `/Applications/Peel.app`
   - `rm -rf ~/Projects/peel/.build/DerivedData-*` (already cleaned once)
4. Apple Developer → request/confirm **FSKit / fskit.fsmodule** capability for team `PKH7G93GGD`, then rebuild with automatic provisioning (not ad-hoc).
5. Re-test: `./scripts/mount-peelfs.sh sample.zip`

Until (4) works, rely on browse-cache fallback for double-click.
