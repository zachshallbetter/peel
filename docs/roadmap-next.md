# Peel — next work from docs (snapshot)

Living checklist derived from specs/design docs. **Not a release commitment.**  
**What already ships:** [`SHIPPED.md`](SHIPPED.md). Issues: [SnackStudio/peel](https://github.com/SnackStudio/peel/issues).

## Now / near-term (engine + macOS product)

| Track | Items |
| --- | --- |
| Safety & contracts | PEL-002 audit all adapters; PEL-003 capability registry; PEL-004 real progress/cancel; PEL-005 staging everywhere |
| Unarchiver parity | Passwords (secure prompt); selective extract UI; multipart qualification; delete-after; encoding |
| CLI / agents | `probe`/`formats` (exist); `verify` still thin; **MCP not started**; no password on argv |
| Finder today | Services + HUD + browse-on-open fallback (**shipping**); PeelFS mount often OS-blocked |

## Differentiating macOS surfaces

| Track | Items |
| --- | --- |
| Quick Look | FND-001 scaffold in tree → qualify listing UI (not done) |
| PeelFS | MAC-004 extension in-tree; **mount disabled on current OS** → Feedback + Gate A |
| Search | MAC-006 Spotlight importer |
| Sessions | MAC-001 file coordination |
| Disk images | MAC-007 Disk Arbitration lifecycle |
| Secrets | MAC-008 Keychain; encryption.md recovery boundary |

## Later

Create/compress pipelines, Windows/Linux shells, File Provider library domain, Compression.framework bake-off, comics-first UX, package intelligence.

## Doc map

Start at `docs/README.md`. Architecture overview: `architecture.md`. OS deep dive: `macos-system-integration.md`.
