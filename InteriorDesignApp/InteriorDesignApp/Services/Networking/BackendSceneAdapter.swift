import Foundation

enum BackendSceneAdapterError: LocalizedError {
    case invalidRoomLayout
    case invalidObjectIdentifier(String)
    case unsupportedCategory(String)
    case invalidObjectGeometry(String)

    var errorDescription: String? {
        switch self {
        case .invalidRoomLayout:
            "The backend scene contains an invalid room layout."
        case let .invalidObjectIdentifier(identifier):
            "The backend returned an invalid object identifier: \(identifier)."
        case let .unsupportedCategory(category):
            "The backend returned an unsupported furniture category: \(category)."
        case let .invalidObjectGeometry(identifier):
            "The backend returned invalid geometry for object \(identifier)."
        }
    }
}

enum BackendSceneAdapter {
    static func makeRoomScene(
        from response: BackendSceneResponse,
        jobID: UUID
    ) throws -> RoomScene {
        let roomHalfSizes = try vector3(
            response.roomLayout.halfSizes,
            error: .invalidRoomLayout
        )
        let roomWidth = roomHalfSizes.x * 2
        let roomHeight = roomHalfSizes.y * 2
        let roomDepth = roomHalfSizes.z * 2
        guard roomWidth > 0, roomHeight > 0, roomDepth > 0 else {
            throw BackendSceneAdapterError.invalidRoomLayout
        }

        let furniture = try response.objects.map { object in
            guard let objectID = UUID(uuidString: object.id) else {
                throw BackendSceneAdapterError.invalidObjectIdentifier(object.id)
            }
            let category = try furnitureCategory(object.category.name)
            let halfSizes = try vector3(
                object.boundingBox3D.halfSizes,
                error: .invalidObjectGeometry(object.id)
            )
            let centroid = try vector3(
                object.boundingBox3D.centroid,
                error: .invalidObjectGeometry(object.id)
            )
            let width = halfSizes.x * 2
            let height = halfSizes.y * 2
            let depth = halfSizes.z * 2
            guard width > 0, height > 0, depth > 0 else {
                throw BackendSceneAdapterError.invalidObjectGeometry(object.id)
            }

            return FurnitureItem(
                id: objectID,
                name: displayName(for: category),
                category: category,
                normalizedX: clamped(centroid.x / roomWidth + 0.5),
                normalizedY: clamped(centroid.z / roomDepth + 0.5),
                width: width,
                depth: depth,
                height: height,
                rotationDegrees: yawDegrees(from: object.boundingBox3D.basis),
                colorHex: colorHex(for: category),
                detectorConfidence: object.confidence.detectorCategoryProbability,
                meshReference: object.mesh.uri
            )
        }

        return RoomScene(
            id: UUID(),
            name: "Room Scan",
            imageIdentifier: "room-scan://\(jobID.uuidString.lowercased())",
            roomWidth: roomWidth,
            roomDepth: roomDepth,
            roomHeight: roomHeight,
            furniture: furniture,
            warnings: response.warnings
        )
    }

    private static func vector3(
        _ values: [Double],
        error: BackendSceneAdapterError
    ) throws -> (x: Double, y: Double, z: Double) {
        guard values.count >= 3,
              values[0].isFinite,
              values[1].isFinite,
              values[2].isFinite else {
            throw error
        }
        return (values[0], values[1], values[2])
    }

    private static func furnitureCategory(_ rawValue: String) throws -> FurnitureCategory {
        switch rawValue.lowercased() {
        case "sofa": return .sofa
        case "chair": return .chair
        case "table", "desk": return .table
        case "cabinet", "bookshelf", "shelves", "dresser", "night_stand": return .cabinet
        case "bed": return .bed
        case "plant": return .plant
        default: throw BackendSceneAdapterError.unsupportedCategory(rawValue)
        }
    }

    private static func yawDegrees(from basis: [[Double]]) -> Double {
        guard basis.count >= 1,
              basis[0].count >= 3,
              basis[0][0].isFinite,
              basis[0][2].isFinite else { return 0 }
        return atan2(basis[0][2], basis[0][0]) * 180 / .pi
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    private static func displayName(for category: FurnitureCategory) -> String {
        switch category {
        case .sofa: "Sample Sofa"
        case .chair: "Sample Chair"
        case .table: "Sample Table"
        case .cabinet: "Sample Cabinet"
        case .bed: "Sample Bed"
        case .plant: "Sample Plant"
        }
    }

    private static func colorHex(for category: FurnitureCategory) -> String {
        switch category {
        case .sofa: "D7CBBE"
        case .chair: "738475"
        case .table: "B88B5A"
        case .cabinet: "9B8067"
        case .bed: "C8BEB4"
        case .plant: "52725B"
        }
    }
}
