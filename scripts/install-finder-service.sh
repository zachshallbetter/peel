#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${PEEL_APP:-/Applications/Peel.app}"
SERVICES="${HOME}/Library/Services"
mkdir -p "$SERVICES"

if [[ ! -d "$APP" ]]; then
  echo "Install Peel.app first" >&2
  exit 1
fi

python3 <<'PY'
import plistlib, shutil
from pathlib import Path
services = Path.home() / "Library/Services"
# remove legacy
for legacy in ("Uncompress.workflow",):
    p = services / legacy
    if p.exists():
        shutil.rmtree(p)

def write_workflow(name: str, menu: str, extra: str = ""):
    wf = services / f"{name}.workflow"
    if wf.exists():
        shutil.rmtree(wf)
    contents = wf / "Contents"
    contents.mkdir(parents=True)
    info = {
        "CFBundleIdentifier": f"dev.shallbetter.peel.wf.{name.lower().replace(' ', '').replace('&','and')}",
        "CFBundleName": menu,
        "CFBundlePackageType": "BNDL",
        "CFBundleShortVersionString": "0.2.0",
        "CFBundleVersion": "2",
        "NSServices": [{
            "NSMenuItem": {"default": menu},
            "NSMessage": "runWorkflowAsService",
            "NSSendFileTypes": ["public.item", "public.data", "public.archive", "public.zip-archive"],
        }],
    }
    with open(contents / "Info.plist", "wb") as f:
        plistlib.dump(info, f)
    cmd = f"""#!/bin/bash
APP="/Applications/Peel.app"
[ -d "$APP" ] || exit 1
[ "$#" -eq 0 ] && exit 0
{extra}exec open -a "$APP" -- "$@"
"""
    action = {
        "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
        "ActionName": "Run Shell Script",
        "ActionParameters": {"COMMAND_STRING": cmd, "inputMethod": 1, "shell": "/bin/bash", "source": cmd},
        "BundleIdentifier": "com.apple.RunShellScript",
        "CFBundleVersion": "2.0.3",
        "UUID": f"PEEL-{abs(hash(name)) % 10**8:08d}",
    }
    doc = {
        "AMApplicationBuild": "523",
        "AMApplicationVersion": "2.10",
        "AMDocumentVersion": "2",
        "actions": [{"action": action}],
        "connectors": {},
        "workflowType": "MenuService",
    }
    with open(contents / "document.wflow", "wb") as f:
        plistlib.dump(doc, f)
    print(wf)

write_workflow("Peel", "Peel")
write_workflow(
    "Peel & Reveal",
    "Peel & Reveal",
    extra='defaults write dev.shallbetter.peel peel._serviceRevealOnce -bool true\n',
)
PY

# Droplet
TMP="$(mktemp).applescript"
cat > "$TMP" <<'AS'
on open droppedItems
  set argv to ""
  repeat with f in droppedItems
    set argv to argv & " " & quoted form of POSIX path of f
  end repeat
  do shell script "open -a /Applications/Peel.app --" & argv
end open
on run
  tell application "Finder"
    try
      set sel to selection as alias list
    on error
      set sel to {}
    end try
  end tell
  if (count of sel) is 0 then
    tell application "Peel" to activate
    return
  end if
  set argv to ""
  repeat with f in sel
    set argv to argv & " " & quoted form of POSIX path of f
  end repeat
  do shell script "open -a /Applications/Peel.app --" & argv
end run
AS
rm -rf "${SERVICES}/Peel Here.app"
osacompile -o "${SERVICES}/Peel Here.app" "$TMP"
rm -f "$TMP"

cp -f "$ROOT/mac/peel-here.sh" "${SERVICES}/peel-here.sh" 2>/dev/null || true
chmod +x "${SERVICES}/peel-here.sh" 2>/dev/null || true

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

if command -v duti >/dev/null 2>&1; then
  for ext in zip rar 7z tar gz tgz cbz cbr; do
    duti -s dev.shallbetter.peel ".$ext" all 2>/dev/null || true
  done
fi

echo "Installed Services/Quick Actions: Peel · Peel & Reveal · Peel Here droplet"
echo "Also in Peel.app: Peel · Peel to… · Peel & Reveal (NSServices)"
echo "Enable under: System Settings → Keyboard → Keyboard Shortcuts → Services"
