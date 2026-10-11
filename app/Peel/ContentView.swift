import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var jobs: JobStore
    @EnvironmentObject private var prefs: PeelPreferences
    @State private var showSettings = false

    var body: some View {
        ExtractHomeView(showSettings: $showSettings)
            .frame(minWidth: 640, minHeight: 480)
            .background(GoldenGate.pageBackground)
            .onAppear { appState.syncFromPreferences() }
            .onReceive(NotificationCenter.default.publisher(for: .peelOpenSettings)) { _ in
                showSettings = true
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsPage()
                        .environmentObject(prefs)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
                .frame(minWidth: 520, minHeight: 480)
            }
    }
}

struct ExtractHomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var jobs: JobStore
    @Binding var showSettings: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                header
                dropCard
                if let latest = jobs.jobs.first {
                    latestCard(latest)
                }
                recentSection
                footerBrand
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Peel")
                    .font(.system(size: 28, weight: .bold))
                Text("Double-click a ZIP to open it as a folder (PeelFS). Drop here or use Services to extract.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                GlassIconButton(systemName: "gearshape") {
                    showSettings = true
                }
                .help("Settings")

                Image("OrangeHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
            }
        }
    }

    private var dropCard: some View {
        GlassCard(padding: 24) {
            VStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop a file here")
                    .font(.headline)
                Text("zip · rar · 7z · tar · dmg · app · pdf · exe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Choose File…") { appState.pickArchive() }
                    .buttonStyle(GlassPrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: GoldenGate.corner, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: appState.isTargeted ? 2 : 1, dash: [7, 5])
                )
                .foregroundStyle(appState.isTargeted ? GoldenGate.accent : Color.primary.opacity(0.12))
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $appState.isTargeted) { providers in
            appState.handleDrop(providers: providers)
        }
    }

    private func latestCard(_ job: PeelJob) -> some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "doc.zipper")
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.sourceName).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        if let n = job.itemCount { Text("\(n) items") }
                        if let b = job.totalBytes {
                            Text("·")
                            Text(ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if job.status == .failed, let err = job.errorMessage, !err.isEmpty {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    } else if let dest = job.destinationPath {
                        Text((dest as NSString).abbreviatingWithTildeInPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if job.status == .running {
                        ProgressView(value: max(0.02, min(0.99, job.progress)))
                            .tint(.orange)
                        Text("Large archives can take several minutes — Peel is still working.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                statusChip(job)
                if let dest = job.destinationPath, job.status == .succeeded {
                    Button {
                        FinderRefresh.afterExtract(
                            destination: URL(fileURLWithPath: dest),
                            items: [URL(fileURLWithPath: dest)],
                            reveal: true
                        )
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func statusChip(_ job: PeelJob) -> some View {
        let label: String
        let color: Color
        switch job.status {
        case .succeeded: label = "Extracted"; color = .green
        case .failed: label = "Failed"; color = .red
        case .cancelled: label = "Cancelled"; color = .secondary
        case .running, .queued: label = "Working"; color = .orange
        }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private var recentSection: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent").font(.headline)
                    Spacer()
                    if !jobs.recentSucceeded.isEmpty {
                        Button("Clear") { jobs.clear() }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                if jobs.recentSucceeded.isEmpty {
                    Text("Nothing peeled yet.")
                        .foregroundStyle(.tertiary)
                        .font(.subheadline)
                } else {
                    ForEach(jobs.recentSucceeded.prefix(12)) { job in
                        RecentRow(job: job)
                    }
                }
            }
        }
    }

    private var footerBrand: some View {
        HStack {
            Spacer()
            Link("Snack Studio", destination: URL(string: "https://snackstud.io")!)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.top, 4)
    }
}

struct RecentRow: View {
    let job: PeelJob
    @EnvironmentObject private var jobs: JobStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.status == .failed ? "exclamationmark.triangle" : "doc")
                .frame(width: 28, height: 28)
                .foregroundStyle(job.status == .failed ? .red : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.sourceName).lineLimit(1)
                if job.status == .failed, let err = job.errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else {
                    HStack(spacing: 6) {
                        if let n = job.itemCount { Text("\(n) items") }
                        if let b = job.totalBytes {
                            Text("· \(ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file))")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let dest = job.destinationPath, job.status == .succeeded {
                Button {
                    FinderRefresh.afterExtract(
                        destination: URL(fileURLWithPath: dest),
                        items: [URL(fileURLWithPath: dest)],
                        reveal: true
                    )
                } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless)
            }
            Menu {
                Button(jobs.isFavorite(job.sourcePath) ? "Remove Favorite" : "Add Favorite") {
                    jobs.toggleFavorite(job.sourcePath)
                }
                if let dest = job.destinationPath {
                    Button("Show in Finder") {
                        FinderRefresh.afterExtract(
                            destination: URL(fileURLWithPath: dest),
                            items: [URL(fileURLWithPath: dest)],
                            reveal: true
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.vertical, 4)
    }
}
