#!/usr/bin/env python3
import plistlib, shutil
from pathlib import Path

services = Path.home() / "Library/Services"
wf_root = services / "Uncompress.workflow"
if wf_root.exists():
    shutil.rmtree(wf_root)
contents = wf_root / "Contents"
contents.mkdir(parents=True)

info = {
    "CFBundleIdentifier": "dev.shallbetter.peel.uncompress",
    "CFBundleName": "Uncompress",
    "CFBundlePackageType": "BNDL",
    "CFBundleShortVersionString": "1.0",
    "CFBundleVersion": "1",
    "NSServices": [{
        "NSMenuItem": {"default": "Uncompress"},
        "NSMessage": "runWorkflowAsService",
        "NSSendFileTypes": ["public.item", "public.data"],
    }],
}
with open(contents / "Info.plist", "wb") as f:
    plistlib.dump(info, f)

cmd = """#!/bin/bash
APP=\"/Applications/Peel.app\"
[ -d \"$APP\" ] || exit 1
[ \"$#\" -eq 0 ] && exit 0
exec open -a \"$APP\" -- \"$@\"
"""
action = {
    "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
    "ActionName": "Run Shell Script",
    "ActionParameters": {
        "COMMAND_STRING": cmd,
        "inputMethod": 1,
        "shell": "/bin/bash",
        "source": cmd,
    },
    "BundleIdentifier": "com.apple.RunShellScript",
    "CFBundleVersion": "2.0.3",
    "UUID": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
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
print(wf_root)
