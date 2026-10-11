#!/usr/bin/env bash
# Build a single installable Peel.app (Rust engine + Swift UI).
set -euo pipefail
export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/bin:/bin:${PATH}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
DIST="$ROOT/dist"
CONFIGURATION="${CONFIGURATION:-Release}"
INSTALL="${INSTALL:-0}"
TEAM_ID="${DEVELOPMENT_TEAM:-PKH7G93GGD}"

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

USED_DEV_SIGN=0
set +e
xcodebuild \
  -project "$APP_DIR/Peel.xcodeproj" \
  -scheme Peel \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS,arch=arm64' \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  -allowProvisioningUpdates \
  build
XCODE_STATUS=$?
set -e

if [[ "$XCODE_STATUS" -eq 0 ]]; then
  USED_DEV_SIGN=1
  echo "Signed with Apple Development (team $TEAM_ID)"
else
  echo "warning: Development signing failed (status $XCODE_STATUS); retrying ad-hoc compile"
  xcodebuild \
    -project "$APP_DIR/Peel.xcodeproj" \
    -scheme Peel \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" \
    -destination 'platform=macOS,arch=arm64' \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    build
fi

APP_SRC="$(find "$DERIVED/Build/Products/$CONFIGURATION" -maxdepth 1 -name 'Peel.app' -print -quit)"
if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
  echo "error: Peel.app not found under $DERIVED" >&2
  exit 1
fi

echo "==> 4/4  Stage app"
rm -rf "$DIST/Peel.app"
cp -R "$APP_SRC" "$DIST/Peel.app"

# Ensure engine is present (re-sign only the binary if we keep Dev signature on the bundle)
HELPERS="$DIST/Peel.app/Contents/Helpers"
mkdir -p "$HELPERS"
cp -f "$ROOT/target/release/peel" "$HELPERS/peel"
chmod +x "$HELPERS/peel"
mkdir -p "$DIST/Peel.app/Contents/Resources"
cp -f "$ROOT/target/release/peel" "$DIST/Peel.app/Contents/Resources/peel"
chmod +x "$DIST/Peel.app/Contents/Resources/peel"

EXT_ENT="$APP_DIR/PeelFSExtension/PeelFSExtension.entitlements"
HOST_ENT="$APP_DIR/Peel/Peel.entitlements"

if [[ "$USED_DEV_SIGN" -eq 1 ]]; then
  # Preserve Development signature; only re-sign after embedding peel helper.
  IDENTITY="Apple Development"
  echo "Re-signing with $IDENTITY after embedding engine"
  while IFS= read -r appex; do
    codesign --force --sign "$IDENTITY" --entitlements "$EXT_ENT" --timestamp=none "$appex"
  done < <(find "$DIST/Peel.app" -name 'PeelFSExtension.appex' -type d 2>/dev/null)
  codesign --force --sign "$IDENTITY" --entitlements "$HOST_ENT" --timestamp=none "$HELPERS/peel" || true
  codesign --force --sign "$IDENTITY" --entitlements "$HOST_ENT" --timestamp=none "$DIST/Peel.app"
else
  echo "Ad-hoc signing (FSKit mount may stay disabled)"
  while IFS= read -r appex; do
    codesign --force --sign - --entitlements "$EXT_ENT" "$appex" || true
  done < <(find "$DIST/Peel.app" -name 'PeelFSExtension.appex' -type d 2>/dev/null)
  if [[ -f "$HOST_ENT" ]]; then
    codesign --force --deep --sign - --entitlements "$HOST_ENT" "$DIST/Peel.app"
  else
    codesign --force --deep --sign - "$DIST/Peel.app"
  fi
fi

codesign --verify --verbose=1 "$DIST/Peel.app" || true
find "$DIST/Peel.app" -name '*.appex' -print 2>/dev/null || true
codesign -dvvv "$DIST/Peel.app/Contents/Extensions/PeelFSExtension.appex" 2>&1 | grep -E 'Authority|TeamIdentifier|flags' || true

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
