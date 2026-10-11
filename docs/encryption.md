# Peel — Encryption Audit, Recovery and Repair

**Version:** 0.1.0 | **Date:** 2026-10-10 | **Status:** Research-backed product and engineering proposal

## 1. Product thesis

Peel should **identify protection, evaluate its security, recover access where feasible, and migrate archives to a stronger configuration**. The intended user experience is: **Inspect → Explain → Recover or Unlock → Verify → Protect → Verify Again**.

Do not equate successful recovery with a broken encryption algorithm. A password recovered because it was weak is evidence of a weak *password*, not necessarily weak AES. Conversely, authenticated encryption may be strong while archive metadata remains visible. Reports must distinguish confidentiality, authentication/integrity, password strength, metadata exposure, and recoverability.

Peel must never promise universal decryption of modern strong archives. It cannot repair an inaccessible archive without recovering a valid secret or finding another accessible plaintext copy.

## 2. Threat and failure taxonomy

| Finding | Meaning | Evidence | Remediation |
|---|---|---|---|
| No encryption | Contents are readable without a secret | Parsed entry flags and actual read test | Offer encryption |
| Legacy weak encryption | Scheme has documented weaknesses (e.g. traditional ZIP encryption) | Precise format/variant identification | Re-encrypt with modern authenticated protection |
| Weak/recovered password | Valid secret found through bounded candidate testing | Verified successful unlock; no secret in report | Replace with stronger unique passphrase |
| Strong cipher, weak KDF settings | Password verification may be cheaper than desired | Supported format-specific KDF parameters | Migrate to stronger supported format/configuration |
| Strong encryption, exposed filenames | Payload confidential; filenames may be visible | Header inspection without password | Use a format/profile that encrypts headers |
| Encryption without robust authentication | Tampering may not be reliably detected | Format-specific authenticated-integrity analysis | Use authenticated encryption |
| Damaged/corrupt archive | Data integrity or structure failure | Decoder/verification errors | Repair from parity/backup if available; do not claim cryptographic bypass |
| Missing multipart volume | Incomplete ciphertext or data | Volume resolver evidence | Locate missing volume; do not attempt partial destructive extraction |
| Secure modern encryption | No verified weakness; strong secret may be infeasible to guess | Cipher/KDF/metadata assessment | Preserve; offer recovery-key options for new archives |

## 3. Format feasibility matrix

| Format | Security questions | Plausible recovery routes | Repair strategy |
|---|---|---|---|
| ZIP traditional/ZipCrypto | Legacy cipher; integrity and metadata limitations | Saved password, remembered candidates, narrowly applicable published legacy cryptanalysis | Repackage as ZIP AES where interoperability requires it, or a stronger authenticated container |
| ZIP WinZip AES AE-1/AE-2 | AES strength, password quality, KDF cost, authentication semantics, filename exposure | Existing credential or password candidates; no general AES bypass | Change password by decrypt-and-re-encrypt; prefer authenticated format/profile with explicit metadata guarantees |
| PKWARE strong ZIP | Identify exact encryption profile; may involve certificate recipients | Private-key/credential recovery or documented recipient path | Preserve supported recipient access; migrate only after verifying compatibility |
| 7z AES-256 | KDF cost, encrypted headers option, integrity limitations | Password/key recovery or alternative plaintext; expensive candidate tests | Re-encrypt with unique strong passphrase; enable header encryption where supported |
| RAR3 | Legacy variant-specific construction and KDF | Credential recovery, candidates; only proven variant-specific weaknesses | Extract and recreate in modern format (do not promise in-place RAR rewrite) |
| RAR5 | Modern AES and KDF parameters | Credential/candidate recovery, accessible copy | Extract and recreate in preferred secure output format |
| PDF | Security handler revision, user/owner password semantics, permissions | Authorized password or document copy | Export/recreate under modern PDF security handler when supported |
| Office OOXML encrypted | Exact Agile/Standard scheme, KDF and document metadata | Authorized credential, candidates, backup | Open and save with current Office encryption profile |
| Encrypted DMG | macOS encryption variant and OS-mediated unlock | Keychain/authorized recovery credential | Create new encrypted image after unlocking |
| LUKS / BitLocker / FileVault | Keyslots, recovery keys, TPM/device binding | Official recovery keys and authorized OS unlock | Use native OS key rotation; do not treat as ordinary archive conversion |

**Caution:** The above is a research plan. Each row requires a versioned conformance fixture before any user-facing assertion about recoverability or security.

## 4. Recovery method evaluation

