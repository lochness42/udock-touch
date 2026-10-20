import CoreGraphics

extension Calibration {
    /// x' = a·x + c·y + tx,  y' = b·x + d·y + ty
    public func apply(_ p: CGPoint) -> CGPoint {
        CGPoint(x: a * p.x + c * p.y + tx, y: b * p.x + d * p.y + ty)
    }

    /// Least-squares affine transform taking `measured` points onto `targets`. Needs 3+ points
    /// that aren't all on one line.
    public static func fit(measured: [CGPoint], targets: [CGPoint]) -> Calibration? {
        guard measured.count == targets.count, measured.count >= 3 else { return nil }
        var sxx = 0.0, sxy = 0.0, syy = 0.0, sx = 0.0, sy = 0.0
        var rx = [0.0, 0.0, 0.0], ry = [0.0, 0.0, 0.0]
        for (m, t) in zip(measured, targets) {
            let x = Double(m.x), y = Double(m.y)
            sxx += x * x; sxy += x * y; syy += y * y; sx += x; sy += y
            rx[0] += x * t.x; rx[1] += y * t.x; rx[2] += t.x
            ry[0] += x * t.y; ry[1] += y * t.y; ry[2] += t.y
        }
        let m = [[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, Double(measured.count)]]
        guard let px = solve3(m, rx), let py = solve3(m, ry) else { return nil }
        var k = Calibration()
        (k.a, k.c, k.tx) = (px[0], px[1], px[2])
        (k.b, k.d, k.ty) = (py[0], py[1], py[2])
        return k
    }

    /// Largest distance between a transformed measured point and its target.
    public func maxError(measured: [CGPoint], targets: [CGPoint]) -> Double {
        zip(measured, targets).map { m, t in
            let p = apply(m)
            return hypot(p.x - t.x, p.y - t.y)
        }.max() ?? 0
    }
}

/// Solves m·v = r for a 3×3 system by Cramer's rule.
private func solve3(_ m: [[Double]], _ r: [Double]) -> [Double]? {
    func det(_ a: [[Double]]) -> Double {
        a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
            - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
            + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
    }
    let d = det(m)
    guard abs(d) > 1e-12 else { return nil }
    return (0..<3).map { col in
        var a = m
        for row in 0..<3 { a[row][col] = r[row] }
        return det(a) / d
    }
}

extension Orientation {
    /// Works out swap/flip from raw taps on the screen's top-left and top-right targets.
    public static func infer(topLeft a: TouchContact, topRight b: TouchContact) -> Orientation {
        var o = Orientation()
        o.swapXY = abs(b.y - a.y) > abs(b.x - a.x)
        let ax = o.swapXY ? a.y : a.x
        let ay = o.swapXY ? a.x : a.y
        let bx = o.swapXY ? b.y : b.x
        o.flipX = bx < ax
        o.flipY = ay > 0.5
        return o
    }
}
