import Foundation

/// Represents a scanned toy with its metadata and file references.
struct ToyModel: Identifiable, Codable {
    let id: UUID
    var name: String
    let createdAt: Date
    var modelFileName: String?  // Relative to toy's directory
    var features: [ToyFeature] = []

    /// The directory containing this toy's assets (images, model, etc.)
    var directoryName: String { id.uuidString }

    /// Whether all core features have been annotated.
    var isFullyAnnotated: Bool {
        let kinds = Set(features.map(\.kind))
        return kinds.contains(.leftEye) && kinds.contains(.rightEye) &&
               kinds.contains(.mouth) && kinds.contains(.bodyCenter)
    }

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    /// Resume from an existing capture directory (whose name is a UUID)
    init(existingID: UUID, name: String) {
        self.id = existingID
        self.name = name
        self.createdAt = Date()
    }
}
