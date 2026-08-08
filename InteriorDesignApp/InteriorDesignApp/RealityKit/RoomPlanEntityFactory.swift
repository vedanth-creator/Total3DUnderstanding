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
        for object in project.objects where !object.isRemoved {
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
        let entity = Entity()
        entity.name = objectPrefix + object.id.uuidString
        entity.transform = Transform(matrix: object.transform.matrix)
        entity.components.set(
            CollisionComponent(shapes: [.generateBox(size: dimensions)])
        )

        addPlaceholderGeometry(
            category: object.category,
            dimensions: dimensions,
            to: entity
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
        case "Lamp": UIColor(red: 0.78, green: 0.65, blue: 0.38, alpha: 0.95)
        case "Plant": UIColor(red: 0.32, green: 0.50, blue: 0.30, alpha: 0.95)
        case "Wall Art": UIColor(red: 0.48, green: 0.42, blue: 0.58, alpha: 0.95)
        default: UIColor(red: 0.57, green: 0.55, blue: 0.50, alpha: 0.9)
        }
    }

    private static func addPlaceholderGeometry(
        category: String,
        dimensions d: SIMD3<Float>,
        to root: Entity
    ) {
        let material = SimpleMaterial(
            color: categoryColor(category),
            roughness: 0.78,
            isMetallic: false
        )
        let accent = SimpleMaterial(
            color: categoryColor(category).withAlphaComponent(0.72),
            roughness: 0.9,
            isMetallic: false
        )

        switch category {
        case "Chair":
            addBox(to: root, size: SIMD3<Float>(d.x * 0.88, d.y * 0.16, d.z * 0.84), position: SIMD3<Float>(0, -d.y * 0.12, 0), material: material)
            addBox(to: root, size: SIMD3<Float>(d.x * 0.88, d.y * 0.55, d.z * 0.14), position: SIMD3<Float>(0, d.y * 0.20, -d.z * 0.36), material: accent)
            addFourLegs(to: root, dimensions: d, material: accent)
        case "Sofa":
            addBox(to: root, size: SIMD3<Float>(d.x, d.y * 0.48, d.z * 0.82), position: SIMD3<Float>(0, -d.y * 0.22, 0), material: material)
            addBox(to: root, size: SIMD3<Float>(d.x, d.y * 0.58, d.z * 0.18), position: SIMD3<Float>(0, d.y * 0.20, -d.z * 0.39), material: accent)
            for x: Float in [-d.x * 0.46, d.x * 0.46] {
                addBox(to: root, size: SIMD3<Float>(d.x * 0.08, d.y * 0.42, d.z * 0.75), position: SIMD3<Float>(x, 0, 0), material: accent)
            }
        case "Table":
            addBox(to: root, size: SIMD3<Float>(d.x, d.y * 0.12, d.z), position: SIMD3<Float>(0, d.y * 0.43, 0), material: material)
            addFourLegs(to: root, dimensions: d, material: accent)
        case "Bed":
            addBox(to: root, size: SIMD3<Float>(d.x, d.y * 0.55, d.z * 0.92), position: SIMD3<Float>(0, -d.y * 0.18, d.z * 0.03), material: material)
            addBox(to: root, size: SIMD3<Float>(d.x, d.y, d.z * 0.10), position: SIMD3<Float>(0, 0, -d.z * 0.45), material: accent)
        case "Storage":
            addBox(to: root, size: d, position: .zero, material: material)
            addBox(to: root, size: SIMD3<Float>(d.x * 0.02, d.y * 0.9, d.z * 0.02), position: SIMD3<Float>(0, 0, d.z * 0.51), material: accent)
        case "Television":
            addBox(to: root, size: SIMD3<Float>(d.x, d.y * 0.84, max(d.z * 0.28, 0.04)), position: SIMD3<Float>(0, d.y * 0.08, 0), material: material)
            addBox(to: root, size: SIMD3<Float>(d.x * 0.35, d.y * 0.08, d.z), position: SIMD3<Float>(0, -d.y * 0.44, 0), material: accent)
        case "Lamp":
            addBox(to: root, size: SIMD3<Float>(d.x * 0.16, d.y * 0.72, d.z * 0.16), position: SIMD3<Float>(0, -d.y * 0.10, 0), material: accent)
            addBox(to: root, size: SIMD3<Float>(d.x, d.y * 0.25, d.z), position: SIMD3<Float>(0, d.y * 0.34, 0), material: material)
            addBox(to: root, size: SIMD3<Float>(d.x * 0.7, d.y * 0.05, d.z * 0.7), position: SIMD3<Float>(0, -d.y * 0.47, 0), material: accent)
        case "Plant":
            addBox(to: root, size: SIMD3<Float>(d.x * 0.55, d.y * 0.34, d.z * 0.55), position: SIMD3<Float>(0, -d.y * 0.33, 0), material: accent)
            let canopy = ModelEntity(mesh: .generateSphere(radius: min(d.x, d.z) * 0.47), materials: [material])
            canopy.position = SIMD3<Float>(0, d.y * 0.20, 0)
            root.addChild(canopy)
        case "Wall Art":
            addBox(to: root, size: d, position: .zero, material: material)
            addBox(to: root, size: SIMD3<Float>(d.x * 0.86, d.y * 0.80, d.z * 1.08), position: SIMD3<Float>(0, 0, d.z * 0.04), material: accent)
        default:
            addBox(to: root, size: d, position: .zero, material: material)
        }
    }

    private static func addFourLegs(
        to root: Entity,
        dimensions d: SIMD3<Float>,
        material: SimpleMaterial
    ) {
        let legSize = SIMD3<Float>(max(d.x * 0.08, 0.04), d.y * 0.78, max(d.z * 0.08, 0.04))
        for x: Float in [-d.x * 0.40, d.x * 0.40] {
            for z: Float in [-d.z * 0.38, d.z * 0.38] {
                addBox(
                    to: root,
                    size: legSize,
                    position: SIMD3<Float>(x, -d.y * 0.10, z),
                    material: material
                )
            }
        }
    }

    private static func addBox(
        to root: Entity,
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        material: SimpleMaterial
    ) {
        let box = ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: min(size.x, size.z) * 0.04),
            materials: [material]
        )
        box.position = position
        root.addChild(box)
    }
}

struct RoomPlanObjectEntityRecord {
    let entity: Entity
    let highlight: ModelEntity
}
