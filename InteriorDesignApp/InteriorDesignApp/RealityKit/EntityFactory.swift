import RealityKit
import UIKit

struct FurnitureEntityRecord {
    let root: Entity
    let box: ModelEntity
    let selectionOutline: SelectionOutline
    let label: ModelEntity?
}

struct SelectionOutline {
    let root: Entity
    let xEdges: [ModelEntity]
    let yEdges: [ModelEntity]
    let zEdges: [ModelEntity]
}

@MainActor
enum EntityFactory {
    private static let unitBox = MeshResource.generateBox(
        size: SIMD3<Float>(repeating: 1),
        cornerRadius: 0.035
    )

    static func makeFurniture(_ furniture: FurnitureItem) -> FurnitureEntityRecord {
        let root = Entity()
        root.name = furnitureEntityName(furniture.id)

        let box = ModelEntity(
            mesh: unitBox,
            materials: [furnitureMaterial(hex: furniture.colorHex)]
        )
        box.name = furnitureEntityName(furniture.id)
        box.components.set(
            CollisionComponent(
                shapes: [ShapeResource.generateBox(size: SIMD3<Float>(repeating: 1))]
            )
        )
        if #available(iOS 18.0, *) {
            box.components.set(InputTargetComponent())
        }
        root.addChild(box)

        let selectionOutline = makeSelectionOutline()
        selectionOutline.root.isEnabled = false
        root.addChild(selectionOutline.root)

        let label = makeLabel(furniture.name)
        if let label {
            root.addChild(label)
        }

        return FurnitureEntityRecord(
            root: root,
            box: box,
            selectionOutline: selectionOutline,
            label: label
        )
    }

    static func update(
        _ record: FurnitureEntityRecord,
        from furniture: FurnitureItem,
        roomWidth: Float,
        roomDepth: Float
    ) {
        let dimensions = SIMD3<Float>(
            RoomCoordinateSystem.safeDimension(furniture.width),
            RoomCoordinateSystem.safeDimension(furniture.height),
            RoomCoordinateSystem.safeDimension(furniture.depth)
        )
        let floorPosition = RoomCoordinateSystem.floorPosition(
            for: furniture,
            roomWidth: roomWidth,
            roomDepth: roomDepth
        )

        record.root.position = floorPosition
        record.root.orientation = simd_quatf(
            angle: Float(furniture.rotationDegrees * .pi / 180),
            axis: SIMD3<Float>(0, 1, 0)
        )
        record.box.scale = dimensions
        record.box.position = SIMD3<Float>(0, dimensions.y / 2, 0)
        record.box.model?.materials = [furnitureMaterial(hex: furniture.colorHex)]

        updateSelectionOutline(record.selectionOutline, dimensions: dimensions)
        record.label?.position = SIMD3<Float>(0, dimensions.y + 0.16, 0)
    }

    static func makeRoomSurface(
        name: String,
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        color: UIColor
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: color, roughness: 0.9, isMetallic: false)]
        )
        entity.name = name
        entity.position = position
        entity.components.set(
            CollisionComponent(shapes: [ShapeResource.generateBox(size: size)])
        )
        if #available(iOS 18.0, *) {
            entity.components.set(InputTargetComponent())
        }
        return entity
    }

    static func furnitureID(from entity: Entity) -> UUID? {
        var candidate: Entity? = entity
        while let current = candidate {
            let prefix = "furniture:"
            if current.name.hasPrefix(prefix) {
                return UUID(uuidString: String(current.name.dropFirst(prefix.count)))
            }
            candidate = current.parent
        }
        return nil
    }

    private static func furnitureEntityName(_ id: UUID) -> String {
        "furniture:\(id.uuidString)"
    }

    private static func furnitureMaterial(hex: String) -> SimpleMaterial {
        SimpleMaterial(
            color: UIColor(hex: hex),
            roughness: 0.72,
            isMetallic: false
        )
    }

    private static func selectionMaterial() -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 1.0, green: 0.78, blue: 0.16, alpha: 1.0))
        return material
    }

    private static func makeSelectionOutline() -> SelectionOutline {
        let root = Entity()
        root.name = "selection-outline"

        func makeEdges(count: Int, axis: String) -> [ModelEntity] {
            (0..<count).map { index in
                let edge = ModelEntity(mesh: unitBox, materials: [selectionMaterial()])
                edge.name = "selection-outline:\(axis):\(index)"
                root.addChild(edge)
                return edge
            }
        }

        return SelectionOutline(
            root: root,
            xEdges: makeEdges(count: 4, axis: "x"),
            yEdges: makeEdges(count: 4, axis: "y"),
            zEdges: makeEdges(count: 4, axis: "z")
        )
    }

    private static func updateSelectionOutline(
        _ outline: SelectionOutline,
        dimensions: SIMD3<Float>
    ) {
        // The wireframe sits outside the mesh rather than using a nearly
        // coplanar shell, so depth testing cannot hide the selection state.
        let padding: Float = 0.055
        let thickness: Float = 0.025
        let half = dimensions / 2 + SIMD3<Float>(repeating: padding)
        outline.root.position = SIMD3<Float>(0, dimensions.y / 2, 0)

        let signs: [Float] = [-1, 1]
        var index = 0
        for ySign in signs {
            for zSign in signs {
                let edge = outline.xEdges[index]
                edge.scale = SIMD3<Float>(dimensions.x + padding * 2, thickness, thickness)
                edge.position = SIMD3<Float>(0, ySign * half.y, zSign * half.z)
                index += 1
            }
        }

        index = 0
        for xSign in signs {
            for zSign in signs {
                let edge = outline.yEdges[index]
                edge.scale = SIMD3<Float>(thickness, dimensions.y + padding * 2, thickness)
                edge.position = SIMD3<Float>(xSign * half.x, 0, zSign * half.z)
                index += 1
            }
        }

        index = 0
        for xSign in signs {
            for ySign in signs {
                let edge = outline.zEdges[index]
                edge.scale = SIMD3<Float>(thickness, thickness, dimensions.z + padding * 2)
                edge.position = SIMD3<Float>(xSign * half.x, ySign * half.y, 0)
                index += 1
            }
        }
    }

    private static func makeLabel(_ text: String) -> ModelEntity? {
        guard #available(iOS 18.0, *) else { return nil }
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.004,
            font: .systemFont(ofSize: 0.13, weight: .semibold),
            containerFrame: CGRect(x: -0.9, y: -0.12, width: 1.8, height: 0.24),
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(white: 0.16, alpha: 0.92))
        let label = ModelEntity(mesh: mesh, materials: [material])
        label.name = "furniture-label"
        label.components.set(BillboardComponent())
        return label
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
