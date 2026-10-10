import Foundation
import Darwin

/// Swift front-end for Peel (talks to the `peel` Rust CLI).
public final class PeelClient: @unchecked Sendable {
    public var peelBinary: URL
    /// Active extract process (for cancel).
    private let lock = NSLock()
    private var activeProcess: Process?

    public init(peelBinary: URL) {
        self.peelBinary = peelBinary
    }

    public static func fromRepoRoot(_ root: URL, release: Bool = true) -> PeelClient {
        let rel = root.appendingPathComponent("target/\(release ? "release" : "debug")/peel")
        return PeelClient(peelBinary: rel)
    }

    public struct Policy: Sendable {
        public var destination: URL?
        public var collision: String
        public var enclosing: String
        public var password: String?
        public var deleteSource: Bool

        public init(
            destination: URL? = nil,
            collision: String = "rename",
            enclosing: String = "when-needed",
            password: String? = nil,
            deleteSource: Bool = false
        ) {
            self.destination = destination
            self.collision = collision
            self.enclosing = enclosing
            self.password = password
            self.deleteSource = deleteSource
        }
    }

    public func list(archive: URL) throws -> String {
        try run(arguments: ["l", archive.path, "-j"])
    }

    public func probe(archive: URL) throws -> String {
        try run(arguments: ["p", archive.path, "-j"])
    }

    public func extract(archive: URL, policy: Policy = Policy(), members: [String] = []) throws -> String {
        var args = ["x", archive.path, "-j"]
        if let destination = policy.destination {
            args += ["-o", destination.path]
        }
        switch policy.collision {
        case "overwrite": args.append("-f")
        case "skip": args.append("-s")
        default: args.append("-r")
        }
        switch policy.enclosing {
        case "always": args.append("-d")
        case "never": args.append("-D")
        default: break
        }
        if let password = policy.password, !password.isEmpty {
            args += ["-p", password]
        }
        if policy.deleteSource {
            args.append("--delete")
        }
        args.append(contentsOf: members)
        return try run(arguments: args, trackAsActive: true)
    }

    /// Kill in-flight extract (and child peel engine).
    public func cancelActive() {
        lock.lock()
        let proc = activeProcess
        activeProcess = nil
        lock.unlock()
        guard let proc else { return }
        if proc.isRunning {
            proc.terminate()
            // Give it a moment; force kill if needed
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                if proc.isRunning {
                    proc.interrupt()
                    kill(proc.processIdentifier, SIGKILL)
                }
            }
        }
    }

    private func run(arguments: [String], trackAsActive: Bool = false) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: peelBinary.path) else {
            throw PeelError.missingBinary(peelBinary)
        }
        let proc = Process()
        proc.executableURL = peelBinary
        proc.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        if trackAsActive {
            lock.lock()
            activeProcess = proc
            lock.unlock()
        }
        defer {
            if trackAsActive {
                lock.lock()
                if activeProcess === proc { activeProcess = nil }
                lock.unlock()
            }
        }
        try proc.run()
        proc.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            // 15 = SIGTERM from cancel
            if proc.terminationStatus == 15 || proc.terminationReason == .uncaughtSignal {
                throw PeelError.cancelled
            }
            throw PeelError.commandFailed(code: proc.terminationStatus, stderr: stderr.isEmpty ? stdout : stderr)
        }
        return stdout
    }
}

public enum PeelError: Error, LocalizedError {
    case missingBinary(URL)
    case commandFailed(code: Int32, stderr: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingBinary(let url):
            return "peel binary not found at \(url.path). Run: cargo build -p peel-cli --release"
        case .commandFailed(let code, let stderr):
            return "peel exited \(code): \(stderr)"
        case .cancelled:
            return "Cancelled"
        }
    }
}
