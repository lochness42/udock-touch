import XCTest
@testable import TouchCore

final class TouchSettingsTests: XCTestCase {
    func testRoundTrip() {
        var s = TouchSettings()
        s.enabled = false
        s.display = DisplayIdentity(vendor: 1, model: 2, serial: 3)
        s.orientation.flipY = true
        s.tunables.pinchMode = .keys
        s.tunables.scrollSpeed = 2.5
        XCTAssertEqual(TouchSettings.decode(s.encoded()), s)
    }

    func testMissingKeysFallBackToDefaults() {
        let old = #"{"enabled": false, "tunables": {"scrollSpeed": 3}}"#.data(using: .utf8)!
        let s = TouchSettings.decode(old)
        XCTAssertFalse(s.enabled)
        XCTAssertEqual(s.tunables.scrollSpeed, 3)
        XCTAssertEqual(s.tunables.longPressDelay, GestureTunables().longPressDelay)
        XCTAssertEqual(s.gestures, GestureToggles())
    }

    func testUnreadableDataGivesDefaults() {
        XCTAssertEqual(TouchSettings.decode(nil), TouchSettings())
        XCTAssertEqual(TouchSettings.decode(Data("nope".utf8)), TouchSettings())
        XCTAssertEqual(TouchSettings.decode(Data(#"{"enabled": "yes"}"#.utf8)), TouchSettings())
    }
}

final class DisplayMatchingTests: XCTestCase {
    let builtin = DisplayCandidate(identity: DisplayIdentity(vendor: 0x610, model: 1, serial: 0), isBuiltin: true)
    let monitor = DisplayCandidate(identity: DisplayIdentity(vendor: 0x10AC, model: 5, serial: 9), isBuiltin: false)
    let udock = DisplayCandidate(identity: DisplayIdentity(vendor: 0x4C2D, model: 7, serial: 42), isBuiltin: false)

    func testExactMatch() {
        XCTAssertEqual(DisplayMatching.pick(saved: udock.identity, from: [builtin, monitor, udock]), 2)
    }

    func testSerialChangedStillMatchesVendorAndModel() {
        var saved = udock.identity
        saved.serial = 0
        XCTAssertEqual(DisplayMatching.pick(saved: saved, from: [builtin, monitor, udock]), 2)
    }

    func testDefaultsToFirstExternal() {
        XCTAssertEqual(DisplayMatching.pick(saved: nil, from: [builtin, monitor, udock]), 1)
        XCTAssertEqual(DisplayMatching.pick(saved: udock.identity, from: [builtin, monitor]), 1)
    }

    func testFallsBackToBuiltinOrNothing() {
        XCTAssertEqual(DisplayMatching.pick(saved: nil, from: [builtin]), 0)
        XCTAssertNil(DisplayMatching.pick(saved: nil, from: []))
    }
}
