# Peel — Finder, Quick Look & In-Archive Opening

**Version:** 0.1.1 | **Date:** 2026-10-11 | **Status:** Design + FND-001 scaffold in tree

**Double-click / Open With interaction (browse-first):** see [`finder-open-interaction.md`](finder-open-interaction.md). Production list/read sharing: [`peelfs-xpc-bridge.md`](peelfs-xpc-bridge.md).

**Scaffold:** `app/PeelQLPreview` — ZIP-only bounded listing via `QLPreviewingController`. Not yet the full tree UI or XPC-backed listing.

## Goal

Make supported archives feel like folders in macOS Finder: preview archive contents with Space, browse individual entries in Finder where a supported filesystem bridge is installed, and open individual files without manually extracting the entire archive. Preserve the existing double-click-to-extract default unless the user explicitly changes it.

## macOS integration constraints

Quick Look preview extensions can render an archive-level preview but do not turn ZIP/RAR/7z into Finder directories. Finder Sync extensions support scoped badges and contextual actions, not arbitrary navigation substitution. File Provider is designed for managed file domains and is not a drop-in replacement for mounting local archives. A FUSE-based filesystem can expose read-only mounted directories, but requires a separately installed, compatible filesystem component and entails installation, signing, permissions, performance and maintenance costs. Do not promise transparent inline expansion of a ZIP in its original Finder parent directory using public Finder APIs.

## Three supported UX tiers

| Tier | Entry point | Behavior | Dependency |
|---|---|---|---|
| A — Quick Look | Select archive, press Space | Native archive-level preview with file tree, metadata, protection status, and actions | Quick Look preview extension + read-only core listing |
| B — Open one item | Quick Look or Peel browser | Select item, preview or open using a bounded private materialized copy; no full-archive extraction where adapter permits | Entry read/materialization API; secure cache; password prompt |
| C — Browse in Finder | Finder action: Browse as Folder | Create read-only virtual mount, open its Finder window, preview and drag individual entries | Optional compatible filesystem/mount backend; explicit enablement |

Fallback: if Tier C is unavailable, use the native Peel browser; do not misrepresent it as Finder browsing.

## Core API integration

Reuse the existing Container Resolver, Volume Resolver, Container Graph, entry IDs, read/materialization and operation-policy contracts from `containers.md`. Do not build a second ZIP/RAR/7z parser inside a Quick Look extension or filesystem adapter.

Proposed read APIs:

```text
list_children(container_handle, node_id, page_token) -> EntryPage
open_entry(container_handle, entry_id, budget) -> ReadHandle | MaterializationPlan
materialize_entry(container_handle, entry_id, destination_policy) -> ScopedFile
close_handle(handle) -> CleanupReceipt
```

Read strategies: seekable ZIP entries and ISO sectors may be accessed directly; TAR and solid 7z may require sequential decode and temporary materialization. Encrypted headers may require authorization before listing. The UI must communicate waiting, unlocking, materializing and unsupported states accurately.

## Quick Look preview contract

Render a bounded first page: recognized format, entry/file counts if known, total and stored size if known, folders/files, encryption state, warnings, and actions `Browse Contents`, `Extract`, `Inspect Protection`. Cap entry enumeration, thumbnails, elapsed time and memory. For encrypted filenames, show a locked state and explicit unlock action; never invent a tree. Avoid executable rendering of untrusted content and keep extension sandbox boundaries intact.

## Read-only PeelFS mount contract

- Mount only at a dedicated app-managed mount root; do not alter the original archive.
- Display a distinct mount name; Finder eject/unmount maps to cleanup.
- Every read enforces cumulative resource budgets and cancellation; reads must never trigger unbounded decompression.
- Reject or safely map symlinks, hardlinks, special files, path collisions, Unicode normalization conflicts and unsafe metadata.
- Mounted archive remains immutable. Editing through mounted paths is not promised; apps may need a managed writable copy and an explicit `Save Back` operation in a later phase.
- Handle archive replacement/deletion while mounted, app termination, helper crash, stale mounts, filesystem backend absence, and macOS version changes.
- Cache decrypted/materialized bytes in access-controlled temporary storage with explicit eviction and cleanup. Do not store passwords in cache or logs.
- Warn that opening a file in an external app can create independent plaintext copies or autosaves outside Peel's control.

