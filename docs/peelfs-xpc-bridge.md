# PeelFS ↔ peel-core bridge

**Version:** 0.1.0  
**Date:** 2026-10-11  
**Status:** Design for production PeelFS (post–Gate A mount)  
**Related:** `finder-open-interaction.md` §10.3, `fskit-peelfs.md`, `finder-quicklook.md`

## 1. Problem

The FSKit appex spike parses ZIP in-process (`ZipArchiveReader`). That diverges from peel-core, cannot share RAR/7z/tar/safety policy, and will rot. Quick Look and the main app already (or will) need the same list/read primitives.

**Rule:** peel-core is the only format authority. Extensions are thin clients.

## 2. Target shape

```text
┌─────────────────────┐     ┌──────────────────────────┐
│ PeelFSExtension     │     │ PeelQLPreview (future)   │
│ (FSKit, sandboxed)  │     │ (QL, sandboxed)          │
└─────────┬───────────┘     └────────────┬─────────────┘
          │ XPC                           │ XPC
          └──────────────┬────────────────┘
                         ▼
          ┌──────────────────────────────┐
          │ PeelArchiveService (XPC)     │
          │ io.snackstud.peel.archivesvc │
          │  - hosts peel-core via FFI   │
          │    or peel CLI helper        │
          │  - budgets, cancel, cache    │
          └──────────────┬───────────────┘
                         ▼
                   peel-core / peel FFI
```

Main app (`io.snackstud.peel`) can talk to the same service for in-app browser parity.

## 3. Transport choice

| Option | Pros | Cons |
| --- | --- | --- |
| **A. XPC service + peel-ffi** | Low latency, typed, cancel-friendly | Need stable C/Swift FFI surface |
| **B. XPC service shells `peel` JSON** | Reuses CLI now | Higher latency; argv/password care |
| **C. Appex links peel-ffi directly** | No hop | Sandbox + code size; hard to share with QL |

**Phase 1:** B (JSON CLI over XPC) to unblock mount/QL without finishing FFI.  
**Phase 2:** A (peel-ffi) once list/read APIs stabilize.

## 4. Service API (v1)

All paths are security-scoped bookmarks or already-accessible sandbox paths granted by the host resource.

```text
probe(url) -> { format, encrypted, entry_count?, warnings[] }
list(url, opts) -> { entries: [{ path, is_dir, size, method? }], truncated: bool }
read(url, member_path, opts) -> { bytes | file_url, size }   # bounded
cancel(job_id) -> ok
```

### Options / budgets

```text
opts.max_entries        default 5000
opts.max_bytes_list     default 32 MiB wall for listing work
opts.max_read_bytes     default 64 MiB per read (or stream chunks)
opts.timeout_ms         default 30_000
opts.password_ref       keychain / one-shot XPC secret, never logs
```

### Errors (stable codes)

`not_archive`, `unsupported_feature`, `encrypted`, `truncated`, `bomb_suspected`, `cancelled`, `io`, `sandbox`.

## 5. FSKit mapping

| FSKit | Service |
| --- | --- |
| `probeResource` | `probe` |
| volume tree build | `list` (paged if needed) |
| `read` on file item | `read` member; cache short-lived in service tmp |
| deactivate/unmount | drop session; `cancel` outstanding jobs |

**Do not** load entire archive into appex memory. Prefer mmap/core streaming inside the service.

## 6. Security

- App group or Mach service name restricted to team id.
- Appex sandbox: user-selected / path-URL resource only for the mounted archive.
- Service validates member paths (no `..`, no absolute escape).
- Passwords only via XPC + optional Keychain; never argv in production path (CLI phase uses secure temp or env carefully).
- No telemetry of paths/secrets.

## 7. Packaging

| Binary | Bundle ID | Install |
| --- | --- | --- |
| Peel.app | `io.snackstud.peel` | `/Applications` |
| PeelFSExtension.appex | `io.snackstud.peel.PeelFS` | embedded |
| PeelQLPreview.appex | `io.snackstud.peel.qlpreview` | embedded |
| PeelArchiveService.xpc | `io.snackstud.peel.archivesvc` | embedded in app `Contents/XPCServices` |

Service is launched on demand by XPC; code-signed with same team.

## 8. Migration from spike

1. Gate A: mount works at all (OS).
2. Introduce `archivesvc` with `probe`/`list`/`read` via CLI JSON.
3. Point `PeelFSVolume` payloadProvider at service `read`.
4. Point QL listing at service `list`.
5. Replace CLI backend with peel-ffi.
6. Delete `ZipArchiveReader` from appex.

## 9. Acceptance

- Opening one small file from a large ZIP does not decompress all members (when format allows).
- Cancel stops in-flight read.
- RAR/7z list works once core adapters do, without appex changes beyond format allow-list.
- QL and PeelFS show the same entry paths for the same fixture.

## 10. Non-goals (v1)

- Write-back / repack through mount
- Network archives
- Running untrusted entry code in-process
