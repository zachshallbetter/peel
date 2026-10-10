#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_PROJ="$ROOT/vendor/XADMaster/XADMaster.xcodeproj"
OUT="$ROOT/.build/bin"
DERIVED="$ROOT/.build/DerivedData-XADMaster"

[[ -d "$ROOT/vendor/UniversalDetector" ]] || { echo "Missing vendor/UniversalDetector" >&2; exit 1; }
[[ -f "$XCODE_PROJ/project.pbxproj" ]] || { echo "Missing Xcode project" >&2; exit 1; }

mkdir -p "$OUT" "$DERIVED"

build_scheme() {
  local scheme="$1"
  echo "Building ${scheme} (Release)…"
  xcodebuild \
    -project "$XCODE_PROJ" \
    -scheme "$scheme" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -destination 'platform=macOS,arch=arm64' \
    MACOSX_DEPLOYMENT_TARGET=12.0 \
    CLANG_CXX_LIBRARY=libc++ \
    OTHER_LDFLAGS='-lc++' \
    build
}

build_scheme unar
build_scheme lsar

while IFS= read -r bin; do
  cp -f "$bin" "$OUT/$(basename "$bin")"
  chmod +x "$OUT/$(basename "$bin")"
  echo "Installed $OUT/$(basename "$bin")"
done < <(find "$DERIVED/Build/Products" -type f \( -name unar -o -name lsar \) -perm +111)

test -x "$OUT/unar"
"$OUT/unar" -v 2>/dev/null || true
echo "Done → $OUT"
