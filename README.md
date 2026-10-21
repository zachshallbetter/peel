# Peel

**Open what's inside.**

Peel is **one product**: a native-feeling macOS archive and structured-container utility backed by a portable Rust engine. Its intended experience is to recognize, inspect, browse, preview, extract, create, verify, and protect supported containers without forcing users to unpack everything first. **Peel Pro is a feature entitlement, not another application or brand.**

> **Status:** This repository contains a macOS prototype and format adapters. The roadmap below is a design and qualification target, **not a claim that every capability is implemented or secure**. Read [docs/status-and-roadmap.md](docs/status-and-roadmap.md) before describing supported features publicly.

## What Peel should feel like

- **Open With / double-click:** simple extraction remains a supported configurable default for ordinary archives; browsing is an alternative, not a silent behavior change.
- **Finder Quick Look:** inspect an archive's entry structure and protection status without opening a full Peel window (planned).
- **Browse in Finder:** optionally expose supported containers through a read-only virtual mount, subject to macOS integration and distribution feasibility (research/planned).
- **Open inside:** preview or open individual files with bounded, on-demand decompression and managed temporary content; some solid archives require substantial decoding (planned).
- **Advanced:** nested containers, multipart sets, ISO and optical images, package inspection, verification, security assessment, and safe conversion, each qualified per format and operation.

## Product and licensing

Peel's everyday archive capabilities remain **free**: extraction, browsing, Finder/Quick Look integration, known-password unlock, encrypted archive creation, protection inspection, and recovery feasibility assessment. **Peel Pro** is the proposed paid entitlement for guided forgotten-password recovery, advanced candidate reconstruction, optional acceleration, and narrowly applicable legacy-encryption research. Never imply Pro guarantees recovery or bypasses strong cryptography. A **$29–$49 one-time purchase** is a hypothesis, not approved pricing.

See [docs/product.md](docs/product.md), [docs/finder-integration.md](docs/finder-integration.md), and [docs/encryption-and-recovery.md](docs/encryption-and-recovery.md).

## Repository architecture (current baseline)

```text
app/Peel (SwiftUI)
    -> swift/PeelKit
    -> crates/peel-ffi and/or peel-cli helper
    -> crates/peel-core (Rust)
    -> format-specific libraries / permitted OS image backends
```

The engine owns format interpretation and operation safety. Swift owns native UI, prompts, Finder integrations, and macOS lifecycle. Future Windows/Linux shells should reuse Rust contracts, not the SwiftUI application. Existing adapter paths include ZIP, TAR, GZIP, BZIP2, RAR, and 7z; DMG uses a macOS backend. Detection of PDF/EXE and copying an APP bundle are **not** evidence of internal extraction or inspection. Support is per **format × variant × operation × platform**.

## Build and run

Prerequisites: compatible macOS/Xcode, Rust/Cargo, and project-specific dependencies.

```sh
cargo test -p peel-core
cargo build -p peel-cli --release
./scripts/build-app.sh
./scripts/install-app.sh
./scripts/install-finder-service.sh
open -a Peel
```

Installation scripts change the local system; inspect them before running. Commands are documented development entry points, not independently verified in this documentation update.

## Documentation map

- [Product, experience, and commercial boundaries](docs/product.md)
- [Architecture and container contracts](docs/architecture.md)
- [Finder, Quick Look, and PeelFS](docs/finder-integration.md)
- [Encryption audit, authorized recovery, and migration](docs/encryption-and-recovery.md)
- [Qualification, release gates, and roadmap](docs/status-and-roadmap.md)
- [Agent operating instructions](AGENTS.md) and [.agents/README.md](.agents/README.md)

## Contribution rule

Do not promote a feature from proposed to implemented, tested, or qualified without source evidence and repeatable fixtures. Fix secret transport, false-positive verification, resource budgets, path/link containment, and transactional commits before broadening untrusted-container execution. See [AGENTS.md](AGENTS.md).
