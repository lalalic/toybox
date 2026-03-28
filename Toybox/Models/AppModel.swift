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
        case ready            // Preparing to scan
        case scanning         // ObjectCaptureSession active (LiDAR)
        case photoCapture     // Manual photo capture (non-LiDAR)
        case reconstructing   // PhotogrammetrySession processing
        case viewing          // Showing reconstructed model
        case annotating       // Marking features on model
        case living           // Animated, interactive toy
        case failed(String)   // Error state
    }

    var state: State = .home
    var scanCoordinator: ScanCoordinator?
    var captureFolder: CaptureFolderManager?
    let toyStore = ToyStore()

    /// The toy currently being created
    var currentToy: ToyModel?

    /// Whether the device supports LiDAR-based object capture scanning
    var isLiDARSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ObjectCaptureSession.isSupported
        #endif
    }

    /// Photo-based capture (PhotogrammetrySession) works on all devices
    var isPhotoCaptureSupported: Bool {
        return true
    }

    func startNewScan(toyName: String) {
        let toy = ToyModel(name: toyName)
        currentToy = toy

        if isLiDARSupported {
            do {
                let coordinator = try ScanCoordinator(toy: toy)
                scanCoordinator = coordinator
                state = .scanning
                logger.info("Started LiDAR scan for toy: \(toyName)")
            } catch {
                state = .failed("Failed to set up scanning: \(error.localizedDescription)")
                logger.error("Scan setup failed: \(error)")
            }
        } else {
            // Use manual photo capture flow
            do {
                let folder = try CaptureFolderManager(toyDirectoryName: toy.directoryName)
                captureFolder = folder
                state = .photoCapture
                logger.info("Started photo capture for toy: \(toyName)")
            } catch {
                state = .failed("Failed to set up photo capture: \(error.localizedDescription)")
                logger.error("Photo capture setup failed: \(error)")
            }
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

    func bringToLife(_ toy: ToyModel) {
        currentToy = toy
        state = .living
    }

    func returnHome() {
        scanCoordinator = nil
        captureFolder = nil
        currentToy = nil
        state = .home
    }
}
