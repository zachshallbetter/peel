# Peel — Strong Encryption Recovery: Research Survey and Engineering Agenda

**Version:** 0.1.0 | **Date:** 2026-10-10 | **Status:** Research and proposed design; not implementation-complete  
**Companion:** `PEEL_ENCRYPTION_AND_RECOVERY_ARCHITECTURE_v0.1.md`

## 1. Executive conclusion

There is no known general-purpose way to decrypt properly implemented modern AES-256 archive encryption without an appropriate key. The engineering opportunity is to maximize *legitimate recovery routes* rather than promise to defeat AES: find existing credentials or recovery keys; infer weak/partially remembered passwords; exploit demonstrably weak **legacy** constructions; restore plaintext copies; or use documented account/device recovery mechanisms. Specialized memory forensics and implementation-vulnerability research belong in a separate, high-friction forensic program, not the default consumer product.

**Three independent probabilities:** (1) probability a valid key or copy exists elsewhere; (2) probability the password lies in a tractable candidate distribution; (3) probability a *specific, verified* format/implementation weakness applies. None is equivalent to the AES key length.

## 2. Recovery taxonomy and feasibility

| Route | Prerequisites | Typical feasibility | Peel treatment |
|---|---|---|---|
| Saved password / OS credential | Previously stored secret; user grants access | High when present | Baseline, explicit authorization |
| Recovery key / escrow / additional keyslot | Original system provisioned one | High when present | Guided discovery and native integration |
| User-hinted candidate search | Words, years, patterns, partial memory | Variable, often best compute option | Baseline recovery engine |
| Wordlist / rules / probabilistic ranking | Human-generated password | Variable; no guarantee | Opt-in, local, bounded |
| Exhaustive constrained mask | Small search space | Quantifiable | Opt-in with measured cost |
| Full exhaustive search for random strong secret | Very large entropy | Impractical | Explicit no-go recommendation |
| Legacy cryptanalysis | Vulnerable cipher/construction and required conditions | Narrow, variant-specific | Separate evidence-gated adapter |
| Known plaintext / file structure | Specific vulnerable legacy scheme | Narrow; not an AES bypass | Research-only qualification |
| Previously extracted/plaintext copy | Accessible backup or cache | Often better than cracking | First-class restoration |
| Live unlocked session or authorized export | Data already unlocked on user's device | Potentially high | Native OS-mediated export; avoid invasive acquisition |
| Memory-forensic key acquisition | Specialized authorized forensic setting | Uncertain, platform-specific | Not default Peel; separate review |
| Hardware side channel/fault injection | Vulnerable target and lab conditions | Not a general consumer route | Out of scope |
| Quantum key search | Fault-tolerant quantum computing at enormous scale | Not practical today | No roadmap dependency |

## 3. Format-by-format analysis

### ZIP: Traditional PKWARE / ZipCrypto

Legacy stream-cipher construction is materially weaker than modern AES. Some known-plaintext scenarios can enable specialized cryptanalysis. Do not conflate recovering *decryption capability* with recovering the original password. Qualification must account for encrypted members, available known plaintext, compressed vs uncompressed known data, and archive integrity. **Opportunity:** a narrowly scoped legacy recovery adapter with published test fixtures and explicit applicability checks.

### ZIP: WinZip AES AE-1 / AE-2

Specification uses password-based derivation, salt, and authentication; the AE-1 and AE-2 variants differ in CRC treatment. No generic AES bypass. Password guessability, password reuse, or pre-existing credentials determine feasibility. Validate the entire file/authentication result; do not treat preliminary password-verification bytes as sufficient evidence. Metadata such as filenames may remain visible. **Opportunity:** precise variant detection, correct password checks, bounded candidate tests, secure extraction.

### 7z AES-256

7z uses AES-256 with SHA-256-based password derivation; iteration settings matter. Encrypted headers may hide filenames and prevent listing without the password. Solid archives affect extraction and validation costs. **Opportunity:** correct KDF parameter parsing, measured attempts/sec, explicit header-encryption status and a recovery benchmark per specimen.

### RAR3

Older RAR encryption is version-specific (including AES-based variants with modified SHA-1 derivation); it is not identical to RAR5. **Opportunity:** distinguish header/data encryption, legacy version, and relevant verification evidence; qualify candidate checking independently.

### RAR5

