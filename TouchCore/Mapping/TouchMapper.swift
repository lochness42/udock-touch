import CoreGraphics

/// A touch in normalised panel coordinates (0–1, origin top-left), as the panel reports it.
public struct TouchContact: Codable, Equatable, Sendable {
    public var id: Int
    public var x: Double
    public var y: Double

    public init(id: Int, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public enum TouchMapper {
    /// Raw panel point with swap/flip applied, still normalised.
    public static func oriented(_ c: TouchContact, _ o: Orientation) -> CGPoint {
        var x = c.x
        var y = c.y
        if o.swapXY { swap(&x, &y) }
        if o.flipX { x = 1 - x }
        if o.flipY { y = 1 - y }
        return CGPoint(x: x, y: y)
    }

    /// Orientation then calibration, clamped to 0–1.
    public static func normalized(_ c: TouchContact, settings: TouchSettings) -> CGPoint {
        let p = settings.calibration.apply(oriented(c, settings.orientation))
        return CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }

    /// Normalised → orientation → calibration → global screen point inside `bounds`.
    public static func screenPoint(_ c: TouchContact, settings: TouchSettings, bounds: CGRect) -> CGPoint {
        let p = normalized(c, settings: settings)
        return CGPoint(x: bounds.minX + p.x * (bounds.width - 1), y: bounds.minY + p.y * (bounds.height - 1))
    }
}
