import Foundation

protocol RoomScanSubmitting {
    func submit(_ video: RoomScanVideo) async throws -> RoomScanAcceptedResponse
    func pollUntilCompleted(
        jobID: UUID,
        onUpdate: @escaping (RoomScanJobResponse) -> Void
    ) async throws
    func fetchScene(jobID: UUID) async throws -> BackendSceneResponse
}

enum RoomScanNetworkError: LocalizedError {
    case sourceFileUnavailable
    case invalidServerResponse
    case server(statusCode: Int, message: String?)
    case decodingFailed
    case jobFailed(String)
    case pollingTimedOut
    case multipartFileCreationFailed

    var errorDescription: String? {
        switch self {
        case .sourceFileUnavailable:
            "The local room-scan video is no longer available."
        case .invalidServerResponse:
            "The room-scan server returned an invalid response."
        case let .server(statusCode, message):
            message ?? "The room-scan server returned HTTP \(statusCode)."
        case .decodingFailed:
            "The room-scan server returned data this app could not understand."
        case let .jobFailed(message):
            message
        case .pollingTimedOut:
            "The room scan is taking longer than expected. Please try again."
        case .multipartFileCreationFailed:
            "The room-scan upload could not be prepared."
        }
    }
}
