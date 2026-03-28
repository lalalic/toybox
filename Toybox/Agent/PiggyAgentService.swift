import Foundation
import Observation
import AVFoundation
import CopilotSDK
import os

private let piggyAgentLogger = Logger(subsystem: ToyboxConstants.subsystem, category: "PiggyAgent")

@Observable
@MainActor
final class PiggyAgentService {
	var isConnected = false
	var isThinking = false
	var lastReply = ""
	var lastError: String?
	var pendingGesture: PiggyGestureAction?
	var relayHost = UserDefaults.standard.string(forKey: "piggy.relayHost") ?? "relay.ai.qili2.com"
	var relayPort: UInt16 = {
		let value = UserDefaults.standard.integer(forKey: "piggy.relayPort")
		return value > 0 ? UInt16(value) : 8765
	}()

	@ObservationIgnored private var client: CopilotClient?
	@ObservationIgnored private var session: CopilotSession?
	@ObservationIgnored private let speaker = AVSpeechSynthesizer()
	@ObservationIgnored private let store = PiggyRelaySessionStore.shared
	@ObservationIgnored private var activePersonaSignature: String?

	func ask(_ userMessage: String, as toyName: String, settings: PiggyPersonaSettings) async -> String? {
		let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }

		isThinking = true
		lastError = nil
		defer { isThinking = false }

		do {
			let session = try await ensureSession(for: toyName, settings: settings)
			let prompt = """
			You are \(toyName), a cute toy pig living on the user's iPhone.
			Reply in first person as the toy.
			Your personality is: \(settings.personality).
			Your age vibe is: \(settings.age.promptText).
			Your speaking style is: \(settings.voice.promptText).
			Keep the reply short, warm, playful, encouraging, and under 2 sentences.
			Sound like a beloved toy friend, not a generic assistant.
			If the moment feels expressive, you may use one gesture tool before replying.
			No markdown.

			User says: \(trimmed)
			"""

			guard let reply = try await session.sendAndWait(prompt: prompt, timeout: 45) else {
				throw PiggyAgentError.emptyReply
			}

			if let snapshot = session.snapshotData {
				store.saveSnapshot(snapshot, timestamp: session.snapshotTimestamp)
			}

			lastReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
			speak(lastReply)
			return lastReply
		} catch {
			let message = error.localizedDescription
			piggyAgentLogger.error("Piggy agent failed: \(message)")
			lastError = message
			return nil
		}
	}

	func disconnect() {
		Task {
			if let session {
				try? await session.disconnect()
			}
			speaker.stopSpeaking(at: .immediate)
			client?.disconnect()
			session = nil
			client = nil
			activePersonaSignature = nil
			isConnected = false
		}
	}

	func clearPendingGesture() {
		pendingGesture = nil
	}

	private func ensureSession(for toyName: String, settings: PiggyPersonaSettings) async throws -> CopilotSession {
		let signature = "\(toyName)|\(settings.personality)|\(settings.age.rawValue)|\(settings.voice.rawValue)"
		if activePersonaSignature != signature, session != nil {
			disconnect()
		}

		if let session {
			return session
		}

		let transport = WebSocketTransport(host: relayHost, port: relayPort)
		let client = CopilotClient(transport: transport)
		try await client.start()

		store.lastRelayHost = relayHost
		store.lastRelayPort = relayPort

		let tools = buildGestureTools()

		let config = SessionConfig(
			model: "gpt-4.1",
			tools: tools,
			systemMessage: .append("You are \(toyName), a scanned pig toy companion living in Toybox on iPhone. Your personality is \(settings.personality). Your age vibe is \(settings.age.promptText). Your voice style is \(settings.voice.promptText). You are affectionate, child-safe, playful, and emotionally warm. Speak like a tiny best friend with a gentle piggy personality. Stay in character as the toy, keep answers concise, and avoid sounding like a generic AI assistant. When fitting, you may call one of your gesture tools to animate your body before you speak."),
			clientId: store.clientId,
			snapshot: store.savedSnapshot,
			onPermissionRequest: { _ in .approved }
		)

		let session = try await client.createSession(config: config)
		if let snapshot = session.snapshotData {
			store.saveSnapshot(snapshot, timestamp: session.snapshotTimestamp)
		}

		self.client = client
		self.session = session
		self.activePersonaSignature = signature
		self.isConnected = true

		piggyAgentLogger.info("Piggy agent connected via relay \(self.relayHost):\(self.relayPort)")
		return session
	}

	private func speak(_ text: String) {
		guard !text.isEmpty else { return }
		do {
			let audioSession = AVAudioSession.sharedInstance()
			try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker])
			try audioSession.setActive(true)
		} catch {
			piggyAgentLogger.error("Failed to configure audio session: \(error.localizedDescription)")
		}
		speaker.stopSpeaking(at: .immediate)
		let utterance = AVSpeechUtterance(string: text)
		utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
		let settings = PiggyPersonaSettingsStore.shared.load()
		utterance.rate = settings.voice.rate
		utterance.pitchMultiplier = settings.voice.pitch
		utterance.volume = 1.0
		speaker.speak(utterance)
	}

	private func buildGestureTools() -> [ToolDefinition] {
		[
			ToolDefinition(name: "wiggle", description: "Make Piggy wiggle happily.", skipPermission: true) { [weak self] _ in
				await MainActor.run { self?.pendingGesture = .wiggle }
				return "Piggy wiggled."
			},
			ToolDefinition(name: "spin", description: "Make Piggy do a playful spin.", skipPermission: true) { [weak self] _ in
				await MainActor.run { self?.pendingGesture = .spin }
				return "Piggy spun around."
			},
			ToolDefinition(name: "blink", description: "Make Piggy blink cutely.", skipPermission: true) { [weak self] _ in
				await MainActor.run { self?.pendingGesture = .blink }
				return "Piggy blinked."
			},
		]
	}
}

