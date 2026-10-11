# Peel — Encryption, Unlocking & Lost-Password Recovery

**Version:** 0.1.0 (design proposal)  
**Date:** 2026-10-10  
**Status:** Proposed architecture; not an implementation-complete claim  
**Product principle:** *Open what's inside—without pretending strong encryption can be bypassed.*

## 1. Purpose and scope

Make encrypted containers a baseline Peel capability. A user should be able to (a) recognize a protected file, (b) unlock and extract it safely with a known credential, and (c) follow a practical, privacy-preserving recovery workflow when a credential is lost. Recovery includes locating credentials, reconstructing plausible passwords, bounded offline candidate testing, and restoring accessible copies of the underlying files.

This document covers ZIP, 7z, RAR, encrypted disk images and selected document/package formats. It does **not** promise universal decryption, recovery of cryptographic keys from ciphertext alone, or support for every variant under a shared filename extension.

## 2. Non-negotiable distinctions

- **Recognition:** identify container, encryption variant, and whether names/metadata are visible.
- **Unlocking:** use a valid password, key, certificate, token or platform authorization.
- **Password recovery:** discover or infer the actual secret, then verify it.
- **Data restoration:** locate another accessible copy of the desired content; does not decrypt the protected original.
- **Cryptanalysis:** exploit a specific weakness in a legacy algorithm, implementation, or file construction; not a generic AES bypass.
- **Verification:** prove that a credential decrypts/authenticates the relevant payload; a readable header alone is not enough.

A successful password check does not automatically mean all archive entries can be extracted safely or without corruption.

## 3. Experience contract

### Known password

1. Open protected file; detect exact format and protection mode.
2. Show a concise unlock prompt with optional show/hide and a clear explanation of what is encrypted.
3. Accept password through a secure secret channel; never through CLI argv, URLs, diagnostics, telemetry or persisted job JSON.
4. Verify the password using format-specific checks, then extract through the same safe-output and transactional-commit pipeline as unencrypted files.
5. Offer explicit opt-in to save the credential in the operating system's secure credential store.
6. Distinguish **incorrect credential**, **unsupported encryption**, **corrupt archive**, **missing volume**, and **extraction failure**.

### Forgotten password

Present a recovery assistant with four clear options:

1. **Find saved access:** look in Peel's own saved credentials; guide the user through authorized password-manager or OS credential retrieval, and check legitimate accompanying password hints.
2. **Try what I remember:** accept user-provided words, dates, patterns, approximate length and other hints; show the estimated candidate count before testing.
3. **Run a bounded local search:** user-authorized dictionary, mask, and rules-based testing; report measured throughput, estimated range, energy use and stop conditions.
4. **Find another copy:** with explicit directory/backup access, locate previously extracted files, unencrypted originals or earlier versions.

Show **No practical recovery path found** when the evidence supports that conclusion. Never promise an unlock based solely on file type or GPU availability.

## 4. Format and encryption qualification matrix

| Container | Protection examples | Metadata visibility | Known-secret unlock | Lost-secret path | Key cautions |
|---|---|---|---|---|---|
| ZIP | Traditional PKWARE/ZipCrypto | Usually names visible | Planned baseline | Candidate tests; selected legacy cryptanalysis where applicable | Legacy ZipCrypto is weak; ZIP AES variants require distinct handling |
| ZIP | WinZip AES (AE-1/AE-2) | Usually names visible | Planned baseline | Credential discovery and candidate search | Do not equate AES-128/256 with password strength |
| 7z | AES-256 with password-based derivation | Headers may be encrypted | Planned baseline | Candidate search; often expensive | Encrypted headers can prevent listing |
| RAR3 | Version-specific AES protection | Varies | Planned baseline | Candidate search; specialized legacy analysis only if justified | Format version matters |
| RAR5 | AES-256 and password-based derivation | Headers may be encrypted | Planned baseline | Candidate search; often expensive | Multipart and solid archives complicate verification |
| PDF | Standard security handlers; version-dependent | Some document structure may be readable | Separate planned adapter | Credential discovery and variant-specific candidate search | Opening password and permissions password differ; respect permissions |
| OOXML/Office | Office encryption (not simply ZIP entry encryption) | Often hidden | Separate planned adapter | Candidate search where supported | Must detect encrypted Office container, not assume DOCX is ordinary ZIP |
| DMG | Apple disk-image encryption | Depends on image | macOS adapter | Saved credential, keychain, candidate search if supported | Mount only with explicit consent; unmount reliably |
| VHD/VHDX, disk volumes | May contain BitLocker, LUKS, FileVault or other encrypted volumes | Often only outer volume metadata | Future specialized adapter | Recovery keys, escrow, keyslots, backups | Distinguish image format from encryption inside its filesystem |
| Proprietary packages | Vendor-specific | Varies | Per-variant only | Per-variant only | Never claim support from extension alone |

