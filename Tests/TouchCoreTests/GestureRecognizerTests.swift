import CoreGraphics
import XCTest
@testable import TouchCore

final class GestureRecognizerTests: XCTestCase {
    var r: GestureRecognizer!

    override func setUp() {
        r = GestureRecognizer()
    }

    private func c(_ id: Int, _ x: Double, _ y: Double) -> Contact {
        Contact(id: id, p: CGPoint(x: x, y: y))
    }

    func testTapClicks() {
        XCTAssertEqual(r.update([c(1, 100, 100)], at: 0), [.move(CGPoint(x: 100, y: 100))])
        XCTAssertEqual(r.update([c(1, 102, 101)], at: 0.05), [])
        XCTAssertEqual(r.update([], at: 0.1), [.leftClick(CGPoint(x: 100, y: 100), clicks: 1)])
        XCTAssertTrue(r.isIdle)
    }

    func testDoubleTap() {
        _ = r.update([c(1, 100, 100)], at: 0)
        _ = r.update([], at: 0.08)
        _ = r.update([c(2, 105, 103)], at: 0.2)
        XCTAssertEqual(r.update([], at: 0.28), [.leftClick(CGPoint(x: 105, y: 103), clicks: 2)])
    }

    func testDrag() {
        _ = r.update([c(1, 100, 100)], at: 0)
        XCTAssertEqual(r.update([c(1, 130, 100)], at: 0.05), [
            .leftDown(CGPoint(x: 100, y: 100), clicks: 1),
            .leftDragged(CGPoint(x: 130, y: 100), clicks: 1),
        ])
        XCTAssertEqual(r.update([c(1, 160, 100)], at: 0.1), [.leftDragged(CGPoint(x: 160, y: 100), clicks: 1)])
        XCTAssertEqual(r.update([], at: 0.15), [.leftUp(CGPoint(x: 160, y: 100), clicks: 1)])
    }

    func testLongPressRightClicksViaTick() {
        _ = r.update([c(1, 100, 100)], at: 0)
        XCTAssertEqual(r.nextDeadline, 0.6)
        XCTAssertEqual(r.tick(at: 0.3), [])
        XCTAssertEqual(r.tick(at: 0.61), [.rightClick(CGPoint(x: 100, y: 100))])
        XCTAssertEqual(r.update([], at: 1), [])
        XCTAssertTrue(r.isIdle)
    }

    func testHoldStartsDragWhenLongPressOff() {
        r.settings.gestures.longPress = false
        _ = r.update([c(1, 100, 100)], at: 0)
        XCTAssertEqual(r.tick(at: 0.13), [.leftDown(CGPoint(x: 100, y: 100), clicks: 1)])
    }

    func testTwoFingerTapRightClicksAtCentroid() {
        XCTAssertEqual(r.update([c(1, 100, 100), c(2, 200, 100)], at: 0), [.move(CGPoint(x: 150, y: 100))])
        _ = r.update([c(2, 200, 100)], at: 0.1)
        XCTAssertEqual(r.update([], at: 0.15), [.rightClick(CGPoint(x: 150, y: 100))])
    }

    func testSecondFingerDuringPendingBecomesTwoFinger() {
        _ = r.update([c(1, 100, 100)], at: 0)
        _ = r.update([c(1, 100, 100), c(2, 200, 100)], at: 0.03)
        _ = r.update([], at: 0.1)
        XCTAssertTrue(r.isIdle)
        XCTAssertNil(r.nextDeadline)
    }

    func testScrollPhasesAndNoMomentumWhenSlow() {
        _ = r.update([c(1, 100, 100), c(2, 200, 100)], at: 0)
        XCTAssertEqual(r.update([c(1, 100, 120), c(2, 200, 120)], at: 0.5),
                       [.scroll(dx: 0, dy: 20, phase: .began, momentum: .none)])
        XCTAssertEqual(r.update([c(1, 100, 125), c(2, 200, 125)], at: 1.0),
                       [.scroll(dx: 0, dy: 5, phase: .changed, momentum: .none)])
        XCTAssertEqual(r.update([c(1, 100, 128), c(2, 200, 128)], at: 1.5),
                       [.scroll(dx: 0, dy: 3, phase: .changed, momentum: .none)])
        XCTAssertEqual(r.update([], at: 1.55), [.scroll(dx: 0, dy: 0, phase: .ended, momentum: .none)])
        XCTAssertTrue(r.isIdle)
    }

