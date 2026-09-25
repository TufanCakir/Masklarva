import Foundation

/// Owns project-wide transaction history independently from SwiftUI views.
/// Snapshot entries are an intentionally simple Phase 1 implementation;
/// geometry-heavy commands can later replace individual entries with deltas.
struct EditorHistory {
    private let capacity: Int
    private var undoStack: [MasklarvaProject] = []
    private var redoStack: [MasklarvaProject] = []
    private var pendingProject: MasklarvaProject?

    init(capacity: Int = 100) {
        self.capacity = capacity
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func begin(project: MasklarvaProject) {
        guard pendingProject == nil else { return }
        pendingProject = project
    }

    @discardableResult
    mutating func commit(project: MasklarvaProject) -> Bool {
        guard let pendingProject else { return false }
        self.pendingProject = nil
        guard pendingProject != project else { return false }
        undoStack.append(pendingProject)
        if undoStack.count > capacity {
            undoStack.removeFirst(undoStack.count - capacity)
        }
        redoStack.removeAll()
        return true
    }

    mutating func undo(currentProject: MasklarvaProject) -> MasklarvaProject? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(currentProject)
        pendingProject = nil
        return previous
    }

    mutating func redo(currentProject: MasklarvaProject) -> MasklarvaProject? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(currentProject)
        pendingProject = nil
        return next
    }
}
