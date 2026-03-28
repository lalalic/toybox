import SwiftUI
import RealityKit
import os

private let logger = Logger(subsystem: ToyboxConstants.subsystem, category: "ScanView")

/// The main scanning view that wraps Apple's ObjectCaptureView with custom overlay.
struct ScanView: View {
    @Environment(AppModel.self) var appModel
    let session: ObjectCaptureSession

    @State private var isPreparing = true

    var body: some View {
        ZStack {
            // Apple's guided capture view
            ObjectCaptureView(session: session) {
                // Camera feed overlay
                VStack {
                    // Top bar with toy name
                    HStack {
                        Text(appModel.scanCoordinator?.toy.name ?? "Scanning...")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())

                        Spacer()

                        Button {
                            cancelScan()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding()

                    Spacer()

                    // Feedback messages
                    if let feedback = appModel.scanCoordinator?.feedbackMessages.last {
                        Text(feedback)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.bottom, 100)
                    }
                }
            }
        }
        .task {
            await monitorSessionState()
        }
        .task {
            await monitorFeedback()
        }
    }

    private func monitorSessionState() async {
        guard let coordinator = appModel.scanCoordinator else { return }
        for await state in coordinator.session.stateUpdates {
            logger.info("Session state: \(String(describing: state))")
            switch state {
            case .ready:
                isPreparing = false
            case .detecting:
                break
            case .capturing:
                break
            case .finishing:
                break
            case .completed:
                // Transition to reconstruction
                appModel.state = .reconstructing
            case .failed(let error):
                appModel.state = .failed("Scan failed: \(error.localizedDescription)")
            @unknown default:
                break
            }
        }
    }

    private func monitorFeedback() async {
        guard let coordinator = appModel.scanCoordinator else { return }
        for await feedback in coordinator.session.feedbackUpdates {
            logger.info("Feedback: \(String(describing: feedback))")
            let messages = feedback.compactMap { feedbackMessage($0) }
            coordinator.feedbackMessages = messages
        }
    }

    private func feedbackMessage(_ feedback: ObjectCaptureSession.Feedback) -> String? {
        switch feedback {
        case .objectTooClose:
            return "Move further away"
        case .objectTooFar:
            return "Move closer"
        case .movingTooFast:
            return "Slow down"
        case .environmentLowLight:
            return "Need more light"
        case .environmentTooDark:
            return "Too dark"
        case .objectNotFlippable:
            return "Object is not flippable"
        case .outOfFieldOfView:
            return "Point camera at the object"
        @unknown default:
            return nil
        }
    }

    private func cancelScan() {
        appModel.scanCoordinator?.session.cancel()
        appModel.returnHome()
    }
}
