# Peel agent guide

**Read [../AGENTS.md](../AGENTS.md) first.** This directory documents agent roles and tool-use expectations; it does not grant merge, deployment, signing, or security-promotion authority.

## Role map

| Role | Responsibility | Must not claim |
| --- | --- | --- |
| Product/spec agent | Single identity, free/Pro boundary, user journeys, docs | Feature implemented because it is specified |
| Rust/container agent | Resolver, graph, ByteSource, codecs, per-variant capabilities | Extension implies format support |
| Security/recovery agent | Threat model, secret transport, encryption audit, verified migration | Generic strong-encryption bypass or guaranteed recovery |
| macOS integration agent | SwiftUI, Quick Look, Finder actions, mount feasibility, signing | Finder Sync or Quick Look alone creates virtual folders |
| QA/conformance agent | Fixtures, fuzzing, lifecycle tests, measured receipts | Listing or smoke test proves full correctness |
| Release/documentation agent | Build matrix, entitlement/packaging, docs, issue references | Shipped/qualified without reproducible evidence |

## Shared tools and how to use them

- **Cargo/Rust:** `cargo test -p peel-core`; targeted package tests; `cargo build -p peel-cli --release`; use `cargo fmt --check` and `cargo clippy` when available.
- **Swift/Xcode:** inspect Xcode targets, extension entitlements, app groups, signing, sandbox and minimum macOS version; use `xcodebuild` only when the host supports it.
- **Filesystem/CLI:** inspect scripts before install, never pass passwords in shell arguments, avoid tests that execute unknown archive payloads.
- **Git/GitHub:** inspect issues and PRs, reference dependency issues, use topic branches and reviewable commits, record actual test output.
- **Fixtures:** own synthetic archives, corrupt and encrypted controls, multipart gaps, Unicode/case collisions, decompression bombs under hard resource limits; hash golden trees.
- **Evidence:** record date, commit SHA, OS, CPU, command, fixture, expected vs actual, and whether tests were run or skipped.

## Work packages and dependencies

**Gate 0:** source/build inventory and P0 security remediation. **Gate 1:** stable probe/graph/read API. **Gate 2:** Quick Look + native browse/open-inside. **Gate 3:** optional Finder mount feasibility and qualification. **Parallel track:** honest encryption assessment and authorized Pro recovery research. **Later:** writeback and new recoverable container after security review.

Every task must state the exact files it touches, acceptance criteria, negative cases, dependencies, and who may promote the result. Cross-project research (including Reflective Rust) remains optional until integration is justified by a measured need.

## Definition of done

Code and docs agree; tests are run and reported; security/lifecycle regressions are addressed; limitations remain visible; relevant issues/PRs are linked. A design document or issue alone is **not** implementation completion.
