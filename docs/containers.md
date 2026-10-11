# Peel — Container & Format Architecture

**Version:** 0.1.0 (proposed)  
**Date:** 2026-10-10  
**Status:** Engineering design / implementation contract; not an implementation-complete claim  
**Companion documents:** `PEEL_SYSTEM_ARCHITECTURE_v0.2.md`, `PEEL_PRODUCT_TECHNICAL_SPEC_v0.2.md`, `PEEL_V0.2_CODE_REVIEW.md`  
**Product:** Peel — *Open what's inside.*

## 1. Purpose and architectural decision

Peel should treat archives, split volumes, filesystem images, optical discs, installers, and nested packages as **typed containers** that expose a common set of *capabilities*, rather than as interchangeable ZIP-like files. A shared discovery, graph, and read interface should support browsing and extraction while format adapters retain their own physical semantics.

**Decision:** Add four composable facilities to the Rust engine:

1. **Container Resolver:** identifies possible interpretations using signatures, structure, companions, and bounded probes.
2. **Volume Resolver:** groups, orders, and validates multipart archive volumes and associated descriptors.
3. **Container Graph + Entry API:** represents hierarchical and non-hierarchical content, including partitions, optical tracks, and nested containers.
4. **Read/Materialization Layer:** supports seekable, sequential, and temporary-materialized content under shared security/resource policies.

The existing operation executor remains authoritative for policy, staging, progress, cancellation, and receipts. **Do not** make every adapter mount an OS filesystem or promise random access when a format cannot provide it.

## 2. Scope, priorities, and non-goals

**In scope:** common multipart RAR/7z/ZIP; split raw files as a distinct mode; ISO 9660/Joliet/Rock Ridge/UDF; raw IMG partition/filesystem discovery; BIN/CUE data and audio tracks; read-only package inspection; nested container traversal; deterministic capability reporting; safe selective extraction.

**Out of scope for the first implementation:** executing installers, decrypting protected media without authorization, generic extraction of arbitrary `.bin`/`.exe`/`.pak` files, write/mutate support for arbitrary disk images, automatic mounting of untrusted images, full emulation of optical media, and claiming support based on extension alone.

**Dependency:** Existing v0.2 security remediation (secure password transport, true verification, runtime budgets, transactional commit, reliable cancellation) is a release gate for new adapters, not a reason to postpone interface design.

## 3. Taxonomy and capability semantics

| Family | Examples | Structure | Initial supported operations (targets) |
|---|---|---|---|
| Archive | ZIP, RAR, 7z, TAR, CPIO | Entries, optionally compressed/encrypted | Probe, list, extract all/selected, verify where implemented |
| Compression stream | GZIP, BZIP2, XZ, Zstd, LZ4 | Stream, possibly no directory | Probe, decompress, verify where available |
| Optical/filesystem image | ISO, IMG, UDF | Sectors, optional partitions, filesystems | Probe, inspect, list, extract selected; read-only |
| Optical descriptor + image | BIN/CUE, CCD/IMG/SUB, MDF/MDS | Tracks/sessions, sidecar dependencies | Probe, resolve companion files, inspect tracks; selected extraction by supported track/filesystem |
| Virtual disk | VHD/VHDX, VMDK, QCOW2 | Disk layers, partitions, filesystems | Inspect-first, conditional read-only support |
| Package/installer | MSI, CAB, XAR/PKG, DEB, RPM, AppImage | Metadata + payload(s) | Inspect, list, extract supported payloads |
| ZIP-based semantic package | DOCX, EPUB, JAR, APK, CBZ | Archive + domain-specific manifest | Inspect, browse, extract, semantic preview where implemented |
| Specialized | PAK, WAD, firmware BIN | Proprietary, often ambiguous | Explicit per-variant adapter only |

Support is **per operation and variant**, not per extension. A file may be `detected` but not `listable`, `extractable`, or `verified`. Report one of `supported`, `conditional`, `experimental`, or `unsupported` with machine-readable reason codes and prerequisites (e.g., missing companion, password required, unsupported filesystem, non-seekable source).

## 4. Logical component diagram

```text
Native macOS / Windows / Linux UI            peel CLI / SDK
               |                                  |
               +----------- Operation API --------+
                                   |
                       Container Service
                                   |
                  +----------------+----------------+
                  |                                 |
           Container Resolver                Volume Resolver
                  |                                 |
                  +---------------+-----------------+
                                  |
                      Container Graph / Entries
                                  |
                    Read + Materialization API
                                  |
              +-------------------+--------------------+
              |                   |                    |
        Archive adapters     Image adapters       Package adapters
        ZIP/RAR/7z/TAR      ISO/IMG/BIN-CUE       MSI/PKG/DEB...
              |                   |                    |
              +-------------------+--------------------+
                                  |
             Policy / Budgets / Job Events / Cancellation
                                  |
               Staging / Commit / Receipt / Cleanup
```

