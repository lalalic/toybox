import SwiftUI
import RealityKit
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "AnnotationView")

/// Interactive view for annotating toy features (eyes, mouth, body) on the 3D model.
/// User positions a crosshair over the desired feature location, then taps "Place".
/// The feature is placed by raycasting from the camera through the crosshair into the model.
struct AnnotationView: View {
    @Environment(AppModel.self) var appModel
    let modelURL: URL
    @Binding var toy: ToyModel

    @State private var selectedFeatureKind: ToyFeature.Kind = .leftEye
    @State private var rootAnchor: AnchorEntity?
    @State private var modelScale: Float = 1.0
    @State private var markerEntities: [UUID: ModelEntity] = [:]

    // Rotation state for manual model rotation
    @State private var rotationAngle: Angle = .zero
    @State private var lastDragAngle: Angle = .zero
    @State private var verticalAngle: Angle = .zero
    @State private var lastVerticalAngle: Angle = .zero

    // Position editor for precise feature placement
    @State private var editingPosition = SIMD3<Float>(0, 0, 0)
    @State private var showPositionEditor = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Mark Features")
                    .font(.headline)

                Spacer()

                Button("Done") {
                    appModel.toyStore.update(toy)
                    appModel.returnHome()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            // 3D model view with rotation
            ZStack {
                RealityView { content in
                    do {
                        let entity = try await ModelEntity(contentsOf: modelURL)

                        let bounds = entity.visualBounds(relativeTo: nil)
                        let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
                        let scale = 0.15 / maxExtent
                        modelScale = scale
                        entity.scale = SIMD3<Float>(repeating: scale)
                        entity.position = -bounds.center * scale

                        let anchor = AnchorEntity()
                        anchor.addChild(entity)
                        content.add(anchor)
                        rootAnchor = anchor

                        // Add existing markers
                        for feature in toy.features {
                            addMarker(for: feature, to: anchor)
                        }

                        logger.info("Model loaded for annotation")
                    } catch {
                        logger.error("Failed to load model: \(error)")
                    }
                } update: { content in
                    // Apply rotation from drag gesture
                    if let anchor = rootAnchor {
                        let yaw = simd_quatf(angle: Float(rotationAngle.radians), axis: SIMD3<Float>(0, 1, 0))
                        let pitch = simd_quatf(angle: Float(verticalAngle.radians), axis: SIMD3<Float>(1, 0, 0))
                        anchor.orientation = yaw * pitch
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let deltaX = value.translation.width
                            let deltaY = value.translation.height
                            rotationAngle = lastDragAngle + .degrees(Double(deltaX) * 0.5)
                            verticalAngle = lastVerticalAngle + .degrees(Double(deltaY) * 0.3)
                        }
                        .onEnded { _ in
                            lastDragAngle = rotationAngle
                            lastVerticalAngle = verticalAngle
                        }
                )

                // Crosshair overlay
                Image(systemName: "plus")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.05))

            // Feature selector
            featureSelector

            // Place button + progress
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    Button {
                        placeFeatureAtCenter()
                    } label: {
                        Label("Place \(selectedFeatureKind.rawValue)", systemImage: "mappin.and.ellipse")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if showPositionEditor {
                        Button {
                            showPositionEditor = false
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Fine-tune controls
                if showPositionEditor {
                    positionEditor
                }

                annotationProgress
            }
            .padding()
        }
    }

    // MARK: - Feature Selector

