import Foundation

protocol RoomDesignProviding {
    func createScene(for room: SampleRoom) async throws -> RoomScene
}

struct MockRoomDesignService: RoomDesignProviding {
    func createScene(for room: SampleRoom) async throws -> RoomScene {
        SampleData.scene(for: room)
    }
}

