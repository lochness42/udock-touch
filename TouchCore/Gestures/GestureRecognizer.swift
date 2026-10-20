import CoreGraphics
import Foundation

/// Turns touch frames into gesture outputs. Pure: no clock, no event posting.
///
/// Call `update` with every frame and `tick` once `nextDeadline` passes
/// (long press, momentum). `reset` closes anything still open.
public final class GestureRecognizer {
    public var settings: TouchSettings
    public private(set) var nextDeadline: Double?
    public var isIdle: Bool { state == .idle }

    private enum State {
        case idle, pending, dragging, hovering, waitLift
        case twoFinger, scrolling, pinching, rotating, swiping, momentum
    }
    private var state = State.idle

    // One finger
    private var start = CGPoint.zero
    private var last = CGPoint.zero
    private var t0 = 0.0
    private var trackedID = -1
    private var dragClicks = 1
    private var lastTapTime = -Double.infinity
    private var lastTapPoint = CGPoint.zero
    private var tapCount = 0

    // Several fingers
    private var count = 0
    private var maxFingers = 0
    private var anchor = Geometry.zero
    private var prev = Geometry.zero
    private var prevTime = 0.0
    private var begun = false
    private var velocity = CGVector.zero
    private var zoomAnchor = 0.0
    private var momentumTime = 0.0

    public init(settings: TouchSettings = TouchSettings()) {
        self.settings = settings
    }

    private var tun: GestureTunables { settings.tunables }
    private var on: GestureToggles { settings.gestures }

    public func update(_ contacts: [Contact], at t: Double) -> [GestureOutput] {
        var out: [GestureOutput] = []
        if state == .momentum {
            guard !contacts.isEmpty else { return out }
            out.append(.scroll(dx: 0, dy: 0, phase: nil, momentum: .end))
            state = .idle
        }
        let n = contacts.count
        switch state {
        case .idle, .momentum:
            if n == 1 { beginPending(contacts[0], t, &out) } else if n >= 2 { beginMulti(contacts, t, &out) }

        case .pending:
            if n == 0 {
                if on.tap { out.append(.leftClick(start, clicks: nextClickCount(at: start, t))) }
                state = .idle
            } else if n >= 2 {
                beginMulti(contacts, t, &out)
            } else {
                last = tracked(contacts)
                if distance(last, start) > tun.moveThreshold {
                    if on.drag {
                        beginDrag(t, &out)
                    } else {
                        state = .hovering
                        out.append(.move(last))
                    }
                }
            }

        case .dragging:
            if n == 0 {
                out.append(.leftUp(last, clicks: dragClicks))
                state = .idle
            } else {
                let p = tracked(contacts)
                if p != last {
                    last = p
                    out.append(.leftDragged(p, clicks: dragClicks))
                }
            }

        case .hovering:
            if n == 0 {
                state = .idle
            } else {
                let p = tracked(contacts)
                if p != last {
                    last = p
                    out.append(.move(p))
                }
            }

        case .waitLift:
            if n == 0 { state = .idle }

        case .twoFinger, .scrolling, .pinching, .rotating:
            updateTwoFinger(contacts, t, &out)

        case .swiping:
            updateSwipe(contacts, &out)
        }
        updateDeadline()
        return out
    }

    public func tick(at t: Double) -> [GestureOutput] {
        var out: [GestureOutput] = []
        switch state {
        case .pending:
            if on.longPress, t >= t0 + tun.longPressDelay {
                out.append(.rightClick(start))
                state = .waitLift
            } else if !on.longPress, on.drag, t >= t0 + tun.holdDelay {
                // Many panels stop reporting a finger that holds still; start the drag anyway.
                beginDrag(t, &out)
            }
        case .momentum:
            stepMomentum(t, &out)
        default:
            break
        }
        updateDeadline()
        return out
    }

    /// Closes any open button, scroll or gesture (unplug, pause, quit).
    public func reset() -> [GestureOutput] {
        var out: [GestureOutput] = []
        switch state {
        case .dragging: out.append(.leftUp(last, clicks: dragClicks))
        case .scrolling: if begun { out.append(.scroll(dx: 0, dy: 0, phase: .ended, momentum: .none)) }
        case .momentum: out.append(.scroll(dx: 0, dy: 0, phase: nil, momentum: .end))
        case .pinching: if begun && tun.pinchMode == .native { out.append(.magnify(0, .ended)) }
        case .rotating: if begun { out.append(.rotate(0, .ended)) }
        default: break
        }
        state = .idle
        nextDeadline = nil
        return out
    }

    // MARK: One finger

    private func beginPending(_ c: Contact, _ t: Double, _ out: inout [GestureOutput]) {
        state = .pending
        start = c.p
        last = c.p
        trackedID = c.id
        t0 = t
        out.append(.move(c.p))
    }

    private func beginDrag(_ t: Double, _ out: inout [GestureOutput]) {
        dragClicks = nextClickCount(at: start, t)
        out.append(.leftDown(start, clicks: dragClicks))
        if last != start { out.append(.leftDragged(last, clicks: dragClicks)) }
        state = .dragging
    }

