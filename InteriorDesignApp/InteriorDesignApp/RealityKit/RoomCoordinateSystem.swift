import Foundation
import simd

enum RoomCoordinateSystem {
    static let wallThickness: Float = 0.10
    static let floorThickness: Float = 0.08
    static let minimumFurnitureDimension: Float = 0.05
    static let maximumFurnitureDimension: Float = 8.0

    static func safeDimension(_ value: Double, fallback: Float = 0.5) -> Float {
        guard value.isFinite else { return fallback }
        return min(
            max(Float(value), minimumFurnitureDimension),
            maximumFurnitureDimension
        )
    }

    static func safeRoomDimension(_ value: Double, fallback: Float) -> Float {
        guard value.isFinite, value > 0 else { return fallback }
        return min(max(Float(value), 1.0), 20.0)
    }

    /// Scene convention: X is left/right, Y is vertical, and Z is front/back.
    /// The origin is the center of the floor. Positive Z points toward the open
    /// front of the room, and furniture model positions are floor-relative.
    static func floorPosition(
        for furniture: FurnitureItem,
        roomWidth: Float,
        roomDepth: Float
    ) -> SIMD3<Float> {
        let normalizedX = clampedNormalized(furniture.normalizedX)
        let normalizedZ = clampedNormalized(furniture.normalizedY)
        return SIMD3<Float>(
            (Float(normalizedX) - 0.5) * roomWidth,
            0,
            (Float(normalizedZ) - 0.5) * roomDepth
        )
    }

    private static func clampedNormalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }
}

