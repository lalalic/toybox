import Foundation
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "ToyStore")

/// Persistence layer for scanned toys.
@Observable
@MainActor
final class ToyStore {
    private(set) var toys: [ToyModel] = []
    private let toysFile: URL

    init() {
        let docs = URL.documentsDirectory
        toysFile = docs.appendingPathComponent("toys.json")
        load()
    }

    func add(_ toy: ToyModel) {
        toys.insert(toy, at: 0)
        save()
    }

    func update(_ toy: ToyModel) {
        if let index = toys.firstIndex(where: { $0.id == toy.id }) {
            toys[index] = toy
            save()
        }
    }

    func delete(_ toy: ToyModel) {
        toys.removeAll { $0.id == toy.id }
        // Delete toy's directory
        let toyDir = URL.documentsDirectory.appendingPathComponent(toy.directoryName)
        try? FileManager.default.removeItem(at: toyDir)
        save()
    }

    func modelURL(for toy: ToyModel) -> URL? {
        guard let modelFileName = toy.modelFileName else { return nil }
        return URL.documentsDirectory
            .appendingPathComponent(toy.directoryName)
            .appendingPathComponent("Models")
            .appendingPathComponent(modelFileName)
    }

    // MARK: - Private

    private func load() {
        guard FileManager.default.fileExists(atPath: toysFile.path) else { return }
        do {
            let data = try Data(contentsOf: toysFile)
            toys = try JSONDecoder().decode([ToyModel].self, from: data)
            logger.info("Loaded \(self.toys.count) toys")
        } catch {
            logger.error("Failed to load toys: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(toys)
            try data.write(to: toysFile, options: .atomic)
            logger.info("Saved \(self.toys.count) toys")
        } catch {
            logger.error("Failed to save toys: \(error)")
        }
    }
}
