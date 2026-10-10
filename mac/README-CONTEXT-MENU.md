# Finder context menu — Peel

## What you’ll see

macOS always keeps Apple’s **Compress**. Peel adds extract actions under **Services** and **Quick Actions**:

| Menu item | Behavior |
|-----------|----------|
| **Peel** | Extract beside the archive (compact progress HUD) |
| **Peel to…** | Pick a destination folder, then extract |
| **Peel & Reveal** | Extract, then select the result in Finder |
| **Open With → Peel** | Same as **Peel** (also default for zip/rar/7z when claimed) |

Path: right-click archive → **Services** → **Peel** / **Peel to…** / **Peel & Reveal**  
(On some macOS versions the same items appear under **Quick Actions**.)

## Enable

1. Rebuild/install Peel, then run `./scripts/install-finder-service.sh`
2. **System Settings → Keyboard → Keyboard Shortcuts → Services**
3. Enable **Peel**, **Peel to…**, **Peel & Reveal** under Files and Folders
4. Optional shortcuts (e.g. ⌃⌘P for Peel)

```bash
/System/Library/CoreServices/pbs -flush
```

## Why not a single top-level “Uncompress”?

Finder does not allow third parties to inject a peer of **Compress** without a Finder Sync extension. Services/Quick Actions is the supported Unarchiver-class approach. Labels are short product actions (**Peel**), not “Uncompress filename”.
