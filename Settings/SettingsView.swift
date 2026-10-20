import SwiftUI
import TouchCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            OrientationTab().tabItem { Label("Orientation", systemImage: "rotate.right") }
            GesturesTab().tabItem { Label("Gestures", systemImage: "hand.draw") }
            DeviceTab().tabItem { Label("Device", systemImage: "cable.connector") }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 420)
    }
}

private struct GeneralTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Toggle("Touch enabled", isOn: $state.settings.enabled)
            Picker("Touchscreen display", selection: displaySelection) {
                ForEach(state.displays) { Text($0.label).tag(Optional($0.id)) }
            }
            Toggle("Show a ripple where you touch", isOn: $state.settings.touchFeedback)
            Toggle("Launch at login", isOn: $state.launchAtLogin)
            if let error = state.launchAtLoginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }

    private var displaySelection: Binding<CGDirectDisplayID?> {
        Binding(
            get: { state.targetDisplay?.id },
            set: { id in
                if let d = state.displays.first(where: { $0.id == id }) { state.selectDisplay(d) }
            }
        )
    }
}

private struct OrientationTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Swap X and Y", isOn: $state.settings.orientation.swapXY)
                Toggle("Flip horizontally", isOn: $state.settings.orientation.flipX)
                Toggle("Flip vertically", isOn: $state.settings.orientation.flipY)
                Button("Detect Automatically…") { state.startCalibration(.orientation) }
            } footer: {
                Text("Automatic detection asks you to tap two corners of the touchscreen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Calibration", value: state.settings.calibration == .identity ? "Not calibrated" : "Calibrated")
                HStack {
                    Button("Calibrate…") { state.startCalibration(.calibration) }
                    Button("Test Accuracy…") { state.startTouchTest() }
                    Button("Reset") { state.settings.calibration = .identity }
                        .disabled(state.settings.calibration == .identity)
                }
            } footer: {
                Text("Calibration asks you to tap four targets, so taps land exactly under your finger.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GesturesTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Gestures") {
                Toggle("Tap to click", isOn: $state.settings.gestures.tap)
                Toggle("Drag", isOn: $state.settings.gestures.drag)
                Toggle("Long press to right-click", isOn: $state.settings.gestures.longPress)
                Toggle("Two-finger tap to right-click", isOn: $state.settings.gestures.twoFingerTap)
                Toggle("Two-finger scroll", isOn: $state.settings.gestures.scroll)
                Toggle("Pinch to zoom", isOn: $state.settings.gestures.pinch)
                Toggle("Rotate", isOn: $state.settings.gestures.rotate)
                Toggle("Three-finger swipe", isOn: $state.settings.gestures.threeFingerSwipe)
            }
            Section("Scrolling") {
                LabeledSlider("Speed", value: $state.settings.tunables.scrollSpeed, in: 0.25...3, format: "%.2f×")
                Toggle("Reverse direction", isOn: $state.settings.tunables.reverseScroll)
                Toggle("Momentum", isOn: $state.settings.tunables.momentum)
            }
            Section("Pinch and rotate") {
                Picker("Mode", selection: $state.settings.tunables.pinchMode) {
                    Text("Native gestures").tag(PinchMode.native)
                    Text("Keyboard (⌘+ / ⌘−)").tag(PinchMode.keys)
                }
                LabeledSlider("Pinch sensitivity", value: $state.settings.tunables.pinchSensitivity, in: 0.25...3,
                              format: "%.2f×")
            }
            Section("Timing") {
                LabeledSlider("Long-press delay", value: $state.settings.tunables.longPressDelay, in: 0.3...1.5,
                              format: "%.2f s")
            }
        }
        .formStyle(.grouped)
    }
}

private struct DeviceTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            if state.touchDevices.count > 1 {
                Picker("Touch device", selection: $state.settings.device) {
                    Text("Automatic").tag(DeviceIdentity?.none)
                    ForEach(state.touchDevices) { Text($0.name).tag(Optional($0.identity)) }
                }
            } else {
                LabeledContent("Touch device", value: state.touchDevices.first?.name ?? "Not connected")
            }
            Section {
                Toggle("Exclusive mode", isOn: $state.settings.seize)
            } footer: {
                Text("Turn this on if every tap clicks twice or the cursor jumps. It can also switch off the UDock's own keyboard and trackpad. If that happens, turn it off again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: String) {
        self.title = title
        _value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range)
                Text(String(format: format, value)).monospacedDigit().frame(width: 56, alignment: .trailing)
            }
        }
    }
}
