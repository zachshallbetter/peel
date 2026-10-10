import Foundation

struct PeelJob: Identifiable, Codable, Equatable {
    enum Status: String, Codable {
        case queued
        case running
        case succeeded
        case failed
        case cancelled
    }

    let id: UUID
    var sourcePath: String
    var destinationPath: String?
    var format: String?
    var itemCount: Int?
    var totalBytes: UInt64?
    var processedItems: Int?
    var processedBytes: UInt64?
    var status: Status
    var errorMessage: String?
    var createdAt: Date
    var finishedAt: Date?

    var sourceName: String {
        URL(fileURLWithPath: sourcePath).lastPathComponent
    }

    var progress: Double {
        if let total = itemCount, total > 0, let done = processedItems {
            return min(1, Double(done) / Double(total))
        }
        if let total = totalBytes, total > 0, let done = processedBytes {
            return min(1, Double(done) / Double(total))
        }
        return status == .succeeded ? 1 : 0
    }

    static func new(source: URL) -> PeelJob {
        PeelJob(
            id: UUID(),
            sourcePath: source.path,
            destinationPath: nil,
            format: nil,
            itemCount: nil,
            totalBytes: nil,
            processedItems: nil,
            processedBytes: nil,
            status: .queued,
            errorMessage: nil,
            createdAt: Date(),
            finishedAt: nil
        )
    }
}

@MainActor
final class JobStore: ObservableObject {
    static let shared = JobStore()

    @Published private(set) var jobs: [PeelJob] = []
    @Published var favorites: [String] = [] // paths

    private let jobsKey = "peel.jobHistory"
    private let favKey = "peel.favorites"
    private let limit = 50

    private init() {
        load()
    }

    func load() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: jobsKey),
           let decoded = try? JSONDecoder().decode([PeelJob].self, from: data) {
            jobs = decoded
        }
        favorites = d.stringArray(forKey: favKey) ?? []
    }

    private func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(Array(jobs.prefix(limit))) {
            d.set(data, forKey: jobsKey)
        }
        d.set(favorites, forKey: favKey)
    }

    func upsert(_ job: PeelJob) {
        if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[idx] = job
        } else {
            jobs.insert(job, at: 0)
        }
        if jobs.count > limit {
            jobs = Array(jobs.prefix(limit))
        }
        save()
    }

    func clear() {
        jobs.removeAll()
        save()
    }

    func toggleFavorite(_ path: String) {
        if let i = favorites.firstIndex(of: path) {
            favorites.remove(at: i)
        } else {
            favorites.insert(path, at: 0)
        }
        save()
    }

    func isFavorite(_ path: String) -> Bool {
        favorites.contains(path)
    }

    var recentSucceeded: [PeelJob] {
        jobs.filter { $0.status == .succeeded || $0.status == .failed }
    }

    var activeJobs: [PeelJob] {
        jobs.filter { $0.status == .running || $0.status == .queued }
    }
}
