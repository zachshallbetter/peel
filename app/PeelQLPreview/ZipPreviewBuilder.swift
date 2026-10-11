import Foundation

/// Minimal ZIP central-directory listing for QL scaffold (stored/deflate index only).
/// Caps work so large/malicious archives cannot hang Finder. Replace with peel XPC later.
enum ZipPreviewBuilder {
    enum PreviewError: Error {
        case unreadable
        case notZip
        case truncated
    }

    static func summary(for url: URL, maxEntries: Int) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= 22 else { throw PreviewError.notZip }
        guard let eocd = findEOCD(in: data) else { throw PreviewError.notZip }

        let totalEntries = Int(readU16(data, eocd + 10))
        let cdSize = Int(readU32(data, eocd + 12))
        let cdOffset = Int(readU32(data, eocd + 16))
        guard cdOffset >= 0, cdSize >= 0, cdOffset + cdSize <= data.count else {
            throw PreviewError.truncated
        }

        var lines: [String] = []
        var files = 0
        var dirs = 0
        var shown = 0
        var totalUncomp: UInt64 = 0
        var encrypted = false

        var cursor = cdOffset
        let cdEnd = cdOffset + cdSize
        while cursor + 46 <= cdEnd {
            let sig = readU32(data, cursor)
            guard sig == 0x02014b50 else { break }
            let flag = readU16(data, cursor + 8)
            let uncomp = readU32(data, cursor + 24)
            let nameLen = Int(readU16(data, cursor + 28))
            let extraLen = Int(readU16(data, cursor + 30))
            let commentLen = Int(readU16(data, cursor + 32))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLen
            guard nameEnd <= data.count else { throw PreviewError.truncated }
            let nameData = data.subdata(in: nameStart..<nameEnd)
            let raw = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? "entry-\(shown)"
            let path = normalize(raw)
            if flag & 0x1 != 0 { encrypted = true }

            let isDir = raw.hasSuffix("/") || path.hasSuffix("/")
            if isDir { dirs += 1 } else {
                files += 1
                totalUncomp += UInt64(uncomp)
            }

            if shown < maxEntries, !path.isEmpty, !path.contains("..") {
                let mark = isDir ? "📁" : "📄"
                let size = isDir ? "" : "  \(byteString(UInt64(uncomp)))"
                lines.append("\(mark) \(path)\(size)")
                shown += 1
            }

            cursor = nameEnd + extraLen + commentLen
        }

        let name = url.lastPathComponent
        var header: [String] = [
            "Peel — \(name)",
            "Format: ZIP",
            "Entries (central dir): \(totalEntries)  ·  files \(files)  ·  folders \(dirs)",
            "Uncompressed (listed files): \(byteString(totalUncomp))",
            "Size on disk: \(byteString(UInt64(data.count)))",
        ]
        if encrypted {
            header.append("Protection: encrypted entries present (listing may be incomplete without password)")
        }
        if totalEntries > maxEntries || shown >= maxEntries {
            header.append("Listing capped at \(maxEntries) rows (bounded Quick Look).")
        }
        header.append("Open with Peel to browse as a folder · Services → Peel to extract")
        header.append("")
        header.append(contentsOf: lines)
        if lines.isEmpty {
            header.append("(No listable entries)")
        }
        return header.joined(separator: "\n")
    }

    private static func normalize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .filter { $0 != "." && $0 != ".." && !$0.isEmpty }
            .joined(separator: "/")
    }

    private static func byteString(_ n: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(clamping: n))
    }

    private static func findEOCD(in data: Data) -> Int? {
        let maxScan = min(data.count, 22 + 65535)
        guard data.count >= 22 else { return nil }
        var i = data.count - 22
        let end = max(0, data.count - maxScan)
        while i >= end {
            if readU32(data, i) == 0x06054b50 { return i }
            if i == 0 { break }
            i -= 1
        }
        return nil
    }
}

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
