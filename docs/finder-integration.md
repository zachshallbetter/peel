# Peel — Finder, Quick Look, and optional PeelFS

**Status:** Product/engineering proposal; not an implementation claim.

## Intended experience

The user can select an archive in Finder and press Space to see a useful Quick Look summary. Where read-only virtual mounts are available, opening the archive can expose a directory that Finder navigates normally. Opening or dragging one file should decode only what is required; no forced full extraction when the format allows it.

**Do not promise that a Finder Sync extension can transform an arbitrary ZIP into a Finder directory.** Quick Look provides previews; Finder Sync provides limited contextual integration; File Provider is not a general arbitrary archive-mount API. A true folder-like Finder view needs a qualified filesystem/mount mechanism (e.g. an optional FUSE-based implementation) or a separate native Peel browser. Assess macOS version, sandboxing, signing, entitlements, system extension distribution, and user installation friction before selecting a mount backend.

## Surface contracts

| Surface | First deliverable | Limitation |
| --- | --- | --- |
| Quick Look archive preview | Name, type, file/folder counts, bounded entry tree, metadata, encryption and integrity **assessment status**, action to open Peel | Preview extension alone is not a general Finder filesystem |
| Finder actions / Open With | Extract, Browse with Peel, Inspect Protection, Verify; preference for double-click default | No global override of Finder navigation |
| Native Peel browser | Search, hierarchy, previews, selective extract, nested entry navigation | Separate window, fallback for unsupported mounts |
| Optional PeelFS mount | Read-only Finder directory, native per-file Quick Look, drag/copy, eject | Requires qualified mount backend and OS support |
| Managed open-inside | Bounded temp copy/stream, open associated app, cleanup | Editing temp copy must not silently update archive |
| Future writeback | Explicit staged replacement and verified rebuild | Not a writable live filesystem promise |

## PeelFS design

Mount path and display name are generated and collision-safe. Maintain a source fingerprint, graph node IDs, mount session, active readers, per-entry decode state, and cleanup receipt. Use a private bounded cache with per-user access controls, no unencrypted persistent secret leakage, and predictable eviction. For encrypted entries, request authorization securely; never store decrypted data in a shared or world-readable location.

Handle sparse/large files, partial reads, backpressure, cancellation, concurrent reads, stale source changes, archive deletion/move, Finder restarts, process crashes, sleep/wake, eject, and unmount failures. Preserve resource forks, permissions, timestamps, and symlinks only where qualified; reject dangerous links. Do not use source filenames as unchecked mount paths. Index only permitted metadata and honor encrypted-header privacy.

## Delivery and evidence

1. **Quick Look first:** extension installation/signing, bounded archive summary, graceful corrupt/unsupported/password-required states, accessibility and no unwanted main window.
2. **Entry API and native browser:** paginated listing, search, per-entry read, selective extraction, nested budgets; ZIP first, then qualified RAR/7z/TAR/ISO.
3. **Open inside:** secure temporary materialization, launch, reference counting, cleanup, edit-notification semantics, cache privacy tests.
4. **PeelFS feasibility spike:** compare mounting options against OS support, installation, signing, sandbox, performance, Finder behavior; implement only if release-compatible.
5. **Read-only mount qualification:** Quick Look of mounted child files, copy/drag, eject, source mutation, crash recovery, encrypted archives, multipart, adversarial names.
6. **Future writeback:** opt-in edit staging, metadata-loss disclosure, complete rebuild, independent round-trip verification, atomic replacement with rollback.

**Acceptance:** no false success, no implicit full extraction, no plaintext cache leakage, no source modification on browse, no orphaned mounts, and honest limitations for solid archives and unsupported image formats.
