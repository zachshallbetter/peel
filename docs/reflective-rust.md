# Reflective Rust × Peel

[Reflective Rust](https://github.com/zachshallbetter/reflective-rust) provides runtime semantic contracts (RSP envelopes, OSG topology, `#[derive(Reflectable)]`).

## Where Peel uses the ideas

| Peel surface | Reflective concept | Status |
|--------------|-------------------|--------|
| `peel formats` / `peel probe -j` | Capability descriptors per format | Implemented as plain JSON (agent-friendly) |
| MCP `peel_*` tools | Operation contracts | Implemented |
| Future in-process FFI types | `#[derive(Reflectable)]` on `ArchiveEntry` / `ExtractResult` | Optional path dep when wiring libpeel |

## Why not a hard dependency yet

Reflective Rust is edition 2024 research crates (protocol, derive, CSG). Peel’s engine stays lean for shipping. We mirror **capability-shaped JSON** in CLI/MCP now; full `reflective-rust-protocol` envelopes can attach later for signed provenance without changing the peel UX.

## Optional integration

```toml
# crates/peel-core/Cargo.toml (future)
reflective-rust-protocol = { path = "../../reflective-rust/crates/reflective-rust-protocol" }
reflective-rust-derive = { path = "../../reflective-rust/crates/reflective-rust-derive" }
```

Then annotate public result types and emit RSP envelopes from `peel probe --rsp`.
