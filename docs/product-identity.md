# Peel — Unified Product Identity, Finder Experience & Pro Recovery

**Version:** 0.1.0  
**Date:** 2026-10-10  
**Status:** Product decision and implementation proposal; not a shipped-capability claim  
**Publisher:** [Snack Studio](https://snackstud.io)  
**Companions:** `specification.md`, `finder-quicklook.md`, `containers.md`, `encryption.md`, `competitive.md`

## 1. Product decision: one Peel

**Peel is one product, one brand, and one integrated experience.** Do not create separate branded Extract, Explore, or Protect applications or sub-products. Extraction, compression, browsing, preview, encryption, inspection, and authorized recovery are capabilities of the same application and Rust engine. The positioning remains **Peel — Open what's inside.**

The product promise is to make supported archives and other structured containers understandable and useful with minimal friction, ideally within the operating system's existing file interface. The everyday workflow must remain excellent without purchase.

**Brand and UX invariants:** one application icon, one name, one settings system, one capability registry, one navigation model, one job/receipt system. Pro is an entitlement within Peel, not a separate app or visual identity. No separate launchers or artificial mode switching. Avoid upsells during routine extraction, ordinary password unlocking, or standard encryption creation.

## 2. Core free experience

Free Peel includes all normal archive functionality where the format and implementation are qualified:

- Detect, list, extract, selectively extract, verify, create and compress supported formats; inspect nested and semantic containers as supported.
- Open password-protected archives when the user already has a valid password; prompt securely.
- Create password-protected archives using supported modern encryption. **Do not paywall baseline security.**
- Inspect encryption type, metadata visibility, integrity/authentication properties and documented legacy weaknesses, with appropriately qualified findings.
- Recommend stronger protection and explain limitations; normal authorized decrypt-and-re-encrypt/migration should not be artificially restricted.
- Preview archive structure with Finder Quick Look, open individual entries on demand, and use the native Peel browser.
- Optional Finder folder browsing through a qualified read-only filesystem bridge, if and when shipped; it is not a prerequisite for the free product.
- Clear failures, resource budgets, cancellation, safe staging, and operation receipts.

Free capability does not mean every proposed format is currently implemented. Publish support by exact format variant, operation, and platform.

## 3. Peel Pro: specialized forgotten-access recovery

**Pro value proposition:** help users recover access to their own encrypted archives when normal unlocking fails, using evidence-based, authorized, local-first recovery methods. It is **not** a universal decryption service, a promise to break AES, or a paywall on ordinary password entry.

Candidate Pro features, subject to engineering qualification:

1. Guided recovery interview and password-memory reconstruction (user-supplied clues, candidate patterns and bounded rules).
2. Consent-based discovery of existing credentials and recovery keys through permitted OS/key-management integrations.
3. Format-specific, budgeted local candidate testing, resumable checkpoints that do not persist secrets, and measured feasibility estimates.
4. Optional CPU/GPU acceleration where independently benchmarked and worthwhile; never imply acceleration changes the security of a high-entropy key.
5. Narrow, published, variant-specific legacy cryptanalysis only when prerequisites and verification are demonstrated.
6. Advanced diagnostics: method eligibility, time/energy/disk estimates, evidence provenance, confidence boundaries and recovery receipts.
7. Authorized alternative-copy discovery as part of recovery, with explicit scope and identity checks.

**Free preflight before payment:** identify encryption variant, explain what is and is not known, discover whether a plausible recovery path exists without exposing private information, and show realistic feasibility ranges. A paid entitlement should never be required merely to learn that recovery is infeasible.

**Success semantics:** distinguish (a) found saved key, (b) user-provided candidate succeeded, (c) recovered password by search, (d) exploited a proven legacy weakness, and (e) located another plaintext copy. Never label weak passwords as broken AES. Modern correctly implemented AES with a strong random password generally has no practical generic bypass.

## 4. Capability and entitlement matrix

| Capability | Free Peel | Peel Pro |
|---|---|---|
| Ordinary extraction, creation, browsing and selective extraction | Yes | Yes |
| Finder Quick Look and qualified optional Finder mounts | Yes | Yes |
| Open encrypted archive with known password | Yes | Yes |
| Create encrypted archive with strong supported encryption | Yes | Yes |
| Inspect protection and flag legacy weaknesses | Yes | Yes |
| Show recovery feasibility and honest limitations | Yes | Yes |
| Routine migration to stronger encryption with valid access | Yes | Yes |
| Guided forgotten-password reconstruction | No | Yes |
| Extended bounded candidate testing / resumable recovery | No | Yes |
| Specialized legacy cryptanalysis (where proven) | No | Yes |
| Advanced recovery acceleration and diagnostics | No | Yes |

Pro includes all Free functionality. Features in this matrix are **product targets**, not evidence of existing implementations. Optional future cloud compute, if offered, requires explicit opt-in, a separate privacy/security review, and transparent pricing.

## 5. Integrated user journeys

### A. Ordinary archive

Select an archive in Finder → Space previews its structure → optionally open one item or extract selected entries → no purchase prompts. Double-click preserves the user's configured extract/open preference. A read-only Finder mount is offered only where its backend is installed and qualified.

### B. Encrypted archive, known password

Peel identifies the precise encryption variant → requests password securely → validates access → previews/opens/extracts as permitted → offers a protection assessment and optional verified migration. Entire flow remains free.

### C. Encrypted archive, forgotten password

Peel identifies variant and KDF → free preflight explains feasible routes and estimated cost → user selects **Forgot Password** → optional Pro purchase only if user chooses advanced recovery → obtains explicit authorization and budget → attempts eligible routes → independently verifies result → offers non-destructive migration to modern protection. Failure reports state what was tried and what remains unknown; no guaranteed-success copy.

### D. Weak legacy protection

Peel detects legacy ZipCrypto → shows **Upgrade recommended**, not unqualified **Broken** → if access is available, offers secure migration; if not, explains whether a specialized Pro recovery method is eligible. Only display **demonstrated recoverability** after a method succeeds on that archive and is verified.

### E. Archive as Finder folder

Quick Look is the first native Finder surface; opening one entry materializes only the necessary content when feasible. Optional PeelFS exposes a read-only mounted folder through a separately qualified filesystem backend. Mounted files are not silently editable; explicit save-back/repack is a future workflow. Files opened in external apps can leave plaintext copies or autosaves outside Peel's control.

## 6. Architecture and separation of concerns

```text
macOS Finder / Quick Look / SwiftUI Peel / CLI / SDK
                     |
             Peel Operation API
                     |
          Container Resolver + Graph
                     |
        Read / Materialization / Cache
                     |
      Format adapters + policy executor
                     |
          Verification and receipts
                     |
      Protection inspection (Free)
                     |
        Recovery planner (Pro-gated)
                     |
  Credential broker / candidate verifier /
  optional accelerators / legacy adapters
```

Entitlements gate **advanced recovery operations**, not format parsers, basic decrypt, password entry, security advice, or creation of encrypted archives. Entitlement checks occur at the service operation boundary, with versioned machine-readable capability descriptions and clear offline behavior. Do not fork Free and Pro engines or duplicate Quick Look parsers. Protect secrets from argv, logs, caches, telemetry, receipts and crash reports. Local-first operation is the default.

## 7. Commercial model (hypothesis, not decision)

- **Free:** fully useful everyday application, no extraction quotas or deliberate weakening of encryption.
- **Pro:** initial pricing hypothesis **US$29–49 one-time**, subject to competitive research, willingness-to-pay tests, support burden, platform-store fees and recovery economics.
- Prefer one-time licensing initially over a subscription for an occasional recovery need. Define update policy, device activation, offline licensing, refunds, and cross-platform entitlement before launch.
- If costly remote computation is ever introduced, evaluate separately; do not bundle opaque usage promises into a one-time license.
- Purchase copy must explain that Pro purchases recovery *capabilities*, **not a successful unlock guarantee**. Respect privacy and user authorization.

## 8. Conversion and UI guidelines

**Entry:** `Forgot Password` is discoverable beside the normal password prompt, not a modal advertisement.

**Free preflight:** show exact variant, supported recovery routes, uncertainty, expected time/resource range and when recovery is implausible.

**Pro offer:** describe eligible advanced methods for the *specific archive* and their limitations. Avoid urgency, fake probability scores, or claims that Peel can defeat modern encryption.

**Recovery results:** separate method attempted, result, verified access, provenance, elapsed work and migration recommendation. Never display a green `secure` badge based solely on AES-256 or a red `broken` badge based solely on a legacy format label.

**Security migration:** safe, independently verified, non-destructive output; do not delete original until explicit user decision. Warn of metadata/signature/compatibility losses. Standard encryption creation and ordinary migration remain free.

## 9. Delivery order and dependencies

| Stage | Work | Release gate |
|---|---|---|
| 0 — Safety | Fix password argv leakage, misleading list/test, decompression budgets, commit safety and cancellation | Adversarial and fault-injection tests |
| 1 — Everyday Peel | Archive browser, selective access, encrypted unlock, modern encrypted creation, Quick Look ZIP | Reproducible format/OS fixtures |
| 2 — Finder polish | Entry opening, safe cache, extended preview variants; optional read-only PeelFS prototype | Bounded reads, mount lifecycle, Finder compatibility |
| 3 — Free protection audit | Variant/KDF/metadata inspection, accurate findings, free feasibility preflight, safe migration | Version-specific evidence and round-trip verification |
| 4 — Pro recovery | Guided candidate reconstruction, consent-based key discovery, bounded recovery engine, checkpoints, receipts | No secret leaks; benchmarked and truthful estimates |
| 5 — Specialized recovery | Qualified legacy methods, optional acceleration, further format coverage | Reproducible proof on exact variants; measured utility |

Stages may overlap, but security gates are mandatory. The optional filesystem bridge must not block Quick Look or the native browser. Recovery licensing must not block known-password extraction.

## 10. Proposed tickets

- **PRD-001 (P0):** Enforce one-product brand, shared capabilities, and no separate Extract/Explore/Protect products.
- **PRD-002 (P0):** Define Free/Pro entitlement contract at recovery-operation boundary; prevent gating ordinary encryption/decryption.
- **PRD-003 (P1):** Build `Forgot Password` free feasibility assessment with qualified variant detection and honest estimates.
- **PRD-004 (P1):** Implement Pro recovery authorization, budgets, candidate sources, verified results and resumable operation receipts.
- **PRD-005 (P1):** Provide safe migration and round-trip verification for supported output formats, available without Pro when access is known.
- **PRD-006 (P1):** Integrate Quick Look and entry-open flows without upsell interruption.
- **PRD-007 (P2):** Evaluate Pro one-time pricing, licensing, purchase/refund policy and offline behavior through research.
- **PRD-008 (P2):** Pro legacy attack adapters only with variant-specific fixtures and evidence ledger.

## 11. Acceptance criteria

1. All ordinary supported extraction and known-password unlocking flows work in Free without artificial limits or Pro prompts.
2. Users can create strong encrypted archives and see truthful protection findings in Free.
3. Free preflight can explicitly return `no practical recovery route identified`; it never implies that payment improves mathematical feasibility.
4. Pro-only operations require explicit user authorization, bounded local budgets, truthful progress, cancellation and independently verified outcomes.
5. A single Rust capability registry powers UI, CLI, Quick Look and optional Finder filesystem bridge; entitlements are separately represented.
6. No format-wide `broken` or `secure` claim is emitted without scoped evidence; no secret material appears in argv/logs/receipts.
7. Finder Quick Look remains free; optional mounting is read-only and independently qualified.
8. No destructive source replacement or deletion during encryption migration; output verified before presenting success.

## 12. Open decisions

- Exact Pro entitlement/licensing provider, offline activation and platform-store policy.
- Whether some low-cost guided recovery steps remain free or all active candidate testing is Pro-only; the **free feasibility assessment is fixed**.
- Precise format-by-format recovery methods and eligibility thresholds; requires research and fixtures.
- Which modern interoperable encrypted output profiles are qualified for creation/migration.
- Whether and when optional GPU acceleration materially improves user outcomes.
- Whether optional Finder mounts are feasible across targeted macOS versions and distribution channels.
- Pricing, upgrade policy, and whether recovery demand supports a one-time purchase.

**Decision summary:** One Peel. All normal archive and security fundamentals free. Specialized, evidence-based forgotten-access recovery is the proposed paid capability. Finder-native interaction remains a core product experience, not a premium add-on.
