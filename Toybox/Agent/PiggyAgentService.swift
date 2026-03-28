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
	var relayHost = UserDefaults.standard.string(forKey: "piggy.relayHost") ?? "relay.ai.qili2.com"
	var relayPort: UInt16 = {
		let value = UserDefaults.standard.integer(forKey: "piggy.relayPort")
		return value > 0 ? UInt16(value) : 8765
	}()

	@ObservationIgnored private var client: CopilotClient?
	@ObservationIgnored private var session: CopilotSession?
	@ObservationIgnored private let speaker = AVSpeechSynthesizer()
	@ObservationIgnored private let store = PiggyRelaySessionStore.shared

	func ask(_ userMessage: String, as toyName: String) async -> String? {
		let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }

		isThinking = true
		lastError = nil
		defer { isThinking = false }

		do {
			let session = try await ensureSession(for: toyName)
			let prompt = """
			You are \(toyName), a cute toy pig living on the user's iPhone.
			Reply in first person as the toy.
			Keep the reply short, warm, playful, encouraging, and under 2 sentences.
			Sound like a beloved toy friend, not a generic assistant.
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
			client?.disconnect()
			session = nil
			client = nil
			isConnected = false
		}
	}

	private func ensureSession(for toyName: String) async throws -> CopilotSession {
		if let session {
			return session
		}

		let transport = WebSocketTransport(host: relayHost, port: relayPort)
		let client = CopilotClient(transport: transport)
		try await client.start()

		store.lastRelayHost = relayHost
		store.lastRelayPort = relayPort

		let config = SessionConfig(
			model: "gpt-4.1",
			systemMessage: .append("You are \(toyName), a scanned pig toy companion living in Toybox on iPhone. You are affectionate, child-safe, playful, and emotionally warm. Speak like a tiny best friend with a gentle piggy personality. Stay in character as the toy, keep answers concise, and avoid sounding like a generic AI assistant."),
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
		self.isConnected = true

		piggyAgentLogger.info("Piggy agent connected via relay \(self.relayHost):\(self.relayPort)")
		return session
	}

	private func speak(_ text: String) {
		guard !text.isEmpty else { return }
		speaker.stopSpeaking(at: .immediate)
		let utterance = AVSpeechUtterance(string: text)
		utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
		utterance.rate = 0.44
		utterance.pitchMultiplier = 1.32
		utterance.volume = 1.0
		speaker.speak(utterance)
	}
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
