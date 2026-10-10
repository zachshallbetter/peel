import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum PeelTab: String, CaseIterable, Identifiable {
    case extract, recent, favorites, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .extract: return "Extract"
        case .recent: return "Recent"
        case .favorites: return "Favorites"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .extract: return "house.fill"
        case .recent: return "clock"
        case .favorites: return "star"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var jobs: JobStore
    @EnvironmentObject private var prefs: PeelPreferences
    @Binding var tab: PeelTab

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 168)
                .frame(maxHeight: .infinity)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Single pane owns scrolling — avoid nested bars fighting the window.
                .clipped()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 820, minHeight: 560)
        .onAppear { appState.syncFromPreferences() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(PeelTab.allCases) { item in
                Button { tab = item } label: {
                    Label(item.title, systemImage: item.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(tab == item ? Color.orange.opacity(0.18) : Color.clear)
                        )
                        .foregroundStyle(tab == item ? Color.orange : Color.primary.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
            Spacer()
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .extract: ExtractHomeView()
        case .recent: RecentView()
        case .favorites: FavoritesView()
        case .settings: SettingsPage()
        }
    }
}

struct ExtractHomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var jobs: JobStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Peel")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("Drop any archive to extract it.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ZStack(alignment: .topTrailing) {
                        Image("OrangeHero")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .shadow(color: .orange.opacity(0.35), radius: 30, y: 10)
                        Text("Unpack\nthe good\nstuff.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.orange.opacity(0.9))
                            .rotationEffect(.degrees(8))
                            .offset(x: 8, y: -4)
                    }
                }

                dropCard

                if let latest = jobs.jobs.first {
                    latestCard(latest)
                }

                recentSection
            }
            .padding(28)
        }
        .background(
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.10, green: 0.11, blue: 0.14), Color(red: 0.07, green: 0.08, blue: 0.10)]
                    : [Color(red: 0.98, green: 0.97, blue: 0.95), Color(red: 0.96, green: 0.94, blue: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var dropCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "archivebox")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop a file here").font(.headline)
            Text("Supports zip, rar, 7z, tar, dmg, app, pdf, exe and more.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button { appState.pickArchive() } label: {
                Text("Choose File…")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.orange))
            .shadow(color: .orange.opacity(0.35), radius: 10, y: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                        .foregroundStyle(appState.isTargeted ? Color.orange : Color.primary.opacity(0.15))
                }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $appState.isTargeted) { providers in
            appState.handleDrop(providers: providers)
        }
    }

    private func latestCard(_ job: PeelJob) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.zipper")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
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
                if let dest = job.destinationPath {
                    Label((dest as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: job.status == .succeeded ? "checkmark.circle.fill" : (job.status == .failed ? "xmark.circle.fill" : "arrow.triangle.2.circlepath"))
                    .foregroundStyle(job.status == .succeeded ? .green : (job.status == .failed ? .red : .orange))
                Text(job.status == .succeeded ? "Extracted" : (job.status == .failed ? "Failed" : "Working"))
                    .font(.caption.weight(.semibold))
            }
            if let dest = job.destinationPath {
                Button {
                    FinderRefresh.afterExtract(destination: URL(fileURLWithPath: dest), items: [URL(fileURLWithPath: dest)], reveal: true)
                } label: { Image(systemName: "folder") }
                .buttonStyle(.bordered)
                Button("Show") {
                    FinderRefresh.afterExtract(destination: URL(fileURLWithPath: dest), items: [URL(fileURLWithPath: dest)], reveal: true)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)) }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                if !jobs.recentSucceeded.isEmpty {
                    Button("Clear") { jobs.clear() }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            if jobs.recentSucceeded.isEmpty {
                Text("Nothing peeled yet.").foregroundStyle(.tertiary).font(.subheadline)
            } else {
                ForEach(jobs.recentSucceeded.prefix(8)) { job in
                    RecentRow(job: job)
                }
            }
        }
    }
}

struct RecentRow: View {
    let job: PeelJob
    @EnvironmentObject private var jobs: JobStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc")
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 2) {
                Text(job.sourceName).lineLimit(1)
                HStack(spacing: 6) {
                    if let n = job.itemCount { Text("\(n) items") }
                    if let b = job.totalBytes {
                        Text("· \(ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let dest = job.destinationPath {
                Button {
                    FinderRefresh.afterExtract(destination: URL(fileURLWithPath: dest), items: [URL(fileURLWithPath: dest)], reveal: true)
                } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless)
            }
            Menu {
                Button(jobs.isFavorite(job.sourcePath) ? "Remove Favorite" : "Add Favorite") {
                    jobs.toggleFavorite(job.sourcePath)
                }
                if let dest = job.destinationPath {
                    Button("Show in Finder") {
                        FinderRefresh.afterExtract(destination: URL(fileURLWithPath: dest), items: [URL(fileURLWithPath: dest)], reveal: true)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.vertical, 6)
    }
}

struct RecentView: View {
    @EnvironmentObject private var jobs: JobStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent").font(.largeTitle.bold())
                Spacer()
                Button("Clear") { jobs.clear() }
            }
            .padding(.horizontal, 28).padding(.top, 24)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(jobs.recentSucceeded) { job in
                        RecentRow(job: job)
                            .padding(.horizontal, 28)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var jobs: JobStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorites").font(.largeTitle.bold())
                .padding(.horizontal, 28).padding(.top, 24)
            if jobs.favorites.isEmpty {
                Text("Star archives from Recent to pin them here.")
                    .foregroundStyle(.secondary).padding(28)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(jobs.favorites, id: \.self) { path in
                            HStack {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                Spacer()
                                Button("Peel") {
                                    NSWorkspace.shared.open(
                                        [URL(fileURLWithPath: path)],
                                        withApplicationAt: Bundle.main.bundleURL,
                                        configuration: NSWorkspace.OpenConfiguration()
                                    )
                                }
                            }
                            .padding(.horizontal, 28)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }
}
