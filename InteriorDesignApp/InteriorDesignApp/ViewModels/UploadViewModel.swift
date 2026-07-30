import Foundation
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class UploadViewModel: ObservableObject {
    @Published var selectedRoom: SampleRoom? = SampleData.rooms.first
    @Published private(set) var selectedPhoto: SelectedPhoto?
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?

    let availableRooms = SampleData.rooms

    private let maximumPreviewPixelSize = 2_048

    func select(_ room: SampleRoom) {
        selectedRoom = room
    }

    func prepareForPhotoSelection() async -> Bool {
        errorMessage = nil

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let requestedStatus = await requestPhotoLibraryAuthorization()
            guard requestedStatus == .authorized || requestedStatus == .limited else {
                showPermissionDeniedMessage()
                return false
            }
            return true
        case .denied, .restricted:
            showPermissionDeniedMessage()
            return false
        @unknown default:
            errorMessage = "Photos are unavailable right now. Please try again."
            return false
        }
    }

    func importPhoto(from item: PhotosPickerItem) async {
        guard !isImporting else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw PhotoImportError.missingData
            }

            let maximumPixelSize = maximumPreviewPixelSize
            let image = try await Task.detached(priority: .userInitiated) {
                try Self.makeMemoryEfficientImage(
                    from: data,
                    maximumPixelSize: maximumPixelSize
                )
            }.value

            selectedPhoto = SelectedPhoto(
                id: item.itemIdentifier ?? UUID().uuidString,
                image: image,
                pixelWidth: Int(image.size.width * image.scale),
                pixelHeight: Int(image.size.height * image.scale)
            )
        } catch is CancellationError {
            // Dismissing the system picker is a normal cancellation, not an error.
        } catch PhotoImportError.decodeFailed {
            errorMessage = "That photo could not be opened. Please choose a JPEG, PNG, or HEIC image."
        } catch {
            errorMessage = "We couldn’t import that photo. Please try another image."
        }
    }

    func removeSelectedPhoto() {
        selectedPhoto = nil
        errorMessage = nil
    }

    private func requestPhotoLibraryAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func showPermissionDeniedMessage() {
        errorMessage = "Photo access is turned off. Allow access in Settings to choose a room photo."
    }

    private nonisolated static func makeMemoryEfficientImage(
        from data: Data,
        maximumPixelSize: Int
    ) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PhotoImportError.decodeFailed
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw PhotoImportError.decodeFailed
        }

        return UIImage(cgImage: cgImage)
    }
}

private enum PhotoImportError: Error {
    case missingData
    case decodeFailed
}