### Component authority

- **Resolver** selects candidate interpretations; it does not extract or assert safety.
- **Volume Resolver** discovers and validates dependencies; it does not assume numbered filenames are volumes.
- **Adapter** interprets bytes and exposes entries/streams; it does not bypass operation policy or write arbitrary destination paths.
- **Graph** holds stable, scoped identifiers and parent-child relationships; it is not an OS-mounted filesystem.
- **Executor** enforces authorization, destination safety, budgets, cancellation, and commit semantics for all adapters.
- **UI** renders declared capabilities and explains unsupported operations; it must not infer them from file extensions.

## 5. Container resolution and ambiguous inputs

**Probe order:** bounded signature check → structural validation → nearby companion discovery (subject to scope/permission) → candidate adapters → ranked interpretations with evidence → user choice only when ambiguity remains. Prefer actual structure over suffix. Cap bytes read, recursion, file count, and probe time.

`*.bin` is *not* a supported format category. It may be raw optical sectors, firmware, arbitrary bytes, a disk image, or a vendor package. Only report specific recognized variants. `*.img` is similarly ambiguous. `*.iso` can contain different filesystems and layout variants. A recognized executable or PDF is not proof of extractable embedded content.

Proposed response:

```json
{
  "source_id": "src:1",
  "candidates": [
    {"kind": "optical_image", "variant": "bin_cue", "confidence": "high", "evidence": ["cue_descriptor", "track_layout_valid"]},
    {"kind": "raw_binary", "variant": "unknown", "confidence": "low", "evidence": ["extension_only"]}
  ],
  "selected": "optical_image/bin_cue",
  "capabilities": {"inspect": "supported", "list": "conditional", "extract_selected": "conditional", "mount": "unsupported"}
}
```

Do not expose a numeric confidence as a correctness guarantee; confidence ranks candidates, and successful structural validation establishes usable capabilities.

## 6. Multipart and companion-file resolution

### 6.1 Supported naming patterns to recognize (not blindly trust)

| Pattern | Example | Notes |
|---|---|---|
| RAR new | `film.part01.rar`, `film.part02.rar` | Use RAR volume metadata to validate |
| RAR legacy | `film.rar`, `film.r00`, `film.r01` | Legacy sequence semantics |
| 7z split | `film.7z.001`, `film.7z.002` | Numbered volume chain |
| ZIP split | `film.z01`, `film.z02`, `film.zip` | ZIP central directory often in final `.zip` |
| Generic split | `disk.img.001`, `.002` | **Not** necessarily a multipart archive; may require explicit join |
| Optical sidecars | `disc.cue` + `disc.bin` | Descriptor/dependency relationship, **not** archive volume chain |

### 6.2 Resolution contract

Given any recognized volume, locate the logical root/first volume, enumerate required companions within authorized directories, validate naming and format metadata, identify gaps/duplicates/conflicts, and produce an ordered `VolumeSet` with provenance. Never silently mix same-named files from unrelated directories. Avoid following symlinks to unapproved locations. Require explicit permission before searching outside the source directory or accessing network paths.

States: `complete`, `incomplete`, `ambiguous`, `invalid`, `password_required`, `unsupported_variant`. A missing-volume response should identify expected members when derivable; otherwise state the exact uncertainty. An incomplete set may permit inspection of known metadata but must not claim successful complete extraction.

### 6.3 Operations

- **Open any volume:** route to the resolved logical container when metadata permits.
- **Extract:** validate the full dependency set first where possible; never silently produce success for truncated data.
- **Join generic chunks:** a distinct explicit operation with ordered inputs, size/checksum checks where available, and safe destination handling.
- **Delete sources:** treat all volumes as one dependency set; delete only after successful commit and applicable verification, with clear failure reporting.
- **Progress:** report logical operation progress, not separate misleading successes for each part.

## 7. Virtual entry and container graph model

A container is a **graph**, not always a folder tree. Nodes may represent `directory`, `file`, `symlink`, `archive`, `partition`, `filesystem`, `session`, `track`, `package`, `payload`, or `metadata`. Edges represent `contains`, `backed_by`, `requires`, and `nested_container`. Provide a folder-like projection where useful, without discarding non-file concepts.

