# Peel — Finder open interaction

**Version:** 0.2.0  
**Date:** 2026-10-10  
**Status:** Product interaction contract (intended UX + current implementation notes)  
**Related:** `fskit-peelfs.md`, `finder-quicklook.md`, `macos-system-integration.md`, `product-identity.md`

## 1. Goal

When the user opens a compressed archive **directly** from Finder (double-click or Open With → Peel), the archive should **feel like opening a folder**: same Finder window, contents visible, no Peel chrome. Full extraction is a separate, explicit action.

Tagline alignment: **Open what's inside** — browse first; peel (extract) on purpose.

## 2. Primary interaction: open archive (double-click / Open With)

### 2.1 Intended behavior

| Step | Behavior |
| --- | --- |
| 1. User double-clicks archive (or Open With Peel) | Launch Services delivers the file to Peel |
| 2. Peel presence | **Passive helper**: no main window, no Dock flash, no setup sheet |
| 3. Destination surface | **Finder only** — never a new Peel document window |
| 4. Navigation | **Same Finder window/tab** that held the archive navigates into contents |
| 5. Back | Finder Back returns to the parent folder; the archive file remains |
| 6. Mental model | “I opened the archive like a folder,” not “an app unzipped something for me” |
| 7. Lifetime | Browse is a **session/cache**, not a permanent extract product |

### 2.2 Ideal backend (PeelFS)

```text
Downloads/
  project.zip          ← still a file
       │
       ▼  double-click
  PeelFS read-only mount (archive-as-folder)
       │
       ▼  same Finder window target
  [archive root entries]
    README.md
    src/
    …
```

- Mount is **read-only**.
- Reads map to archive I/O with budgets/cancellation (see `finder-quicklook.md` PeelFS contract).
- Eject/unmount cleans up; original archive is unchanged.
- Opening an entry in an external app may create plaintext copies outside Peel — warn where relevant.

### 2.3 Fallback backend (browse volume)

When macOS does not load PeelFS (`Module … is disabled` or format not mountable yet):

```text
Downloads/
  project.zip
  project/             ← Peel-managed browse cache (sibling when free)
    .peel-volume-meta.json   (hidden)
    README.md                (single top-level zip wrappers are promoted)
    src/
```

Rules:

1. Prefer a **sibling folder** next to the archive (natural Back target = same parent).
2. If the sibling name collides with a non-Peel folder, use  
   `~/Library/Application Support/Peel/Volumes/<name>/`.
3. After materialize, **promote** a sole top-level directory so the browse root matches “opened contents,” not a nested GitHub-style wrapper.
4. Browse volumes are **TTL- and size-capped caches** (default 24h / ~2 GB), clearable from Settings — not permanent extracts.
5. Finder must be **retargeted** with AppleScript `set target of Finder window …`  
   - **Never** `NSWorkspace.open` / Finder `open` when a window exists (creates a new tab).
   - Requires **Automation → Peel → Finder** once.
6. Log diagnostics to `~/Library/Logs/Peel/browse.log`.

### 2.4 Preference

| Key | Default | Meaning |
| --- | --- | --- |
| `peel.browseOnOpen` | **true** | Double-click / Open With uses browse (mount or volume), not full extract |

User can turn this off in Setup/Settings → Browse & PeelFS. When off, open uses the extract path (§3).

### 2.5 Success criteria (acceptance)

- [ ] No Peel main window flash on double-click  
- [ ] No new Finder tab when Automation is granted and a Finder window exists  
- [ ] Same window shows archive contents (or promoted browse root)  
- [ ] Back returns to the folder containing the archive  
- [ ] Archive file is not deleted or replaced  
- [ ] Second open of the same archive reuses cache/mount when stamp matches  
- [ ] Large/solid archives show bounded progress or honest wait — never hang forever without cancel path (mount path)  

### 2.6 Failure behavior

| Failure | User-visible result |
| --- | --- |
| PeelFS unavailable | Silent fallback to browse volume (no error UI if volume succeeds) |
| Format not browsable | Fall through to extract path if open must complete, or clear status without main window |
| Automation denied | Same-window nav may fail; **do not** open a new tab via NSWorkspace; Settings offers “Allow Finder Control…” |
| Materialize/mount error | Stay passive; optional future HUD; no setup sheet |

---

## 3. Secondary interaction: extract (“Peel”)

Extract is **explicit**. It must not be confused with open-as-folder.

### 3.1 Entry points

| Entry | Behavior |
| --- | --- |
| Finder **Services → Peel** | Extract beside source (or policy default); silent HUD if enabled |
| **Services → Peel to…** | Folder picker, then extract |
| **Services → Peel & Reveal** | Extract and reveal results in Finder |
| Drop on Peel window | Extract in-window (interactive) |
| Peel UI Open… / buttons | Browse if enabled+supported, else extract |
| Double-click with `browseOnOpen = false` | Extract (silent HUD if `silentBackgroundExtract`) |

### 3.2 Extract defaults

