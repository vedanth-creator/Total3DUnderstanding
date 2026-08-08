import RealityKit
import UIKit

@MainActor
enum RoomPlanMaterialLibrary {
    static let paintedWall = material(
        color: UIColor(red: 0.89, green: 0.88, blue: 0.84, alpha: 1),
        roughness: 0.86
    )
    static let lightWood = material(
        color: UIColor(red: 0.63, green: 0.48, blue: 0.34, alpha: 1),
        roughness: 0.68
    )
    static let darkWood = material(
        color: UIColor(red: 0.32, green: 0.23, blue: 0.17, alpha: 1),
        roughness: 0.72
    )
    static let upholstery = material(
        color: UIColor(red: 0.42, green: 0.47, blue: 0.45, alpha: 1),
        roughness: 0.92
    )
    static let upholsteryAccent = material(
        color: UIColor(red: 0.34, green: 0.39, blue: 0.38, alpha: 1),
        roughness: 0.94
    )
    static let warmMetal = material(
        color: UIColor(red: 0.43, green: 0.39, blue: 0.32, alpha: 1),
        roughness: 0.38,
        metallic: 0.72
    )
    static let darkMetal = material(
        color: UIColor(red: 0.14, green: 0.15, blue: 0.15, alpha: 1),
        roughness: 0.34,
        metallic: 0.8
    )
    static let windowFrame = material(
        color: UIColor(red: 0.78, green: 0.79, blue: 0.77, alpha: 1),
        roughness: 0.48,
        metallic: 0.16
    )
    // An opaque, low-roughness tint is intentionally used instead of transparent
    // glass. It reads as glass while avoiding mobile transparency depth sorting.
    static let stableGlass = material(
        color: UIColor(red: 0.42, green: 0.61, blue: 0.68, alpha: 1),
        roughness: 0.16,
        metallic: 0.08
    )
    static let doorPanel = material(
        color: UIColor(red: 0.49, green: 0.34, blue: 0.23, alpha: 1),
        roughness: 0.68
    )
    static let doorInset = material(
        color: UIColor(red: 0.39, green: 0.27, blue: 0.19, alpha: 1),
        roughness: 0.72
    )
    static let mattress = material(
        color: UIColor(red: 0.88, green: 0.87, blue: 0.82, alpha: 1),
        roughness: 0.96
    )
    static let bedding = material(
        color: UIColor(red: 0.55, green: 0.61, blue: 0.64, alpha: 1),
        roughness: 0.94
    )
    static let screen = material(
        color: UIColor(red: 0.035, green: 0.045, blue: 0.055, alpha: 1),
        roughness: 0.12,
        metallic: 0.18
    )
    static let foliage = material(
        color: UIColor(red: 0.25, green: 0.43, blue: 0.27, alpha: 1),
        roughness: 0.9
    )
    static let foliageAccent = material(
        color: UIColor(red: 0.36, green: 0.53, blue: 0.31, alpha: 1),
        roughness: 0.92
    )
    static let ceramic = material(
        color: UIColor(red: 0.67, green: 0.58, blue: 0.48, alpha: 1),
        roughness: 0.52
    )
    static let lampshade = material(
        color: UIColor(red: 0.86, green: 0.79, blue: 0.65, alpha: 1),
        roughness: 0.84
    )
    static let cabinet = material(
        color: UIColor(red: 0.52, green: 0.45, blue: 0.37, alpha: 1),
        roughness: 0.76
    )
    static let artwork = material(
        color: UIColor(red: 0.45, green: 0.48, blue: 0.53, alpha: 1),
        roughness: 0.82
    )

    static func material(
        color: UIColor,
        roughness: Float,
        metallic: Float = 0
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = color
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)
        return material
    }
}
