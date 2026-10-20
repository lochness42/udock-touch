import AppKit
import QuartzCore
import TouchCore

/// Draws a short ripple where each finger lands, in a click-through window over the touch display.
@MainActor
final class TouchFeedback {
    private var window: NSWindow?
    private var activeIDs: Set<Int> = []

    func show(_ contacts: [TouchContact], settings: TouchSettings, bounds: CGRect, screen: NSScreen) {
        let ids = Set(contacts.map(\.id))
        defer { activeIDs = ids }
        let landed = contacts.filter { !activeIDs.contains($0.id) }
        guard !landed.isEmpty else { return }
        let w = window(on: screen)
        guard let layer = w.contentView?.layer else { return }
        for c in landed {
            // Global CG coordinates are top-left based; the layer is bottom-left.
            let p = TouchMapper.screenPoint(c, settings: settings, bounds: bounds)
            ripple(in: layer, at: CGPoint(x: p.x - bounds.minX, y: bounds.maxY - p.y))
        }
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        activeIDs = []
    }

    private func window(on screen: NSScreen) -> NSWindow {
        if let w = window {
            if w.frame != screen.frame { w.setFrame(screen.frame, display: false) }
            return w
        }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        w.contentView = view
        w.setFrame(screen.frame, display: false)
        w.orderFrontRegardless()
        window = w
        return w
    }

    private func ripple(in parent: CALayer, at p: CGPoint) {
        let size = 56.0
        let ring = CAShapeLayer()
        ring.frame = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        ring.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
        ring.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        ring.strokeColor = NSColor.controlAccentColor.cgColor
        ring.lineWidth = 2
        ring.opacity = 0
        parent.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.4
        scale.toValue = 1.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.4
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "ripple")
        CATransaction.commit()
    }
}
