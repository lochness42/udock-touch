import Foundation
import IOKit.hid

/// Reads one HID touch device and assembles complete frames of normalised contacts.
/// Handles "hybrid" panels that split fingers across several reports.
final class TouchFrameReader {
    struct Slot {
        let reportID: UInt32
        let order: UInt32
        var x: IOHIDElement?
        var y: IOHIDElement?
        var tip: IOHIDElement?
        var contactID: IOHIDElement?
    }

    let device: IOHIDDevice
    let info: HIDDeviceInfo
    private(set) var slots: [Slot] = []
    var active = false
    var onFrame: (([TouchContact]) -> Void)?

    private let log = TouchLog.shared
    private var countElements: [UInt32: IOHIDElement] = [:]   // reportID → Contact Count
    private var buffer: UnsafeMutablePointer<UInt8>?
    private var bufferSize = 0
    private let valuePtr = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)

    private var frameExpected = 0
    private var frameSeen = 0
    private var frame: [TouchContact] = []
    private var rawLogSecond = 0
    private var rawLogCount = 0

    init(device: IOHIDDevice) {
        self.device = device
        info = HIDDeviceInfo(device: device)
        parseElements()
    }

    deinit {
        valuePtr.deallocate()
        buffer?.deallocate()
    }

    var hasContactCount: Bool { !countElements.isEmpty }

    var layoutDescription: String {
        func range(_ e: IOHIDElement?) -> String {
            guard let e else { return "none" }
            return "\(IOHIDElementGetLogicalMin(e))…\(IOHIDElementGetLogicalMax(e))"
        }
        var lines = slots.map {
            "  report \($0.reportID) slot \($0.order): x \(range($0.x)) y \(range($0.y)) "
                + "tip \($0.tip == nil ? "no" : "yes") contactID \($0.contactID == nil ? "no" : "yes")"
        }
        lines.append("  contact count in reports: \(countElements.keys.sorted().map(String.init).joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }

    private static func isUnderTouchScreen(_ e: IOHIDElement) -> Bool {
        var p = IOHIDElementGetParent(e)
        while let c = p {
            if IOHIDElementGetUsagePage(c) == 0x0D && IOHIDElementGetUsage(c) == 0x04 { return true }
            p = IOHIDElementGetParent(c)
        }
        return false
    }

    private func parseElements() {
        let all = (IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []
        let restrict = all.contains(where: TouchFrameReader.isUnderTouchScreen)
        var byParent: [UInt32: Slot] = [:]

        for e in all {
            let t = IOHIDElementGetType(e).rawValue
            guard t >= 1 && t <= 3 else { continue }          // input misc / button / axis
            if restrict && !TouchFrameReader.isUnderTouchScreen(e) { continue }
            let page = IOHIDElementGetUsagePage(e)
            let use = IOHIDElementGetUsage(e)
            let reportID = IOHIDElementGetReportID(e)

            if page == 0x0D && use == 0x54 {                     // Contact Count
                countElements[reportID] = e
                continue
            }
            guard let parent = IOHIDElementGetParent(e) else { continue }
            let key = IOHIDElementGetCookie(parent)
            var s = byParent[key] ?? Slot(reportID: reportID, order: key)
            switch (page, use) {
            case (0x01, 0x30): s.x = e                           // X
            case (0x01, 0x31): s.y = e                           // Y
            case (0x0D, 0x42): s.tip = e                         // Tip Switch
            case (0x0D, 0x51): s.contactID = e                   // Contact Identifier
            default: continue
            }
            byParent[key] = s
        }
        slots = byParent.values
            .filter { $0.x != nil && $0.y != nil }
            .sorted { $0.order < $1.order }
    }

    func start() {
        guard buffer == nil else { return }
        bufferSize = max(IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64, 64)
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer!, bufferSize, { ctx, _, _, _, reportID, report, length in
            guard let ctx else { return }
            Unmanaged<TouchFrameReader>.fromOpaque(ctx).takeUnretainedValue()
                .handleReport(reportID: reportID, bytes: report, length: length)
        }, ctx)
    }

    func stop() {
        guard let buffer else { return }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
    }

    private func handleReport(reportID: UInt32, bytes: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        if log.debugEnabled { logRaw(reportID: reportID, bytes: bytes, length: length) }
        let reportSlots = slots.filter { $0.reportID == reportID }
        guard !reportSlots.isEmpty else { return }

        guard let countEl = countElements[reportID] else {
            // Simple panel: every report holds all fingers.
            frame = reportSlots.compactMap(contact)
            emit()
            return
        }

        let cc = value(countEl)
        if cc > 0 {
            frameExpected = cc
            frameSeen = 0
            frame = []
        } else if frameSeen >= frameExpected {
            frame = []                     // no touches
            emit()
            return
        }
        let take = max(0, min(reportSlots.count, frameExpected - frameSeen))
        for s in reportSlots.prefix(take) {
            frameSeen += 1
            if let c = contact(from: s) { frame.append(c) }
        }
        if frameSeen >= frameExpected { emit() }
    }

    /// At most 10 raw reports a second, so the log stays readable.
    private func logRaw(reportID: UInt32, bytes: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        let second = Int(ProcessInfo.processInfo.systemUptime)
        if second != rawLogSecond {
            rawLogSecond = second
            rawLogCount = 0
        }
        rawLogCount += 1
        guard rawLogCount <= 10 else { return }
        let hex = UnsafeBufferPointer(start: bytes, count: length).map { String(format: "%02x", $0) }.joined(separator: " ")
        log.debug("raw report id=\(reportID) len=\(length): \(hex)")
    }

    private func value(_ e: IOHIDElement) -> Int {
        guard IOHIDDeviceGetValue(device, e, valuePtr) == kIOReturnSuccess else { return 0 }
        return IOHIDValueGetIntegerValue(valuePtr.pointee.takeUnretainedValue())
    }

    private func normalized(_ e: IOHIDElement) -> Double {
        let lo = Double(IOHIDElementGetLogicalMin(e))
        let hi = Double(IOHIDElementGetLogicalMax(e))
        guard hi > lo else { return 0 }
        return min(max((Double(value(e)) - lo) / (hi - lo), 0), 1)
    }

    private func contact(from s: Slot) -> TouchContact? {
        let down = s.tip.map { value($0) != 0 } ?? true
        guard down else { return nil }
        let id = s.contactID.map { value($0) } ?? Int(s.order)
        return TouchContact(id: id, x: normalized(s.x!), y: normalized(s.y!))
    }

    private func emit() {
        onFrame?(frame)
        frame = []
    }
}
