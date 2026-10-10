#!/usr/bin/env bash
# Finder / Services helper — hand files to Peel.app so the compact progress HUD runs.
set -euo pipefail
APP="/Applications/Peel.app"
if [[ ! -d "$APP" ]]; then
  echo "Peel.app not installed at $APP" >&2
  exit 1
fi
if [[ $# -eq 0 ]]; then
  open -a "$APP"
  exit 0
fi
open -a "$APP" -- "$@"
