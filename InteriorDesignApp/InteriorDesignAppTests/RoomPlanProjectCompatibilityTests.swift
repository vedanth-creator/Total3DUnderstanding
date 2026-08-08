import RoomPlan
import XCTest
@testable import InteriorDesignApp

final class RoomPlanProjectCompatibilityTests: XCTestCase {
    func testProjectSavedBeforeWorldMapReferenceFieldStillDecodes() throws {
        let roomID = UUID(uuidString: "73C0D814-6AE1-488F-98A2-7F22A64CF3AD")!
        let capturedRoom = try makeEmptyCapturedRoom(identifier: roomID)
        let currentProject = RoomPlanProject(capturedRoom: capturedRoom, archivedWorldMap: Data([1, 2, 3]))
        let encoded = try JSONEncoder().encode(currentProject)
        var legacyPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyPayload.removeValue(forKey: "worldMapReferenceID")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyPayload)

        let decoded = try JSONDecoder().decode(RoomPlanProject.self, from: legacyData)

        XCTAssertEqual(decoded.id, currentProject.id)
        XCTAssertNil(decoded.worldMapReferenceID)
        XCTAssertEqual(decoded.effectiveWorldMapReferenceID, decoded.id)
        XCTAssertEqual(decoded.archivedWorldMap, Data([1, 2, 3]))
    }

    func testNewProjectPersistsStableProjectAndWorldMapIdentifiers() throws {
        let roomID = UUID(uuidString: "48E0C17D-139E-4943-A997-87D57FDEB19B")!
        let project = RoomPlanProject(
            capturedRoom: try makeEmptyCapturedRoom(identifier: roomID),
            archivedWorldMap: Data([4, 5, 6])
        )

        let decoded = try JSONDecoder().decode(
            RoomPlanProject.self,
            from: JSONEncoder().encode(project)
        )

        XCTAssertEqual(decoded.id, project.id)
        XCTAssertEqual(decoded.worldMapReferenceID, project.worldMapReferenceID)
        XCTAssertEqual(decoded.effectiveWorldMapReferenceID, project.worldMapReferenceID)
        XCTAssertNotNil(decoded.worldMapReferenceID)
    }

    private func makeEmptyCapturedRoom(identifier: UUID) throws -> CapturedRoom {
        let payload: [String: Any] = [
            "identifier": identifier.uuidString,
            "walls": [],
            "doors": [],
            "windows": [],
            "openings": [],
            "floors": [],
            "objects": [],
            "sections": [],
            "story": 0,
            "version": 1
        ]
        return try JSONDecoder().decode(
            CapturedRoom.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
    }
}
