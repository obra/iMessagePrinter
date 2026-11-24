import Foundation

final class ExportCoordinator {
    private let lock = NSLock()
    private var active = false

    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !active else { return false }
        active = true
        return true
    }

    func end() {
        lock.lock()
        active = false
        lock.unlock()
    }
}
