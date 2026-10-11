# Peel — Product & Technical Specification

**Version:** 0.2.1  
**Date:** 2026-10-11  
**Status:** **Target specification** — not a checklist of HEAD. For what exists in code, see [`SHIPPED.md`](SHIPPED.md).  
**Platforms (target):** macOS first; Windows/Linux shells are roadmap only  
**Positioning:** **Peel — Open what's inside.**

## 1. Product definition

Peel is a fast, safe, cross-platform desktop utility for **recognizing, browsing, extracting, creating, compressing, converting, verifying, and managing** archives and other structured file containers. It should cover conventional unarchiver/compressor workflows while extending into application packages, comics, document containers, disk images, and selected installer formats. Peel must distinguish *an ordinary archive*, *a compression stream*, *a package or bundle*, *a disk/filesystem image*, and *an executable with potentially embedded content*; these do not imply identical operations.

**Product promises:** (1) double-click and drag/drop just work; (2) inspect before extracting; (3) operations are explicit, safe, reversible where feasible, and observable; (4) format support is honest and capability-based; (5) native-feeling on every platform; (6) Rust engine usable without the GUI.

**Non-goals initially:** executing installers; circumventing passwords, DRM, or signatures; universal extraction of arbitrary EXEs or game assets; modifying signed app bundles without warning; silently mounting untrusted disk images; promising repair for formats lacking repair support.

## 2. Existing repository baseline (supplied archive and 2026-10-10 agent report)

The uploaded project is **already a macOS prototype**, not a blank repository. Observed source layout:

- `crates/peel-core`: detection, extraction, listing, policy, ZIP/TAR/GZIP/BZIP2, RAR and 7z adapters, special-container handlers.
- `crates/peel-cli`: `list` and `extract` commands.
- `crates/peel-ffi`, `include/peel.h`, `swift/PeelKit`: FFI/Swift integration scaffolding.
- `app/Peel`: SwiftUI macOS shell; embedded CLI executable bridge.
- `fixtures/hello.zip`, Rust tests, build scripts and an Xcode project.

**Important baseline caveats:** README documents ZIP/TAR/GZ/BZ2 as v0.1 and RAR/7z as planned, while source now contains RAR/7z implementations. Treat these as *implemented paths requiring verification*, not production-proven format support. `detect_format` recognizes PDF, EXE, APP, DMG; recognition does **not** establish general-purpose extraction of embedded contents. EXE/Mach-O recognition is especially not equivalent to installer parsing. The CLI currently only exposes `list` and `extract`. No tests or builds were executed for this specification.

**New reported evidence (2026-10-10):** The supplied `ui-rightclick-settings-smoke.md` reports PASS for Open With silent extraction, a compact approximately 420×120 progress HUD, extract-beside with collision rename, a `Peel Here` service routed through Peel.app, and Settings scene access. This is a **reported local smoke test**, not an independently reproduced release qualification. The current CLI source inspection exposes only `list` and `extract`. Source inspection shows real handler paths for ZIP, TAR, GZIP, BZIP2, RAR and 7z, but does not prove password, multipart, filename encoding, or security edge-case support. The DMG handler invokes macOS image tooling; `.app` is copied as a directory bundle; PDF and EXE handlers stage/copy the input rather than providing genuine internal-structure inspection. Do not label the latter two as extraction support.

**Evidence levels:** `observed-source` (implementation path exists), `reported-smoke` (external test report), `tested` (reproducible fixture test passed), `qualified` (full per-operation/per-platform conformance and safety gates passed). A feature can be implemented without being qualified. Only `qualified` capabilities may be advertised without a limitation.

**Required immediate audit:** confirm ZIP/TAR safety invariants; check whether RAR/7z library extract-to-directory operations honor the same path, symlink, collision and resource policies; verify DMG mount lifecycle and cleanup; characterize APP/PDF/EXE behavior; inventory dependency licenses and platform portability; test against malformed archives.

