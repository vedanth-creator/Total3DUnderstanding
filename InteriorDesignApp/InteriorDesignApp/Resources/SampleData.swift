import Foundation

enum SampleData {
    static let rooms: [SampleRoom] = [
        SampleRoom(
            id: "sunlit-living-room",
            name: "Sunlit Living Room",
            subtitle: "Warm minimal · 18 m²",
            systemImage: "sun.max.fill",
            accentHex: "E7B46A"
        ),
        SampleRoom(
            id: "calm-bedroom",
            name: "Calm Bedroom",
            subtitle: "Soft modern · 14 m²",
            systemImage: "moon.stars.fill",
            accentHex: "8EA6C8"
        ),
        SampleRoom(
            id: "studio-workspace",
            name: "Studio Workspace",
            subtitle: "Creative neutral · 11 m²",
            systemImage: "lamp.desk.fill",
            accentHex: "A8B9A2"
        )
    ]

    static func scene(for room: SampleRoom) -> RoomScene {
        switch room.id {
        case "calm-bedroom": bedroomScene
        case "studio-workspace": studioScene
        default: livingRoomScene
        }
    }

    static let livingRoomScene = RoomScene(
        id: UUID(uuidString: "CF22EBF4-A00D-4AC5-B215-04B2335F7951") ?? UUID(),
        name: "Sunlit Living Room",
        imageIdentifier: "sample://sunlit-living-room",
        roomWidth: 5.8,
        roomDepth: 4.2,
        roomHeight: 2.7,
        furniture: [
            FurnitureItem(
                id: UUID(uuidString: "74AFE875-861C-4CB5-8427-A34ED03E0C74") ?? UUID(),
                name: "Cloud Sofa",
                category: .sofa,
                normalizedX: 0.50,
                normalizedY: 0.77,
                width: 2.4,
                depth: 0.9,
                height: 0.82,
                rotationDegrees: 0,
                colorHex: "D7CBBE",
                detectorConfidence: 0.94,
                meshReference: nil
            ),
            FurnitureItem(
                id: UUID(uuidString: "A1891890-3A4C-485B-8E0B-F4D2EC868126") ?? UUID(),
                name: "Oak Coffee Table",
                category: .table,
                normalizedX: 0.50,
                normalizedY: 0.48,
                width: 1.25,
                depth: 0.65,
                height: 0.38,
                rotationDegrees: 0,
                colorHex: "B88B5A",
                detectorConfidence: 0.89,
                meshReference: nil
            ),
            FurnitureItem(
                id: UUID(uuidString: "D9D2F5F3-2444-4BA2-8D79-2CA863C3EA10") ?? UUID(),
                name: "Reading Chair",
                category: .chair,
                normalizedX: 0.20,
                normalizedY: 0.35,
                width: 0.85,
                depth: 0.85,
                height: 0.92,
                rotationDegrees: 28,
                colorHex: "738475",
                detectorConfidence: 0.91,
                meshReference: nil
            ),
            FurnitureItem(
                id: UUID(uuidString: "8464300D-C270-429F-B861-1A95349DA5C3") ?? UUID(),
                name: "Fiddle Leaf Fig",
                category: .plant,
                normalizedX: 0.84,
                normalizedY: 0.20,
                width: 0.55,
                depth: 0.55,
                height: 1.65,
                rotationDegrees: 0,
                colorHex: "52725B",
                detectorConfidence: nil,
                meshReference: nil
            )
        ],
        warnings: ["Preview geometry uses placeholder furniture boxes."]
    )

    static let bedroomScene = RoomScene(
        id: UUID(),
        name: "Calm Bedroom",
        imageIdentifier: "sample://calm-bedroom",
        roomWidth: 4.6,
        roomDepth: 3.8,
        roomHeight: 2.65,
        furniture: [
            FurnitureItem(id: UUID(), name: "Platform Bed", category: .bed, normalizedX: 0.5, normalizedY: 0.62, width: 2.1, depth: 2.2, height: 0.6, rotationDegrees: 0, colorHex: "C8BEB4", detectorConfidence: 0.96, meshReference: nil),
            FurnitureItem(id: UUID(), name: "Bedside Cabinet", category: .cabinet, normalizedX: 0.82, normalizedY: 0.62, width: 0.55, depth: 0.48, height: 0.55, rotationDegrees: 0, colorHex: "9B8067", detectorConfidence: 0.87, meshReference: nil)
        ],
        warnings: ["Preview geometry uses placeholder furniture boxes."]
    )

    static let studioScene = RoomScene(
        id: UUID(),
        name: "Studio Workspace",
        imageIdentifier: "sample://studio-workspace",
        roomWidth: 4.2,
        roomDepth: 3.1,
        roomHeight: 2.7,
        furniture: [
            FurnitureItem(id: UUID(), name: "Work Table", category: .table, normalizedX: 0.52, normalizedY: 0.3, width: 1.8, depth: 0.75, height: 0.74, rotationDegrees: 0, colorHex: "AA8A68", detectorConfidence: 0.92, meshReference: nil),
            FurnitureItem(id: UUID(), name: "Task Chair", category: .chair, normalizedX: 0.52, normalizedY: 0.58, width: 0.65, depth: 0.65, height: 0.95, rotationDegrees: 0, colorHex: "66717E", detectorConfidence: 0.90, meshReference: nil),
            FurnitureItem(id: UUID(), name: "Storage", category: .cabinet, normalizedX: 0.84, normalizedY: 0.5, width: 0.8, depth: 0.45, height: 1.8, rotationDegrees: 90, colorHex: "D2C7B6", detectorConfidence: 0.85, meshReference: nil)
        ],
        warnings: ["Preview geometry uses placeholder furniture boxes."]
    )
}
