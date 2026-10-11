import Foundation
import FSKit

final class PeelFSItem: FSItem {
    private static var nextID: UInt64 = FSItem.Identifier.rootDirectory.rawValue + 1
    private static let idLock = NSLock()

    static func allocateID() -> UInt64 {
        idLock.lock()
        defer { idLock.unlock() }
        let value = nextID
        nextID += 1
        return value
    }

    let name: FSFileName
    let pathInArchive: String
    let isDirectory: Bool
    /// Uncompressed size for files.
    let uncompressedSize: UInt64
    /// Lazy payload provider for file items.
    private let payloadProvider: (() throws -> Data)?
    private var cachedPayload: Data?
    private let payloadLock = NSLock()

    var attributes = FSItem.Attributes()
    private(set) var children: [String: PeelFSItem] = [:]

    init(
        name: FSFileName,
        pathInArchive: String,
        isDirectory: Bool,
        uncompressedSize: UInt64 = 0,
        payloadProvider: (() throws -> Data)? = nil
    ) {
        self.name = name
        self.pathInArchive = pathInArchive
        self.isDirectory = isDirectory
        self.uncompressedSize = uncompressedSize
        self.payloadProvider = payloadProvider

        let id = Self.allocateID()
        attributes.fileID = FSItem.Identifier(rawValue: id) ?? .invalid
        attributes.parentID = .invalid
        attributes.uid = 0
        attributes.gid = 0
        attributes.linkCount = 1
        attributes.flags = 0
        attributes.type = isDirectory ? .directory : .file
        if isDirectory {
            attributes.mode = UInt32(S_IFDIR | 0o555)
            attributes.size = 1
            attributes.allocSize = 1
        } else {
            attributes.mode = UInt32(S_IFREG | 0o444)
            attributes.size = uncompressedSize
            attributes.allocSize = uncompressedSize
        }

        var ts = timespec()
        timespec_get(&ts, TIME_UTC)
        attributes.addedTime = ts
        attributes.birthTime = ts
        attributes.changeTime = ts
        attributes.modifyTime = ts
        attributes.accessTime = ts
    }

    static func makeRoot() -> PeelFSItem {
        let root = PeelFSItem(
            name: FSFileName(string: "/"),
            pathInArchive: "",
            isDirectory: true
        )
        root.attributes.parentID = .parentOfRoot
        root.attributes.fileID = .rootDirectory
        return root
    }

    func addChild(_ item: PeelFSItem) {
        item.attributes.parentID = attributes.fileID
        let key = item.name.string ?? ""
        children[key] = item
    }

    func child(named name: FSFileName) -> PeelFSItem? {
        guard let key = name.string else { return nil }
        return children[key]
    }

    func payload() throws -> Data {
        payloadLock.lock()
        defer { payloadLock.unlock() }
        if let cachedPayload {
            return cachedPayload
        }
        guard let payloadProvider else {
            return Data()
        }
        let data = try payloadProvider()
        cachedPayload = data
        attributes.size = UInt64(data.count)
        attributes.allocSize = UInt64(data.count)
        return data
    }
}
