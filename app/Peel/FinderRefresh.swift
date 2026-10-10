import AppKit
import Foundation

/// Make Finder pick up newly written files without requiring a relaunch.
enum FinderRefresh {
    /// Notify Finder that these paths (and their parents) changed.
    static func pathsChanged(_ paths: [String]) {
        var unique = Set<String>()
        for path in paths {
            guard !path.isEmpty else { continue }
            unique.insert(path)
            let parent = (path as NSString).deletingLastPathComponent
            if !parent.isEmpty, parent != "/" {
                unique.insert(parent)
            }
        }

        for path in unique {
            // Still the reliable public API for directory refresh.
            NSWorkspace.shared.noteFileSystemChanged(path)
            // Bump directory mtime so list views re-stat.
            let url = URL(fileURLWithPath: path)
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                try? FileManager.default.setAttributes(
                    [.modificationDate: Date()],
                    ofItemAtPath: path
                )
            }
        }

        // Ask open Finder windows that show these folders to reload.
        refreshOpenFinderWindows(for: Array(unique))
    }

    static func urlsChanged(_ urls: [URL]) {
        pathsChanged(urls.map(\.path))
    }

    /// Reveal without thrashing: select items if requested, else only refresh.
    static func afterExtract(destination: URL, items: [URL], reveal: Bool) {
        var notify = [destination, destination.deletingLastPathComponent()]
        notify.append(contentsOf: items.prefix(20))
        urlsChanged(notify)

        if reveal {
            let select = items.isEmpty ? [destination] : Array(items.prefix(30))
            // Defer slightly so directory entries are fully settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSWorkspace.shared.activateFileViewerSelecting(select)
            }
        }
    }

    private static func refreshOpenFinderWindows(for paths: [String]) {
        // Best-effort; ignore failures (no Finder, permissions, etc.)
        let posixList = paths
            .filter { !$0.isEmpty }
            .prefix(8)
            .map { $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        guard !posixList.isEmpty else { return }

        let folderExprs = posixList
            .map { "POSIX file \"\($0)\"" }
            .joined(separator: ", ")

        let script = """
        tell application "System Events"
          if not (exists process "Finder") then return
        end tell
        tell application "Finder"
          set folderList to {\(folderExprs)}
          repeat with f in folderList
            try
              update f
            end try
          end repeat
          repeat with w in windows
            try
              set t to target of w as alias
              set tp to POSIX path of t
              repeat with p in {\(posixList.map { "\"\($0)/\"" }.joined(separator: ", "))}
                if tp is p or tp starts with p then
                  try
                    update target of w
                  end try
                end if
              end repeat
            end try
          end repeat
        end tell
        """

        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                _ = appleScript.executeAndReturnError(&error)
            }
        }
    }
}
