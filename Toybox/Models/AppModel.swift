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

    /// Scans Documents directory for existing capture folders with photos that haven't been reconstructed yet.
    /// Returns (directoryName, imageCount) for the best candidate.
    func discoverExistingCaptures() -> (String, Int)? {
        let docs = URL.documentsDirectory
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: docs.path) else { return nil }

        var bestCandidate: (String, Int)? = nil
        for dirName in contents {
            // Must be a valid UUID directory
            guard UUID(uuidString: dirName) != nil else { continue }
            let imagesDir = docs.appendingPathComponent(dirName).appendingPathComponent("Images")
            let modelsDir = docs.appendingPathComponent(dirName).appendingPathComponent("Models")
            guard fm.fileExists(atPath: imagesDir.path) else { continue }
            // Skip if already has a model
            let modelFiles = (try? fm.contentsOfDirectory(atPath: modelsDir.path))?.filter { $0.hasSuffix(".usdz") } ?? []
            if !modelFiles.isEmpty { continue }
            // Count images
            let files = (try? fm.contentsOfDirectory(atPath: imagesDir.path)) ?? []
            let imageFiles = files.filter { $0.hasSuffix(".heic") || $0.hasSuffix(".jpg") || $0.hasSuffix(".png") }
            if imageFiles.count >= 3 {
                if bestCandidate == nil || imageFiles.count > bestCandidate!.1 {
                    bestCandidate = (dirName, imageFiles.count)
                }
            }
        }
        return bestCandidate
    }

    /// Resume reconstruction from an existing capture folder
    func resumeReconstruction(directoryName: String, toyName: String) {
        guard let uuid = UUID(uuidString: directoryName) else {
            state = .failed("Invalid directory name: \(directoryName)")
            return
        }
        let toy = ToyModel(existingID: uuid, name: toyName)
        currentToy = toy
        do {
            let folder = try CaptureFolderManager(toyDirectoryName: directoryName)
            captureFolder = folder
            state = .reconstructing
            logger.info("Resuming reconstruction for \(toyName) from \(directoryName)")
        } catch {
            state = .failed("Failed to set up reconstruction: \(error.localizedDescription)")
        }
    }
}
