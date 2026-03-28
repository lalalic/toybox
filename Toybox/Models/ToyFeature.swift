import Foundation
import simd

/// A specific feature identified on a toy (eye, mouth, etc.)
struct ToyFeature: Identifiable, Codable {
    let id: UUID
    var kind: Kind
    var position: SIMD3<Float>  // 3D position relative to model origin

    enum Kind: String, Codable, CaseIterable {
        case leftEye = "Left Eye"
        case rightEye = "Right Eye"
        case mouth = "Mouth"
        case nose = "Nose"
        case bodyCenter = "Body Center"
        case head = "Head"

        var systemImage: String {
            switch self {
            case .leftEye, .rightEye: return "eye.fill"
            case .mouth: return "mouth.fill"
            case .nose: return "nose.fill"
            case .bodyCenter: return "figure.stand"
            case .head: return "brain.head.profile"
            }
        }

        var color: String {
            switch self {
            case .leftEye: return "blue"
            case .rightEye: return "cyan"
            case .mouth: return "red"
            case .nose: return "orange"
            case .bodyCenter: return "green"
            case .head: return "purple"
            }
        }
    }

    init(kind: Kind, position: SIMD3<Float> = .zero) {
        self.id = UUID()
        self.kind = kind
        self.position = position
    }
}

// SIMD3<Float> Codable conformance
extension SIMD3: @retroactive Codable where Scalar == Float {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Float.self)
        let y = try container.decode(Float.self)
        let z = try container.decode(Float.self)
        self.init(x, y, z)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
    }
}
