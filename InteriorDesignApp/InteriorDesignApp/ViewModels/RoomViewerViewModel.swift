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

    func updateSelected(
        width: Double? = nil,
        depth: Double? = nil,
        height: Double? = nil,
        rotationDegrees: Double? = nil
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
    }
}

