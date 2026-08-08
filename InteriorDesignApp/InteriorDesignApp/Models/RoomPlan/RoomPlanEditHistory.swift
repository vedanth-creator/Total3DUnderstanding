import Foundation

struct RoomPlanEditSnapshot {
    let objects: [EditableRoomPlanObject]
    let selectedObjectID: UUID?
}

struct RoomPlanEditHistory {
    private(set) var undoStack: [RoomPlanEditSnapshot] = []
    private(set) var redoStack: [RoomPlanEditSnapshot] = []
    private let maximumEntries = 40

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func record(_ snapshot: RoomPlanEditSnapshot) {
        undoStack.append(snapshot)
        redoStack.removeAll()
        if undoStack.count > maximumEntries {
            undoStack.removeFirst(undoStack.count - maximumEntries)
        }
    }

    mutating func undo(current: RoomPlanEditSnapshot) -> RoomPlanEditSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(current: RoomPlanEditSnapshot) -> RoomPlanEditSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
