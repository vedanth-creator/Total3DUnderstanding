import RealityKit
import UIKit

@MainActor
enum RoomPlanEntityFactory {
    static let objectPrefix = "roomplan-object:"
    private static let wallThickness: Float = 0.04
    private static let floorThickness: Float = 0.025
    private static let insetThickness: Float = 0.012
    private static let insetFaceGap: Float = 0.002
    private static let architecturalFrameDepth: Float = 0.022

    static func makeSceneRoot(
        for project: RoomPlanProject,
        includeFloor: Bool
    ) -> Entity {
        let root = Entity()
        root.name = "roomplan-scene"
        for surface in makeArchitecturalSurfaces(for: project, includeFloor: includeFloor) {
            root.addChild(surface)
        }
        for object in project.objects where !object.isRemoved {
            root.addChild(makeObject(object).entity)
        }
        return root
    }

    static func makeArchitecturalSurfaces(
        for project: RoomPlanProject,
        includeFloor: Bool = true
    ) -> [Entity] {
        let wallsByID = Dictionary(
            uniqueKeysWithValues: project.walls.map { ($0.id, $0) }
        )
        return project.surfaces.compactMap { surface in
            if surface.kind == .floor && !includeFloor { return nil }
            return makeSurface(
                surface,
                roomCenter: project.floorBounds.center,
                parentWall: surface.parentIdentifier.flatMap { wallsByID[$0] }
            )
        }
    }

