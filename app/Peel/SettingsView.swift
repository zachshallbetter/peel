import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var prefs: PeelPreferences
    @State private var handlerNote: String?

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            integration.tabItem { Label("Finder", systemImage: "folder") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 380)
    }

    private var general: some View {
        Form {
            Section("Double-click behavior") {
                Toggle("Extract without opening a window", isOn: $prefs.silentBackgroundExtract)
                Toggle("Bring Peel to the front when opening files", isOn: $prefs.openWindowOnDrop)
                    .disabled(prefs.silentBackgroundExtract)
            }
            Section("Extraction") {
                Toggle("Peel beside the original file", isOn: $prefs.extractBesideSource)
                Toggle("Reveal in Finder when finished", isOn: $prefs.revealAfterExtract)
                if !prefs.extractBesideSource {
                    HStack {
                        Text("Fixed folder")
                        Spacer()
                        Text(prefs.fixedDestinationPath ?? "None")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button("Choose…") { chooseFixedFolder() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var integration: some View {
        Form {
            Section("Default app") {
                Toggle("Claim default handler for archives", isOn: $prefs.claimDefaultHandler)
                Button("Apply default handler now") {
                    prefs.claimDefaultHandler = true
                    prefs.applyDefaultHandlerClaim()
                    handlerNote = "Default handler updated. New double-clicks should use Peel."
                }
                Text("Or: select a file → Get Info → Open with → Peel → Change All…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let handlerNote {
                    Text(handlerNote).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Quick menu") {
                Toggle("Keep “Peel Here” service installed", isOn: $prefs.installFinderService)
                Button("Install / repair Finder service") {
                    prefs.installFinderService = true
                    prefs.runFinderServiceInstallIfNeeded()
                    handlerNote = "Service install attempted."
                }
            }
            Section {
                Button("Run quick setup again…") {
                    prefs.didCompleteSetup = false
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var about: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Peel").font(.title2.weight(.semibold))
            Text("Open what's inside.").foregroundStyle(.secondary)
            Text("Double-click extracts without opening a window — like Archive Utility.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseFixedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.fixedDestinationURL = url
        prefs.extractBesideSource = false
    }
}