1. **Credential discovery:** user-authorized Keychain/password-manager integration, archive comments, sender documentation, local prior Peel records. Never scrape secrets silently.
2. **Recovery keys and recipient credentials:** use standard OS recovery and certificate paths where applicable. No bypass claims.
3. **Guided candidate search:** user-provided words, masks, dates and rules; bounded local testing with measured throughput and realistic search-space estimates.
4. **Legacy cryptanalysis:** evaluate published attacks only against exactly identified weak legacy constructions and their documented preconditions. An attack may recover a decryption capability without revealing the original password. Isolate this in a reviewed optional adapter, not the general AES engine.
5. **Alternative plaintext:** user-approved search of prior extracts, backups, cloud copies and sender originals; verify file identity before presenting results.
6. **Implementation-vulnerability research:** keep a separate evidence ledger with vendor, version, prerequisites, reproducibility, disclosure status and patch. Do not imply a generic format is vulnerable because one historical tool version was.
7. **Specialized forensics:** memory acquisition, side channels and physical attacks are not default consumer workflows. No support or success claim without a separate legal/security review and validated lab evidence.

## 5. What Peel should actually demonstrate

A defensible result card should read:

> **Protection assessment: Upgrade recommended**  
> ZIP legacy encryption detected. This archive uses an older protection method with known weaknesses. We have **not** demonstrated that this specific archive was decrypted without its password.  
> **Recommended action:** Unlock using an authorized method, then create a new encrypted archive with a strong unique password.

Or, when a bounded recovery succeeds:

> **Password recovered**  
> Peel verified one of the passwords you supplied or authorized Peel to test. The archive's encryption algorithm may still be sound; the password was recoverable within the selected search budget.  
> **Recommended action:** Re-encrypt using a new unique passphrase.

Or, for modern protection:

> **No practical recovery route identified**  
> Modern encryption detected. No saved key or accessible copy was found in the locations you approved. The password-search budget is unlikely to cover a strong random password. The archive remains protected.

Never display an unqualified badge reading “broken” merely because a format is old, or “secure” merely because AES-256 appears in a header.

## 6. Repair pipeline and invariants

```text
Source -> Detect/Inspect -> Security assessment -> Authorization
       -> Unlock or Recover -> Extract to isolated staging
       -> Verify source content -> Create new encrypted container
       -> Verify new container independently -> Present migration receipt
       -> User decides whether to retain/delete original
```

**Invariants:** original is never overwritten; no deletion on failed verification; secrets never in argv/logs; migration cannot silently omit entries or metadata; verification includes full payload checks and round-trip manifest comparison; unsupported metadata and filename changes are disclosed. Use independent readers for cross-tool interoperability checks where feasible.

**Re-encryption is not necessarily in-place.** For ZIP, 7z and RAR migration may require extraction and full recompression. Preserve file attributes where supported, with explicit warnings for ACLs, links, timestamps, resource forks and unsupported metadata.

## 7. Creation profiles

**Compatible:** ZIP AES-256 for broad interchange, with explicit warning that ZIP metadata/header privacy and authentication semantics depend on profile and implementation.

**Private:** An interoperable, audited authenticated-encryption container profile (or a well-supported established tool/format) with strong password KDF, full metadata confidentiality where supported, and independently verifiable authentication. Do not invent a cryptographic primitive or market a bespoke format as audited.

**Recoverable:** For newly created Peel-managed containers, use a random content-encryption key wrapped by separate credentials: passphrase-derived wrapping key and an optional recovery key/recipient. This enables password rotation without re-encrypting all payload bytes **if the chosen container format supports key wrapping**. ZIP/7z/RAR compatibility profiles generally cannot be assumed to support this design. Document how users back up the recovery key; Peel must not secretly escrow it.

For a new profile, use established authenticated encryption, a vetted memory-hard password KDF such as Argon2id, cryptographically secure randomness, per-container salts, unique nonces, authenticated metadata, explicit format/version headers and a documented migration path. Parameter choices require benchmarking, threat modeling and expert review.

## 8. Architecture modules

- `protection_probe`: precise cipher, KDF, encryption scope, authentication and metadata exposure.
- `security_assessor`: evidence-based findings, severity and caveats; never infer password strength from encryption flags alone.
- `credential_broker`: OS-backed, permissioned secret retrieval and secure helper IPC.
- `recovery_planner`: feasible routes, time/resource budgets, user consent and checkpoints without secrets.
- `candidate_verifier`: format-specific, bounded password checks and definitive unlock confirmation.
- `legacy_research_adapters`: gated and version-specific methods with reproducible fixtures.
- `migration_planner`: output format, metadata losses, compatibility and disk-space estimate.
- `secure_writer`: encrypted output, integrity verification, atomic commit and receipt.
- `audit_receipt`: source evidence, actions, outcome, limitations and verified destination hash; no password material.

