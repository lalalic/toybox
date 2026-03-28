import AVFoundation
import Observation
import Speech

@Observable
@MainActor
final class PiggyVoiceInputService {
    var isRecording = false
    var transcribedText = ""
    var finalTranscript: String?
    var errorMessage: String?

    @ObservationIgnored private var isStarting = false

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    func startRecording() {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        finalTranscript = nil
        transcribedText = ""
        errorMessage = nil

        guard AVAudioApplication.shared.recordPermission == .granted else {
            isStarting = false
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
            isStarting = false
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
            isStarting = false
            errorMessage = "Speech recognition is not available right now."
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
            try AVAudioSession.sharedInstance().setActive(true)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = false

            let inputNode = engine.inputNode
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let transcript = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let failureMessage = error?.localizedDescription

                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if let transcript {
                        self.transcribedText = transcript
                        if isFinal {
                            self.finishRecording(commitTranscript: true)
                        }
                    }

                    if let failureMessage {
                        self.errorMessage = failureMessage
                        self.finishRecording(commitTranscript: true)
                    }
                }
            }

            try engine.start()
            audioEngine = engine
            recognitionRequest = request
            isRecording = true
            isStarting = false
        } catch {
            isStarting = false
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
        isStarting = false
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = errorMessage ?? error.localizedDescription
        }

        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        finalTranscript = commitTranscript && !text.isEmpty ? text : nil
    }
}
