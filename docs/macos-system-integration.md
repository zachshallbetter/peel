# Peel — macOS system integration investigation

**Version:** 0.1.0  
**Date:** 2026-10-10  
**Status:** Research architecture and experiment plan — not implementation claims  
**Related:** `finder-quicklook.md`, `containers.md`, `architecture.md`, `specification.md`

## Purpose

Investigate less commonly used macOS frameworks that can change Peel’s product architecture—not only polish the UI. Some provide capabilities we can ship; others expose OS behaviors conventional archive utilities rarely integrate deeply.

**Central distinction:** peel-core remains the source of truth for detection, listing, reading, materialization, policy, and cancellation. Platform frameworks are **adapters and surfaces**, never a second parser stack.

## Product thesis

Archives should feel like folders, not files that must be unpacked before use—while keeping double-click extract as the reliable default until the user opts into browse-first behavior.

```text
                    macOS
                      |
          +-----------+-----------+
          |           |           |
        Finder     Quick Look   Spotlight
          |           |           |
          +-----------+-----------+
                      |
             Peel Integration Layer
                      |
          +-----------+-----------+
          |                       |
       PeelFS               Peel App / Browser
          |                       |
          +-----------+-----------+
                      |
              Archive Session
                      |
              Container Graph
                      |
           Read / Materialization
                      |
               Rust Adapters
                      |
             Archive / Image bytes
```

The same entry identity should be reachable from Spotlight, Quick Look, Finder (when mounted), and Peel extract without duplicating parsers.

---

## Framework inventory

### 1. FSKit — archives as userspace filesystems

**Impact: Transformative | Priority: P0 investigation**

FSKit enables userspace filesystem implementations. Peel could expose ZIP/RAR/7z/ISO as a **read-only virtual volume** (PeelFS) so Finder column/list/icon views, Space (Quick Look of entries), drag-out, and open-in-default-app work against ordinary paths.

```text
Downloads/
  project.zip
       |
       v
    PeelFS (read-only mount)
       |
       +-- Documents/
       +-- Images/
       +-- README.md
```

**Hard problem:** map filesystem reads to archive I/O. Seekable ZIP entries can be efficient; **solid 7z/RAR** may require decompressing preceding data. PeelFS must declare adapter capabilities and refuse unbounded reads.

**Not assumed:** FSKit is not automatically a complete replacement for macFUSE. Evaluate distribution, install, signing, mount lifecycle, and macOS version support.

**First experiment:** mount a simple ZIP read-only; browse in Finder; eject; measure latency for random entry open; document install story.

**Decision gate:** only after FND-004-style acceptance (browse, Space, drag/copy, eject, crash recovery, no-write guarantee). See `finder-quicklook.md` Tier C.

---

### 2. Quick Look extensions — native inspection

**Impact: Very high | Priority: P0**

Custom archive preview on Space—not only a filename list:

| Element | Content |
| --- | --- |
| Header | Name, format, total size |
| Contents | Bounded navigable hierarchy |
| Preview | Thumbnail / preview of selected entry |
| Security | Encryption and integrity status |
| Actions | Open entry, extract selected, browse |
| Inspector | Ratio, metadata, warnings |

Contact sheets for CBZ/photo ZIPs and volume maps for ISOs are format-semantic views over the same container graph.

**Constraints:** QL extensions are not unrestricted apps. Lifetime, sandbox, and helper access must be verified. Interactive behavior is limited.

**First experiment:** ZIP-only QL extension with bounded listing, locked-state UI, no full extract. **FND-001**.

---

### 3. File Provider — on-demand materialization (conditional)

**Impact: High, conditional | Priority: P2 research**

File Provider is for **managed domains** (cloud-style “file exists before bytes are local”). Useful for a persistent **Peel Archives library**, not for expanding arbitrary archives in place.

**Not:** a generic FS driver or substitute for PeelFS at the archive’s original path.

