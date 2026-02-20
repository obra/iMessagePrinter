import Foundation
import AppKit

enum FullDiskAccessChecker {
    static var hasAccess: Bool {
        // Actually try to open the file — isReadableFile alone may not trigger TCC
        let path = DatabaseService.chatDBPath
        if FileManager.default.isReadableFile(atPath: path) {
            // Double-check by actually opening
            if let _ = FileHandle(forReadingAtPath: path) {
                return true
            }
        }
        return false
    }

    /// Attempt to trigger TCC by reading the protected file
    /// This causes macOS to add the app to the FDA list in System Settings
    static func triggerTCCPrompt() {
        let path = DatabaseService.chatDBPath
        _ = FileHandle(forReadingAtPath: path)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
