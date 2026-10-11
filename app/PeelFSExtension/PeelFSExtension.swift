import Foundation
import FSKit

@main
struct PeelFSExtension: UnaryFileSystemExtension {
    var fileSystem: FSUnaryFileSystem & FSUnaryFileSystemOperations {
        PeelFileSystem()
    }
}
