import Foundation
import RealityKit

@MainActor
final class RoomPlanARSceneCoordinator {
    let anchor = AnchorEntity(world: .zero)

    private let objectRoot = Entity()
    private var objectRecords: [UUID: RoomPlanObjectEntityRecord] = [:]

    init() {
        anchor.name = "roomplan-ar-origin"
        anchor.addChild(objectRoot)
    }

    func synchronize(project: RoomPlanProject) {
        // AR is a proposal preview, not a second rendering of the captured
        // room. Unchanged scanned furniture and all structural surfaces stay
        // in the live camera image; only edits are represented virtually.
        let changedObjects = project.objects.filter(\.shouldRenderAsARChange)
        let currentIDs = Set(changedObjects.map(\.id))
        for staleID in Array(objectRecords.keys) where !currentIDs.contains(staleID) {
            objectRecords[staleID]?.entity.removeFromParent()
            objectRecords.removeValue(forKey: staleID)
        }
        for object in changedObjects {
            let record: RoomPlanObjectEntityRecord
            if let existing = objectRecords[object.id] {
                record = existing
                RoomPlanEntityFactory.update(existing, from: object)
            } else {
                record = RoomPlanEntityFactory.makeObject(object)
                objectRecords[object.id] = record
                objectRoot.addChild(record.entity)
            }
            record.highlight.isEnabled = false
        }
    }
}
