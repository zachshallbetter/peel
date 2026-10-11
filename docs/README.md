# Peel documentation

**Start here for what exists in code:** [`SHIPPED.md`](SHIPPED.md).  
Most other docs are **targets, design, or research**. Do not implement against identity/Pro/MCP/create claims unless SHIPPED.md lists them.

Canonical documents use lowercase kebab-case names. Versions live in each document header.

| File | Purpose |
| --- | --- |
| **`SHIPPED.md`** | **Source of truth: shipped vs scaffold vs roadmap** |
| `specification.md` | Target requirements (not a HEAD feature list) |
| `architecture.md` | System architecture overview |
| `containers.md` | Formats, volume resolution, and container graph |
| `finder-quicklook.md` | Finder integration, Quick Look, and archive navigation |
| `macos-system-integration.md` | FSKit, QL, Spotlight, coordination, Disk Arbitration, CryptoKit investigation |
| `fskit-peelfs.md` | PeelFS FSKit extension spike (MAC-004) |
| `finder-open-interaction.md` | Double-click open / browse vs extract contract |
| `peelfs-xpc-bridge.md` | PeelFS/QL → peel-core XPC design |
| `golden-gate.md` | Liquid-glass visual system (Snack Studio) |
| `roadmap-next.md` | Near-term implementation checklist |
| `encryption.md` | Encryption auditing, recovery, and repair |
| `encryption-architecture.md` | Encryption and recovery system design |
| `encryption-research.md` | Research survey and constraints |
| `product-identity.md` | Identity/monetization **roadmap** (not shipped Pro/MCP/create) |
| `competitive.md` | Competitor and positioning analysis |
| `review.md` | Implementation review and remediation |
| `reflective-rust.md` | Optional future notes — **not integrated**; no MCP |

## Consolidation

- Prefer [`SHIPPED.md`](SHIPPED.md) over any aspirational matrix in identity/spec docs.
- Removed old prefixed PEEL_* filenames in favor of kebab-case docs.
- `product-identity.md` and `reflective-rust.md` corrected 2026-10-11: roadmap-only claims (no MCP/Pro/create as shipped).
