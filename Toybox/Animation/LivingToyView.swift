import SwiftUI
import RealityKit
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "LivingToyView")

/// The main "living" toy view — shows the animated 3D model that breathes, blinks,
/// and eventually talks. This is the end-state experience.
struct LivingToyView: View {
    @Environment(AppModel.self) var appModel
    let toy: ToyModel
    let modelURL: URL

    @State private var animator = ToyAnimator()
    @State private var isLoaded = false
    @State private var showControls = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Animated 3D model
            RealityView { content in
                do {
                    let entity = try await ModelEntity(contentsOf: modelURL)

                    // Center and scale for display
                    let bounds = entity.visualBounds(relativeTo: nil)
                    let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
                    let scale = 0.2 / maxExtent
                    entity.scale = SIMD3<Float>(repeating: scale)
                    entity.position = -bounds.center * scale

                    let anchor = AnchorEntity()
                    anchor.addChild(entity)
                    content.add(anchor)

                    // Set up animator with features
                    animator.setup(entity: entity, features: toy.features)
                    animator.startIdleAnimation()
                    isLoaded = true

                    logger.info("Living toy loaded: \(toy.name)")
                } catch {
                    logger.error("Failed to load living toy: \(error)")
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { _ in }
            )
            .onTapGesture {
                withAnimation { showControls.toggle() }
            }

            // UI overlay
            if showControls {
                VStack {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(toy.name)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)

                            if toy.isFullyAnnotated {
                                Text("Fully rigged")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("\(toy.features.count) features")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
                        ActionButton(icon: "hand.wave.fill", label: "Wave") {
                            // TODO: Trigger wave animation
                        }

                        ActionButton(icon: "mouth.fill", label: "Talk") {
                            // TODO: Trigger speech
                            Task {
                                for _ in 0..<5 {
                                    animator.setMouthOpen(Float.random(in: 0.3...1.0))
                                    try? await Task.sleep(for: .milliseconds(150))
                                    animator.setMouthOpen(0)
                                    try? await Task.sleep(for: .milliseconds(100))
                                }
                            }
                        }

                        ActionButton(icon: "face.smiling.fill", label: "Blink") {
                            // Manual blink via animation
                        }

                        ActionButton(icon: "camera.fill", label: "Photo") {
                            // TODO: Screenshot
                        }
                    }
                    .padding(.bottom, 30)
                }
                .transition(.opacity)
            }
        }
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
        .buttonStyle(.plain)
    }
}
