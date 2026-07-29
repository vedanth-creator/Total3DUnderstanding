import Foundation

struct SampleRoom: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let systemImage: String
    let accentHex: String
}

enum FurnitureCategory: String, CaseIterable, Identifiable, Hashable {
    case sofa = "Sofa"
    case chair = "Chair"
    case table = "Table"
    case cabinet = "Cabinet"
    case bed = "Bed"
    case plant = "Plant"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .sofa: "sofa.fill"
        case .chair: "chair.lounge.fill"
        case .table: "table.furniture.fill"
        case .cabinet: "cabinet.fill"
        case .bed: "bed.double.fill"
        case .plant: "leaf.fill"
        }
    }
}

struct FurnitureItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var category: FurnitureCategory
    var normalizedX: Double
    var normalizedY: Double
    var width: Double
    var depth: Double
    var height: Double
    var rotationDegrees: Double
    var colorHex: String
    var detectorConfidence: Double?
    var meshReference: String?
}

struct RoomScene: Identifiable, Hashable {
    let id: UUID
    var name: String
    var imageIdentifier: String
    var roomWidth: Double
    var roomDepth: Double
    var furniture: [FurnitureItem]
    var warnings: [String]
}

