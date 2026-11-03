# Peel — status, qualification, backlog

**Snapshot:** 2026-10-19 documentation consolidation. No builds, tests, or runtime audits were performed as part of this update. Review current source before treating earlier findings as still open.

## Evidence vocabulary

- **Proposed:** documented design only.
- **Observed source:** code path exists, behavior not independently qualified.
- **Reported smoke:** someone reported a successful run; not independently reproduced.
- **Tested:** reproducible fixture passed with recorded environment.
- **Qualified:** format × variant × operation × platform meets correctness, security, cleanup, accessibility (where relevant), and release gates.

The existing source was previously reported to include ZIP/TAR/GZIP/BZIP2/RAR/7z adapters, macOS SwiftUI shell, CLI/FFI scaffolding, and DMG OS backend. Prior review flagged password-in-argv, misleading 7z listing success, list-only 'test', resource-budget gaps, unsafe commit behavior, inconsistent selection, and incomplete cancellation. **These are historical findings to revalidate, not verified current failures.**

## Priority order and issue map

| Priority | Track | Acceptance evidence |
| --- | --- | --- |
| P0 | Baseline build, tests, dependency/license audit | Clean checkout reproducible build; versions and matrix |
| P0 | Secure password transport and honest errors | No argv/log secrets; wrong-password/corrupt fixtures |
| P0 | True payload verification | Corrupt payload fails; coverage is reported |
| P0 | Path/link containment, runtime limits, transactional commit | Adversarial and fault-injection tests |
| P0 | Structured progress, cancellation, cleanup, receipts | UI/CLI parity and crash/cancel fixtures |
| P0 | Multipart and selective-extract parity | ZIP/RAR/7z volume and selected-entry corpus |
| P1 | Versioned graph, ByteSource, capability registry | Paginated stable entries; supported/conditional statuses |
| P1 | Quick Look archive preview | Signed extension, no app window, bounded tree |
| P1 | Native browser, search, previews, open-inside | ZIP and second format, managed cache cleanup |
| P1 | Create, encrypt, verify, audit | Round-trip fixtures, honest security findings |
| P2 | Optional PeelFS feasibility and read-only mount | Finder behavior, signing, eject, encrypted cache |
| P2 | ISO/BIN-CUE/IMG and nested package adapters | Typed tracks/partitions, malformed input corpus |
| P2 | Pro recovery research, licensing and benchmarks | Fixed-budget controls; no guaranteed recovery |
| P3 | Archive writeback / recoverable new container | Independent review, staged rebuild, metadata receipts |

See GitHub issues for work tracking; don't close an issue without linked test evidence. Prefer adding references to existing issues over duplicates. Cross-platform Rust CI begins now even though macOS is the current UI focus.

## Release gates

1. Security: no password disclosure, untrusted path escape, unbounded expansion, or destructive commit.
2. Correctness: actual payload verification where claimed, no fake listing success, no silent skipped entries.
3. UX: Finder associations/Quick Look qualified per macOS version; accessible fallback browser.
4. Lifecycle: cancellation, crash, eject, stale source, temp-cache cleanup, and mount teardown are tested.
5. Documentation: every feature and format has versioned capability status and evidence; Pro purchase is not represented as guaranteed recovery.

## Open decisions

- Finder mount implementation feasibility: FUSE/system extension vs native browser fallback, distribution and sandbox.
- Whether double-click defaults to extraction or browsing for new installations; preserve user preference.
- Cache size, location, encrypted-file policy, and cleanup semantics.
- Windows/Linux shell choice and OS integration scope.
- Recovery pricing, license model, offline entitlement, upgrades, and optional acceleration.
- Private/recoverable encryption format selection and independent cryptographic review.
- Format/codec licensing, especially legacy and RAR-related dependencies.