    func testFlickStartsMomentumThatEnds() {
        _ = r.update([c(1, 100, 100), c(2, 200, 100)], at: 0)
        var y = 100.0
        var t = 0.0
        for _ in 0..<6 {
            y += 20
            t += 0.016
            _ = r.update([c(1, 100, y), c(2, 200, y)], at: t)
        }
        let end = r.update([], at: t + 0.01)
        XCTAssertEqual(end.first, .scroll(dx: 0, dy: 0, phase: .ended, momentum: .none))
        guard case .scroll(_, let dy, nil, .begin) = end.last else { return XCTFail("no momentum: \(end)") }
        XCTAssertGreaterThan(dy, 0)
        XCTAssertNotNil(r.nextDeadline)

        var outputs: [GestureOutput] = []
        var now = t
        while let d = r.nextDeadline, now < t + 5 {
            now = d
            outputs += r.tick(at: now)
        }
        XCTAssertEqual(outputs.last, .scroll(dx: 0, dy: 0, phase: nil, momentum: .end))
        XCTAssertTrue(r.isIdle)
    }

    func testTouchDuringMomentumStopsIt() {
        _ = r.update([c(1, 100, 100), c(2, 200, 100)], at: 0)
        for i in 1...6 { _ = r.update([c(1, 100, 100 + Double(i) * 20), c(2, 200, 100 + Double(i) * 20)], at: Double(i) * 0.016) }
        _ = r.update([], at: 0.1)
        let out = r.update([c(1, 50, 50)], at: 0.12)
        XCTAssertEqual(out.first, .scroll(dx: 0, dy: 0, phase: nil, momentum: .end))
        XCTAssertEqual(out.last, .move(CGPoint(x: 50, y: 50)))
    }

    func testPinchNativeMagnifies() {
        _ = r.update([c(1, 100, 100), c(2, 200, 100)], at: 0)
        let first = r.update([c(1, 80, 100), c(2, 220, 100)], at: 0.1)   // spread 40 locks
        guard case .magnify(let m0, .began) = first.first else { return XCTFail("\(first)") }
        XCTAssertEqual(m0, 0.4, accuracy: 1e-9)
        let out = r.update([c(1, 70, 100), c(2, 230, 100)], at: 0.2)
        guard case .magnify(let m, .changed) = out.first else { return XCTFail("\(out)") }
        XCTAssertEqual(m, 160.0 / 140.0 - 1, accuracy: 1e-9)
        XCTAssertEqual(r.update([], at: 0.3), [.magnify(0, .ended)])
    }

    func testPinchKeysMode() {
        r.settings.tunables.pinchMode = .keys
        _ = r.update([c(1, 100, 100), c(2, 200, 100)], at: 0)
        XCTAssertEqual(r.update([c(1, 80, 100), c(2, 220, 100)], at: 0.1), [.zoomKey(zoomIn: true)])   // 1.4× of 100
        XCTAssertEqual(r.update([c(1, 60, 100), c(2, 240, 100)], at: 0.2), [.zoomKey(zoomIn: true)])   // 1.44× of 125
    }

    func testRotateAnticlockwiseIsPositive() {
        _ = r.update([c(1, 100, 200), c(2, 300, 200)], at: 0)
        // Twist 20° anticlockwise as seen on screen, around a fixed centre.
        let a = 20.0 * .pi / 180
        let out = r.update([c(1, 200 - 100 * cos(a), 200 + 100 * sin(a)), c(2, 200 + 100 * cos(a), 200 - 100 * sin(a))], at: 0.1)
        guard case .rotate(let deg, .began) = out.first else { return XCTFail("\(out)") }
        XCTAssertEqual(deg, 20, accuracy: 1e-6)
    }

