import Combine
import RealityKit
import UIKit

@MainActor
final class RoomSceneCoordinator: ObservableObject {
    let rootEntity = AnchorEntity(world: .zero)
    let cameraController = CameraController()

    private let roomEntity = Entity()
    private let furnitureEntity = Entity()
    private let lightingEntity = Entity()
    private var entityRegistry: [UUID: FurnitureEntityRecord] = [:]
    private var roomSignature: RoomSignature?
    private var configuredSceneID: UUID?
    private weak var fallbackARView: ARView?
    private var cameraDebugSubscription: AnyCancellable?
    private var lastDebugCameraPosition: SIMD3<Float>?

    init() {
        rootEntity.name = "room-scene-root"
        roomEntity.name = "room-shell"
        furnitureEntity.name = "furniture-root"
        lightingEntity.name = "lighting-root"
        rootEntity.addChild(roomEntity)
        rootEntity.addChild(furnitureEntity)
        rootEntity.addChild(lightingEntity)
        installLighting()

        cameraController.cameraDidChange = { [weak self] in
            self?.applyFallbackCameraTransform()
        }
    }

    func synchronize(scene: RoomScene, selectedFurnitureID: UUID?) {
        let width = RoomCoordinateSystem.safeRoomDimension(scene.roomWidth, fallback: 5.0)
        let depth = RoomCoordinateSystem.safeRoomDimension(scene.roomDepth, fallback: 4.0)
        let height = RoomCoordinateSystem.safeRoomDimension(scene.roomHeight, fallback: 2.7)
        let signature = RoomSignature(width: width, depth: depth, height: height)

        if roomSignature != signature {
            rebuildRoom(width: width, depth: depth, height: height)
            roomSignature = signature
        }

        synchronizeFurniture(scene.furniture, roomWidth: width, roomDepth: depth)
        updateSelection(selectedFurnitureID)

        let isNewScene = configuredSceneID != scene.id
        configuredSceneID = scene.id
        cameraController.configure(for: scene, reset: isNewScene)
    }

    func resetCamera() {
        cameraController.resetView()
    }

    @available(iOS 18.0, *)
    func startCameraDebugLogging() {
        guard cameraDebugSubscription == nil, let scene = rootEntity.scene else { return }
        lastDebugCameraPosition = cameraController.cameraEntity.position(relativeTo: nil)
        let subscription = scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cameraController.logCameraPositionIfChanged(
                    from: &self.lastDebugCameraPosition
                )
            }
        }
        cameraDebugSubscription = AnyCancellable(subscription)
    }

    func furnitureID(for entity: Entity) -> UUID? {
        EntityFactory.furnitureID(from: entity)
    }

    func attachFallback(to arView: ARView) {
        fallbackARView = arView
        if rootEntity.scene == nil {
            arView.scene.addAnchor(rootEntity)
        }
        applyFallbackCameraTransform()
    }

    private func rebuildRoom(width: Float, depth: Float, height: Float) {
        roomEntity.children.removeAll()
        let wallThickness = RoomCoordinateSystem.wallThickness
        let floorThickness = RoomCoordinateSystem.floorThickness
        let floorColor = UIColor(red: 0.77, green: 0.74, blue: 0.69, alpha: 1)
        let wallColor = UIColor(red: 0.91, green: 0.90, blue: 0.87, alpha: 1)

        roomEntity.addChild(
            EntityFactory.makeRoomSurface(
                name: "room-surface:floor",
                size: SIMD3<Float>(width, floorThickness, depth),
                position: SIMD3<Float>(0, -floorThickness / 2, 0),
                color: floorColor
            )
        )
        roomEntity.addChild(
            EntityFactory.makeRoomSurface(
                name: "room-surface:back-wall",
                size: SIMD3<Float>(width, height, wallThickness),
                position: SIMD3<Float>(0, height / 2, -depth / 2 - wallThickness / 2),
                color: wallColor
            )
        )
        roomEntity.addChild(
            EntityFactory.makeRoomSurface(
                name: "room-surface:left-wall",
                size: SIMD3<Float>(wallThickness, height, depth),
                position: SIMD3<Float>(-width / 2 - wallThickness / 2, height / 2, 0),
                color: wallColor
            )
        )
        roomEntity.addChild(
            EntityFactory.makeRoomSurface(
                name: "room-surface:right-wall",
                size: SIMD3<Float>(wallThickness, height, depth),
                position: SIMD3<Float>(width / 2 + wallThickness / 2, height / 2, 0),
                color: wallColor
            )
        )
    }

    private func synchronizeFurniture(
        _ furniture: [FurnitureItem],
        roomWidth: Float,
        roomDepth: Float
    ) {
        let currentIDs = Set(furniture.map(\.id))
        for staleID in Array(entityRegistry.keys) where !currentIDs.contains(staleID) {
            entityRegistry[staleID]?.root.removeFromParent()
            entityRegistry.removeValue(forKey: staleID)
        }

        for item in furniture {
            let record: FurnitureEntityRecord
            if let existing = entityRegistry[item.id] {
                record = existing
            } else {
                let created = EntityFactory.makeFurniture(item)
                furnitureEntity.addChild(created.root)
                entityRegistry[item.id] = created
                record = created
            }
            EntityFactory.update(
                record,
                from: item,
                roomWidth: roomWidth,
                roomDepth: roomDepth
            )
        }
    }

    private func updateSelection(_ selectedFurnitureID: UUID?) {
        for (id, record) in entityRegistry {
            record.selectionHalo.isEnabled = id == selectedFurnitureID
        }
    }

    private func installLighting() {
        let sun = DirectionalLight()
        sun.name = "soft-key-light"
        sun.light.intensity = 1450
        sun.look(
            at: SIMD3<Float>(0, 0.8, 0),
            from: SIMD3<Float>(-4, 6, 5),
            relativeTo: nil
        )
        lightingEntity.addChild(sun)

        let fill = PointLight()
        fill.name = "soft-fill-light"
        fill.light.intensity = 850
        fill.light.attenuationRadius = 12
        fill.position = SIMD3<Float>(2.2, 3.4, 2.5)
        lightingEntity.addChild(fill)
    }

    private func applyFallbackCameraTransform() {
        guard fallbackARView != nil else { return }
        // ARView's non-AR camera is read-only. Applying the inverse camera
        // transform to the shared root produces the same view on iOS 17.
        let cameraMatrix = cameraController.cameraEntity.transformMatrix(relativeTo: nil)
        rootEntity.transform = Transform(matrix: cameraMatrix.inverse)
    }
}

private struct RoomSignature: Equatable {
    let width: Float
    let depth: Float
    let height: Float
}
