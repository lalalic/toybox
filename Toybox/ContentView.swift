import SwiftUI
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "ContentView")

/// Root content view that switches between states.
struct ContentView: View {
    @Environment(AppModel.self) var appModel

    var body: some View {
        Group {
            switch appModel.state {
            case .home:
                ToyGallery()

            case .ready:
                ProgressView("Preparing scanner...")

            case .scanning:
                if let coordinator = appModel.scanCoordinator {
                    ScanView(session: coordinator.session)
                } else {
                    errorView("Scanner not available")
                }

            case .reconstructing:
                if let coordinator = appModel.scanCoordinator {
                    ReconstructionView(folderManager: coordinator.folderManager)
                } else {
                    errorView("Reconstruction data not available")
                }

            case .viewing:
                if let toy = appModel.currentToy,
                   let url = appModel.toyStore.modelURL(for: toy) {
                    ModelViewer(modelURL: url, toyName: toy.name) {
                        appModel.returnHome()
                    }
                } else {
                    errorView("Model not found")
                }

            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.red)

                    Text("Something went wrong")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Go Home") {
                        appModel.returnHome()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .animation(.default, value: appModel.state)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .foregroundStyle(.secondary)
            Button("Go Home") {
                appModel.returnHome()
            }
        }
    }
}
