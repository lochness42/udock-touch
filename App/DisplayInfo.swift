import AppKit
import TouchCore

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let identity: DisplayIdentity
    let bounds: CGRect
    let isBuiltin: Bool

    var candidate: DisplayCandidate { DisplayCandidate(identity: identity, isBuiltin: isBuiltin) }
    var label: String { "\(name) (\(Int(bounds.width))×\(Int(bounds.height)))" }

    static func active() -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[n.uint32Value] = screen.localizedName
            }
        }

        return ids.prefix(Int(count)).map { id in
            DisplayInfo(
                id: id,
                name: names[id] ?? "Display \(id)",
                identity: DisplayIdentity(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                          serial: CGDisplaySerialNumber(id)),
                bounds: CGDisplayBounds(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0
            )
        }
    }
}
