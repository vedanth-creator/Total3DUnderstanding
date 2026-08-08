import Foundation
import RealityKit

@MainActor
final class FurnitureAssetLibrary {
    static let shared = FurnitureAssetLibrary()

    private var prototypeCache: [String: Entity] = [:]
    private var failedAssetNames: Set<String> = []

    private let descriptors: [String: FurnitureAssetDescriptor] = [
        "chair": FurnitureAssetDescriptor(
            category: "Chair",
            assetName: "GenericChair",
            nativeDimensions: SIMD3<Float>(0.62, 0.9, 0.62),
            scaleBehavior: .contain
        ),
        "sofa": FurnitureAssetDescriptor(
            category: "Sofa",
            assetName: "GenericSofa",
            nativeDimensions: SIMD3<Float>(2.0, 0.9, 0.88),
            scaleBehavior: .footprint
        ),
        "table": FurnitureAssetDescriptor(
            category: "Table",
            assetName: "GenericTable",
            nativeDimensions: SIMD3<Float>(1.4, 0.76, 0.82),
            scaleBehavior: .footprint
        ),
        "bed": FurnitureAssetDescriptor(
            category: "Bed",
            assetName: "GenericBed",
            nativeDimensions: SIMD3<Float>(1.6, 0.7, 2.05),
            scaleBehavior: .footprint
        ),
        "storage": FurnitureAssetDescriptor(
            category: "Storage",
            assetName: "GenericStorage",
            nativeDimensions: SIMD3<Float>(1.2, 1.8, 0.5),
            scaleBehavior: .contain
        ),
        "television": FurnitureAssetDescriptor(
            category: "Television",
            assetName: "GenericTelevision",
            nativeDimensions: SIMD3<Float>(1.25, 0.82, 0.28),
            scaleBehavior: .width
        ),
        "lamp": FurnitureAssetDescriptor(
            category: "Lamp",
            assetName: "GenericLamp",
            nativeDimensions: SIMD3<Float>(0.4, 1.45, 0.4),
            scaleBehavior: .height
        ),
        "plant": FurnitureAssetDescriptor(
            category: "Plant",
            assetName: "GenericPlant",
            nativeDimensions: SIMD3<Float>(0.6, 1.05, 0.6),
            scaleBehavior: .height
        ),
        "wall art": FurnitureAssetDescriptor(
            category: "Wall Art",
            assetName: "GenericWallArt",
            nativeDimensions: SIMD3<Float>(1.0, 0.72, 0.08),
            scaleBehavior: .width
        )
    ]

    private init() {}

    func makeVisual(category: String, dimensions: SIMD3<Float>) -> Entity {
        let key = category.lowercased()
        if let descriptor = descriptors[key], let loaded = loadAsset(descriptor) {
            configure(loaded, descriptor: descriptor, dimensions: dimensions)
            loaded.name = "furniture-asset:\(descriptor.category)"
            return loaded
        }

        let fallback = makeProceduralVisual(category: category, dimensions: dimensions)
        fallback.name = "furniture-procedural:\(category)"
        return fallback
    }

    private func loadAsset(_ descriptor: FurnitureAssetDescriptor) -> Entity? {
        guard case .bundledUSDZ(let assetName) = descriptor.source else { return nil }
        if let prototype = prototypeCache[assetName] {
            return prototype.clone(recursive: true)
        }
        guard !failedAssetNames.contains(assetName) else { return nil }

        guard Bundle.main.url(forResource: assetName, withExtension: "usdz") != nil else {
            failedAssetNames.insert(assetName)
            AppDebugLog.write(
                "Furniture asset missing; asset=\(assetName).usdz category=\(descriptor.category) using procedural fallback"
            )
            return nil
        }

        do {
            let prototype = try Entity.load(named: assetName, in: .main)
            stripCollisionComponents(from: prototype)
            prototypeCache[assetName] = prototype
            AppDebugLog.write(
                "Furniture asset loaded and cached; asset=\(assetName).usdz category=\(descriptor.category)"
            )
            return prototype.clone(recursive: true)
        } catch {
            failedAssetNames.insert(assetName)
            AppDebugLog.write(
                "Furniture asset load failed; asset=\(assetName).usdz category=\(descriptor.category) error=\(error.localizedDescription) using procedural fallback"
            )
            return nil
        }
    }

