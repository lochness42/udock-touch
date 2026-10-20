import AppKit
import ServiceManagement
import TouchCore

@MainActor
final class AppState: ObservableObject {
    enum Status {
        case running, paused, missingPermission, noTouchscreen

        var title: String {
            switch self {
            case .running: return "Touch is on"
            case .paused: return "Paused"
            case .missingPermission: return "Accessibility permission needed"
            case .noTouchscreen: return "No touchscreen connected"
            }
        }

        var symbol: String {
            switch self {
            case .running: return "hand.tap.fill"
            case .paused: return "hand.raised.slash"
            case .missingPermission: return "exclamationmark.triangle"
            case .noTouchscreen: return "hand.tap"
            }
        }
    }

    @Published var settings: TouchSettings {
        didSet {
            guard settings != oldValue else { return }
            SettingsStore.save(settings)
            applySettings()
        }
    }
    @Published private(set) var accessibilityGranted = Permissions.accessibility
    @Published private(set) var inputMonitoringGranted = Permissions.inputMonitoring
    @Published private(set) var touchDevices: [HIDDeviceInfo] = []
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var touching = false
    @Published private(set) var isRecording = false
    @Published private(set) var calibration: CalibrationController?
    @Published private(set) var touchTest: TouchTestController?
    /// Sees every touch frame on the main thread (used by the touch test).
    var frameObserver: (([TouchContact]) -> Void)?
    @Published var onboardingCompleted = SettingsStore.onboardingCompleted {
        didSet { SettingsStore.onboardingCompleted = onboardingCompleted }
    }

    let live = LiveTouchModel()
    private let engine = TouchEngine()
    private let feedback = TouchFeedback()
    private let log = TouchLog.shared
    private var permissionTimer: Timer?

    init() {
        settings = SettingsStore.load()
    }

    func start() {
        log.debugEnabled = settings.debugLogging
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        log.info("UDock Touch \(version) starting on macOS \(ProcessInfo.processInfo.operatingSystemVersionString); "
            + "Accessibility \(accessibilityGranted ? "granted" : "missing"), "
            + "Input Monitoring \(inputMonitoringGranted ? "granted" : "not granted")")

        let live = self.live
        log.onLine = { line in DispatchQueue.main.async { live.addLog(line) } }
        engine.onDevicesChanged = { [weak self] devices in
            DispatchQueue.main.async { self?.touchDevices = devices }
        }
        engine.onFrame = { [weak self] contacts in
            DispatchQueue.main.async { self?.handleFrame(contacts) }
        }
        engine.onGesture = { output in
            guard output.isNotable else { return }
            DispatchQueue.main.async { live.addGesture(output.description) }
        }

        refreshDisplays()
        engine.start(settings: settings, displayBounds: targetBounds)

        CGDisplayRegisterReconfigurationCallback({ _, flags, ctx in
            guard let ctx, !flags.contains(.beginConfigurationFlag) else { return }
            let state = Unmanaged<AppState>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { state.refreshDisplays() }
        }, Unmanaged.passUnretained(self).toOpaque())

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log.info("Woke from sleep; resetting gestures")
                self?.engine.resetGestures()
            }
        }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    func stop() {
        engine.stop()
    }

    var status: Status {
        if !settings.enabled { return .paused }
        if !accessibilityGranted { return .missingPermission }
        if touchDevices.isEmpty { return .noTouchscreen }
        return .running
    }

    func refreshPermissions() {
        let ax = Permissions.accessibility
        let im = Permissions.inputMonitoring
        if ax != accessibilityGranted {
            accessibilityGranted = ax
            log.info("Accessibility permission \(ax ? "granted" : "revoked")")
        }
        if im != inputMonitoringGranted {
            inputMonitoringGranted = im
            log.info("Input Monitoring permission \(im ? "granted" : "revoked")")
        }
    }

    private func applySettings() {
        log.debugEnabled = settings.debugLogging
        engine.update(settings: settings, displayBounds: targetBounds)
        if !settings.touchFeedback { feedback.hide() }
    }

    private func handleFrame(_ contacts: [TouchContact]) {
        live.contacts = contacts
        frameObserver?(contacts)
        let t = !contacts.isEmpty
        if t != touching { touching = t }
        if settings.touchFeedback && settings.enabled && calibration == nil && touchTest == nil,
           let screen = touchScreen {
            feedback.show(contacts, settings: settings, bounds: targetBounds, screen: screen)
        }
    }

    // MARK: Traces

    static let tracesFolder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UDockTouch/Traces")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func startRecording() {
        engine.startRecording()
        isRecording = true
    }

    func stopRecording(name: String, expected: [String]?, completion: @escaping (URL?) -> Void) {
        engine.stopRecording(name: name, expected: expected) { [weak self] trace in
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let url = AppState.tracesFolder.appendingPathComponent("\(name)-\(f.string(from: trace.recordedAt)).json")
            var saved: URL?
            do {
                try trace.encoded().write(to: url)
                saved = url
                TouchLog.shared.info("Saved trace \(url.lastPathComponent)")
            } catch {
                TouchLog.shared.info("⚠️ Could not save trace: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self?.isRecording = false
                completion(saved)
            }
        }
    }

    // MARK: Calibration

    func startTouchTest() {
        guard touchTest == nil, calibration == nil else { return }
        let t = TouchTestController(state: self)
        t.onFinish = { [weak self] in self?.touchTest = nil }
        touchTest = t
        t.start()
    }

    func startCalibration(_ mode: CalibrationController.Mode) {
        guard calibration == nil, touchTest == nil else { return }
        let c = CalibrationController(state: self, mode: mode)
        c.onFinish = { [weak self] in self?.calibration = nil }
        calibration = c
        c.start()
    }

    /// Routes one-finger taps to `onTap` instead of clicking, or back to normal with nil.
    func setCapture(_ onTap: ((TouchContact) -> Void)?) {
        engine.setCapture(onTap.map { tap in { c in DispatchQueue.main.async { tap(c) } } })
    }

    var touchScreen: NSScreen? {
        guard let id = targetDisplay?.id else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    // MARK: Displays

    func refreshDisplays() {
        displays = DisplayInfo.active()
        if let d = targetDisplay {
            log.info("Touch display: \(d.label) at (\(Int(d.bounds.minX)),\(Int(d.bounds.minY)))")
        }
        applySettings()
    }

    var targetDisplay: DisplayInfo? {
        DisplayMatching.pick(saved: settings.display, from: displays.map(\.candidate)).map { displays[$0] }
    }

    var targetBounds: CGRect {
        targetDisplay?.bounds ?? CGDisplayBounds(CGMainDisplayID())
    }

    func selectDisplay(_ display: DisplayInfo) {
        settings.display = display.identity
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = error.localizedDescription
            }
        }
    }
}
