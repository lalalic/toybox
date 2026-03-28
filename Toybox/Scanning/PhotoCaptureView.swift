import SwiftUI
import AVFoundation
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "PhotoCapture")

/// Camera preview + photo capture for non-LiDAR devices.
/// Takes multiple photos around an object for photogrammetry reconstruction.
struct PhotoCaptureView: View {
    @Environment(AppModel.self) var appModel
    let folderManager: CaptureFolderManager

    @State private var captureManager = CameraManager()
    @State private var photoCount = 0
    @State private var showGuidance = true
    @State private var lastCaptureFlash = false

    private let minimumPhotos = 20
    private let recommendedPhotos = 40

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: captureManager.captureSession)
                .ignoresSafeArea()

            // Overlay
            VStack {
                // Top bar
                HStack {
                    Button {
                        appModel.returnHome()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    // Photo counter
                    Label("\(photoCount)", systemImage: "photo.stack")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding()

                Spacer()

                // Guidance text
                if showGuidance {
                    guidanceOverlay
                        .transition(.opacity)
                }

                Spacer()

                // Bottom controls
                HStack(alignment: .center, spacing: 40) {
                    // Photo count progress
                    VStack(spacing: 4) {
                        Text("\(photoCount)/\(recommendedPhotos)")
                            .font(.caption)
                            .fontWeight(.semibold)
                        ProgressView(value: Double(photoCount), total: Double(recommendedPhotos))
                            .frame(width: 60)
                            .tint(photoCount >= minimumPhotos ? .green : .white)
                    }

                    // Capture button
                    Button {
                        capturePhoto()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 72, height: 72)
                            Circle()
                                .stroke(.white, lineWidth: 4)
                                .frame(width: 80, height: 80)
                        }
                    }

                    // Done button (enabled after minimum photos)
                    Button {
                        finishCapture()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .foregroundStyle(photoCount >= minimumPhotos ? .white : .gray)
                    }
                    .disabled(photoCount < minimumPhotos)
                }
                .padding(.bottom, 40)
            }

            // Capture flash effect
            if lastCaptureFlash {
                Color.white
                    .ignoresSafeArea()
                    .opacity(0.3)
                    .allowsHitTesting(false)
            }
        }
        .task {
            await captureManager.configure()
        }
        .onDisappear {
            captureManager.stop()
        }
    }

    private var guidanceOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "rotate.3d")
                .font(.system(size: 40))
                .foregroundStyle(.white)

            Text("Take Photos Around Your Toy")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 6) {
                guidanceLine(icon: "camera.circle", text: "Take \(recommendedPhotos)+ photos from all angles")
                guidanceLine(icon: "arrow.triangle.2.circlepath", text: "Move slowly around the object")
                guidanceLine(icon: "light.max", text: "Even lighting, avoid shadows")
                guidanceLine(icon: "hand.raised.slash", text: "Keep the toy still")
            }
            .font(.subheadline)

            Button("Got it") {
                withAnimation { showGuidance = false }
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .padding(.top, 4)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 32)
    }

    private func guidanceLine(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.white.opacity(0.8))
            Text(text)
                .foregroundStyle(.white)
        }
    }

    private func capturePhoto() {
        Task {
            do {
                let fileName = String(format: "IMG_%04d.heic", photoCount)
                let outputURL = folderManager.imagesFolder.appendingPathComponent(fileName)
                try await captureManager.capturePhoto(to: outputURL)
                photoCount += 1
                logger.info("Captured photo \(photoCount): \(fileName)")

                // Flash effect
                withAnimation(.easeOut(duration: 0.15)) { lastCaptureFlash = true }
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeOut(duration: 0.15)) { lastCaptureFlash = false }

                // Hide guidance after first capture
                if showGuidance {
                    withAnimation { showGuidance = false }
                }
            } catch {
                logger.error("Photo capture failed: \(error)")
            }
        }
    }

    private func finishCapture() {
        logger.info("Photo capture finished with \(photoCount) photos")
        appModel.state = .reconstructing
    }
}

// MARK: - Camera Manager

@Observable
@MainActor
final class CameraManager: NSObject {
    let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<Void, Error>?
    private var pendingOutputURL: URL?

    func configure() async {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            logger.error("Failed to access camera")
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        captureSession.commitConfiguration()
        captureSession.startRunning()
    }

    func stop() {
        captureSession.stopRunning()
    }

    func capturePhoto(to url: URL) async throws {
        pendingOutputURL = url
        let settings = AVCapturePhotoSettings()

        // Use HEIC if available
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            let heicSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            return try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                photoOutput.capturePhoto(with: heicSettings, delegate: self)
            }
        }

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Extract data in nonisolated context before crossing to MainActor
        let photoData = photo.fileDataRepresentation()
        let captureError = error

        Task { @MainActor in
            if let captureError {
                continuation?.resume(throwing: captureError)
                continuation = nil
                return
            }

            guard let data = photoData,
                  let url = pendingOutputURL else {
                continuation?.resume(throwing: CaptureError.noData)
                continuation = nil
                return
            }

            do {
                try data.write(to: url)
                continuation?.resume()
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }
}

enum CaptureError: Error, LocalizedError {
    case noData
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noData: return "No photo data captured"
        case .saveFailed: return "Failed to save photo"
        }
    }
}

// MARK: - Camera Preview UIViewRepresentable

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}
