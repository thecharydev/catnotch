// Mic, camera, Wi-Fi and Bluetooth state, for the status moments and dots.
import CoreAudio
import CoreLocation
import CoreMediaIO
import CoreWLAN
import Foundation

// MARK: microphone and camera

private func objectIDs(_ object: UInt32, _ selector: UInt32) -> [UInt32] {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == 0, size > 0 else { return [] }
    var ids = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == 0 else { return [] }
    return ids
}

private func audioHasInput(_ id: UInt32) -> Bool {
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == 0, size > 0 else { return false }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == 0 else { return false }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.contains { $0.mNumberChannels > 0 }
}

/// True when any input device is running for any process. A headset that is
/// also playing audio counts too: CoreAudio keeps one flag per device.
func micRunning() -> Bool {
    for id in objectIDs(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices) where audioHasInput(id) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &running) == 0 && running != 0 { return true }
    }
    return false
}

func cameraRunning() -> Bool {
    var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0, size > 0 else { return false }
    var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &ids) == 0 else { return false }
    for id in ids {
        var running: UInt32 = 0
        var runningAddress = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var got: UInt32 = 0
        if CMIOObjectGetPropertyData(id, &runningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == 0 && running != 0 { return true }
    }
    return false
}

// MARK: Wi-Fi and Location

final class LocationGate: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var onChange: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var state: String {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorized: return "granted"
        case .denied, .restricted: return "denied"
        default: return "unknown"
        }
    }

    func request() { if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() } }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { onChange?() }
}

/// The network name needs Location; without it the state still says connected.
func wifiState(_ location: String) -> [String: Any] {
    let interface = CWWiFiClient.shared().interface()
    let rssi = interface?.rssiValue() ?? 0
    let connected = (interface?.powerOn() ?? false) && rssi != 0
    var state: [String: Any] = ["t": "wifi", "connected": connected, "location": location,
                                 // Percent in steps of 20, so a drifting reading is not news.
                                 "signal": connected ? min(100, max(0, (rssi + 100) * 2)) / 20 * 20 : 0]
    state["ssid"] = connected && location == "granted" ? (interface?.ssid() as Any? ?? NSNull()) : NSNull()
    return state
}

// MARK: Bluetooth

/// Connected devices with their battery, from system_profiler (no Bluetooth
/// permission needed). Takes a second or two, so callers use a background queue.
func bluetoothDevices() -> [[String: Any]] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["SPBluetoothDataType", "-json"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let first = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
          let connected = first["device_connected"] as? [[String: Any]] else { return [] }
    func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }
    return connected.compactMap { entry in
        guard let name = entry.keys.first, let info = entry[name] as? [String: Any] else { return nil }
        let sides = [percent(info["device_batteryLevelLeft"]), percent(info["device_batteryLevelRight"])].compactMap { $0 }
        let battery = percent(info["device_batteryLevelMain"]) ?? sides.min()
        return ["name": name, "connected": true, "battery": battery as Any? ?? NSNull()]
    }
}
