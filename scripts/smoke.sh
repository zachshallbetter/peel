#!/usr/bin/env bash
set -euo pipefail
export PATH="${HOME}/.cargo/bin:${PATH}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

cargo test -p peel-core
cargo build -p peel-cli --release

BIN="$ROOT/target/release/peel"
FIX="$ROOT/fixtures/hello.zip"
OUT="$ROOT/.build/smoke-out"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "== list =="
"$BIN" list "$FIX"
echo "== extract =="
"$BIN" extract "$FIX" --out "$OUT" --collision overwrite --json
test -f "$OUT/hello.txt" || test -n "$(find "$OUT" -name 'hello.txt' | head -1)"
echo "smoke OK"