| Preference | Default | Notes |
| --- | --- | --- |
| `peel.extractBesideSource` | true | Output under archive parent |
| `peel.revealAfterExtract` | true | Reveal when appropriate |
| `peel.silentBackgroundExtract` | true | Services/use HUD, not main window |
| `peel.deleteArchiveAfterExtract` | false | Never delete unless user opts in |

Extract creates durable user files. Browse volumes do not replace extract.

---

## 4. Related Finder surfaces (not “open archive”)

These are separate from double-click open; see `finder-quicklook.md`.

| Surface | Intended role |
| --- | --- |
| **Quick Look (Space)** | Archive-level preview; list/metadata; actions Browse / Extract — **not shipped as of this doc’s implementation focus** |
| **Open one entry** | Materialize one member on demand |
| **Context menu** | Browse as Folder / Extract Here / Inspect — wire as available |
| **Spotlight** | Future: search inside without unpack (`macos-system-integration.md`) |

---

## 5. Passive model (open path)

```text
Finder double-click / Open With
        │
        ▼
AppDelegate (passive, accessory)
        │
        ▼
AppState.enqueueOpen(url)
        │
        ├─ browseOnOpen && supportsBrowse?
        │         │
        │         ▼
        │   capture FinderContext (window id + parent path)
        │         │
        │         ▼
        │   PeelFSMount.mount(url)
        │         ├─ try FSKit PeelFS
        │         └─ else materialize browse volume (+ promote single root)
        │         │
        │         ▼
        │   navigateFinder(same window only)
        │
        └─ else extract(silent per prefs)
```

**Single owner for file opens:** `application(_:open:)` only.  
SwiftUI `onOpenURL` must **not** re-handle local file URLs (duplicate open → extra Finder tabs).

---

## 6. Permissions and Settings copy

| Permission / setting | Why |
| --- | --- |
| **Automation → Peel → Finder** | Same-window `set target` without new tabs |
| **Extensions → Peel → FSKit Modules** | Real archive-as-folder mount when OS allows |
| **Default app for zip/rar/7z…** | Double-click reaches Peel instead of Archive Utility |
| Settings: Allow Finder Control… | Triggers TCC registration + prompt |
| Settings: Clear browse cache | Removes Application Support volumes (and tracked siblings via policy) |

---

## 7. What “open” must never mean

1. Archive Utility–style expand that leaves a permanent sibling as the *only* model  
2. New Finder tab to `Application Support` or `/tmp` as the happy path  
3. Flashing full Peel UI for a passive open  
4. Silent full extract of multi-GB archives when the user only wanted to look inside  
5. Write-through edits on mounted/browse paths (v1 is read-only browse)  
6. Promising the `.zip` path itself becomes a directory without a filesystem bridge  

---

## 8. Implementation map (code)

| Concern | Location |
| --- | --- |
| Open routing | `app/Peel/AppState.swift` → `enqueueOpen` |
| Passive launch / no window | `app/Peel/AppDelegate.swift` |
| Mount + browse volume + Finder nav | `app/Peel/PeelFSMount.swift` |
| Prefs | `app/Peel/PeelPreferences.swift` (`browseOnOpen`) |
| Setup / Settings UI | `SetupView`, `PeelFSSettingsViews`, `SettingsPage` |
| PeelFS extension | `app/PeelFSExtension/` |
| FSKit notes | `docs/fskit-peelfs.md` |

---

## 9. Current reality (honest)

| Capability | State |
| --- | --- |
| Passive open, no Peel window | Implemented |
| Browse-on-open default | Implemented (`browseOnOpen = true`) |
| Same-window Finder retarget | Implemented (needs Automation) |
| Single-root promote | Implemented |
| Sibling browse cache | Implemented |
| PeelFS live mount | Blocked when OS reports module disabled; code path kept first |
| Quick Look extension | Not shipped |
| True “path is the .zip” | Requires working PeelFS |

Until PeelFS mounts, open still **materializes** a cache under the hood. UX must keep feeling like folder navigation (same window, Back works, no new tab), not like Archive Utility.

---

## 10. Path to ideal (completely native)

Native means: double-click feels like Finder opened a folder — **no unzip side-effect**, **no AppleScript**, **no Automation prompt**, **instant directory listing**, **on-demand reads**. That is only achievable with a real filesystem surface (PeelFS), not a materialized cache.

### 10.1 What “native” requires

| Native cue | Mechanism |
| --- | --- |
| Same window, no new tab | Finder navigates a **real path** (mount point or path-URL volume); no `NSWorkspace.open` |
| Instant open | List directory from archive index; **do not** decompress the whole archive first |
| Open a file | FSKit `read` → peel-core materializes **that entry only** |
| Quick Look / drag / apps | Ordinary POSIX paths on the mount |
| Back / path bar | Mount sits in a predictable place; optional volume name = archive stem |
| No Peel UI | Host stays accessory; extension runs in fskitd |
| No permanent clutter | Unmount on eject / idle; no sibling extract folder |

Browse-volume fallback can **approximate** navigation but cannot be fully native: it still unpacks, needs Automation, and leaves cache folders.

