# Peel

**By [Snack Studio](https://snackstud.io)** — macOS app + **native Rust** extraction engine (`peel-core`).  
**What actually ships:** [`docs/SHIPPED.md`](docs/SHIPPED.md) (read before trusting other docs).

No Unarchiver / `unar` / XADMaster dependency for the core path.

## Formats (extract — peel-core)

| Format | Notes |
| --- | --- |
| zip | peel-core |
| tar / tar.gz / tar.bz2 / gz | peel-core |
| rar | unrar-ng |
| 7z | sevenz-rust2 |
| dmg / .app / pdf / exe | light staging / OS helpers — **not** full container intelligence |

**Not shipped:** create/compress, MCP server, Peel Pro recovery, qualified PeelFS mounts, polished Quick Look.

## Install

```bash
cd ~/Projects/peel
INSTALL=1 DEVELOPMENT_TEAM=… ./scripts/build-app.sh   # → /Applications/Peel.app
./scripts/install-finder-service.sh
open -a Peel
```

## Use (current product behavior)

- **Double-click / Open With:** browse-on-open (folder-like) when enabled — PeelFS mount if OS allows, else browse cache beside the archive; same Finder window when Automation is granted
- **Services:** Peel · Peel to… · Peel & Reveal (extract + optional HUD)
- Drop on the Peel window: extract
- CLI: `peel extract|list|probe|formats|test`

## Develop

```bash
export PATH="$HOME/.cargo/bin:$PATH"
cargo test -p peel-core
cargo build -p peel-cli --release
INSTALL=1 ./scripts/build-app.sh
```

Docs index: [`docs/README.md`](docs/README.md). Private GitHub: [SnackStudio/peel](https://github.com/SnackStudio/peel).

## Windows / Linux

**Planned** only — not in this tree.
