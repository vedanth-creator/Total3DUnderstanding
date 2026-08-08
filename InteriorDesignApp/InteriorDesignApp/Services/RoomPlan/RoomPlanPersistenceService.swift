import Foundation
import RealityKit
import RoomPlan

protocol RoomPlanProjectPersisting {
    func save(_ project: RoomPlanProject) throws
    func loadMostRecent() throws -> RoomPlanProject?
    func exportOriginalUSDZ(_ project: RoomPlanProject) throws -> URL
    @MainActor func exportEditedUSDZ(_ project: RoomPlanProject) async throws -> URL
}

struct RoomPlanPersistenceService: RoomPlanProjectPersisting {
    private let fileManager: FileManager
    private let rootDirectory: URL

    init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.rootDirectory = applicationSupport
                .appendingPathComponent("RoomPlanScans", isDirectory: true)
        }
    }

    func save(_ project: RoomPlanProject) throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: projectURL(project.id), options: .atomic)
    }

    func loadMostRecent() throws -> RoomPlanProject? {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return nil }
        let files = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        let latest = try files.max {
            let left = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let right = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return left < right
        }
        guard let latest else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RoomPlanProject.self, from: Data(contentsOf: latest))
    }

    func exportOriginalUSDZ(_ project: RoomPlanProject) throws -> URL {
        let destination = exportURL(project.id, suffix: "original")
        try removeExistingFile(destination)
        try project.originalCapturedRoom.export(to: destination, exportOptions: .mesh)
        return destination
    }

    @MainActor
    func exportEditedUSDZ(_ project: RoomPlanProject) async throws -> URL {
        guard #available(iOS 18.0, *) else {
            throw RoomPlanPersistenceError.editedExportRequiresIOS18
        }
        let destination = exportURL(project.id, suffix: "edited")
        try removeExistingFile(destination)
        let root = RoomPlanEntityFactory.makeSceneRoot(for: project, includeFloor: true)
        try await root.write(to: destination)
        return destination
    }

    private func projectURL(_ id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func exportURL(_ id: UUID, suffix: String) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("\(id.uuidString)-\(suffix)")
            .appendingPathExtension("usdz")
    }

    private func removeExistingFile(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

enum RoomPlanPersistenceError: LocalizedError {
    case editedExportRequiresIOS18

    var errorDescription: String? {
        switch self {
        case .editedExportRequiresIOS18:
            "Edited RealityKit export requires iOS 18 or newer. Original RoomPlan USDZ export is still available."
        }
    }
}
