import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    let featuredRooms = SampleData.rooms

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }
}
