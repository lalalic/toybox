import Foundation
import RealityKit
import UIKit
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "ToyAnimator")

/// Animates a scanned toy model with expressive cartoon-style overlays.
/// Eyes blink, mouth opens/closes, and the body breathes.
@Observable
@MainActor
final class ToyAnimator {
    private var rootEntity: Entity?
    private var isAnimating = false

    // Cartoon overlay entities
    private var leftEyeWhite: ModelEntity?
    private var leftIris: ModelEntity?
    private var rightEyeWhite: ModelEntity?
    private var rightIris: ModelEntity?
    private var leftEyelid: ModelEntity?
    private var rightEyelid: ModelEntity?
    private var mouthEntity: ModelEntity?

    // Animation parameters
    var breathingSpeed: Float = 0.8
    var breathingAmount: Float = 0.015
    var blinkInterval: TimeInterval = 3.0
    var blinkDuration: TimeInterval = 0.15

    // State
    var isSpeaking = false

    /// Set up with a loaded entity. If features are provided, use those positions.
    /// Otherwise auto-place at reasonable defaults on the front of the model.
    func setup(entity: Entity, features: [ToyFeature] = []) {
        rootEntity = entity

        let bounds = entity.visualBounds(relativeTo: entity.parent)
        let center = bounds.center
        let extent = bounds.extents
        let frontZ = center.z + extent.z * 0.48 // Just in front of model surface

        // Determine positions
        let eyeY: Float
        let eyeSpacing: Float
        let mouthY: Float
        let eyeSize: Float
        let mouthSize: Float

        if !features.isEmpty {
            // Use annotated positions
            let leftEyePos = features.first(where: { $0.kind == .leftEye })?.position
            let rightEyePos = features.first(where: { $0.kind == .rightEye })?.position
            let mouthPos = features.first(where: { $0.kind == .mouth })?.position

            if let le = leftEyePos, let re = rightEyePos {
                eyeY = (le.y + re.y) / 2
                eyeSpacing = abs(le.x - re.x) / 2
            } else {
                eyeY = center.y + extent.y * 0.15
                eyeSpacing = extent.x * 0.12
            }
            mouthY = mouthPos?.y ?? (center.y - extent.y * 0.1)
            eyeSize = extent.x * 0.07
            mouthSize = extent.x * 0.1
        } else {
            // Auto-place: estimate face on upper-front of model
            eyeY = center.y + extent.y * 0.15
            eyeSpacing = extent.x * 0.12
            mouthY = center.y - extent.y * 0.05
            eyeSize = extent.x * 0.07
            mouthSize = extent.x * 0.1
        }

        let leftEyeX = center.x - eyeSpacing
        let rightEyeX = center.x + eyeSpacing

        // Create googly eyes
        createGooglyEye(at: SIMD3(leftEyeX, eyeY, frontZ), size: eyeSize, isLeft: true, parent: entity)
        createGooglyEye(at: SIMD3(rightEyeX, eyeY, frontZ), size: eyeSize, isLeft: false, parent: entity)

        // Create mouth
        createMouth(at: SIMD3(center.x, mouthY, frontZ), size: mouthSize, parent: entity)

        logger.info("Animator set up. Bounds: \(extent), center: \(center)")
    }

    func startIdleAnimation() {
        guard !isAnimating, let root = rootEntity else { return }
        isAnimating = true

        let baseTransform = root.transform

        // Breathing
        Task {
            while isAnimating {
                var up = baseTransform
                up.scale = baseTransform.scale * (1.0 + breathingAmount)
                root.move(to: up, relativeTo: root.parent, duration: 0.6)
                try? await Task.sleep(for: .milliseconds(600))
                root.move(to: baseTransform, relativeTo: root.parent, duration: 0.6)
                try? await Task.sleep(for: .milliseconds(600))
            }
        }

        // Blinking
        Task {
            while isAnimating {
                try? await Task.sleep(for: .seconds(blinkInterval + Double.random(in: -0.5...1.5)))
                if isAnimating { await blink() }
            }
        }

        // Idle iris look-around
        Task {
            while isAnimating {
                try? await Task.sleep(for: .seconds(Double.random(in: 1.5...4.0)))
                if isAnimating { await lookAround() }
            }
        }

        logger.info("Started idle animation")
    }

    func stopAnimation() {
        isAnimating = false
    }

    /// Speak: rapidly open/close mouth
    func speak(syllables: Int = 8) async {
        isSpeaking = true
        for _ in 0..<syllables {
            setMouthOpen(Float.random(in: 0.4...1.0))
            try? await Task.sleep(for: .milliseconds(Int.random(in: 100...200)))
            setMouthOpen(0)
            try? await Task.sleep(for: .milliseconds(Int.random(in: 50...120)))
        }
        isSpeaking = false
    }

