import AppKit
import QuickLookUI
import UniformTypeIdentifiers
import os.log

/// FND-001 scaffold: Space on a ZIP shows a bounded entry list without launching Peel.
/// Production path should call peel-core via XPC (`docs/peelfs-xpc-bridge.md`), not a second parser.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let log = Logger(subsystem: "io.snackstud.peel.QuickLook", category: "Preview")
    private let scroll = NSScrollView()
    private let textView = NSTextView()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 480,
            height: CGFloat.greatestFiniteMagnitude
        )

        scroll.documentView = textView
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        self.view = root
    }

    func preparePreviewOfFile(at url: URL) async throws {
        log.debug("preparePreviewOfFile \(url.path, privacy: .public)")
        let summary = try ZipPreviewBuilder.summary(for: url, maxEntries: 400)
        await MainActor.run {
            self.textView.string = summary
            self.preferredContentSize = NSSize(width: 520, height: 640)
        }
    }
}
