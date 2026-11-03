# Peel — architecture and container contracts

**Status:** Target architecture reconciled with existing SwiftUI/Rust prototype; module names below are logical contracts unless source proves otherwise.

## Layers

```text
macOS SwiftUI / Quick Look / Finder actions / optional PeelFS
                    |
             PeelKit / IPC / FFI
                    |
       Peel operation service (optional)
                    |
         Rust core: probe + policy
                    |
  Container Resolver ---- Volume Resolver
                    |
         Container Graph / Entry API
                    |
     ReadHandle / Materialization API
                    |
   ZIP / 7z / RAR / TAR / ISO / image / package adapters
                    |
  budgets + isolation + staging + verification + receipts
```

Swift/OS adapters own OS-specific mounts, prompts, and extension lifecycle. Rust owns structural interpretation, byte-access contracts, path policy, cancellation, and operation evidence. Do not add Reflective Rust as a hard dependency merely for architecture symmetry; optional capability-shaped JSON / reflection can be evaluated after stable public types exist.

## Resolution and graph

Probe with bounded signature and structural reads, rank candidate interpretations with evidence, then resolve authorized companions. Multipart ZIP (.z01/.zip), RAR (.partNN.rar or legacy .rNN), 7z (.7z.001), generic split files, and BIN/CUE sidecars are **different dependency semantics**. Missing/ambiguous volumes are first-class errors.

Model nodes as file, directory, symlink, partition, filesystem, track, session, payload, package, and nested container. Preserve scoped stable IDs, raw names, encoding, parent relationships, and typed capabilities. A node display path is **never** a trusted destination path.

Proposed interface:

```text
probe(source) -> CandidateContainer[]
resolve_volumes(source, permission_scope) -> VolumeSet
open_container(candidate, options) -> ContainerHandle
list_children(handle, node_id, page_token) -> EntryPage
open_entry(handle, node_id) -> ReadHandle | MaterializationPlan
open_nested(handle, node_id, budget) -> ContainerHandle
extract_selected(handle, node_ids, destination, policy) -> JobId
verify(handle, scope) -> VerificationReceipt
```

Read strategies: seekable; sequential; materialize-required; metadata-only. ZIP often supports entry-level access; solid 7z may require decoding a block. No adapter promises random access unless proven. Bound nested depth, expanded bytes, files, memory, wall time, and temporary disk cumulatively.

## Security and operation invariants

- Reject traversal, absolute paths, unsafe links, Unicode/case collisions, symlink swaps, and escape from authorized roots.
- Enforce runtime budgets **during** decoding; isolate adapters without enforceable streaming callbacks.
- Never send passwords through process arguments, environment variables, logs, or receipts; use secure IPC/FD or OS credential channels.
- Verification decodes/checks actual payloads where supported. Listing is not verification; distinguish CRC from authenticated integrity.
- Stage writes, preflight conflicts, commit safely, preserve source, record partial outcomes, and clean up after cancel/failure.
- No automatic execution of untrusted installers, macros, or binaries; read-only disk/optical inspection first.
- Each operation returns structured phase events and a receipt with exact verification coverage and cleanup outcome.
- Mounts must be unprivileged/read-only by default, bounded, explicitly authorized, revocable, and unmounted on lifecycle end.

## Format families

Archives: ZIP, RAR, 7z, TAR/CPIO. Streams: gzip/bzip2/xz/zstd. Optical: ISO 9660/Joliet/Rock Ridge/UDF; BIN/CUE with validated track geometry. Disk: IMG partition/filesystem projection; advanced VHD/VHDX/VMDK/QCOW2 only after backing-chain design. Semantic packages: DOCX/EPUB/APK/JAR, DEB/RPM, macOS PKG, selected MSI. A detected extension is not an implemented parser.

## CLI/SDK (proposed where absent)

```sh
peel probe input --json
peel inspect input --json
peel list input --json
peel extract input --select NODE --to DIR
peel verify input --json
peel volumes input --json
peel formats --json
```

Version schemas and error codes; isolate stdout data from diagnostics; never put secrets in flags. Rust portability and cross-platform fixtures start before new shells ship.
