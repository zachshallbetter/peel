# Peel 0.2 — Codebase Review and Remediation Plan

**Date:** 2026-10-10  
**Source:** `peel.2.zip` and the accompanying repository reports  
**Reference:** Peel Product & Technical Specification v0.2.0  
**Status:** Source-review findings and recommendations; reported tests are not independently reproduced in this document.

## Executive assessment

Peel has a functional macOS extraction workflow, including Finder/Open With entry points, a compact progress HUD, settings, and extraction paths for ZIP, TAR, GZIP, BZIP2, RAR, and 7z. The newer source also includes partial password, multipart, selective-extraction, and source-deletion functionality. This does not yet establish production-grade format qualification or The Unarchiver parity.

**Recommendation:** Close correctness, safety, secret-handling, and operational gaps before broadening format support or building the full container browser.

## Capability assessment

| Capability | Current assessment | Qualification needed |
|---|---|---|
| ZIP / TAR / GZIP / BZIP2 extraction | Implemented paths | Adversarial and conformance corpus |
| RAR / 7z extraction | Implemented paths | Password, multipart, solid, malformed and safety tests |
| Password handling | Partial | Protected secret transport and UI flows |
| Multipart RAR | Partial | Volume discovery and full-set conformance |
| Selective extraction | Partial / inconsistent | Same selection contract across adapters |
| Delete source after extraction | Implemented path | Verified completion and failure reporting |
| `probe` and `test` CLI | Partial | Honest detection and payload verification |
| Real engine progress / cancel | Not yet established | Structured event and cancellation contract |
| Archive creation / conversion | Not established | New pipelines and round-trip tests |
| Archive browser | Not established | Browse/search/preview/selective UX |
| macOS Finder and HUD | Reported smoke-test pass | Release reproducibility and accessibility |
| Windows / Linux shells | Not established | Dedicated implementation and qualification |

## Findings and recommended actions

### P0-01 — Passwords in process arguments

The reviewed Swift client constructs `-p` plus the password in the child-process arguments. This exposes secrets to process inspection and violates the spec's secret-handling contract.

**Action:** Move password transfer to a protected pipe/file descriptor or other secure IPC mechanism. Redact diagnostics and receipts. **Acceptance:** password never appears in argv, logs, job records, or crash diagnostics.

### P0-02 — Misleading 7z listing success

The reviewed `list_7z` path can substitute a synthetic entry after a listing error. Callers can mistake failure for successful enumeration.

**Action:** Return structured errors, including encrypted-header/unsupported-variant distinctions. **Acceptance:** unreadable or corrupt 7z files cannot produce a successful list/test result.

### P0-03 — `test` is not integrity verification

The CLI `test` path uses archive listing rather than decoding and checking file payloads.

**Action:** Implement per-format full-payload verification and checksums where supported, or rename the existing command to a metadata/list check. **Acceptance:** damaged payload fixtures fail verification reliably.

### P0-04 — Runtime resource enforcement gaps

Metadata-based size estimates and post-extraction tree checks do not by themselves stop an adapter from exhausting disk, CPU, or memory during decompression.

**Action:** Enforce streamed byte budgets and runtime limits; isolate adapters where write callbacks are unavailable. **Acceptance:** decompression-bomb and runaway-resource fixtures terminate within configured bounds.

### P0-05 — Non-transactional destination commit

Existing staging is useful, but destination deletion and file-by-file merging can leave partially modified output if commit fails.

**Action:** Preflight collisions, stage output, commit atomically where possible, and record/restore or explicitly report partial changes. **Acceptance:** simulated mid-commit failure never silently destroys unrelated files.

### P1-01 — Inconsistent selective extraction

ZIP applies selection during extraction; the inspected RAR path extracts broadly before filtering; the inspected 7z path does not consistently apply selection.

**Action:** Define a common selection contract with explicit fallback behavior. **Acceptance:** the same selected paths produce equivalent outputs or an explicit unsupported response for every format.

### P1-02 — Source deletion safety

Deleting archives after a nominally successful extraction requires stronger completion evidence, particularly for multipart sets.

**Action:** Delete only after all requested outputs are committed and verified to the configured level; report deletion failures. **Acceptance:** no source is deleted on incomplete extraction or unresolved output failure.

### P1-03 — Genuine progress and cancellation

The compact HUD exists, but the Rust engine lacks a confirmed structured byte/entry event stream and robust cancellation semantics.

**Action:** Add versioned operation IDs, progress events, warnings, terminal receipts, and cancellation tokens. **Acceptance:** UI displays measured progress or an honest indeterminate state; cancel stops work and cleans up safely.

### P1-04 — Reproducible workspace packaging

The supplied archive appeared to omit the root Cargo workspace manifest, despite scripts using workspace-level Cargo commands. Confirm whether this is export-only omission.

**Action:** Ensure distributable source archives include the complete workspace and lockfile. **Acceptance:** clean-machine build and tests run using documented commands.

## Proposed next build sequence

| Order | Deliverable | Exit condition |
|---|---|---|
| 1 | Secure password channel and honest errors | No argv secrets; no false-positive list/test success |
| 2 | Real integrity verification | Corrupt payloads rejected in fixture tests |
| 3 | Resource budgets and transactional commits | Adversarial extraction and fault-injection tests pass |
| 4 | Progress, cancellation, operation receipts | UI/CLI agree on actual operation state |
| 5 | Selection and multipart conformance | Shared corpus passes across supported adapters |
| 6 | Safe source deletion and packaging | Failure-safe deletion and clean build reproduction |
| 7 | Creation and archive browser | Start only after core reliability exit criteria |

## Release qualification contract

Track each **format × variant × operation × platform** separately. A feature should move through **detected → readable → extractable → qualified**, with test evidence for each promotion. Compare representative fixtures with The Unarchiver and 7-Zip for output correctness, filename preservation, failures, memory use, and throughput. Do not claim parity based on code paths or a small smoke suite alone.

## Scope and evidence limitations

This document records the findings from the Peel 0.2 review in this conversation and the supplied repository/report excerpts. It is not a completed independent security audit, and it does not claim fresh execution of the project's tests or macOS app. Validate findings against the current branch before marking tickets resolved.
