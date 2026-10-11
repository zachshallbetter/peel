# Peel documentation

Canonical documents use lowercase kebab-case names without product prefixes or filename version suffixes. Document versions remain in the document header.

| File | Purpose |
| --- | --- |
| `specification.md` | Product requirements and release milestones |
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
| `product-identity.md` | Identity and monetization decisions |
| `competitive.md` | Competitor and positioning analysis |
| `review.md` | Implementation review and remediation |
| `reflective-rust.md` | Reflective Rust integration notes |

## Consolidation

- Removed `PEEL_FINDER_QUICKLOOK_INTEGRATION_v0.1.md` in favor of the longer `finder-quicklook.md`.
- Removed `PEEL_ENCRYPTION_AUDIT_AND_REPAIR_v0.1.md` in favor of the longer `encryption.md`.
- Renamed the remaining prefixed documents to lowercase kebab-case names.
- Kept distinct encryption architecture, research, and product identity documents; they are related, not exact duplicates.
- No substantive content was rewritten; version metadata inside documents is retained.
