import SwiftUI
import AVFoundation
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "PhotoCapture")

/// Camera preview + photo capture for non-LiDAR devices.
/// Auto-captures photos while the user slowly rotates the toy.
struct PhotoCaptureView: View {
    @Environment(AppModel.self) var appModel
    let folderManager: CaptureFolderManager

    @State private var captureManager = CameraManager()
    @State private var photoCount = 0
    @State private var isAutoCapturing = false
    @State private var showGuidance = true
    @State private var lastCaptureFlash = false
    @State private var autoTask: Task<Void, Never>?

    private let targetPhotos = 30
    private let captureInterval: Duration = .milliseconds(1500) // Auto-capture every 1.5s

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
                        stopAutoCapture()
                        appModel.returnHome()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    // Photo counter badge
                    HStack(spacing: 6) {
                        if isAutoCapturing {
                            Circle()
                                .fill(.red)
                                .frame(width: 10, height: 10)
                        }
                        Text("\(photoCount) photos")
                            .font(.headline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding()

                Spacer()

                // Guidance or status
                if showGuidance {
                    guidanceOverlay
                        .transition(.opacity)
                } else if isAutoCapturing {
                    captureStatusOverlay
                        .transition(.opacity)
                }

                Spacer()

                // Circular progress ring + controls
                VStack(spacing: 16) {
                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 6)
                            .frame(width: 100, height: 100)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(photoCount, targetPhotos)) / CGFloat(targetPhotos))
                            .stroke(photoCount >= targetPhotos ? .green : .white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: photoCount)

                        // Center button
                        Button {
                            if isAutoCapturing {
                                stopAutoCapture()
                            } else if photoCount >= targetPhotos {
                                finishCapture()
                            } else {
                                startAutoCapture()
                            }
                        } label: {
                            ZStack {
                                if isAutoCapturing {
                                    // Pause icon
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.red)
                                        .frame(width: 30, height: 30)
                                } else if photoCount >= targetPhotos {
                                    // Checkmark
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundStyle(.green)
                                } else {
                                    // Play icon
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 30))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 70, height: 70)
                            .background(.ultraThinMaterial, in: Circle())
                        }
                    }

                    // Status text
                    if photoCount >= targetPhotos && !isAutoCapturing {
                        Button("Build 3D Model") {
                            finishCapture()
                        }
                        .font(.headline)
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else if isAutoCapturing {
                        Text("Slowly rotate the toy...")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    } else if photoCount > 0 {
                        Text("Tap to continue • \(photoCount)/\(targetPhotos)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.bottom, 50)
            }

            // Capture flash effect
            if lastCaptureFlash {
                Color.white
                    .ignoresSafeArea()
                    .opacity(0.15)
                    .allowsHitTesting(false)
            }
        }
        .task {
            await captureManager.configure()
        }
        .onDisappear {
            stopAutoCapture()
            captureManager.stop()
        }
    }

    private var guidanceOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "rotate.3d")
                .font(.system(size: 50))
                .foregroundStyle(.white)

            Text("Auto-Capture Mode")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("Place your toy on a table.\nTap Start, then slowly rotate the toy.\nPhotos are taken automatically.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            Button {
                withAnimation { showGuidance = false }
                startAutoCapture()
            } label: {
                Label("Start Capturing", systemImage: "camera.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .padding(.top, 8)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 32)
    }

    private var captureStatusOverlay: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("Auto-capturing...")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func startAutoCapture() {
        guard !isAutoCapturing else { return }
        isAutoCapturing = true
        if showGuidance { withAnimation { showGuidance = false } }

        autoTask = Task {
            while !Task.isCancelled && isAutoCapturing {
                await captureOnePhoto()
                if photoCount >= targetPhotos {
                    stopAutoCapture()
                    break
                }
                try? await Task.sleep(for: captureInterval)
            }
        }
    }

    private func stopAutoCapture() {
        isAutoCapturing = false
        autoTask?.cancel()
        autoTask = nil
    }

    private func captureOnePhoto() async {
        do {
            let fileName = String(format: "IMG_%04d.heic", photoCount)
            let outputURL = folderManager.imagesFolder.appendingPathComponent(fileName)
            try await captureManager.capturePhoto(to: outputURL)
            photoCount += 1
            logger.info("Auto-captured photo \(photoCount): \(fileName)")

            // Subtle flash
            withAnimation(.easeOut(duration: 0.1)) { lastCaptureFlash = true }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.1)) { lastCaptureFlash = false }
        } catch {
            logger.error("Auto-capture failed: \(error)")
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
        // Request camera authorization
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                logger.error("Camera access denied by user")
                return
            }
        } else if status != .authorized {
            logger.error("Camera access not authorized: \(status.rawValue)")
            return
        }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            logger.error("Failed to access camera")
            captureSession.commitConfiguration()
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

        // Start running on background queue to avoid blocking main thread
        nonisolated(unsafe) let session = captureSession
        Task.detached { @Sendable in
            session.startRunning()
        }
        logger.info("Camera configured and started")
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

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Session is already set
    }
}

class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