**First experiment:** prototype a managed domain only if FSKit/QL path is blocked and a library UX is prioritized.

---

### 4. NSFileCoordinator / NSFilePresenter — changing sources

**Impact: High | Priority: P0**

When Peel holds an open archive and another process replaces the file, offset-based reads become unsafe. Introduce an explicit **ArchiveSession**:

```text
ArchiveSession
  source identity + version
  open handles
  content index
  active readers
  materialized entries
  invalidation state
```

On source change: invalidate session, cancel readers, prompt reopen. Required for PeelFS and multi-window browse. Complements—not replaces—fd identity checks and budgets.

---

### 5. Disk Arbitration & Disk Images — DMG/ISO workflows

**Impact: High | Priority: P1**

Separate **inspect via Rust adapters** from **OS mount**:

```text
example.dmg
  detect → metadata → encryption?
  → user consent → mount read-only
  → browse in Finder → eject + cleanup
```

Use Disk Arbitration for mount/unmount notifications. Prefer documented OS facilities over reimplementing image attach. Never silently mount untrusted images (spec non-goal).

---

### 6. Spotlight metadata importers — search inside archives

**Impact: Very high | Priority: P1**

First version: archive-level metadata (contained names, paths, types, bounded text where allowed) attached to the **archive item**. Entry-as-independent-Spotlight-file needs extra architecture.

Product line: **Search what’s inside, without unpacking.**

Peel may also maintain a private entry index for richer results than MD importers alone allow.

**First experiment:** ZIP filename importer; prove query surfaces parent archive; no full extract.

---

### 7. Compression framework — optional codec backend

**Impact: Medium–high | Priority: P2**

Apple Compression is **streams/algorithms**, not archive containers. Benchmark vs Rust codecs (throughput, memory, cancel, correctness). Optional platform backend behind peel-codec selection—never replace container/encryption logic.

---

### 8. CryptoKit & Security framework — secrets, not format crypto

**Impact: High | Priority: P1**

Archive-format crypto stays in peel-core adapters. OS integration:

- Keychain for **opt-in** stored passwords
- Secure credential prompts
- CryptoKit for modern primitives where formats allow
- Secure Enclave only with explicit key-wrapping design

Touch ID does not magically unlock ZIP/RAR/7z; Peel still needs password/key material.

---

### 9. Endpoint Security — specialized only

**Impact: Specialized | Priority: P3 / research only**

Requires special entitlements; unsuitable as a general consumer dependency. Prefer coordination + session invalidation.

---

### 10. Uniform Type Identifiers — presentation & routing

**Impact: Medium | Priority: P1**

Declare and consume UTTypes so CBZ ≠ plain ZIP in UI and Services. Rust signature inspection remains authoritative. Improves Open With, Quick Look registration, and comic/package semantics.

---

## Recommended experiment order

| Priority | Technology | Opportunity | First experiment |
| --- | --- | --- | --- |
| **P0** | FSKit (+ macFUSE comparison) | Finder-native navigation | Read-only ZIP mount prototype |
| **P0** | Quick Look | Inspect without full app | ZIP QL extension (FND-001) |
| **P0** | File coordination | Safe sessions | Detect replace/invalidate |
| **P1** | Spotlight importers | Search contents | ZIP filename metadata |
| **P1** | Disk Arbitration | DMG/ISO lifecycle | Consentful read-only mount |
| **P1** | Security / Keychain | Credentials | Opt-in password store |
| **P1** | UTType | Associations | Semantic type table |
| **P2** | Compression framework | Perf | Codec bake-off |
| **P2** | File Provider | Archive library domain | Optional prototype |
| **P3** | Endpoint Security | Monitoring | Research only |

### Three decisive experiments

1. **FSKit** — Can we mount ZIP read-only and navigate in Finder with acceptable install + performance?  
2. **Quick Look** — Can we show a real tree + entry preview without launching the main window?  
3. **Spotlight** — Can contained names surface without expanding every archive?