## 3. Personas and primary workflows

1. **Everyday user:** double-click a ZIP/RAR/7z; automatically extract beside the source, create a containing folder only when appropriate, open result.
2. **Power user:** browse contents; selectively extract; set password; choose compression algorithm, level, archive splitting, encryption and metadata policy.
3. **Developer:** inspect `.app`, `.exe`, `.apk`, `.jar`, `.deb`, `.rpm`, `.dmg`, `.iso`; examine signatures and embedded structures without executing code.
4. **Comics reader/organizer:** browse CBZ/CBR/CB7/CBT; preview pages in natural order; export pages or convert supported formats.
5. **Batch operator:** queue hundreds of archives, apply a consistent policy, get machine-readable reports; use CLI and shell integration.

### Default behavior

- Double-click associated supported file: **extract** for conventional archives (configurable); **inspect first** for executables, app packages, installers, disk images, and document containers.
- Drag onto Peel: show detected type and available actions; dropping a regular archive may use the user's default extraction policy.
- Destination: next to archive by default, configurable; create enclosing folder **when needed**; never silently overwrite unrelated files.
- Collision default: **rename** or ask (choose one product default before implementation); never default to destructive overwrite. Existing CLI defaults to overwrite and must be reconciled.
- On success: unobtrusive completion, reveal/open optional; on failure: actionable error, retained source, clear partial-output handling.

## 4. Capabilities model

Every format handler declares supported operations rather than relying on extension-only flags:

`probe`, `list`, `preview`, `extract_all`, `extract_selected`, `create`, `append`, `delete`, `convert_from`, `verify`, `repair`, `encrypt`, `decrypt`, `split`, `join`, `mount`, `unmount`.

Support status per operation: `supported | conditional | unsupported | experimental`. Conditional status includes OS requirements, optional codec availability, encryption method, or read-only limitations. UI and CLI query the same capability registry; no action is shown as guaranteed unless the engine supports it.

**Detection contract:** `DetectedContainer { family, format, variant, confidence, evidence, mime_hint, filename_hint, capabilities, warnings }`. Probe bounded bytes and metadata; recognize signatures and structural checks; use extension only as a hint; allow multiple candidates and ambiguous results. Never execute a sample to determine its type.

**Operations:** `OperationRequest { id, input, action, selection, destination, policy, options }`; emit `OperationEvent { id, phase, processed_bytes, total_bytes?, entries_done, entries_total?, speed?, warnings }`; terminate with `OperationReceipt { input_fingerprint, detected_format, action, outputs, skipped, failures, verification, duration, warnings }`. API fields and serialization versioned; no passwords in logs or receipts.

## 5. Format support matrix and roadmap

Legend: **R** browse/extract; **W** create; **I** inspect/preview; **C** conditional or format-specific; **—** not promised. This is a **target matrix**, not verified current support.

| Family | Formats/examples | Target | Notes |
|---|---|---|---|
| Core archives | ZIP | R/W | ZIP64, Unicode, data descriptors, encryption variants tracked individually |
| Core archives | 7z | R/W | LZMA/LZMA2, solid blocks, encrypted headers, multi-volume conditional |
| Core archives | RAR4/RAR5 | R | Creation not promised; multipart/password support separately qualified |
| Unix containers | TAR, CPIO, XAR | R/W for TAR; R/C others | Metadata, links, pax, sparse entries |
| Streams | GZIP, BZIP2, XZ, Zstandard, LZ4, Brotli, LZMA | R/W | Single stream vs tar-wrapped stream distinguished |
| Compound | `.tar.gz`, `.tgz`, `.tar.bz2`, `.tar.xz`, `.tar.zst`, `.tar.lz4` | R/W | Layered pipelines, one-step extraction |
| Legacy | LHA/LZH, ARJ, ZOO, ACE, SIT/SITX, Compact Pro, HQX | R/C | Codec availability, rights, licensing and fixtures required |
| Comics | CBZ, CBR, CB7, CBT | I/R; W where backend permits | Natural page sorting, thumbnails, metadata, no forced recompression |
| ZIP-based packages | JAR, WAR, EAR, APK, AAB, IPA, DOCX, XLSX, PPTX, EPUB, ODF, NUPKG | I/R; C W | Preserve semantics; rewriting may invalidate signatures |
| Apple | `.app`, `.dmg`, `.aar`, `.pkg`, `.xip`, `.xar` | I/R/C | `.app` directory bundle; DMG requires image handling; platform-specific APIs |
| Windows | PE `.exe`, MSI, MSIX, CAB, SFX installers | I/C | EXE is not a universal archive; identify embedded payload formats |
| Linux | DEB, RPM, AppImage, SquashFS | I/R/C | Parse package/image internals; preserve package metadata |
| Images | ISO, IMG, WIM, VHD/VHDX | I/R/C | Filesystem/partition parsers; mounting optional and consent-based |
| Specialized | PAK, VPK, WAD, Unity bundles | Experimental | Named variants only; no blanket support claim |