## 9. Validation and research protocol

Build synthetic, self-owned test fixtures for each format/variant, covering: no encryption, weak/strong passwords, encrypted filenames, corruption, multipart loss, tampered ciphertext, metadata disclosure, KDF extremes, non-ASCII passwords, wrong-password errors, cancellation, and source/destination collision.

Measure recovery probability **at fixed time/energy budgets**, not guesses per second alone. Separate weak-human-password fixtures from high-entropy random controls. Measure migration interoperability and full-content equality. Security findings must include provenance and version applicability.

A result is **proven** only when the exact format variant, test fixture, method, observed outcome and independent verification are recorded. A literature claim is **research-backed**, not a demonstrated exploit in Peel.

## 10. Delivery phases

**Phase A — Honest protection audit:** format signatures, encryption scheme, KDF/metadata assessment, typed evidence and UI findings. Fix existing argv secret exposure and false-positive `test` semantics first.

**Phase B — Reliable unlock and migration:** password prompts, protected IPC, full verification, output creation, round-trip checking and non-destructive migration.

**Phase C — Forgotten-password assistance:** credential discovery, user-hinted candidate search, bounded local recovery, alternative-copy discovery and feasibility estimates.

**Phase D — Legacy research:** reproducible and narrowly scoped weak-format methods, security reviews and explicit claims. Avoid implementing speculative AES bypasses.

**Phase E — Recoverable new container:** only after a format and threat-model decision, external cryptographic review, and interoperability testing.

## Finder and Quick Look handling of encrypted containers

Quick Look must show a locked state when filenames/headers cannot be listed without credentials. Unlock requests go through the credential broker and secure helper IPC, never command-line arguments or cached secrets. The optional read-only Finder mount must not persist passwords; any decrypted cache requires scoped permissions, bounded lifetime and explicit cleanup. Opening an item in an external application may create plaintext copies outside Peel's control. Password recovery is a separate opt-in operation, not an automatic side effect of Finder browsing. See `finder-quicklook.md`.


## 11. Primary references and verification starting points

1. WinZip, **AES Encryption Specification AE-1 / AE-2**, https://www.winzip.com/en/support/aes-encryption/ — interoperability and authentication semantics.
2. PKWARE, **APPNOTE ZIP File Format Specification**, https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT — ZIP encryption variants and headers.
3. 7-Zip, **7z Format Description**, https://github.com/ip7z/7zip/blob/main/DOC/7zFormat.txt — 7z structural parsing.
4. 7-Zip, **AES encryption documentation**, https://sources.debian.org/src/p7zip/16.02+dfsg-8/DOC/MANUAL/general/7z.htm — KDF context.
5. NIST, **SP 800-132 Password-Based Key Derivation**, https://csrc.nist.gov/pubs/sp/800/132/final — password-derived keys.
6. NIST, **SP 800-38D GCM/GMAC**, https://csrc.nist.gov/pubs/sp/800/38/d/final — authenticated encryption requirements.
7. IETF, **RFC 9106 Argon2**, https://www.rfc-editor.org/rfc/rfc9106 — memory-hard password hashing/KDF design.
8. IETF, **RFC 8439 ChaCha20-Poly1305**, https://www.rfc-editor.org/rfc/rfc8439 — established AEAD alternative.
9. NIST, **SP 800-57 Part 1 Rev. 5**, https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final — key lifecycle and recovery principles.
10. Previous companion: `PEEL_STRONG_ENCRYPTION_RECOVERY_RESEARCH_v0.1.md` — broader papers and investigation backlog.

**Research boundary:** this document describes recovery and migration mechanisms for user-authorized files. It is not evidence that modern AES-encrypted archives can generally be opened without valid keys, nor that Peel has implemented the proposed components.

## Commercial boundary: Free security, Pro forgotten-access recovery

Free Peel provides secure known-password unlock, creation of modern encrypted archives, protection assessment, truthful legacy-weakness findings, safe migration when access exists, and a free recovery-feasibility preflight. Peel Pro may gate guided forgotten-password reconstruction, extended bounded candidate testing, qualified legacy cryptanalysis, acceleration and advanced recovery diagnostics. Never gate baseline encryption strength, imply AES bypass, or guarantee recovery on purchase. One app and one engine; entitlement checks live at the advanced recovery operation boundary. See `PEEL_PRODUCT_IDENTITY_AND_MONETIZATION_v0.1.md`.