    private func configure(
        _ entity: Entity,
        descriptor: FurnitureAssetDescriptor,
        dimensions: SIMD3<Float>
    ) {
        let fittedScale = descriptor.fittedScale(for: dimensions)
        entity.scale = fittedScale
        entity.orientation = descriptor.rotationCorrection
        entity.position = descriptor.pivotOffset * fittedScale
        stripCollisionComponents(from: entity)
        if let style = descriptor.materialOverride {
            applyMaterialOverride(style, to: entity)
        }
    }

    private func stripCollisionComponents(from entity: Entity) {
        entity.components.remove(CollisionComponent.self)
        entity.children.forEach(stripCollisionComponents)
    }

    private func applyMaterialOverride(_ style: FurnitureMaterialStyle, to entity: Entity) {
        if let modelEntity = entity as? ModelEntity, var model = modelEntity.model {
            switch style {
            case .wood:
                model.materials = [RoomPlanMaterialLibrary.lightWood]
            case .upholstery:
                model.materials = [RoomPlanMaterialLibrary.upholstery]
            case .metal:
                model.materials = [RoomPlanMaterialLibrary.darkMetal]
            }
            modelEntity.model = model
        }
        entity.children.forEach { applyMaterialOverride(style, to: $0) }
    }

    private func makeProceduralVisual(
        category: String,
        dimensions rawDimensions: SIMD3<Float>
    ) -> Entity {
        let d = SIMD3<Float>(
            max(rawDimensions.x, 0.08),
            max(rawDimensions.y, 0.08),
            max(rawDimensions.z, 0.08)
        )
        let root = Entity()

        switch category.lowercased() {
        case "chair":
            makeChair(in: root, d: d)
        case "sofa":
            makeSofa(in: root, d: d)
        case "table":
            makeTable(in: root, d: d)
        case "bed":
            makeBed(in: root, d: d)
        case "storage":
            makeStorage(in: root, d: d)
        case "television":
            makeTelevision(in: root, d: d)
        case "lamp":
            makeLamp(in: root, d: d)
        case "plant":
            makePlant(in: root, d: d)
        case "wall art":
            makeWallArt(in: root, d: d)
        default:
            addBox(
                to: root,
                size: d * SIMD3<Float>(0.94, 0.94, 0.94),
                material: RoomPlanMaterialLibrary.cabinet
            )
        }
        return root
    }

    private func makeChair(in root: Entity, d: SIMD3<Float>) {
        let seatY = -d.y * 0.12
        addBox(
            to: root,
            size: SIMD3<Float>(d.x * 0.86, d.y * 0.15, d.z * 0.82),
            position: SIMD3<Float>(0, seatY, 0),
            material: RoomPlanMaterialLibrary.upholstery
        )
        addBox(
            to: root,
            size: SIMD3<Float>(d.x * 0.82, d.y * 0.48, d.z * 0.11),
            position: SIMD3<Float>(0, d.y * 0.22, -d.z * 0.37),
            material: RoomPlanMaterialLibrary.upholsteryAccent
        )
        addFourLegs(
            to: root,
            dimensions: d,
            height: d.y * 0.39,
            topY: seatY - d.y * 0.075,
            material: RoomPlanMaterialLibrary.darkWood
        )
    }

