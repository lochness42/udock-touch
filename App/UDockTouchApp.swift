import SwiftUI

@main
struct UDockTouchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(delegate.state)
        } label: {
            StatusIcon().environmentObject(delegate.state)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.start()
        if !state.onboardingCompleted {
            WindowPresenter.shared.showOnboarding(state)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.stop()
    }
}
