import Foundation

@MainActor
final class RoomViewerViewModel: ObservableObject {
    @Published private(set) var scene: RoomScene
    @Published var selectedFurnitureID: UUID?

    init(scene: RoomScene) {
        self.scene = scene
        self.selectedFurnitureID = scene.furniture.first?.id
    }

    var selectedFurniture: FurnitureItem? {
        guard let selectedFurnitureID else { return nil }
        return scene.furniture.first { $0.id == selectedFurnitureID }
    }

    func select(_ furniture: FurnitureItem) {
        selectedFurnitureID = furniture.id
    }

    func select(furnitureID: UUID?) {
        selectedFurnitureID = furnitureID
    }

    func deselectFurniture() {
        selectedFurnitureID = nil
    }

    func moveSelected(normalizedX: Double, normalizedY: Double) {
        guard
            let selectedFurnitureID,
            let index = scene.furniture.firstIndex(where: { $0.id == selectedFurnitureID })
        else { return }
        scene.furniture[index].normalizedX = min(
            max(scene.furniture[index].normalizedX + normalizedX, 0),
            1
        )
        scene.furniture[index].normalizedY = min(
            max(scene.furniture[index].normalizedY + normalizedY, 0),
            1
        )
    }

    func rotateSelected(by degrees: Double = 15) {
        guard let furniture = selectedFurniture else { return }
        updateSelected(
            rotationDegrees: (furniture.rotationDegrees + degrees)
                .truncatingRemainder(dividingBy: 360)
        )
    }

    func replaceSelectedWithNextCategory() {
        guard
            let selectedFurnitureID,
            let index = scene.furniture.firstIndex(where: { $0.id == selectedFurnitureID }),
            let categoryIndex = FurnitureCategory.allCases.firstIndex(
                of: scene.furniture[index].category
            )
        else { return }
        let nextIndex = FurnitureCategory.allCases.index(
            after: categoryIndex
        ) % FurnitureCategory.allCases.count
        let category = FurnitureCategory.allCases[nextIndex]
        scene.furniture[index].category = category
        scene.furniture[index].name = category.rawValue
    }

    func duplicateSelected() {
        guard let furniture = selectedFurniture else { return }
        let duplicate = FurnitureItem(
            id: UUID(),
            name: furniture.name + " Copy",
            category: furniture.category,
            normalizedX: min(furniture.normalizedX + 0.06, 1),
            normalizedY: min(furniture.normalizedY + 0.06, 1),
            width: furniture.width,
            depth: furniture.depth,
            height: furniture.height,
            rotationDegrees: furniture.rotationDegrees,
            colorHex: furniture.colorHex,
            detectorConfidence: furniture.detectorConfidence,
            meshReference: furniture.meshReference
        )
        scene.furniture.append(duplicate)
        selectedFurnitureID = duplicate.id
    }

    func deleteSelected() {
        guard let selectedFurnitureID else { return }
        scene.furniture.removeAll { $0.id == selectedFurnitureID }
        self.selectedFurnitureID = nil
    }

    func positionMeters(for furniture: FurnitureItem) -> (x: Double, z: Double) {
        (
            x: (furniture.normalizedX - 0.5) * scene.roomWidth,
            z: (furniture.normalizedY - 0.5) * scene.roomDepth
        )
    }

    func updateSelected(
        width: Double? = nil,
        depth: Double? = nil,
        height: Double? = nil,
        rotationDegrees: Double? = nil,
        positionX: Double? = nil,
        positionZ: Double? = nil
    ) {
        guard
            let selectedFurnitureID,
            let index = scene.furniture.firstIndex(where: { $0.id == selectedFurnitureID })
        else { return }

        if let width { scene.furniture[index].width = width }
        if let depth { scene.furniture[index].depth = depth }
        if let height { scene.furniture[index].height = height }
        if let rotationDegrees {
            scene.furniture[index].rotationDegrees = rotationDegrees
        }
        if let positionX, scene.roomWidth > 0 {
            scene.furniture[index].normalizedX = min(
                max(positionX / scene.roomWidth + 0.5, 0.0),
                1.0
            )
        }
        if let positionZ, scene.roomDepth > 0 {
            scene.furniture[index].normalizedY = min(
                max(positionZ / scene.roomDepth + 0.5, 0.0),
                1.0
            )
        }
    }
}
