import ARKit
import Foundation

@MainActor
final class EditableRoomPlanViewModel: ObservableObject {
    @Published private(set) var project: RoomPlanProject
    @Published var selectedObjectID: UUID?
    @Published var isAngledView = false
    @Published var isDebugPanelPresented = false
    @Published var errorMessage: String?

    private let persistence: RoomPlanProjectPersisting
    private var undoStack: [RoomPlanEditSnapshot] = []
    private var interactionSnapshotRecorded = false

    init(
        project: RoomPlanProject,
        persistence: RoomPlanProjectPersisting = RoomPlanPersistenceService()
    ) {
        self.project = project
        self.persistence = persistence
        persist()
    }

    var selectedObject: EditableRoomPlanObject? {
        project.objects.first { $0.id == selectedObjectID }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canDelete: Bool { selectedObject != nil }

    var worldMap: ARWorldMap? {
        guard let data = project.archivedWorldMap else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
    }

    func select(_ id: UUID?) {
        selectedObjectID = id
    }

    func beginTransform() {
        guard selectedObjectID != nil, !interactionSnapshotRecorded else { return }
        pushUndoSnapshot()
        interactionSnapshotRecorded = true
    }

    func moveSelected(by delta: SIMD2<Float>) {
        guard
            let selectedObjectID,
            let index = project.objects.firstIndex(where: { $0.id == selectedObjectID })
        else { return }
        let object = project.objects[index]
        let current = object.transform.position
        let radius = max(object.dimensions.width, object.dimensions.depth) / 2
        let proposed = SIMD3<Float>(current.x + delta.x, current.y, current.z + delta.y)
        let clamped = project.floorBounds.clamped(position: proposed, objectRadius: radius)
        project.objects[index].transform = object.transform.replacingFloorPosition(
            x: clamped.x,
            z: clamped.z
        )
        project.modifiedAt = Date()
    }

    func rotateSelected(by radians: Float, recordsUndo: Bool = true) {
        guard
            let selectedObjectID,
            let index = project.objects.firstIndex(where: { $0.id == selectedObjectID })
        else { return }
        if recordsUndo { pushUndoSnapshot() }
        project.objects[index].transform = project.objects[index].transform
            .rotatedAroundWorldY(by: radians)
        project.modifiedAt = Date()
        if recordsUndo { persist() }
    }

    func endTransform() {
        guard interactionSnapshotRecorded else { return }
        interactionSnapshotRecorded = false
        persist()
    }

    func deleteSelected() {
        guard let selectedObjectID else { return }
        pushUndoSnapshot()
        project.objects.removeAll { $0.id == selectedObjectID }
        self.selectedObjectID = nil
        project.modifiedAt = Date()
        persist()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        project.objects = snapshot.objects
        selectedObjectID = snapshot.selectedObjectID
        project.modifiedAt = Date()
        persist()
    }

    func reset() {
        guard project.objects != project.originalObjects else { return }
        pushUndoSnapshot()
        project.objects = project.originalObjects
        selectedObjectID = nil
        project.modifiedAt = Date()
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

    private func pushUndoSnapshot() {
        undoStack.append(
            RoomPlanEditSnapshot(
                objects: project.objects,
                selectedObjectID: selectedObjectID
            )
        )
        if undoStack.count > 30 {
            undoStack.removeFirst(undoStack.count - 30)
        }
    }

    private func persist() {
        do {
            try persistence.save(project)
        } catch {
            errorMessage = "The edited room could not be saved: \(error.localizedDescription)"
        }
    }
}

private struct RoomPlanEditSnapshot {
    let objects: [EditableRoomPlanObject]
    let selectedObjectID: UUID?
}
