import AppKit
import CoreAudio
import CoreLocation
import CoreWLAN
import IOKit.ps
import Observation
import CatNotchCore

struct WifiState: Equatable {
    var on: Bool
    var connected: Bool
    /// The network's name; nil until Location is allowed (macOS hides it), and the tile says "Wi-Fi".
    var name: String?
    var signal: Int
}

struct AppEntry: Identifiable {
    let path: String
    let name: String
    let icon: NSImage
    var id: String { path }
}

/// The Mac's state at a glance, for the Notch on every display: battery, Wi-Fi, Bluetooth,
/// headphones arriving, and the apps used most. Everything is a system notification (no timers), and a capability the
/// Mac lacks or the user has not allowed leaves only its own value empty.
@MainActor @Observable
final class SystemModel {
    private(set) var battery = BatteryState.none
    private(set) var wifi: WifiState?
    private(set) var bluetooth: [BluetoothDevice] = []
    /// The name of headphones that just connected, for a moment, then nil again.
    private(set) var headphones: String?
    private(set) var apps: [AppEntry] = []

    private let location = LocationGate()
    private let wifiWatcher = WifiWatcher()
    private var outputs: [UInt32: String]?
    private var headphonesHide: Task<Void, Never>?
    private var appsLoaded: Date?
    private var bluetoothAsked: Date?

    private static let appsFresh: TimeInterval = 30 * 60
    private static let appCount = 8

    init() {
        watchBattery()
        watchAudio()
        watchWifi()
        refreshBattery()
        refreshWifi()
    }

    // MARK: battery

