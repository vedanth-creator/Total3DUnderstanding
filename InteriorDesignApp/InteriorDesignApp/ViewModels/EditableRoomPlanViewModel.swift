import ARKit
import Foundation

enum RoomPlanEditorCameraPreset: Equatable {
    case top
    case perspective
}

@MainActor
final class EditableRoomPlanViewModel: ObservableObject {
    @Published private(set) var project: RoomPlanProject
    @Published var selectedObjectID: UUID?
    @Published private(set) var cameraPreset: RoomPlanEditorCameraPreset = .perspective
    @Published private(set) var cameraResetToken = 0
    @Published var isDebugPanelPresented = false
    @Published var errorMessage: String?

    private let persistence: RoomPlanProjectPersisting
    private var history = RoomPlanEditHistory()
    private var interactionStartSnapshot: RoomPlanEditSnapshot?

    init(
        project: RoomPlanProject,
        persistence: RoomPlanProjectPersisting = RoomPlanPersistenceService()
    ) {
        var normalizedProject = project
        let originalTransforms = Dictionary(
            uniqueKeysWithValues: project.originalObjects.map { ($0.id, $0.transform) }
        )
        // Projects saved by the earlier prototype did not persist edit-source
        // metadata. Restore the captured transform association from the
        // immutable original object list so existing moved objects remain AR changes.
        for index in normalizedProject.objects.indices
            where normalizedProject.objects[index].source == .scanned {
            normalizedProject.objects[index].originalTransform = originalTransforms[
                normalizedProject.objects[index].id
            ] ?? normalizedProject.objects[index].originalTransform
        }
        self.project = normalizedProject
        self.persistence = persistence
        persist()
    }

    var selectedObject: EditableRoomPlanObject? {
        project.objects.first { $0.id == selectedObjectID && !$0.isRemoved }
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var canDelete: Bool { selectedObject != nil }
    var arChangeCount: Int { project.objects.filter(\.shouldRenderAsARChange).count }

    var worldMap: ARWorldMap? {
        guard let data = project.archivedWorldMap else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
    }

    func select(_ id: UUID?) {
        selectedObjectID = id
    }

    func beginTransform() {
        guard selectedObject != nil, interactionStartSnapshot == nil else { return }
        interactionStartSnapshot = snapshot
    }

    func moveSelected(toFloorPosition floorPosition: SIMD2<Float>) {
        guard
            let selectedObjectID,
            let index = project.objects.firstIndex(where: { $0.id == selectedObjectID })
        else { return }
        let object = project.objects[index]
        let current = object.transform.position
        let radius = max(object.dimensions.width, object.dimensions.depth) / 2
        var proposed = SIMD3<Float>(floorPosition.x, current.y, floorPosition.y)
        proposed.x = snapToGrid(proposed.x)
        proposed.z = snapToGrid(proposed.z)
        let clamped = project.floorBounds.clamped(position: proposed, objectRadius: radius)
        project.objects[index].transform = object.transform.replacingFloorPosition(
            x: snapToNearbyWall(clamped.x, minimum: project.floorBounds.minimumX + radius, maximum: project.floorBounds.maximumX - radius),
            z: snapToNearbyWall(clamped.z, minimum: project.floorBounds.minimumZ + radius, maximum: project.floorBounds.maximumZ - radius)
        )
        project.modifiedAt = Date()
    }

    func rotateSelected(by radians: Float, recordsUndo: Bool = true) {
        guard
            let selectedObjectID,
            let index = project.objects.firstIndex(where: { $0.id == selectedObjectID })
        else { return }
        let before = recordsUndo ? snapshot : nil
        project.objects[index].transform = project.objects[index].transform
            .rotatedAroundWorldY(by: radians)
        project.modifiedAt = Date()
        if let before {
            history.record(before)
            persist()
        }
    }

    func endTransform() {
        guard let interactionStartSnapshot else { return }
        self.interactionStartSnapshot = nil
        if interactionStartSnapshot.objects != project.objects {
            history.record(interactionStartSnapshot)
            persist()
        }
    }

    func deleteSelected() {
        guard
            let selectedObjectID,
            let index = project.objects.firstIndex(where: { $0.id == selectedObjectID && !$0.isRemoved })
        else { return }
        let before = snapshot
        project.objects[index].isRemoved = true
        self.selectedObjectID = nil
        project.modifiedAt = Date()
        history.record(before)
        persist()
    }

    func add(_ category: RoomPlanAddCategory) {
        let before = snapshot
        let dimensions = category.defaultDimensions
        let center = project.floorBounds.center
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(center.x, dimensions.height / 2, center.z, 1)
        let object = EditableRoomPlanObject(
            id: UUID(),
            category: category.rawValue,
            dimensions: dimensions,
            transform: RoomPlanTransform(matrix),
            confidence: "Added",
            parentIdentifier: nil,
            source: .added
        )
        project.objects.append(object)
        selectedObjectID = object.id
        project.modifiedAt = Date()
        history.record(before)
        persist()
    }

    func undo() {
        guard let previous = history.undo(current: snapshot) else { return }
        restore(previous)
    }

    func redo() {
        guard let next = history.redo(current: snapshot) else { return }
        restore(next)
    }

    func setCameraPreset(_ preset: RoomPlanEditorCameraPreset) {
        cameraPreset = preset
    }

    func resetCamera() {
        cameraResetToken += 1
    }

    func resetLayout() {
        guard project.objects != project.originalObjects else { return }
        let before = snapshot
        project.objects = project.originalObjects
        selectedObjectID = nil
        project.modifiedAt = Date()
        history.record(before)
        persist()
    }

    func exportOriginal() -> URL? {
        do {
            return try persistence.exportOriginalUSDZ(project)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func exportEdited() async -> URL? {
        do {
            return try await persistence.exportEditedUSDZ(project)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private var snapshot: RoomPlanEditSnapshot {
        RoomPlanEditSnapshot(objects: project.objects, selectedObjectID: selectedObjectID)
    }

    private func restore(_ snapshot: RoomPlanEditSnapshot) {
        project.objects = snapshot.objects
        selectedObjectID = snapshot.selectedObjectID
        project.modifiedAt = Date()
        persist()
    }

    private func snapToGrid(_ value: Float) -> Float {
        let gridSize: Float = 0.05
        return (value / gridSize).rounded() * gridSize
    }

    private func snapToNearbyWall(_ value: Float, minimum: Float, maximum: Float) -> Float {
        let threshold: Float = 0.12
        if abs(value - minimum) < threshold { return minimum }
        if abs(value - maximum) < threshold { return maximum }
        return value
    }

    private func persist() {
        do {
            try persistence.save(project)
        } catch {
            errorMessage = "The edited room could not be saved: \(error.localizedDescription)"
        }
    }
}
