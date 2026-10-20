import AppKit
import SwiftUI
import TouchCore

/// Full-screen accuracy check on the touch display. Touches are drawn where they map to,
/// taps near a target record their error, and nothing is clicked meanwhile.
@MainActor
final class TouchTestController: ObservableObject {
    static let targets: [CGPoint] = [0.1, 0.5, 0.9].flatMap { y in [0.1, 0.5, 0.9].map { x in CGPoint(x: x, y: y) } }

    /// Live fingers, normalised screen coordinates.
    @Published private(set) var fingers: [Int: CGPoint] = [:]
    @Published private(set) var trails: [Int: [CGPoint]] = [:]
    /// Target index → error of the latest tap on it, in points.
    @Published private(set) var errors: [Int: Double] = [:]
    @Published private(set) var lastTap: CGPoint?
    /// Cells of a coverage grid that a finger has passed over.
    @Published private(set) var covered: Set<Int> = []
    /// Furthest point reached towards each edge, normalised (min x, min y, max x, max y).
    @Published private(set) var reach: (minX: Double, minY: Double, maxX: Double, maxY: Double)?
    static let columns = 32
    static let rows = 18
    var onFinish: (() -> Void)?

    private unowned let state: AppState
    private var window: OverlayWindow?
    private var screenSize = CGSize(width: 1, height: 1)
    private let maxTrail = 120

    init(state: AppState) {
        self.state = state
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
        screenSize = screen.frame.size
        let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.onEscape = { [weak self] in self?.finish() }
        w.contentView = NSHostingView(rootView: TouchTestView(controller: self))
        w.setFrame(screen.frame, display: true)
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        state.frameObserver = { [weak self] contacts in self?.frame(contacts) }
        state.setCapture { [weak self] c in self?.tapped(c) }
        TouchLog.shared.info("Touch test opened")
    }

    func clear() {
        trails = [:]
        errors = [:]
        lastTap = nil
        covered = []
        reach = nil
    }

    func recalibrate() {
        finish()
        state.startCalibration(.calibration)
    }

    func finish() {
        state.frameObserver = nil
        state.setCapture(nil)
        window?.orderOut(nil)
        window = nil
        if !errors.isEmpty, let s = summary {
            TouchLog.shared.info("Touch test: \(errors.count) target(s), \(s)")
        }
        if let r = reachSummary { TouchLog.shared.info("Touch test: \(r)") }
        onFinish?()
    }

    var summary: String? {
        guard !errors.isEmpty else { return nil }
        let values = Array(errors.values)
        let mean = values.reduce(0, +) / Double(values.count)
        return String(format: "average error %.0f pt, worst %.0f pt", mean, values.max() ?? 0)
    }

    var coveragePercent: Int {
        covered.count * 100 / (Self.columns * Self.rows)
    }

    /// Distance from each edge still not reached, in points.
    var reachSummary: String? {
        guard let r = reach else { return nil }
        let w = screenSize.width, h = screenSize.height
        return String(format: "edges missed by: left %.0f pt, right %.0f pt, top %.0f pt, bottom %.0f pt",
                      r.minX * w, (1 - r.maxX) * w, r.minY * h, (1 - r.maxY) * h)
    }

    private func frame(_ contacts: [TouchContact]) {
        var now: [Int: CGPoint] = [:]
        for c in contacts {
            let p = TouchMapper.normalized(c, settings: state.settings)
            let col = min(Int(p.x * Double(Self.columns)), Self.columns - 1)
            let row = min(Int(p.y * Double(Self.rows)), Self.rows - 1)
            covered.insert(row * Self.columns + col)
            if let r = reach {
                reach = (min(r.minX, p.x), min(r.minY, p.y), max(r.maxX, p.x), max(r.maxY, p.y))
            } else {
                reach = (p.x, p.y, p.x, p.y)
            }
            now[c.id] = p
            if fingers[c.id] == nil { trails[c.id] = [] }
            trails[c.id, default: []].append(p)
            if trails[c.id]!.count > maxTrail { trails[c.id]!.removeFirst() }
        }
        fingers = now
    }

    private func tapped(_ c: TouchContact) {
        let p = TouchMapper.normalized(c, settings: state.settings)
        lastTap = p
        let distances = Self.targets.map { distance(p, $0) }
        guard let i = distances.indices.min(by: { distances[$0] < distances[$1] }), distances[i] < 80 else { return }
        errors[i] = distances[i]
    }

    /// Distance in screen points between two normalised points.
    func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot((a.x - b.x) * screenSize.width, (a.y - b.y) * screenSize.height)
    }
}

