import SwiftUI
import TouchCore

struct DiagnosticsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            TouchesTab(live: state.live).tabItem { Text("Touches") }
            TracesTab().tabItem { Text("Traces") }
            LogTab(live: state.live).tabItem { Text("Log") }
            DevicesTab().tabItem { Text("Devices") }
        }
        .padding()
        .frame(minWidth: 720, minHeight: 480)
    }
}

private let testPoster = CGEventPoster()

/// Posts a zoom-in or 45° anticlockwise rotation at the pointer, 3 s from now.
private func runNativeTest(rotate: Bool) {
    DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 3) {
        let steps = 20
        for i in 0...steps + 1 {
            let phase: GesturePhase = i == 0 ? .began : (i > steps ? .ended : .changed)
            let value = phase == .ended ? 0 : (rotate ? 45.0 / Double(steps) : 0.05)
            testPoster.post(rotate ? .rotate(value, phase) : .magnify(value, phase))
            usleep(16_000)
        }
    }
}

private struct TouchesTab: View {
    @ObservedObject var live: LiveTouchModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                TouchCanvas(contacts: live.contacts)
                    .aspectRatio(16 / 9, contentMode: .fit)
                Text("Raw panel coordinates, before orientation and calibration. \(live.contacts.count) finger(s).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Recognised gestures").font(.headline)
                ScrollingLines(lines: live.gestures)
                Text("Test 3-finger swipe output").font(.headline)
                HStack {
                    ForEach([SwipeDirection.left, .right, .up, .down], id: \.self) { d in
                        Button(d.rawValue.capitalized) { testPoster.post(.swipe(d)) }
                    }
                }
                Text("Test native gestures").font(.headline)
                Text("Starts after 3 s. Move the pointer over a photo in Preview meanwhile.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Pinch") { runNativeTest(rotate: false) }
                    Button("Rotate") { runNativeTest(rotate: true) }
                }
            }
            .frame(width: 260)
        }
    }
}

private struct TouchCanvas: View {
    let contacts: [TouchContact]

    var body: some View {
        Canvas { ctx, size in
            ctx.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(.secondary), lineWidth: 1)
            for c in contacts {
                let p = CGPoint(x: c.x * size.width, y: c.y * size.height)
                let r = 18.0
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.accentColor.opacity(0.7)))
                ctx.draw(Text("\(c.id)").font(.caption.bold()).foregroundColor(.white), at: p)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct LogTab: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var live: LiveTouchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Debug logging", isOn: $state.settings.debugLogging)
                Spacer()
                Button("Clear") { live.clear() }
                Button("Show Log File") {
                    NSWorkspace.shared.activateFileViewerSelecting([TouchLog.shared.fileURL])
                }
            }
            ScrollingLines(lines: live.logLines)
            Text("Debug logging records the panel's report layout, raw reports (10 a second at most), every touch frame and every gesture. Log file: \(TouchLog.shared.fileURL.path)")
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private struct ScrollingLines: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        Text(line).font(.system(.caption, design: .monospaced)).id(i)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: lines.count) { n in
                if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) }
            }
        }
    }
}

private struct DevicesTab: View {
    @EnvironmentObject private var state: AppState
    @State private var devices = HIDDeviceInfo.all()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HID devices").font(.headline)
                Spacer()
                Button("Copy") { copyList() }
                Button("Refresh") { devices = HIDDeviceInfo.all() }
            }
            Table(devices) {
                TableColumn("") { Text($0.isTouchScreen ? "★" : "") }.width(16)
                TableColumn("Name", value: \.name)
                TableColumn("VID") { Text(String(format: "0x%04X", $0.vendorID)).monospaced() }.width(64)
                TableColumn("PID") { Text(String(format: "0x%04X", $0.productID)).monospaced() }.width(64)
                TableColumn("Transport", value: \.transport).width(80)
                TableColumn("Usages") { Text($0.usages.map(\.description).joined(separator: " ")).monospaced() }
            }
            Text("★ = reports as a touchscreen (usage 0D:04).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: state.touchDevices) { _ in devices = HIDDeviceInfo.all() }
    }

    private func copyList() {
        let text = devices.map {
            String(format: "%@ VID 0x%04X PID 0x%04X  %@  [%@]  usages %@", $0.isTouchScreen ? "★" : " ",
                   $0.vendorID, $0.productID, $0.name, $0.transport,
                   $0.usages.map(\.description).joined(separator: " "))
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
