import Foundation
import RealityKit

@MainActor
final class RoomPlanSceneCoordinator {
    let anchor = AnchorEntity(world: .zero)

    private let sceneRoot = Entity()
    private let surfaceRoot = Entity()
    private let objectRoot = Entity()
    private var records: [UUID: RoomPlanObjectEntityRecord] = [:]
    private var configuredProjectID: UUID?

    init() {
        anchor.name = "roomplan-editor-anchor"
        sceneRoot.name = "roomplan-editor-root"
        surfaceRoot.name = "roomplan-surfaces"
        objectRoot.name = "roomplan-objects"
        anchor.addChild(sceneRoot)
        sceneRoot.addChild(surfaceRoot)
        sceneRoot.addChild(objectRoot)
    }

    func synchronize(project: RoomPlanProject, selectedObjectID: UUID?, angled: Bool) {
        if configuredProjectID != project.id {
            rebuildSurfaces(project.surfaces)
            configuredProjectID = project.id
        }

        let currentIDs = Set(project.objects.map(\.id))
        for staleID in Array(records.keys) where !currentIDs.contains(staleID) {
            records[staleID]?.entity.removeFromParent()
            records.removeValue(forKey: staleID)
        }
        for object in project.objects {
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
        applyDollhouseTransform(bounds: project.floorBounds, angled: angled)
    }

    func objectID(from entity: Entity?) -> UUID? {
        RoomPlanEntityFactory.objectID(from: entity)
    }

    private func rebuildSurfaces(_ surfaces: [RoomPlanSurfaceModel]) {
        surfaceRoot.children.removeAll()
        for surface in surfaces {
            surfaceRoot.addChild(RoomPlanEntityFactory.makeSurface(surface))
        }
    }

    private func applyDollhouseTransform(bounds: RoomPlanFloorBounds, angled: Bool) {
        // RoomPlan and the editor both use meters with X left/right, Y up, and
        // Z forward/back. ARView's non-AR camera looks down -Z, so the shared
        // scene root is rotated for presentation only; object data stays in
        // the original RoomPlan coordinate system.
        let span = max(max(bounds.width, bounds.depth), 2)
        let distance = span * (angled ? 1.35 : 1.15)
        let center = bounds.center
        let centerTranslation = simd_float4x4(translation: SIMD3<Float>(-center.x, 0, -center.z))
        let pitch = simd_float4x4(
            simd_quatf(angle: angled ? -.pi / 3.2 : -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        )
        let viewTranslation = simd_float4x4(translation: SIMD3<Float>(0, angled ? -span * 0.08 : 0, -distance))
        sceneRoot.transform = Transform(matrix: viewTranslation * pitch * centerTranslation)
    }
}

private extension simd_float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1)
    }
}
