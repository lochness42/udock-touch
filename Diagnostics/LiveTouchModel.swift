import Foundation
import TouchCore

/// Live data for the Diagnostics window, kept apart from AppState so touches don't redraw the menu.
@MainActor
final class LiveTouchModel: ObservableObject {
    @Published var contacts: [TouchContact] = []
    @Published private(set) var gestures: [String] = []
    @Published private(set) var logLines: [String] = []

    private let maxGestures = 200
    private let maxLogLines = 1000

    func addGesture(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        gestures.append("\(f.string(from: Date()))  \(text)")
        if gestures.count > maxGestures { gestures.removeFirst(gestures.count - maxGestures) }
    }

    func addLog(_ line: String) {
        logLines.append(line)
        if logLines.count > maxLogLines { logLines.removeFirst(logLines.count - maxLogLines) }
    }

    func clear() {
        gestures = []
        logLines = []
    }
}
