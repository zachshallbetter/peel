# Reflective Rust × Peel

**Status:** Optional future integration notes — **not wired into peel-core**  
**Shipped truth:** [`SHIPPED.md`](SHIPPED.md)

[Reflective Rust](https://github.com/zachshallbetter/reflective-rust) is a separate research stack (RSP envelopes, OSG, `#[derive(Reflectable)]`). Peel does **not** depend on it today.

## Honest mapping

| Peel surface | Reflective idea | Reality in this repo |
| --- | --- | --- |
| `peel formats` / `peel probe -j` | Capability-shaped descriptors | **Plain JSON from CLI** — no RSP envelopes |
| MCP `peel_*` tools | Operation contracts for agents | **Not implemented** (no MCP server in tree) |
| FFI result types | `#[derive(Reflectable)]` | **Not applied** — peel-ffi is a thin C ABI scaffold |

## Why no hard dependency

Reflective Rust is edition-2024 research crates. Peel’s engine stays lean for shipping extract/browse.  
We may later emit richer envelopes from `probe` without changing UX; that is **roadmap**, not HEAD.

## If integrating later

```toml
# crates/peel-core/Cargo.toml (future only)
# reflective-rust-protocol = { path = "..." }
# reflective-rust-derive = { path = "..." }
```

Do not design peel features that **require** Reflective Rust until this file and SHIPPED.md say otherwise.