If all three work with one container graph, Peel is no longer “another unarchiver”—it is a **macOS content surface** for compressed and structured files.

---

## Shared engine contracts (required before deep integration)

Do not start FSKit/QL/Spotlight until these exist or are gated:

| Contract | Why |
| --- | --- |
| Capability registry (PEL-003) | Honest mount/list/preview support |
| Entry IDs + container graph (`containers.md`) | Same identity across surfaces |
| `list_children` / `open_entry` / `materialize_entry` | QL + PeelFS + open-one |
| Resource budgets + cancel (PEL-002/004) | No bombs via mount or QL |
| ArchiveSession + file coordination | Stale source safety |
| Password broker (no argv secrets) | Encrypted archives in QL/FS |
| Cleanup receipts | Unmount / QL cache / temp materialization |

---

## Implementation tickets (proposed)

| ID | Priority | Work | Acceptance |
| --- | --- | --- | --- |
| **MAC-001** | P0 | ArchiveSession + NSFileCoordinator on open archives | Replace-while-open invalidates; no silent wrong reads |
| **MAC-002** | P0 | QL preview extension skeleton (ZIP) | Space on ZIP shows Peel preview; main app not required |
| **MAC-003** | P0 | Bounded `list_children` IPC for QL helper | Caps on entries/time/memory; cancel works |
| **MAC-004** | P0 | FSKit vs macFUSE decision spike | Scaffold + report in-repo (`docs/fskit-peelfs.md`, `.reports/mac-004-fskit-spike.md`); live mount pending signing |
| **MAC-005** | P1 | UTType map for Peel document types | CBZ/CBR/comic + package types declared and used |
| **MAC-006** | P1 | Spotlight MD importer spike (ZIP names) | Query finds archive by inner filename |
| **MAC-007** | P1 | DMG lifecycle via Disk Arbitration | Consent → mount RO → eject cleanup receipt |
| **MAC-008** | P1 | Keychain opt-in password store | Store/retrieve with user consent; never logs |
| **MAC-009** | P2 | Compression.framework bake-off | Numbers vs flate2/lzma backends |
| **MAC-010** | P2 | File Provider library domain spike | Only if FSKit path rejected for library UX |

Align with existing FND-001…FND-005 in `finder-quicklook.md` and `specification.md`.

---

## What ships today vs investigation

| Surface | Today (app) | Target |
| --- | --- | --- |
| Open With / Services (Peel, Peel to…, Peel & Reveal) | Implemented | Keep; expand actions as mount/QL land |
| Compact HUD extract | Implemented | Keep as default everyday path |
| Finder refresh after extract | Implemented | Keep |
| Quick Look archive preview | Docs only | FND-001 / MAC-002 |
| PeelFS mount | Spike scaffold (PeelFSExtension, ZIP RO) | MAC-004 → FND-004 |
| Spotlight inside archives | Docs only | MAC-006 |
| ArchiveSession coordination | Partial (process extract) | MAC-001 |

---

## Non-goals for this track

- Transparent write-through editing of archives in Finder (v1)
- Replacing Rust format crypto with CryptoKit for ZIP/RAR/7z
- Endpoint Security as a product dependency
- Claiming File Provider expands ZIPs in place
- Shipping FSKit without install/signing/perf qualification

---

## References

- Apple FSKit / File Provider / Quick Look / Spotlight importer documentation (version-pin per release)
- `docs/finder-quicklook.md` — tiers A/B/C and FND tickets  
- `docs/fskit-peelfs.md` — PeelFS extension layout and enablement  
- `.reports/mac-004-fskit-spike.md` — FSKit vs macFUSE decision notes  
- `docs/containers.md` — container graph and volume resolution  
- `docs/encryption.md` / `encryption-architecture.md` — secrets and recovery boundary  
- macFUSE — comparison baseline for userspace mounts  
