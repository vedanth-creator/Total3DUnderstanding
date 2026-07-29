import Combine
import RealityKit
import UIKit

@MainActor
final class RoomSceneCoordinator: ObservableObject {
    let rootEntity = AnchorEntity(world: .zero)
    let cameraController = CameraController()

    private let compatibilityCameraAnchor = AnchorEntity(world: .zero)
    private let roomEntity = Entity()
    private let furnitureEntity = Entity()
    private let lightingEntity = Entity()
    private var entityRegistry: [UUID: FurnitureEntityRecord] = [:]
    private var furnitureSnapshots: [UUID: FurnitureItem] = [:]
    private var roomSignature: RoomSignature?
    private var configuredSceneID: UUID?
    private var synchronizedSelectionID: UUID?
    private var currentScene: RoomScene?
    private var initialCameraRequestSceneID: UUID?
    private var initialCameraAppliedSceneID: UUID?
    private var initialCameraTask: Task<Void, Never>?
    private weak var fallbackARView: ARView?

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
        AppDebugLog.write("RoomSceneCoordinator created")
    }

    deinit {
        initialCameraTask?.cancel()
        AppDebugLog.write("RoomSceneCoordinator released")
    }

    @discardableResult
    func synchronize(scene: RoomScene, selectedFurnitureID: UUID?) -> Bool {
        let width = RoomCoordinateSystem.safeRoomDimension(scene.roomWidth, fallback: 5.0)
        let depth = RoomCoordinateSystem.safeRoomDimension(scene.roomDepth, fallback: 4.0)
        let height = RoomCoordinateSystem.safeRoomDimension(scene.roomHeight, fallback: 2.7)
        let signature = RoomSignature(width: width, depth: depth, height: height)

        let roomChanged = roomSignature != signature
        if roomChanged {
            rebuildRoom(width: width, depth: depth, height: height)
            roomSignature = signature
            AppDebugLog.write(
                "Room shell rebuilt; width=\(width) depth=\(depth) height=\(height)"
            )
        }

        synchronizeFurniture(
            scene.furniture,
            roomWidth: width,
            roomDepth: depth,
            forceUpdate: roomChanged
        )
        if synchronizedSelectionID != selectedFurnitureID {
            updateSelection(selectedFurnitureID)
            synchronizedSelectionID = selectedFurnitureID
            AppDebugLog.write(
                "Scene selection synchronized; furniture=\(selectedFurnitureID?.uuidString ?? "none")"
            )
        }

        let isNewScene = configuredSceneID != scene.id
        currentScene = scene
        configuredSceneID = scene.id
        if isNewScene {
            initialCameraTask?.cancel()
            initialCameraTask = nil
            initialCameraRequestSceneID = nil
            initialCameraAppliedSceneID = nil
            AppDebugLog.write(
                "Scene first synchronization; id=\(scene.id) furniture=\(scene.furniture.count)"
            )
        }
        return isNewScene
    }

    func resetCamera() {
        guard let currentScene else {
            AppDebugLog.write("Manual camera reset ignored because no scene is synchronized")
            return
        }
        initialCameraTask?.cancel()
        initialCameraTask = nil
        applyCameraReset(for: currentScene, reason: "manual")
        initialCameraAppliedSceneID = currentScene.id
    }

    func requestInitialCameraReset(
        for sceneID: UUID,
        renderer: RoomRendererPath
    ) {
        guard
            initialCameraAppliedSceneID != sceneID,
            initialCameraRequestSceneID != sceneID
        else { return }

        initialCameraRequestSceneID = sceneID
        AppDebugLog.write(
            "Initial camera reset requested; scene=\(sceneID) renderer=\(renderer.debugName)"
        )
        initialCameraTask?.cancel()
        initialCameraTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }

            if let self {
                if self.rendererIsReady(renderer) {
                    self.applyInitialCameraReset(for: sceneID, retryNeeded: false)
                    return
                }
            }

            AppDebugLog.write(
                "Initial camera attachments not ready after yield; scheduling one retry"
            )
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, !Task.isCancelled else { return }
            guard self.rendererIsReady(renderer) else {
                self.initialCameraRequestSceneID = nil
                self.initialCameraTask = nil
                AppDebugLog.write(
                    "Initial camera reset not applied because attachments remained unavailable after one retry"
                )
                return
            }
            self.applyInitialCameraReset(for: sceneID, retryNeeded: true)
        }
    }

    func furnitureID(for entity: Entity) -> UUID? {
        EntityFactory.furnitureID(from: entity)
    }

    func attachFallback(to arView: ARView) {
        fallbackARView = arView
        if rootEntity.scene == nil {
            arView.scene.addAnchor(rootEntity)
        }
        if compatibilityCameraAnchor.scene == nil {
            compatibilityCameraAnchor.isEnabled = false
            compatibilityCameraAnchor.addChild(cameraController.cameraEntity)
            compatibilityCameraAnchor.addChild(cameraController.orbitTargetEntity)
            arView.scene.addAnchor(compatibilityCameraAnchor)
        }
        applyFallbackCameraTransform()
        AppDebugLog.write("Camera entity attached to disabled iOS 17 compatibility rig")
        AppDebugLog.write("Orbit target attached to disabled iOS 17 compatibility rig")
        AppDebugLog.write("Room/content root attached to iOS 17 ARView")
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
        roomDepth: Float,
        forceUpdate: Bool
    ) {
        let currentIDs = Set(furniture.map(\.id))
        for staleID in Array(entityRegistry.keys) where !currentIDs.contains(staleID) {
            entityRegistry[staleID]?.root.removeFromParent()
            entityRegistry.removeValue(forKey: staleID)
            furnitureSnapshots.removeValue(forKey: staleID)
            AppDebugLog.write("Removed furniture entity id=\(staleID)")
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
                AppDebugLog.write("Created furniture entity id=\(item.id)")
            }
            if forceUpdate || furnitureSnapshots[item.id] != item {
                EntityFactory.update(
                    record,
                    from: item,
                    roomWidth: roomWidth,
                    roomDepth: roomDepth
                )
                furnitureSnapshots[item.id] = item
            }
        }
    }

    private func updateSelection(_ selectedFurnitureID: UUID?) {
        for (id, record) in entityRegistry {
            record.selectionOutline.root.isEnabled = id == selectedFurnitureID
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

    private func rendererIsReady(_ renderer: RoomRendererPath) -> Bool {
        switch renderer {
        case .realityView:
            return cameraController.cameraEntity.scene != nil
                && cameraController.orbitTargetEntity.scene != nil
                && rootEntity.scene != nil
        case .arViewCompatibility:
            return fallbackARView != nil
                && compatibilityCameraAnchor.scene != nil
                && rootEntity.scene != nil
        }
    }

    private func applyInitialCameraReset(for sceneID: UUID, retryNeeded: Bool) {
        guard
            initialCameraAppliedSceneID != sceneID,
            configuredSceneID == sceneID,
            let currentScene,
            currentScene.id == sceneID
        else { return }

        applyCameraReset(for: currentScene, reason: "initial")
        initialCameraAppliedSceneID = sceneID
        initialCameraRequestSceneID = nil
        initialCameraTask = nil
        AppDebugLog.write(
            "Initial camera reset applied; scene=\(sceneID) position=\(cameraController.cameraPosition) retryNeeded=\(retryNeeded)"
        )
    }

    private func applyCameraReset(for scene: RoomScene, reason: String) {
        cameraController.applyResetCamera(for: scene, reason: reason)
    }
}

enum RoomRendererPath {
    case realityView
    case arViewCompatibility

    var debugName: String {
        switch self {
        case .realityView: "RealityView"
        case .arViewCompatibility: "ARView compatibility"
        }
    }
}

private struct RoomSignature: Equatable {
    let width: Float
    let depth: Float
    let height: Float
}
