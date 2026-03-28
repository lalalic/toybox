import Foundation
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "CaptureFolderManager")

/// Manages the directory structure for a single capture session.
/// Creates Images/, Checkpoint/, and Models/ subdirectories.
final class CaptureFolderManager: Sendable {
    let captureFolder: URL
    let imagesFolder: URL
    let checkpointFolder: URL
    let modelsFolder: URL

    init(toyDirectoryName: String) throws {
        let baseDir = URL.documentsDirectory.appendingPathComponent(toyDirectoryName)

        captureFolder = baseDir
        imagesFolder = baseDir.appendingPathComponent("Images")
        checkpointFolder = baseDir.appendingPathComponent("Checkpoint")
        modelsFolder = baseDir.appendingPathComponent("Models")

        try Self.createDirectoryIfNeeded(captureFolder)
        try Self.createDirectoryIfNeeded(imagesFolder)
        try Self.createDirectoryIfNeeded(checkpointFolder)
        try Self.createDirectoryIfNeeded(modelsFolder)

        logger.info("Created capture folders at: \(baseDir.path)")
    }

    private static func createDirectoryIfNeeded(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
