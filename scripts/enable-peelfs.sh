#!/usr/bin/env bash
# Enable PeelFS plugin and explain duplicate FSKit rows.
set -euo pipefail
echo "==> pluginkit enable"
pluginkit -e use -i io.snackstud.peel.PeelFS || true
echo
echo "==> registered modules"
pluginkit -mAvvv -p com.apple.fskit.fsmodule 2>/dev/null | sed -n '1,80p' || true
echo
echo "==> Peel.app copies (duplicates cause multiple Settings rows)"
mdfind 'kMDItemCFBundleIdentifier == "io.snackstud.peel"' 2>/dev/null || true
find /Applications /Users/zachshallbetter/Projects/peel/dist -name 'Peel.app' 2>/dev/null || true
echo
echo "Keep only /Applications/Peel.app. Remove extra copies / rebuild DerivedData apps."
echo "System Settings → Extensions → Peel → FSKit Modules toggle ON (you already did)."
echo
echo "If mount still says 'Module … is disabled', fskitd rejected the module."
echo "Common causes: missing restricted entitlement on the team provisioning profile,"
echo "or a macOS FSKit third-party enablement bug. Peel falls back to a Finder browse cache."
