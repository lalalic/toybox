import SwiftUI
import RealityKit
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "ReconstructionView")

/// Shows reconstruction progress while PhotogrammetrySession processes captured images.
struct ReconstructionView: View {
    @Environment(AppModel.self) var appModel
    let folderManager: CaptureFolderManager

    @State private var progress: Float = 0
    @State private var stageDescription: String = "Preparing..."
    @State private var estimatedRemainingTime: TimeInterval?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var imageCount: Int = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let errorMessage {
                // Error state
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.red)

                Text("Reconstruction Failed")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Go Home") {
                    appModel.returnHome()
                }
                .buttonStyle(.borderedProminent)
            } else {
                // Progress state
                Text("Building 3D Model")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(stageDescription)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if imageCount > 0 {
                    Text("\(imageCount) images")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Progress bar
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 300)

                    Text("\(Int(progress * 100))%")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                // Estimated time
                if let remaining = estimatedRemainingTime, remaining > 0 {
                    Text("About \(formatTime(remaining)) remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Cancel button
            Button("Cancel", role: .destructive) {
                appModel.returnHome()
            }
            .padding(.bottom, 40)
        }
        .padding()
        .task {
            await startReconstruction()
        }
    }

    private func startReconstruction() async {
        guard !isProcessing else { return }
        isProcessing = true

        // Check support
        guard PhotogrammetrySession.isSupported else {
            logger.error("PhotogrammetrySession not supported on this device")
            errorMessage = "3D reconstruction is not supported on this device."
            return
        }

        // Count images
        let fm = FileManager.default
        let imagesPath = folderManager.imagesFolder.path
        let files = (try? fm.contentsOfDirectory(atPath: imagesPath)) ?? []
        let imageFiles = files.filter { $0.hasSuffix(".heic") || $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") || $0.hasSuffix(".png") }
        imageCount = imageFiles.count
        logger.info("Found \(imageCount) images in \(imagesPath)")

        guard imageCount >= 3 else {
            errorMessage = "Not enough images (\(imageCount)). Need at least 3 photos."
            return
        }

        let modelFileName = "model.usdz"
        let outputURL = folderManager.modelsFolder.appendingPathComponent(modelFileName)

        do {
            stageDescription = "Loading \(imageCount) images..."
            logger.info("Creating PhotogrammetrySession with input: \(folderManager.imagesFolder.path)")

            let session = try PhotogrammetrySession(
                input: folderManager.imagesFolder
            )

            logger.info("PhotogrammetrySession created, starting processing...")
            stageDescription = "Starting reconstruction..."

            nonisolated(unsafe) let unsafeSession = session
            let processTask = Task.detached { @Sendable in
                try unsafeSession.process(requests: [
                    .modelFile(url: outputURL, detail: .reduced)
                ])
            }

            // Monitor outputs
            for try await output in session.outputs {
                switch output {
                case .inputComplete:
                    logger.info("Input complete")
                    stageDescription = "Images loaded, processing..."

                case .requestProgress(let request, fractionComplete: let fraction):
                    if case .modelFile = request {
                        await MainActor.run { progress = Float(fraction) }
                    }

                case .requestProgressInfo(let request, let info):
                    if case .modelFile = request {
                        await MainActor.run {
                            estimatedRemainingTime = info.estimatedRemainingTime
                            if let stage = info.processingStage {
                                stageDescription = stage.description
                            }
                        }
                    }

                case .requestComplete(let request, let result):
                    if case .modelFile = request {
                        logger.info("Model file complete! Result: \(String(describing: result))")
                    }

                case .requestError(let request, let err):
                    logger.error("Request error for \(String(describing: request)): \(err)")
                    await MainActor.run {
                        errorMessage = "Reconstruction error: \(err.localizedDescription)"
                    }

                case .processingComplete:
                    logger.info("Processing complete!")
                    await MainActor.run {
                        appModel.finishReconstruction(modelFileName: modelFileName)
                    }

                case .processingCancelled:
                    logger.info("Processing cancelled")
                    await MainActor.run { appModel.returnHome() }

                case .invalidSample(let id, let reason):
                    logger.warning("Invalid sample \(id): \(reason)")

                case .skippedSample(let id):
                    logger.info("Skipped sample: \(id)")

                case .automaticDownsampling:
                    logger.info("Automatic downsampling applied")

                case .stitchingIncomplete:
                    logger.warning("Stitching incomplete")

                default:
                    logger.info("Unhandled output: \(String(describing: output))")
                }
            }

            _ = try? await processTask.value
        } catch {
            logger.error("Reconstruction failed: \(error)")
            errorMessage = "Failed: \(error.localizedDescription)"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }
}

// Extension to get user-facing descriptions for processing stages
extension PhotogrammetrySession.Output.ProcessingStage {
    var description: String {
        switch self {
        case .preProcessing: return "Preprocessing images..."
        case .imageAlignment: return "Aligning images..."
        case .pointCloudGeneration: return "Generating point cloud..."
        case .meshGeneration: return "Generating mesh..."
        case .textureMapping: return "Mapping textures..."
        case .optimization: return "Optimizing model..."
        @unknown default: return "Processing..."
        }
    }
}