**Format rules:** capabilities are granular by codec/version/encryption/volume/OS. Avoid conflating extension association with full format support. `.app` on macOS is usually a directory; `.exe` is a PE binary that *may* embed an archive; `.dmg` is a disk image; `.cbr` typically contains RAR; `.cbz` typically contains ZIP. Document packages can be inspected, but changing internals can break validity or signatures.

## 6. Architecture

```text
Native shells                 Integrations
macOS SwiftUI                 Finder / Quick Look / Share / Services
Windows native UI             Explorer / context menu / file associations
Linux desktop UI              Freedesktop MIME / portals / file managers
        \                         /
          Peel Application API
                  |
          peel-service (optional background jobs)
                  |
            peel-core (Rust)
   +--------------+----------------+
   | detection / registry / policy |
   | operations / queue / progress |
   | metadata / receipts / errors  |
   +--------------+----------------+
                  |
    format adapters + codecs + OS image backends
                  |
     sandboxed/staged filesystem output
                  |
             peel-cli / SDK / FFI
```

**Engine boundaries:** `peel-detect`, `peel-container` (entry enumeration), `peel-codec` (stream transforms), `peel-operations` (extract/create/convert/verify), `peel-policy`, `peel-platform` (mounting and metadata), `peel-ffi`, `peel-cli`. These are *logical modules*; split crates only when dependency/ownership boundaries justify it.

**UI strategy:** retain SwiftUI for macOS. Do not assume SwiftUI is a viable universal Windows/Linux shell. Choose and benchmark a Windows/Linux UI approach separately (e.g., native Windows UI + GTK/Qt, or a shared cross-platform shell) against native drag/drop, accessibility, signing, distribution, and binary size. Rust engine is platform-neutral; OS-specific behavior is behind adapters.

**Interop:** define a stable C ABI for Swift and other native clients, with opaque handles and explicit ownership; alternatively use a managed helper process with versioned JSON/IPC. Current macOS helper-process model can remain for early phases. Do not couple core logic to Swift or subprocess stdout conventions. Cancellation, structured errors, streaming progress, and password prompts are mandatory before large batch workflows.

**Extensibility:** versioned internal format-adapter trait; third-party plugin execution is deferred until isolation, ABI, signature, and trust requirements are designed. Never dynamically load untrusted parsers into a privileged host process by default.

## 7. Security and trust requirements (release-blocking)

