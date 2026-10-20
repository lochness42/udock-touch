import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid

/// Reads touchscreens on its own thread, recognises gestures and posts events.
///
/// Callbacks run on the engine thread; hop to the main actor for UI.
public final class TouchEngine {
    public var onDevicesChanged: (([HIDDeviceInfo]) -> Void)?
    public var onFrame: (([TouchContact]) -> Void)?
    public var onGesture: ((GestureOutput) -> Void)?

    private let log = TouchLog.shared
    private let poster: EventPoster
    private let recognizer = GestureRecognizer()

    // Engine thread only
    private var settings = TouchSettings()
    private var bounds = CGRect.zero
    private var runLoop: CFRunLoop?
    private var manager: IOHIDManager?
    private var readers: [TouchFrameReader] = []
    private var timer: CFRunLoopTimer?
    private var lastFrame: [TouchContact] = []
    private var axCheckedAt = -Double.infinity
    private var axTrusted = true
    private var recording: [TraceFrame]?
    private var recordStart = 0.0
    private var captureTap: ((TouchContact) -> Void)?
    private var captureLast: TouchContact?
    private var captureMulti = false
    private let maxRecordedFrames = 20_000

    public init(poster: EventPoster = CGEventPoster()) {
        self.poster = poster
    }

    public func start(settings: TouchSettings, displayBounds: CGRect) {
        guard runLoop == nil else { return }
        self.settings = settings
        bounds = displayBounds
        recognizer.settings = settings
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [unowned self] in
            runLoop = CFRunLoopGetCurrent()
            setUp()
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "UDockTouch.HID"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    /// Applies new settings and display bounds without a restart.
    public func update(settings: TouchSettings, displayBounds: CGRect) {
        perform { [unowned self] in
            let old = self.settings
            self.settings = settings
            bounds = displayBounds
            recognizer.settings = settings
            if old.enabled && !settings.enabled { post(recognizer.reset()) }
            if old.seize != settings.seize || old.device != settings.device {
                log.info("Device options changed; reopening touch devices")
                openManager()
            }
        }
    }

    // MARK: Trace recording

    public func startRecording() {
        perform { [unowned self] in
            recording = []
            recordStart = now()
            log.info("Trace recording started")
        }
    }

    /// Stops recording and hands back the trace on the engine thread.
    public func stopRecording(name: String, expected: [String]?, completion: @escaping (TouchTrace) -> Void) {
        perform { [unowned self] in
            let frames = recording ?? []
            recording = nil
            log.info("Trace recording stopped: \(frames.count) frames")
            completion(TouchTrace(name: name, expected: expected, screenSize: bounds.size,
                                  orientation: settings.orientation, calibration: settings.calibration,
                                  frames: frames))
        }
    }

    // MARK: Calibration capture

    /// While capturing, touches produce no events. Each one-finger tap reports its raw
    /// position when the finger lifts.
    public func setCapture(_ onTap: ((TouchContact) -> Void)?) {
        perform { [unowned self] in
            if onTap != nil { post(recognizer.reset()) }
            captureTap = onTap
            captureLast = nil
            captureMulti = false
        }
    }

    private func capture(_ contacts: [TouchContact]) {
        if contacts.count == 1 && !captureMulti {
            captureLast = contacts[0]
        } else if contacts.count > 1 {
            captureMulti = true
        } else if contacts.isEmpty {
            if let c = captureLast, !captureMulti {
                log.debug(String(format: "calibration tap at (%.3f,%.3f)", c.x, c.y))
                captureTap?(c)
            }
            captureLast = nil
            captureMulti = false
        }
    }

    /// Ends any open gesture, e.g. after sleep.
    public func resetGestures() {
        perform { [unowned self] in
            post(recognizer.reset())
            poster.releaseAll()
        }
    }

    /// Releases everything and stops the thread. Blocks briefly; call on quit.
    public func stop() {
        guard runLoop != nil else { return }
        let done = DispatchSemaphore(value: 0)
        perform { [unowned self] in
            post(recognizer.reset())
            poster.releaseAll()
            closeManager()
            CFRunLoopStop(CFRunLoopGetCurrent())
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }

    private func perform(_ block: @escaping () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    private func now() -> Double { ProcessInfo.processInfo.systemUptime }

    // MARK: Setup

    private func setUp() {
        let far = Date.distantFuture.timeIntervalSinceReferenceDate
        let t = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, far, far, 0, 0) { [unowned self] _ in fire() }
        CFRunLoopAddTimer(runLoop, t, .defaultMode)
        timer = t
        openManager()
    }

    private func openManager() {
        closeManager()
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: HIDUsage.touchScreen.page,
            kIOHIDDeviceUsageKey: HIDUsage.touchScreen.usage,
        ]
        IOHIDManagerSetDeviceMatching(m, matching as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<TouchEngine>.fromOpaque(ctx).takeUnretainedValue().deviceAdded(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<TouchEngine>.fromOpaque(ctx).takeUnretainedValue().deviceRemoved(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, runLoop!, CFRunLoopMode.defaultMode.rawValue)

        var result = IOHIDManagerOpen(m, IOOptionBits(settings.seize ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess && settings.seize {
            log.info("Exclusive mode failed (\(hex(result))); falling back to shared mode")
            result = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if result == kIOReturnSuccess {
            log.info("Watching for touchscreens (\(settings.seize ? "exclusive" : "shared") mode)")
        } else {
            log.info("⚠️ Could not open touch devices (\(hex(result))). Check Input Monitoring permission.")
        }
        manager = m
    }

    private func closeManager() {
        guard let m = manager else { return }
        post(recognizer.reset())
        readers.forEach { $0.stop() }
        readers = []
        IOHIDManagerUnscheduleFromRunLoop(m, runLoop!, CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        onDevicesChanged?([])
    }

    // MARK: Devices

    private func deviceAdded(_ device: IOHIDDevice) {
        guard !readers.contains(where: { $0.device === device }) else { return }
        let reader = TouchFrameReader(device: device)
        let i = reader.info
        log.info(String(format: "Touchscreen connected: \"%@\" VID 0x%04X PID 0x%04X, %d touch slot(s), contact count %@",
                        i.name, i.vendorID, i.productID, reader.slots.count, reader.hasContactCount ? "yes" : "no"))
        log.debug("Report layout of \"\(i.name)\":\n\(reader.layoutDescription)")
        readers.append(reader)

        if reader.slots.isEmpty {
            log.info("Ignoring \"\(i.name)\": no touch contacts found in its report layout")
        } else if let wanted = settings.device, wanted != i.identity {
            log.info("Ignoring \"\(i.name)\": another touch device is selected in Settings")
        } else {
            reader.onFrame = { [unowned self] in handleFrame($0) }
            reader.active = true
            reader.start()
        }
        onDevicesChanged?(readers.map(\.info))
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        guard let i = readers.firstIndex(where: { $0.device === device }) else { return }
        let reader = readers.remove(at: i)
        log.info("Touchscreen disconnected: \"\(reader.info.name)\"")
        reader.stop()
        if reader.active {
            post(recognizer.reset())
            poster.releaseAll()
        }
        onDevicesChanged?(readers.map(\.info))
    }

    // MARK: Frames

    private func handleFrame(_ contacts: [TouchContact]) {
        onFrame?(contacts)
        if contacts != lastFrame {
            lastFrame = contacts
            log.debug("touches: " + (contacts.isEmpty ? "none" : contacts.map {
                String(format: "#%d(%.3f,%.3f)", $0.id, $0.x, $0.y)
            }.joined(separator: " ")))
        }
        if recording != nil, recording!.count < maxRecordedFrames {
            recording!.append(TraceFrame(t: now() - recordStart, contacts: contacts))
        }
        if captureTap != nil {
            capture(contacts)
            return
        }
        guard settings.enabled else { return }
        let mapped = contacts.map { Contact(id: $0.id, p: TouchMapper.screenPoint($0, settings: settings, bounds: bounds)) }
        post(recognizer.update(mapped, at: now()))
        scheduleTimer()
    }

    private func fire() {
        guard settings.enabled, captureTap == nil else { return }
        post(recognizer.tick(at: now()))
        scheduleTimer()
    }

    private func scheduleTimer() {
        guard let timer else { return }
        if let deadline = recognizer.nextDeadline {
            CFRunLoopTimerSetNextFireDate(timer, CFAbsoluteTimeGetCurrent() + max(0, deadline - now()))
        } else {
            CFRunLoopTimerSetNextFireDate(timer, Date.distantFuture.timeIntervalSinceReferenceDate)
        }
    }

    private func post(_ outputs: [GestureOutput]) {
        guard !outputs.isEmpty else { return }
        checkAccessibility()
        for o in outputs {
            poster.post(o)
            log.debug("→ \(o)")
            onGesture?(o)
        }
    }

    private func checkAccessibility() {
        let t = now()
        guard t - axCheckedAt > 2 else { return }
        axCheckedAt = t
        let trusted = AXIsProcessTrusted()
        if !trusted && axTrusted {
            log.info("⚠️ Accessibility permission is missing: macOS ignores the clicks and scrolls this app sends")
        }
        axTrusted = trusted
    }

    private func hex(_ r: IOReturn) -> String { String(format: "0x%08X", UInt32(bitPattern: r)) }
}
