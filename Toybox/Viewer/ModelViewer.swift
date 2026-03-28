import SwiftUI
import RealityKit
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "ModelViewer")

/// Interactive 3D model viewer using RealityKit with orbit gestures.
struct ModelViewer: View {
    let modelURL: URL
    let toyName: String
    var onAnnotate: (() -> Void)?
    var onDone: (() -> Void)?

    @State private var isLoading = true
    @State private var loadError: String?

    // Orbit camera state
    @State private var yaw: Float = 0       // Horizontal rotation (radians)
    @State private var pitch: Float = 0.3   // Vertical tilt (radians)
    @State private var distance: Float = 0.5 // Camera distance
    @State private var modelEntity: ModelEntity?
    @State private var pivotEntity: Entity?

    // Gesture tracking (for deltas)
    @State private var dragStartYaw: Float = 0
    @State private var dragStartPitch: Float = 0
    @State private var pinchStartDistance: Float = 0.5

    var body: some View {
        ZStack {
            // RealityKit 3D view
            RealityView { content in
                do {
                    let entity = try await ModelEntity(contentsOf: modelURL)

                    // Calculate bounds and normalize scale
                    let bounds = entity.visualBounds(relativeTo: nil)
                    let extent = bounds.extents
                    let maxExtent = max(extent.x, max(extent.y, extent.z))
                    let scale = 0.3 / maxExtent

                    // Create a pivot entity for orbit rotation
                    let pivot = Entity()
                    entity.scale = SIMD3<Float>(repeating: scale)
                    entity.position = -bounds.center * scale
                    pivot.addChild(entity)

                    let anchor = AnchorEntity()
                    anchor.addChild(pivot)
                    content.add(anchor)

                    modelEntity = entity
                    pivotEntity = pivot

                    // Apply initial rotation
                    updateRotation()

                    logger.info("Loaded model: \(self.modelURL.lastPathComponent), bounds: \(extent)")
                    isLoading = false
                } catch {
                    logger.error("Failed to load model: \(error)")
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
            .gesture(dragGesture)
            .gesture(magnifyGesture)

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

                // Gesture hints
                Text("Drag to rotate · Pinch to zoom")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
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

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation == .zero { return }
                let sensitivity: Float = 0.004
                yaw = dragStartYaw + Float(value.translation.width) * sensitivity
                pitch = dragStartPitch + Float(value.translation.height) * sensitivity
                // Clamp pitch to avoid flipping
                pitch = max(-.pi / 2 + 0.1, min(.pi / 2 - 0.1, pitch))
                updateRotation()
            }
            .onEnded { _ in
                dragStartYaw = yaw
                dragStartPitch = pitch
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newDist = pinchStartDistance / Float(value.magnification)
                distance = max(0.15, min(3.0, newDist))
                updateRotation()
            }
            .onEnded { _ in
                pinchStartDistance = distance
            }
    }

    private func updateRotation() {
        guard let pivot = pivotEntity else { return }
        // Apply yaw (around Y) then pitch (around X)
        let yawQ = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let pitchQ = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        pivot.orientation = yawQ * pitchQ
        // Scale as zoom
        pivot.scale = SIMD3<Float>(repeating: distance / 0.5)
    }
}
