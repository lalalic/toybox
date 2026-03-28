import SwiftUI
import RealityKit
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "LivingToyView")

/// The main "living" toy view — shows the animated 3D model with googly eyes,
/// animated mouth, breathing, and blinking. Tap to interact!
struct LivingToyView: View {
    @Environment(AppModel.self) var appModel
    let toy: ToyModel
    let modelURL: URL

    @State private var animator = ToyAnimator()
    @State private var isLoaded = false
    @State private var showControls = true
    @State private var pivotEntity: Entity?

    // Orbit state
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0.2
    @State private var dragStartYaw: Float = 0
    @State private var dragStartPitch: Float = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Animated 3D model
            RealityView { content in
                do {
                    let entity = try await ModelEntity(contentsOf: modelURL)

                    let bounds = entity.visualBounds(relativeTo: nil)
                    let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
                    let scale = 0.2 / maxExtent
                    entity.scale = SIMD3<Float>(repeating: scale)
                    entity.position = -bounds.center * scale

                    let pivot = Entity()
                    pivot.addChild(entity)

                    let anchor = AnchorEntity()
                    anchor.addChild(pivot)
                    content.add(anchor)

                    pivotEntity = pivot

                    // Set up animator with googly eyes and mouth
                    animator.setup(entity: entity, features: toy.features)
                    animator.startIdleAnimation()
                    isLoaded = true

                    // Apply initial rotation
                    updateRotation()

                    logger.info("Living toy loaded: \(toy.name)")
                } catch {
                    logger.error("Failed to load living toy: \(error)")
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let sensitivity: Float = 0.004
                        yaw = dragStartYaw + Float(value.translation.width) * sensitivity
                        pitch = dragStartPitch + Float(value.translation.height) * sensitivity
                        pitch = max(-.pi / 2 + 0.1, min(.pi / 2 - 0.1, pitch))
                        updateRotation()
                    }
                    .onEnded { _ in
                        dragStartYaw = yaw
                        dragStartPitch = pitch
                    }
            )

            // UI overlay
            if showControls {
                VStack {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(toy.name)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)

                            Text(isLoaded ? "Alive! 👀" : "Loading...")
                                .font(.caption)
                                .foregroundStyle(isLoaded ? .green : .secondary)
                        }

                        Spacer()

                        Button {
                            animator.stopAnimation()
                            appModel.returnHome()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding()

                    Spacer()

                    // Action buttons
                    HStack(spacing: 20) {
                        ActionButton(icon: "mouth.fill", label: "Talk") {
                            Task { await animator.speak(syllables: 10) }
                        }

                        ActionButton(icon: "hand.wave.fill", label: "Wiggle") {
                            // Quick wiggle animation
                            Task {
                                guard let pivot = pivotEntity else { return }
                                let base = pivot.orientation
                                for _ in 0..<3 {
                                    let wobble = simd_quatf(angle: 0.1, axis: SIMD3(0, 0, 1))
                                    pivot.orientation = base * wobble
                                    try? await Task.sleep(for: .milliseconds(100))
                                    let wobble2 = simd_quatf(angle: -0.1, axis: SIMD3(0, 0, 1))
                                    pivot.orientation = base * wobble2
                                    try? await Task.sleep(for: .milliseconds(100))
                                }
                                pivot.orientation = base
                            }
                        }

                        ActionButton(icon: "arrow.uturn.backward", label: "Spin") {
                            Task {
                                guard let pivot = pivotEntity else { return }
                                for i in 0..<36 {
                                    yaw = dragStartYaw + Float(i) * (.pi * 2 / 36)
                                    updateRotation()
                                    try? await Task.sleep(for: .milliseconds(30))
                                }
                                dragStartYaw = yaw
                            }
                        }
                    }
                    .padding(.bottom, 30)
                }
                .transition(.opacity)
            }
        }
    }

    private func updateRotation() {
        guard let pivot = pivotEntity else { return }
        let yawQ = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let pitchQ = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        pivot.orientation = yawQ * pitchQ
    }
}

/// Circular action button for toy interactions.
private struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .accessibilityAddTraits(.isButton)
    }
}
