# Peel — next work from docs (snapshot)

Living checklist derived from `specification.md`, `finder-quicklook.md`, `macos-system-integration.md`, `containers.md`, and `encryption*.md`. Not a release commitment.

## Now / near-term (engine + macOS product)

| Track | Items |
| --- | --- |
| Safety & contracts | PEL-002 audit all adapters; PEL-003 capability registry; PEL-004 real progress/cancel; PEL-005 staging everywhere |
| Unarchiver parity | Passwords (secure prompt); selective extract UI; multipart qualification; delete-after; encoding |
| CLI / agents | `probe`/`formats`/`verify` parity; MCP; no password on argv |
| Finder today | Services Peel / Peel to… / Peel & Reveal; silent HUD; Finder refresh (shipping) |

## Differentiating macOS surfaces

| Track | Items |
| --- | --- |
| Quick Look | FND-001…003 / MAC-002…003 |
| PeelFS | MAC-004 scaffold in-tree → live mount/signing → FND-004 |
| Search | MAC-006 Spotlight importer |
| Sessions | MAC-001 file coordination |
| Disk images | MAC-007 Disk Arbitration lifecycle |
| Secrets | MAC-008 Keychain; encryption.md recovery boundary |

## Later

Create/compress pipelines, Windows/Linux shells, File Provider library domain, Compression.framework bake-off, comics-first UX, package intelligence.

## Doc map

Start at `docs/README.md`. Architecture overview: `architecture.md`. OS deep dive: `macos-system-integration.md`.
