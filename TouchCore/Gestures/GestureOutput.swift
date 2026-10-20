import CoreGraphics

/// A touch in screen coordinates.
public struct Contact: Equatable, Sendable {
    public var id: Int
    public var p: CGPoint

    public init(id: Int, p: CGPoint) {
        self.id = id
        self.p = p
    }
}

public enum GesturePhase: Int, Equatable, Sendable {
    case began = 1, changed = 2, ended = 4
}

public enum MomentumPhase: Int, Equatable, Sendable {
    case none = 0, begin = 1, `continue` = 2, end = 3
}

public enum SwipeDirection: String, Equatable, Sendable {
    case left, right, up, down
}

/// What the recogniser asks the event poster to do.
public enum GestureOutput: Equatable, Sendable, CustomStringConvertible {
    case move(CGPoint)
    case leftDown(CGPoint, clicks: Int)
    case leftDragged(CGPoint, clicks: Int)
    case leftUp(CGPoint, clicks: Int)
    case leftClick(CGPoint, clicks: Int)
    case rightClick(CGPoint)
    case scroll(dx: Double, dy: Double, phase: GesturePhase?, momentum: MomentumPhase)
    case magnify(Double, GesturePhase)
    case rotate(Double, GesturePhase)
    case zoomKey(zoomIn: Bool)
    case swipe(SwipeDirection)

    /// Start, end or one-shot outputs, as opposed to per-frame updates.
    public var isNotable: Bool {
        switch self {
        case .move, .leftDragged: return false
        case .scroll(_, _, let phase, let momentum):
            return phase == .began || phase == .ended || momentum == .begin || momentum == .end
        case .magnify(_, let phase), .rotate(_, let phase): return phase != .changed
        default: return true
        }
    }

    public var description: String {
        func pt(_ p: CGPoint) -> String { "(\(Int(p.x)),\(Int(p.y)))" }
        func f(_ v: Double) -> String { String(format: "%.3f", v) }
        switch self {
        case .move(let p): return "move \(pt(p))"
        case .leftDown(let p, let c): return "left down \(pt(p)) clicks=\(c)"
        case .leftDragged(let p, let c): return "left dragged \(pt(p)) clicks=\(c)"
        case .leftUp(let p, let c): return "left up \(pt(p)) clicks=\(c)"
        case .leftClick(let p, let c): return c > 1 ? "click ×\(c) \(pt(p))" : "click \(pt(p))"
        case .rightClick(let p): return "right click \(pt(p))"
        case .scroll(let dx, let dy, let phase, let momentum):
            let ph = phase.map { "\($0)" } ?? "-"
            return "scroll dx=\(f(dx)) dy=\(f(dy)) phase=\(ph) momentum=\(momentum)"
        case .magnify(let v, let phase): return "magnify \(f(v)) \(phase)"
        case .rotate(let v, let phase): return "rotate \(f(v))° \(phase)"
        case .zoomKey(let zoomIn): return zoomIn ? "zoom in (⌘=)" : "zoom out (⌘-)"
        case .swipe(let d): return "3-finger swipe \(d)"
        }
    }
}
