import Foundation
import AppKit
import ApplicationServices

/// Open an archive as a Finder location (archive-as-folder).
///
/// Prefer a real PeelFS (FSKit) mount so the ZIP itself behaves like a folder.
/// When macOS leaves the module disabled, materialize a browse volume whose
/// *root entries match the archive root* (single top-level wrappers are
/// promoted so you land on real contents, not an extra nested folder).
/// Browse volumes are TTL/size-limited caches — not permanent extracts.
enum PeelFSMount {
    enum MountError: LocalizedError {
        case unsupportedFormat
        case mountFailed(String)
        case notAvailable(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "This format cannot be browsed yet."
            case .mountFailed(let msg), .notAvailable(let msg):
                return msg
            }
        }
    }

    /// Defaults for browse-volume eviction (overridable via UserDefaults).
    enum CachePolicy {
        static let defaultsTTLKey = "peel.browseCacheTTLHours"
        static let defaultsMaxBytesKey = "peel.browseCacheMaxBytes"
        /// 24 hours
        static var ttl: TimeInterval {
            let hours = UserDefaults.standard.object(forKey: defaultsTTLKey) as? Double ?? 24
            return max(1, hours) * 3600
        }
        /// Default 2 GiB total across all browse volumes. Explicit UserDefaults wins as-is.
        static var maxTotalBytes: UInt64 {
            if let v = UserDefaults.standard.object(forKey: defaultsMaxBytesKey) as? Int, v > 0 {
                return UInt64(v)
            }
            return 2 * 1024 * 1024 * 1024
        }
        static let metaFileName = ".peel-volume-meta.json"
        static let legacyMarkerName = ".peel-volume-id"
    }

    private struct VolumeMeta: Codable {
        var source: String
        var stamp: String
        var created: TimeInterval
        var accessed: TimeInterval
    }

    private static let fsType = "PeelFS"
    private static let lock = NSLock()
    /// archive path → mounted/browse URL
    private static var mounts: [String: URL] = [:]

    /// Stable “volumes” root (not /tmp).
    static var volumesRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let root = base.appendingPathComponent("Peel/Volumes", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Legacy cache root from earlier spikes (cleaned on purge).
    static var legacyBrowseRoot: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Peel/Browse", isDirectory: true)
    }

    static func supportsBrowse(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["zip", "cbz", "rar", "cbr", "7z", "tar", "gz", "tgz", "tbz2", "bz2"].contains(ext)
    }

    static func supportsFSKit(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "zip" || ext == "cbz"
    }

    static func isModuleEnabled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        proc.arguments = ["-m", "-i", "io.snackstud.peel.PeelFS"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return false
        }
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("io.snackstud.peel.PeelFS") {
                return t.hasPrefix("+")
            }
        }
        return false
    }

    static func requestEnable() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        proc.arguments = ["-e", "use", "-i", "io.snackstud.peel.PeelFS"]
        try? proc.run()
        proc.waitUntilExit()
    }

    /// Resolve a browsable folder for the archive (FSKit mount or local volume folder).
    @discardableResult
    static func mount(_ archive: URL) throws -> URL {
        guard supportsBrowse(archive) else { throw MountError.unsupportedFormat }

        // Opportunistic eviction before allocating more disk.
        _ = purgeExpiredBrowseVolumes()

        let key = archive.standardizedFileURL.path

        lock.lock()
        if let existing = mounts[key], FileManager.default.fileExists(atPath: existing.path) {
            if isFSKitMount(existing) || isBrowseVolume(existing) {
                lock.unlock()
                touchAccess(existing)
                return existing
            }
            mounts.removeValue(forKey: key)
        }
        lock.unlock()

        if supportsFSKit(archive) {
            requestEnable()
            if let mp = try? fskitMount(archive) {
                lock.lock()
                mounts[key] = mp
                lock.unlock()
                return mp
            }
        }

        // Extract can take minutes — never hold the cache lock here.
        let folder = try materializeBrowseVolume(archive)
        lock.lock()
        mounts[key] = folder
        lock.unlock()
        _ = enforceSizeBudget(keeping: folder)
        return folder
    }

    /// Open in Finder like normal navigation: reuse the front Finder window when possible.
    @MainActor
    static func browseInFinderThrowing(_ archive: URL) throws {
        let location = try mount(archive)
        // Prefer controlling the existing Finder window; never activate Peel.
        navigateFinder(to: location, preferringReuse: true)
    }

    @MainActor
    static func browseInFinder(_ archive: URL) -> Bool {
        do {
            try browseInFinderThrowing(archive)
            return true
        } catch {
            return false
        }
    }

    static func unmount(archive: URL? = nil, mountPoint: URL? = nil) {
        lock.lock()
        defer { lock.unlock() }
        var points: [URL] = []
        if let mountPoint { points.append(mountPoint) }
        if let archive {
            let key = archive.standardizedFileURL.path
            if let mp = mounts.removeValue(forKey: key) {
                points.append(mp)
            }
        }
        if points.isEmpty {
            points = Array(mounts.values)
            mounts.removeAll()
        }
        for mp in points where isFSKitMount(mp) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/sbin/umount")
            proc.arguments = [mp.path]
            try? proc.run()
            proc.waitUntilExit()
            try? FileManager.default.removeItem(at: mp)
        }
    }

    // MARK: - Cache stats & cleanup

    struct CacheStats {
        var volumeCount: Int
        var totalBytes: UInt64
        var oldestAccess: Date?
        var path: String
    }

    static func cacheStats() -> CacheStats {
        let root = volumesRoot
        var count = 0
        var total: UInt64 = 0
        var oldest: Date?
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return CacheStats(volumeCount: 0, totalBytes: 0, oldestAccess: nil, path: root.path)
        }
        for dir in kids {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard isBrowseVolume(dir) else { continue }
            count += 1
            total += directoryByteSize(dir)
            if let meta = readMeta(dir) {
                let d = Date(timeIntervalSince1970: meta.accessed)
                if oldest == nil || d < oldest! { oldest = d }
            }
        }
        return CacheStats(volumeCount: count, totalBytes: total, oldestAccess: oldest, path: root.path)
    }

    /// Remove volumes older than TTL. Returns number of folders deleted.
    @discardableResult
    static func purgeExpiredBrowseVolumes(now: Date = Date()) -> Int {
        lock.lock()
        defer { lock.unlock() }
        // Also drop legacy Caches/Peel/Browse once.
        try? FileManager.default.removeItem(at: legacyBrowseRoot)

        let root = volumesRoot
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return 0 }

        let cutoff = now.timeIntervalSince1970 - CachePolicy.ttl
        var removed = 0
        for dir in kids {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            // Only touch peel-managed volumes (meta or legacy marker).
            guard isBrowseVolume(dir) || fm.fileExists(atPath: dir.appendingPathComponent(CachePolicy.legacyMarkerName).path) else {
                continue
            }
            let accessed: TimeInterval = {
                if let m = readMeta(dir) { return m.accessed }
                if let vals = try? dir.resourceValues(forKeys: [.contentModificationDateKey]),
                   let d = vals.contentModificationDate {
                    return d.timeIntervalSince1970
                }
                return 0
            }()
            if accessed < cutoff {
                // Don't delete if currently tracked as open mount for this session and still "fresh" —
                // cutoff already handles age; clear map entry if path matches.
                mounts = mounts.filter { $0.value.path != dir.path }
                try? fm.removeItem(at: dir)
                removed += 1
            }
        }
        return removed
    }

    /// Delete all browse volumes (Settings “Clear Cache”). FSKit mounts are unmounted first when possible.
    @discardableResult
    static func clearAllBrowseVolumes() -> (removed: Int, freedBytes: UInt64) {
        lock.lock()
        defer { lock.unlock() }

        // Unmount any FSKit paths we know about.
        for (_, mp) in mounts where isFSKitMount(mp) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/sbin/umount")
            proc.arguments = [mp.path]
            try? proc.run()
            proc.waitUntilExit()
        }
        mounts.removeAll()

        try? FileManager.default.removeItem(at: legacyBrowseRoot)

        let root = volumesRoot
        let fm = FileManager.default
        var removed = 0
        var freed: UInt64 = 0
        guard let kids = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return (0, 0)
        }
        for dir in kids {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                // stray files
                if let sz = (try? dir.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    freed += UInt64(sz)
                }
                try? fm.removeItem(at: dir)
                continue
            }
            freed += directoryByteSize(dir)
            try? fm.removeItem(at: dir)
            removed += 1
        }
        return (removed, freed)
    }

    /// Run TTL + size budget (call on launch).
    static func performMaintenance() {
        _ = purgeExpiredBrowseVolumes()
        _ = enforceSizeBudget(keeping: nil)
    }