Illustrative types (design intent, not compiled Rust):

```rust
enum AccessMode { Seekable, Sequential, MaterializeRequired, MetadataOnly }
enum NodeKind { File, Directory, Symlink, Partition, Filesystem, Session, Track, Package, Payload, Metadata }
struct NodeId(String); // scoped to a container instance, never trusted as an OS path
struct Entry {
    id: NodeId,
    parent: Option<NodeId>,
    kind: NodeKind,
    display_name: String,
    raw_name: Option<Vec<u8>>,
    logical_size: Option<u64>,
    stored_size: Option<u64>,
    access: AccessMode,
    capabilities: Vec<OperationCapability>,
}
```

Preserve raw names/encodings and stable IDs to prevent ambiguous selections. An entry display name is **not** an extraction path. The executor derives and validates output paths under a selected destination policy.

Suggested interfaces:

```text
probe(source) -> CandidateContainer[]
resolve_volumes(source, scope) -> VolumeSet | ResolutionError
open_container(candidate, options) -> ContainerHandle
list_children(handle, node_id, page_token) -> EntryPage
open_entry(handle, node_id) -> ReadHandle | MaterializationPlan
open_nested(handle, node_id, budget) -> ContainerHandle
extract_selected(handle, node_ids, destination, policy) -> JobId
verify(handle, scope) -> VerificationReceipt
```

Listing must be paginated and cancellable. Handles are scoped, time-bounded, and resource-accounted. Format adapters can return `unsupported` or `conditional` for individual operations.

## 8. Read strategies and nested navigation

- **Seekable:** ZIP central-directory entries, ISO sectors, supported indexed filesystems.
- **Sequential:** TAR and compression streams; forward reads or replay may be required.
- **Materialize required:** solid 7z, encrypted headers, deeply nested streams, or formats lacking random access; use bounded, private temporary storage with cleanup.
- **Metadata-only:** known container whose content access is unsupported or unavailable.

Example:

```text
backup.zip
  └─ installer.iso           [nested container]
       └─ volume             [filesystem]
            └─ application.pkg
                 └─ Payload  [may be another compressed/container layer]
                      └─ Example.app
```

Opening nested content must count cumulative expanded bytes, temporary disk, wall time, recursion depth, and number of nodes. Prevent loops/cycles caused by repeated references or malicious layouts. Previewers receive bounded read-only streams, never unchecked direct paths.

## 9. ISO and generic disk-image pipeline

```text
Image bytes → geometry/sector probe → partition-table probe (optional)
            → filesystem detection → read-only filesystem adapter
            → virtual entries → preview / selective extraction
```

### ISO/optical target

Start with ISO 9660 and Joliet, then Rock Ridge and UDF. Account for sector sizes, directory-record validation, duplicate name mappings, timestamps, symlinks, multi-extent files, and malformed descriptors. An ISO can contain multiple compatible namespace views; do not duplicate entries blindly. Read-only extraction should work without an OS mount where the adapter supports it.

### Raw IMG target

Probe raw media geometry, MBR/GPT where present, and supported filesystems. Start with one well-scoped filesystem such as FAT; extend to exFAT/NTFS/ext variants based on portable read-only library suitability and licensing. Do not treat an unsupported partition as an empty image. Reject invalid offsets and arithmetic overflows.

### Virtual disks

VHD/VHDX, VMDK, and QCOW2 require separate container-layer parsers (sparse extents, backing chains, metadata) *before* the same partition/filesystem layer. Treat backing-file resolution as an explicit dependency/permission problem. Read-only first; no silent mounts or writes.

## 10. BIN/CUE and optical-media architecture

Parse CUE as a **descriptor**, not as the disc payload. Resolve referenced BIN files in an authorized scope; validate track indices, offsets, modes, sector sizes, pregaps, and bounds. Represent sessions/tracks as graph nodes. Expose supported data tracks to optical filesystem adapters and audio tracks as tracks with conditional extraction/conversion capabilities. Do not claim every BIN/CUE disc is browsable as files; some are audio-only, mixed-mode, damaged, or use unsupported layouts.

Future MDF/MDS, NRG, and CCD/IMG/SUB adapters can share track and sector abstractions but retain variant-specific parsers. Unsupported subchannel data and copy-protection structures must be reported, not silently discarded under a claim of faithful conversion.

## 11. Package and semantic-container adapters

Use two layers: **physical container** (ZIP, XAR, CPIO, filesystem image, etc.) and **semantic interpretation** (APK, DOCX, EPUB, PKG, DEB, RPM, AppImage, CBZ). Semantic adapters add metadata, validation, and presentation but must not bypass physical extraction policy.

