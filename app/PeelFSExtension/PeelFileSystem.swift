import Foundation
import FSKit
import os

/// Unary filesystem that probes path/block resources and loads a read-only ZIP volume.
final class PeelFileSystem: FSUnaryFileSystem, FSUnaryFileSystemOperations {
    private let logger = Logger(subsystem: PeelFSConstants.loggerSubsystem, category: "PeelFileSystem")

    func probeResource(
        resource: FSResource,
        replyHandler: @escaping (FSProbeResult?, (any Error)?) -> Void
    ) {
        logger.debug("probeResource: \(String(describing: resource), privacy: .public)")

        guard let archiveURL = Self.archiveURL(from: resource) else {
            replyHandler(FSProbeResult.notRecognized, nil)
            return
        }

        let name = archiveURL.deletingPathExtension().lastPathComponent
        if ZipArchiveReader.looksLikeZip(at: archiveURL) {
            replyHandler(
                FSProbeResult.usable(
                    name: name.isEmpty ? PeelFSConstants.defaultVolumeName : name,
                    containerID: FSContainerIdentifier(uuid: PeelFSConstants.containerIdentifier)
                ),
                nil
            )
        } else {
            // Soft usable keeps mount path available while still documenting ZIP-first spike.
            replyHandler(
                FSProbeResult.usable(
                    name: name.isEmpty ? PeelFSConstants.defaultVolumeName : name,
                    containerID: FSContainerIdentifier(uuid: PeelFSConstants.containerIdentifier)
                ),
                nil
            )
        }
    }

    func loadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler: @escaping (FSVolume?, (any Error)?) -> Void
    ) {
        logger.debug("loadResource: \(String(describing: resource), privacy: .public)")
        containerStatus = .ready

        guard let archiveURL = Self.archiveURL(from: resource) else {
            replyHandler(nil, fs_errorForPOSIXError(POSIXError.EINVAL.rawValue))
            return
        }

        do {
            let volume = try PeelFSVolume(archiveURL: archiveURL, resource: resource)
            replyHandler(volume, nil)
        } catch {
            logger.error("loadResource failed: \(error.localizedDescription, privacy: .public)")
            replyHandler(nil, error)
        }
    }

    func unloadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler reply: @escaping ((any Error)?) -> Void
    ) {
        logger.debug("unloadResource: \(String(describing: resource), privacy: .public)")
        reply(nil)
    }

    func didFinishLoading() {
        logger.debug("didFinishLoading")
    }

    static func archiveURL(from resource: FSResource) -> URL? {
        if let pathResource = resource as? FSPathURLResource {
            return pathResource.url
        }
        // Some hosts still present file-backed block resources; try description parse as last resort.
        let description = String(describing: resource)
        if let range = description.range(of: "file://") {
            let tail = String(description[range.lowerBound...])
            let cleaned = tail.split(whereSeparator: { $0 == " " || $0 == ")" || $0 == "," }).first.map(String.init)
            if let cleaned, let url = URL(string: cleaned), url.isFileURL {
                return url
            }
        }
        return nil
    }
}