    private func makeSofa(in root: Entity, d: SIMD3<Float>) {
        addBox(
            to: root,
            size: SIMD3<Float>(d.x * 0.96, d.y * 0.30, d.z * 0.82),
            position: SIMD3<Float>(0, -d.y * 0.26, 0),
            material: RoomPlanMaterialLibrary.upholsteryAccent
        )
        addBox(
            to: root,
            size: SIMD3<Float>(d.x * 0.92, d.y * 0.52, d.z * 0.15),
            position: SIMD3<Float>(0, d.y * 0.18, -d.z * 0.39),
            material: RoomPlanMaterialLibrary.upholstery
        )
        let cushionCount = d.x > 1.5 ? 3 : 2
        let cushionWidth = d.x * 0.76 / Float(cushionCount)
        for index in 0..<cushionCount {
            let x = (Float(index) - Float(cushionCount - 1) / 2) * cushionWidth
            addBox(
                to: root,
                size: SIMD3<Float>(cushionWidth * 0.92, d.y * 0.16, d.z * 0.58),
                position: SIMD3<Float>(x, -d.y * 0.05, d.z * 0.06),
                material: RoomPlanMaterialLibrary.upholstery
            )
        }
        for x: Float in [-d.x * 0.44, d.x * 0.44] {
            addBox(
                to: root,
                size: SIMD3<Float>(d.x * 0.10, d.y * 0.46, d.z * 0.76),
                position: SIMD3<Float>(x, -d.y * 0.02, 0),
                material: RoomPlanMaterialLibrary.upholsteryAccent
            )
        }
    }

    private func makeTable(in root: Entity, d: SIMD3<Float>) {
        let topY = d.y * 0.43
        addBox(
            to: root,
            size: SIMD3<Float>(d.x, max(d.y * 0.10, 0.055), d.z),
            position: SIMD3<Float>(0, topY, 0),
            material: RoomPlanMaterialLibrary.lightWood
        )
        addFourLegs(
            to: root,
            dimensions: d,
            height: d.y * 0.84,
            topY: topY - d.y * 0.05,
            material: RoomPlanMaterialLibrary.darkWood
        )
    }

    private func makeBed(in root: Entity, d: SIMD3<Float>) {
        addBox(
            to: root,
            size: SIMD3<Float>(d.x, d.y * 0.18, d.z * 0.94),
            position: SIMD3<Float>(0, -d.y * 0.35, d.z * 0.02),
            material: RoomPlanMaterialLibrary.darkWood
        )
        addBox(
            to: root,
            size: SIMD3<Float>(d.x * 0.96, d.y * 0.32, d.z * 0.88),
            position: SIMD3<Float>(0, -d.y * 0.14, d.z * 0.03),
            material: RoomPlanMaterialLibrary.mattress
        )
        addBox(
            to: root,
            size: SIMD3<Float>(d.x * 0.94, d.y * 0.08, d.z * 0.58),
            position: SIMD3<Float>(0, d.y * 0.08, d.z * 0.14),
            material: RoomPlanMaterialLibrary.bedding
        )
        addBox(
            to: root,
            size: SIMD3<Float>(d.x, d.y * 0.88, d.z * 0.08),
            position: SIMD3<Float>(0, d.y * 0.04, -d.z * 0.46),
            material: RoomPlanMaterialLibrary.darkWood
        )
        for x: Float in [-d.x * 0.24, d.x * 0.24] {
            addBox(
                to: root,
                size: SIMD3<Float>(d.x * 0.40, d.y * 0.13, d.z * 0.20),
                position: SIMD3<Float>(x, d.y * 0.14, -d.z * 0.30),
                material: RoomPlanMaterialLibrary.mattress
            )
        }
    }

    private func makeStorage(in root: Entity, d: SIMD3<Float>) {
        addBox(
            to: root,
            size: d * SIMD3<Float>(0.98, 0.96, 0.94),
            material: RoomPlanMaterialLibrary.cabinet
        )
        let drawerCount = d.y > 1.2 ? 4 : 3
        let drawerHeight = d.y * 0.72 / Float(drawerCount)
        for index in 0..<drawerCount {
            let y = -d.y * 0.29 + (Float(index) + 0.5) * drawerHeight
            addBox(
                to: root,
                size: SIMD3<Float>(d.x * 0.86, drawerHeight * 0.84, max(d.z * 0.035, 0.012)),
                position: SIMD3<Float>(0, y, d.z * 0.48),
                material: RoomPlanMaterialLibrary.darkWood
            )
            addBox(
                to: root,
                size: SIMD3<Float>(d.x * 0.15, max(d.y * 0.018, 0.012), max(d.z * 0.045, 0.015)),
                position: SIMD3<Float>(0, y, d.z * 0.51),
                material: RoomPlanMaterialLibrary.warmMetal
            )
        }
    }

