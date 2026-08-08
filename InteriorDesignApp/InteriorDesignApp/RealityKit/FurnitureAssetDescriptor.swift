import RealityKit

enum FurnitureAssetSource: Equatable {
    case bundledUSDZ(name: String)
}

enum FurnitureScaleBehavior: Equatable {
    case footprint
    case width
    case height
    case contain
}

enum FurnitureMaterialStyle: Equatable {
    case wood
    case upholstery
    case metal
}

struct FurnitureAssetDescriptor: Equatable {
    let category: String
    let source: FurnitureAssetSource
    let nativeDimensions: SIMD3<Float>
    let scaleBehavior: FurnitureScaleBehavior
    let scaleCorrection: SIMD3<Float>
    let pivotOffset: SIMD3<Float>
    let rotationCorrection: simd_quatf
    let materialOverride: FurnitureMaterialStyle?

    init(
        category: String,
        assetName: String,
        nativeDimensions: SIMD3<Float>,
        scaleBehavior: FurnitureScaleBehavior,
        scaleCorrection: SIMD3<Float> = .one,
        pivotOffset: SIMD3<Float> = .zero,
        rotationCorrection: simd_quatf = .init(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
        materialOverride: FurnitureMaterialStyle? = nil
    ) {
        self.category = category
        source = .bundledUSDZ(name: assetName)
        self.nativeDimensions = nativeDimensions
        self.scaleBehavior = scaleBehavior
        self.scaleCorrection = scaleCorrection
        self.pivotOffset = pivotOffset
        self.rotationCorrection = rotationCorrection
        self.materialOverride = materialOverride
    }

    func fittedScale(for target: SIMD3<Float>) -> SIMD3<Float> {
        let safeNative = SIMD3<Float>(
            max(nativeDimensions.x, 0.001),
            max(nativeDimensions.y, 0.001),
            max(nativeDimensions.z, 0.001)
        )
        let ratios = target / safeNative
        let uniform: Float
        switch scaleBehavior {
        case .footprint:
            uniform = min(ratios.x, ratios.z)
        case .width:
            uniform = ratios.x
        case .height:
            uniform = ratios.y
        case .contain:
            uniform = min(ratios.x, min(ratios.y, ratios.z))
        }
        return SIMD3<Float>(repeating: max(uniform, 0.001)) * scaleCorrection
    }
}