### 10.2 Critical gate: FSKit module actually mounts

Today the extension embeds and Settings can show FSKit ON / pluginkit `+`, yet:

```text
mount -F -t PeelFS …  →  Module io.snackstud.peel.PeelFS is disabled!
```

**Workstream A — make the module loadable**

1. Single install only: `/Applications/Peel.app` (no DerivedData/dist duplicates → one Extensions row).
2. Development **and** distribution profiles with Apple’s **FSKit / `com.apple.fskit.fsmodule`** capability for team `PKH7G93GGD` (restricted entitlement on the appex).
3. After each install: `./scripts/enable-peelfs.sh`; verify `pluginkit -m -i io.snackstud.peel.PeelFS` shows `+`.
4. Gate: `./scripts/mount-peelfs.sh sample.zip` returns 0 and `mount` lists PeelFS.
5. If still disabled on shipping OS builds: track as OS limitation; keep fallback; file Feedback with sysdiagnose + fskitd logs.

Without A, every other native polish is blocked for true mount UX.

### 10.3 Workstream B — production PeelFS (not the ZIP spike)

Current appex uses an in-process minimal ZIP reader (`ZipArchiveReader`). That is a spike only.

| Step | Work |
| --- | --- |
| B1 | XPC (or FSKit resource + helper) from appex → **peel-core** for list/read; one parser stack |
| B2 | Streaming / ranged reads for stored+deflate ZIP; budgets + cancel on every read |
| B3 | ZIP64, encrypted listing lock, nested containers per policy |
| B4 | RAR/7z/tar via core adapters with honest “solid = may stage” behavior |
| B5 | Mount lifecycle: activate, unmount, archive replaced, crash cleanup, no-write (`EROFS`) |
| B6 | Security: path traversal, symlink rejection, bomb budgets (align PEL safety tickets) |

Acceptance: browse, Space on entry, drag-out, eject, kill-and-reopen, no full-archive extract for opening one small file (when format allows).

### 10.4 Workstream C — host open path becomes mount-first native

Once `mount` works:

1. `PeelFSMount.mount` succeeds on double-click; **skip** materialize entirely for supported formats.
2. Prefer mount point naming that feels local (e.g. volume name = archive stem; path under a stable Peel mounts root or system-provided mount URL).
3. Retarget same Finder window to the **mount root** (still useful once; later evaluate whether LS/Finder can open the mount with less scripting).
4. Idle unmount when Finder leaves the volume and no open file handles remain.
5. Fallback browse volume remains for disabled FSKit / unsupported formats only.

### 10.5 Workstream D — native-adjacent surfaces (parallel)

These make the product feel OS-integrated even before/while PeelFS stabilizes:

| Surface | Why |
| --- | --- |
| Quick Look (Space) | Inspect without open; Tier A in `finder-quicklook.md` |
| UTI + default handler | Double-click reaches Peel reliably |
| Services extract | Clear split: open = browse, Service = peel |
| Spotlight importer (later) | Search inside without unpack |

Do **not** block PeelFS on Quick Look, but ship QL early for “native” inspection.

### 10.6 Workstream E — kill the non-native tells (fallback polish)

Until A+B ship, reduce “this is an unzip app” tells:

1. Same-window only (done); never NSWorkspace open for browse.
2. Prefer sibling cache + Back; promote single-root (done).
3. Hide meta; optional dimmed/custom icon later — never show Peel window.
4. Progressive materialize if possible (list first / extract on demand) — hard without a filesystem; treat as transitional R&D, not a substitute for PeelFS.
5. One Peel.app on disk so Extensions/Automation stay coherent.

### 10.7 Sequencing

```text
Now ──────────────────────────────────────────────────────────▶ Native
 │
 ├─ E  Fallback feels like folder nav (same window, passive)     [in progress]
 ├─ A  FSKit module loads + mount sample.zip                     [P0 blocker]
 ├─ B  PeelFS → peel-core, ZIP production reads                  [P0 after A]
 ├─ C  Double-click = mount only; unmount lifecycle              [P0 after B]
 ├─ D  Quick Look + handler polish                               [P1 parallel]
 └─ B4 Format expansion (RAR/7z/…) on mount                      [P1/P2]
```

### 10.8 Decision rule

- If **A fails** on target macOS for distribution: keep browse-volume as shipping open path; document limitation; do not pretend sibling folders are mounts.
- If **A succeeds**: delete user-visible dependence on full extract for open; Automation becomes optional nicety, not a hard requirement for “new tab” avoidance (mount open can still reuse window).
- Never ship a second full ZIP parser long-term in the appex — **peel-core is source of truth**.

## 11. Changelog

| Ver | Change |
| --- | --- |
| 0.1 | (implied) extract-default open in older Finder notes |
| 0.2 | Browse-first double-click is the product default; extract is Services/explicit; document PeelFS + browse-volume contract, same-window rules, and anti-patterns |
| 0.2.1 | Path to completely native: FSKit enablement gate, production PeelFS via peel-core, host mount-first open, QL parallel, fallback anti-tells |
