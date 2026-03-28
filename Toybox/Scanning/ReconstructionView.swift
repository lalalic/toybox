import SwiftUI
import RealityKit
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "ReconstructionView")

/// Shows reconstruction progress while PhotogrammetrySession processes captured images.
struct ReconstructionView: View {
    @Environment(AppModel.self) var appModel
    let folderManager: CaptureFolderManager

    @State private var progress: Float = 0
    @State private var stageDescription: String?
    @State private var estimatedRemainingTime: TimeInterval?
    @State private var isProcessing = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Title
            Text("Building 3D Model")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Stage description
            if let description = stageDescription {
                Text(description)
                    .font(.headline)
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

        let modelFileName = "model.usdz"
        let outputURL = folderManager.modelsFolder.appendingPathComponent(modelFileName)

        do {
            let session = try PhotogrammetrySession(
                input: folderManager.imagesFolder
            )

            logger.info("Starting reconstruction...")

            let task = Task.detached { @Sendable in
                try session.process(requests: [
                    .modelFile(url: outputURL)
                ])
            }

            // Monitor outputs
            for try await output in session.outputs {
                switch output {
                case .inputComplete:
                    logger.info("Input complete")
                case .requestProgress(let request, fractionComplete: let fraction):
                    if case .modelFile = request {
                        await MainActor.run { progress = Float(fraction) }
                    }
                case .requestProgressInfo(let request, let info):
                    if case .modelFile = request {
                        await MainActor.run {
                            estimatedRemainingTime = info.estimatedRemainingTime
                            stageDescription = info.processingStage?.description
                        }
                    }
                case .requestComplete(let request, _):
                    if case .modelFile = request {
                        logger.info("Model file complete!")
                    }
                case .requestError(_, let err):
                    logger.error("Request error: \(err)")
                    await MainActor.run { self.error = err }
                case .processingComplete:
                    logger.info("Processing complete!")
                    await MainActor.run {
                        appModel.finishReconstruction(modelFileName: modelFileName)
                    }
                case .processingCancelled:
                    logger.info("Processing cancelled")
                    await MainActor.run { appModel.returnHome() }
                default:
                    break
                }
            }

            _ = try? await task.value
        } catch {
            logger.error("Reconstruction failed: \(error)")
            await MainActor.run {
                appModel.state = .failed("Reconstruction failed: \(error.localizedDescription)")
            }
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
        case .preProcessing: return "Preprocessing..."
        case .imageAlignment: return "Aligning images..."
        case .pointCloudGeneration: return "Generating point cloud..."
        case .meshGeneration: return "Generating mesh..."
        case .textureMapping: return "Mapping textures..."
        case .optimization: return "Optimizing..."
        @unknown default: return "Processing..."
        }
    }
}