RAR5 specifies AES-256, PBKDF2, per-record salt and iteration parameters, and optional password-check data. Header encryption and multipart/solid layouts affect available evidence and performance. **Opportunity:** native parser of encryption descriptors and conservative credential verification; no promise of shortcut around strong KDF.

### PDF

Different security-handler revisions have substantially different cryptographic constructions. Distinguish an *open password* from an *owner/permissions password*. A document that opens without an open password is not the same as recovering a lost open password. **Opportunity:** precise revision and permissions identification, safe document recovery and copies, specialized candidate verification when supported.

### Microsoft Office

Legacy Office formats and modern Agile Encryption differ. Modern encrypted OOXML documents may use an outer OLE compound container rather than exposing ordinary ZIP members. **Opportunity:** encryption descriptor detection and document-specific verifier; preserve integrity checks.

### DMG and full-disk encryption

Encrypted DMG is a container-specific macOS problem. BitLocker, FileVault, and LUKS are **volume encryption systems**, not generic ZIP-style password prompts. Recovery keys, keyslots, organization escrow, keyfiles, and already-unlocked sessions are the primary avenues. For BitLocker, Microsoft documents account, organizational, USB and printed recovery-key locations. Do not claim that the volume password can be recovered by mounting an image without an authorized key.

## 4. Modern research directions

### 4.1 Candidate prioritization, not magical decryption

Research into probabilistic context-free grammars, Markov models, neural password models and LLM-based candidate ranking can improve the *ordering* of password guesses. The 2025 USENIX Security paper **Password Guessing Using Large Language Models** (Zou, An, Wang) studies model adaptation and ranking across several guessing scenarios. Its reported results are dataset-dependent and do not establish that random strong passwords become recoverable. For Peel, measure **success@N**, median attempts-to-hit, candidate uniqueness, generation overhead, and recovery per joule on a consented synthetic/human-volunteer evaluation set. Avoid collecting leaked real-user passwords or personal information by default.

Research decision: start with simple user-hint rules, wordlists and probabilistic ranking; only add a local language model if it outperforms those baselines *at fixed verification budgets* and does not create privacy or model-supply-chain risk.

### 4.2 Key derivation and memory hardness

NIST SP 800-132 explains password-based derivation for stored data; RFC 9106 documents Argon2's memory-hard design and tradeoffs. **Important:** Peel must implement the target archive's actual KDF to unlock existing files; it cannot substitute Argon2 for a 7z or RAR KDF. Argon2 matters to evaluating the broader security literature and to designing any *new Peel-owned encrypted container*.

Model each attempt cost as `KDF + key-check + optional decode/authentication`. Optimize away repeated archive I/O and unnecessary decompression, but never omit final authentication. GPU acceleration is only useful when the KDF's structure, implementation, memory bandwidth and host/device overhead permit a real improvement. Benchmark representative hardware rather than claiming universal speedups.

### 4.3 Recovery-key systems and cryptographic key lifecycle

NIST SP 800-57 Part 1 describes recovery from backed-up key material and re-derivation from other available key material. This is a different class of recovery from password guessing. For Peel-created encrypted archives, consider **envelope encryption**: random content key; password-wrapped key; optionally separately wrapped recovery key; independently revocable or replaceable key slots. For *existing* ZIP/7z/RAR, Peel cannot retroactively add a recovery key without re-encrypting or migrating the archive while it is unlocked.

A future optional Peel vault could support explicit recovery-key export, OS secure storage and multi-device backup. Recovery design must also specify who can recover, consent, revocation, compromise impact and recovery-key rotation.

### 4.4 Plaintext restoration and provenance

A protected archive's contents may exist in backups, synchronized folders, exported projects, attachments, prior extractions or version history. With explicit scope, compare visible metadata, sizes, filenames, timestamps and hashes of *accessible* files. If names are encrypted, do not invent an index. Preserve provenance: an alternative copy may not be byte-for-byte identical to the protected archive's contents. Report `RESTORED_ALTERNATE_COPY`, never `DECRYPTED_ORIGINAL`.

### 4.5 Implementation weaknesses and legacy cryptanalysis

Evaluate only *documented, version-specific* weaknesses with reproducible fixtures. Maintain a registry: affected algorithm/version, necessary preconditions, source paper/advisory, reproducibility status, false-positive risks and security review. A generic 'try exploit' button is not defensible. Cryptanalytic shortcuts against a weak legacy scheme do not imply a break of AES-256 or PBKDF2.

