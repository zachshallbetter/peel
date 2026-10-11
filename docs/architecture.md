# Peel architecture

SwiftUI (app/Peel) → PeelKit → peel CLI / libpeel_ffi → peel-core

Rust owns detection, zip-slip-safe extract, and Unarchiver-like policy.
Swift owns macOS UI and product UX.


## Finder / Quick Look integration (target)

SwiftUI and PeelKit remain the native application boundary. A Quick Look preview extension calls the shared container-listing service through a bounded, read-only interface. An optional PeelFS mount backend may expose archive entries as read-only filesystem objects to Finder; it is **not** implemented by Finder Sync or Quick Look alone. Entry reads and temporary materialization must use the same Rust core, security policy, credential broker and cancellation semantics as extraction. See `finder-quicklook.md` and `containers.md`.

## Product entitlement boundary

One Peel application and Rust engine serve Free and Pro. Core parsers, container graph, Quick Look, Finder read/mount integration, known-password decrypt, encryption creation and protection inspection are shared Free capabilities. A separately authorized advanced recovery operation boundary checks Pro entitlement. No secret-bearing argv, logs or telemetry; no duplicated Free/Pro engines. See `product-identity.md`.

## macOS deep integration (investigation)

Beyond Services and extract HUD, Peel may surface the same container graph through FSKit (PeelFS), Quick Look, Spotlight importers, Disk Arbitration, file coordination (ArchiveSession), UTType, Keychain, and optional Compression.framework backends.

See `macos-system-integration.md` for framework inventory, experiment order (MAC-001…MAC-010), and gates. Do not treat FSKit or File Provider as implemented until decision spikes pass.
