import Foundation
import RealityKit
import SwiftUI
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "AppModel")

/// Central app state machine that drives navigation.
@Observable
@MainActor
final class AppModel {
    enum State: Equatable {
        case home
        case ready          // Preparing to scan
        case scanning       // ObjectCaptureSession active
        case reconstructing // PhotogrammetrySession processing
        case viewing        // Showing reconstructed model
        case annotating     // Marking features on model
        case failed(String) // Error state
    }

    var state: State = .home
    var scanCoordinator: ScanCoordinator?
    let toyStore = ToyStore()

    /// The toy currently being created
    var currentToy: ToyModel?

    /// Whether the device supports object capture scanning
    var isScanningSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ObjectCaptureSession.isSupported
        #endif
    }

    func startNewScan(toyName: String) {
        let toy = ToyModel(name: toyName)
        currentToy = toy

        do {
            let coordinator = try ScanCoordinator(toy: toy)
            scanCoordinator = coordinator
            state = .scanning
            logger.info("Started new scan for toy: \(toyName)")
        } catch {
            state = .failed("Failed to set up scanning: \(error.localizedDescription)")
            logger.error("Scan setup failed: \(error)")
        }
    }

    func finishReconstruction(modelFileName: String) {
        guard var toy = currentToy else { return }
        toy.modelFileName = modelFileName
        toyStore.add(toy)
        currentToy = toy
        state = .viewing
        logger.info("Reconstruction complete: \(modelFileName)")
    }

    func startAnnotating() {
        state = .annotating
    }

    func annotateToy(_ toy: ToyModel) {
        currentToy = toy
        state = .annotating
    }

    func returnHome() {
        scanCoordinator = nil
        currentToy = nil
        state = .home
    }
}
