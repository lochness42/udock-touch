import Foundation
import os

/// Logs to the unified system log and to ~/Library/Logs/UDockTouch/touch.log.
/// `info` is always written; `debug` only while debug logging is on.
public final class TouchLog {
    public static let shared = TouchLog()

    public let fileURL: URL
    /// Called on a background queue with each line written.
    public var onLine: ((String) -> Void)?

    public var debugEnabled: Bool {
        get { lock.withLock { _debugEnabled } }
        set { lock.withLock { _debugEnabled = newValue } }
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "udocktouch", category: "touch")
    private let queue = DispatchQueue(label: "UDockTouch.log")
    private let lock = NSLock()
    private var _debugEnabled = false
    private var handle: FileHandle?
    private let maxFileSize: UInt64 = 5_000_000
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/UDockTouch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("touch.log")
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        write(message)
    }

    public func debug(_ message: @autoclosure () -> String) {
        guard debugEnabled else { return }
        let m = message()
        logger.debug("\(m, privacy: .public)")
        write(m)
    }

    private func write(_ message: String) {
        let date = Date()
        queue.async { [self] in
            let line = "[\(formatter.string(from: date))] \(message)"
            if handle == nil {
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                }
                handle = try? FileHandle(forWritingTo: fileURL)
                _ = try? handle?.seekToEnd()
            }
            if let h = handle, let size = try? h.offset(), size > maxFileSize {
                try? h.truncate(atOffset: 0)
            }
            handle?.write(Data((line + "\n").utf8))
            onLine?(line)
        }
    }
}
