import AppKit
import UserNotifications
import UniformTypeIdentifiers

/// Handles Finder Open With / Services / double-click without forcing the main window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var pendingURLs: [URL] = []
    private var launchedWithFiles = false
    var shouldSuppressMainWindow = false
    var appState: AppState?
    var prefs: PeelPreferences?

    /// One-shot overrides applied to the next service-driven extracts.
    private var serviceForceReveal: Bool?
    private var serviceDestination: URL?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        if let event, event.eventClass == AEEventClass(kCoreEventClass),
           event.eventID == AEEventID(kAEOpenDocuments) {
            launchedWithFiles = true
            shouldSuppressMainWindow = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        if launchedWithFiles || !pendingURLs.isEmpty {
            shouldSuppressMainWindow = prefs?.silentBackgroundExtract ?? true
            if shouldSuppressMainWindow {
                hideMainWindows()
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.launchedWithFiles || !self.pendingURLs.isEmpty {
                let silent = self.prefs?.silentBackgroundExtract ?? true
                self.shouldSuppressMainWindow = silent && !(self.prefs?.openWindowOnDrop ?? false)
                if self.shouldSuppressMainWindow {
                    self.hideMainWindows()
                    self.drainPending(activate: false)
                } else {
                    self.drainPending(activate: true)
                }
            }
        }
    }

    // MARK: - NSServices (Finder → Services)

    /// Services → Peel  (extract beside source, compact HUD)
    @objc func peelServiceExtract(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        handleService(pboard: pboard, error: error, reveal: false, pickDestination: false)
    }

    /// Services → Peel to…  (choose folder, then extract)
    @objc func peelServiceExtractTo(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        handleService(pboard: pboard, error: error, reveal: true, pickDestination: true)
    }

    /// Services → Peel & Reveal  (extract + show in Finder)
    @objc func peelServiceExtractReveal(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        handleService(pboard: pboard, error: error, reveal: true, pickDestination: false)
    }

    /// Backward-compatible alias if an old workflow still targets this selector.
    @objc func extractWithPeelService(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        peelServiceExtract(pboard, userData: userData, error: error)
    }

    private func handleService(
        pboard: NSPasteboard,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?,
        reveal: Bool,
        pickDestination: Bool
    ) {
        let urls = Self.fileURLs(from: pboard)
        guard !urls.isEmpty else {
            error?.pointee = "No files selected" as NSString
            return
        }

        Task { @MainActor in
            var dest: URL? = nil
            if pickDestination {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "Peel to This Folder"
                panel.message = "Choose where Peel should put the extracted files."
                // Seed near first archive
                if let parent = urls.first?.deletingLastPathComponent() {
                    panel.directoryURL = parent
                }
                NSApp.activate(ignoringOtherApps: true)
                guard panel.runModal() == .OK, let url = panel.url else { return }
                dest = url
            }

            self.serviceForceReveal = reveal
            self.serviceDestination = dest
            // Service path is always HUD-style unless user asked for window.
            let silent = (self.prefs?.silentBackgroundExtract ?? true) && !(self.prefs?.openWindowOnDrop ?? false)
            self.shouldSuppressMainWindow = silent && dest == nil
            if self.shouldSuppressMainWindow {
                self.hideMainWindows()
            }

            if let appState = self.appState {
                for url in urls {
                    appState.extract(
                        archive: url,
                        silent: silent || dest != nil,
                        destinationOverride: dest,
                        revealOverride: reveal
                    )
                }
            } else {
                self.pendingURLs.append(contentsOf: urls)
                self.launchedWithFiles = true
                self.drainPending(activate: !silent)
            }

            // Clear one-shots after kickoff
            self.serviceForceReveal = nil
            self.serviceDestination = nil
        }
    }

    private static func fileURLs(from pboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []
        if let items = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls.append(contentsOf: items.map { URL(fileURLWithPath: $0) })
        }
        if urls.isEmpty,
           let reading = pboard.readObjects(forClasses: [NSURL.self], options: [
               .urlReadingFileURLsOnly: true
           ]) as? [URL] {
            urls.append(contentsOf: reading)
        }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        launchedWithFiles = true
        pendingURLs.append(contentsOf: urls)
        Task { @MainActor in
            let silent = self.prefs?.silentBackgroundExtract ?? true
            let show = (self.prefs?.openWindowOnDrop ?? false) && !silent
            self.shouldSuppressMainWindow = !show
            if show {
                NSApp.activate(ignoringOtherApps: true)
                self.showMainWindow()
                self.drainPending(activate: true)
            } else {
                self.hideMainWindows()
                self.drainPending(activate: false)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        shouldSuppressMainWindow = false
        if !flag {
            Task { @MainActor in self.showMainWindow() }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    func hideMainWindows() {
        for window in NSApp.windows {
            if window is NSPanel { continue }
            if window.level == .floating || window.level == .statusBar { continue }
            window.orderOut(nil)
        }
    }

    @MainActor
    func showMainWindow() {
        shouldSuppressMainWindow = false
        if let win = NSApp.windows.first(where: {
            !($0 is NSPanel) && $0.level != .floating && $0.level != .statusBar
        }) {
            win.makeKeyAndOrderFront(nil)
        } else {
            NSApp.windows.first(where: { !($0 is NSPanel) })?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func drainPending(activate: Bool) {
        guard let appState else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                Task { @MainActor in
                    self?.drainPending(activate: activate)
                }
            }
            return
        }
        let urls = pendingURLs
        pendingURLs.removeAll()
        guard !urls.isEmpty else { return }

        if activate {
            NSApp.activate(ignoringOtherApps: true)
            showMainWindow()
        } else {
            hideMainWindows()
        }

        let dest = serviceDestination
        let reveal = serviceForceReveal
        for url in urls {
            appState.extract(
                archive: url,
                silent: !activate,
                destinationOverride: dest,
                revealOverride: reveal
            )
        }
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
