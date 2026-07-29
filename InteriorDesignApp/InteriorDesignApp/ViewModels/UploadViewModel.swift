import Foundation

@MainActor
final class UploadViewModel: ObservableObject {
    @Published var selectedRoom: SampleRoom? = SampleData.rooms.first

    let availableRooms = SampleData.rooms

    func select(_ room: SampleRoom) {
        selectedRoom = room
    }
}

