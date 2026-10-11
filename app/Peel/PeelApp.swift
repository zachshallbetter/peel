import SwiftUI
import AppKit

@main
struct PeelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var prefs = PeelPreferences.shared
    @StateObject private var jobs = JobStore.shared
    @State private var showSetup = false

    var body: some Scene {
WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(prefs)
                .environmentObject(jobs)
                .background(SilentWindowGuard())
                .background(StandardWindowChrome())
// AppDelegate.application(_:open:) owns Finder double-click / Open With.
                // Handling the same file URL here too opened the folder twice and
                // often produced a second Finder tab via the fallback path.
                .onOpenURL { url in
                    if url.isFileURL { return }
                    appDelegate.appState = appState
                    appDelegate.prefs = prefs
                    appState.enqueueOpen(url)
                }
                .onAppear {
                    appDelegate.appState = appState
                    appDelegate.prefs = prefs
                    appState.syncFromPreferences()
                    if AppDelegate.shared?.shouldSuppressMainWindow == true {
                        AppDelegate.shared?.hideMainWindows()
                        // Never flash setup during Open With / double-click browse.
                        showSetup = false
                        return
                    }
                    if !prefs.didCompleteSetup {
                        showSetup = true
                    }
                }
                .onChange(of: prefs.didCompleteSetup) { done in
                    if !done && AppDelegate.shared?.shouldSuppressMainWindow != true {
                        showSetup = true
                    }
                }
                .sheet(isPresented: $showSetup) {
                    SetupView(prefs: prefs) {
                        showSetup = false
                        prefs.didCompleteSetup = true
                        appState.syncFromPreferences()
                    }
                }
        }
        // Don't spawn a WindowGroup instance for external file opens.
        .handlesExternalEvents(matching: [])
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Open…") { appState.pickArchive() }
                    .keyboardShortcut("o", modifiers: [.command])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .peelOpenSettings, object: nil)
                    AppDelegate.shared?.showMainWindow()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandMenu("Peel") {
                Button("Show Peel Window") {
                    AppDelegate.shared?.showMainWindow()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let peelOpenSettings = Notification.Name("peel.openSettings")
}

/// Keeps the main SwiftUI window ordered out while silent extract is active.
struct SilentWindowGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if AppDelegate.shared?.shouldSuppressMainWindow == true {
                AppDelegate.shared?.hideMainWindows()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if AppDelegate.shared?.shouldSuppressMainWindow == true {
            AppDelegate.shared?.hideMainWindows()
            if let window = nsView.window, !(window is NSPanel) {
                window.orderOut(nil)
                window.alphaValue = 0
                window.ignoresMouseEvents = true
            }
        } else if let window = nsView.window, !(window is NSPanel) {
            window.alphaValue = 1
            window.ignoresMouseEvents = false
        }
    }
}


/// Normal macOS window chrome (title visible, opaque background).
struct StandardWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { Self.apply(v.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        Self.apply(nsView.window)
    }
    private static func apply(_ window: NSWindow?) {
        guard let w = window else { return }
        w.titlebarAppearsTransparent = false
        w.titleVisibility = .visible
        w.isOpaque = true
        w.backgroundColor = .windowBackgroundColor
        w.title = "Peel"
        if w.styleMask.contains(.fullSizeContentView) {
            w.styleMask.remove(.fullSizeContentView)
        }
    }
}