**Support state per variant:** `detected` → `protection_identified` → `unlock_supported` → `verified` → `extraction_qualified` → `recovery_qualified`. These are independent evidence-backed claims, not automatic promotions.

## 5. Component architecture

```text
Native UI / CLI / SDK
        |
Protected-File Controller --------------> Recovery Assistant
        |                                        |
Encryption Probe                         Recovery Planner
        |                                        |
Capability Registry                  +-----------+-------------+
        |                            |           |             |
Credential Broker <---------------- Saved     Candidate     Copy/Backup
        |                         Access      Verifier      Discovery
        |                            |           |             |
Secure Secret Channel <--------------+-----------+-------------+
        |
Format-Specific Unlock Adapter
        |
Verified Read/Decode Stream
        |
Common Extraction Policy / Safe Writer / Staging / Commit
        |
Redacted Operation Receipt
```

### Module responsibilities

- **`peel-crypto` (proposed Rust module/crate):** encryption variant descriptors, credential verification interface, cryptographic primitives where necessary, secret zeroization, typed failures. Prefer audited libraries over original cryptographic implementations.
- **Credential broker:** mediates user-authorized retrieval and storage; secure platform interfaces; no silent password-store enumeration.
- **Recovery planner:** estimates candidate counts and cost, prioritizes remembered hints, and prevents unbounded work by default.
- **Candidate verifier:** tests candidates against an exact archive/volume set; supports CPU workers first, optional GPU backends later. Must distinguish false positives from complete verification.
- **Copy finder:** opt-in searches of authorized locations and backup indexes using available filenames, sizes, fingerprints or known manifests.
- **Operation supervisor:** cancellation, quotas, process isolation, checkpoint metadata, thermal/battery limits and progress events.
- **Format adapter:** understands encryption-specific headers, key derivation and payload authentication; it does not own secret storage, arbitrary destination writes or UI prompts.

## 6. Interfaces and data model

Illustrative types (not existing code):

```text
ProtectionDescriptor {
  format_family, format_variant, encryption_scheme,
  password_kdf?, metadata_encrypted, requires_external_key,
  supported_unlock_methods[], recovery_support, evidence[]
}

UnlockRequest {
  operation_id, input_ref, volume_set_ref?, secret_ref,
  selected_entry_ids[], destination, extraction_policy
}

RecoveryPlan {
  operation_id, archive_fingerprint, strategy,
  candidate_source_ref?, search_space_estimate?,
  measured_attempts_per_second?, time_budget, resource_budget,
  user_consent, feasibility_note
}

RecoveryEvent {
  operation_id, phase, tested_candidates, measured_rate?,
  candidates_remaining_estimate?, elapsed_ms, warnings[]
}

RecoveryReceipt {
  operation_id, archive_fingerprint, method,
  outcome, verified_secret_found, tested_candidates,
  duration_ms, caveats[], artifact_refs[]
}
```

**Secret handling:** A `secret_ref` must resolve only inside the authorized operation and must not be serialized to disk. Recovered passwords are displayed or saved only on explicit user request. Checkpoints may contain nonsecret search state, not candidate strings that disclose the user's personal password hints by default.

## 7. Recovery strategy ladder

### R0 — Establish exact facts

Confirm file integrity, all multipart volumes, correct file identity, encryption scheme, metadata visibility and whether the archive can be verified offline. Distinguish a corrupt archive from an incorrect password. For split archives, discover the complete volume set before recovery.

