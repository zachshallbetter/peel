#!/usr/bin/env bash
# Build a single installable Peel.app (Rust engine + Swift UI).
set -euo pipefail
export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/bin:/bin:${PATH}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
DIST="$ROOT/dist"
CONFIGURATION="${CONFIGURATION:-Release}"
INSTALL="${INSTALL:-0}"

cd "$ROOT"

echo "==> 1/4  Rust engine (peel-cli release)"
cargo build -p peel-cli --release
test -x "$ROOT/target/release/peel"

echo "==> 2/4  Generate Xcode project"
cd "$APP_DIR"
xcodegen generate

echo "==> 3/4  xcodebuild Peel.app"
DERIVED="$ROOT/.build/DerivedData-PeelApp"
mkdir -p "$DERIVED" "$DIST"
xcodebuild \
  -project "$APP_DIR/Peel.xcodeproj" \
  -scheme Peel \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  build

APP_SRC="$(find "$DERIVED/Build/Products/$CONFIGURATION" -maxdepth 1 -name 'Peel.app' -print -quit)"
if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
  echo "error: Peel.app not found under $DERIVED" >&2
  exit 1
fi

echo "==> 4/4  Stage + ad-hoc sign"
rm -rf "$DIST/Peel.app"
cp -R "$APP_SRC" "$DIST/Peel.app"

# Ensure engine is present even if resource phase skipped
HELPERS="$DIST/Peel.app/Contents/Helpers"
mkdir -p "$HELPERS"
cp -f "$ROOT/target/release/peel" "$HELPERS/peel"
chmod +x "$HELPERS/peel"
mkdir -p "$DIST/Peel.app/Contents/Resources"
cp -f "$ROOT/target/release/peel" "$DIST/Peel.app/Contents/Resources/peel"
chmod +x "$DIST/Peel.app/Contents/Resources/peel"

codesign --force --deep --sign - "$DIST/Peel.app"
codesign --verify --verbose=1 "$DIST/Peel.app" || true

echo
echo "Built: $DIST/Peel.app"
echo "Run:   open \"$DIST/Peel.app\""
echo "Size:  $(du -sh "$DIST/Peel.app" | awk '{print $1}')"

if [[ "$INSTALL" == "1" ]]; then
  echo "==> Installing to /Applications/Peel.app"
  rm -rf /Applications/Peel.app
  cp -R "$DIST/Peel.app" /Applications/Peel.app
  echo "Installed. Launch with: open -a Peel"
fi
