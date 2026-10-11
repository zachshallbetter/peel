import Foundation

enum PeelFSConstants {
    /// Stable container id advertised from probeResource.
    static let containerIdentifier = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
    /// Volume id returned from loadResource (must stay stable for a mount session).
    static let volumeIdentifier = UUID(uuidString: "B2C3D4E5-F678-9012-BCDE-F12345678901")!
    static let fileSystemTypeName = "PeelFS"
    static let shortName = "PeelFS"
    static let defaultVolumeName = "Peel Archive"
    static let loggerSubsystem = "io.snackstud.peel.fskit"
}