private struct TouchTestView: View {
    @ObservedObject var controller: TouchTestController

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black.opacity(0.92)
                Canvas { ctx, size in
                    func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
                    // Coverage
                    let cw = size.width / Double(TouchTestController.columns)
                    let ch = size.height / Double(TouchTestController.rows)
                    for cell in controller.covered {
                        let col = cell % TouchTestController.columns, row = cell / TouchTestController.columns
                        ctx.fill(Path(CGRect(x: Double(col) * cw, y: Double(row) * ch, width: cw, height: ch)),
                                 with: .color(.green.opacity(0.12)))
                    }
                    // Edges reached
                    if let r = controller.reach {
                        let edges: [(Bool, CGPoint, CGPoint)] = [
                            (r.minX <= 0.002, CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1)),
                            (r.maxX >= 0.998, CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1)),
                            (r.minY <= 0.002, CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)),
                            (r.maxY >= 0.998, CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)),
                        ]
                        for (reached, a, b) in edges where reached {
                            var line = Path()
                            line.move(to: pt(a))
                            line.addLine(to: pt(b))
                            ctx.stroke(line, with: .color(.green), lineWidth: 8)
                        }
                    }
                    // Grid
                    for f in stride(from: 0.1, through: 0.9, by: 0.1) {
                        var path = Path()
                        path.move(to: pt(CGPoint(x: f, y: 0)))
                        path.addLine(to: pt(CGPoint(x: f, y: 1)))
                        path.move(to: pt(CGPoint(x: 0, y: f)))
                        path.addLine(to: pt(CGPoint(x: 1, y: f)))
                        ctx.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 1)
                    }
                    // Trails
                    for trail in controller.trails.values where trail.count > 1 {
                        var path = Path()
                        path.addLines(trail.map(pt))
                        ctx.stroke(path, with: .color(.accentColor.opacity(0.6)), lineWidth: 3)
                    }
                    // Targets
                    for (i, t) in TouchTestController.targets.enumerated() {
                        let c = pt(t)
                        let color = controller.errors[i].map(Self.color) ?? .white
                        var cross = Path()
                        cross.move(to: CGPoint(x: c.x - 20, y: c.y))
                        cross.addLine(to: CGPoint(x: c.x + 20, y: c.y))
                        cross.move(to: CGPoint(x: c.x, y: c.y - 20))
                        cross.addLine(to: CGPoint(x: c.x, y: c.y + 20))
                        ctx.stroke(cross, with: .color(color), lineWidth: 2)
                        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 25, y: c.y - 25, width: 50, height: 50)),
                                   with: .color(color.opacity(0.6)), lineWidth: 1.5)
                        if let e = controller.errors[i] {
                            ctx.draw(Text(String(format: "%.0f pt", e)).font(.caption.bold()).foregroundColor(color),
                                     at: CGPoint(x: c.x, y: c.y + 40))
                        }
                    }
                    // Last tap
                    if let p = controller.lastTap.map(pt) {
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.yellow))
                    }
                    // Live fingers
                    for (id, f) in controller.fingers {
                        let p = pt(f)
                        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 22, y: p.y - 22, width: 44, height: 44)),
                                   with: .color(.white), lineWidth: 2)
                        ctx.draw(Text("\(id)").font(.caption.bold()).foregroundColor(.white), at: CGPoint(x: p.x, y: p.y - 34))
                    }
                }
                VStack(spacing: 10) {
                    Text("Touch Test").font(.title.bold())
                    Text("Tap the crosses to measure accuracy. Drag a finger into every corner and along every edge to check you can reach the whole screen. Touches don't click while this is open.")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 640)
                    Text(controller.summary ?? "Targets: green under 10 pt, yellow under 25 pt, red beyond.")
                        .foregroundStyle(.secondary)
                    Text("Covered \(controller.coveragePercent)% of the screen"
                         + (controller.reachSummary.map { " · \($0)" } ?? ""))
                        .foregroundStyle(.secondary)
                    Text("Reached edges turn green.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Clear") { controller.clear() }
                        Button("Recalibrate…") { controller.recalibrate() }
                        Button("Done") { controller.finish() }.keyboardShortcut(.cancelAction)
                    }
                    Text("Use the mouse for these buttons, or press Esc.").font(.caption).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                .padding(20)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .position(x: size.width / 2, y: size.height * 0.3)
            }
        }
        .ignoresSafeArea()
    }

    static func color(_ error: Double) -> Color {
        error < 10 ? .green : (error < 25 ? .yellow : .red)
    }
}