    func testThreeFingerSwipeFiresOnce() {
        _ = r.update([c(1, 100, 100), c(2, 150, 100), c(3, 200, 100)], at: 0)
        XCTAssertEqual(r.update([c(1, 60, 100), c(2, 110, 100), c(3, 160, 100)], at: 0.05), [])
        XCTAssertEqual(r.update([c(1, 30, 100), c(2, 80, 100), c(3, 130, 100)], at: 0.1), [.swipe(.left)])
        XCTAssertEqual(r.update([c(1, 0, 100), c(2, 50, 100), c(3, 100, 100)], at: 0.15), [])
        _ = r.update([], at: 0.2)
        XCTAssertTrue(r.isIdle)
    }

    func testLateThirdFingerTurnsScrollIntoSwipe() {
        _ = r.update([c(1, 100, 100), c(2, 150, 100)], at: 0)
        XCTAssertEqual(r.update([c(1, 85, 100), c(2, 135, 100)], at: 0.05).first,
                       .scroll(dx: -15, dy: 0, phase: .began, momentum: .none))
        XCTAssertEqual(r.update([c(1, 80, 100), c(2, 130, 100), c(3, 180, 100)], at: 0.1),
                       [.scroll(dx: 0, dy: 0, phase: .ended, momentum: .none)])
        XCTAssertEqual(r.update([c(1, 40, 100), c(2, 90, 100), c(3, 140, 100)], at: 0.15), [])
        XCTAssertEqual(r.update([c(1, 10, 100), c(2, 60, 100), c(3, 110, 100)], at: 0.2), [.swipe(.left)])
    }

    func testThirdFingerLongAfterScrollKeepsScrolling() {
        _ = r.update([c(1, 100, 100), c(2, 150, 100)], at: 0)
        _ = r.update([c(1, 100, 120), c(2, 150, 120)], at: 0.1)
        XCTAssertEqual(r.update([c(1, 100, 120), c(2, 150, 120), c(3, 300, 120)], at: 0.5), [])
        XCTAssertEqual(r.update([c(1, 100, 130), c(2, 150, 130), c(3, 300, 130)], at: 0.6),
                       [.scroll(dx: 0, dy: 10, phase: .changed, momentum: .none)])
    }

    func testFingerCountChangeDoesNotJump() {
        _ = r.update([c(1, 100, 100), c(2, 200, 100)], at: 0)
        _ = r.update([c(1, 100, 120), c(2, 200, 120)], at: 0.1)
        _ = r.update([c(1, 100, 125), c(2, 200, 125)], at: 0.2)
        // Third finger lands far away: centroid jumps, but no scroll should be emitted for it.
        XCTAssertEqual(r.update([c(1, 100, 125), c(2, 200, 125), c(3, 500, 600)], at: 0.3), [])
        XCTAssertEqual(r.update([c(1, 100, 128), c(2, 200, 128), c(3, 500, 603)], at: 0.4),
                       [.scroll(dx: 0, dy: 3, phase: .changed, momentum: .none)])
    }

    func testResetDuringDragReleasesButton() {
        _ = r.update([c(1, 100, 100)], at: 0)
        _ = r.update([c(1, 150, 100)], at: 0.05)
        XCTAssertEqual(r.reset(), [.leftUp(CGPoint(x: 150, y: 100), clicks: 1)])
        XCTAssertTrue(r.isIdle)
    }

    func testDisabledTapDoesNothing() {
        r.settings.gestures.tap = false
        _ = r.update([c(1, 100, 100)], at: 0)
        XCTAssertEqual(r.update([], at: 0.05), [])
    }
}

final class TouchMapperTests: XCTestCase {
    let bounds = CGRect(x: 1000, y: 0, width: 1921, height: 1081)

    func testIdentity() {
        XCTAssertEqual(TouchMapper.screenPoint(TouchContact(id: 0, x: 0.5, y: 1), settings: TouchSettings(), bounds: bounds),
                       CGPoint(x: 1960, y: 1080))
    }

    func testOrientation() {
        var s = TouchSettings()
        s.orientation.swapXY = true
        s.orientation.flipX = true
        let p = TouchMapper.screenPoint(TouchContact(id: 0, x: 0.25, y: 0), settings: s, bounds: bounds)
        XCTAssertEqual(p, CGPoint(x: 2920, y: 270))
    }
}
