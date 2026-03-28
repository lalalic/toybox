import SwiftUI
import RealityKit
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "ModelViewer")

/// Interactive 3D model viewer using RealityKit.
struct ModelViewer: View {
    let modelURL: URL
    let toyName: String
    var onAnnotate: (() -> Void)?
    var onDone: (() -> Void)?

    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ZStack {
            // RealityKit 3D view
            RealityView { content in
                do {
                    let entity = try await ModelEntity(contentsOf: modelURL)

                    // Center and scale the model
                    let bounds = entity.visualBounds(relativeTo: nil)
                    let extent = bounds.extents
                    let maxExtent = max(extent.x, max(extent.y, extent.z))
                    let scale = 0.3 / maxExtent  // Normalize to ~30cm
                    entity.scale = SIMD3<Float>(repeating: scale)

                    // Center the model
                    let center = bounds.center
                    entity.position = -center * scale

                    // Add to an anchor
                    let anchor = AnchorEntity()
                    anchor.addChild(entity)
                    content.add(anchor)

                    logger.info("Loaded model: \(self.modelURL.lastPathComponent)")
                    isLoading = false
                } catch {
                    logger.error("Failed to load model: \(error)")
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { _ in
                        // Rotation gesture handled by RealityView natively
                    }
            )

            // Overlay UI
            VStack {
                HStack {
                    Text(toyName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())

                    Spacer()

                    if let onAnnotate {
                        Button {
                            onAnnotate()
                        } label: {
                            Label("Mark Features", systemImage: "hand.point.up.left.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let onDone {
                        Button("Done") {
                            onDone()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()

                Spacer()
            }

            // Loading / Error states
            if isLoading {
                ProgressView("Loading model...")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Failed to load model")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
