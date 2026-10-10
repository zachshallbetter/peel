#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNAR="$ROOT/.build/bin/unar"
LSAR="$ROOT/.build/bin/lsar"
FIX="$ROOT/fixtures/hello.zip"
OUT="$ROOT/.build/smoke-out"

[[ -x "$UNAR" ]] || { echo "Run ./scripts/build-unar.sh first" >&2; exit 1; }
rm -rf "$OUT"
mkdir -p "$OUT"
echo "Listing $FIX"
"$LSAR" "$FIX" || true
echo "Extracting…"
"$UNAR" -f -o "$OUT" "$FIX"
find "$OUT" -type f -print
test -f "$OUT/hello.txt"
grep -q 'hello from unarchiver-rea' "$OUT/hello.txt"
echo "smoke-extract OK"
