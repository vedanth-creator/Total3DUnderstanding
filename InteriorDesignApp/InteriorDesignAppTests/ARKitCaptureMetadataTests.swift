import XCTest
import simd
@testable import InteriorDesignApp

final class ARKitCaptureMetadataTests: XCTestCase {
    func testMetadataJSONRoundTripPreservesRelationshipsAndPTS() throws {
        let projectID = UUID(uuidString: "3C462F14-7447-4AC2-93D9-8931AF3C4EF3")!
        let captureID = UUID(uuidString: "F0632464-C192-42DE-B525-186668529216")!
        let worldMapID = UUID(uuidString: "86BDBED5-E27A-4A9D-9A1E-E45587F4A58A")!
        let videoID = UUID(uuidString: "C54CA141-C222-45DE-A48F-6AA01966968B")!
        let frameID = UUID(uuidString: "C1771054-115A-47D0-A479-F10D3073B89B")!
        let pts = try VideoPresentationTime(value: 1001, timescale: 600)
        let frame = ARKitFrameMetadata(
            id: frameID,
            sampleIndex: 42,
            sourcePTS: pts,
            arFrameTimestampSeconds: 49_102.25,
            cameraToWorld: CodableMatrix4x4(matrix_identity_float4x4),
            cameraIntrinsics: CodableMatrix3x3(simd_float3x3(diagonal: SIMD3<Float>(1_450, 1_450, 1))),
            intrinsicsImageResolution: CaptureImageResolution(width: 1920, height: 1080),
            imageGeometry: CaptureImageGeometry(orientation: .portrait, isMirrored: false, crop: nil),
            trackingState: .normal,
            worldMappingStatus: .mapped,
            isUsableForAlignment: true
        )
        let metadata = ARKitCaptureMetadata(
            captureID: captureID,
            roomPlanProjectID: projectID,
            worldMapReference: ARWorldMapReference(identifier: worldMapID, archiveRelativePath: nil),
            video: AppearanceVideoReference(
                identifier: videoID,
                fileName: "room-scan.mov",
                resolution: CaptureImageResolution(width: 1920, height: 1080),
                imageGeometry: CaptureImageGeometry(orientation: .portrait, isMirrored: false, crop: nil)
            ),
            frames: [frame]
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(ARKitCaptureMetadata.self, from: data)

        XCTAssertEqual(decoded, metadata)
        XCTAssertEqual(decoded.captureID, captureID)
        XCTAssertEqual(decoded.roomPlanProjectID, projectID)
        XCTAssertEqual(decoded.worldMapReference.identifier, worldMapID)
        XCTAssertEqual(decoded.video.identifier, videoID)
        XCTAssertEqual(decoded.frames[0].id, frameID)
        XCTAssertEqual(decoded.frames[0].sourcePTS.value, 1001)
        XCTAssertEqual(decoded.frames[0].sourcePTS.timescale, 600)
    }

    func testFourByFourMatrixRoundTripUsesMathematicalRows() throws {
        let rows: [[Float]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]
        let value = try CodableMatrix4x4(rows: rows)
        let reconstructed = CodableMatrix4x4(value.simdMatrix)

        XCTAssertEqual(reconstructed.rows, rows)
        XCTAssertEqual(value.simdMatrix.columns.3, SIMD4<Float>(4, 8, 12, 16))
    }

    func testThreeByThreeIntrinsicsRoundTripUsesMathematicalRows() throws {
        let rows: [[Float]] = [
            [1_450, 0, 960],
            [0, 1_445, 540],
            [0, 0, 1]
        ]
        let value = try CodableMatrix3x3(rows: rows)
        let reconstructed = CodableMatrix3x3(value.simdMatrix)

        XCTAssertEqual(reconstructed.rows, rows)
        XCTAssertEqual(value.simdMatrix.columns.2, SIMD3<Float>(960, 540, 1))
    }

    func testMalformedMatrixDimensionsAreRejectedByInitializerAndDecoder() throws {
        XCTAssertThrowsError(try CodableMatrix4x4(rows: [[1, 2], [3, 4]]))
        XCTAssertThrowsError(try JSONDecoder().decode(CodableMatrix3x3.self, from: Data("[[1,2],[3,4]]".utf8)))
    }

    func testNonpositivePTSTimescaleIsRejected() {
        XCTAssertThrowsError(try VideoPresentationTime(value: 1, timescale: 0))
    }
}
