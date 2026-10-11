import SwiftUI
import AppKit

struct SettingsPage: View {
    @EnvironmentObject private var prefs: PeelPreferences
    @StateObject private var fskitStatus = PeelFSStatusModel()
    @State private var note: String?
    @State private var showSetup = false
    @State private var cacheStats = PeelFSMount.cacheStats()

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.largeTitle.bold())

                group("Browse & PeelFS") {
                    PeelBrowseAndFSKitSection(
                        prefs: prefs,
                        status: fskitStatus,
                        showAdvancedExtractFallback: true
                    )
                    Button("Apply as default handler now") {
                        prefs.claimDefaultHandler = true
                        prefs.applyDefaultHandlerClaim()
                        note = "Peel is now the default for supported archives (where macOS allows)."
                    }
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

                group("Browse cache") {
                    Text(cacheSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Browse folders are created next to the archive when possible (else under Application Support). They expire after 24 hours and are capped at about 2 GB total. Clear anytime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button("Clear Cache") {
                            clearCache()
                        }
                        .disabled(cacheStats.volumeCount == 0 && cacheStats.totalBytes == 0)
                        .accessibilityIdentifier("clearBrowseCache")
                        .accessibilityLabel("Clear Cache")
                        Button("Show in Finder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: cacheStats.path))
                        }
                        .accessibilityIdentifier("showBrowseCache")
                        Button("Refresh") {
                            refreshCacheStats()
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("refreshBrowseCache")
                    }
                    if let note, note.hasPrefix("Cache") {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }

                group("Finder Services") {
                    Toggle("Install Peel / Peel to… / Peel & Reveal", isOn: $prefs.installFinderService)
                    Button("Install / repair Finder service") {
                        prefs.installFinderService = true
                        prefs.runFinderServiceInstallIfNeeded()
                        note = "Service install attempted."
                    }
                    Text("Services always extract. Double-click uses Browse & PeelFS above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                group("Setup") {
                    Button("Run setup assistant again…") {
                        showSetup = true
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
                            Link("Snack Studio", destination: URL(string: "https://snackstud.io")!)
                                .font(.caption)
                            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .onAppear {
            fskitStatus.refresh()
            refreshCacheStats()
        }
        .sheet(isPresented: $showSetup) {
            SetupView(prefs: prefs) {
                showSetup = false
                fskitStatus.refresh()
            }
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

    private var cacheSummary: String {
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(cacheStats.totalBytes), countStyle: .file)
        if cacheStats.volumeCount == 0 {
            return "No browse volumes cached."
        }
        var s = "\(cacheStats.volumeCount) volume\(cacheStats.volumeCount == 1 ? "" : "s") · \(bytes)"
        if let oldest = cacheStats.oldestAccess {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .short
            s += " · oldest \(rel.localizedString(for: oldest, relativeTo: Date()))"
        }
        return s
    }

    private func refreshCacheStats() {
        cacheStats = PeelFSMount.cacheStats()
    }

    private func clearCache() {
        let result = PeelFSMount.clearAllBrowseVolumes()
        refreshCacheStats()
        let freed = ByteCountFormatter.string(fromByteCount: Int64(result.freedBytes), countStyle: .file)
        note = "Cache cleared — removed \(result.removed) folder\(result.removed == 1 ? "" : "s"), freed \(freed)."
    }
}
