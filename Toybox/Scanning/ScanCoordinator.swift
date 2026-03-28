import Foundation
import RealityKit
import SwiftUI
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "ScanCoordinator")

/// Manages the ObjectCaptureSession lifecycle for a single toy scan.
@Observable
@MainActor
final class ScanCoordinator {
    let folderManager: CaptureFolderManager
    let session: ObjectCaptureSession
    let toy: ToyModel

    var feedbackMessages: [String] = []

    init(toy: ToyModel) throws {
        self.toy = toy
        self.folderManager = try CaptureFolderManager(toyDirectoryName: toy.directoryName)

        self.session = ObjectCaptureSession()

        var configuration = ObjectCaptureSession.Configuration()
        configuration.isOverCaptureEnabled = true
        configuration.checkpointDirectory = folderManager.checkpointFolder

        session.start(
            imagesDirectory: folderManager.imagesFolder,
            configuration: configuration
        )

        logger.info("ObjectCaptureSession started for toy: \(toy.name)")
    }

    func startDetecting() {
        session.startDetecting()
    }

    func startCapturing() {
        session.startCapturing()
    }

    func finishCapture() {
        session.finish()
    }
}