    // MARK: - Private

    private func setMouthOpen(_ amount: Float) {
        guard let mouth = mouthEntity else { return }
        // Scale Y to simulate opening
        var t = Transform.identity
        t.scale = SIMD3<Float>(1 + amount * 0.3, 1 + amount * 0.8, 1)
        t.translation.y = -amount * 0.002
        mouth.move(to: t, relativeTo: mouth.parent, duration: 0.05)
    }

    private func blink() async {
        guard let leftLid = leftEyelid, let rightLid = rightEyelid else { return }

        // Show eyelids (close)
        leftLid.isEnabled = true
        rightLid.isEnabled = true

        try? await Task.sleep(for: .milliseconds(Int(blinkDuration * 1000)))

        // Hide eyelids (open)
        leftLid.isEnabled = false
        rightLid.isEnabled = false
    }

    private func lookAround() async {
        guard let li = leftIris, let ri = rightIris else { return }
        let dx = Float.random(in: -0.002...0.002)
        let dy = Float.random(in: -0.001...0.001)

        var lt = Transform.identity
        lt.translation = SIMD3(dx, dy, 0.0001)
        var rt = Transform.identity
        rt.translation = SIMD3(dx, dy, 0.0001)

        li.move(to: lt, relativeTo: li.parent, duration: 0.3)
        ri.move(to: rt, relativeTo: ri.parent, duration: 0.3)

        try? await Task.sleep(for: .seconds(Double.random(in: 0.5...2.0)))

        // Look back to center
        var center = Transform.identity
        center.translation = SIMD3(0, 0, 0.0001)
        li.move(to: center, relativeTo: li.parent, duration: 0.3)
        ri.move(to: center, relativeTo: ri.parent, duration: 0.3)
    }

    private func createGooglyEye(at position: SIMD3<Float>, size: Float, isLeft: Bool, parent: Entity) {
        // White of the eye
        let whiteMesh = MeshResource.generateSphere(radius: size)
        let whiteMat = SimpleMaterial(color: .white, isMetallic: false)
        let eyeWhite = ModelEntity(mesh: whiteMesh, materials: [whiteMat])
        eyeWhite.position = position

        // Iris (smaller dark sphere on front)
        let irisSize = size * 0.55
        let irisMesh = MeshResource.generateSphere(radius: irisSize)
        let irisMat = SimpleMaterial(color: UIColor(red: 0.15, green: 0.1, blue: 0.05, alpha: 1), isMetallic: false)
        let iris = ModelEntity(mesh: irisMesh, materials: [irisMat])
        iris.position = SIMD3(0, 0, size * 0.5) // In front of eyeWhite center

        // Pupil (even smaller black sphere)
        let pupilSize = irisSize * 0.5
        let pupilMesh = MeshResource.generateSphere(radius: pupilSize)
        let pupilMat = SimpleMaterial(color: .black, isMetallic: false)
        let pupil = ModelEntity(mesh: pupilMesh, materials: [pupilMat])
        pupil.position = SIMD3(0, 0, irisSize * 0.4)
        iris.addChild(pupil)

        eyeWhite.addChild(iris)

        // Eyelid (flattened sphere, same color as model surface, hidden by default)
        let lidMesh = MeshResource.generateSphere(radius: size * 1.05)
        let lidMat = SimpleMaterial(color: UIColor(red: 0.9, green: 0.7, blue: 0.7, alpha: 1), isMetallic: false)
        let lid = ModelEntity(mesh: lidMesh, materials: [lidMat])
        lid.scale = SIMD3(1, 0.9, 0.5) // Flattened to cover front
        lid.position = SIMD3(0, 0, size * 0.1)
        lid.isEnabled = false // Hidden until blink
        eyeWhite.addChild(lid)

        parent.addChild(eyeWhite)

        if isLeft {
            leftEyeWhite = eyeWhite
            leftIris = iris
            leftEyelid = lid
        } else {
            rightEyeWhite = eyeWhite
            rightIris = iris
            rightEyelid = lid
        }
    }

    private func createMouth(at position: SIMD3<Float>, size: Float, parent: Entity) {
        // Simple red oval mouth
        let mouthMesh = MeshResource.generateSphere(radius: size)
        let mouthMat = SimpleMaterial(color: UIColor(red: 0.85, green: 0.2, blue: 0.2, alpha: 1), isMetallic: false)
        let mouth = ModelEntity(mesh: mouthMesh, materials: [mouthMat])
        mouth.position = position
        mouth.scale = SIMD3(1.5, 0.5, 0.3) // Wide, thin, flat

        parent.addChild(mouth)
        mouthEntity = mouth
    }
}
