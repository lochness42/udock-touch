import SwiftUI
import TouchCore

/// What the user is about to perform, so the trace can be checked automatically later.
enum TraceLabel: String, CaseIterable, Identifiable {
    case tap, doubleTap, drag, longPress, twoFingerTap, scroll, pinch, rotate
    case swipeLeft, swipeRight, swipeUp, swipeDown, freeForm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tap: return "Tap"
        case .doubleTap: return "Double tap"
        case .drag: return "Drag"
        case .longPress: return "Long press"
        case .twoFingerTap: return "Two-finger tap"
        case .scroll: return "Two-finger scroll"
        case .pinch: return "Pinch"
        case .rotate: return "Rotate"
        case .swipeLeft: return "3-finger swipe left"
        case .swipeRight: return "3-finger swipe right"
        case .swipeUp: return "3-finger swipe up"
        case .swipeDown: return "3-finger swipe down"
        case .freeForm: return "Anything else"
        }
    }

    var expected: [String]? {
        switch self {
        case .tap: return ["click"]
        case .doubleTap: return ["click", "double-click"]
        case .drag: return ["drag"]
        case .longPress, .twoFingerTap: return ["right-click"]
        case .scroll: return ["scroll"]
        case .pinch: return ["pinch"]
        case .rotate: return ["rotate"]
        case .swipeLeft: return ["swipe-left"]
        case .swipeRight: return ["swipe-right"]
        case .swipeUp: return ["swipe-up"]
        case .swipeDown: return ["swipe-down"]
        case .freeForm: return nil
        }
    }
}

struct TracesTab: View {
    @EnvironmentObject private var state: AppState
    @State private var label = TraceLabel.tap
    @State private var files: [TraceFile] = []
    @State private var results: [URL: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Record a gesture a few times, both cleanly and sloppily. Each recording is saved as a trace that can be replayed through the gesture recogniser as a test.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Picker("Gesture", selection: $label) {
                    ForEach(TraceLabel.allCases) { Text($0.title).tag($0) }
                }
                .frame(width: 280)
                .disabled(state.isRecording)
                if state.isRecording {
                    Button("Stop and Save") { stop() }.keyboardShortcut(.defaultAction)
                    Label("Recording…", systemImage: "record.circle").foregroundStyle(.red)
                } else {
                    Button("Record") { state.startRecording() }
                }
                Spacer()
                Button("Show Folder") { NSWorkspace.shared.open(AppState.tracesFolder) }
            }
            Table(files) {
                TableColumn("Trace") { Text($0.url.deletingPathExtension().lastPathComponent) }
                TableColumn("Replay result") { f in
                    Text(results[f.url] ?? "").foregroundStyle((results[f.url] ?? "").hasPrefix("✓") ? .green : .primary)
                }
                TableColumn("") { f in Button("Replay") { replay(f.url) } }.width(70)
            }
        }
        .onAppear(perform: reload)
    }

    private func stop() {
        state.stopRecording(name: label.rawValue, expected: label.expected) { url in
            reload()
            if let url { replay(url) }
        }
    }

    private func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: AppState.tracesFolder, includingPropertiesForKeys: nil)) ?? []
        files = urls.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map(TraceFile.init)
    }

    private func replay(_ url: URL) {
        guard let data = try? Data(contentsOf: url), let trace = try? TouchTrace.decode(data) else {
            results[url] = "Unreadable"
            return
        }
        let got = TraceReplay.summary(TraceReplay.run(trace))
        let text = got.isEmpty ? "nothing" : got.joined(separator: ", ")
        if let expected = trace.expected {
            results[url] = (got == expected ? "✓ " : "✗ ") + text + (got == expected ? "" : " (expected \(expected.joined(separator: ", ")))")
        } else {
            results[url] = text
        }
    }
}

struct TraceFile: Identifiable {
    let url: URL
    var id: URL { url }
}
