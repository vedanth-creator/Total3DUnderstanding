import Foundation
import RealityKit

@MainActor
final class RoomPlanSceneCoordinator {
    let anchor = AnchorEntity(world: .zero)
    let sceneRoot = Entity()

    private let surfaceRoot = Entity()
    private let objectRoot = Entity()
    private let lightingRoot = Entity()
    private var records: [UUID: RoomPlanObjectEntityRecord] = [:]
    private var configuredProjectID: UUID?

    init() {
        anchor.name = "roomplan-editor-anchor"
        sceneRoot.name = "roomplan-editor-root"
        surfaceRoot.name = "roomplan-surfaces"
        objectRoot.name = "roomplan-objects"
        lightingRoot.name = "roomplan-lighting-root"
        anchor.addChild(sceneRoot)
        anchor.addChild(lightingRoot)
        sceneRoot.addChild(surfaceRoot)
        sceneRoot.addChild(objectRoot)
    }

    func synchronize(project: RoomPlanProject, selectedObjectID: UUID?) {
        if configuredProjectID != project.id {
            rebuildSurfaces(project)
            rebuildLighting(roomHeight: project.roomHeight)
            configuredProjectID = project.id
        }

        let visibleObjects = project.objects.filter { !$0.isRemoved }
        let currentIDs = Set(visibleObjects.map(\.id))
        for staleID in Array(records.keys) where !currentIDs.contains(staleID) {
            records[staleID]?.entity.removeFromParent()
            records.removeValue(forKey: staleID)
        }
        for object in visibleObjects {
            let record: RoomPlanObjectEntityRecord
            if let existing = records[object.id] {
                record = existing
                RoomPlanEntityFactory.update(existing, from: object)
            } else {
                record = RoomPlanEntityFactory.makeObject(object)
                records[object.id] = record
                objectRoot.addChild(record.entity)
            }
            record.highlight.isEnabled = object.id == selectedObjectID
        }
    }

    func objectID(from entity: Entity?) -> UUID? {
        RoomPlanEntityFactory.objectID(from: entity)
    }

    func roomPoint(
        for screenPoint: CGPoint,
        in view: ARView,
        horizontalPlaneY: Float
    ) -> SIMD3<Float>? {
        guard let ray = view.ray(through: screenPoint) else { return nil }
        let roomFromView = sceneRoot.transformMatrix(relativeTo: nil).inverse
        let origin4 = roomFromView * SIMD4<Float>(ray.origin.x, ray.origin.y, ray.origin.z, 1)
        let direction4 = roomFromView * SIMD4<Float>(ray.direction.x, ray.direction.y, ray.direction.z, 0)
        let origin = SIMD3<Float>(origin4.x, origin4.y, origin4.z)
        let direction = simd_normalize(SIMD3<Float>(direction4.x, direction4.y, direction4.z))
        guard abs(direction.y) > 0.0001 else { return nil }
        let distance = (horizontalPlaneY - origin.y) / direction.y
        guard distance > 0 else { return nil }
        return origin + direction * distance
    }

    private func rebuildSurfaces(_ project: RoomPlanProject) {
        surfaceRoot.children.removeAll()
        for surface in RoomPlanEntityFactory.makeArchitecturalSurfaces(for: project) {
            surfaceRoot.addChild(surface)
        }
    }

    private func rebuildLighting(roomHeight: Float) {
        lightingRoot.children.removeAll()
        lightingRoot.addChild(
            RoomPlanLightingController.makeEditorLighting(roomHeight: roomHeight)
        )
    }

}
