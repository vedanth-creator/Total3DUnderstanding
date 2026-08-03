import Foundation

struct APIConfiguration {
    let baseURL: URL

    // Change RoomScanPhysicalDeviceBaseURL in Info.plist to the Mac's LAN
    // address when testing on a physical iPhone.
    private static let simulatorBaseURL = "http://127.0.0.1:8000"

    static var development: APIConfiguration {
        #if targetEnvironment(simulator)
        let candidate = simulatorBaseURL
        #else
        let candidate = Bundle.main.object(
            forInfoDictionaryKey: "RoomScanPhysicalDeviceBaseURL"
        ) as? String ?? simulatorBaseURL
        #endif

        if let url = URL(string: candidate),
           let scheme = url.scheme,
           scheme == "http" || scheme == "https" {
            return APIConfiguration(baseURL: url)
        }

        // The literal fallback is valid and keeps a malformed device override local.
        return APIConfiguration(
            baseURL: URL(string: simulatorBaseURL) ?? URL(fileURLWithPath: "/")
        )
    }
}
