import Foundation
import FSKit
import os

/// Read-only FSKit volume backed by a ZIP archive (spike).
final class PeelFSVolume: FSVolume {
    private let resource: FSResource
    private let archiveURL: URL
    private let reader: ZipArchiveReader
    private let root: PeelFSItem
    private let logger = Logger(subsystem: PeelFSConstants.loggerSubsystem, category: "PeelFSVolume")
    private let fileCount: UInt64
    private let totalBytes: UInt64

    init(archiveURL: URL, resource: FSResource) throws {
        self.archiveURL = archiveURL
        self.resource = resource
        self.reader = try ZipArchiveReader(url: archiveURL)
        self.root = PeelFSItem.makeRoot()

        var files: UInt64 = 0
        var bytes: UInt64 = 0
        for entry in reader.entries {
            if entry.path.isEmpty { continue }
            if entry.isDirectory {
                _ = Self.ensureDirectory(path: entry.path, root: root)
                continue
            }
            let parentPath = (entry.path as NSString).deletingLastPathComponent
            let fileName = (entry.path as NSString).lastPathComponent
            let parent = parentPath.isEmpty ? root : Self.ensureDirectory(path: parentPath, root: root)
            let readerRef = reader
            let entryCopy = entry
            let item = PeelFSItem(
                name: FSFileName(string: fileName),
                pathInArchive: entry.path,
                isDirectory: false,
                uncompressedSize: UInt64(entry.uncompressedSize),
                payloadProvider: {
                    try readerRef.readFile(entryCopy)
                }
            )
            parent.addChild(item)
            files += 1
            bytes += UInt64(entry.uncompressedSize)
        }
        self.fileCount = max(files, 1)
        self.totalBytes = max(bytes, 1)

        let volumeName = archiveURL.deletingPathExtension().lastPathComponent
        super.init(
            volumeID: FSVolume.Identifier(uuid: PeelFSConstants.volumeIdentifier),
            volumeName: FSFileName(string: volumeName.isEmpty ? PeelFSConstants.defaultVolumeName : volumeName)
        )
    }

    private static func ensureDirectory(path: String, root: PeelFSItem) -> PeelFSItem {
        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        var current = root
        var built = ""
        for part in parts {
            built = built.isEmpty ? part : built + "/" + part
            if let existing = current.children[part] {
                current = existing
                continue
            }
            let dir = PeelFSItem(
                name: FSFileName(string: part),
                pathInArchive: built,
                isDirectory: true
            )
            current.addChild(dir)
            current = dir
        }
        return current
    }
}

extension PeelFSVolume: FSVolume.PathConfOperations {
    var maximumLinkCount: Int { 1 }
    var maximumNameLength: Int { 255 }
    var restrictsOwnershipChanges: Bool { true }
    var truncatesLongNames: Bool { false }
    var maximumXattrSize: Int { 0 }
    var maximumFileSize: UInt64 { UInt64.max }
}

extension PeelFSVolume: FSVolume.Operations {
    var supportedVolumeCapabilities: FSVolume.SupportedCapabilities {
        let capabilities = FSVolume.SupportedCapabilities()
        capabilities.supportsHardLinks = false
        capabilities.supportsSymbolicLinks = false
        capabilities.supportsPersistentObjectIDs = true
        capabilities.doesNotSupportVolumeSizes = false
        capabilities.supportsHiddenFiles = true
        capabilities.supports64BitObjectIDs = true
        capabilities.caseFormat = .sensitive
        return capabilities
    }

    var volumeStatistics: FSStatFSResult {
        let result = FSStatFSResult(fileSystemTypeName: PeelFSConstants.fileSystemTypeName)
        let blockSize: UInt64 = 4096
        let totalBlocks = max((totalBytes + blockSize - 1) / blockSize, 1)
        result.blockSize = Int(blockSize)
        result.ioSize = Int(blockSize)
        result.totalBlocks = totalBlocks
        result.availableBlocks = 0
        result.freeBlocks = 0
        result.totalFiles = fileCount
        result.freeFiles = 0
        return result
    }

    func activate(options: FSTaskOptions) async throws -> FSItem {
        logger.debug("activate \(self.archiveURL.path, privacy: .public)")
        return root
    }

    func deactivate(options: FSDeactivateOptions = []) async throws {
        logger.debug("deactivate")
    }

    func mount(options: FSTaskOptions) async throws {
        logger.debug("mount")
    }

    func unmount() async {
        logger.debug("unmount")
    }

    func synchronize(flags: FSSyncFlags) async throws {
        // Read-only: nothing to flush.
    }

    func attributes(
        _ desiredAttributes: FSItem.GetAttributesRequest,
        of item: FSItem
    ) async throws -> FSItem.Attributes {
        guard let item = item as? PeelFSItem else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        return item.attributes
    }

    func setAttributes(
        _ newAttributes: FSItem.SetAttributesRequest,
        on item: FSItem
    ) async throws -> FSItem.Attributes {
        // Read-only volume: reject mutations.
        throw fs_errorForPOSIXError(POSIXError.EROFS.rawValue)
    }

