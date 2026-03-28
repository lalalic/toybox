import Foundation

enum PiggyAgePreset: String, CaseIterable, Codable, Identifiable {
    case baby
    case kid
    case teen
    case grown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .baby: return "Baby"
        case .kid: return "Kid"
        case .teen: return "Teen"
        case .grown: return "Grown"
        }
    }

    var promptText: String {
        switch self {
        case .baby: return "very young, innocent, and tiny"
        case .kid: return "young, cheerful, and playful"
        case .teen: return "energetic, curious, and expressive"
        case .grown: return "gentle, thoughtful, and reassuring"
        }
    }
}

enum PiggyVoicePreset: String, CaseIterable, Codable, Identifiable {
    case cute
    case calm
    case bright

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }

    var rate: Float {
        switch self {
        case .cute: return 0.43
        case .calm: return 0.4
        case .bright: return 0.47
        }
    }

    var pitch: Float {
        switch self {
        case .cute: return 1.34
        case .calm: return 1.1
        case .bright: return 1.24
        }
    }

    var promptText: String {
        switch self {
        case .cute: return "cute and cuddly"
        case .calm: return "soft and calm"
        case .bright: return "bright and upbeat"
        }
    }
}

struct PiggyPersonaSettings: Codable, Equatable {
    var personality: String = "playful, affectionate, and curious"
    var age: PiggyAgePreset = .kid
    var voice: PiggyVoicePreset = .cute

    static let `default` = PiggyPersonaSettings()
}

@MainActor
final class PiggyPersonaSettingsStore {
    static let shared = PiggyPersonaSettingsStore()

    private let defaults = UserDefaults.standard
    private let key = "piggy.persona.settings"

    func load() -> PiggyPersonaSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(PiggyPersonaSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: PiggyPersonaSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    private init() {}
}
