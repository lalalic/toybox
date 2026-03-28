import SwiftUI
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "ToyGallery")

/// Grid view showing all scanned toys.
struct ToyGallery: View {
    @Environment(AppModel.self) var appModel
    @State private var showNewScanSheet = false
    @State private var showImportPicker = false
    @State private var newToyName = ""
    @State private var selectedToy: ToyModel?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if appModel.toyStore.toys.isEmpty {
                    emptyState
                } else {
                    toyGrid
                }
            }
            .navigationTitle("Toybox")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if appModel.isScanningSupported {
                            Button {
                                showNewScanSheet = true
                            } label: {
                                Label("Scan New Toy", systemImage: "camera.viewfinder")
                            }
                        }

                        Button {
                            showImportPicker = true
                        } label: {
                            Label("Import USDZ", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showNewScanSheet) {
                newScanSheet
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [UTType(filenameExtension: "usdz")!],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .fullScreenCover(item: $selectedToy) { toy in
                if let url = appModel.toyStore.modelURL(for: toy) {
                    ModelViewer(modelURL: url, toyName: toy.name, onAnnotate: {
                        selectedToy = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            appModel.annotateToy(toy)
                        }
                    }) {
                        selectedToy = nil
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            Text("No Toys Yet")
                .font(.title2)
                .fontWeight(.bold)

            Text("Scan your favorite toy to bring it to life!")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if appModel.isScanningSupported {
                Button {
                    showNewScanSheet = true
                } label: {
                    Label("Scan a Toy", systemImage: "camera.viewfinder")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text("LiDAR Required")
                        .font(.headline)
                    Text("3D scanning needs a device with LiDAR sensor.\nYou can still view toys scanned on another device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            // Import option always available
            Button {
                showImportPicker = true
            } label: {
                Label("Import USDZ Model", systemImage: "square.and.arrow.down")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding()
    }

    private var toyGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(appModel.toyStore.toys) { toy in
                    ToyCard(toy: toy) {
                        selectedToy = toy
                    }
                    .contextMenu {
                        if toy.features.count > 0 {
                            Button {
                                appModel.bringToLife(toy)
                            } label: {
                                Label("Bring to Life!", systemImage: "sparkles")
                            }
                        }

                        Button {
                            appModel.annotateToy(toy)
                        } label: {
                            Label("Mark Features", systemImage: "hand.point.up.left.fill")
                        }

                        Button(role: .destructive) {
                            appModel.toyStore.delete(toy)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var newScanSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Name Your Toy")
                    .font(.title2)
                    .fontWeight(.bold)

                TextField("e.g., Piggy", text: $newToyName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                Button("Start Scanning") {
                    guard !newToyName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    showNewScanSheet = false
                    appModel.startNewScan(toyName: newToyName.trimmingCharacters(in: .whitespaces))
                    newToyName = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(newToyName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .navigationTitle("New Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showNewScanSheet = false
                        newToyName = ""
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Import Handler

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else { return }

            // Get file name without extension as toy name
            let name = sourceURL.deletingPathExtension().lastPathComponent

            // Create toy
            var toy = ToyModel(name: name)
            let modelFileName = "model.usdz"
            toy.modelFileName = modelFileName

            // Create directory and copy file
            let toyDir = URL.documentsDirectory.appendingPathComponent(toy.directoryName)
            let modelsDir = toyDir.appendingPathComponent("Models")

            do {
                try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

                // Start security-scoped access
                guard sourceURL.startAccessingSecurityScopedResource() else {
                    logger.error("Failed to access security-scoped resource")
                    return
                }
                defer { sourceURL.stopAccessingSecurityScopedResource() }

                let destURL = modelsDir.appendingPathComponent(modelFileName)
                try FileManager.default.copyItem(at: sourceURL, to: destURL)

                appModel.toyStore.add(toy)
                logger.info("Imported toy: \(name) from \(sourceURL.lastPathComponent)")
            } catch {
                logger.error("Import failed: \(error)")
            }

        case .failure(let error):
            logger.error("File picker failed: \(error)")
        }
    }
}

/// Card view for a single toy in the gallery grid.
struct ToyCard: View {
    let toy: ToyModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Thumbnail placeholder (later: render 3D preview)
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .aspectRatio(1, contentMode: .fit)

                    Image(systemName: "cube.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue.opacity(0.7))
                }

                Text(toy.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(toy.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