- **Path containment:** reject absolute paths, traversal, alternate separators, drive letters, UNC paths, unsafe normalization and equivalent encodings. Check final destination containment at write time.
- **Link safety:** reject or explicitly constrain symlinks, hardlinks, junctions, reparse points, device files, FIFOs and other special entries. Prevent symlink-assisted escape and TOCTOU attacks; use safe descriptor-relative filesystem APIs where available.
- **Resource budgets:** configurable maximum entries, expanded bytes, per-entry bytes, nesting depth, compression ratio, CPU time, memory, and total disk consumption. Stream data; don't buffer unbounded files.
- **Transactional writes:** extract into isolated staging directories; preflight collisions; commit with atomic moves where possible; clean up on cancellation and failure; report any incomplete cleanup.
- **Permissions:** preserve timestamps/modes/ACLs/xattrs only according to policy; never silently restore dangerous executable bits or privilege-bearing metadata; prevent zip-slip and link tricks on every adapter.
- **Untrusted code:** do not execute installers, scripts, macros, or extracted executables. Previewers must be isolated; show risk warnings where warranted.
- **Mounting:** explicit user consent for image mounting; read-only by default; reliable unmount and cleanup; OS-specific entitlements/privileges audited.
- **Secrets:** passwords never persisted by default, redacted from telemetry/CLI logs; platform secure storage only with opt-in.
- **Supply chain:** dependency/license audit, SBOM, reproducible builds where feasible, signed releases, vulnerability tracking and fuzzing of parsers.
- **No security bypass via adapter:** RAR/7z/OS utilities must not write directly to unchecked destinations without equivalent policy enforcement. Existing adapters require a dedicated audit here.

## 8. UX specification

### Primary surfaces

**Drop surface:** a compact drop target with recognizable Peel sticker; accepts files/folders, previews action and destination, supports batch queues.

**Archive browser:** Finder/Explorer-style hierarchical tree; breadcrumbs, filename/type/size/compressed-size/date, search, sorting, thumbnails, Quick Look-like preview, selected extraction, password and unsupported-feature prompts.

**Create panel:** drag sources; choose format, algorithm/level, solid mode if applicable, password/encryption, split volume size, destination, metadata preservation; show compatibility warnings before commit.

**Job center:** persistent operation queue with progress, speed, ETA where reliable, pause where supported, cancel, retry, conflict resolution and receipts.

**Inspector:** file signatures, container type, codec, entries, ratio, encrypted/signed status, nested layers, platform metadata and integrity results; distinguish detection confidence from verification.

**Preferences:** defaults for extract destination, enclosing folders, collisions, post-extract behavior, file associations, preview, safety limits, notifications and appearance.

### Platform integration

- macOS: Finder Quick Actions, Open With, drag/drop, Dock, Quick Look where feasible, notarization, sandbox/entitlement review.
- Windows: Explorer context menu, associations, drag/drop, signed installer/MSIX or equivalent, long paths and reparse point handling.
- Linux: `.desktop`, MIME registration, xdg-desktop-portal, desktop notifications, packaging (AppImage/Flatpak/deb/rpm as appropriate), symlink/mode behavior.

### Sticker brand system

**Canonical identity:** a die-cut **orange** sticker with an organic silhouette, white vinyl border, real material thickness, subtle shadow, and a lifted/peeled section of orange rind. Do **not** put the artwork inside a generic colored rounded-square tile. Maintain legibility at 16–32 px; simplify details rather than shrinking the hero artwork unchanged.

**Variants:** banana, pistachio, fortune cookie, candy wrapper, pizza, etc. are optional collectible themes, not required to understand the app. Consistent material/edge/curl behavior; artwork follows its own die-cut outline. Format-family stickers may be introduced later but must not obscure file type labels.

**Motion:** idle static; drag-over lifts a corner; extraction progresses through a subtle peel; completion settles/springs back; reduced-motion alternative mandatory. Motion must never be the only progress signal. For icon integration, follow each OS's actual icon constraints rather than assuming arbitrary die-cut alpha presentation is identical everywhere.

## 9. CLI and SDK contract

Proposed commands (existing: `list`, `extract`):

```sh
peel probe input.bin --json
peel list archive.7z --json
peel inspect installer.exe --json
peel extract archive.zip --out ./result --collision rename --json
peel extract comic.cbr --select 'pages/001.jpg' --out ./pages
peel create output.tar.zst ./project --level 8
peel convert input.cbz output.cb7
peel verify archive.zip --json
peel formats --json
peel jobs --json
```

