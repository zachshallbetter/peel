#!/usr/bin/env bash
# Enable PeelFS plugin and print Gate A diagnostics.
set -euo pipefail

APPEX="/Applications/Peel.app/Contents/Extensions/PeelFSExtension.appex"

echo "==> pluginkit enable"
pluginkit -e use -i io.snackstud.peel.PeelFS || true
echo

echo "==> pluginkit state (- = disabled, + = enabled)"
pluginkit -m -i io.snackstud.peel.PeelFS 2>/dev/null || true
echo

echo "==> FSKit modules (verbose excerpt)"
pluginkit -mAvvv -p com.apple.fskit.fsmodule 2>/dev/null | sed -n '1,100p' || true
echo

echo "==> signed appex entitlements"
if [[ -d "$APPEX" ]]; then
  codesign -d --entitlements :- "$APPEX" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null \
    || codesign -d --entitlements :- "$APPEX" 2>/dev/null || true
  PROF="$APPEX/Contents/embedded.provisionprofile"
  if [[ -f "$PROF" ]]; then
    echo
    echo "==> provision profile fskit key"
    security cms -D -i "$PROF" 2>/dev/null \
      | plutil -extract Entitlements.xml xml1 -o - - 2>/dev/null \
      | plutil -p - 2>/dev/null \
      || echo "(could not decode profile)"
  else
    echo "==> no embedded.provisionprofile on appex"
  fi
else
  echo "missing $APPEX — install with INSTALL=1 ./scripts/build-app.sh"
fi
echo

echo "==> Peel.app copies (duplicates confuse Settings / Automation)"
mdfind 'kMDItemCFBundleIdentifier == "io.snackstud.peel"' 2>/dev/null || true
ls -d /Applications/Peel.app "$HOME/Projects/peel/dist/Peel.app" 2>/dev/null || true
echo
echo "Use /Applications/Peel.app as the daily binary. dist/ is build output only."
echo "System Settings → Extensions → Peel → FSKit Modules ON."
echo
echo "Smoke mount: ./scripts/mount-peelfs.sh ~/path/to/file.zip"
echo "If mount prints 'Module … is disabled' while pluginkit shows '+' and the"
echo "profile contains com.apple.developer.fskit.fsmodule, fskitd is refusing the"
echo "module (OS/policy). Peel double-click falls back to browse cache — see"
echo "docs/finder-open-interaction.md §10 and .reports/mac-004-fskit-spike.md."
