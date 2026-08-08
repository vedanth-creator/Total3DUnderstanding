import Foundation
import RoomPlan
import simd

struct RoomPlanTransform: Codable, Equatable {
    private var values: [Float]

    init(_ matrix: simd_float4x4) {
        values = [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w
        ]
    }

    var matrix: simd_float4x4 {
        guard values.count == 16 else { return matrix_identity_float4x4 }
        return simd_float4x4(columns: (
            SIMD4<Float>(values[0], values[1], values[2], values[3]),
            SIMD4<Float>(values[4], values[5], values[6], values[7]),
            SIMD4<Float>(values[8], values[9], values[10], values[11]),
            SIMD4<Float>(values[12], values[13], values[14], values[15])
        ))
    }

    var position: SIMD3<Float> {
        let translation = matrix.columns.3
        return SIMD3<Float>(translation.x, translation.y, translation.z)
    }

    func replacingFloorPosition(x: Float, z: Float) -> RoomPlanTransform {
        var updated = matrix
        updated.columns.3.x = x
        updated.columns.3.z = z
        return RoomPlanTransform(updated)
    }

    func rotatedAroundWorldY(by angle: Float) -> RoomPlanTransform {
        let rotation = simd_float4x4(simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0)))
        var updated = matrix
        let translation = updated.columns.3
        updated.columns.3 = SIMD4<Float>(0, 0, 0, 1)
        updated = rotation * updated
        updated.columns.3 = translation
        return RoomPlanTransform(updated)
    }
}

struct RoomPlanDimensions: Codable, Equatable {
    var width: Float
    var height: Float
    var depth: Float

    init(_ dimensions: SIMD3<Float>) {
        width = max(dimensions.x, 0.05)
        height = max(dimensions.y, 0.05)
        depth = max(dimensions.z, 0.05)
    }

    init(width: Float, height: Float, depth: Float) {
        self.init(SIMD3<Float>(width, height, depth))
    }

    var vector: SIMD3<Float> { SIMD3<Float>(width, height, depth) }
}

enum RoomPlanSurfaceKind: Codable, Equatable {
    case wall
    case door(isOpen: Bool)
    case window
    case opening
    case floor
}

struct RoomPlanSurfaceModel: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: RoomPlanSurfaceKind
    let dimensions: RoomPlanDimensions
    let transform: RoomPlanTransform
    let confidence: String
    let parentIdentifier: UUID?
}

enum RoomPlanObjectSource: String, Codable, Equatable {
    case scanned
    case added
    case replacement
}

enum RoomPlanObjectSemantic: Equatable {
    case majorObject
    case wallArt
    case mirror
    case wallDecor

    init(categoryName: String) {
        switch categoryName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "wall art", "painting", "picture", "framed photo":
            self = .wallArt
        case "mirror":
            self = .mirror
        case "wall decor":
            self = .wallDecor
        default:
            self = .majorObject
        }
    }

    var isWallMountedDecor: Bool { self != .majorObject }
}

enum RoomPlanWallDecorGeometry {
    static let depth: Float = 0.025
    static let wallThickness: Float = 0.04
    static let wallSurfaceGap: Float = 0.003
}

enum RoomPlanAddCategory: String, CaseIterable, Identifiable {
    case chair = "Chair"
    case sofa = "Sofa"
    case table = "Table"
    case lamp = "Lamp"
    case plant = "Plant"
    case wallArt = "Wall Art"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .chair: "chair.fill"
        case .sofa: "sofa.fill"
        case .table: "table.furniture.fill"
        case .lamp: "lamp.floor.fill"
        case .plant: "leaf.fill"
        case .wallArt: "photo.artframe"
        }
    }

    var defaultDimensions: RoomPlanDimensions {
        switch self {
        case .chair: RoomPlanDimensions(width: 0.62, height: 0.9, depth: 0.62)
        case .sofa: RoomPlanDimensions(width: 2.0, height: 0.9, depth: 0.88)
        case .table: RoomPlanDimensions(width: 1.4, height: 0.76, depth: 0.82)
        case .lamp: RoomPlanDimensions(width: 0.38, height: 1.45, depth: 0.38)
        case .plant: RoomPlanDimensions(width: 0.55, height: 1.05, depth: 0.55)
        case .wallArt: RoomPlanDimensions(width: 1.0, height: 0.72, depth: 0.08)
        }
    }
}

struct EditableRoomPlanObject: Identifiable, Codable, Equatable {
    let id: UUID
    let category: String
    let dimensions: RoomPlanDimensions
    var transform: RoomPlanTransform
    let confidence: String
    let parentIdentifier: UUID?
    let source: RoomPlanObjectSource
    var originalTransform: RoomPlanTransform?
    var isRemoved: Bool
    var productID: String?
    var productURL: URL?

