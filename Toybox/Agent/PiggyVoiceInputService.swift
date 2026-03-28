import AVFoundation
import Observation
import Speech

@Observable
@MainActor
final class PiggyVoiceInputService {
    var isRecording = false
    var transcribedText = ""
    var finalTranscript: String?
    var soundLevel: Float = 0
    var errorMessage: String?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    func startRecording() {
        finalTranscript = nil
        transcribedText = ""
        errorMessage = nil

        guard AVAudioApplication.shared.recordPermission == .granted else {
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor [weak self] in
                    self?.errorMessage = granted
                        ? "Microphone access approved. Tap the mic again to talk to Piggy."
                        : "Microphone permission is required."
                }
            }
            return
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor [weak self] in
                    self?.errorMessage = status == .authorized
                        ? "Speech access approved. Tap the mic again to talk to Piggy."
                        : "Speech recognition permission is required."
                }
            }
            return
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available right now."
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let inputNode = engine.inputNode
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                request.append(buffer)
                guard let self, let channelData = buffer.floatChannelData else { return }
                let frames = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frames {
                    let sample = channelData[0][i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(max(frames, 1)))
                let db = 20 * log10(max(rms, 1e-10))
                let level = max(0, min(1, (db + 50) / 50))
                Task { @MainActor in
                    self.soundLevel = level
                }
            }

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    Task { @MainActor in
                        self.transcribedText = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.finishRecording(commitTranscript: true)
                        }
                    }
                }
                if error != nil {
                    Task { @MainActor in
                        self.errorMessage = error?.localizedDescription ?? "Speech recognition failed."
                        self.finishRecording(commitTranscript: true)
                    }
                }
            }

            try engine.start()
            audioEngine = engine
            recognitionRequest = request
            isRecording = true
            soundLevel = 0
        } catch {
            errorMessage = error.localizedDescription
            finishRecording(commitTranscript: false)
        }
    }

    func stopRecordingAndSubmit() {
        finishRecording(commitTranscript: true)
    }

    func cancelRecording() {
        finishRecording(commitTranscript: false)
    }

    private func finishRecording(commitTranscript: Bool) {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        soundLevel = 0

        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        finalTranscript = commitTranscript && !text.isEmpty ? text : nil
    }
}