### R1 — Recover an existing secret or key

Use user-authorized Peel credentials, OS keychain, password-manager lookup, original sender/download instructions, organization escrow, recovery keys and backup documentation. For encrypted volumes, a recovery key or keyslot may be more relevant than the original password.

### R2 — Restore the data without decrypting this copy

Find original files, previously extracted directories, cloud history, backups, alternate unencrypted exports or earlier snapshots. This often achieves the user's goal with less time and uncertainty.

### R3 — Reconstruct the password

Accept remembered fragments and generate bounded candidates using case, separators, substitutions, dates, suffixes and masks. Preview the scope without revealing sensitive guesses in logs. Prioritize user-specific hints over broad dictionaries.

### R4 — Offline dictionary/rule/mask testing

Test only against archives the user is authorized to access. Benchmark the actual archive variant, then show an estimated cost interval and allow the user to set maximum duration, CPU/GPU use and power limits. Do not present candidate progress as probability of success.

### R5 — Specialized legacy weakness analysis

For certain weak or incorrectly implemented schemes (notably some legacy ZIP constructions), specialized techniques may outperform generic password guessing. Gate such methods by positively identified format/variant and the evidence they require (for example, known plaintext). Keep a reviewed, per-variant catalog of applicable techniques; never generalize a weakness to AES-protected ZIP, 7z or RAR5.

### R6 — Exhaustive search within a small defined space

Offer only when the user has constrained the search space enough to make the expected work defensible. Explain that long random passwords protected by correctly implemented modern encryption may be computationally infeasible to recover.

## 8. Strong-encryption lost-password research program

The next research phase must answer **which route can recover access**, not presume that strong encryption can be broken. Investigate these tracks in order:

| Track | Research question | Evidence needed | Expected outcome |
|---|---|---|---|
| Credential provenance | Where might the original secret or recovery key exist? | OS/platform credential interfaces; user-authorized sources | Recovery without cryptanalysis |
| Alternate-copy recovery | Can equivalent plaintext be restored? | Backup metadata, accessible paths, file fingerprints | Restore files, not decrypt archive |
| KDF cost benchmarking | How many candidate passwords can be checked per second for this exact variant? | Controlled fixture set; CPU/GPU benchmark | Defensible feasibility estimates |
| Targeted candidate construction | Can user hints reduce search space enough? | Candidate-count models and synthetic test passwords | Higher practical success per unit compute |
| Legacy cryptanalysis | Does the identified legacy format have a documented weakness? | Exact variant, known plaintext, reproducible fixtures | Limited specialized recovery |
| Key/escrow mechanisms | Are recovery keys, keyslots, certificates or organization escrow supported? | Format specifications and platform APIs | Key-based access without password |
| Implementation defects | Is there a reproducible, variant-specific flaw in a legacy implementation? | Public technical analysis and safe test fixtures | Narrowly scoped finding, not universal bypass |
| Modern cryptographic limits | What remains impossible without the secret? | Algorithm/KDF parameters and entropy assumptions | Clear refusal to promise decryption |

**Research rule:** Never describe GPU acceleration, AI, quantum computing or generic “advanced recovery” as a way around sound AES encryption. They may improve *candidate prioritization* or *testing throughput*, but do not remove the need for a correct key or exploitable weakness.

## 9. Feasibility and estimation

Candidate-search time depends on `candidate_count / measured_attempts_per_second`. Report best/worst-case bounds and acknowledge that the actual password may not be in the search space.

Illustration only: a six-digit numeric space contains 1,000,000 candidates. At an **example measured** 250 candidates/second, exhaustive testing would take approximately 67 minutes; the rate is **not** a universal 7z/RAR/ZIP benchmark. A uniformly random 16-character password drawn from a large alphabet is generally not a realistic target for exhaustive search.

A progress bar may show the fraction of a **defined search plan** completed. It must not claim “80% likely to recover” without a validated probability model.

## 10. Security, authorization and privacy requirements

