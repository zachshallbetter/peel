import AppKit
import UserNotifications
import UniformTypeIdentifiers

/// Finder Open With / Services handler.
/// Background extract runs as a **passive OS enhancement**: no Dock icon, no main window,
/// only the compact HUD. Interactive UI appears only when the user opens Peel deliberately.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var pendingURLs: [URL] = []
    private var launchedWithFiles = false
    /// True while we are in background-extract mode (no Dock / no main window).
    private(set) var isPassive = false
    var shouldSuppressMainWindow = false
    var appState: AppState?
    var prefs: PeelPreferences?

    private var serviceForceReveal: Bool?
    private var serviceDestination: URL?
    private var idleQuitWorkItem: DispatchWorkItem?
    /// Active silent jobs; when zero, schedule idle quit in passive mode.
    private var silentJobCount = 0
    /// Browse-on-open jobs (no HUD); keep process alive until Finder nav finishes.
    private var browseJobCount = 0

    override init() {
        super.init()
        AppDelegate.shared = self
    }

func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let isOpenDocs = event?.eventClass == AEEventClass(kCoreEventClass)
            && event?.eventID == AEEventID(kAEOpenDocuments)
        // Also catch launches where argv lists archive paths (some Open With paths).
        let argvHasArchive = CommandLine.arguments.dropFirst().contains { arg in
            let ext = (arg as NSString).pathExtension.lowercased()
            return ["zip", "cbz", "rar", "cbr", "7z", "tar", "gz", "tgz", "tbz2", "bz2", "dmg"].contains(ext)
        }
        if isOpenDocs || argvHasArchive {
            launchedWithFiles = true
            shouldSuppressMainWindow = true
            isPassive = true
            // Must run before AppKit materializes a Dock tile / main window.
            _ = NSApp.setActivationPolicy(.accessory)
            NSApp.windows.forEach { w in
                guard !(w is NSPanel) else { return }
                w.alphaValue = 0
                w.ignoresMouseEvents = true
                w.orderOut(nil)
            }
        }
        // Hide any windows the moment they become key during passive open (macOS 13-safe).
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, self.shouldSuppressMainWindow else { return }
            guard let window = note.object as? NSWindow else { return }
            if window is NSPanel { return }
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.orderOut(nil)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didExposeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, self.shouldSuppressMainWindow else { return }
            guard let window = note.object as? NSWindow else { return }
            if window is NSPanel { return }
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.orderOut(nil)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Prevent empty WindowGroup flash when launched via Open With / double-click.
        !launchedWithFiles && !shouldSuppressMainWindow
    }

func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        // Browse-volume TTL / size budget (Application Support, not /tmp).
        // Test hooks: PEEL_CLEAR_CACHE=1 wipes volumes; maintenance always runs.
        // PEEL_REQUEST_FINDER_AUTOMATION=1 forces the Automation prompt (dev/setup).
        DispatchQueue.global(qos: .utility).async {
            if ProcessInfo.processInfo.environment["PEEL_CLEAR_CACHE"] == "1" {
                _ = PeelFSMount.clearAllBrowseVolumes()
            }
            PeelFSMount.performMaintenance()
            if ProcessInfo.processInfo.environment["PEEL_REQUEST_FINDER_AUTOMATION"] == "1" {
                DispatchQueue.main.async {
                    _ = PeelFSMount.requestFinderAutomation(prompt: true)
                    let script = "tell application \"Finder\" to get name"
                    var error: NSDictionary?
                    if let appleScript = NSAppleScript(source: script) {
                        _ = appleScript.executeAndReturnError(&error)
                    }
                }
            }
        }

NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.shouldSuppressMainWindow else { return }
                self.hideMainWindows()
            }
        }

        // Notifications optional; don't prompt during passive extract.
        if !isPassive {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        if launchedWithFiles || !pendingURLs.isEmpty {
            // Browse-on-open (PeelFS) and silent extract both stay out of the Dock/window.
            let browse = prefs?.browseOnOpen ?? true
            let silent = prefs?.silentBackgroundExtract ?? true
            shouldSuppressMainWindow = browse || (silent && !(prefs?.openWindowOnDrop ?? false))
            if shouldSuppressMainWindow {
                enterPassiveMode()
                hideMainWindows()
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.launchedWithFiles || !self.pendingURLs.isEmpty {
                let browse = self.prefs?.browseOnOpen ?? true
                let silent = self.prefs?.silentBackgroundExtract ?? true
                self.shouldSuppressMainWindow = browse || (silent && !(self.prefs?.openWindowOnDrop ?? false))
                if self.shouldSuppressMainWindow {
                    self.enterPassiveMode()
                    self.hideMainWindows()
                    self.drainPending(activate: false)
                } else {
                    self.enterInteractiveMode()
                    self.drainPending(activate: true)
                }
            }
        }
    }

    // MARK: - Passive vs interactive

    @MainActor
    func enterPassiveMode() {
        isPassive = true
        shouldSuppressMainWindow = true
        // Removes Dock icon and app switcher presence — feels like an OS helper.
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        hideMainWindows()
        cancelIdleQuit()
    }

    @MainActor
    func enterInteractiveMode() {
        cancelIdleQuit()
        isPassive = false
        shouldSuppressMainWindow = false
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.unhide(nil)
    }

    /// Called by AppState when a silent extract starts/ends.
    @MainActor
    func noteSilentJobStarted() {
        silentJobCount += 1
        cancelIdleQuit()
        enterPassiveMode()
    }

    @MainActor
    func noteSilentJobFinished() {
        silentJobCount = max(0, silentJobCount - 1)
        scheduleIdleQuitIfNeeded()
    }

    @MainActor
    func noteBrowseJobStarted() {
        browseJobCount += 1
        cancelIdleQuit()
        enterPassiveMode()
        hideMainWindows()
    }

    @MainActor
    func noteBrowseJobFinished() {
        browseJobCount = max(0, browseJobCount - 1)
        scheduleIdleQuitIfNeeded()
    }

    @MainActor
    private func scheduleIdleQuitIfNeeded() {
        guard isPassive, shouldSuppressMainWindow else { return }
        guard silentJobCount == 0, browseJobCount == 0 else { return }
        // Also wait until AppState reports idle.
        if appState?.isWorking == true { return }

        cancelIdleQuit()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.isPassive, self.shouldSuppressMainWindow else { return }
                guard self.silentJobCount == 0, self.browseJobCount == 0, self.appState?.isWorking != true else { return }
                // HUD may still be visible briefly — allow it, then terminate.
                // Keep process only if a progress panel is still up with running job.
                let hasLiveHUD = ProgressPanelController.shared.hasVisiblePanels
                if hasLiveHUD {
                    self.scheduleIdleQuitIfNeeded()
                    return
                }
                NSApp.terminate(nil)
            }
        }
        idleQuitWorkItem = work
        // After HUD auto-dismiss (~5s success); give a little headroom.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5, execute: work)
    }

    @MainActor
    private func cancelIdleQuit() {
        idleQuitWorkItem?.cancel()
        idleQuitWorkItem = nil
    }

    // MARK: - NSServices

    @objc func peelServiceExtract(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        handleService(pboard: pboard, error: error, reveal: false, pickDestination: false)
    }

    @objc func peelServiceExtractTo(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        handleService(pboard: pboard, error: error, reveal: true, pickDestination: true)
    }

    @objc func peelServiceExtractReveal(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        handleService(pboard: pboard, error: error, reveal: true, pickDestination: false)
    }

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
                // Folder picker requires a momentary interactive presence.
                self.enterInteractiveMode()
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "Peel to This Folder"
                panel.message = "Choose where Peel should put the extracted files."
                if let parent = urls.first?.deletingLastPathComponent() {
                    panel.directoryURL = parent
                }
                NSApp.activate(ignoringOtherApps: true)
                guard panel.runModal() == .OK, let url = panel.url else {
                    // User cancelled picker — return to passive if we weren't interactive before.
                    self.enterPassiveMode()
                    return
                }
                dest = url
                // Back to passive for the extract itself.
                self.enterPassiveMode()
            }

            self.serviceForceReveal = reveal
            self.serviceDestination = dest
            let silent = (self.prefs?.silentBackgroundExtract ?? true) && !(self.prefs?.openWindowOnDrop ?? false)
            self.shouldSuppressMainWindow = silent
            self.enterPassiveMode()
            self.hideMainWindows()

            if let appState = self.appState {
                for url in urls {
                    appState.extract(
                        archive: url,
                        silent: true,
                        destinationOverride: dest,
                        revealOverride: reveal
                    )
                }
            } else {
                self.pendingURLs.append(contentsOf: urls)
                self.launchedWithFiles = true
                self.drainPending(activate: false)
            }

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
        // Dedupe paths — LS sometimes delivers the same open twice.
        var seen = Set(pendingURLs.map { $0.standardizedFileURL.path })
        for url in urls {
            let p = url.standardizedFileURL.path
            if seen.insert(p).inserted {
                pendingURLs.append(url)
            }
        }
        // Prefer accessory immediately so Dock doesn't flash for Open With / Services / PeelFS browse.
        let browsePref = UserDefaults.standard.object(forKey: "peel.browseOnOpen") as? Bool ?? true
        let silentPref = UserDefaults.standard.object(forKey: "peel.silentBackgroundExtract") as? Bool ?? true
        let openWindow = UserDefaults.standard.object(forKey: "peel.openWindowOnDrop") as? Bool ?? false
        if browsePref || (silentPref && !openWindow) {
            shouldSuppressMainWindow = true
            isPassive = true
            _ = NSApp.setActivationPolicy(.accessory)
        }
        Task { @MainActor in
            let browse = self.prefs?.browseOnOpen ?? true
            let silent = self.prefs?.silentBackgroundExtract ?? true
            let show = (self.prefs?.openWindowOnDrop ?? false) && !silent && !browse
            if show {
                self.enterInteractiveMode()
                self.showMainWindow()
                self.drainPending(activate: true)
            } else {
                self.enterPassiveMode()
                self.hideMainWindows()
                self.drainPending(activate: false)
            }
        }
    }

    /// Dock icon click / reopen — only path that forces interactive UI (when Dock is visible).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            self.enterInteractiveMode()
            if !flag {
                self.showMainWindow()
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // In interactive mode, keep running (like a normal app) until quit.
        // Passive mode uses explicit idle terminate.
        false
    }

    @MainActor
    func hideMainWindows() {
        for window in NSApp.windows {
            if window is NSPanel { continue }
            if window.level == .floating || window.level == .statusBar { continue }
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.orderOut(nil)
        }
    }

    @MainActor
    func showMainWindow() {
        enterInteractiveMode()
        if let win = NSApp.windows.first(where: {
            !($0 is NSPanel) && $0.level != .floating && $0.level != .statusBar
        }) {
            win.alphaValue = 1
            win.ignoresMouseEvents = false
            win.makeKeyAndOrderFront(nil)
        } else if let win = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            win.alphaValue = 1
            win.ignoresMouseEvents = false
            win.makeKeyAndOrderFront(nil)
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
            enterInteractiveMode()
            showMainWindow()
        } else {
            enterPassiveMode()
            hideMainWindows()
        }

        let dest = serviceDestination
        let reveal = serviceForceReveal
        for url in urls {
            // Double-click / Open With → enqueueOpen (PeelFS browse when enabled).
            // Services that set reveal/dest still force extract.
            if dest != nil || reveal != nil {
                appState.extract(
                    archive: url,
                    silent: !activate,
                    destinationOverride: dest,
                    revealOverride: reveal
                )
            } else {
                appState.enqueueOpen(url)
            }
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
