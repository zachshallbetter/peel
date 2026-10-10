import Foundation
import PeelKit

/// Locates the embedded Rust `peel` engine and runs extractions for the UI.
enum PeelExtractor {
    enum ExtractError: LocalizedError {
        case engineMissing
        case failed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .engineMissing:
                return "Peel engine is missing from the app bundle. Reinstall Peel."
            case .failed(let message):
                return message
            case .cancelled:
                return "Cancelled"
            }
        }
    }

    private static let clientLock = NSLock()
    private static var sharedClient: PeelClient?

    static func engineURL() -> URL? {
        let bundle = Bundle.main
        if let helpers = bundle.privateFrameworksURL?
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers/peel", isDirectory: false),
           FileManager.default.isExecutableFile(atPath: helpers.path) {
            return helpers
        }
        if let bundleURL = bundle.bundleURL as URL? {
            let helpers = bundleURL
                .appendingPathComponent("Contents/Helpers/peel", isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: helpers.path) {
                return helpers
            }
        }
        if let res = bundle.url(forResource: "peel", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: res.path) {
            return res
        }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("target/release/peel")
        if FileManager.default.isExecutableFile(atPath: dev.path) {
            return dev
        }
        return nil
    }

    static func client() throws -> PeelClient {
        clientLock.lock()
        defer { clientLock.unlock() }
        if let sharedClient { return sharedClient }
        guard let url = engineURL() else { throw ExtractError.engineMissing }
        let c = PeelClient(peelBinary: url)
        sharedClient = c
        return c
    }

    static func cancelActive() {
        clientLock.lock()
        let c = sharedClient
        clientLock.unlock()
        c?.cancelActive()
    }

    static func defaultDestination(for archive: URL) -> URL {
        archive.deletingLastPathComponent()
    }

    @discardableResult
    static func extract(
        archive: URL,
        to destination: URL? = nil,
        collision: String = "rename",
        deleteSource: Bool = false,
        password: String? = nil
    ) throws -> String {
        let client = try client()
        let dest = destination ?? defaultDestination(for: archive)
        let policy = PeelClient.Policy(
            destination: dest,
            collision: collision,
            enclosing: "when-needed",
            password: password,
            deleteSource: deleteSource
        )
        do {
            return try client.extract(archive: archive, policy: policy)
        } catch PeelError.cancelled {
            throw ExtractError.cancelled
        } catch {
            throw ExtractError.failed(error.localizedDescription)
        }
    }

    static func list(_ archive: URL) throws -> String {
        try client().list(archive: archive)
    }
}