1. Recovery is opt-in and local by default. Never upload ciphertext, password hints, candidates or recovered content without separate explicit consent.
2. No secrets in argv, environment variables where avoidable, URLs, ordinary logs, crash reports or analytics. Prefer a protected descriptor/pipe or equivalent OS credential channel.
3. Never auto-test a user's unrelated saved passwords against arbitrary files; credential lookup and candidate generation require clear authorization and scope.
4. Securely handle candidate buffers, minimize memory lifetime, and avoid persistent plaintext password caches. OS memory limitations mean zeroization is best-effort, not an absolute guarantee.
5. Enforce CPU, memory, disk, time, temperature/battery and concurrency limits; support immediate cancellation and predictable cleanup.
6. Run untrusted parsers and external verification tools under least privilege; validate binaries, licenses and supply chain.
7. Never confuse a recovered password with an authenticated complete extraction. Apply the common safe-output and verification pipeline.
8. Provide truthful outcomes: `recovered`, `credential_found`, `alternate_copy_found`, `search_exhausted`, `budget_reached`, `unsupported`, `corrupt`, `missing_volume`, `cancelled`.
9. Do not bypass operating-system access controls, enterprise authorization or DRM restrictions as a side effect of archive handling.

## 11. Implementation phases and acceptance criteria

### Phase A — Baseline protected extraction (P0)

- Identify supported encrypted ZIP, RAR and 7z variants and their metadata visibility.
- Implement password prompt and protected secret transport; remove any plaintext `-p` argument usage.
- Verify supplied passwords and perform safe, transactional extraction.
- Handle wrong passwords, encrypted headers, multipart sets and damaged payloads distinctly.
- Add format-specific positive/negative fixtures, redaction tests and UI tests.

**Exit:** known-password encrypted archives in the qualified fixture matrix unlock and extract correctly; secrets never enter process arguments or logs.

### Phase B — Recovery assistant (P1)

- User-authorized saved-credential retrieval.
- Guided hints, bounded candidate generation, dictionary/mask verification.
- Actual-rate benchmarks and feasibility presentation.
- Opt-in alternate-copy discovery; cancellation and redacted receipts.

**Exit:** representative forgotten-password fixtures can be recovered when their passwords lie in the selected bounded search, and unrealistic searches are accurately explained.

### Phase C — Specialized recovery (P2)

- Reviewed legacy ZIP-specific analysis where technically justified.
- Optional GPU acceleration after correctness and throughput benchmarks.
- Encrypted PDF/Office/disk-image adapters and recovery-key workflows.
- Resumable nonsecret search checkpoints, power-aware scheduling.

**Exit:** each additional technique is documented with supported variants, evidence, performance and failure modes; no unsupported broad recovery claims.

## 12. Test and evidence matrix

For each format/encryption variant: correct password, incorrect password, empty password, non-ASCII password, encrypted metadata, corrupt ciphertext, truncated input, missing multipart volume, malicious paths, extraction bomb, cancellation, crash/restart and secret-leak tests. For recovery: known candidate present, absent, candidate verifier false-positive resistance, budget expiry, duplicate candidates, checkpoint restart, and no logging of hints/secrets. Keep corpus provenance and redistribution rights recorded.

## 13. Decisions to pin

- Initial supported encrypted variants (not just file extensions).
- Credential-store integration and explicit authorization UX.
- Recovery defaults: time limit, concurrency, power/battery policy and opt-in persistence.
- Whether candidate testing runs in a separate sandboxed worker (recommended: yes).
- Definition of a verified password for each encryption variant.
- Which specialized legacy recovery methods merit implementation and maintenance.
- How to message irrecoverable modern encryption without overstating certainty.

## 14. Immediate next research deliverable

Produce a **Strong Encryption Recovery Feasibility Matrix** for WinZip AES, 7z AES-256, RAR3, RAR5, encrypted DMG, modern Office and encrypted disk volumes. For each, document key derivation, authentication/password-check method, metadata leakage, availability of alternate keys or recovery mechanisms, realistic benchmark methodology, and whether a publicly documented format-specific weakness exists. Distinguish **password guessing**, **key retrieval**, **plaintext restoration**, and **actual cryptographic compromise**. The first three can be viable even when the fourth is not.
