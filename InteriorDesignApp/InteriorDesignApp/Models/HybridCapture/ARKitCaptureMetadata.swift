import Foundation
import simd

/// A JSON matrix encoded as four rows of four values: `rows[row][column]`.
///
/// SIMD matrices use column-major storage internally. The conversion helpers
/// below preserve mathematical row/column meaning across that storage boundary.
struct CodableMatrix4x4: Codable, Equatable {
    let rows: [[Float]]

    init(_ matrix: simd_float4x4) {
        rows = (0..<4).map { row in
            (0..<4).map { column in matrix[column][row] }
        }
    }

    init(rows: [[Float]]) throws {
        try Self.validate(rows)
        self.rows = rows
    }

    var simdMatrix: simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(rows[0][0], rows[1][0], rows[2][0], rows[3][0]),
            SIMD4<Float>(rows[0][1], rows[1][1], rows[2][1], rows[3][1]),
            SIMD4<Float>(rows[0][2], rows[1][2], rows[2][2], rows[3][2]),
            SIMD4<Float>(rows[0][3], rows[1][3], rows[2][3], rows[3][3])
        ))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decodedRows = try container.decode([[Float]].self)
        try Self.validate(decodedRows)
        rows = decodedRows
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rows)
    }

    private static func validate(_ rows: [[Float]]) throws {
        guard rows.count == 4, rows.allSatisfy({ $0.count == 4 }) else {
            throw MatrixCodingError.invalidDimensions(expected: "4x4")
        }
        guard rows.joined().allSatisfy(\.isFinite) else {
            throw MatrixCodingError.nonFiniteValue
        }
    }
}

/// A JSON matrix encoded as three rows of three values: `rows[row][column]`.
struct CodableMatrix3x3: Codable, Equatable {
    let rows: [[Float]]

    init(_ matrix: simd_float3x3) {
        rows = (0..<3).map { row in
            (0..<3).map { column in matrix[column][row] }
        }
    }

    init(rows: [[Float]]) throws {
        try Self.validate(rows)
        self.rows = rows
    }

    var simdMatrix: simd_float3x3 {
        simd_float3x3(columns: (
            SIMD3<Float>(rows[0][0], rows[1][0], rows[2][0]),
            SIMD3<Float>(rows[0][1], rows[1][1], rows[2][1]),
            SIMD3<Float>(rows[0][2], rows[1][2], rows[2][2])
        ))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decodedRows = try container.decode([[Float]].self)
        try Self.validate(decodedRows)
        rows = decodedRows
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rows)
    }

    private static func validate(_ rows: [[Float]]) throws {
        guard rows.count == 3, rows.allSatisfy({ $0.count == 3 }) else {
            throw MatrixCodingError.invalidDimensions(expected: "3x3")
        }
        guard rows.joined().allSatisfy(\.isFinite) else {
            throw MatrixCodingError.nonFiniteValue
        }
    }
}

enum MatrixCodingError: Error, Equatable {
    case invalidDimensions(expected: String)
    case nonFiniteValue
}

/// Exact encoded-video presentation time. `value / timescale` is seconds.
/// The integer pair, not floating-point seconds, is the synchronization key.
struct VideoPresentationTime: Codable, Hashable {
    let value: Int64
    let timescale: Int32

    init(value: Int64, timescale: Int32) throws {
        guard timescale > 0 else { throw VideoTimingError.invalidTimescale }
        self.value = value
        self.timescale = timescale
    }

    var seconds: Double { Double(value) / Double(timescale) }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(Int64.self, forKey: .value)
        let timescale = try container.decode(Int32.self, forKey: .timescale)
        try self.init(value: value, timescale: timescale)
    }
}

enum VideoTimingError: Error, Equatable {
    case invalidTimescale
}

struct ARKitCoordinateSystem: Codable, Equatable {
    let name: String
    let handedness: String
    let units: String
    let worldUp: String
    let cameraForward: String
    let transformSemantics: String
    let matrixLayout: String

    static let arKitWorld = ARKitCoordinateSystem(
        name: "arkit_world",
        handedness: "right_handed",
        units: "meters",
        worldUp: "+Y",
        cameraForward: "-Z",
        transformSemantics: "camera_to_world",
        matrixLayout: "row_major_nested_arrays_rows_row_column"
    )
}

struct CaptureImageResolution: Codable, Equatable {
    let width: Int
    let height: Int
}

enum CaptureImageOrientation: String, Codable, CaseIterable {
    case portrait
    case portraitUpsideDown = "portrait_upside_down"
    case landscapeLeft = "landscape_left"
    case landscapeRight = "landscape_right"
}

