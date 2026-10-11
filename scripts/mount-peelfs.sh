#!/usr/bin/env bash
# Mount a ZIP via PeelFS (FSKit spike).
# Requires: macOS 15.4+, Peel.app installed/built with PeelFSExtension enabled
# under System Settings → General → Login Items & Extensions → File System Extensions.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: mount-peelfs.sh <archive.zip> [mountpoint]

Mount a ZIP archive through the PeelFS FSKit personality (short name: PeelFS).

Examples:
  ./scripts/mount-peelfs.sh ~/Downloads/project.zip
  ./scripts/mount-peelfs.sh ./fixture.zip /tmp/peel-mnt
  ./scripts/mount-peelfs.sh --unmount /tmp/peel-mnt

Notes:
  - Enable PeelFS in System Settings after installing Peel.app.
  - Ad-hoc / developer builds may need SIP-off or proper signing to load.
  - Path-URL mounts: mount -F -t PeelFS <archive> <mountpoint>
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--unmount" || "${1:-}" == "-u" ]]; then
  MP="${2:-}"
  if [[ -z "$MP" ]]; then
    echo "error: mountpoint required" >&2
    exit 2
  fi
  umount "$MP"
  echo "Unmounted $MP"
  exit 0
fi

ARCHIVE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
if [[ ! -f "$ARCHIVE" ]]; then
  echo "error: archive not found: $ARCHIVE" >&2
  exit 1
fi

MP="${2:-}"
if [[ -z "$MP" ]]; then
  base="$(basename "$ARCHIVE")"
  base="${base%.*}"
  MP="/tmp/peelfs-${base}-$$"
fi

mkdir -p "$MP"
echo "Mounting:"
echo "  archive: $ARCHIVE"
echo "  mount:   $MP"
echo "  type:    PeelFS (FSKit)"

# Prefer path-URL style (-F). Some builds also accept -t only.
if mount -F -t PeelFS "$ARCHIVE" "$MP"; then
  echo "Mounted OK."
  echo "Browse: open \"$MP\""
  echo "Unmount: ./scripts/mount-peelfs.sh --unmount \"$MP\""
  exit 0
fi

echo "path mount failed; retrying classic form…" >&2
if mount -t PeelFS "$ARCHIVE" "$MP"; then
  echo "Mounted OK (classic)."
  echo "Browse: open \"$MP\""
  exit 0
fi

echo "error: mount failed. Check that PeelFS is enabled in System Settings," >&2
echo "       that Peel.app embeds PeelFSExtension, and Console logs for io.snackstud.peel.fskit" >&2
exit 1
