# Peel — protection audit, recovery, and verified migration

**Status:** Research and implementation plan. No claim of universal decryption or completed security audit.

## Core distinction

**Encryption weakness ≠ password weakness ≠ credential recovery ≠ implementation vulnerability ≠ metadata exposure.** ZIP ZipCrypto is legacy and has documented weaknesses under specific conditions. Modern WinZip AES, 7z AES-256, and RAR5 do **not** have a general bypass when correctly implemented with strong secrets. An old scheme alone is not proof a particular archive has been cracked.

## Product workflow

**Inspect → Explain → Unlock or Assess Recovery → Verify → Re-encrypt → Verify Again.**

Free: scheme/variant identification, header visibility and KDF analysis where available, clear recommendations, normal password prompt, known-password unlock, encrypted creation, and bounded recovery feasibility assessment. Pro: explicit opt-in guided forgotten-password reconstruction, authorized credential discovery, local bounded candidate checks, optional measured CPU/GPU acceleration, and separately reviewed legacy-specific techniques.

Show the user what has actually been demonstrated, with evidence and limitations. Never advertise “broken” solely because a format is old, or “secure” solely because AES-256 appears in a header. Do not guarantee recovery. Candidate-testing cost estimates must be measured against the exact archive variant and device, not guessed.

## Supported research paths (not blanket implementation promises)

- ZIP traditional/ZipCrypto: identify exact variant; narrow, documented legacy research when preconditions hold.
- WinZip AES AE-1/AE-2: distinguish password search, authentication, metadata exposure, and compatibility.
- 7z: account for encrypted headers, solid-block cost, KDF and non-seekable access.
- RAR3/RAR5: qualify variant-specific parsing and credential checks; do not promise RAR writing.
- OS-managed DMG/FileVault/BitLocker/LUKS: use authorized native recovery/key slots; do not treat them as generic ZIP migration.
- Credential sources: user-selected Keychain/password manager, recovery keys, original senders, and backups; explicit permission, no silent scanning.

## Secure design

Logical components: protection_probe, security_assessor, credential_broker, recovery_planner, candidate_verifier, optional legacy_research_adapters, migration_planner, secure_writer, audit_receipt. Keep recovery execution separately isolated from ordinary decoding and gate Pro at workflow level.

No secrets in argv/env/logs/telemetry; no default credential persistence; no unconsented cloud upload. Use per-job resource limits, cancellation, energy estimates, local-only defaults, and safe checkpoint handling. Recovered plaintext stays within protected temporary storage with deterministic cleanup.

Migration is **non-destructive**: unlock, extract to isolated staging, verify source content, create stronger encrypted output, independently read back and compare full manifest/payloads, produce receipt, and only then let the user choose what to do with the original. Explicitly report unsupported metadata, ACLs, xattrs, symlinks, timestamps, and signature impacts.

## Encryption creation profiles

- **Compatible:** supported interoperable ZIP AES with clearly stated metadata/privacy limitations.
- **Private:** established, audited authenticated-encryption profile with appropriate password KDF and metadata confidentiality; select an existing proven format before implementing.
- **Recoverable (future):** only for a designed Peel-managed container using a random content key wrapped separately by a password-derived key and optional independent recovery key. Requires format specification, threat model, interoperability, external review, and recovery-key backup UX. Do not imply standard ZIP/7z/RAR automatically support key wrapping.

## Validation

Fixtures for wrong passwords, Unicode passwords, encrypted headers, weak/strong controls, corruption, multipart loss, tampered ciphertext, KDF extremes, cancelled recovery, migration collision, disk full, cache leaks, and round-trip mismatch. Record method, source format/version, prerequisites, observed outcome, verification, and provenance. Compare success **at fixed compute/time budgets**. Security assertions must be evidence-pinned.
