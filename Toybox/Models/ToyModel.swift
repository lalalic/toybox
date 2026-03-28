import Foundation

/// Represents a scanned toy with its metadata and file references.
struct ToyModel: Identifiable, Codable {
    let id: UUID
    var name: String
    let createdAt: Date
    var modelFileName: String?  // Relative to toy's directory

    /// The directory containing this toy's assets (images, model, etc.)
    var directoryName: String { id.uuidString }

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
