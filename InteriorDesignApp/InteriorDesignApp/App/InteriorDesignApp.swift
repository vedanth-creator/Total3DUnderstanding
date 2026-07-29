import OSLog
import SwiftUI
import UIKit

enum AppDebugLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "InteriorDesignApp",
        category: "Lifecycle"
    )

    static func write(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #endif
    }
}

final class AppLifecycleDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppDebugLog.write("App launch completed; pid=\(ProcessInfo.processInfo.processIdentifier)")
        return true
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        AppDebugLog.write("App received a memory warning")
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // iOS does not call this for every force-quit or terminated background app.
        AppDebugLog.write("App will terminate")
    }
}

@main
struct InteriorDesignApp: App {
    @UIApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appViewModel = AppViewModel(
        designService: MockRoomDesignService()
    )

    var body: some Scene {
        WindowGroup {
            AppRootView(viewModel: appViewModel)
                .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                AppDebugLog.write("App scene entered foreground/active")
            case .inactive:
                AppDebugLog.write("App scene became inactive")
            case .background:
                AppDebugLog.write("App scene entered background")
            @unknown default:
                AppDebugLog.write("App scene entered an unknown phase")
            }
        }
    }
}
