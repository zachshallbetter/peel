# Peel

**By [Snack Studio](https://snackstud.io)** — **Single installable macOS app** — Swift glass UI + **native Rust** extraction engine.

No Unarchiver / `unar` / XADMaster dependency. Peel rebuilds that capability.

## Formats (native)

| Format | Engine |
| --- | --- |
| zip | peel-core |
| tar / tar.gz / tar.bz2 / gz | peel-core |
| **rar** | unrar-ng (native lib) |
| **7z** | sevenz-rust2 (pure Rust) |
| dmg | hdiutil + copy (macOS) |
| .app | package expand |
| pdf / exe | staged peel folder |

Everything peels **into a folder** (`*-peeled` beside the source by default).

## Install

```bash
cd ~/Projects/peel
./scripts/install-app.sh          # → /Applications/Peel.app
./scripts/install-finder-service.sh
open -a Peel
```

## Use

- Drop archives on the glass window
- **Open…** / **Peel to…**
- Finder: **Open With → Peel**
- Finder **Services**: Peel · Peel to… · Peel & Reveal
- Passive extract (no Dock) + top-center HUD

## Develop

```bash
export PATH="$HOME/.cargo/bin:$PATH"
cargo test -p peel-core
cargo build -p peel-cli --release
./scripts/build-app.sh
```

## Windows

Planned: same Rust CLI + Explorer context menu. macOS app is the product focus today.
