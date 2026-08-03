import Foundation

enum BackendRoomScanStatus: String, Decodable {
    case queued
    case processing
    case completed
    case failed
}

struct RoomScanAcceptedResponse: Decodable {
    let jobID: UUID
    let status: BackendRoomScanStatus
    let createdAt: String
    let statusURL: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
        case createdAt = "created_at"
        case statusURL = "status_url"
    }
}

struct RoomScanJobResponse: Decodable {
    let jobID: UUID
    let status: BackendRoomScanStatus
    let progress: Double
    let stage: String
    let error: String?

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
        case progress
        case stage
        case error
    }
}

struct BackendSceneResponse: Decodable {
    let schemaVersion: String
    let image: BackendImageInfo
    let coordinateSystem: BackendCoordinateSystem
    let camera: BackendCamera
    let roomLayout: BackendRoomLayout
    let objects: [BackendDetectedObject]
    let timing: BackendTiming
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case image
        case coordinateSystem = "coordinate_system"
        case camera
        case roomLayout = "room_layout"
        case objects
        case timing
        case warnings
    }
}

struct BackendImageInfo: Decodable {
    let width: Int
    let height: Int
}

struct BackendCoordinateSystem: Decodable {
    let name: String
    let units: String
    let handedness: String?
    let axisConvention: String?

    enum CodingKeys: String, CodingKey {
        case name
        case units
        case handedness
        case axisConvention = "axis_convention"
    }
}

struct BackendCamera: Decodable {
    let intrinsics: [[Double]]
    let rotation: [[Double]]
    let pitchRadians: Double
    let rollRadians: Double
    let confidence: BackendCameraConfidence

    enum CodingKeys: String, CodingKey {
        case intrinsics
        case rotation
        case pitchRadians = "pitch_radians"
        case rollRadians = "roll_radians"
        case confidence
    }
}

struct BackendCameraConfidence: Decodable {
    let pitchBinProbability: Double?
    let rollBinProbability: Double?

    enum CodingKeys: String, CodingKey {
        case pitchBinProbability = "pitch_bin_probability"
        case rollBinProbability = "roll_bin_probability"
    }
}

struct BackendRoomLayout: Decodable {
    let corners: [[Double]]
    let centroid: [Double]
    let basis: [[Double]]
    let halfSizes: [Double]
    let confidence: BackendLayoutConfidence

    enum CodingKeys: String, CodingKey {
        case corners
        case centroid
        case basis
        case halfSizes = "half_sizes"
        case confidence
    }
}

struct BackendLayoutConfidence: Decodable {
    let orientationBinProbability: Double?

    enum CodingKeys: String, CodingKey {
        case orientationBinProbability = "orientation_bin_probability"
    }
}

struct BackendDetectedObject: Decodable {
    let id: String
    let category: BackendObjectCategory
    let confidence: BackendObjectConfidence
    let boundingBox2D: BackendBoundingBox2D
    let boundingBox3D: BackendBoundingBox3D
    let mesh: BackendMeshReference

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case confidence
        case boundingBox2D = "bounding_box_2d"
        case boundingBox3D = "bounding_box_3d"
        case mesh
    }
}

struct BackendObjectCategory: Decodable {
    let name: String
    let nyu40ID: Int?
    let pix3dID: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case nyu40ID = "nyu40_id"
        case pix3dID = "pix3d_id"
    }
}

struct BackendObjectConfidence: Decodable {
    let detectorCategoryProbability: Double
    let orientationBinProbability: Double?
    let depthBinProbability: Double?

    enum CodingKeys: String, CodingKey {
        case detectorCategoryProbability = "detector_category_probability"
        case orientationBinProbability = "orientation_bin_probability"
        case depthBinProbability = "depth_bin_probability"
    }
}

struct BackendBoundingBox2D: Decodable {
    let xyxy: [Double]
}

struct BackendBoundingBox3D: Decodable {
    let corners: [[Double]]
    let centroid: [Double]
    let basis: [[Double]]
    let halfSizes: [Double]

    enum CodingKeys: String, CodingKey {
        case corners
        case centroid
        case basis
        case halfSizes = "half_sizes"
    }
}

struct BackendMeshReference: Decodable {
    let uri: String
    let mediaType: String
    let coordinateFrame: String?

    enum CodingKeys: String, CodingKey {
        case uri
        case mediaType = "media_type"
        case coordinateFrame = "coordinate_frame"
    }
}

struct BackendTiming: Decodable {
    let detectionMilliseconds: Double?
    let total3DMilliseconds: Double?
    let totalMilliseconds: Double?

    enum CodingKeys: String, CodingKey {
        case detectionMilliseconds = "detection_ms"
        case total3DMilliseconds = "total3d_ms"
        case totalMilliseconds = "total_ms"
    }
}
