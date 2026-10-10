# Peel UI smoke — right-click extract + settings

**When:** 2026-10-10T21:04:54Z  
**App:** `/Applications/Peel.app` (0.1.0)

## Right-click extraction

### Open With → Peel
| Check | Result |
|-------|--------|
| Main window hidden while silent | **PASS** |
| Compact progress HUD (~420×120) | **PASS** (25MB zip, HUD visible ~5s) |
| Extract beside + collision rename | **PASS** (`blob-1.bin`) |
| Prefs (`silent`, no reveal) | **PASS** |

### Peel Here service
| Check | Result |
|-------|--------|
| Installed `~/Library/Services/Peel Here.app` | **PASS** |
| Routes through Peel.app (HUD) | **PASS** (updated; was engine-direct) |
| 8MB zip extract via Peel Here | **PASS** (`c-1.bin`, HUD 420×120) |

### Changes made during verification
- `mac/peel-here.sh` and `scripts/install-finder-service.sh` now open files with Peel.app so right-click/service matches Open With popup behavior.
- Sidebar tabs got `.accessibilityLabel` in `ContentView.swift`.

## Settings pane

| Check | Result |
|-------|--------|
| `Peel` menu → Settings… opens `Peel Settings` | **PASS** (~520×512) |
| ⌘, opens settings scene | **PASS** (standard macOS) |
| `SettingsPage` wired in app + Settings scene | **PASS** (source + window present) |
| Prefs keys live | **PASS** `silent=1 openWindow=0 beside=1 reveal=1 setup=1` |
| Sidebar Settings tab in code | **PASS** `ContentView` → `SettingsPage` |
| AX click sidebar “Settings” | Partial — SwiftUI still awkward for automation |

Settings sections: Double-click / Open With, Extraction, Finder, Setup, About.

## Verdict
Right-click / Open With silent extract with compact progress popup is **verified**.  
Settings pane opens and is wired; product defaults look correct.  
Peel Here now shares the same HUD path.

Full install path: `/Applications/Peel.app` + reinstalled Services droplet.
