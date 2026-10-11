import Foundation
import AppKit
import UniformTypeIdentifiers

/// Persisted product settings (spec defaults + quick setup).
@MainActor
final class PeelPreferences: ObservableObject {
    static let shared = PeelPreferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let didCompleteSetup = "peel.didCompleteSetup"
        static let extractBesideSource = "peel.extractBesideSource"
        static let revealAfterExtract = "peel.revealAfterExtract"
        static let openWindowOnDrop = "peel.openWindowOnDrop"
        static let silentBackgroundExtract = "peel.silentBackgroundExtract"
        static let installFinderService = "peel.installFinderService"
        static let claimDefaultHandler = "peel.claimDefaultHandler"
        static let fixedDestinationPath = "peel.fixedDestinationPath"
        static let deleteArchiveAfterExtract = "peel.deleteArchiveAfterExtract"
        /// Double-click / Open With: browse via PeelFS (mount) instead of extracting.
        static let browseOnOpen = "peel.browseOnOpen"
    }

    @Published var didCompleteSetup: Bool {
        didSet { defaults.set(didCompleteSetup, forKey: Key.didCompleteSetup) }
    }

    @Published var extractBesideSource: Bool {
        didSet { defaults.set(extractBesideSource, forKey: Key.extractBesideSource) }
    }

    @Published var revealAfterExtract: Bool {
        didSet { defaults.set(revealAfterExtract, forKey: Key.revealAfterExtract) }
    }

    /// When false, Open With does not raise the main Peel window (used with extract mode).
    @Published var openWindowOnDrop: Bool {
        didSet { defaults.set(openWindowOnDrop, forKey: Key.openWindowOnDrop) }
    }

    /// When true, Services / explicit extract uses the compact HUD without the main window.
    @Published var silentBackgroundExtract: Bool {
        didSet { defaults.set(silentBackgroundExtract, forKey: Key.silentBackgroundExtract) }
    }

    /// Double-click opens archive via PeelFS mount in Finder (Windows-style browse).
    @Published var browseOnOpen: Bool {
        didSet { defaults.set(browseOnOpen, forKey: Key.browseOnOpen) }
    }

    @Published var installFinderService: Bool {
        didSet { defaults.set(installFinderService, forKey: Key.installFinderService) }
    }

    @Published var claimDefaultHandler: Bool {
        didSet { defaults.set(claimDefaultHandler, forKey: Key.claimDefaultHandler) }
    }

    @Published var fixedDestinationPath: String? {
        didSet { defaults.set(fixedDestinationPath, forKey: Key.fixedDestinationPath) }
    }

    @Published var deleteArchiveAfterExtract: Bool {
        didSet { defaults.set(deleteArchiveAfterExtract, forKey: Key.deleteArchiveAfterExtract) }
    }

    var fixedDestinationURL: URL? {
        get { fixedDestinationPath.map { URL(fileURLWithPath: $0) } }
        set { fixedDestinationPath = newValue?.path }
    }

    private init() {
        let d = defaults
        didCompleteSetup = d.object(forKey: Key.didCompleteSetup) as? Bool ?? false
        extractBesideSource = d.object(forKey: Key.extractBesideSource) as? Bool ?? true
        revealAfterExtract = d.object(forKey: Key.revealAfterExtract) as? Bool ?? true
        openWindowOnDrop = d.object(forKey: Key.openWindowOnDrop) as? Bool ?? false
        // Services still prefer silent HUD extract.
        silentBackgroundExtract = d.object(forKey: Key.silentBackgroundExtract) as? Bool ?? true
        // Double-click default: browse as folder via PeelFS (not Archive Utility extract).
        browseOnOpen = d.object(forKey: Key.browseOnOpen) as? Bool ?? true
        installFinderService = d.object(forKey: Key.installFinderService) as? Bool ?? true
        claimDefaultHandler = d.object(forKey: Key.claimDefaultHandler) as? Bool ?? true
        fixedDestinationPath = d.string(forKey: Key.fixedDestinationPath)
        deleteArchiveAfterExtract = d.object(forKey: Key.deleteArchiveAfterExtract) as? Bool ?? false
    }

    static let claimableExtensions = [
        "zip", "rar", "7z", "tar", "gz", "tgz", "tbz2", "bz2", "cbz", "cbr", "cb7"
    ]

    func applyDefaultHandlerClaim() {
        guard claimDefaultHandler else { return }
        let bundleId = Bundle.main.bundleIdentifier ?? "io.snackstud.peel"
        for ext in Self.claimableExtensions {
            guard let uti = UTType(filenameExtension: ext)?.identifier else { continue }
            LSSetDefaultRoleHandlerForContentType(
                uti as CFString,
                .all,
                bundleId as CFString
            )
        }
    }

    func runFinderServiceInstallIfNeeded() {
        guard installFinderService else { return }
        let candidates = [
            URL(fileURLWithPath: NSString(string: "~/Projects/peel/scripts/install-finder-service.sh").expandingTildeInPath),
            Bundle.main.resourceURL?.appendingPathComponent("install-finder-service.sh"),
        ].compactMap { $0 }
        for url in candidates where FileManager.default.isExecutableFile(atPath: url.path) {
            let task = Process()
            task.executableURL = url
            try? task.run()
            task.waitUntilExit()
            return
        }
    }
}