    init(
        id: UUID,
        category: String,
        dimensions: RoomPlanDimensions,
        transform: RoomPlanTransform,
        confidence: String,
        parentIdentifier: UUID?,
        source: RoomPlanObjectSource = .scanned,
        originalTransform: RoomPlanTransform? = nil,
        isRemoved: Bool = false,
        productID: String? = nil,
        productURL: URL? = nil
    ) {
        self.id = id
        self.category = category
        self.dimensions = dimensions
        self.transform = transform
        self.confidence = confidence
        self.parentIdentifier = parentIdentifier
        self.source = source
        self.originalTransform = originalTransform ?? (source == .scanned ? transform : nil)
        self.isRemoved = isRemoved
        self.productID = productID
        self.productURL = productURL
    }

    var hasTransformChange: Bool {
        guard let originalTransform else { return source != .scanned }
        return transform != originalTransform
    }

    var shouldRenderAsARChange: Bool {
        guard !isRemoved else { return false }
        return source != .scanned || hasTransformChange
    }

    var semantic: RoomPlanObjectSemantic {
        RoomPlanObjectSemantic(categoryName: category)
    }

    var editorDimensions: SIMD3<Float> {
        let measured = dimensions.vector
        guard semantic.isWallMountedDecor else { return measured }
        return SIMD3<Float>(
            measured.x,
            measured.y,
            RoomPlanWallDecorGeometry.depth
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, category, dimensions, transform, confidence, parentIdentifier
        case source, originalTransform, isRemoved, productID, productURL
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        category = try values.decode(String.self, forKey: .category)
        dimensions = try values.decode(RoomPlanDimensions.self, forKey: .dimensions)
        transform = try values.decode(RoomPlanTransform.self, forKey: .transform)
        confidence = try values.decode(String.self, forKey: .confidence)
        parentIdentifier = try values.decodeIfPresent(UUID.self, forKey: .parentIdentifier)
        source = try values.decodeIfPresent(RoomPlanObjectSource.self, forKey: .source) ?? .scanned
        originalTransform = try values.decodeIfPresent(RoomPlanTransform.self, forKey: .originalTransform)
            ?? (source == .scanned ? transform : nil)
        isRemoved = try values.decodeIfPresent(Bool.self, forKey: .isRemoved) ?? false
        productID = try values.decodeIfPresent(String.self, forKey: .productID)
        productURL = try values.decodeIfPresent(URL.self, forKey: .productURL)
    }
}

struct RoomPlanFloorBounds: Codable, Equatable {
    var minimumX: Float
    var maximumX: Float
    var minimumZ: Float
    var maximumZ: Float

    var width: Float { maximumX - minimumX }
    var depth: Float { maximumZ - minimumZ }
    var center: SIMD3<Float> {
        SIMD3<Float>((minimumX + maximumX) / 2, 0, (minimumZ + maximumZ) / 2)
    }

    func clamped(position: SIMD3<Float>, objectRadius: Float) -> SIMD3<Float> {
        let insetX = min(objectRadius, max(width / 2 - 0.05, 0))
        let insetZ = min(objectRadius, max(depth / 2 - 0.05, 0))
        return SIMD3<Float>(
            min(max(position.x, minimumX + insetX), maximumX - insetX),
            position.y,
            min(max(position.z, minimumZ + insetZ), maximumZ - insetZ)
        )
    }
}

struct RoomPlanProject: Identifiable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date
    var modifiedAt: Date
    let originalCapturedRoom: CapturedRoom
    let surfaces: [RoomPlanSurfaceModel]
    let originalObjects: [EditableRoomPlanObject]
    var objects: [EditableRoomPlanObject]
    let floorBounds: RoomPlanFloorBounds
    let roomHeight: Float
    var archivedWorldMap: Data?
    /// Stable identity for the separately archived ARWorldMap. Older saved
    /// projects decode this as nil and remain fully usable.
    let worldMapReferenceID: UUID?

    /// Existing scans predate `worldMapReferenceID`. Their project identifier
    /// is a deterministic fallback, so a saved world map is still referenceable
    /// without rewriting the persisted project during decoding.
    var effectiveWorldMapReferenceID: UUID? {
        guard archivedWorldMap != nil else { return nil }
        return worldMapReferenceID ?? id
    }

    var walls: [RoomPlanSurfaceModel] { surfaces.filter { $0.kind == .wall } }
    var doors: [RoomPlanSurfaceModel] {
        surfaces.filter { if case .door = $0.kind { return true }; return false }
    }
    var windows: [RoomPlanSurfaceModel] { surfaces.filter { $0.kind == .window } }
    var openings: [RoomPlanSurfaceModel] { surfaces.filter { $0.kind == .opening } }

