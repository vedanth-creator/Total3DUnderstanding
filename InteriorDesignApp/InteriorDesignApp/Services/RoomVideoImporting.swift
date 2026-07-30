import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

protocol RoomVideoImporting {
    func importVideo(from item: PhotosPickerItem) async throws -> RoomScanVideo
}

struct LocalRoomVideoImportService: RoomVideoImporting {
    func importVideo(from item: PhotosPickerItem) async throws -> RoomScanVideo {
        guard let importedMovie = try await item.loadTransferable(type: ImportedRoomMovie.self) else {
            throw RoomScanVideoError.importFailed
        }

        do {
            return try await RoomScanVideo.inspect(
                localFileURL: importedMovie.localURL,
                source: .imported
            )
        } catch {
            try? FileManager.default.removeItem(at: importedMovie.localURL)
            throw error
        }
    }
}

private struct ImportedRoomMovie: Transferable {
    let localURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.localURL)
        } importing: { receivedFile in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("imported-room-scan-\(UUID().uuidString)")
                .appendingPathExtension(receivedFile.file.pathExtension.isEmpty ? "mov" : receivedFile.file.pathExtension)
            try FileManager.default.copyItem(at: receivedFile.file, to: destination)
            return ImportedRoomMovie(localURL: destination)
        }
    }
}
