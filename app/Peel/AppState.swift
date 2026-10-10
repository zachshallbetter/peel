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

    func enqueueOpen(_ url: URL) {
        let silent = prefs.silentBackgroundExtract || !prefs.openWindowOnDrop
        if silent {
            AppDelegate.shared?.hideMainWindows()
            extract(archive: url, silent: true)
        } else {
            if prefs.openWindowOnDrop {
                NSApp.activate(ignoringOtherApps: true)
                AppDelegate.shared?.showMainWindow()
            }
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
            extract(archive: url, silent: false)
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
        if let vals = try? archive.resourceValues(forKeys: [.fileSizeKey]), let size = vals.fileSize {
            job.totalBytes = UInt64(size)
            job.processedBytes = 0
        }
        jobs.upsert(job)
        activeJobId = job.id
        let jobId = job.id
        let started = Date()

        if silent {
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
                // Ease toward 0.95 over ~minutes for large archives; small ones finish before this matters.
                let ease = 1.0 - exp(-elapsed / 45.0) // ~63% at 45s, ~95% asymptote of the ease itself
                let p = min(0.95, max(0.03, ease * 0.95))

                if let total = j.totalBytes, total > 0 {
                    j.processedBytes = UInt64(Double(total) * p)
                } else {
                    j.processedItems = Int(p * 100)
                    j.itemCount = 100
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
                self.drainQueue(silentDefault: silent)
            }
        }
    }

    private func drainQueue(silentDefault: Bool = true) {
        guard !isWorking, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        extract(archive: next, silent: silentDefault)
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
