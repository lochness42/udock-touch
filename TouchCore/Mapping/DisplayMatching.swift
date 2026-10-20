import Foundation

public struct DisplayCandidate: Equatable, Sendable {
    public var identity: DisplayIdentity
    public var isBuiltin: Bool

    public init(identity: DisplayIdentity, isBuiltin: Bool) {
        self.identity = identity
        self.isBuiltin = isBuiltin
    }
}

public enum DisplayMatching {
    /// Index of the display the touchscreen belongs to: the saved one (exact, then same
    /// vendor and model), else the first external display, else the first display.
    public static func pick(saved: DisplayIdentity?, from candidates: [DisplayCandidate]) -> Int? {
        if let s = saved {
            if let i = candidates.firstIndex(where: { $0.identity == s }) { return i }
            if let i = candidates.firstIndex(where: { $0.identity.vendor == s.vendor && $0.identity.model == s.model }) {
                return i
            }
        }
        if let i = candidates.firstIndex(where: { !$0.isBuiltin }) { return i }
        return candidates.isEmpty ? nil : 0
    }
}