    private var featureSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ToyFeature.Kind.allCases, id: \.self) { kind in
                    featureButton(kind)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private func featureButton(_ kind: ToyFeature.Kind) -> some View {
        let isSelected = selectedFeatureKind == kind
        let isPlaced = toy.features.contains { $0.kind == kind }

        return Button {
            selectedFeatureKind = kind
            // If this feature already exists, load its position
            if let existing = toy.features.first(where: { $0.kind == kind }) {
                editingPosition = existing.position
                showPositionEditor = true
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : (isPlaced ? Color.green.opacity(0.3) : Color.gray.opacity(0.3)))
                        .frame(width: 50, height: 50)

                    Image(systemName: kind.systemImage)
                        .font(.title3)
                        .foregroundStyle(isSelected ? .white : (isPlaced ? .green : .primary))

                    if isPlaced {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .offset(x: 18, y: -18)
                    }
                }

                Text(kind.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Position Editor

    private var positionEditor: some View {
        VStack(spacing: 4) {
            positionSlider(label: "X", value: $editingPosition.x)
            positionSlider(label: "Y", value: $editingPosition.y)
            positionSlider(label: "Z", value: $editingPosition.z)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: editingPosition) {
            updateCurrentFeaturePosition()
        }
    }

    private func positionSlider(label: String, value: Binding<Float>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 16)
            Slider(value: value, in: -0.15...0.15, step: 0.001)
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.caption)
                .monospacedDigit()
                .frame(width: 50)
        }
    }

    // MARK: - Progress

    private var annotationProgress: some View {
        let placed = Set(toy.features.map(\.kind)).count
        let total = ToyFeature.Kind.allCases.count

        return HStack {
            Text("\(placed)/\(total) features marked")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if toy.isFullyAnnotated {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Feature Placement

    /// Place a feature at the model's center (from current viewing angle).
    /// The user rotates the model so the desired feature faces the camera,
    /// then taps "Place" — the marker goes at position (0,0,0) in model space
    /// which the user can then fine-tune.
    private func placeFeatureAtCenter() {
        // Calculate a position along the viewing direction
        // The model is centered, so (0,0,0) is the center
        // We'll place at the model surface facing the camera
        let forwardDir = SIMD3<Float>(
            -sin(Float(rotationAngle.radians)),
            sin(Float(verticalAngle.radians)),
            -cos(Float(rotationAngle.radians))
        )
        // Place marker at about 80% of the model radius in the forward direction
        let surfacePos = normalize(forwardDir) * (0.15 * 0.4)

        editingPosition = surfacePos
        showPositionEditor = true

        // Remove existing feature of same kind
        removeFeature(kind: selectedFeatureKind)

        // Add new feature
        let feature = ToyFeature(kind: selectedFeatureKind, position: surfacePos)
        toy.features.append(feature)

        // Add marker
        if let anchor = rootAnchor {
            addMarker(for: feature, to: anchor)
        }

        logger.info("Placed \(selectedFeatureKind.rawValue) at (\(surfacePos.x), \(surfacePos.y), \(surfacePos.z))")

        // Auto-advance to next unplaced feature
        advanceToNextFeature()
    }

    private func updateCurrentFeaturePosition() {
        guard let index = toy.features.firstIndex(where: { $0.kind == selectedFeatureKind }) else { return }
        let feature = toy.features[index]
        toy.features[index].position = editingPosition

        // Update marker position
        if let marker = markerEntities[feature.id] {
            marker.position = editingPosition
        }
    }

    private func removeFeature(kind: ToyFeature.Kind) {
        if let index = toy.features.firstIndex(where: { $0.kind == kind }) {
            let existing = toy.features[index]
            markerEntities[existing.id]?.removeFromParent()
            markerEntities.removeValue(forKey: existing.id)
            toy.features.remove(at: index)
        }
    }

    private func addMarker(for feature: ToyFeature, to parent: Entity) {
        let sphere = MeshResource.generateSphere(radius: 0.005)
        let color: UIColor = switch feature.kind {
        case .leftEye: .systemBlue
        case .rightEye: .systemCyan
        case .mouth: .systemRed
        case .nose: .systemOrange
        case .bodyCenter: .systemGreen
        case .head: .systemPurple
        }
        let material = SimpleMaterial(color: color.withAlphaComponent(0.9), isMetallic: false)
        let marker = ModelEntity(mesh: sphere, materials: [material])
        marker.position = feature.position
        parent.addChild(marker)
        markerEntities[feature.id] = marker
    }

    private func advanceToNextFeature() {
        let placedKinds = Set(toy.features.map(\.kind))
        if let next = ToyFeature.Kind.allCases.first(where: { !placedKinds.contains($0) }) {
            selectedFeatureKind = next
        }
    }
}