**Contract details:** versioned JSON schema; stable error codes; separate stdout results from stderr diagnostics; optional NDJSON progress; deterministic exit codes; `--dry-run` for destructive operations; cancellation signal handling; stdin/stdout stream support only when codec/container permits. Password input via protected prompt, file descriptor or OS secret channel—never require `--password plaintext` on a shared command line.

**Conversion semantics:** decode source entries to a safe staged representation and encode target; report losses (metadata, encryption, signatures, permissions, comments, ordering, timestamps). Refuse or request confirmation for lossy/invalidating conversions. Don't promise arbitrary pairwise conversion.

## 10. Data structures and invariants

`ContainerEntry`: stable entry ID, normalized display path, original raw name/encoding, type, logical/compressed sizes, timestamps, permissions, checksums, encryption, links, warnings, lazy content handle.

`ExtractionPolicy`: destination, collision mode, enclosing-directory mode, link policy, metadata policy, resource budgets, overwrite confirmation, quarantine policy, password-provider handle.

`CapabilityReport`: detected format/variant, operations with support level and constraints, decoder backend/version, platform requirements.

**Invariants:** source immutable unless explicitly editing; destination never escapes its root; every write is policy-governed; every operation returns a structured receipt; unsupported operations fail clearly; no extension-based assertion of successful decoding; partial results are always reported; no silent executable invocation.

## Finder-native archive access — proposed integration (2026-10-10)

Add **Quick Look archive previews** as a P1 capability, **open-one-entry** as a P1 capability, and optional **read-only Finder mounting (PeelFS)** as P2. See `finder-quicklook.md` for API boundaries, macOS limitations, acceptance tests and fallback behavior. Finder Quick Look does not itself make archives navigable folders. A Finder-mounted directory requires an independently qualified filesystem backend; do not assume Finder Sync or File Provider provides arbitrary local archive mounts. Preserve the current extraction default until users explicitly choose browse-first behavior. Reuse `containers.md` entry/read APIs and enforce encryption prompts, resource budgets and cleanup for previews as well as extraction.

New tracked work: **FND-001** Quick Look extension; **FND-002** open-entry materialization; **FND-003** format coverage; **FND-004** optional read-only Finder mount; **FND-005** future explicit edit-and-repack. Platform investigation tickets **MAC-001…MAC-010** (ArchiveSession, FSKit spike, Spotlight, Disk Arbitration, Keychain, UTType, etc.) are defined in `macos-system-integration.md`.


## 11. Milestone-driven implementation plan

The implementation order is **reliability → complete archive utility → container intelligence → cross-platform product**. Cross-platform core portability and CI start in Milestone A, not at the end. Feature development does not override release-blocking safety gates.

### Milestone A — Dependable Unarchiver replacement (P0)

- Audit actual extraction paths, library licensing and format variants; publish the baseline capability matrix.
- Complete encrypted ZIP (including method-specific qualification), RAR and 7z password prompts through a protected secret-provider channel.
- Qualify multipart RAR/ZIP/7z, including missing-volume diagnostics and correct volume discovery.
- Implement real engine byte/item progress, cancellation, error propagation and reliable cleanup. Never display synthetic progress as measured progress.
- Qualify legacy filename decoding, Unicode normalization, directory layout, metadata and collision rename/ask behavior.
- Enforce path/link containment, resource budgets and staged writes across **every** adapter, including OS-tool-based handlers.
- Stabilize macOS Open With, default associations, Finder service, preferences and one-step extraction; distinguish `reported-smoke` from reproducible test evidence.
- Run representative correctness and adverse-case fixtures against Peel, The Unarchiver and 7-Zip where each competitor supports the format.

**Exit gate:** P0 parity contract (Section 15) passes for each *claimed* format variant; no known unsafe adapter is enabled; macOS everyday extract flow is verified end-to-end. Broad legacy-format parity is **not** a prerequisite for this milestone, but gaps must be published.

