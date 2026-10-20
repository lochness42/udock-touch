import CoreGraphics
import Foundation

public protocol EventPoster: AnyObject {
    func post(_ output: GestureOutput)
    /// Releases a held mouse button, if any.
    func releaseAll()
}

/// Posts gesture outputs as system events. Needs Accessibility permission.
public final class CGEventPoster: EventPoster {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var leftHeld: CGPoint?
    private var remainder = CGVector.zero

    public init() {}

    public func post(_ output: GestureOutput) {
        switch output {
        case .move(let p):
            mouse(.mouseMoved, p)
        case .leftDown(let p, let clicks):
            mouse(.leftMouseDown, p, clicks: clicks)
            leftHeld = p
        case .leftDragged(let p, let clicks):
            mouse(.leftMouseDragged, p, clicks: clicks)
            leftHeld = p
        case .leftUp(let p, let clicks):
            mouse(.leftMouseUp, p, clicks: clicks)
            leftHeld = nil
        case .leftClick(let p, let clicks):
            mouse(.mouseMoved, p)
            mouse(.leftMouseDown, p, clicks: clicks)
            mouse(.leftMouseUp, p, clicks: clicks)
        case .rightClick(let p):
            mouse(.mouseMoved, p)
            mouse(.rightMouseDown, p, button: .right)
            mouse(.rightMouseUp, p, button: .right)
        case .scroll(let dx, let dy, let phase, let momentum):
            scroll(dx, dy, phase, momentum)
        case .magnify(let value, let phase):
            gesture(subtype: 8, phase: phase, valueField: 113, value: value)
        case .rotate(let degrees, let phase):
            gesture(subtype: 5, phase: phase, valueField: 114, value: degrees)
        case .zoomKey(let zoomIn):
            key(zoomIn ? 24 : 27, flags: .maskCommand)   // = / -
        case .swipe(let direction):
            swipe(direction)
        }
    }

    private func swipe(_ direction: SwipeDirection) {
        let log = TouchLog.shared
        switch direction {
        case .up:
            if Dock.send("com.apple.expose.awake") { return }
            log.debug("CoreDock unavailable; using Ctrl+↑ for Mission Control")
        case .down:
            if Dock.send("com.apple.expose.front.awake") { return }
            log.debug("CoreDock unavailable; using Ctrl+↓ for App Exposé")
        default:
            break
        }
        // Content follows the fingers: swiping left shows the Space on the right.
        let code: CGKeyCode
        switch direction {
        case .left: code = 124
        case .right: code = 123
        case .up: code = 126
        case .down: code = 125
        }
        controlArrow(code)
    }

    /// System shortcuts only fire when Control itself is pressed, not just flagged on the arrow.
    private func controlArrow(_ code: CGKeyCode) {
        let control: CGKeyCode = 59
        let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
        let sequence: [(CGKeyCode, Bool, CGEventFlags)] = [
            (control, true, .maskControl),
            (code, true, arrowFlags),
            (code, false, arrowFlags),
            (control, false, []),
        ]
        for (key, down, flags) in sequence {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }

    public func releaseAll() {
        if let p = leftHeld {
            mouse(.leftMouseUp, p)
            leftHeld = nil
        }
    }

    private func mouse(_ type: CGEventType, _ p: CGPoint, button: CGMouseButton = .left, clicks: Int = 1) {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button)
        else { return }
        e.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
        e.post(tap: .cghidEventTap)
    }

    private func scroll(_ dx: Double, _ dy: Double, _ phase: GesturePhase?, _ momentum: MomentumPhase) {
        remainder.dx += dx
        remainder.dy += dy
        let ix = remainder.dx.rounded(.towardZero)
        let iy = remainder.dy.rounded(.towardZero)
        remainder.dx -= ix
        remainder.dy -= iy
        let boundary = phase == .began || phase == .ended || momentum == .begin || momentum == .end
        if phase == .ended || momentum == .end { remainder = .zero }
        guard ix != 0 || iy != 0 || boundary else { return }
        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                              wheel1: Int32(iy), wheel2: Int32(ix), wheel3: 0)
        else { return }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase?.rawValue ?? 0))
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue))
        e.post(tap: .cghidEventTap)
    }

    /// Undocumented NSEventTypeGesture events (magnify / rotate).
    private func gesture(subtype: Int64, phase: GesturePhase, valueField: UInt32, value: Double) {
        guard let e = CGEvent(source: nil) else { return }
        e.setIntegerValueField(rawField(55), value: 29)
        e.setIntegerValueField(rawField(110), value: subtype)
        e.setIntegerValueField(rawField(132), value: Int64(phase.rawValue))
        e.setDoubleValueField(rawField(valueField), value: value)
        e.post(tap: .cghidEventTap)
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }

    private func rawField(_ n: UInt32) -> CGEventField {
        unsafeBitCast(n, to: CGEventField.self)
    }
}