    private func makeTelevision(in root: Entity, d: SIMD3<Float>) {
        addBox(
            to: root,
            size: SIMD3<Float>(d.x, d.y * 0.78, max(d.z * 0.20, 0.035)),
            position: SIMD3<Float>(0, d.y * 0.08, 0),
            material: RoomPlanMaterialLibrary.darkMetal
        )
        addBox(
            to: root,
            size: SIMD3<Float>(d.x * 0.93, d.y * 0.68, max(d.z * 0.215, 0.038)),
            position: SIMD3<Float>(0, d.y * 0.08, d.z * 0.005),
            material: RoomPlanMaterialLibrary.screen
        )
        addBox(
            to: root,
            size: SIMD3<Float>(d.x * 0.06, d.y * 0.18, d.z * 0.18),
            position: SIMD3<Float>(0, -d.y * 0.36, 0),
            material: RoomPlanMaterialLibrary.darkMetal
        )
        addBox(
            to: root,
            size: SIMD3<Float>(d.x * 0.42, max(d.y * 0.055, 0.025), d.z * 0.78),
            position: SIMD3<Float>(0, -d.y * 0.46, 0),
            material: RoomPlanMaterialLibrary.darkMetal
        )
    }

    private func makeLamp(in root: Entity, d: SIMD3<Float>) {
        addCylinder(
            to: root,
            height: max(d.y * 0.05, 0.035),
            radius: max(min(d.x, d.z) * 0.34, 0.04),
            position: SIMD3<Float>(0, -d.y * 0.47, 0),
            material: RoomPlanMaterialLibrary.warmMetal
        )
        addCylinder(
            to: root,
            height: d.y * 0.68,
            radius: max(min(d.x, d.z) * 0.045, 0.014),
            position: SIMD3<Float>(0, -d.y * 0.11, 0),
            material: RoomPlanMaterialLibrary.darkMetal
        )
        addCone(
            to: root,
            height: d.y * 0.27,
            radius: max(min(d.x, d.z) * 0.48, 0.05),
            position: SIMD3<Float>(0, d.y * 0.34, 0),
            material: RoomPlanMaterialLibrary.lampshade
        )
    }

    private func makePlant(in root: Entity, d: SIMD3<Float>) {
        addCylinder(
            to: root,
            height: d.y * 0.32,
            radius: min(d.x, d.z) * 0.28,
            position: SIMD3<Float>(0, -d.y * 0.34, 0),
            material: RoomPlanMaterialLibrary.ceramic
        )
        addCylinder(
            to: root,
            height: d.y * 0.38,
            radius: max(min(d.x, d.z) * 0.035, 0.012),
            position: SIMD3<Float>(0, -d.y * 0.03, 0),
            material: RoomPlanMaterialLibrary.darkWood
        )
        let leafRadius = max(min(d.x, d.z) * 0.23, 0.04)
        let positions = [
            SIMD3<Float>(0, d.y * 0.30, 0),
            SIMD3<Float>(-d.x * 0.20, d.y * 0.17, 0),
            SIMD3<Float>(d.x * 0.20, d.y * 0.20, d.z * 0.05),
            SIMD3<Float>(0, d.y * 0.10, -d.z * 0.19),
            SIMD3<Float>(0, d.y * 0.18, d.z * 0.20)
        ]
        for (index, position) in positions.enumerated() {
            addSphere(
                to: root,
                radius: leafRadius * (index == 0 ? 1.08 : 0.88),
                position: position,
                material: index.isMultiple(of: 2)
                    ? RoomPlanMaterialLibrary.foliage
                    : RoomPlanMaterialLibrary.foliageAccent
            )
        }
    }

