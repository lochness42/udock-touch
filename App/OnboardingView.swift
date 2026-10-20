import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set up UDock Touch")
                .font(.title2.bold())
            Text("This window updates on its own as each step is done.")
                .foregroundStyle(.secondary)

            Step(number: 1, title: "Allow Accessibility",
                 detail: "Lets UDock Touch click, scroll and send gestures for you. Switch it on in the list that opens.",
                 done: state.accessibilityGranted) {
                Button("Open System Settings") { Permissions.requestAccessibility() }
            }

            Step(number: 2, title: "Allow Input Monitoring (recommended)",
                 detail: "Some macOS versions need this to read the touch panel.",
                 done: state.inputMonitoringGranted) {
                Button("Open System Settings") { Permissions.requestInputMonitoring() }
            }

            Step(number: 3, title: "Connect the UDock",
                 detail: touchDetail,
                 done: !state.touchDevices.isEmpty) {
                EmptyView()
            }

            Step(number: 4, title: "Calibrate (optional)",
                 detail: "Tap a few targets on the touchscreen so touches land exactly under your finger.",
                 done: state.settings.calibration != .identity) {
                Button("Start") { state.startCalibration(.full) }
                    .disabled(state.touchDevices.isEmpty || state.calibration != nil)
            }
            if state.settings.calibration != .identity {
                Button("Test Accuracy…") { state.startTouchTest() }
                    .padding(.leading, 40)
            }

            Spacer()

            HStack {
                Spacer()
                Button(state.accessibilityGranted ? "Done" : "Finish Later") {
                    state.onboardingCompleted = true
                    WindowPresenter.shared.close("onboarding")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 480)
    }

    private var touchDetail: String {
        if let d = state.touchDevices.first { return "Found “\(d.name)”." }
        return "Use a full-function USB-C cable, or HDMI plus a USB data cable. Wireless mode doesn't carry touch."
    }
}

private struct Step<Action: View>: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !done { action() }
            }
        }
    }
}
