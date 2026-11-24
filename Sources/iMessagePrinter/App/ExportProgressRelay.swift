import Foundation

/// Latest progress and final outcome shared between an export worker and the
/// modal UI loop.
///
/// The modal run loop can be starved of `DispatchQueue.main` blocks, so the UI
/// polls this relay instead of relying only on main-queue callbacks.
final class ExportProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingProgress: ExportProgress?
    private var outcome: Result<Void, Error>?

    func update(_ progress: ExportProgress) {
        lock.lock()
        pendingProgress = progress
        lock.unlock()
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        outcome = result
        lock.unlock()
    }

    func take() -> (progress: ExportProgress?, outcome: Result<Void, Error>?) {
        lock.lock()
        defer { lock.unlock() }
        let taken = (pendingProgress, outcome)
        pendingProgress = nil
        outcome = nil
        return taken
    }
}
