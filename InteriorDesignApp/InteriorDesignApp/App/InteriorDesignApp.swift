import SwiftUI

@main
struct InteriorDesignApp: App {
    @StateObject private var appViewModel = AppViewModel(
        designService: MockRoomDesignService()
    )

    var body: some Scene {
        WindowGroup {
            AppRootView(viewModel: appViewModel)
                .preferredColorScheme(.light)
        }
    }
}

