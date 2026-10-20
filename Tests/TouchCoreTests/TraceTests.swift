import CoreGraphics
import XCTest
@testable import TouchCore

/// Replays every trace in Tests/Traces and checks it produces the gesture it was labelled with.
final class RecordedTraceTests: XCTestCase {
    func testRecordedTracesMatchTheirLabels() throws {
        let urls = Bundle(for: Self.self).urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let traces = try urls.map { ($0.lastPathComponent, try TouchTrace.decode(Data(contentsOf: $0))) }
        try XCTSkipIf(traces.isEmpty, "No traces in Tests/Traces")
        for (file, trace) in traces.sorted(by: { $0.0 < $1.0 }) {
            let outputs = TraceReplay.run(trace)
            XCTAssertFalse(outputs.contains { if case .leftDown = $0 { return true } else { return false } }
                           && !outputs.contains { if case .leftUp = $0 { return true } else { return false } },
                           "\(file): left button left held")
            if let expected = trace.expected {
                XCTAssertEqual(TraceReplay.summary(outputs), expected, file)
            }
        }
    }
}

final class TraceReplayTests: XCTestCase {
    private func trace(_ frames: [(Double, [(Int, Double, Double)])], expected: [String]? = nil) -> TouchTrace {
        TouchTrace(name: "synthetic", expected: expected, recordedAt: Date(timeIntervalSince1970: 1_800_000_000),
                   screenSize: CGSize(width: 1920, height: 1080),
                   orientation: nil, calibration: nil,
                   frames: frames.map { t, cs in TraceFrame(t: t, contacts: cs.map { TouchContact(id: $0.0, x: $0.1, y: $0.2) }) })
    }

    func testTapReplays() {
        let t = trace([(0, [(1, 0.5, 0.5)]), (0.05, [(1, 0.5, 0.5)]), (0.1, [])])
        XCTAssertEqual(TraceReplay.summary(TraceReplay.run(t)), ["click"])
    }

    func testLongPressFiresTimerBetweenFrames() {
        // The panel goes quiet while the finger rests; the lift comes 1 s later.
        let t = trace([(0, [(1, 0.5, 0.5)]), (1.0, [])])
        XCTAssertEqual(TraceReplay.summary(TraceReplay.run(t)), ["right-click"])
    }

    func testUnplugDuringDragReleasesButton() {
        let t = trace([(0, [(1, 0.5, 0.5)]), (0.05, [(1, 0.6, 0.5)])])
        XCTAssertEqual(TraceReplay.run(t).last, .leftUp(CGPoint(x: 0.6 * 1919, y: 0.5 * 1079), clicks: 1))
    }

    func testDoubleTapThenDragIsDoubleClickDrag() {
        let t = trace([(0, [(1, 0.5, 0.5)]), (0.05, []), (0.2, [(2, 0.5, 0.5)]), (0.25, [(2, 0.6, 0.5)]), (0.3, [])])
        let outputs = TraceReplay.run(t)
        XCTAssertTrue(outputs.contains(.leftDown(CGPoint(x: 0.5 * 1919, y: 0.5 * 1079), clicks: 2)), "\(outputs)")
    }

    func testRoundTripsThroughJSON() throws {
        let t = trace([(0, [(1, 0.25, 0.75)]), (0.1, [])], expected: ["click"])
        XCTAssertEqual(try TouchTrace.decode(t.encoded()), t)
    }
}

final class CalibrationTests: XCTestCase {
    let targets = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9)]

    func testFitRecoversOffsetAndScale() throws {
        // Panel reads 5% too wide and 0.02 too low.
        let measured = targets.map { CGPoint(x: $0.x * 1.05, y: $0.y + 0.02) }
        let k = try XCTUnwrap(Calibration.fit(measured: measured, targets: targets))
        XCTAssertLessThan(k.maxError(measured: measured, targets: targets), 1e-9)
        XCTAssertEqual(k.apply(CGPoint(x: 0.525, y: 0.52)).x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(k.apply(CGPoint(x: 0.525, y: 0.52)).y, 0.5, accuracy: 1e-9)
    }

    func testFitRejectsCollinearPoints() {
        let line = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.9, y: 0.9)]
        XCTAssertNil(Calibration.fit(measured: line, targets: line))
    }

    func testMistapShowsLargeError() throws {
        var measured = targets
        measured[2] = CGPoint(x: 0.5, y: 0.5)
        let k = try XCTUnwrap(Calibration.fit(measured: measured, targets: targets))
        XCTAssertGreaterThan(k.maxError(measured: measured, targets: targets), 0.05)
    }

    func testInferOrientation() {
        func raw(_ o: Orientation) -> (TouchContact, TouchContact) {
            // The raw points that this orientation maps onto the two screen targets.
            func invert(_ p: (Double, Double)) -> TouchContact {
                var (x, y) = p
                if o.flipY { y = 1 - y }
                if o.flipX { x = 1 - x }
                if o.swapXY { swap(&x, &y) }
                return TouchContact(id: 0, x: x, y: y)
            }
            return (invert((0.1, 0.1)), invert((0.9, 0.1)))
        }
        for swapXY in [false, true] {
            for flipX in [false, true] {
                for flipY in [false, true] {
                    var o = Orientation()
                    (o.swapXY, o.flipX, o.flipY) = (swapXY, flipX, flipY)
                    let (a, b) = raw(o)
                    XCTAssertEqual(Orientation.infer(topLeft: a, topRight: b), o)
                    XCTAssertEqual(TouchMapper.oriented(a, o).x, 0.1, accuracy: 1e-9)
                }
            }
        }
    }
}