Examples: DOCX/EPUB/JAR/APK/CBZ are commonly ZIP-backed with domain-specific structure; DEB is an `ar` package containing metadata/data archives; RPM uses its own header and payload format; macOS PKG may be XAR-based; MSI is a Windows Installer database and is not equivalent to a ZIP. Executables may embed resources, but arbitrary EXE extraction remains unsupported unless a specific installer variant is recognized.

## 12. Security, integrity, and failure contracts

**All adapters must satisfy the same externally observable rules:**

1. Validate paths, traversal, alternate separators, case collisions, Unicode normalization, links, device names, and platform-specific reserved names before committing output.
2. Enforce budgets *during* decompression/materialization, not solely from untrusted size metadata or post-extraction scans. Where third-party libraries cannot support limits, isolate and restrict the worker.
3. Treat files, sidecars, and backing chains as untrusted. Resolve within an approved scope; defend against symlink swaps and TOCTOU.
4. Stage outputs and commit with defined collision/rollback semantics; never report complete success after partial output.
5. Propagate real adapter errors. `list` success is not integrity verification; verify payloads/checksums where supported and clearly report coverage.
6. Keep passwords off argv and logs; use secure IPC/FD delivery, redact receipts, and avoid retaining secrets in cache.
7. Support cooperative cancellation and bounded cleanup of staging, temp files, image handles, and mounts.
8. Preserve provenance and clear status for incomplete/missing multipart sets, unsupported tracks, and partial verification.
9. Default to read-only for disk and optical images; explicit consent for any platform mount or write operation.
10. Apply fuzzing and adversarial corpus tests to every new parser, including integer overflow, offset validation, loops, malformed descriptors, and decompression bombs.

**Receipt fields:** source identity and dependency set, detected variants, requested vs performed operations, adapter/version, entries and bytes processed, integrity checks performed, warnings, cancellation/failure phase, commit outcome, and cleanup outcome. Never log secret material.

## 13. Suggested module boundaries

The following is a **target layout**, not a claim that these files already exist:

```text
crates/peel-core/src/
  container/{mod.rs,probe.rs,capability.rs,graph.rs,entry.rs}
  volume/{mod.rs,patterns.rs,rar.rs,sevenzip.rs,zip.rs,sidecars.rs}
  io/{source.rs,seek.rs,materialize.rs,budget.rs}
  image/{mod.rs,sector.rs,partition.rs,iso9660.rs,udf.rs,raw.rs}
  optical/{mod.rs,cue.rs,track.rs}
  package/{mod.rs,semantic.rs}
  operations/{inspect.rs,extract.rs,verify.rs,progress.rs,receipt.rs}
  policy/{paths.rs,limits.rs,commit.rs}
```

Preserve existing adapters initially. Introduce the new interfaces behind compatibility wrappers; migrate ZIP first, then RAR/7z, rather than rewriting all adapters simultaneously. Keep the Rust core portable; platform-specific mounting, shell integration, and filesystem APIs live behind separate platform adapters.

## Finder projections and on-demand entry access

The container graph is authoritative; Finder integration is a **projection**, not a second archive parser. A Quick Look extension may display bounded entry metadata; `open_entry` serves a requested entry as a scoped stream or private temporary copy; an optional read-only PeelFS backend may project supported entries into a mounted Finder directory. Do not imply random access for solid formats, or that Finder Sync/File Provider can turn an arbitrary local ZIP into a native folder. See `finder-quicklook.md` for lifecycle, cache, mount and test contracts.


## 14. CLI and UI contracts

Proposed CLI surface:

```text
peel probe <path> --json
peel inspect <path> --json
peel volumes <path> --json
peel list <path> --json [--node <id>]
peel extract <path> --select <node-id> --to <directory>
peel verify <path> --json
peel join <first-chunk> --to <file>       # explicit generic split-file mode
```

Structured NDJSON events should report `resolving`, `probing`, `listing`, `reading`, `verifying`, `staging`, `committing`, `completed`, `failed`, and `cancelled`, with totals only when known. The GUI should present partitions, tracks, and nested containers without flattening them into misleading directories. Missing volumes, passwords, unsupported filesystem variants, and read strategies should be explicit UI states.

## 15. Phased delivery and dependencies

