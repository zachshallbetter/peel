# Agent operating contract — Peel

This file is authoritative for agents working in this repository. Read [README.md](README.md), [docs/status-and-roadmap.md](docs/status-and-roadmap.md), [docs/architecture.md](docs/architecture.md), [docs/finder-integration.md](docs/finder-integration.md), and [docs/encryption-and-recovery.md](docs/encryption-and-recovery.md) before changing behavior.

## Mission and authority

Peel is **one product** with free everyday features and an optional paid advanced-recovery entitlement. Do not invent separate product identities. Treat proposed docs as **requirements**, not evidence of implementation. Do not claim a build, test, deployment, security audit, or feature works unless you actually executed and recorded it.

Work in bounded, reviewable changes. Preserve existing user-facing behavior unless a ticket and acceptance tests authorize a change. Do not merge or deploy without required project authority. Prefer PRs with exact test receipts. Do not close issues on design alone.

## Tool and repository orientation

- Rust: `crates/peel-core` (format operations/policy), `crates/peel-cli` (CLI), `crates/peel-ffi` (interop). Confirm actual paths before editing.
- macOS: `app/Peel` (SwiftUI), `swift/PeelKit` (bridge); inspect Xcode project, entitlements, signing, extensions before changes.
- Scripts: `scripts/build-app.sh`, `scripts/install-app.sh`, `scripts/install-finder-service.sh` if present; installation mutates the host.
- Suggested baseline: `cargo test -p peel-core`, `cargo build -p peel-cli --release`, `./scripts/build-app.sh`. Run only in a suitable environment and report skipped checks.
- GitHub: inspect current issues/PRs and branches before creating duplicates; link related work and evidence. Do not assume the local checkout matches main.
- Optional Reflective Rust research: capability-shaped JSON may be useful, but **do not add a hard dependency** without a compatibility and licensing decision.

## Non-negotiable engineering rules

1. **Security first:** no secrets in process arguments, environment, logs, telemetry, crash reports, or issue fixtures. Use reviewed protected IPC/FD or OS credential channels.
2. **Never trust archive names or metadata:** validate traversal, links, case/Unicode collisions, sizes, companion paths, and filesystem boundaries.
3. **Budget during execution:** expanded bytes, CPU/wall time, memory, temporary disk, entry count, nested depth, and cumulative reads.
4. **Honest outcomes:** listing is not verification; no synthetic success entries, fake progress, or unqualified support badges.
5. **Source safety:** read-only inspection; staged writes, collision policy, explicit metadata loss, independently verified migration, and deterministic cleanup.
6. **Finder integration:** Quick Look ≠ virtual Finder directory; evaluate actual Apple APIs, signing, sandbox, and optional mount backend before implementation.
7. **Encryption:** never imply a general AES bypass; distinguish weak legacy cipher, weak password, implementation flaw, and missing credential. Free unlock remains free.
8. **Portable core:** OS-specific mounting/Keychain/Finder behavior stays outside portable Rust core.
9. **No installer execution** during inspection. Do not silently mount untrusted images or enable writable virtual filesystems.
10. **Capability qualification:** track format × variant × operation × platform, with fixtures and exact backend versions.

## Agent workflow

1. Inspect branch, status, issues, docs, and relevant source; write a bounded plan and affected contracts.
2. Identify user-facing behavior, security boundary, feature entitlement, and expected failure modes.
3. Add or update fixtures/tests first where feasible; implement smallest viable vertical slice.
4. Run targeted tests and adversarial cases; capture commands, results, platform, and skipped checks.
5. Update README, capability matrix, architecture, and issue references **in the same PR** as behavioral changes.
6. Submit a PR describing scope, evidence, risks, rollbacks, and unresolved gaps. Do not silently promote roadmap items to qualified.
7. For multi-agent work, use explicit ownership of files/branches and preserve independent review; no agent self-approves release qualification.

## Ticket and PR template

**Problem / evidence**; **scope and non-goals**; **design / security boundaries**; **implementation slices**; **acceptance fixtures**; **observed test receipts**; **dependencies / related issues**; **rollback and release considerations**. Mark research hypotheses explicitly.

See [.agents/README.md](.agents/README.md) for task-specific agent responsibilities.
