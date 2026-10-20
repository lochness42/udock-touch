import SwiftUI

struct StatusIcon: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Image(systemName: state.touching && state.status == .running ? "hand.point.up.left.fill" : state.status.symbol)
    }
}

struct MenuContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Text(state.status.title)

        Divider()

        Button(state.settings.enabled ? "Pause Touch" : "Enable Touch") {
            state.settings.enabled.toggle()
        }

        Picker("Target Display", selection: displaySelection) {
            ForEach(state.displays) { display in
                Text(display.label).tag(Optional(display.id))
            }
        }

        if !state.accessibilityGranted {
            Button("Set Up Permissions…") { WindowPresenter.shared.showOnboarding(state) }
        }

        Divider()

        Button("Settings…") { WindowPresenter.shared.showSettings(state) }
            .keyboardShortcut(",")
        Button("Touch Test…") { state.startTouchTest() }
            .disabled(state.touchDevices.isEmpty)
        Button("Diagnostics…") { WindowPresenter.shared.showDiagnostics(state) }
        Toggle("Debug Logging", isOn: $state.settings.debugLogging)
        Toggle("Launch at Login", isOn: $state.launchAtLogin)

        Divider()

        Button("Quit UDock Touch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
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