### Milestone B — Complete archive utility (P1)

- Create ZIP, TAR and supported compressed TAR formats; add level/algorithm controls and round-trip tests.
- Add archive tree browsing, filename search, selective extraction and previews where safely supported.
- Add verification, durable batch queue, retries, receipts, richer extraction preferences and optional delete-after-success with explicit safeguards.
- Expand common codecs (XZ, Zstandard, LZ4) based on qualification and demand.

**Exit gate:** common create/browse/extract workflows are reproducible, with structured results, cancellation and policy parity across UI/CLI.

### Milestone C — Universal container browser (P2)

- Add nested archive navigation with bounded depth and decompression budgets; lazy entry access when possible.
- Add first-class CBZ/CBR/CB7/CBT page ordering and previews; inspect ZIP-based documents and application packages.
- Add PE/EXE, `.app`, DEB/RPM and selected installer inspection without executing untrusted content.
- Add compatible conversions with explicit metadata/signature loss reporting; qualify disk-image browsing separately.

**Exit gate:** container semantics are verified by type, previews are isolated, and unsupported operations are explicit rather than silently staging a copy.

### Milestone D — Cross-platform shipping (parallel foundations; release milestone)

- Windows and Linux native-feeling shells, file associations, context menus, accessibility, signing/packaging and updates.
- Platform-specific safe filesystem APIs and link/reparse-point behavior; portable policy and operation receipts.
- CI for the shared Rust core begins in Milestone A; complete OS integration and release qualification here.

**Exit gate:** supported core operations and receipt schemas behave equivalently across macOS/Windows/Linux, with documented platform-specific exceptions.

### Subsequent investments (demand- and evidence-driven)

Legacy codecs (SIT/SITX, ACE, LHA, ARJ, etc.), advanced image formats, archive repair, third-party plugins, public commercial SDK, sticker themes and motion polish follow measured demand, licensing clearance and security isolation.

## 12. Test and qualification plan

**Conformance:** known-good archives per format/version/codec, filenames (Unicode/legacy encodings), timestamps, metadata, empty files, large files, ZIP64, solid archives, encryption, multipart and corrupted headers. Golden extracted trees compared by hashes and metadata policy.

**Security:** zip-slip, absolute paths, symlink/hardlink escapes, Windows reserved names/ADS/reparse points, decompression bombs, deeply nested containers, collisions, races, sparse files, malformed lengths and malicious checksums. Fuzz format detection and parsers with sanitizers.

**Performance:** measure cold probe latency, list latency, extraction throughput, creation throughput, peak RSS, CPU, disk I/O and UI responsiveness on representative small/mixed/large corpora. Publish hardware and codec settings with results; do not invent universal throughput claims.

**Cross-platform:** identical fixtures and receipt-schema validation across macOS/Windows/Linux CI; platform-specific permissions, paths, mount and association tests.

**UX acceptance:** one-step extract, smart folder handling, safe collision handling, browse/preview, clear unsupported explanations, keyboard and screen-reader access, reduced-motion support.

## 13. Open decisions

1. **Windows/Linux UI stack:** native per-platform vs shared shell; benchmark before committing.
2. **Default collision policy:** rename vs ask; existing CLI overwrite default is not acceptable for a safety-first product without deliberate opt-in.
3. **Core distribution:** in-process C ABI vs helper/IPC; choose based on parser isolation, progress/cancel and deployment constraints.
4. **Licensing:** review all codecs and RAR/legacy dependencies; no blanket assumption that redistribution or encoding is permitted.
5. **Support claims:** define release qualification criteria per format, variant, operation and platform.
6. **Package editing:** whether v1 includes modification of signed/document packages or stays inspect/extract-only.
7. **Security isolation:** OS-specific sandboxing and privilege boundaries for parsers, previews and mounts.
8. **Brand usage:** canonical orange vs user-selectable sticker artwork; ensure legibility in taskbar/Dock/desktop associations.