// MARK: - Finder navigation

    /// Snapshot of the Finder window the user was in when they opened an archive.
    /// Used so we retarget *that* window/tab instead of spawning a new one.
    struct FinderContext: Sendable {
        var windowID: Int?
        var parentPath: String
        var archiveName: String
    }

/// Ask macOS to allow Peel → Finder Automation (shows system prompt once).
    /// Returns true when permitted. Apps only appear under Privacy → Automation after this runs.
@discardableResult
    static func requestFinderAutomation(prompt: Bool = true) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        // Newer SDKs take AEAddressDesc by value (not pointer).
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            typeWildCard,
            typeWildCard,
            prompt
        )
        // noErr (0) = allowed; errAEEventNotPermitted (-1743) = denied
        return status == noErr
    }

    static func openAutomationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    /// Capture front Finder window + folder containing the archive (call ASAP on open).
    static func captureFinderContext(for archive: URL) -> FinderContext {
        let parent = archive.deletingLastPathComponent().standardizedFileURL.path
        let name = archive.lastPathComponent
        var windowID: Int?

        // Ensure Peel is listed under Automation and prompt if needed.
        _ = requestFinderAutomation(prompt: true)

        let script = """
        tell application "Finder"
          try
            if (count of Finder windows) > 0 then
              return id of front Finder window as string
            end if
          end try
          return ""
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if error == nil {
                let s = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if let id = Int(s) { windowID = id }
            }
        }
        return FinderContext(windowID: windowID, parentPath: parent, archiveName: name)
    }

/// How Finder was navigated (for diagnostics in AppState.detail).
    enum NavigateResult: String {
        case sameWindow = "same-window"
        case newWindowOnly = "new-window-empty-finder"
        case failed = "failed-no-open"
    }

    /// Navigate Finder like “open this folder” in the *same* window/tab.
    /// Never uses `NSWorkspace.open` / Finder `open` when a window exists — those
    /// create a new tab when Finder’s “open folders in tabs” is on.
    @discardableResult
    static func navigateFinder(
        to url: URL,
        preferringReuse: Bool,
        context: FinderContext? = nil
    ) -> NavigateResult {
        let destPath = url.standardizedFileURL.path
        let parentPath = context?.parentPath
            ?? url.deletingLastPathComponent().standardizedFileURL.path
        let windowID = context?.windowID

        _ = requestFinderAutomation(prompt: false)

        if preferringReuse {
            for _ in 0..<3 {
                if runFinderNavigateScript(destPath: destPath, parentPath: parentPath, windowID: windowID) {
                    logBrowse("navigate same-window → \(destPath)")
                    // Nudge Finder without opening anything new.
                    NSWorkspace.shared.noteFileSystemChanged(destPath)
                    return .sameWindow
                }
                usleep(120_000)
            }
        }

        // Only create a window if Finder has none. Never NSWorkspace.open (new tab).
        if runFinderOpenOnlyIfNoWindows(destPath: destPath) {
            logBrowse("navigate new-window (Finder had none) → \(destPath)")
            return .newWindowOnly
        }

        logBrowse("navigate FAILED (no NSWorkspace fallback) → \(destPath)")
        return .failed
    }

    /// Index-based Finder retarget. Avoids `repeat with w in windows` reference bugs
    /// and never calls `open` (new tab).
    @discardableResult
    private static func runFinderNavigateScript(
        destPath: String,
        parentPath: String,
        windowID: Int?
    ) -> Bool {
        let dest = escapeAppleScript(destPath)
        let parentBare = escapeAppleScript(parentPath)
        let parentSlash = escapeAppleScript(parentPath.hasSuffix("/") ? parentPath : parentPath + "/")
        let destSlash = escapeAppleScript(destPath.hasSuffix("/") ? destPath : destPath + "/")
        let idNum = windowID ?? 0

        let script = """
        set destPath to "\(dest)"
        set destSlash to "\(destSlash)"
        set parentBare to "\(parentBare)"
        set parentSlash to "\(parentSlash)"
        set wantId to \(idNum)
        set folderAlias to (POSIX file destPath) as alias
        tell application "Finder"
          -- 1) Captured window id from double-click moment
          if wantId is not 0 then
            try
              set target of Finder window id wantId to folderAlias
              set tp to POSIX path of (target of Finder window id wantId as alias)
              if tp is destPath or tp is destSlash then return "ok-id"
            end try
          end if

          set n to count of Finder windows
          if n is 0 then return "none"

          -- 2) Window still showing the archive's parent folder
          repeat with i from 1 to n
            try
              set tp to POSIX path of (target of Finder window i as alias)
              if tp is parentBare or tp is parentSlash then
                set target of Finder window i to folderAlias
                set tp2 to POSIX path of (target of Finder window i as alias)
                if tp2 is destPath or tp2 is destSlash then return "ok-parent"
              end if
            end try
          end repeat

          -- 3) Already on destination (idempotent)
          repeat with i from 1 to n
            try
              set tp to POSIX path of (target of Finder window i as alias)
              if tp is destPath or tp is destSlash then return "ok-already"
            end try
          end repeat

          -- 4) Front window (same tab) — still never `open`
          try
            set target of Finder window 1 to folderAlias
            set tp to POSIX path of (target of Finder window 1 as alias)
            if tp is destPath or tp is destSlash then return "ok-front"
          end try

          return "fail"
        end tell
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
        let result = appleScript.executeAndReturnError(&error)
        if let error {
            logBrowse("AppleScript error: \(error)")
            return false
        }
        let s = result.stringValue ?? ""
        logBrowse("AppleScript result: \(s)")
        return s.hasPrefix("ok")
    }

    private static func runFinderOpenOnlyIfNoWindows(destPath: String) -> Bool {
        let dest = escapeAppleScript(destPath)
        let script = """
        set folderAlias to (POSIX file "\(dest)") as alias
        tell application "Finder"
          if (count of Finder windows) = 0 then
            make new Finder window to folderAlias
            return "ok-new"
          else
            try
              set target of Finder window 1 to folderAlias
              return "ok-front"
            on error
              return "fail"
            end try
          end if
        end tell
        """
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
        let result = appleScript.executeAndReturnError(&error)
        if error != nil { return false }
        return (result.stringValue ?? "").hasPrefix("ok")
    }

    private static func logBrowse(_ message: String) {
        let fm = FileManager.default
        let dir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/Peel", isDirectory: true)
        if let dir {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("browse.log")
            let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
            if let data = line.data(using: .utf8) {
                if fm.fileExists(atPath: file.path),
                   let handle = try? FileHandle(forWritingTo: file) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? data.write(to: file)
                }
            }
        }
    }

    private static func escapeAppleScript(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - FSKit

    private static func fskitMount(_ archive: URL) throws -> URL {
        let name = sanitize(archive.deletingPathExtension().lastPathComponent)
        let mp = volumesRoot.appendingPathComponent("fs-\(name)", isDirectory: true)
        if FileManager.default.fileExists(atPath: mp.path), !isFSKitMount(mp) {
            try? FileManager.default.removeItem(at: mp)
        }
        try FileManager.default.createDirectory(at: mp, withIntermediateDirectories: true)

        let attempts: [[String]] = [
            ["-F", "-t", fsType, "-o", "rdonly,noowners", archive.path, mp.path],
            ["-F", "-t", fsType, "-o", "rdonly", archive.path, mp.path],
            ["-t", fsType, "-o", "rdonly", archive.path, mp.path],
        ]
        var lastErr = "mount failed"
        for args in attempts {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/sbin/mount")
            proc.arguments = args
            let err = Pipe()
            proc.standardError = err
            proc.standardOutput = Pipe()
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0, isFSKitMount(mp) {
                return mp
            }
            lastErr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? lastErr
        }
        try? FileManager.default.removeItem(at: mp)
        throw MountError.notAvailable(lastErr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Browse volume

    private static func materializeBrowseVolume(_ archive: URL) throws -> URL {
        let name = sanitize(archive.deletingPathExtension().lastPathComponent)
        let stamp: String = {
            let vals = try? archive.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let t = Int(vals?.contentModificationDate?.timeIntervalSince1970 ?? 0)
            let s = vals?.fileSize ?? 0
            return "\(t)-\(s)"
        }()
        let now = Date().timeIntervalSince1970
        let parent = archive.deletingLastPathComponent()

        // Prefer a sibling folder next to the archive (natural Finder path in Downloads, etc.).
        // Fall back to Application Support if the sibling name collides with a non-Peel folder.
        let sibling = parent.appendingPathComponent(name, isDirectory: true)
        let appSupport = volumesRoot.appendingPathComponent(name, isDirectory: true)

        let folder: URL = {
            if let meta = readMeta(sibling),
               meta.source == archive.standardizedFileURL.path,
               meta.stamp == stamp {
                return sibling
            }
            if !FileManager.default.fileExists(atPath: sibling.path) {
                return sibling
            }
            // Exists but not ours — use App Support volume name.
            return appSupport
        }()

if let meta = readMeta(folder),
           meta.source == archive.standardizedFileURL.path,
           meta.stamp == stamp,
           FileManager.default.fileExists(atPath: folder.path) {
            // Older browse volumes kept a single zip root folder nested inside.
            // Promote so the folder root is the archive contents.
            promoteSingleRootContents(of: folder)
            touchAccess(folder)
            return folder
        }

        // Legacy marker migration
        let legacy = folder.appendingPathComponent(CachePolicy.legacyMarkerName)
        if let data = try? Data(contentsOf: legacy),
           let text = String(data: data, encoding: .utf8),
           text == "\(archive.standardizedFileURL.path)|\(stamp)" {
            promoteSingleRootContents(of: folder)
            writeMeta(
                folder,
                VolumeMeta(source: archive.standardizedFileURL.path, stamp: stamp, created: now, accessed: now)
            )
            try? FileManager.default.removeItem(at: legacy)
            return folder
        }

        if FileManager.default.fileExists(atPath: folder.path) {
            // Only wipe if it's our volume (has meta) or empty-ish new sibling.
            if isBrowseVolume(folder) || folder.path.hasPrefix(volumesRoot.path) {
                try? FileManager.default.removeItem(at: folder)
            } else if folder.path == sibling.path {
                // Collision with real folder — switch to app support
                return try materializeAt(
                    appSupport,
                    archive: archive,
                    name: name,
                    stamp: stamp,
                    now: now
                )
            }
        }
        return try materializeAt(folder, archive: archive, name: name, stamp: stamp, now: now)
    }

    private static func materializeAt(
        _ folder: URL,
        archive: URL,
        name: String,
        stamp: String,
        now: TimeInterval
    ) throws -> URL {
        let _ = name
        if FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        guard let peel = PeelExtractor.engineURL() else {
            throw MountError.notAvailable("Peel engine missing; cannot open archive as a folder.")
        }

        let proc = Process()
        proc.executableURL = peel
        proc.arguments = ["x", archive.path, "-o", folder.path, "-D", "-r", "-q"]
        let err = Pipe()
        proc.standardError = err
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
if proc.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "extract failed"
            throw MountError.mountFailed(msg)
        }

        // Archive-as-folder: browse root should show what you get by opening the
        // archive, not an extra enclosing directory. GitHub-style zips wrap
        // everything in one top-level folder — promote that so Finder lands on
        // README / sources instead of a redundant nested name.
        promoteSingleRootContents(of: folder)

        writeMeta(
            folder,
            VolumeMeta(source: archive.standardizedFileURL.path, stamp: stamp, created: now, accessed: now)
        )
        return folder
    }

    /// If `folder` contains exactly one visible subdirectory (and no files),
    /// move that directory's children up so `folder` mirrors archive contents
    /// after entering the sole root entry.
    private static func promoteSingleRootContents(of folder: URL) {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let visible = kids.filter { url in
            let name = url.lastPathComponent
            if name == ".DS_Store" { return false }
            if name == CachePolicy.metaFileName { return false }
            if name == CachePolicy.legacyMarkerName { return false }
            if name.hasPrefix(".peel-") { return false }
            return true
        }
        guard visible.count == 1 else { return }

        let only = visible[0]
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: only.path, isDirectory: &isDir), isDir.boolValue else { return }

        // Stage the wrapper aside, then hoist children into the browse root.
        let staging = folder.appendingPathComponent(
            ".peel-promote-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fm.moveItem(at: only, to: staging)
            let nested = try fm.contentsOfDirectory(
                at: staging,
                includingPropertiesForKeys: nil,
                options: []
            )
            for item in nested {
                let dest = folder.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.moveItem(at: item, to: dest)
            }
            try fm.removeItem(at: staging)
        } catch {
            // Best-effort: if promote fails, leave the extracted tree as-is.
            if fm.fileExists(atPath: staging.path), !fm.fileExists(atPath: only.path) {
                try? fm.moveItem(at: staging, to: only)
            }
        }
    }

    private static func isBrowseVolume(_ url: URL) -> Bool {
        let meta = url.appendingPathComponent(CachePolicy.metaFileName)
        let legacy = url.appendingPathComponent(CachePolicy.legacyMarkerName)
        return FileManager.default.fileExists(atPath: meta.path)
            || FileManager.default.fileExists(atPath: legacy.path)
    }

    private static func isFSKitMount(_ url: URL) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/mount")
        let out = Pipe()
        proc.standardOutput = out
        try? proc.run()
        proc.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.contains(url.path) && text.lowercased().contains("peelfs")
    }

    private static func readMeta(_ folder: URL) -> VolumeMeta? {
        let url = folder.appendingPathComponent(CachePolicy.metaFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VolumeMeta.self, from: data)
    }

    private static func writeMeta(_ folder: URL, _ meta: VolumeMeta) {
        let url = folder.appendingPathComponent(CachePolicy.metaFileName)
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: url, options: .atomic)
        var values = URLResourceValues()
        values.isHidden = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }

    private static func touchAccess(_ folder: URL) {
        guard var meta = readMeta(folder) else { return }
        meta.accessed = Date().timeIntervalSince1970
        writeMeta(folder, meta)
    }

    /// LRU-ish eviction by last access until under maxTotalBytes.
    @discardableResult
    private static func enforceSizeBudget(keeping keep: URL?) -> Int {
        let maxBytes = CachePolicy.maxTotalBytes
        var stats = listVolumeDirs()
        var total = stats.reduce(UInt64(0)) { $0 + $1.bytes }
        if total <= maxBytes { return 0 }

        // Oldest accessed first
        stats.sort { $0.accessed < $1.accessed }
        var removed = 0
        for item in stats {
            if total <= maxBytes { break }
            if let keep, item.url.path == keep.path { continue }
            mounts = mounts.filter { $0.value.path != item.url.path }
            try? FileManager.default.removeItem(at: item.url)
            total = total > item.bytes ? total - item.bytes : 0
            removed += 1
        }
        return removed
    }

    private struct VolumeDir {
        var url: URL
        var bytes: UInt64
        var accessed: TimeInterval
    }

    private static func listVolumeDirs() -> [VolumeDir] {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(
            at: volumesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }
        var out: [VolumeDir] = []
        for dir in kids {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard isBrowseVolume(dir) else { continue }
            let accessed = readMeta(dir)?.accessed
                ?? ((try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate?.timeIntervalSince1970 ?? 0)
            out.append(VolumeDir(url: dir, bytes: directoryByteSize(dir), accessed: accessed))
        }
        return out
    }

    private static func directoryByteSize(_ root: URL) -> UInt64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in en {
            if let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               vals.isRegularFile == true,
               let sz = vals.fileSize {
                total += UInt64(sz)
            }
        }
        return total
    }

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ."))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        return cleaned.isEmpty ? "Archive" : String(cleaned.prefix(80))
    }
}