    private func watchBattery() {
        // Fires on a charge step and when the power source changes; the source lives on the main run loop for the life of the app.
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<SystemModel>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { model.refreshBattery() }
        }, Unmanaged.passUnretained(self).toOpaque()).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func refreshBattery() {
        Task {
            let state = BatteryState(pmset: await Self.run("/usr/bin/pmset", ["-g", "batt"]))
            if state != battery { battery = state }
        }
    }

    // MARK: audio outputs

    private func watchAudio() {
        listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices) { [weak self] in self?.audioDevicesChanged() }
        audioDevicesChanged()
    }

    private func audioDevicesChanged() {
        let ids = Self.audioIDs(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)

        // What is already connected when the app starts is not news.
        let now = Dictionary(uniqueKeysWithValues: ids.filter { Self.hasStreams($0, scope: kAudioDevicePropertyScopeOutput) }.compactMap { id in Self.name(id).map { (id, $0) } })
        defer { outputs = now }
        if let before = outputs {
            if let name = Headphones.arrival(before: Self.byName(before), now: Self.byName(now)) { showHeadphones(name) }
            if before.keys != now.keys { refreshBluetooth(force: true) } // a headset connecting or leaving
        }
    }

    private static func byName(_ outputs: [UInt32: String]) -> [String: String] {
        Dictionary(outputs.map { (String($0.key), $0.value) }, uniquingKeysWith: { $1 })
    }

    private func showHeadphones(_ name: String) {
        headphones = name
        headphonesHide?.cancel()
        headphonesHide = Task {
            try? await Task.sleep(for: .milliseconds(1400))
            if !Task.isCancelled { headphones = nil }
        }
    }

    // MARK: Wi-Fi

    private func watchWifi() {
        location.onChange = { [weak self] in self?.refreshWifi() }
        location.request() // the network's name needs Location; without it the tile still says Wi-Fi
        wifiWatcher.onChange = { [weak self] in self?.refreshWifi() }
        wifiWatcher.start()
    }

    private func refreshWifi() {
        guard let interface = CWWiFiClient.shared().interface() else { wifi = nil; return } // no Wi-Fi hardware: no tile
        let rssi = interface.rssiValue()
        let connected = interface.powerOn() && rssi != 0
        let next = WifiState(on: interface.powerOn(), connected: connected,
                             name: connected && location.isGranted ? interface.ssid() : nil,
                             signal: connected ? Wifi.signal(rssi: rssi) : 0)
        if next != wifi { wifi = next }
    }

    // MARK: Bluetooth

    /// system_profiler takes a second or two and has no change notification, so it is read when the Notch opens
    /// and when an audio output comes or goes, not on a timer.
    func refreshBluetooth(force: Bool = false) {
        if !force, let asked = bluetoothAsked, Date().timeIntervalSince(asked) < 10 { return }
        bluetoothAsked = Date()
        Task {
            let json = await Self.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])
            let devices = BluetoothDevice.connected(profiler: Data(json.utf8))
            if devices != bluetooth { bluetooth = devices }
        }
    }

    // MARK: most used apps

    /// Looks at Spotlight's launch counts, at most every 30 minutes.
    func refreshApps() {
        if let loaded = appsLoaded, Date().timeIntervalSince(loaded) < Self.appsFresh { return }
        appsLoaded = Date()
        Task {
            let paths = await Task.detached { Self.installedApps() }.value
            let output = await Self.run("/usr/bin/mdls", ["-name", "kMDItemUseCount", "-raw", "-nullMarker", "0"] + paths)
            let top = TopApps.rank(TopApps.counts(paths: paths, mdls: output), excluding: Bundle.main.bundlePath, limit: Self.appCount)
            apps = top.map { path in
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 64, height: 64)
                return AppEntry(path: path, name: FileManager.default.displayName(atPath: path).replacing(/\.app$/, with: ""), icon: icon)
            }
        }
    }

    func launch(_ app: AppEntry) { NSWorkspace.shared.open(URL(fileURLWithPath: app.path)) }

    /// Every .app in the usual folders, and one level down (Utilities, vendor folders).
    nonisolated private static func installedApps() -> [String] {
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var found: [String] = []
        func scan(_ dir: String, depth: Int) {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where !name.hasPrefix(".") {
                let path = dir + "/" + name
                if name.hasSuffix(".app") { found.append(path) } else if depth > 0 { scan(path, depth: depth - 1) }
            }
        }
        roots.forEach { scan($0, depth: 1) }
        return found
    }

    // MARK: helpers

    /// Runs a tool off the main thread and returns what it printed. A tool that cannot run prints nothing.
    nonisolated static func run(_ path: String, _ arguments: [String]) async -> String {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile() // read before waiting: a full pipe would block the tool
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
    }

    /// Calls `change` on the main thread whenever the property changes. Lives as long as the app.
    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ change: @escaping @MainActor () -> Void) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(object, &address, .main) { _, _ in MainActor.assumeIsolated { change() } }
    }

    nonisolated private static func audioIDs(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [UInt32] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == 0, size > 0 else { return [] }
        var ids = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == 0 else { return [] }
        return ids
    }

    nonisolated private static func hasStreams(_ id: UInt32, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == 0, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == 0 else { return false }
        return UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self)).contains { $0.mNumberChannels > 0 }
    }

    nonisolated private static func name(_ id: UInt32) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == 0 else { return nil }
        return name?.takeRetainedValue() as String?
    }
}

/// Asks for Location once (macOS hides the Wi-Fi network's name without it) and says when the answer changes.
private final class LocationGate: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onChange: @MainActor () -> Void = {}

    override init() {
        super.init()
        manager.delegate = self
    }

    var isGranted: Bool { manager.authorizationStatus == .authorizedAlways }
    func request() { if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() } }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { let handler = onChange; Task { @MainActor in handler() } }
}

/// CoreWLAN reports link changes on its own queue; each is one hop to the main thread.
private final class WifiWatcher: NSObject, CWEventDelegate {
    var onChange: @MainActor () -> Void = {}

    func start() {
        let client = CWWiFiClient.shared()
        client.delegate = self
        for event in [CWEventType.ssidDidChange, .linkDidChange, .powerDidChange, .linkQualityDidChange] { try? client.startMonitoringEvent(with: event) }
    }

    private func changed() { let handler = onChange; Task { @MainActor in handler() } }
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) { changed() }
    func linkDidChangeForWiFiInterface(withName interfaceName: String) { changed() }
    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { changed() }
    func linkQualityDidChangeForWiFiInterface(withName interfaceName: String, rssi: Int, transmitRate: Double) { changed() }
}
