import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Live PeelFS / browse-on-open status + actions for Setup and Settings.
@MainActor
final class PeelFSStatusModel: ObservableObject {
    @Published var moduleRegistered = false
    @Published var moduleEnabled = false
    @Published var extensionPresent = false
    @Published var lastMessage: String?
    @Published var isBusy = false

    func refresh() {
        extensionPresent = Bundle.main
            .builtInPlugInsURL
            .map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("PeelFSExtension.appex").path) }
            ?? FileManager.default.fileExists(
                atPath: Bundle.main.bundleURL
                    .appendingPathComponent("Contents/Extensions/PeelFSExtension.appex").path
            )
        // Also check Extensions folder used by ExtensionKit
        if !extensionPresent {
            let p = Bundle.main.bundleURL.appendingPathComponent("Contents/Extensions/PeelFSExtension.appex")
            extensionPresent = FileManager.default.fileExists(atPath: p.path)
        }
        moduleEnabled = PeelFSMount.isModuleEnabled()
        moduleRegistered = moduleEnabled || isRegistered()
    }

    private func isRegistered() -> Bool {
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
        return text.contains("io.snackstud.peel.PeelFS")
    }

    func enableModule() {
        isBusy = true
        lastMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            PeelFSMount.requestEnable()
            DispatchQueue.main.async {
                self.refresh()
                if self.moduleEnabled {
                    self.lastMessage = "PeelFS marked enabled in PluginKit. If mount still fails, macOS may still block the module — browse cache will be used."
                } else {
                    self.lastMessage = "Could not enable via PluginKit. Use System Settings → Extensions → Peel → FSKit Modules."
                }
                self.isBusy = false
            }
        }
    }

func openSystemSettingsExtensions() {
        // Best-effort deep links (macOS varies by version).
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.Extensions-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                lastMessage = "Opened System Settings. Find Peel → FSKit Modules and turn it on."
                return
            }
        }
        // Fallback: open System Settings app
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        lastMessage = "Open Extensions (or Login Items & Extensions) → Peel → enable FSKit Modules."
    }

    func requestFinderAutomation() {
        let ok = PeelFSMount.requestFinderAutomation(prompt: true)
        // Also poke Finder so TCC records the client even if the determine API is quiet.
        let script = "tell application \"Finder\" to get name"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            _ = appleScript.executeAndReturnError(&error)
        }
        if ok {
            lastMessage = "Finder control allowed. Double-click should stay in the same Finder window."
        } else if error != nil {
            lastMessage = "macOS blocked Finder control. Click Automation Settings… → Peel → enable Finder."
            PeelFSMount.openAutomationSettings()
        } else {
            lastMessage = "If a permission dialog appeared, click OK. Then check Automation → Peel → Finder."
            PeelFSMount.openAutomationSettings()
        }
        // Bring Peel forward so the user sees the message / any prompt.
        AppDelegate.shared?.showMainWindow()
    }
}

struct PeelFSStatusBanner: View {
    @ObservedObject var status: PeelFSStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusDot
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Refresh") { status.refresh() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let msg = status.lastMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(statusBackground)
        }
        .onAppear { status.refresh() }
    }

    private var statusTitle: String {
        if !status.extensionPresent { return "PeelFS extension missing from app" }
        if status.moduleEnabled { return "PeelFS enabled (PluginKit)" }
        if status.moduleRegistered { return "PeelFS installed — needs System Settings toggle" }
        return "PeelFS not registered yet"
    }

    private var statusDetail: String {
        if !status.extensionPresent {
            return "Reinstall Peel.app so Contents/Extensions/PeelFSExtension.appex is present."
        }
        if status.moduleEnabled {
            return "If double-click still doesn’t mount, macOS may block the module; Peel opens a browse folder in Finder instead."
        }
        return "Turn on FSKit Modules under Peel in System Settings → Extensions (or Login Items & Extensions)."
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
    }

    private var dotColor: Color {
        if !status.extensionPresent { return .red }
        if status.moduleEnabled { return .green }
        if status.moduleRegistered { return .orange }
        return .secondary
    }

    private var statusBackground: Color {
        if status.moduleEnabled { return Color.green.opacity(0.08) }
        if status.moduleRegistered { return Color.orange.opacity(0.08) }
        return Color.primary.opacity(0.05)
    }
}

/// Shared controls for browse-on-open + PeelFS enablement.
struct PeelBrowseAndFSKitSection: View {
    @ObservedObject var prefs: PeelPreferences
    @ObservedObject var status: PeelFSStatusModel
    var showAdvancedExtractFallback: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Double-click opens archives in Finder like a folder (Windows-style). Right-click → Services → Peel extracts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PeelFSStatusBanner(status: status)

            Toggle("Browse on double-click / Open With", isOn: $prefs.browseOnOpen)

            Text(browseExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

HStack(spacing: 10) {
                Button {
                    status.enableModule()
                } label: {
                    if status.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Enable PeelFS")
                    }
                }
                .disabled(status.isBusy)

                Button("Open System Settings…") {
                    status.openSystemSettingsExtensions()
                }
            }

            HStack(spacing: 10) {
                Button("Allow Finder Control…") {
                    status.requestFinderAutomation()
                }
                Button("Automation Settings…") {
                    PeelFSMount.openAutomationSettings()
                }
            }
            Text("Same-window browse needs Automation → Peel → Finder. Click Allow Finder Control once; approve the system prompt, then enable Finder under Peel.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Make Peel the default app for zip, rar, 7z…", isOn: $prefs.claimDefaultHandler)

            if showAdvancedExtractFallback {
                Divider().padding(.vertical, 4)
                Text("Services & extract")
                    .font(.subheadline.weight(.semibold))
                Toggle("Services extract with progress popup only (no main window)", isOn: $prefs.silentBackgroundExtract)
                Text("Dropping a file on the Peel window always extracts. Browse-on-open never full-extracts unless you use Services.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var browseExplanation: String {
        """
        Peel tries a real PeelFS mount first. If macOS leaves the module disabled, it opens a folder next to the archive (or under Application Support if that name is taken). Finder stays in the same window when Automation is allowed.
        """
    }
}