    private func makeWallArt(in root: Entity, d: SIMD3<Float>) {
        addBox(
            to: root,
            size: d,
            material: RoomPlanMaterialLibrary.darkWood
        )
        addBox(
            to: root,
            size: SIMD3<Float>(d.x * 0.88, d.y * 0.82, d.z * 1.06),
            position: SIMD3<Float>(0, 0, d.z * 0.04),
            material: RoomPlanMaterialLibrary.artwork
        )
        addBox(
            to: root,
            size: SIMD3<Float>(d.x * 0.55, d.y * 0.06, d.z * 1.08),
            position: SIMD3<Float>(-d.x * 0.10, d.y * 0.12, d.z * 0.06),
            material: RoomPlanMaterialLibrary.lampshade
        )
    }

    private func addFourLegs(
        to root: Entity,
        dimensions d: SIMD3<Float>,
        height: Float,
        topY: Float,
        material: PhysicallyBasedMaterial
    ) {
        let legWidth = max(min(d.x, d.z) * 0.07, 0.028)
        let legSize = SIMD3<Float>(legWidth, max(height, 0.04), legWidth)
        let y = topY - legSize.y / 2
        for x: Float in [-d.x * 0.38, d.x * 0.38] {
            for z: Float in [-d.z * 0.36, d.z * 0.36] {
                addBox(
                    to: root,
                    size: legSize,
                    position: SIMD3<Float>(x, y, z),
                    material: material
                )
            }
        }
    }

    private func addBox(
        to root: Entity,
        size rawSize: SIMD3<Float>,
        position: SIMD3<Float> = .zero,
        material: PhysicallyBasedMaterial
    ) {
        let size = SIMD3<Float>(
            max(rawSize.x, 0.008),
            max(rawSize.y, 0.008),
            max(rawSize.z, 0.008)
        )
        let entity = ModelEntity(
            mesh: .generateBox(
                size: size,
                cornerRadius: min(min(size.x, size.y), size.z) * 0.08
            ),
            materials: [material]
        )
        entity.position = position
        root.addChild(entity)
    }

    private func addCylinder(
        to root: Entity,
        height: Float,
        radius: Float,
        position: SIMD3<Float>,
        material: PhysicallyBasedMaterial
    ) {
        let safeHeight = max(height, 0.008)
        let safeRadius = max(radius, 0.006)
        let mesh: MeshResource
        if #available(iOS 18.0, *) {
            mesh = .generateCylinder(height: safeHeight, radius: safeRadius)
        } else {
            // RealityKit does not expose procedural cylinders on iOS 17.
            // A compact rounded column keeps the same footprint and height.
            mesh = .generateBox(
                size: SIMD3<Float>(safeRadius * 2, safeHeight, safeRadius * 2),
                cornerRadius: safeRadius * 0.35
            )
        }
        let entity = ModelEntity(
            mesh: mesh,
            materials: [material]
        )
        entity.position = position
        root.addChild(entity)
    }

    private func addCone(
        to root: Entity,
        height: Float,
        radius: Float,
        position: SIMD3<Float>,
        material: PhysicallyBasedMaterial
    ) {
        let safeHeight = max(height, 0.008)
        let safeRadius = max(radius, 0.006)
        let mesh: MeshResource
        if #available(iOS 18.0, *) {
            mesh = .generateCone(height: safeHeight, radius: safeRadius)
        } else {
            // Preserve a lampshade-like tapered silhouette approximately on
            // iOS 17 without introducing custom mesh generation.
            mesh = .generateBox(
                size: SIMD3<Float>(safeRadius * 2, safeHeight, safeRadius * 2),
                cornerRadius: safeRadius * 0.18
            )
        }
        let entity = ModelEntity(
            mesh: mesh,
            materials: [material]
        )
        entity.position = position
        root.addChild(entity)
    }

    private func addSphere(
        to root: Entity,
        radius: Float,
        position: SIMD3<Float>,
        material: PhysicallyBasedMaterial
    ) {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: max(radius, 0.006)),
            materials: [material]
        )
        entity.position = position
        root.addChild(entity)
    }
}
