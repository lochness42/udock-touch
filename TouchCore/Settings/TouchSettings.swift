import Foundation

/// Identifies a display across reconnects (CGDisplayVendorNumber / ModelNumber / SerialNumber).
public struct DisplayIdentity: Codable, Hashable, Sendable {
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32

    public init(vendor: UInt32, model: UInt32, serial: UInt32) {
        self.vendor = vendor
        self.model = model
        self.serial = serial
    }
}

/// Identifies a touch device when more than one is connected.
public struct DeviceIdentity: Codable, Hashable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var serial: String

    public init(vendorID: Int, productID: Int, serial: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.serial = serial
    }
}

public enum PinchMode: String, Codable, CaseIterable, Sendable {
    case native   // magnify / rotate gesture events
    case keys     // Cmd+= / Cmd+-
}

public struct Orientation: Codable, Equatable, Sendable {
    public var swapXY = false
    public var flipX = false
    public var flipY = false
    public init() {}
}

/// Affine transform applied to normalised (0–1) coordinates after orientation.
public struct Calibration: Codable, Equatable, Sendable {
    public var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0
    public init() {}
    public static let identity = Calibration()
}

public struct GestureToggles: Codable, Equatable, Sendable {
    public var tap = true
    public var drag = true
    public var longPress = true
    public var twoFingerTap = true
    public var scroll = true
    public var pinch = true
    public var rotate = true
    public var threeFingerSwipe = true
    public init() {}
}

/// Every gesture threshold in one place. Distances are in points, times in seconds.
public struct GestureTunables: Codable, Equatable, Sendable {
    public var moveThreshold = 10.0
    public var holdDelay = 0.12
    public var doubleTapInterval = 0.4
    public var doubleTapDistance = 30.0
    public var longPressDelay = 0.6
    public var twoFingerTapMax = 0.35
    public var gestureLockThreshold = 12.0
    public var scrollSpeed = 1.0
    public var reverseScroll = false
    public var momentum = true
    public var momentumMinVelocity = 150.0
    public var momentumDecay = 0.95
    public var momentumStopVelocity = 40.0
    public var pinchSensitivity = 1.0
    public var pinchMode = PinchMode.native
    public var keyZoomStep = 1.25
    public var rotateMinDegrees = 11.0
    public var swipeDistance = 60.0
    public var swipeLateFingerWindow = 0.3
    public init() {}
}

public struct TouchSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var display: DisplayIdentity?
    public var device: DeviceIdentity?
    public var seize = false
    public var orientation = Orientation()
    public var calibration = Calibration.identity
    public var gestures = GestureToggles()
    public var tunables = GestureTunables()
    public var debugLogging = false
    public var touchFeedback = false
    public init() {}
}

// MARK: - Persistence

extension TouchSettings {
    /// Decodes stored settings, filling keys missing from older versions with defaults.
    /// Unreadable data yields the defaults.
    public static func decode(_ data: Data?) -> TouchSettings {
        guard let data,
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(TouchSettings()),
              var merged = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any]
        else { return TouchSettings() }
        deepMerge(&merged, stored)
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let settings = try? JSONDecoder().decode(TouchSettings.self, from: mergedData)
        else { return TouchSettings() }
        return settings
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

private func deepMerge(_ base: inout [String: Any], _ over: [String: Any]) {
    for (key, value) in over {
        if var b = base[key] as? [String: Any], let o = value as? [String: Any] {
            deepMerge(&b, o)
            base[key] = b
        } else {
            base[key] = value
        }
    }
}
