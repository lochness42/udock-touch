import AppKit
import SwiftUI
import TouchCore

/// Runs the full-screen orientation and 4-point calibration steps on the touch display.
@MainActor
final class CalibrationController: ObservableObject {
    enum Mode { case full, orientation, calibration }
    private enum Step { case orientation, calibration }

    static let orientationTargets = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1)]
    static let calibrationTargets = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1),
                                     CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9)]

    @Published private(set) var targets: [CGPoint] = []
    @Published private(set) var index = 0
    @Published private(set) var title = ""
    @Published private(set) var message = ""
    var onFinish: (() -> Void)?

    private unowned let state: AppState
    private let mode: Mode
    private var step = Step.orientation
    private var taps: [TouchContact] = []
    private var window: OverlayWindow?

    init(state: AppState, mode: Mode) {
        self.state = state
        self.mode = mode
    }

    func start() {
        guard let screen = state.touchScreen else {
            let alert = NSAlert()
            alert.messageText = "No touch display found"
            alert.informativeText = "Connect the UDock and pick its display in Settings, then try again."
            alert.runModal()
            finish()
            return
        }
        let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.onEscape = { [weak self] in self?.cancel() }
        w.contentView = NSHostingView(rootView: CalibrationView(controller: self))
        w.setFrame(screen.frame, display: true)
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        state.setCapture { [weak self] c in self?.tapped(c) }
        begin(mode == .calibration ? .calibration : .orientation)
    }

    func cancel() {
        TouchLog.shared.info("Calibration cancelled")
        finish()
    }

    private func begin(_ s: Step) {
        step = s
        taps = []
        index = 0
        switch s {
        case .orientation:
            title = "Orientation"
            targets = Self.orientationTargets
        case .calibration:
            title = "Calibration"
            targets = Self.calibrationTargets
        }
    }

    private func tapped(_ c: TouchContact) {
        guard index < targets.count else { return }
        taps.append(c)
        index += 1
        if index == targets.count { finishStep() }
    }

    private func finishStep() {
        switch step {
        case .orientation:
            let (a, b) = (taps[0], taps[1])
            guard hypot(a.x - b.x, a.y - b.y) > 0.3 else {
                message = "Those two taps were too close together. Let's try again."
                begin(.orientation)
                return
            }
            let o = Orientation.infer(topLeft: a, topRight: b)
            TouchLog.shared.info("Orientation detected: swapXY=\(o.swapXY) flipX=\(o.flipX) flipY=\(o.flipY)")
            state.settings.orientation = o
            state.settings.calibration = .identity
            message = ""
            if mode == .full { begin(.calibration) } else { finish() }

        case .calibration:
            let measured = taps.map { TouchMapper.oriented($0, state.settings.orientation) }
            guard let k = Calibration.fit(measured: measured, targets: targets),
                  k.maxError(measured: measured, targets: targets) < 0.05
            else {
                message = "Those taps didn't line up. Let's try again, aiming for the centre of each cross."
                begin(.calibration)
                return
            }
            TouchLog.shared.info(String(format: "Calibration saved: a=%.4f b=%.4f c=%.4f d=%.4f tx=%.4f ty=%.4f",
                                        k.a, k.b, k.c, k.d, k.tx, k.ty))
            state.settings.calibration = k
            finish()
        }
    }

    private func finish() {
        state.setCapture(nil)
        window?.orderOut(nil)
        window = nil
        onFinish?()
    }
}

final class OverlayWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

private struct CalibrationView: View {
    @ObservedObject var controller: CalibrationController

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.88)
                if controller.index < controller.targets.count {
                    let t = controller.targets[controller.index]
                    Crosshair()
                        .position(x: t.x * geo.size.width, y: t.y * geo.size.height)
                }
                VStack(spacing: 12) {
                    Text(controller.title).font(.largeTitle.bold())
                    Text("Tap the centre of the cross with one finger (\(min(controller.index + 1, controller.targets.count)) of \(controller.targets.count)).")
                        .font(.title3)
                    if !controller.message.isEmpty {
                        Text(controller.message).foregroundStyle(.yellow)
                    }
                    Button("Cancel") { controller.cancel() }
                        .keyboardShortcut(.cancelAction)
                    Text("Or press Esc").font(.caption).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
    }
}

private struct Crosshair: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor, lineWidth: 3)
                .frame(width: 60, height: 60)
                .scaleEffect(pulse ? 1.2 : 0.8)
                .opacity(pulse ? 0.4 : 1)
            Rectangle().fill(.white).frame(width: 44, height: 2)
            Rectangle().fill(.white).frame(width: 2, height: 44)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
