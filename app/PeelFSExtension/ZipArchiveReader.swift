import Foundation
import zlib

/// Minimal ZIP reader for the FSKit spike (stored + deflate, no encryption/ZIP64).
/// Production PeelFS should call peel-core via XPC instead of re-parsing formats here.
struct ZipArchiveReader {
    struct Entry {
        let path: String
        let isDirectory: Bool
        let compressionMethod: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
        let generalPurposeFlag: UInt16
    }

    enum ZipError: Error, LocalizedError {
        case unreadable
        case notZip
        case truncated
        case unsupported(String)
        case inflateFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Unable to read archive"
            case .notZip: return "Not a ZIP archive"
            case .truncated: return "Truncated ZIP"
            case .unsupported(let reason): return "Unsupported ZIP feature: \(reason)"
            case .inflateFailed: return "Deflate failed"
            }
        }
    }

    let url: URL
    let data: Data
    let entries: [Entry]

    static func looksLikeZip(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let prefix = handle.readData(ofLength: 4)
        guard prefix.count == 4 else { return false }
        // Local file header or empty archive EOCD
        return prefix == Data([0x50, 0x4b, 0x03, 0x04])
            || prefix == Data([0x50, 0x4b, 0x05, 0x06])
            || prefix == Data([0x50, 0x4b, 0x07, 0x08])
    }

    init(url: URL) throws {
        self.url = url
        self.data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= 22 else { throw ZipError.notZip }
        self.entries = try Self.parseCentralDirectory(data: data)
    }

    func readFile(_ entry: Entry) throws -> Data {
        if entry.isDirectory {
            return Data()
        }
        if entry.generalPurposeFlag & 0x1 != 0 {
            throw ZipError.unsupported("encrypted entry \(entry.path)")
        }
        guard entry.localHeaderOffset < data.count else { throw ZipError.truncated }

        let offset = Int(entry.localHeaderOffset)
        guard data.count >= offset + 30 else { throw ZipError.truncated }
        let sig: UInt32 = readU32(data, offset)
        guard sig == 0x04034b50 else { throw ZipError.truncated }
        let nameLen = Int(readU16(data, offset + 26))
        let extraLen = Int(readU16(data, offset + 28))
        let dataStart = offset + 30 + nameLen + extraLen
        let dataEnd = dataStart + Int(entry.compressedSize)
        guard data.count >= dataEnd else { throw ZipError.truncated }
        let compressed = data.subdata(in: dataStart..<dataEnd)

        switch entry.compressionMethod {
        case 0:
            return compressed
        case 8:
            return try inflateRaw(compressed, expectedSize: Int(entry.uncompressedSize))
        default:
            throw ZipError.unsupported("compression \(entry.compressionMethod)")
        }
    }

    // MARK: - Parse

    private static func parseCentralDirectory(data: Data) throws -> [Entry] {
        guard let eocd = findEOCD(in: data) else { throw ZipError.notZip }
        let totalEntries = Int(readU16(data, eocd + 10))
        let cdSize = Int(readU32(data, eocd + 12))
        let cdOffset = Int(readU32(data, eocd + 16))
        guard cdOffset >= 0, cdSize >= 0, cdOffset + cdSize <= data.count else {
            throw ZipError.truncated
        }

        var entries: [Entry] = []
        entries.reserveCapacity(totalEntries)
        var cursor = cdOffset
        let cdEnd = cdOffset + cdSize
        while cursor + 46 <= cdEnd {
            let sig = readU32(data, cursor)
            guard sig == 0x02014b50 else { break }
            let flag = readU16(data, cursor + 8)
            let method = readU16(data, cursor + 10)
            let compSize = readU32(data, cursor + 20)
            let uncompSize = readU32(data, cursor + 24)
            let nameLen = Int(readU16(data, cursor + 28))
            let extraLen = Int(readU16(data, cursor + 30))
            let commentLen = Int(readU16(data, cursor + 32))
            let localOffset = readU32(data, cursor + 42)
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLen
            guard nameEnd <= data.count else { throw ZipError.truncated }
            let nameData = data.subdata(in: nameStart..<nameEnd)
            let rawName = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? "unknown-\(entries.count)"
            let path = normalizePath(rawName)
            if !path.isEmpty && !path.contains("..") {
                let isDir = rawName.hasSuffix("/") || uncompSize == 0 && rawName.hasSuffix("/")
                entries.append(
                    Entry(
                        path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                        isDirectory: isDir || rawName.hasSuffix("/"),
                        compressionMethod: method,
                        compressedSize: compSize,
                        uncompressedSize: uncompSize,
                        localHeaderOffset: localOffset,
                        generalPurposeFlag: flag
                    )
                )
            }
            cursor = nameEnd + extraLen + commentLen
        }
        return entries
    }

    private static func findEOCD(in data: Data) -> Int? {
        // EOCD is at least 22 bytes; comment up to 65535.
        let maxScan = min(data.count, 22 + 65535)
        guard data.count >= 22 else { return nil }
        let start = data.count - 22
        let end = max(0, data.count - maxScan)
        var i = start
        while i >= end {
            if readU32(data, i) == 0x06054b50 {
                return i
            }
            if i == 0 { break }
            i -= 1
        }
        return nil
    }

    private static func normalizePath(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .filter { $0 != "." && $0 != ".." && !$0.isEmpty }
            .joined(separator: "/")
    }
}

// MARK: - Binary helpers

private func readU16(_ data: Data, _ offset: Int) -> UInt16 {
    data.withUnsafeBytes { buf in
        UInt16(littleEndian: buf.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
    }
}

private func readU32(_ data: Data, _ offset: Int) -> UInt32 {
    data.withUnsafeBytes { buf in
        UInt32(littleEndian: buf.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
}

private func inflateRaw(_ input: Data, expectedSize: Int) throws -> Data {
    if input.isEmpty {
        return Data()
    }
    var stream = z_stream()
    var status = inflateInit2_(
        &stream,
        -MAX_WBITS,
        ZLIB_VERSION,
        Int32(MemoryLayout<z_stream>.size)
    )
    guard status == Z_OK else { throw ZipArchiveReader.ZipError.inflateFailed }
    defer { inflateEnd(&stream) }

    let destinationCapacity = max(expectedSize, input.count * 2, 64)
    var output = Data(count: destinationCapacity)
    var totalOut = 0

    try input.withUnsafeBytes { inBuf in
        guard let inBase = inBuf.bindMemory(to: Bytef.self).baseAddress else {
            throw ZipArchiveReader.ZipError.inflateFailed
        }
        stream.next_in = UnsafeMutablePointer(mutating: inBase)
        stream.avail_in = uInt(input.count)

        while true {
            if totalOut >= output.count {
                output.count = max(output.count * 2, totalOut + 64 * 1024)
            }
            let wrote: Int = try output.withUnsafeMutableBytes { outBuf in
                guard let outBase = outBuf.bindMemory(to: Bytef.self).baseAddress else {
                    throw ZipArchiveReader.ZipError.inflateFailed
                }
                stream.next_out = outBase.advanced(by: totalOut)
                stream.avail_out = uInt(outBuf.count - totalOut)
                status = inflate(&stream, Z_NO_FLUSH)
                let produced = (outBuf.count - totalOut) - Int(stream.avail_out)
                return produced
            }
            totalOut += wrote
            if status == Z_STREAM_END {
                break
            }
            if status != Z_OK {
                throw ZipArchiveReader.ZipError.inflateFailed
            }
            if wrote == 0 && stream.avail_in == 0 {
                break
            }
        }
    }

    output.count = totalOut
    return output
}
