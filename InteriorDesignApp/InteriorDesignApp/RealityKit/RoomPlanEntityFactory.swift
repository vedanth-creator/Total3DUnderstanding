import RealityKit
import UIKit

@MainActor
enum RoomPlanEntityFactory {
    static let objectPrefix = "roomplan-object:"

    static func makeSceneRoot(
        for project: RoomPlanProject,
        includeFloor: Bool
    ) -> Entity {
        let root = Entity()
        root.name = "roomplan-scene"
        for surface in project.surfaces {
            if surface.kind == .floor && !includeFloor { continue }
            root.addChild(makeSurface(surface))
        }
        for object in project.objects {
            root.addChild(makeObject(object).entity)
        }
        return root
    }

    static func makeSurface(_ surface: RoomPlanSurfaceModel) -> ModelEntity {
        let appearance = surfaceAppearance(surface.kind)
        var dimensions = surface.dimensions.vector
        switch surface.kind {
        case .wall, .door, .window, .opening:
            dimensions.z = max(dimensions.z, 0.035)
        case .floor:
            dimensions.y = max(dimensions.y, 0.025)
        }
        let entity = ModelEntity(
            mesh: .generateBox(size: dimensions),
            materials: [appearance]
        )
        entity.name = "roomplan-surface:\(surface.id.uuidString)"
        entity.transform = Transform(matrix: surface.transform.matrix)
        return entity
    }

    static func makeObject(_ object: EditableRoomPlanObject) -> RoomPlanObjectEntityRecord {
        let dimensions = object.dimensions.vector
        let material = SimpleMaterial(
            color: categoryColor(object.category),
            roughness: 0.78,
            isMetallic: false
        )
        let entity = ModelEntity(
            mesh: .generateBox(size: dimensions, cornerRadius: min(dimensions.x, dimensions.z) * 0.05),
            materials: [material]
        )
        entity.name = objectPrefix + object.id.uuidString
        entity.transform = Transform(matrix: object.transform.matrix)
        entity.components.set(
            CollisionComponent(shapes: [.generateBox(size: dimensions)])
        )

        var highlightMaterial = UnlitMaterial()
        highlightMaterial.color = .init(tint: UIColor(red: 1, green: 0.72, blue: 0.05, alpha: 0.32))
        let highlight = ModelEntity(
            mesh: .generateBox(
                size: dimensions + SIMD3<Float>(repeating: 0.08),
                cornerRadius: min(dimensions.x, dimensions.z) * 0.05
            ),
            materials: [highlightMaterial]
        )
        highlight.name = "roomplan-selection:\(object.id.uuidString)"
        highlight.components.remove(CollisionComponent.self)
        highlight.isEnabled = false
        entity.addChild(highlight)

        return RoomPlanObjectEntityRecord(entity: entity, highlight: highlight)
    }

    static func update(_ record: RoomPlanObjectEntityRecord, from object: EditableRoomPlanObject) {
        record.entity.transform = Transform(matrix: object.transform.matrix)
    }

    static func objectID(from entity: Entity?) -> UUID? {
        var candidate = entity
        while let current = candidate {
            if current.name.hasPrefix(objectPrefix) {
                return UUID(uuidString: String(current.name.dropFirst(objectPrefix.count)))
            }
            candidate = current.parent
        }
        return nil
    }

    private static func surfaceAppearance(_ kind: RoomPlanSurfaceKind) -> SimpleMaterial {
        let color: UIColor
        switch kind {
        case .wall:
            color = UIColor(red: 0.84, green: 0.83, blue: 0.79, alpha: 0.92)
        case .door(let isOpen):
            color = isOpen
                ? UIColor(red: 0.35, green: 0.62, blue: 0.48, alpha: 0.38)
                : UIColor(red: 0.45, green: 0.31, blue: 0.20, alpha: 0.68)
        case .window:
            color = UIColor(red: 0.36, green: 0.66, blue: 0.83, alpha: 0.42)
        case .opening:
            color = UIColor(red: 0.98, green: 0.72, blue: 0.24, alpha: 0.28)
        case .floor:
            color = UIColor(red: 0.72, green: 0.69, blue: 0.63, alpha: 0.72)
        }
        return SimpleMaterial(color: color, roughness: 0.9, isMetallic: false)
    }

    private static func categoryColor(_ category: String) -> UIColor {
        switch category {
        case "Chair", "Sofa": UIColor(red: 0.39, green: 0.48, blue: 0.40, alpha: 0.9)
        case "Table": UIColor(red: 0.50, green: 0.36, blue: 0.25, alpha: 0.9)
        case "Bed": UIColor(red: 0.50, green: 0.52, blue: 0.63, alpha: 0.9)
        default: UIColor(red: 0.57, green: 0.55, blue: 0.50, alpha: 0.9)
        }
    }
}

struct RoomPlanObjectEntityRecord {
    let entity: ModelEntity
    let highlight: ModelEntity
}
