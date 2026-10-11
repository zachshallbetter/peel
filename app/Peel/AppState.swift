import SwiftUI
import UniformTypeIdentifiers
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var status = "Drop an archive"
    @Published var detail: String?
    @Published var isWorking = false
    @Published var isTargeted = false
    @Published var lastOutputFolder: URL?

private let prefs = PeelPreferences.shared
    private let jobs = JobStore.shared
    private var queue: [URL] = []
    private var activeJobId: UUID?
    private var progressTimer: Timer?
    private var cancelledJobIds: Set<UUID> = []
    /// In-flight browse opens (standardized paths) — Launch Services can deliver twice.
    private var browseInFlight: Set<String> = []

    init() {
        DispatchQueue.main.async {
            AppDelegate.shared?.appState = self
            AppDelegate.shared?.prefs = PeelPreferences.shared
        }
    }

    func syncFromPreferences() {
        AppDelegate.shared?.appState = self
        AppDelegate.shared?.prefs = prefs
    }

    /// Finder double-click / Open With.
    /// Default: mount with PeelFS and open the folder in Finder (no full extract).
    /// Falls back to extract if PeelFS is unavailable or format is unsupported.
func enqueueOpen(_ url: URL) {
        if prefs.browseOnOpen, PeelFSMount.supportsBrowse(url) {
            let key = url.standardizedFileURL.path
            if browseInFlight.contains(key) {
                return
            }
            browseInFlight.insert(key)

            // Snapshot Finder window *before* background work so we can retarget
            // the same tab (archive-as-folder feel) instead of opening a new one.
            let finderCtx = PeelFSMount.captureFinderContext(for: url)
            Task.detached(priority: .userInitiated) {
                await MainActor.run {
                    AppDelegate.shared?.noteBrowseJobStarted()
                    AppDelegate.shared?.hideMainWindows()
                }
                defer {
                    Task { @MainActor in
                        self.browseInFlight.remove(key)
                    }
                }
                do {
                    let location = try await Task.detached(priority: .userInitiated) {
                        try PeelFSMount.mount(url)
                    }.value
                    await MainActor.run {
                        let mode = PeelFSMount.navigateFinder(
                            to: location,
                            preferringReuse: true,
                            context: finderCtx
                        )
                        self.status = "Browsing \(url.lastPathComponent)"
                        self.detail = "\(location.path) [\(mode)]"
                        AppDelegate.shared?.noteBrowseJobFinished()
                    }
                } catch {
                    await MainActor.run {
                        self.status = "Browse failed"
                        self.detail = error.localizedDescription
                        AppDelegate.shared?.noteBrowseJobFinished()
                        AppDelegate.shared?.hideMainWindows()
                    }
                }
            }
            return
        }

        // Non-ZIP or browse disabled: extract (Services-style).
        let silent = prefs.silentBackgroundExtract && !prefs.openWindowOnDrop
        if silent {
            AppDelegate.shared?.enterPassiveMode()
            AppDelegate.shared?.hideMainWindows()
            extract(archive: url, silent: true)
        } else {
            AppDelegate.shared?.showMainWindow()
            extract(archive: url, silent: false)
        }
    }

    private static let archiveTypes: [UTType] = {
        var types: [UTType] = [.zip]
        for ext in ["rar", "7z", "tar", "gz", "tgz", "tbz2", "bz2", "dmg", "pdf", "exe", "app", "cbz", "cbr"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }()

    func pickArchive() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.archiveTypes
        panel.message = "Choose items to peel"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            // File picker: prefer browse when possible, else extract in-window.
            if prefs.browseOnOpen, PeelFSMount.supportsBrowse(url) {
                enqueueOpen(url)
            } else {
                extract(archive: url, silent: false)
            }
        }
    }

    func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.fixedDestinationURL = url
        prefs.extractBesideSource = false
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
            guard let url else { return }
            Task { @MainActor in
                // Drop on window: extract (explicit peel), not mount.
                self?.extract(archive: url, silent: false)
            }
        }
        return true
    }

    func revealOutput() {
        guard let folder = lastOutputFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Cancel the active job (HUD X or explicit).
    func cancelActiveExtract() {
        guard let id = activeJobId else {
            PeelExtractor.cancelActive()
            return
        }
        cancelledJobIds.insert(id)
        PeelExtractor.cancelActive()
        progressTimer?.invalidate()
        progressTimer = nil
        if var j = jobs.jobs.first(where: { $0.id == id }), j.status == .running || j.status == .queued {
            j.status = .cancelled
            j.errorMessage = "Cancelled"
            j.finishedAt = Date()
            jobs.upsert(j)
            ProgressPanelController.shared.update(job: j)
        }
        isWorking = false
        activeJobId = nil
        AppDelegate.shared?.noteSilentJobFinished()
        drainQueue()
    }

    func extract(
        archive: URL,
        silent: Bool,
        destinationOverride: URL? = nil,
        revealOverride: Bool? = nil
    ) {
        if isWorking {
            queue.append(archive)
            return
        }
        isWorking = true
        if !silent {
            status = "Peeling \(archive.lastPathComponent)…"
            detail = nil
        }

        var job = PeelJob.new(source: archive)
        job.status = .running
        // Progress denominator: prefer archive size (compressed). Unpacked can be larger;
        // we still show growth of the destination folder for multi-GB RARs.
        if let vals = try? archive.resourceValues(forKeys: [.fileSizeKey]), let size = vals.fileSize {
            job.totalBytes = UInt64(size)
            job.processedBytes = 0
        }
        let expectedDest = destinationOverride
            ?? (prefs.extractBesideSource ? PeelExtractor.defaultDestination(for: archive) : (prefs.fixedDestinationURL ?? PeelExtractor.defaultDestination(for: archive)))
        // Peel folder name is chosen by the engine; watch the parent and any *-peeled dirs.
        job.destinationPath = expectedDest.path
        jobs.upsert(job)
        activeJobId = job.id
        let jobId = job.id
        let started = Date()
        let watchRoot = expectedDest

        if silent {
            AppDelegate.shared?.noteSilentJobStarted()
            ProgressPanelController.shared.show(job: job) { [weak self] in
                self?.cancelActiveExtract()
            }
        }

        let beside = prefs.extractBesideSource
        let dest: URL? = {
            if let destinationOverride { return destinationOverride }
            return beside ? nil : prefs.fixedDestinationURL
        }()
        var reveal = revealOverride ?? prefs.revealAfterExtract
        // One-shot from "Peel & Reveal" Quick Action / workflow
        if UserDefaults.standard.bool(forKey: "peel._serviceRevealOnce") {
            reveal = true
            UserDefaults.standard.set(false, forKey: "peel._serviceRevealOnce")
        }
        let deleteAfter = prefs.deleteArchiveAfterExtract
        let scoped = archive.startAccessingSecurityScopedResource()
        let name = archive.lastPathComponent

        // Progress: asymptotic approach to 95% based on elapsed time + optional dest growth.
        // Never hard-cap at a sticky 90% forever while still running.
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard !self.cancelledJobIds.contains(jobId) else { return }
                guard !ProgressPanelController.shared.isDismissed(jobId) || silent == false else {
                    // If user dismissed HUD we still update job silently for completion path
                    return
                }
                guard var j = JobStore.shared.jobs.first(where: { $0.id == jobId }),
                      j.status == .running else { return }

                let elapsed = Date().timeIntervalSince(started)
                // Prefer real on-disk growth under the destination parent (streaming RAR/ZIP).
                let grown = Self.directoryBytes(under: watchRoot)
                if let total = j.totalBytes, total > 0, grown > 0 {
                    // Unpacked can exceed archive size; cap display at 95% until complete.
                    let ratio = min(0.95, Double(grown) / Double(total))
                    j.processedBytes = UInt64(Double(total) * max(0.02, ratio))
                } else {
                    // Time ease fallback when nothing written yet (header parse / first block).
                    let ease = 1.0 - exp(-elapsed / 90.0)
                    let p = min(0.15, max(0.02, ease * 0.15))
                    if let total = j.totalBytes, total > 0 {
                        j.processedBytes = UInt64(Double(total) * p)
                    } else {
                        j.processedItems = Int(p * 100)
                        j.itemCount = 100
                    }
                }
                JobStore.shared.upsert(j)
                if silent && !ProgressPanelController.shared.isDismissed(jobId) {
                    ProgressPanelController.shared.update(job: j)
                }
            }
        }
        RunLoop.main.add(progressTimer!, forMode: .common)

        Task.detached(priority: .userInitiated) {
            let result: Result<(String, URL, Int?), Error>
            do {
                // Skip expensive full list on huge archives (>256MB) — it blocks progress and can hang UX.
                var itemCount: Int? = nil
                let size = (try? archive.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                if size < 256 * 1024 * 1024 {
                    if let listJSON = try? PeelExtractor.list(archive),
                       let data = listJSON.data(using: .utf8),
                       let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                        itemCount = arr.count
                    }
                }
                let alreadyCancelled = await MainActor.run { self.cancelledJobIds.contains(jobId) }
                if Task.isCancelled || alreadyCancelled {
                    throw PeelExtractor.ExtractError.cancelled
                }
                let json = try PeelExtractor.extract(
                    archive: archive,
                    to: dest,
                    deleteSource: deleteAfter
                )
                var out = PeelExtractor.defaultDestination(for: archive)
                var count = itemCount
                if let data = json.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let d = obj["destination"] as? String {
                        out = URL(fileURLWithPath: d)
                    }
                    if let extracted = obj["extracted"] as? [Any] {
                        count = extracted.count
                    }
                }
                result = .success((json, out, count))
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                self.progressTimer?.invalidate()
                self.progressTimer = nil
                if scoped { archive.stopAccessingSecurityScopedResource() }

                let failureIsCancel: Bool = {
                    if case .failure(let e) = result {
                        if let pe = e as? PeelExtractor.ExtractError, case .cancelled = pe { return true }
                        return e.localizedDescription.lowercased().contains("cancel")
                    }
                    return false
                }()
                let wasCancelled = self.cancelledJobIds.contains(jobId) || failureIsCancel

                self.isWorking = false
                if self.activeJobId == jobId { self.activeJobId = nil }

                var finished = JobStore.shared.jobs.first(where: { $0.id == jobId }) ?? job
                switch result {
                case .success(let (json, out, count)):
                    if wasCancelled {
                        finished.status = .cancelled
                        finished.errorMessage = "Cancelled"
                        finished.finishedAt = Date()
                        JobStore.shared.upsert(finished)
                    } else {
                        finished.status = .succeeded
                        finished.destinationPath = out.path
                        finished.itemCount = count
                        finished.processedItems = count
                        finished.finishedAt = Date()
                        if let total = finished.totalBytes {
                            finished.processedBytes = total
                        }
                        JobStore.shared.upsert(finished)
                        self.lastOutputFolder = out

                        // Collect top-level outputs for Finder refresh / optional reveal.
                        var itemURLs: [URL] = []
                        if let contents = try? FileManager.default.contentsOfDirectory(
                            at: out,
                            includingPropertiesForKeys: nil,
                            options: [.skipsHiddenFiles]
                        ) {
                            itemURLs = contents
                        }
                        // Always refresh Finder so new folders/files appear without relaunch.
                        FinderRefresh.afterExtract(destination: out, items: itemURLs, reveal: reveal)

                        if silent {
                            if !ProgressPanelController.shared.isDismissed(jobId) {
                                ProgressPanelController.shared.update(job: finished)
                            }
                        } else {
                            self.status = "Done — \(name)"
                            self.detail = Self.summarize(json)
                        }
                    }
                case .failure(let error):
                    let cancelled = self.cancelledJobIds.contains(jobId)
                        || (error as? PeelExtractor.ExtractError).map { if case .cancelled = $0 { return true }; return false } ?? false
                        || error.localizedDescription.lowercased().contains("cancel")
                    if cancelled {
                        finished.status = .cancelled
                        finished.errorMessage = "Cancelled"
                    } else {
                        finished.status = .failed
                        finished.errorMessage = error.localizedDescription
                    }
                    finished.finishedAt = Date()
                    JobStore.shared.upsert(finished)
                    if silent {
                        if !ProgressPanelController.shared.isDismissed(jobId) {
                            ProgressPanelController.shared.update(job: finished)
                        }
                        // Don't force main window open on cancel
                        if !cancelled {
                            AppDelegate.shared?.showMainWindow()
                            self.status = "Failed"
                            self.detail = error.localizedDescription
                        }
                    } else {
                        self.status = cancelled ? "Cancelled" : "Failed"
                        self.detail = cancelled ? nil : error.localizedDescription
                    }
                }

                self.cancelledJobIds.remove(jobId)
                if silent {
                    AppDelegate.shared?.noteSilentJobFinished()
                }
                self.drainQueue(silentDefault: silent)
            }
        }
    }

    private func drainQueue(silentDefault: Bool = true) {
        guard !isWorking, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        extract(archive: next, silent: silentDefault)
    }

    /// Sum file sizes under root and immediate *-peeled children (best-effort progress).
    private static func directoryBytes(under root: URL) -> UInt64 {
        let fm = FileManager.default
        var total: UInt64 = 0
        var candidates: [URL] = [root]
        if let kids = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
            for u in kids {
                let name = u.lastPathComponent
                if name.hasSuffix("-peeled") || name.contains("peeled") {
                    candidates.append(u)
                }
                if let vals = try? u.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                   vals.isRegularFile == true,
                   let sz = vals.fileSize {
                    total += UInt64(sz)
                }
            }
        }
        for dir in candidates {
            guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in en {
                if let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                   vals.isRegularFile == true,
                   let sz = vals.fileSize {
                    total += UInt64(sz)
                }
            }
        }
        return total
    }

    private static func summarize(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return json
        }
        let format = obj["format"] as? String ?? "?"
        let dest = obj["destination"] as? String ?? ""
        let n = (obj["extracted"] as? [Any])?.count ?? 0
        let short = (dest as NSString).abbreviatingWithTildeInPath
        return "\(format) · \(n) items · \(short)"
    }
}