### 4.6 Live keys, memory and forensics

Halderman et al., **Lest We Remember: Cold Boot Attacks on Encryption Keys** (USENIX Security 2008), demonstrated key material recoverability from DRAM in particular historical physical-access scenarios. This is important security research, but it is not a reliable recovery method for modern Apple silicon, TPM-backed workflows or an ordinary unopened archive. Peel's consumer path should use OS-approved access to already-unlocked files and documented key stores; invasive memory acquisition or hardware attacks are out of scope without a separate forensic, legal and platform-specific program.

### 4.7 Quantum considerations

Grover-style theoretical search does not provide a practical current method to recover AES-256 archive keys. Realistic resource requirements and password-derived key entropy dominate. Do not market 'quantum recovery'. If future research changes that assessment, require peer-reviewed, reproducible evidence and concrete cost estimates.

## 5. Feasibility estimator

For a bounded candidate set of size `N` and measured verification rate `r` candidates/sec, a full scan takes approximately `N/r` seconds, excluding setup and variability. A probabilistically ranked search needs an empirical probability-of-hit curve, not just a candidate count. For uniform random passwords, estimate entropy from the actual alphabet and length assumptions; never infer entropy from AES-256 key size alone.

Output should include: archive format/variant, encryption/KDF parameters, available recovery routes, verified candidate rate with hardware details, search space, expected energy/disk implications, user-set time budget, and confidence level. Separate **estimated cost** from **chance of success**. Stop early when posterior likelihood and expected benefit become negligible; allow the user to override within explicit resource bounds.

## 6. Architecture proposal

```text
Protected File -> Encryption/Variant Probe -> Recovery Route Planner
                                            |-> Credential / key discovery (consented)
                                            |-> Recovery-key / keyslot guidance
                                            |-> Accessible-copy discovery (consented)
                                            |-> Candidate generator / ranker
                                                      |
                                               Budgeted verifier
                                                      |
                                               Validated credential
                                                      |
                                         Existing safe extraction pipeline

Every path -> evidence-backed outcome and redacted receipt
```

Recommended interfaces:

- `ProtectionDescriptor`: exact variant, KDF and parameters, header visibility, keyslot/recovery-key possibilities, verification capabilities.
- `RecoveryRoute`: required permissions, expected resource cost, evidence strength, privacy implications, supported platforms.
- `CandidateSource`: hint rules, user wordlist, bounded mask, optional probabilistic ranker; streaming, deduplicated, reproducible.
- `CredentialVerifier`: constant-work where possible, format-specific quick rejection and full authenticated confirmation; typed false-positive/inconclusive outcomes.
- `RecoveryBudget`: maximum attempts, time, CPU/GPU share, energy preference, thermal constraints, cancellation.
- `RecoveryReceipt`: source fingerprint, format variant, route, attempts, measured throughput, terminal outcome, verification confidence; **no secret material**.

Secure process communication is mandatory: no passwords in argv, logs, telemetry, analytics, or persisted job JSON. Memory-zeroization is best effort and cannot substitute for process isolation. Keep recovery local by default. No remote cracking service in the baseline.

## 7. Research evaluation protocol

1. Construct **synthetic fixtures** with known passwords for every encryption variant; include weak, medium and random strong secrets, corruption, multipart, encrypted headers, and missing volumes.
2. Validate detection and correct unlocking before recovery benchmarking. Include incorrect-password and damaged-data cases.
3. Measure CPU-only reference verifier across Apple silicon, x86-64 and representative Windows/Linux hardware. Record KDF settings and thermal throttling.
4. Compare candidate strategies at identical attempt and wall-time budgets: naive mask, user-hint rules, dictionaries, probabilistic model, optional local LLM.
5. Evaluate hit rate, attempts-to-hit, time, power, RAM, false positives, privacy footprint and reproducibility; publish negative results.
6. Test pause/resume without storing secrets, and cancellation with zero unexpected archive writes.
7. Require security review before shipping any legacy cryptanalysis adapter; keep it disabled when applicability is uncertain.
8. Report each format variant as `recognized`, `unlock_qualified`, `recovery_qualified`, or `unsupported`; no generic 'encrypted files supported' claim.

## 8. Priority and decision gates