    private func tracked(_ contacts: [Contact]) -> CGPoint {
        (contacts.first { $0.id == trackedID } ?? contacts[0]).p
    }

    /// 1 for a single click, 2 for a double-click, and so on.
    private func nextClickCount(at p: CGPoint, _ t: Double) -> Int {
        if t - lastTapTime < tun.doubleTapInterval && distance(p, lastTapPoint) < tun.doubleTapDistance {
            tapCount += 1
        } else {
            tapCount = 1
        }
        lastTapTime = t
        lastTapPoint = p
        return tapCount
    }

    // MARK: Several fingers

    private func beginMulti(_ cs: [Contact], _ t: Double, _ out: inout [GestureOutput]) {
        let g = Geometry(cs)
        t0 = t
        count = cs.count
        maxFingers = cs.count
        anchor = g
        prev = g
        prevTime = t
        begun = false
        velocity = .zero
        zoomAnchor = g.d
        // Scroll and gestures go to the window under the pointer.
        out.append(.move(g.c))
        state = .twoFinger
        if cs.count >= 3 { beginSwipe() }
    }

    private func beginSwipe() {
        state = on.threeFingerSwipe ? .swiping : .waitLift
        anchor = prev
    }

    private func updateTwoFinger(_ cs: [Contact], _ t: Double, _ out: inout [GestureOutput]) {
        let n = cs.count
        if n == 0 {
            endTwoFinger(t, &out)
            return
        }
        maxFingers = max(maxFingers, n)
        if n == 1 {
            // Wait for the rest to lift.
            count = 1
            return
        }
        let g = Geometry(cs)
        if n != count {
            // Finger count changed: re-anchor so values don't jump.
            count = n
            prev = g
            prevTime = t
            if state == .twoFinger {
                anchor = g
                zoomAnchor = g.d
                if n >= 3 { beginSwipe() }
            } else if n >= 3, on.threeFingerSwipe, t - t0 < tun.swipeLateFingerWindow {
                // Fingers rarely land together: a third one soon after the first two
                // means a swipe, even if the two already started scrolling or pinching.
                out += reset()
                state = .twoFinger
                beginSwipe()
            }
            return
        }
        if state == .twoFinger { lock(g) }
        switch state {
        case .scrolling: scroll(g, t, &out)
        case .pinching: pinch(g, &out)
        case .rotating: rotate(g, &out)
        default: break
        }
        prev = g
        prevTime = t
    }

    /// Picks the dominant 2-finger gesture once movement passes the lock threshold.
    private func lock(_ g: Geometry) {
        let translation = distance(g.c, anchor.c)
        let spread = abs(g.d - anchor.d)
        let twist = angleDelta(g.a, anchor.a)
        let arc = abs(twist) * g.d / 2
        guard max(translation, spread, arc) > tun.gestureLockThreshold else { return }

        var options: [(State, Double)] = []
        if on.scroll { options.append((.scrolling, translation)) }
        if on.pinch { options.append((.pinching, spread)) }
        if on.rotate, tun.pinchMode == .native, abs(twist) * 180 / .pi > tun.rotateMinDegrees {
            options.append((.rotating, arc))
        }
        if !on.scroll && !on.pinch && !on.rotate {
            state = .waitLift
            return
        }
        guard let best = options.max(by: { $0.1 < $1.1 }), best.1 > tun.gestureLockThreshold else { return }
        state = best.0
        zoomAnchor = anchor.d
    }

    private func scroll(_ g: Geometry, _ t: Double, _ out: inout [GestureOutput]) {
        let k = tun.scrollSpeed * (tun.reverseScroll ? -1 : 1)
        let dx = Double(g.c.x - prev.c.x) * k
        let dy = Double(g.c.y - prev.c.y) * k
        let dt = t - prevTime
        if dt > 0 {
            velocity = CGVector(dx: 0.6 * dx / dt + 0.4 * velocity.dx, dy: 0.6 * dy / dt + 0.4 * velocity.dy)
        }
        guard dx != 0 || dy != 0 || !begun else { return }
        out.append(.scroll(dx: dx, dy: dy, phase: begun ? .changed : .began, momentum: .none))
        begun = true
    }

    private func pinch(_ g: Geometry, _ out: inout [GestureOutput]) {
        if tun.pinchMode == .native {
            guard prev.d > 0 else { return }
            out.append(.magnify((g.d / prev.d - 1) * tun.pinchSensitivity, begun ? .changed : .began))
            begun = true
        } else {
            guard zoomAnchor > 0 else { return }
            let step = 1 + (tun.keyZoomStep - 1) / max(tun.pinchSensitivity, 0.01)
            while g.d / zoomAnchor >= step {
                out.append(.zoomKey(zoomIn: true))
                zoomAnchor *= step
            }
            while g.d / zoomAnchor <= 1 / step {
                out.append(.zoomKey(zoomIn: false))
                zoomAnchor /= step
            }
        }
    }

