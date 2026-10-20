import Foundation

/// Asks the Dock to show Mission Control or App Exposé directly, without keyboard shortcuts.
/// Uses the private `CoreDockSendNotification`, looked up at runtime so a missing symbol isn't fatal.
enum Dock {
    private typealias SendNotification = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void

    private static let sendNotification: SendNotification? = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(path, RTLD_LAZY), let sym = dlsym(handle, "CoreDockSendNotification") else {
            return nil
        }
        return unsafeBitCast(sym, to: SendNotification.self)
    }()

    /// Returns false when the Dock API isn't available.
    static func send(_ notification: String) -> Bool {
        guard let send = sendNotification else { return false }
        send(notification as CFString, nil)
        return true
    }
}