## 14. Updated implementation tickets

| ID | Milestone | Priority | Work item | Acceptance evidence |
|---|---|---|---|---|
| PEL-001 | A | P0 | Baseline build/test/dependency/license audit | Versioned format-variant matrix and reproducible baseline |
| PEL-002 | A | P0 | Safe extraction policy for all adapters | Traversal/link/race/budget tests; unsafe paths gated |
| PEL-003 | A | P0 | Capability registry and structured probe | Detected vs readable vs extractable vs qualified states, with evidence |
| PEL-004 | A | P0 | Real progress, cancellation, errors and receipts | Engine-driven progress, deterministic cancel/cleanup, UI/CLI parity |
| PEL-005 | A | P0 | Universal staging and safe commit | No silent overwrite or unreported partial output |
| PEL-013 | A | P0 | Password provider and encrypted archive qualification | ZIP variants, RAR, 7z fixtures; secrets never logged/argv |
| PEL-014 | A | P0 | Multipart volume handling | RAR/ZIP/7z positive, missing-volume and corruption fixtures |
| PEL-015 | A | P0 | Filename and metadata compatibility | Unicode, MacRoman/codepage, permissions and collision corpus |
| PEL-016 | A | P0 | macOS extraction/association release gate | Repeatable Open With, Peel Here, HUD, Settings, association tests |
| PEL-017 | A | P0 | Competitor conformance baseline | Shared corpus, recorded versions, machine and measured results |
| PEL-006 | B | P1 | Creation pipelines | ZIP/TAR/compressed TAR round-trip and metadata tests |
| PEL-007 | B | P1 | Archive browser and selective extraction | Large archive browsable without full extraction where possible |
| PEL-018 | B | P1 | Verify, batch jobs and richer preferences | Durable queue, retries, structured receipts and safe deletion option |
| PEL-009 | C | P2 | Comic format adapter and preview | Correct natural page order and supported-format disclosure |
| PEL-010 | C | P2 | Package/executable inspection | APP/PE/DEB/RPM and ZIP-based packages not misrepresented |
| PEL-011 | C | P2 | Disk-image read-only abstraction | Scoped DMG/ISO support and verified mount cleanup |
| PEL-019 | C | P2 | Nested containers and conversion | Bounded recursion, selective operations, loss reports |
| PEL-008 | D (CI in A) | P1 | Windows/Linux native integration | Platform filesystem safety, shell actions, accessibility and packaging |
| PEL-012 | Subsequent | P2 | Die-cut orange icon and motion | Legibility, OS icon compliance and reduced-motion tests |

## 15. Unarchiver-parity acceptance contract

**Scope:** Parity means the *supported everyday workflows* are reliable; it does **not** mean claiming every legacy XADMaster format is implemented. Publish an explicit supported-format/variant list and known gaps.

1. **Open behavior:** double-click/Open With extracts supported conventional archives with no unnecessary main window; unsupported or special containers open an honest inspect/unsupported path.
2. **Encryption:** supported passworded archives prompt securely, retry appropriately and distinguish wrong passwords from corruption or unsupported encryption.
3. **Multipart:** all parts are resolved when present; missing parts produce an actionable error; no false success on partial output.
4. **Progress:** item/byte counts are measured by the engine, unknown totals are labeled indeterminate, and cancellation stops work and cleans staging.
5. **Destination:** default extract-beside and containing-folder rules are deterministic; collision policy never silently destroys unrelated data.
6. **Names and metadata:** golden fixtures verify non-ASCII/legacy names, directory trees and supported metadata policy.
7. **Safety:** every enabled adapter passes traversal, link escape, budget, race and cleanup tests on supported operating systems.
8. **Integration:** file associations, Finder service, Settings and result reveal are reproducibly tested on supported macOS versions.
9. **Qualification:** release notes distinguish supported operations and known constraints for each format/version/encryption/multipart/platform combination.

