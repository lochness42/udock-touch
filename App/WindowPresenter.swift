import AppKit
import SwiftUI

/// Opens the app's windows. A menu bar app has no Dock icon, so it activates itself first.
@MainActor
final class WindowPresenter {
    static let shared = WindowPresenter()

    private var windows: [String: NSWindow] = [:]

    func showSettings(_ state: AppState) {
        show("settings", title: "UDock Touch Settings", size: CGSize(width: 520, height: 460)) {
            SettingsView().environmentObject(state)
        }
    }

    func showDiagnostics(_ state: AppState) {
        show("diagnostics", title: "UDock Touch Diagnostics", size: CGSize(width: 720, height: 480)) {
            DiagnosticsView().environmentObject(state)
        }
    }

    func showOnboarding(_ state: AppState) {
        show("onboarding", title: "Set Up UDock Touch", size: CGSize(width: 520, height: 520)) {
            OnboardingView().environmentObject(state)
        }
    }

    func close(_ id: String) {
        windows[id]?.close()
    }

    private func show<V: View>(_ id: String, title: String, size: CGSize, content: () -> V) {
        let window = windows[id] ?? {
            let w = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = title
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: content())
            w.setContentSize(size)
            w.center()
            windows[id] = w
            return w
        }()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
