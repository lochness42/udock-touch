import Foundation
import IOKit
import IOKit.hid

public struct HIDUsage: Hashable, Sendable, CustomStringConvertible {
    public let page: Int
    public let usage: Int

    public init(page: Int, usage: Int) {
        self.page = page
        self.usage = usage
    }

    public static let touchScreen = HIDUsage(page: 0x0D, usage: 0x04)

    public var description: String { String(format: "%02X:%02X", page, usage) }
}

/// A snapshot of one HID device's properties.
public struct HIDDeviceInfo: Identifiable, Hashable, Sendable {
    public let id: UInt64              // IORegistry entry ID
    public let name: String
    public let manufacturer: String
    public let vendorID: Int
    public let productID: Int
    public let serial: String
    public let transport: String
    public let usages: [HIDUsage]

    public var isTouchScreen: Bool { usages.contains(.touchScreen) }
    public var identity: DeviceIdentity { DeviceIdentity(vendorID: vendorID, productID: productID, serial: serial) }

    public init(device: IOHIDDevice) {
        func prop(_ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }
        var entryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &entryID)
        id = entryID
        name = prop(kIOHIDProductKey) as? String ?? "?"
        manufacturer = prop(kIOHIDManufacturerKey) as? String ?? ""
        vendorID = prop(kIOHIDVendorIDKey) as? Int ?? 0
        productID = prop(kIOHIDProductIDKey) as? Int ?? 0
        serial = prop(kIOHIDSerialNumberKey) as? String ?? ""
        transport = prop(kIOHIDTransportKey) as? String ?? ""
        let pairs = prop(kIOHIDDeviceUsagePairsKey) as? [[String: Any]] ?? []
        usages = pairs.map {
            HIDUsage(page: $0[kIOHIDDeviceUsagePageKey] as? Int ?? 0, usage: $0[kIOHIDDeviceUsageKey] as? Int ?? 0)
        }
    }

    /// Every HID device currently attached (the `--list-devices` equivalent).
    public static func all() -> [HIDDeviceInfo] {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, nil)
        let devices = (IOHIDManagerCopyDevices(m) as NSSet?)?.allObjects ?? []
        return devices
            .map { HIDDeviceInfo(device: $0 as! IOHIDDevice) }
            .sorted { ($0.isTouchScreen ? 0 : 1, $0.name) < ($1.isTouchScreen ? 0 : 1, $1.name) }
    }
}