    func lookupItem(
        named name: FSFileName,
        inDirectory directory: FSItem
    ) async throws -> (FSItem, FSFileName) {
        guard let directory = directory as? PeelFSItem else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        guard let item = directory.child(named: name) else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        return (item, name)
    }

    func reclaimItem(_ item: FSItem) async throws {}

    func readSymbolicLink(_ item: FSItem) async throws -> FSFileName {
        throw fs_errorForPOSIXError(POSIXError.EINVAL.rawValue)
    }

    func createItem(
        named name: FSFileName,
        type: FSItem.ItemType,
        inDirectory directory: FSItem,
        attributes newAttributes: FSItem.SetAttributesRequest
    ) async throws -> (FSItem, FSFileName) {
        throw fs_errorForPOSIXError(POSIXError.EROFS.rawValue)
    }

    func createSymbolicLink(
        named name: FSFileName,
        inDirectory directory: FSItem,
        attributes newAttributes: FSItem.SetAttributesRequest,
        linkContents contents: FSFileName
    ) async throws -> (FSItem, FSFileName) {
        throw fs_errorForPOSIXError(POSIXError.EROFS.rawValue)
    }

    func createLink(
        to item: FSItem,
        named name: FSFileName,
        inDirectory directory: FSItem
    ) async throws -> FSFileName {
        throw fs_errorForPOSIXError(POSIXError.EROFS.rawValue)
    }

    func removeItem(
        _ item: FSItem,
        named name: FSFileName,
        fromDirectory directory: FSItem
    ) async throws {
        throw fs_errorForPOSIXError(POSIXError.EROFS.rawValue)
    }

    func renameItem(
        _ item: FSItem,
        inDirectory sourceDirectory: FSItem,
        named sourceName: FSFileName,
        to destinationName: FSFileName,
        inDirectory destinationDirectory: FSItem,
        overItem: FSItem?
    ) async throws -> FSFileName {
        throw fs_errorForPOSIXError(POSIXError.EROFS.rawValue)
    }

    func enumerateDirectory(
        _ directory: FSItem,
        startingAt cookie: FSDirectoryCookie,
        verifier: FSDirectoryVerifier,
        attributes: FSItem.GetAttributesRequest?,
        packer: FSDirectoryEntryPacker
    ) async throws -> FSDirectoryVerifier {
        guard let directory = directory as? PeelFSItem else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }

        let ordered = directory.children.values.sorted {
            ($0.name.string ?? "") < ($1.name.string ?? "")
        }
        let start = Int(cookie.rawValue)
        guard start <= ordered.count else {
            return FSDirectoryVerifier(0)
        }

        if start < ordered.count {
            for idx in start..<ordered.count {
                let item = ordered[idx]
                _ = packer.packEntry(
                    name: item.name,
                    itemType: item.attributes.type,
                    itemID: item.attributes.fileID,
                    nextCookie: FSDirectoryCookie(UInt64(idx + 1)),
                    attributes: attributes != nil ? item.attributes : nil
                )
            }
        }
        return FSDirectoryVerifier(0)
    }
}

extension PeelFSVolume: FSVolume.OpenCloseOperations {
    func openItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        // Writes are rejected at read/write layer; open is allowed for read.
        if modes.contains(.write) {
            throw fs_errorForPOSIXError(POSIXError.EROFS.rawValue)
        }
    }

    func closeItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {}
}

extension PeelFSVolume: FSVolume.XattrOperations {
    func xattr(named name: FSFileName, of item: FSItem) async throws -> Data {
        throw fs_errorForPOSIXError(POSIXError.ENOATTR.rawValue)
    }

    func setXattr(
        named name: FSFileName,
        to value: Data?,
        on item: FSItem,
        policy: FSVolume.SetXattrPolicy
    ) async throws {
        throw fs_errorForPOSIXError(POSIXError.EROFS.rawValue)
    }

    func xattrs(of item: FSItem) async throws -> [FSFileName] {
        []
    }
}

extension PeelFSVolume: FSVolume.ReadWriteOperations {
    func read(
        from item: FSItem,
        at offset: off_t,
        length: Int,
        into buffer: FSMutableFileDataBuffer
    ) async throws -> Int {
        guard let item = item as? PeelFSItem, !item.isDirectory else {
            throw fs_errorForPOSIXError(POSIXError.EISDIR.rawValue)
        }
        let data: Data
        do {
            data = try item.payload()
        } catch {
            logger.error("read payload failed: \(error.localizedDescription, privacy: .public)")
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        if offset < 0 || offset >= data.count || length <= 0 {
            return 0
        }
        let start = Int(offset)
        let end = min(start + min(length, buffer.length), data.count)
        let slice = data.subdata(in: start..<end)
        return slice.withUnsafeBytes { src in
            buffer.withUnsafeMutableBytes { dst in
                let n = min(dst.count, slice.count)
                if n > 0, let s = src.baseAddress, let d = dst.baseAddress {
                    memcpy(d, s, n)
                }
                return n
            }
        }
    }

    func write(contents: Data, to item: FSItem, at offset: off_t) async throws -> Int {
        throw fs_errorForPOSIXError(POSIXError.EROFS.rawValue)
    }
}
