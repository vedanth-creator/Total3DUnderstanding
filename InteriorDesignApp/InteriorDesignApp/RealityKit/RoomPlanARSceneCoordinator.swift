import Foundation
import RealityKit

@MainActor
final class RoomPlanARSceneCoordinator {
    let anchor = AnchorEntity(world: .zero)

    private let surfaceRoot = Entity()
    private let objectRoot = Entity()
    private var objectRecords: [UUID: RoomPlanObjectEntityRecord] = [:]
    private var configuredProjectID: UUID?

    init() {
        anchor.name = "roomplan-ar-origin"
        anchor.addChild(surfaceRoot)
        anchor.addChild(objectRoot)
    }

    func synchronize(project: RoomPlanProject, selectedObjectID: UUID?) {
        if configuredProjectID != project.id {
            surfaceRoot.children.removeAll()
            for surface in project.surfaces where surface.kind != .floor {
                surfaceRoot.addChild(RoomPlanEntityFactory.makeSurface(surface))
            }
            configuredProjectID = project.id
        }

        let currentIDs = Set(project.objects.map(\.id))
        for staleID in Array(objectRecords.keys) where !currentIDs.contains(staleID) {
            objectRecords[staleID]?.entity.removeFromParent()
            objectRecords.removeValue(forKey: staleID)
        }
        for object in project.objects {
            let record: RoomPlanObjectEntityRecord
            if let existing = objectRecords[object.id] {
                record = existing
                RoomPlanEntityFactory.update(existing, from: object)
            } else {
                record = RoomPlanEntityFactory.makeObject(object)
                objectRecords[object.id] = record
                objectRoot.addChild(record.entity)
            }
            record.highlight.isEnabled = object.id == selectedObjectID
        }
    }
}