| Phase | Deliverable | Gate |
|---|---|---|
| P0 | Secure password input, variant detection, correct known-password extraction | No argv secrets; full auth/CRC validation |
| P1a | OS credential and documented recovery-key guidance | Explicit authorization; no broad secret enumeration |
| P1b | Local candidate engine, user hints, masks and cost estimator | Measured speed, bounded jobs, realistic outcomes |
| P1c | Alternative-copy restoration | Scoped access and provenance receipts |
| P2a | Format-specific legacy weakness qualification | Peer-reviewed or authoritative technical evidence, test fixtures |
| P2b | Candidate ranking experiments (PCFG/Markov/LLM) | Better success@N than simple baseline on consented test data |
| P2c | Optional GPU verification | Real end-to-end speed/energy benefit on target hardware |
| P3 | Peel-owned recoverable encrypted container design | Explicit key lifecycle, threat model and recovery governance |

**No-go:** universal AES bypass claims; remote upload by default; speculative quantum recovery; brute-force jobs with no realistic bound; storing recovered passwords without consent; memory-forensic acquisition in the standard consumer UI.

## 9. Primary sources and papers

1. NIST, **SP 800-132: Recommendation for Password-Based Key Derivation, Part 1** (2010). https://csrc.nist.gov/pubs/sp/800/132/final
2. IRTF CFRG, **RFC 9106: Argon2 Memory-Hard Function** (2021), including tradeoff analysis and test vectors. https://www.rfc-editor.org/info/rfc9106/
3. Biryukov, Dinu, Khovratovich, **Argon2: New Generation of Memory-Hard Functions for Password Hashing and Other Applications** (Euro S&P 2016). https://orbilu.uni.lu/handle/10993/31652
4. WinZip, **AES Encryption Specification AE-1 and AE-2**, v1.04 (2009). https://www.winzip.com/en/support/aes-encryption/
5. RARLAB, **RAR 5.0 Archive Format Technical Note**, encryption header and KDF specification. https://www.rarlab.com/technote.htm
6. 7-Zip, **7z Format / AES Encryption** (project documentation mirrored in Debian source). https://sources.debian.org/src/p7zip/16.02%2Bdfsg-8/DOC/MANUAL/general/7z.htm
7. 7-Zip project, **Methods.txt**, archive encryption identifiers and variants. https://github.com/ip7z/7zip/blob/main/DOC/Methods.txt
8. Zou, An, Wang, **Password Guessing Using Large Language Models** (USENIX Security 2025). https://www.usenix.org/conference/usenixsecurity25/presentation/zou-yunkai
9. Halderman et al., **Lest We Remember: Cold Boot Attacks on Encryption Keys** (USENIX Security 2008). https://www.usenix.org/conference/17th-usenix-security-symposium/lest-we-remember-cold-boot-attacks-encryption-keys
10. NIST, **SP 800-57 Part 1 Rev. 5: Recommendation for Key Management** (2020), especially key recovery. https://nvlpubs.nist.gov/nistpubs/specialpublications/nist.sp.800-57pt1r5.pdf
11. Microsoft, **Find Your BitLocker Recovery Key**, current support documentation. https://support.microsoft.com/en-us/windows/security/encryption/find-your-bitlocker-recovery-key
12. Microsoft Learn, **BitLocker Recovery Overview**, account/enterprise escrow mechanisms. https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/recovery-overview
13. NIST, **Post-Quantum Cryptography FAQ**, symmetric algorithm context. https://csrc.nist.gov/Projects/Post-Quantum-Cryptography/faqs

## 10. Open research questions

- Which archive variants are most frequent in Peel's real-world corpus, and how often are passwords human-generated?
- Can a common verifier API safely use a fast preliminary check while requiring full authentication before claiming success?
- What is the measured candidate throughput per format, KDF parameter and hardware target?
- Do probabilistic/LLM generators improve success under a *fixed* wall-clock and energy budget over user hints?
- Which OS credential and recovery-key sources offer a legitimate, narrow, auditable integration API?
- Can alternative-copy discovery deliver more recovered files per user-minute than compute-heavy guessing?
- What are the actual legal/licensing requirements for each legacy recovery algorithm or library?
- Which file formats support recovery-key slots that Peel can preserve during conversion or creation?

**Final product position:** Peel can make recovery intelligent, transparent and unusually effective for *recoverable circumstances*. It must also be able to say, with evidence, when the file cannot practically be opened without the missing secret.
