import Foundation
import RealityKit
import UIKit
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "ToyAnimator")

/// Animates a scanned toy model based on annotated feature points.
/// Supports idle animations (breathing, blinking) and speech-synced mouth movement.
@Observable
@MainActor
final class ToyAnimator {
    private var rootEntity: Entity?
    private var featureMarkers: [ToyFeature.Kind: ModelEntity] = [:]
    private var isAnimating = false

    // Animation parameters
    var breathingSpeed: Float = 1.0    // cycles per second
    var breathingAmount: Float = 0.02  // scale oscillation
    var blinkInterval: TimeInterval = 3.0
    var blinkDuration: TimeInterval = 0.15

    // Mouth animation
    var isSpeaking = false
    var mouthOpenAmount: Float = 0.0  // 0 = closed, 1 = fully open

    /// Set up the animator with a loaded model entity and its features.
    func setup(entity: Entity, features: [ToyFeature]) {
        rootEntity = entity
        featureMarkers.removeAll()

        // Create animated markers at feature positions
        for feature in features {
            let marker = createFeatureMarker(for: feature)
            entity.addChild(marker)
            featureMarkers[feature.kind] = marker
        }

        logger.info("Animator set up with \(features.count) features")
    }

    /// Start idle animations (breathing, occasional blinks).
    func startIdleAnimation() {
        guard !isAnimating, let root = rootEntity else { return }
        isAnimating = true

        // Breathing animation — gentle scale oscillation
        let breatheUp = root.transform
        var breatheDown = breatheUp
        breatheDown.scale *= (1.0 + breathingAmount)

        // Use RealityKit's built-in animation
        let duration: TimeInterval = 1.0 / Double(breathingSpeed)

        // Create a repeating transform animation
        Task {
            while isAnimating {
                // Scale up
                var upTransform = root.transform
                upTransform.scale = root.transform.scale * (1.0 + breathingAmount)
                root.move(to: upTransform, relativeTo: root.parent, duration: duration / 2)
                try? await Task.sleep(for: .milliseconds(Int(duration * 500)))

                // Scale back
                root.move(to: breatheUp, relativeTo: root.parent, duration: duration / 2)
                try? await Task.sleep(for: .milliseconds(Int(duration * 500)))
            }
        }

        // Blink animation
        Task {
            while isAnimating {
                try? await Task.sleep(for: .seconds(blinkInterval + Double.random(in: -1...1)))
                if isAnimating { await blink() }
            }
        }

        logger.info("Started idle animation")
    }

    /// Stop all animations.
    func stopAnimation() {
        isAnimating = false
        logger.info("Stopped animation")
    }

    /// Animate mouth open/close for speech.
    func setMouthOpen(_ amount: Float) {
        guard let mouth = featureMarkers[.mouth] else { return }
        mouthOpenAmount = amount

        // Animate mouth by scaling the marker and displacing downward
        var transform = Transform.identity
        transform.scale = SIMD3<Float>(1, 1 + amount * 0.5, 1)
        transform.translation.y -= amount * 0.003
        mouth.move(to: transform, relativeTo: mouth.parent, duration: 0.05)
    }

    // MARK: - Private

    private func blink() async {
        guard let leftEye = featureMarkers[.leftEye],
              let rightEye = featureMarkers[.rightEye] else { return }

        // Close eyes
        let closedScale = SIMD3<Float>(1, 0.1, 1)
        var leftClosed = leftEye.transform
        leftClosed.scale = closedScale
        var rightClosed = rightEye.transform
        rightClosed.scale = closedScale

        let leftOpen = leftEye.transform
        let rightOpen = rightEye.transform

        leftEye.move(to: leftClosed, relativeTo: leftEye.parent, duration: blinkDuration / 2)
        rightEye.move(to: rightClosed, relativeTo: rightEye.parent, duration: blinkDuration / 2)

        try? await Task.sleep(for: .milliseconds(Int(blinkDuration * 500)))

        // Open eyes
        leftEye.move(to: leftOpen, relativeTo: leftEye.parent, duration: blinkDuration / 2)
        rightEye.move(to: rightOpen, relativeTo: rightEye.parent, duration: blinkDuration / 2)
    }

    private func createFeatureMarker(for feature: ToyFeature) -> ModelEntity {
        let size: Float = switch feature.kind {
        case .leftEye, .rightEye: 0.004
        case .mouth: 0.006
        case .nose: 0.003
        case .bodyCenter: 0.008
        case .head: 0.005
        }

        let mesh = MeshResource.generateSphere(radius: size)
        let color: UIColor = switch feature.kind {
        case .leftEye: .systemBlue
        case .rightEye: .systemCyan
        case .mouth: .systemRed
        case .nose: .systemOrange
        case .bodyCenter: .systemGreen
        case .head: .systemPurple
        }
        let material = SimpleMaterial(color: color.withAlphaComponent(0.7), isMetallic: false)
        let marker = ModelEntity(mesh: mesh, materials: [material])
        marker.position = feature.position
        return marker
    }
}
