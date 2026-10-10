import SwiftUI
import AppKit

struct SettingsPage: View {
    @EnvironmentObject private var prefs: PeelPreferences
    @State private var note: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.largeTitle.bold())

                group("Double-click / Open With") {
                    Toggle("Extract without opening a window (quick popup only)", isOn: $prefs.silentBackgroundExtract)
                    Toggle("Also open the main Peel window", isOn: $prefs.openWindowOnDrop)
                        .disabled(prefs.silentBackgroundExtract)
                    Text("Right-click extract uses the compact progress popup — like Archive Utility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                group("Extraction") {
                    Toggle("Peel beside the original file", isOn: $prefs.extractBesideSource)
                    Toggle("Reveal folder in Finder when done", isOn: $prefs.revealAfterExtract)
                    Toggle("Delete archive after successful extract", isOn: $prefs.deleteArchiveAfterExtract)
                    if !prefs.extractBesideSource {
                        HStack {
                            Text(prefs.fixedDestinationPath ?? "No folder selected")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button("Choose…") { chooseFolder() }
                        }
                    }
                }

                group("Finder") {
                    Toggle("Claim default handler for zip, rar, 7z…", isOn: $prefs.claimDefaultHandler)
                    Button("Apply default handler now") {
                        prefs.claimDefaultHandler = true
                        prefs.applyDefaultHandlerClaim()
                        note = "Default handler updated."
                    }
                    Toggle("Install “Peel Here” service", isOn: $prefs.installFinderService)
                    Button("Install / repair Finder service") {
                        prefs.installFinderService = true
                        prefs.runFinderServiceInstallIfNeeded()
                        note = "Service install attempted."
                    }
                    Text("Or: file → Get Info → Open with → Peel → Change All…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                group("Setup") {
                    Button("Run quick setup again…") {
                        prefs.didCompleteSetup = false
                    }
                    if let note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }

                group("About") {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Peel").font(.headline)
                            Text("Open what's inside.").foregroundStyle(.secondary)
                            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
        }
    }

    private func chooseFolder() {
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
