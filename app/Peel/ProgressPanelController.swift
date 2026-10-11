import AppKit
import SwiftUI

/// Compact floating HUD for silent Open With / right-click extract.
@MainActor
final class ProgressPanelController {
    static let shared = ProgressPanelController()

    private var panels: [UUID: NSPanel] = [:]
    /// User dismissed / cancelled — never auto-reopen these jobs.
    private var dismissed: Set<UUID> = []
    private var cancelHandlers: [UUID: () -> Void] = [:]

    private let panelSize = NSSize(width: 380, height: 96)

    private init() {}

    func show(job: PeelJob, onCancel: (() -> Void)? = nil) {
        if dismissed.contains(job.id) { return }
        if let onCancel { cancelHandlers[job.id] = onCancel }

        if panels[job.id] != nil {
            update(job: job)
            return
        }

        let root = ProgressPanelView(
            jobId: job.id,
            onClose: { [weak self] in
                self?.userDismiss(jobId: job.id, cancelWork: true)
            },
            onShow: { [weak self] in
                if let path = JobStore.shared.jobs.first(where: { $0.id == job.id })?.destinationPath {
                    let url = URL(fileURLWithPath: path)
                    FinderRefresh.afterExtract(destination: url, items: [url], reveal: true)
                }
                self?.userDismiss(jobId: job.id, cancelWork: false)
            }
        )
        let hosting = NSHostingView(rootView: root.environmentObject(JobStore.shared))
        hosting.frame = NSRect(origin: .zero, size: panelSize)

        // Borderless HUD — no traffic lights / title chrome (those caused the weird layout).
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.contentView = hosting

        position(panel)
        panel.orderFrontRegardless()
        panels[job.id] = panel
        update(job: job)
    }

    private func position(_ panel: NSPanel) {
        // Top-center of the screen that contains the mouse (fallback: main).
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let topMargin: CGFloat = 28
        let origin = NSPoint(
            x: visible.midX - panelSize.width / 2,
            y: visible.maxY - panelSize.height - topMargin
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    func update(job: PeelJob) {
        if dismissed.contains(job.id) { return }
        guard let panel = panels[job.id] else {
            // Do NOT reopen after user close. Only create if never shown and still running
            // is handled exclusively by show().
            return
        }
        panel.orderFrontRegardless()

        if job.status == .succeeded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self else { return }
                if JobStore.shared.jobs.first(where: { $0.id == job.id })?.status == .succeeded {
                    self.userDismiss(jobId: job.id, cancelWork: false)
                }
            }
        }
        if job.status == .failed || job.status == .cancelled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.userDismiss(jobId: job.id, cancelWork: false)
            }
        }
    }

    /// User clicked X or finished auto-dismiss.
    func userDismiss(jobId: UUID, cancelWork: Bool) {
        dismissed.insert(jobId)
        panels[jobId]?.orderOut(nil)
        panels[jobId] = nil
        if cancelWork {
            let handler = cancelHandlers.removeValue(forKey: jobId)
            handler?()
        } else {
            cancelHandlers.removeValue(forKey: jobId)
        }
    }

    func close(jobId: UUID) {
        userDismiss(jobId: jobId, cancelWork: false)
    }

    func isDismissed(_ jobId: UUID) -> Bool {
        dismissed.contains(jobId)
    }

    var hasVisiblePanels: Bool {
        panels.values.contains { $0.isVisible }
    }
}

struct ProgressPanelView: View {
    let jobId: UUID
    var onClose: () -> Void
    var onShow: () -> Void
    @EnvironmentObject private var store: JobStore

    private var job: PeelJob? {
        store.jobs.first { $0.id == jobId }
    }

    var body: some View {
        Group {
            if let job {
                content(job)
            } else {
                Color.clear
            }
        }
        .frame(width: 380, height: 96)
    }

    @ViewBuilder
    private func content(_ job: PeelJob) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color(red: 1.0, green: 0.45, blue: 0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                if job.status == .succeeded {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                } else if job.status == .failed || job.status == .cancelled {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Peel")
                    .font(.subheadline.weight(.semibold))
                if job.status == .running || job.status == .queued {
                    Text("Extracting “\(job.sourceName)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: max(0.02, min(1, job.progress)))
                        .tint(.orange)
                        .controlSize(.small)
                    HStack {
                        Text(progressCaption(job))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(Int((job.progress * 100).rounded()))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else if job.status == .succeeded {
                    Text(successCaption(job))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if job.status == .cancelled {
                    Text("Cancelled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(job.errorMessage ?? "Something went wrong")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                        .lineLimit(2)
                }
            }

            VStack(spacing: 6) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(job.status == .running ? "Cancel" : "Dismiss")

                if job.status == .succeeded {
                    Button(action: onShow) {
                        Image(systemName: "folder")
                            .font(.caption)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
        .padding(6)
    }

    private func progressCaption(_ job: PeelJob) -> String {
        if let total = job.itemCount, let done = job.processedItems, total > 0 {
            return "\(done) of \(total) items"
        }
        if let total = job.totalBytes, let done = job.processedBytes, total > 0 {
                    // Archive size is compressed; note multi-GB jobs take time.
            if total > 512 * 1024 * 1024 {
                return "\(byteString(done)) · large archive, keep waiting…"
            }
            return "\(byteString(done)) of \(byteString(total))"
        }
        return "Working…"
    }

    private func successCaption(_ job: PeelJob) -> String {
        let n = job.itemCount.map { "\($0) items" } ?? "items"
        let dest = job.destinationPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "folder"
        return "Extracted \(n) to “\(dest)”"
    }

    private func byteString(_ n: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}
