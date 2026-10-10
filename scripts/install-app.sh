#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL=1 CONFIGURATION=Release "$ROOT/scripts/build-app.sh"
