# What Peel actually ships (read this first)

**Updated:** 2026-10-11  
**Rule:** Design and evaluate against this file, not aspirational product essays.  
If a doc disagrees with this table, **this table wins** until code lands and this file is updated.

## Repository reality

- Young tree (scaffold + macOS product commits on `feat/macos-peel-app-services`).
- Engine: `crates/peel-core`, `peel-cli`, `peel-ffi`.
- App: `app/Peel` (+ PeelFS + QL scaffold extensions).
- Org remote: `https://github.com/SnackStudio/peel` (private).

## Shipped (code exists and is the intended product path)

| Area | What exists |
| --- | --- |
| **Extract** | ZIP, TAR/GZ/BZ2, RAR, 7z via peel-core; CLI `extract` / `list` / `test` / `probe` / `formats` |
| **macOS app** | SwiftUI Peel; drop / Open; Services (Peel, Peel to…, Peel & Reveal); silent HUD; Settings/Setup |
| **Browse on open** | Default double-click → browse volume (sibling cache + single-root promote) or try PeelFS mount; same-window Finder retarget when Automation allows |
| **PeelFS** | FSKit extension **in tree**; mount often **OS-disabled** (`Module … is disabled!`) — fallback is required |
| **Browse cache** | TTL/size caps, Settings clear, meta under Application Support / sibling |
| **CLI agents** | JSON-ish `probe` / `formats` / list — **not** an MCP server |

## Scaffold only (do not design as finished product)

| Area | Reality |
| --- | --- |
| **Quick Look** | `app/PeelQLPreview` ZIP listing scaffold — not a polished/qualified Finder preview product |
| **PeelFS live mount** | Code path first; production mount **blocked** on current OS/signing until Gate A passes |
| **peel-ffi / PeelKit** | Present; not a full public SDK story |
| **capabilities.rs** | Started; not the sole driver of all UI yet |

## Not shipped (roadmap / proposal only — no implementation to build on)

| Claim sometimes seen in docs | Status |
| --- | --- |
| **MCP server** / `peel_*` tools | **Not implemented** |
| **Create / compress / writers** | **Not implemented** |
| **Peel Pro** / forgotten-password recovery | **Proposal only** (`product-identity.md`) |
| **Encryption audit UI**, migrate/re-encrypt product flows | **Not implemented** |
| **Verified** integrity product, repair | **Not implemented** as product features |
| **Windows / Linux shells** | **Not implemented** |
| **Spotlight importer**, File Provider library | **Not implemented** |
| **Reflective Rust** envelopes / derive in peel-core | **Not integrated** |
| **Full archive browser** (in-app tree, selective extract UI) | **Partial at best** — do not assume complete |
| **Open one entry** without full materialize | **Not a finished API** for QL/FS |

## How other docs must be labeled

| Doc | Treat as |
| --- | --- |
| `specification.md` | **Target** architecture & requirements — not a feature checklist of HEAD |
| `product-identity.md` | **Product/roadmap decisions** — Free/Pro matrix is **targets** |
| `finder-quicklook.md` | **Design + FND tickets**; QL is scaffold |
| `encryption*.md` | **Research / design** |
| `reflective-rust.md` | **Optional future** integration notes |
| `finder-open-interaction.md` | **Interaction contract** + honest “current reality” §9 |
| `peelfs-xpc-bridge.md` | **Design only** |
| `competitive.md`, `golden-gate.md` | Positioning / visual — not engine claims |

## Update process

When you merge a real capability:

1. Add/adjust a row under **Shipped** or move out of **Not shipped**.
2. Soften or date-stamp the aspirational doc section.
3. Prefer linking here from README and `docs/README.md`.
