import SwiftUI
import AppKit

@main
struct PeelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var prefs = PeelPreferences.shared
    @StateObject private var jobs = JobStore.shared
    @State private var showSetup = false
    @State private var selectedTab: PeelTab = .extract

    var body: some Scene {
        WindowGroup {
            ContentView(tab: $selectedTab)
                .environmentObject(appState)
                .environmentObject(prefs)
                .environmentObject(jobs)
                .onOpenURL { url in
                    appState.enqueueOpen(url)
                }
                .onAppear {
                    appDelegate.appState = appState
                    appDelegate.prefs = prefs
                    appState.syncFromPreferences()
                    if AppDelegate.shared?.shouldSuppressMainWindow == true {
                        AppDelegate.shared?.hideMainWindows()
                    }
                    if !prefs.didCompleteSetup && AppDelegate.shared?.shouldSuppressMainWindow != true {
                        showSetup = true
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .peelOpenSettings)) { _ in
                    selectedTab = .settings
                    AppDelegate.shared?.showMainWindow()
                }
                .sheet(isPresented: $showSetup) {
                    SetupView(prefs: prefs) {
                        showSetup = false
                        appState.syncFromPreferences()
                    }
                }
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Open…") { appState.pickArchive() }
                    .keyboardShortcut("o", modifiers: [.command])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .peelOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandMenu("Peel") {
                Button("Show Peel Window") {
                    AppDelegate.shared?.showMainWindow()
                }
                .keyboardShortcut("0", modifiers: [.command])
                Button("Settings") {
                    NotificationCenter.default.post(name: .peelOpenSettings, object: nil)
                }
            }
        }
        // Settings live in the main window right pane — no separate Settings scene.
    }
}

extension Notification.Name {
    static let peelOpenSettings = Notification.Name("peel.openSettings")
}
