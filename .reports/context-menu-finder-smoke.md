# Context menu + Finder refresh smoke

**When:** 2026-10-10  
**Fixture:** `.build/ctxmenu-finder-test/`

## Results

| Test | Path | Result |
|------|------|--------|
| 1 Peel / Open With | `open -a Peel sample-a.zip` | **PASS** — `sample-a-peeled/` with one.txt, two.txt, sub/ |
| 2 Peel & Reveal | reveal-once flag + open sample-b.zip | **PASS** — `sample-b-peeled/`; flag cleared |
| 3 Peel to… (engine) | `peel x -o dest -d` | **PASS** — files under `dest/sample-c-peeled/` |
| 4 Finder refresh | Finder window open during late.zip extract | **PASS** — Finder listed peeled dirs + late.zip without relaunch |
| 5 Services install | workflows + app NSServices | **PASS** — Peel, Peel & Reveal workflows; app: Peel / Peel to… / Peel & Reveal |

## Notes

- Multi-entry zips correctly land in `*-peeled` enclosing folders.
- Finder AppleScript `update` saw new items after extract (no relaunch).
- UI folder-picker for **Peel to…** is manual; destination extract covered via engine.
- Enable Services in System Settings if menu items are greyed out.