enum PiggyGestureAction: String, Sendable {
	case wiggle
	case spin
	case blink
}

private enum PiggyAgentError: LocalizedError {
	case emptyReply

	var errorDescription: String? {
		switch self {
		case .emptyReply:
			return "Piggy did not answer."
		}
	}
}

private final class PiggyRelaySessionStore: @unchecked Sendable {
	static let shared = PiggyRelaySessionStore()

	var clientId: String {
		if let existing = UserDefaults.standard.string(forKey: Keys.clientId) {
			return existing
		}
		let value = "piggy-\(UUID().uuidString.prefix(12).lowercased())"
		UserDefaults.standard.set(value, forKey: Keys.clientId)
		return value
	}

	var savedSnapshot: String? {
		UserDefaults.standard.string(forKey: Keys.snapshot)
	}

	func saveSnapshot(_ data: String?, timestamp: Int? = nil) {
		if let data {
			UserDefaults.standard.set(data, forKey: Keys.snapshot)
			UserDefaults.standard.set(timestamp ?? Int(Date().timeIntervalSince1970), forKey: Keys.snapshotTimestamp)
		} else {
			UserDefaults.standard.removeObject(forKey: Keys.snapshot)
			UserDefaults.standard.removeObject(forKey: Keys.snapshotTimestamp)
		}
	}

	var lastRelayHost: String? {
		get { UserDefaults.standard.string(forKey: Keys.lastRelayHost) }
		set { UserDefaults.standard.set(newValue, forKey: Keys.lastRelayHost) }
	}

	var lastRelayPort: UInt16? {
		get {
			let value = UserDefaults.standard.integer(forKey: Keys.lastRelayPort)
			return value > 0 ? UInt16(value) : nil
		}
		set {
			if let newValue {
				UserDefaults.standard.set(Int(newValue), forKey: Keys.lastRelayPort)
			} else {
				UserDefaults.standard.removeObject(forKey: Keys.lastRelayPort)
			}
		}
	}

	private enum Keys {
		static let clientId = "piggy.relay.clientId"
		static let snapshot = "piggy.relay.snapshot"
		static let snapshotTimestamp = "piggy.relay.snapshotTimestamp"
		static let lastRelayHost = "piggy.relay.lastHost"
		static let lastRelayPort = "piggy.relay.lastPort"
	}

	private init() {}
}