| Phase | Deliverable | Acceptance gate |
|---|---|---|
| **0 — Contracts and safety** | Probe/capability schema; entry IDs; source and budget interfaces; verification semantics | Existing ZIP/RAR/7z behaviors preserved; security gates defined and tested |
| **1 — Multipart foundation** | Shared volume resolver; RAR/7z/split ZIP fixtures; missing-volume reporting | Open any recognized part; deterministic grouping; no false complete extraction |
| **2 — Browser substrate** | Graph, paginated entries, selective extract, nested open with limits | Consistent selections and policy across at least ZIP + one other adapter |
| **3 — ISO vertical slice** | ISO 9660/Joliet read-only adapter; metadata + selective extraction | Known-good ISO browse/extract; malformed-image and offset tests pass |
| **4 — Optical and raw images** | Rock Ridge/UDF as scoped; BIN/CUE; raw IMG + one filesystem | Track/partition graph correct; companions validated; unsupported variants honest |
| **5 — Semantic packages** | ZIP-backed semantic adapters, DEB/PKG or other demand-driven packages | Metadata and payload separation; no installer execution |
| **6 — Advanced images** | VHD/VHDX/VMDK/QCOW2 and niche formats | Demand, licensing, threat model, and benchmark gates met |

**Cross-platform CI begins in Phase 0**, even though native Windows/Linux UI work may land later. Every phase requires portable fixtures, format-variant capability assertions, error-state tests, and memory/time/disk budgets.

## 16. Conformance and benchmark corpus

Maintain versioned fixtures with expected entry trees, hashes, raw-name encodings, and capability outcomes:

- Multipart: RAR modern/legacy, 7z split, ZIP split; open middle volume; missing/duplicate/out-of-order volume; password-protected and corrupt part; misleading numbered files.
- ISO: ISO 9660, Joliet, Rock Ridge, UDF, mixed naming, multi-extent, malformed sector and directory offsets.
- BIN/CUE: single-track data, multi-track audio, mixed-mode, missing BIN, invalid index/sector size, path traversal in descriptor.
- IMG: raw FAT filesystem, MBR/GPT with multiple partitions, unsupported filesystem, sparse/oversized metadata, malformed partition offsets.
- Nested: ZIP → ISO → package, encrypted nested layer, deep recursion, expansion bomb, duplicate node names.
- Security: traversal, symlink escape, Unicode/case collisions, destination conflicts, cancellation, disk-full, resource exhaustion, corrupt checksum, TOCTOU.

Measure correctness first, then wall time, peak RSS, temporary disk, bytes read, startup/probe latency, and cancellation responsiveness. Compare representative archive workflows with The Unarchiver and 7-Zip where applicable; do not extrapolate those tools' behavior to disk-image or optical formats they do not support.

## 17. Architectural acceptance contract

The design is implemented sufficiently for its first milestone when:

- A single probe returns **specific format/variant evidence and honest per-operation capabilities**.
- Opening any valid multipart member resolves to one logical archive; missing parts are surfaced before success can be claimed.
- ZIP and at least one non-ZIP adapter expose the same entry/selection API and enforce the same output policy.
- A supported ISO can be inspected, browsed, and selectively extracted without silently mounting it.
- BIN/CUE is distinguished from arbitrary BIN, and tracks are represented without pretending all are ordinary files.
- Nested open has tested recursion/expansion/time limits and deterministic cleanup.
- Errors, verification coverage, cancellation, and partial commits are visible in receipts.
- Tests run reproducibly on the supported Rust target platforms.

## 18. Open design decisions

1. **Seekable-source contract:** standard `Read + Seek`, async range reads, or a custom `ByteSource` abstraction; benchmark remote and sparse files before choosing.
2. **Filesystem library strategy:** which read-only ISO/UDF/FAT libraries meet license, safety, portability, and maintenance requirements?
3. **RAR/7z multipart ownership:** which checks belong in shared resolver versus format libraries, without duplicating parser logic?
4. **Nested materialization cache:** eviction, privacy, lifetime, deduplication, and size ceilings.
5. **Mounting boundary:** when platform-native mounting is acceptable and how to isolate/clean it up.
6. **Verification vocabulary:** what `verified` means for formats without payload checksums or complete authenticity information.
7. **Optical track UX:** whether audio extraction is raw sector output, a converted audio format, or deferred entirely.
8. **Virtual disk scope:** prioritize portable read-only inspection versus platform-provided mounts for VHD/VMDK/QCOW2.

**Recommended next engineering slice:** implement the shared `VolumeSet` contract with multipart RAR/7z/ZIP fixtures, while defining the `Entry`/`ByteSource` interfaces that will support ISO. Then implement ISO 9660/Joliet as the first proof that the architecture handles a non-archive container correctly.