    init(capturedRoom: CapturedRoom, archivedWorldMap: Data?) {
        id = capturedRoom.identifier
        title = "RoomPlan Scan"
        createdAt = Date()
        modifiedAt = createdAt
        originalCapturedRoom = capturedRoom
        self.archivedWorldMap = archivedWorldMap
        worldMapReferenceID = archivedWorldMap == nil ? nil : UUID()

        let convertedSurfaces = Self.convertSurfaces(capturedRoom)
        surfaces = convertedSurfaces
        let convertedObjects = capturedRoom.objects.map(Self.convertObject)
        originalObjects = convertedObjects
        objects = convertedObjects
        floorBounds = Self.calculateBounds(surfaces: convertedSurfaces, objects: convertedObjects)
        roomHeight = max(
            convertedSurfaces
                .filter { $0.kind == .wall }
                .map(\.dimensions.height)
                .max() ?? 2.7,
            2.0
        )
    }

    private static func convertSurfaces(_ room: CapturedRoom) -> [RoomPlanSurfaceModel] {
        let all = room.walls + room.doors + room.windows + room.openings + room.floors
        return all.map { surface in
            RoomPlanSurfaceModel(
                id: surface.identifier,
                kind: surfaceKind(surface.category),
                dimensions: RoomPlanDimensions(surface.dimensions),
                transform: RoomPlanTransform(surface.transform),
                confidence: confidenceName(surface.confidence),
                parentIdentifier: surface.parentIdentifier
            )
        }
    }

    private static func convertObject(_ object: CapturedRoom.Object) -> EditableRoomPlanObject {
        EditableRoomPlanObject(
            id: object.identifier,
            category: categoryName(object.category),
            dimensions: RoomPlanDimensions(object.dimensions),
            transform: RoomPlanTransform(object.transform),
            confidence: confidenceName(object.confidence),
            parentIdentifier: object.parentIdentifier
        )
    }

    private static func calculateBounds(
        surfaces: [RoomPlanSurfaceModel],
        objects: [EditableRoomPlanObject]
    ) -> RoomPlanFloorBounds {
        var points: [SIMD3<Float>] = []
        for surface in surfaces where surface.kind == .wall || surface.kind == .floor {
            let matrix = surface.transform.matrix
            let halfWidth = surface.dimensions.width / 2
            if surface.kind == .floor {
                // RoomPlan surfaces are local XY planes. The floor transform
                // rotates that plane into world XZ, so its second planar extent
                // is local Y rather than the thin local Z dimension.
                let halfLength = surface.dimensions.height / 2
                for x in [-halfWidth, halfWidth] {
                    for y in [-halfLength, halfLength] {
                        let world = matrix * SIMD4<Float>(x, y, 0, 1)
                        points.append(SIMD3<Float>(world.x, world.y, world.z))
                    }
                }
            } else {
                for x in [-halfWidth, halfWidth] {
                    let world = matrix * SIMD4<Float>(x, 0, 0, 1)
                    points.append(SIMD3<Float>(world.x, world.y, world.z))
                }
            }
        }
        if points.isEmpty {
            points = objects.map(\.transform.position)
        }
        guard let first = points.first else {
            return RoomPlanFloorBounds(minimumX: -2.5, maximumX: 2.5, minimumZ: -2.5, maximumZ: 2.5)
        }
        let minimumX = points.reduce(first.x) { min($0, $1.x) }
        let maximumX = points.reduce(first.x) { max($0, $1.x) }
        let minimumZ = points.reduce(first.z) { min($0, $1.z) }
        let maximumZ = points.reduce(first.z) { max($0, $1.z) }
        let usableWidth = maximumX - minimumX > 1
        let usableDepth = maximumZ - minimumZ > 1
        return RoomPlanFloorBounds(
            minimumX: usableWidth ? minimumX : first.x - 2.5,
            maximumX: usableWidth ? maximumX : first.x + 2.5,
            minimumZ: usableDepth ? minimumZ : first.z - 2.5,
            maximumZ: usableDepth ? maximumZ : first.z + 2.5
        )
    }

    private static func surfaceKind(_ category: CapturedRoom.Surface.Category) -> RoomPlanSurfaceKind {
        switch category {
        case .wall: .wall
        case .door(let isOpen): .door(isOpen: isOpen)
        case .window: .window
        case .opening: .opening
        case .floor: .floor
        @unknown default: .wall
        }
    }

    private static func confidenceName(_ confidence: CapturedRoom.Confidence) -> String {
        switch confidence {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        @unknown default: "Unknown"
        }
    }

    private static func categoryName(_ category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .storage: "Storage"
        case .refrigerator: "Refrigerator"
        case .stove: "Stove"
        case .bed: "Bed"
        case .sink: "Sink"
        case .washerDryer: "Washer/Dryer"
        case .toilet: "Toilet"
        case .bathtub: "Bathtub"
        case .oven: "Oven"
        case .dishwasher: "Dishwasher"
        case .table: "Table"
        case .sofa: "Sofa"
        case .chair: "Chair"
        case .fireplace: "Fireplace"
        case .television: "Television"
        case .stairs: "Stairs"
        @unknown default: "Unknown"
        }
    }
}