/// A normalized crop in the oriented image, with origin at its top-left.
struct NormalizedImageCrop: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct CaptureImageGeometry: Codable, Equatable {
    let orientation: CaptureImageOrientation
    let isMirrored: Bool
    let crop: NormalizedImageCrop?
}

enum ARKitTrackingState: String, Codable {
    case notAvailable = "not_available"
    case limited
    case normal
}

enum ARKitWorldMappingStatus: String, Codable {
    case notAvailable = "not_available"
    case limited
    case extending
    case mapped
}

struct ARWorldMapReference: Codable, Equatable {
    let identifier: UUID
    let archiveRelativePath: String?
}

struct AppearanceVideoReference: Codable, Equatable {
    let identifier: UUID
    let fileName: String
    let resolution: CaptureImageResolution
    let imageGeometry: CaptureImageGeometry
}

struct ARKitFrameMetadata: Identifiable, Codable, Equatable {
    let id: UUID
    let sampleIndex: Int
    let sourcePTS: VideoPresentationTime
    /// Convenience/debug value only. `sourcePTS` remains authoritative.
    let sourceTimestampSeconds: Double
    let arFrameTimestampSeconds: Double
    let cameraToWorld: CodableMatrix4x4
    let cameraIntrinsics: CodableMatrix3x3
    let intrinsicsImageResolution: CaptureImageResolution
    let imageGeometry: CaptureImageGeometry
    let trackingState: ARKitTrackingState
    let trackingStateReason: String?
    let worldMappingStatus: ARKitWorldMappingStatus
    let isUsableForAlignment: Bool

    init(
        id: UUID = UUID(),
        sampleIndex: Int,
        sourcePTS: VideoPresentationTime,
        sourceTimestampSeconds: Double? = nil,
        arFrameTimestampSeconds: Double,
        cameraToWorld: CodableMatrix4x4,
        cameraIntrinsics: CodableMatrix3x3,
        intrinsicsImageResolution: CaptureImageResolution,
        imageGeometry: CaptureImageGeometry,
        trackingState: ARKitTrackingState,
        trackingStateReason: String? = nil,
        worldMappingStatus: ARKitWorldMappingStatus,
        isUsableForAlignment: Bool
    ) {
        self.id = id
        self.sampleIndex = sampleIndex
        self.sourcePTS = sourcePTS
        self.sourceTimestampSeconds = sourceTimestampSeconds ?? sourcePTS.seconds
        self.arFrameTimestampSeconds = arFrameTimestampSeconds
        self.cameraToWorld = cameraToWorld
        self.cameraIntrinsics = cameraIntrinsics
        self.intrinsicsImageResolution = intrinsicsImageResolution
        self.imageGeometry = imageGeometry
        self.trackingState = trackingState
        self.trackingStateReason = trackingStateReason
        self.worldMappingStatus = worldMappingStatus
        self.isUsableForAlignment = isUsableForAlignment
    }
}

struct ARKitCaptureMetadata: Codable, Equatable {
    static let currentSchemaVersion = "1.0"

    let schemaVersion: String
    let captureID: UUID
    let roomPlanProjectID: UUID
    let coordinateSystem: ARKitCoordinateSystem
    let worldMapReference: ARWorldMapReference
    let video: AppearanceVideoReference
    let frames: [ARKitFrameMetadata]

    init(
        schemaVersion: String = Self.currentSchemaVersion,
        captureID: UUID = UUID(),
        roomPlanProjectID: UUID,
        coordinateSystem: ARKitCoordinateSystem = .arKitWorld,
        worldMapReference: ARWorldMapReference,
        video: AppearanceVideoReference,
        frames: [ARKitFrameMetadata]
    ) {
        self.schemaVersion = schemaVersion
        self.captureID = captureID
        self.roomPlanProjectID = roomPlanProjectID
        self.coordinateSystem = coordinateSystem
        self.worldMapReference = worldMapReference
        self.video = video
        self.frames = frames
    }
}

/// Future backend extraction contract. It deliberately refers to exact source
/// PTS and a metadata sample, rather than deriving time from the JPEG index.
struct ExtractedFrameAssociation: Codable, Equatable {
    let imageFileName: String
    let sourcePTS: VideoPresentationTime
    let arKitMetadataSampleID: UUID
    let arKitMetadataSampleIndex: Int
}

struct FrameExtractionManifest: Codable, Equatable {
    static let currentSchemaVersion = "1.0"

    let schemaVersion: String
    let captureID: UUID
    let frames: [ExtractedFrameAssociation]
}
