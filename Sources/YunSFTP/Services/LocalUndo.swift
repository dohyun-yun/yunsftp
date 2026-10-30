import Foundation

/// Registers inverse operations for local file actions on the window's UndoManager.
/// Redo is not offered (the inverse of the inverse would need the original request); the
/// action simply disappears from the Undo menu after it ran.
public enum LocalUndo {
    private final class Box: NSObject { static let shared = Box() }

    public static func register(_ undoManager: UndoManager?, actionName: String, undo: @escaping @Sendable () async throws -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: Box.shared) { _ in
            Task { try? await undo() }
        }
        undoManager.setActionName(actionName)
    }
}
