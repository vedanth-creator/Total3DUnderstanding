import Foundation

final class URLSessionRoomScanService: RoomScanSubmitting {
    private let baseURL: URL
    private let session: URLSession
    private let pollingIntervalNanoseconds: UInt64
    private let maximumPollingDuration: TimeInterval
    private let decoder = JSONDecoder()

    init(
        baseURL: URL,
        session: URLSession = .shared,
        pollingIntervalNanoseconds: UInt64 = 600_000_000,
        maximumPollingDuration: TimeInterval = 180
    ) {
        self.baseURL = baseURL
        self.session = session
        self.pollingIntervalNanoseconds = pollingIntervalNanoseconds
        self.maximumPollingDuration = maximumPollingDuration
    }

    func submit(_ video: RoomScanVideo) async throws -> RoomScanAcceptedResponse {
        guard FileManager.default.fileExists(atPath: video.localFileURL.path) else {
            throw RoomScanNetworkError.sourceFileUnavailable
        }

        let boundary = "CanvasRoomScan-\(UUID().uuidString)"
        let multipartURL = try makeMultipartFile(video: video, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: multipartURL) }

        var request = URLRequest(url: endpoint("v1", "room-scans"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        let (data, response) = try await session.upload(for: request, fromFile: multipartURL)
        try validate(response: response, data: data, expectedStatus: 202)
        return try decode(RoomScanAcceptedResponse.self, from: data)
    }

    func pollUntilCompleted(
        jobID: UUID,
        onUpdate: @escaping (RoomScanJobResponse) -> Void
    ) async throws {
        let deadline = Date().addingTimeInterval(maximumPollingDuration)

        while Date() < deadline {
            try Task.checkCancellation()
            let job: RoomScanJobResponse = try await get(
                endpoint("v1", "room-scans", jobID.uuidString.lowercased())
            )
            onUpdate(job)

            switch job.status {
            case .completed:
                return
            case .failed:
                throw RoomScanNetworkError.jobFailed(
                    job.error ?? "The backend could not prepare this room scan."
                )
            case .queued, .processing:
                try await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
            }
        }

        throw RoomScanNetworkError.pollingTimedOut
    }

    func fetchScene(jobID: UUID) async throws -> BackendSceneResponse {
        try await get(
            endpoint(
                "v1",
                "room-scans",
                jobID.uuidString.lowercased(),
                "scene"
            )
        )
    }

    private func get<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, expectedStatus: 200)
        return try decode(Response.self, from: data)
    }

    private func endpoint(_ components: String...) -> URL {
        components.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
    }

    private func validate(
        response: URLResponse,
        data: Data,
        expectedStatus: Int
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RoomScanNetworkError.invalidServerResponse
        }
        guard httpResponse.statusCode == expectedStatus else {
            let message = (try? decoder.decode(ServerErrorResponse.self, from: data))?.detail
            throw RoomScanNetworkError.server(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    private func decode<Response: Decodable>(
        _ type: Response.Type,
        from data: Data
    ) throws -> Response {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw RoomScanNetworkError.decodingFailed
        }
    }

    private func makeMultipartFile(video: RoomScanVideo, boundary: String) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-scan-upload-\(UUID().uuidString)")
            .appendingPathExtension("multipart")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw RoomScanNetworkError.multipartFileCreationFailed
        }

        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }

            try writeField(
                name: "duration_seconds",
                value: String(video.duration),
                boundary: boundary,
                to: output
            )
            if let width = video.pixelWidth {
                try writeField(name: "width", value: String(width), boundary: boundary, to: output)
            }
            if let height = video.pixelHeight {
                try writeField(name: "height", value: String(height), boundary: boundary, to: output)
            }
            try writeField(name: "source", value: video.source.rawValue, boundary: boundary, to: output)
            try writeField(
                name: "client_scan_id",
                value: video.id.uuidString.lowercased(),
                boundary: boundary,
                to: output
            )

            let fileExtension = video.localFileURL.pathExtension.lowercased()
            let normalizedExtension = ["mov", "mp4", "m4v"].contains(fileExtension)
                ? fileExtension
                : "mov"
            let contentType: String
            switch normalizedExtension {
            case "mp4": contentType = "video/mp4"
            case "m4v": contentType = "video/x-m4v"
            default: contentType = "video/quicktime"
            }
            let fileHeader = "--\(boundary)\r\n"
                + "Content-Disposition: form-data; name=\"video\"; filename=\"room-video.\(normalizedExtension)\"\r\n"
                + "Content-Type: \(contentType)\r\n\r\n"
            try output.write(contentsOf: Data(fileHeader.utf8))

            let input = try FileHandle(forReadingFrom: video.localFileURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: chunk)
            }
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private func writeField(
        name: String,
        value: String,
        boundary: String,
        to output: FileHandle
    ) throws {
        let field = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            + value
            + "\r\n"
        try output.write(contentsOf: Data(field.utf8))
    }
}

private struct ServerErrorResponse: Decodable {
    let detail: String?
}