    private func rotate(_ g: Geometry, _ out: inout [GestureOutput]) {
        // Screen y points down, so a visually anticlockwise twist lowers the angle.
        let degrees = -angleDelta(g.a, prev.a) * 180 / .pi
        out.append(.rotate(degrees, begun ? .changed : .began))
        begun = true
    }

    private func endTwoFinger(_ t: Double, _ out: inout [GestureOutput]) {
        let ended = state
        state = .idle
        switch ended {
        case .twoFinger:
            if on.twoFingerTap, maxFingers == 2, t - t0 < tun.twoFingerTapMax {
                out.append(.rightClick(prev.c))
            }
        case .scrolling:
            guard begun else { return }
            out.append(.scroll(dx: 0, dy: 0, phase: .ended, momentum: .none))
            let speed = hypot(velocity.dx, velocity.dy)
            if tun.momentum, speed > tun.momentumMinVelocity, t - prevTime < 0.1 {
                out.append(.scroll(dx: velocity.dx / 60, dy: velocity.dy / 60, phase: nil, momentum: .begin))
                momentumTime = t
                state = .momentum
            }
        case .pinching:
            if begun && tun.pinchMode == .native { out.append(.magnify(0, .ended)) }
        case .rotating:
            if begun { out.append(.rotate(0, .ended)) }
        default:
            break
        }
    }

    private func stepMomentum(_ t: Double, _ out: inout [GestureOutput]) {
        let frame = 1.0 / 60
        if t - momentumTime > 1 {
            // Woke up late (e.g. after sleep): just stop.
            out.append(.scroll(dx: 0, dy: 0, phase: nil, momentum: .end))
            state = .idle
            return
        }
        var dx = 0.0, dy = 0.0
        while momentumTime + frame <= t + 1e-6 {
            momentumTime += frame
            velocity.dx *= tun.momentumDecay
            velocity.dy *= tun.momentumDecay
            if hypot(velocity.dx, velocity.dy) < tun.momentumStopVelocity {
                if dx != 0 || dy != 0 { out.append(.scroll(dx: dx, dy: dy, phase: nil, momentum: .continue)) }
                out.append(.scroll(dx: 0, dy: 0, phase: nil, momentum: .end))
                state = .idle
                return
            }
            dx += velocity.dx * frame
            dy += velocity.dy * frame
        }
        if dx != 0 || dy != 0 { out.append(.scroll(dx: dx, dy: dy, phase: nil, momentum: .continue)) }
    }

    private func updateSwipe(_ cs: [Contact], _ out: inout [GestureOutput]) {
        if cs.isEmpty {
            state = .idle
            return
        }
        let c = Geometry.centroid(cs)
        if cs.count != count {
            // Keep the distance travelled so far when the finger count changes.
            anchor.c = CGPoint(x: anchor.c.x + c.x - prev.c.x, y: anchor.c.y + c.y - prev.c.y)
            count = cs.count
        }
        prev.c = c
        let dx = c.x - anchor.c.x
        let dy = c.y - anchor.c.y
        guard cs.count >= 3, hypot(dx, dy) > tun.swipeDistance else { return }
        let direction: SwipeDirection = abs(dx) > abs(dy) ? (dx < 0 ? .left : .right) : (dy < 0 ? .up : .down)
        out.append(.swipe(direction))
        state = .waitLift
    }

    private func updateDeadline() {
        switch state {
        case .pending:
            if on.longPress { nextDeadline = t0 + tun.longPressDelay }
            else if on.drag { nextDeadline = t0 + tun.holdDelay }
            else { nextDeadline = nil }
        case .momentum:
            nextDeadline = momentumTime + 1.0 / 60
        default:
            nextDeadline = nil
        }
    }
}

private struct Geometry {
    var c: CGPoint   // centroid of all fingers
    var d: Double    // distance between the first two fingers
    var a: Double    // angle between them, radians

    static let zero = Geometry(c: .zero, d: 0, a: 0)

    init(c: CGPoint, d: Double, a: Double) {
        self.c = c
        self.d = d
        self.a = a
    }

    init(_ cs: [Contact]) {
        c = Geometry.centroid(cs)
        let two = cs.sorted { $0.id < $1.id }.prefix(2).map(\.p)
        if two.count == 2 {
            d = distance(two[0], two[1])
            a = atan2(two[1].y - two[0].y, two[1].x - two[0].x)
        } else {
            d = 0
            a = 0
        }
    }

    static func centroid(_ cs: [Contact]) -> CGPoint {
        let n = CGFloat(cs.count)
        return CGPoint(x: cs.reduce(0) { $0 + $1.p.x } / n, y: cs.reduce(0) { $0 + $1.p.y } / n)
    }
}

private func distance(_ p: CGPoint, _ q: CGPoint) -> Double {
    hypot(p.x - q.x, p.y - q.y)
}

/// a − b, wrapped to −π…π.
private func angleDelta(_ a: Double, _ b: Double) -> Double {
    var d = a - b
    while d > .pi { d -= 2 * .pi }
    while d < -.pi { d += 2 * .pi }
    return d
}