    private static func makeSurface(
        _ surface: RoomPlanSurfaceModel,
        roomCenter: SIMD3<Float>,
        parentWall: RoomPlanSurfaceModel?
    ) -> Entity {
        let measuredDimensions = surface.dimensions.vector
        let generatedDimensions: SIMD3<Float>
        let strategy: String
        switch surface.kind {
        case .wall:
            generatedDimensions = SIMD3<Float>(
                measuredDimensions.x,
                measuredDimensions.y,
                wallThickness
            )
            strategy = "wall geometry"
        case .floor:
            // RoomPlan surfaces are local XY planes; local Z is their normal.
            generatedDimensions = SIMD3<Float>(
                measuredDimensions.x,
                measuredDimensions.y,
                floorThickness
            )
            strategy = "floor geometry"
        case .door, .window:
            generatedDimensions = SIMD3<Float>(
                measuredDimensions.x,
                measuredDimensions.y,
                insetThickness
            )
            strategy = "inset geometry"
        case .opening:
            generatedDimensions = SIMD3<Float>(
                measuredDimensions.x,
                measuredDimensions.y,
                insetThickness
            )
            strategy = "opening frame geometry"
        }

        let entity: Entity
        switch surface.kind {
        case .wall:
            entity = ModelEntity(
                mesh: .generateBox(size: generatedDimensions),
                materials: [RoomPlanMaterialLibrary.paintedWall]
            )
        case .floor:
            entity = ModelEntity(
                mesh: .generateBox(size: generatedDimensions),
                materials: [RoomPlanMaterialLibrary.lightWood]
            )
        case .window:
            entity = makeWindow(dimensions: generatedDimensions)
        case .door(let isOpen):
            entity = makeDoor(dimensions: generatedDimensions, isOpen: isOpen)
        case .opening:
            entity = makeOpeningFrame(dimensions: generatedDimensions)
        }
        entity.name = "roomplan-surface:\(surface.id.uuidString)"
        var renderedTransform = surface.transform.matrix
        if surface.kind != .wall && surface.kind != .floor {
            let referenceTransform = parentWall?.transform.matrix ?? surface.transform.matrix
            let referencePosition = position(of: referenceTransform)
            let candidateNormal = normalizedNormal(of: referenceTransform)
            let toRoomCenter = roomCenter - referencePosition
            let inwardNormal = simd_dot(candidateNormal, toRoomCenter) >= 0
                ? candidateNormal
                : -candidateNormal
            let offset = wallThickness / 2 + insetThickness / 2 + insetFaceGap
            renderedTransform.columns.3 += SIMD4<Float>(
                inwardNormal.x * offset,
                inwardNormal.y * offset,
                inwardNormal.z * offset,
                0
            )
        }
        entity.transform = Transform(matrix: renderedTransform)
        logArchitecturalSurface(
            surface,
            generatedDimensions: generatedDimensions,
            renderedTransform: renderedTransform,
            strategy: strategy
        )
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

        let visual = FurnitureAssetLibrary.shared.makeVisual(
            category: object.category,
            dimensions: dimensions
        )
        entity.addChild(visual)

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

    private static func makeOpeningFrame(
        dimensions: SIMD3<Float>
    ) -> Entity {
        let root = Entity()
        let frameWidth = min(max(min(dimensions.x, dimensions.y) * 0.045, 0.025), 0.06)
        let horizontalSize = SIMD3<Float>(dimensions.x, frameWidth, architecturalFrameDepth)
        let verticalHeight = max(dimensions.y - frameWidth * 2, frameWidth)
        let verticalSize = SIMD3<Float>(frameWidth, verticalHeight, architecturalFrameDepth)
        let halfX = max(dimensions.x / 2 - frameWidth / 2, 0)
        let halfY = max(dimensions.y / 2 - frameWidth / 2, 0)

        addBox(to: root, size: horizontalSize, position: SIMD3<Float>(0, halfY, 0), material: RoomPlanMaterialLibrary.windowFrame)
        addBox(to: root, size: horizontalSize, position: SIMD3<Float>(0, -halfY, 0), material: RoomPlanMaterialLibrary.windowFrame)
        addBox(to: root, size: verticalSize, position: SIMD3<Float>(halfX, 0, 0), material: RoomPlanMaterialLibrary.windowFrame)
        addBox(to: root, size: verticalSize, position: SIMD3<Float>(-halfX, 0, 0), material: RoomPlanMaterialLibrary.windowFrame)
        return root
    }

    private static func makeWindow(dimensions: SIMD3<Float>) -> Entity {
        let root = Entity()
        let frameWidth = min(max(min(dimensions.x, dimensions.y) * 0.055, 0.028), 0.07)
        let paneWidth = max(dimensions.x - frameWidth * 2.35, frameWidth)
        let paneHeight = max(dimensions.y - frameWidth * 2.35, frameWidth)
        let halfX = max(dimensions.x / 2 - frameWidth / 2, 0)
        let halfY = max(dimensions.y / 2 - frameWidth / 2, 0)
        let horizontal = SIMD3<Float>(dimensions.x, frameWidth, architecturalFrameDepth)
        let vertical = SIMD3<Float>(frameWidth, max(dimensions.y - frameWidth * 2, frameWidth), architecturalFrameDepth)

        // The opaque tinted pane does not overlap the frame in XY, and its face
        // sits behind the thicker frame. This preserves the deterministic wall
        // separation without introducing transparent coplanar surfaces.
        addBox(
            to: root,
            size: SIMD3<Float>(paneWidth, paneHeight, insetThickness * 0.48),
            material: RoomPlanMaterialLibrary.stableGlass
        )
        addBox(to: root, size: horizontal, position: SIMD3<Float>(0, halfY, 0), material: RoomPlanMaterialLibrary.windowFrame)
        addBox(to: root, size: horizontal, position: SIMD3<Float>(0, -halfY, 0), material: RoomPlanMaterialLibrary.windowFrame)
        addBox(to: root, size: vertical, position: SIMD3<Float>(halfX, 0, 0), material: RoomPlanMaterialLibrary.windowFrame)
        addBox(to: root, size: vertical, position: SIMD3<Float>(-halfX, 0, 0), material: RoomPlanMaterialLibrary.windowFrame)
        addBox(
            to: root,
            size: SIMD3<Float>(frameWidth * 0.72, paneHeight, architecturalFrameDepth * 0.82),
            material: RoomPlanMaterialLibrary.windowFrame
        )
        return root
    }

    private static func makeDoor(dimensions: SIMD3<Float>, isOpen: Bool) -> Entity {
        let root = Entity()
        let bodyMaterial = isOpen
            ? RoomPlanMaterialLibrary.paintedWall
            : RoomPlanMaterialLibrary.doorPanel
        addBox(to: root, size: dimensions, material: bodyMaterial)

        let railWidth = min(max(dimensions.x * 0.075, 0.035), 0.085)
        let railDepth = architecturalFrameDepth
        let insetWidth = max(dimensions.x - railWidth * 2.6, railWidth)
        let insetHeight = max(dimensions.y * 0.27, railWidth)
        for y: Float in [-dimensions.y * 0.20, dimensions.y * 0.20] {
            addBox(
                to: root,
                size: SIMD3<Float>(insetWidth, insetHeight, railDepth),
                position: SIMD3<Float>(0, y, 0),
                material: RoomPlanMaterialLibrary.doorInset
            )
        }

        let knob = ModelEntity(
            mesh: .generateSphere(radius: max(min(dimensions.x, dimensions.y) * 0.025, 0.018)),
            materials: [RoomPlanMaterialLibrary.warmMetal]
        )
        knob.position = SIMD3<Float>(dimensions.x * 0.36, 0, railDepth * 0.75)
        root.addChild(knob)
        return root
    }

    private static func normalizedNormal(of transform: simd_float4x4) -> SIMD3<Float> {
        let normal = SIMD3<Float>(
            transform.columns.2.x,
            transform.columns.2.y,
            transform.columns.2.z
        )
        let length = simd_length(normal)
        return length > 0.0001 ? normal / length : SIMD3<Float>(0, 0, 1)
    }

    private static func position(of transform: simd_float4x4) -> SIMD3<Float> {
        SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }

    private static func logArchitecturalSurface(
        _ surface: RoomPlanSurfaceModel,
        generatedDimensions: SIMD3<Float>,
        renderedTransform: simd_float4x4,
        strategy: String
    ) {
        let measured = surface.dimensions.vector
        let capturedPosition = surface.transform.position
        let renderedPosition = position(of: renderedTransform)
        let rotation = Transform(matrix: surface.transform.matrix).rotation
        AppDebugLog.write(
            "RoomPlan architecture type=\(surface.kind.debugName) "
                + "measured=(\(measured.x),\(measured.y),\(measured.z)) "
                + "capturedPosition=(\(capturedPosition.x),\(capturedPosition.y),\(capturedPosition.z)) "
                + "renderedPosition=(\(renderedPosition.x),\(renderedPosition.y),\(renderedPosition.z)) "
                + "rotation=(x:\(rotation.imag.x),y:\(rotation.imag.y),z:\(rotation.imag.z),w:\(rotation.real)) "
                + "mesh=(\(generatedDimensions.x),\(generatedDimensions.y),\(generatedDimensions.z)) "
                + "strategy=\(strategy)"
        )
    }

    private static func addBox(
        to root: Entity,
        size: SIMD3<Float>,
        position: SIMD3<Float> = .zero,
        material: PhysicallyBasedMaterial
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

private extension RoomPlanSurfaceKind {
    var debugName: String {
        switch self {
        case .wall: "wall"
        case .door(let isOpen): isOpen ? "door(open)" : "door(closed)"
        case .window: "window"
        case .opening: "opening"
        case .floor: "floor"
        }
    }
}
