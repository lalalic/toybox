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
    @State private var piggyAgent = PiggyAgentService()
    @State private var voiceInput = PiggyVoiceInputService()
    @State private var personaSettings = PiggyPersonaSettingsStore.shared.load()
    @State private var showSetup = false

    // Orbit state
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0.2
    @State private var dragStartYaw: Float = 0
    @State private var dragStartPitch: Float = 0
    @State private var cameraDistance: Float = 1.0
    @State private var pinchStartDistance: Float = 1.0

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
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
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
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let ratio = Float(value.magnification)
                            cameraDistance = max(0.3, min(5.0, pinchStartDistance * ratio))
                            updateZoom()
                        }
                        .onEnded { _ in
                            pinchStartDistance = cameraDistance
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
                            showSetup = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.8))
                        }

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

                    piggyChatPanel
                        .padding(.horizontal)
                    .padding(.bottom, 30)
                }
                .transition(.opacity)
            }
        }
        .onDisappear {
            piggyAgent.disconnect()
            voiceInput.cancelRecording()
        }
        .onChange(of: voiceInput.finalTranscript) { _, transcript in
            guard let transcript, !transcript.isEmpty else { return }
            sendToPiggy(transcript)
        }
        .onChange(of: piggyAgent.pendingGesture) { _, gesture in
            guard let gesture else { return }
            performGesture(gesture)
            piggyAgent.clearPendingGesture()
        }
        .sheet(isPresented: $showSetup) {
            PiggySetupSheet(settings: $personaSettings) {
                PiggyPersonaSettingsStore.shared.save(personaSettings)
                piggyAgent.disconnect()
            }
        }
    }

    private func updateRotation() {
        guard let pivot = pivotEntity else { return }
        let yawQ = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let pitchQ = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        pivot.orientation = yawQ * pitchQ
    }

    private func updateZoom() {
        guard let pivot = pivotEntity else { return }
        pivot.scale = SIMD3<Float>(repeating: cameraDistance)
    }

    private var piggyChatPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    piggyAgent.isConnected ? "Piggy agent online" : "Piggy agent",
                    systemImage: piggyAgent.isConnected ? "brain.filled.head.profile" : "brain"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))

                Spacer()

                if piggyAgent.isThinking {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                }
            }

            if !piggyAgent.lastReply.isEmpty {
                Text(piggyAgent.lastReply)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else if let error = piggyAgent.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else if voiceInput.isRecording || !voiceInput.transcribedText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text(voiceInput.isRecording ? "Listening..." : "Heard")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Text(voiceInput.transcribedText.isEmpty ? "Say something to Piggy" : voiceInput.transcribedText)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else if let voiceError = voiceInput.errorMessage {
                Text(voiceError)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }

            Button {
                toggleVoiceInput()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: voiceInput.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(voiceInput.isRecording ? "Tap to stop" : "Tap to talk")
                            .font(.headline)

                        Text(piggyAgent.isThinking ? "Piggy is thinking..." : "Speech only")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }

                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(voiceInput.isRecording ? .red : .pink)
            .disabled(piggyAgent.isThinking)
        }
        .padding(14)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
    }

    private func toggleVoiceInput() {
        print("[LivingToy] toggleVoiceInput – isRecording=\(voiceInput.isRecording) isThinking=\(piggyAgent.isThinking)")
        if voiceInput.isRecording {
            voiceInput.stopRecordingAndSubmit()
        } else {
            voiceInput.startRecording()
        }
    }

    private func performGesture(_ gesture: PiggyGestureAction) {
        switch gesture {
        case .wiggle:
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
        case .spin:
            Task {
                for i in 0..<36 {
                    yaw = dragStartYaw + Float(i) * (.pi * 2 / 36)
                    updateRotation()
                    try? await Task.sleep(for: .milliseconds(30))
                }
                dragStartYaw = yaw
            }
        case .blink:
            Task {
                await animator.speak(syllables: 2)
            }
        }
    }

    private func sendToPiggy(_ message: String) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        Task {
            if let reply = await piggyAgent.ask(text, as: toy.name, settings: personaSettings) {
                let syllables = max(8, min(28, reply.count / 4))
                await animator.speak(syllables: syllables)
            }
        }
    }

}

private struct PiggySetupSheet: View {
    @Binding var settings: PiggyPersonaSettings
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Personality") {
                    TextField("Playful, affectionate, curious...", text: $settings.personality)
                }

                Section("Age") {
                    Picker("Age", selection: $settings.age) {
                        ForEach(PiggyAgePreset.allCases) { age in
                            Text(age.label).tag(age)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Voice") {
                    Picker("Voice", selection: $settings.voice) {
                        ForEach(PiggyVoicePreset.allCases) { voice in
                            Text(voice.label).tag(voice)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Piggy Setup")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}