## Finder behavior

- **Space on archive:** Peel Quick Look preview where extension is available and registered.
- **Double-click archive:** preserve configured extraction/open behavior; offer optional `Browse as Folder` preference after supported mount backend qualification.
- **Context menu:** `Quick Look Contents`, `Browse as Folder` (only if available), `Extract Here`, `Extract Selected`, `Inspect Protection`.
- **Space on mounted item:** normal Finder Quick Look where its file type is supported and materialization succeeds.
- **Drag from mounted folder:** copies selected bytes out; do not imply atomic extraction for multi-file drag operations without verification.
- **Eject:** unmount and release resources, with clear errors if handles remain open.

## Delivery milestones

**FND-001 (P1):** Archive Quick Look extension for ZIP with bounded, cancellable listing and locked-state UI. Acceptance: preview works from Finder without launching main window; malicious and large archives are bounded.

**FND-002 (P1):** Common `open_entry`/materialization path; ZIP and one non-ZIP adapter; private cache, typed errors, secure password prompts. Acceptance: opening one entry does not extract all entries where random access is supported.

**FND-003 (P1):** Extend Quick Look to RAR, 7z, TAR and ISO as each adapter qualifies; show explicit limitations for solid/encrypted variants. Acceptance: no misleading contents or progress.

**FND-004 (P2, optional):** Prototype read-only PeelFS Finder mount on supported macOS versions using an independently evaluated filesystem backend. Acceptance: browse, Space, drag/copy, eject, crash recovery and no-write guarantee pass integration tests. Provide native browser fallback.

**FND-005 (P3):** Optional explicit edit-and-repack workflow using staged copies, metadata-loss disclosure and independent round-trip verification. No transparent write-through in v1.

## Dependencies and release gates

Required first: PEL-002 safe extraction, PEL-003 capabilities, PEL-004 progress/cancel, PEL-005 staged commit, PEL-007 entry browser, PEL-013 secure password transport, PEL-014 multipart, and actual integrity verification. Preview-only paths still need strict parsing, read, memory and time budgets. A successful list is not integrity verification.

## Validation matrix

Test: ZIP regular/ZIP64/encrypted; RAR and 7z solid/encrypted; TAR; ISO; missing multipart volumes; corrupt central directory; path traversal and symlink entries; huge directory counts; decompression bombs; external-app open; mount/unmount; macOS upgrades; Quick Look cache invalidation; cancellation; password prompt; app crash; file changes during mount. Record format variant, macOS version, filesystem backend version, observed result and cleanup receipt.

## Architectural decision

Ship Tier A first, Tier B next, and keep Tier C optional until the filesystem dependency and macOS compatibility are qualified. This achieves Finder-native Quick Look quickly without promising APIs Finder does not expose.

## Product and entitlement decision

Quick Look, opening individual entries and qualified optional Finder mounting are core **Free Peel** experiences, not paid differentiators. Preserve one application identity. The `Forgot Password` action from an encrypted archive may lead to a free feasibility preflight and then optional Pro recovery; ordinary known-password unlock remains free. See `PEEL_PRODUCT_IDENTITY_AND_MONETIZATION_v0.1.md`.

## Related investigation

Broader OS framework opportunities (FSKit vs macFUSE, File Provider, Spotlight, Disk Arbitration, CryptoKit, UTType, Compression.framework) and the P0–P3 experiment matrix live in `macos-system-integration.md`. This document remains the **UX tier and FND ticket** source of truth for Quick Look / open-entry / PeelFS product behavior.