**Pass rule:** Every applicable criterion has linked fixture/test receipts. Any unqualified variant is clearly labeled conditional/experimental or disabled. A reported smoke PASS is not a substitute for full conformance.

## 16. Competitive conformance and benchmark protocol

Use a versioned corpus containing small/mixed/large files, empty directories, large files, nested trees, Unicode and legacy encodings, encrypted and multipart archives, malformed headers, corrupted checksums, traversal/link payloads and decompression bombs. Preserve fixture provenance, generation commands, hashes and licensing.

For **Peel**, **The Unarchiver**, and **7-Zip**, record application/version, OS, CPU, memory, storage, archive format/codec/level, cold/warm state, iteration count and tool invocation. Only compare operations each tool actually supports; mark others `not supported`, never zero or failure by default.

**Correctness first:** compare extracted trees by file hashes, relative paths and explicitly scoped metadata; record warnings, skipped entries, partial outputs and exit status. **Performance second:** cold probe/list latency, time to first visible result, extraction and creation throughput, peak RSS, CPU, disk I/O and UI responsiveness. Repeat measurements, report distributions and variance, and separate engine benchmarks from GUI startup/integration tests.

**Adverse cases:** compare corruption diagnostics, password failures, missing volumes, safe rejection of malicious entries, cleanup after cancellation and filesystem collisions. Do not execute unknown installers or malicious payloads as part of detection.

**Claim gate:** no public "faster," "safer," or "more formats" claim without a dated, reproducible comparison scoped to tested versions, formats and workloads.

## 17. Status snapshot and decision log (2026-10-10)

| Area | Current evidence | Next required proof |
|---|---|---|
| macOS Open With / compact HUD / Peel Here / Settings | Reported local smoke PASS | Repeatable automated/manual release checks |
| ZIP/TAR/GZ/BZ2/RAR/7z | Source implementation paths | Variant-by-variant correctness and security fixtures |
| DMG | OS-tool extraction path | Read-only lifecycle, consent, cleanup and safety tests |
| APP | Directory-bundle copy path | Metadata and containment qualification; inspect semantics |
| PDF / EXE | Stage/copy handlers | Real inspection adapter or explicit unsupported result |
| CLI | `list`, `extract` | Structured `probe`, `create`, `verify`, progress and receipts |
| Security | PEL-002 helpers and partial staging reported | Adapter-wide adversarial proof; race and symlink tests |
| Passwords / multipart / real progress | Not integrated in supplied excerpts | P0 implementation and fixture qualification |
| Windows / Linux | Target only | Portable core CI early; native shells later |

**Open decisions added:** choose a secure password-prompt/provider contract; define multipart naming/discovery rules; decide whether archive deletion is opt-in and delayed until receipt verification; specify measured versus indeterminate progress UX; choose baseline competitor versions and benchmark corpus ownership.

---

**Implementation rule:** A detected extension is not a supported format, a listed entry is not a safely extractable entry, a smoke test is not a release qualification, and a successful extraction is not proof that the output is trustworthy. Release claims must be pinned to tests for each operation, variant, and platform.

## Product identity and monetization decision (2026-10-10)

**One Peel:** extraction, browsing, Finder Quick Look, encryption, inspection and authorized recovery belong to one application and brand. Do not split into Extract/Explore/Protect products. **Free** includes ordinary extraction, creation, known-password unlocking, modern encrypted creation, protection inspection, normal migration, Quick Look and qualified optional Finder browsing. **Pro** is proposed for specialized forgotten-password assistance, advanced candidate testing, qualified legacy recovery and optional acceleration. Provide a **free recovery feasibility preflight** and never promise that paid access can bypass strong encryption. Pricing hypothesis: US$29–49 one-time, not approved. See `PEEL_PRODUCT_IDENTITY_AND_MONETIZATION_v0.1.md` for decision, entitlement matrix, journeys and tickets PRD-001–008.
