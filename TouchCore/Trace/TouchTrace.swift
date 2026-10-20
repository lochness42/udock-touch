import CoreGraphics
import Foundation

public struct TraceFrame: Codable, Equatable, Sendable {
    public var t: Double                // seconds since recording started
    public var contacts: [TouchContact] // raw, normalised

    public init(t: Double, contacts: [TouchContact]) {
        self.t = t
        self.contacts = contacts
    }
}

/// A recording of raw touch frames, replayable through the recogniser.
public struct TouchTrace: Codable, Equatable, Sendable {
    public var name: String
    /// Gesture kinds the trace should produce (see `GestureOutput.kind`), or nil if free-form.
    public var expected: [String]?
    public var recordedAt: Date
    public var screenWidth: Double
    public var screenHeight: Double
    public var orientation: Orientation?
    public var calibration: Calibration?
    public var frames: [TraceFrame]

    public init(name: String, expected: [String]?, recordedAt: Date = Date(), screenSize: CGSize,
                orientation: Orientation?, calibration: Calibration?, frames: [TraceFrame]) {
        self.name = name
        self.expected = expected
        self.recordedAt = recordedAt
        screenWidth = Double(screenSize.width)
        screenHeight = Double(screenSize.height)
        self.orientation = orientation
        self.calibration = calibration
        self.frames = frames
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> TouchTrace {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(TouchTrace.self, from: data)
    }
}

public enum TraceReplay {
    /// Feeds the trace through a fresh recogniser using the current default tunables and the
    /// trace's own orientation and calibration. Fires timers exactly when they would have.
    public static func run(_ trace: TouchTrace, tunables: GestureTunables = GestureTunables()) -> [GestureOutput] {
        var settings = TouchSettings()
        settings.tunables = tunables
        settings.orientation = trace.orientation ?? Orientation()
        settings.calibration = trace.calibration ?? .identity
        let bounds = CGRect(x: 0, y: 0, width: trace.screenWidth, height: trace.screenHeight)
        let r = GestureRecognizer(settings: settings)
        var out: [GestureOutput] = []

        func runTimers(until t: Double) {
            while let d = r.nextDeadline, d <= t { out += r.tick(at: d) }
        }
        for frame in trace.frames {
            runTimers(until: frame.t)
            let contacts = frame.contacts.map {
                Contact(id: $0.id, p: TouchMapper.screenPoint($0, settings: settings, bounds: bounds))
            }
            out += r.update(contacts, at: frame.t)
        }
        runTimers(until: (trace.frames.last?.t ?? 0) + 10)
        out += r.reset()
        return out
    }

    /// The gesture kinds produced, with consecutive repeats collapsed.
    public static func summary(_ outputs: [GestureOutput]) -> [String] {
        var kinds: [String] = []
        for k in outputs.compactMap(\.kind) where kinds.last != k { kinds.append(k) }
        return kinds
    }
}

extension GestureOutput {
    /// Short name for what the user did, used to label and check traces.
    public var kind: String? {
        switch self {
        case .leftClick(_, let clicks): return clicks > 1 ? "double-click" : "click"
        case .leftDown: return "drag"
        case .rightClick: return "right-click"
        case .scroll(_, _, let phase, _): return phase == .began ? "scroll" : nil
        case .magnify(_, let phase): return phase == .began ? "pinch" : nil
        case .zoomKey: return "pinch"
        case .rotate(_, let phase): return phase == .began ? "rotate" : nil
        case .swipe(let d): return "swipe-\(d.rawValue)"
        default: return nil
        }
    }
}
