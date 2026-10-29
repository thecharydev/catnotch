// DeskNotchHelper: prints one JSON object per line when a value changes.
// Protocol: docs/specs/0001-macos-port/index.md. Exits when its parent does.
import AppKit

setbuf(stdout, nil)

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let line = String(data: data, encoding: .utf8) else { return }
    print(line)
}

// One `notch` line per display, only for displays whose size changed.
// Size 0x0 means no hardware notch.
var lastNotch: [UInt32: String] = [:]

func reportNotches() {
    var seen = Set<UInt32>()
    for screen in NSScreen.screens {
        guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
        seen.insert(id)
        var w = 0.0, h = 0.0
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            w = Double(screen.frame.width - left.width - right.width)
            h = Double(screen.safeAreaInsets.top)
        }
        let key = "\(w)x\(h)"
        if lastNotch[id] == key { continue }
        lastNotch[id] = key
        emit(["t": "notch", "display": id, "w": w, "h": h])
    }
    for id in lastNotch.keys where !seen.contains(id) { lastNotch[id] = nil }
}

// Foreground app and whether it fills a display (a full screen Space).
// Only watched while main asks, since the 300 ms check is not free.
var lastForeground = ""
var foregroundTimer: Timer?

func displayBounds(_ id: CGDirectDisplayID) -> CGRect { CGDisplayBounds(id) }

func reportForeground() {
    guard let front = NSWorkspace.shared.frontmostApplication else { return }
    if front.processIdentifier == getppid() {
        if lastForeground != "self" { lastForeground = "self"; emit(["t": "foreground", "self": true]) }
        return
    }
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &count)
    let displays = Array(ids.prefix(Int(count)))

    var fullscreen = false
    var display = CGMainDisplayID()
    var best = 0.0
    let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    for w in windows where (w[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier && (w[kCGWindowLayer as String] as? Int) == 0 {
        guard let dict = w[kCGWindowBounds as String] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: dict) else { continue }
        for id in displays {
            let bounds = displayBounds(id)
            let overlap = bounds.intersection(rect)
            let area = overlap.isNull ? 0 : Double(overlap.width * overlap.height)
            if area > best { best = area; display = id }
            // Covering the whole display, menu bar included, is full screen;
            // a maximised window stops below the menu bar.
            if rect.minX <= bounds.minX + 2 && rect.minY <= bounds.minY + 2 && rect.maxX >= bounds.maxX - 2 && rect.maxY >= bounds.maxY - 2 {
                fullscreen = true; display = id; best = .infinity
            }
        }
    }
    let bundle = front.bundleIdentifier ?? ""
    let key = "\(fullscreen)|\(display)|\(bundle)"
    if key == lastForeground { return }
    lastForeground = key
    emit(["t": "foreground", "fullscreen": fullscreen, "display": display, "bundle": bundle])
}

func watchForeground(_ on: Bool) {
    foregroundTimer?.invalidate()
    foregroundTimer = nil
    lastForeground = ""
    guard on else { return }
    reportForeground()
    foregroundTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in reportForeground() }
}

// Requests from main: one JSON object per line.
var input = ""
FileHandle.standardInput.readabilityHandler = { handle in
    let data = handle.availableData
    if data.isEmpty { exit(0) }   // main closed our stdin: it is gone
    input += String(decoding: data, as: UTF8.self)
    while let newline = input.firstIndex(of: "\n") {
        let line = String(input[..<newline])
        input = String(input[input.index(after: newline)...])
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
        DispatchQueue.main.async {
            if object["cmd"] as? String == "usage", let id = object["id"] {
                emit(["id": id, "gpu": gpuUtilization() as Any? ?? NSNull(), "memory": memoryUsed()])
                return
            }
            if let id = object["id"], let cmd = object["cmd"] as? String, cmd.hasPrefix("calendar") {
                handleCalendar(cmd, id, object)
                return
            }
            switch object["cmd"] as? String {
            case "watchCalendar": watchCalendar(object["on"] as? Bool ?? false)
            case "watchForeground": watchForeground(object["on"] as? Bool ?? false)
            case "watchStatus": watchStatus(object["on"] as? Bool ?? false)
            case "requestLocation": location.request()
            default: break
            }
        }
    }
}

// Status: polled, one tick a second (cheap property reads). Bluetooth is slower.
let location = LocationGate()
var lastStatus: [String: String] = [:]

func emitIfChanged(_ key: String, _ object: [String: Any]) {
    let text = String(describing: object.sorted { $0.key < $1.key })
    if lastStatus[key] == text { return }
    lastStatus[key] = text
    emit(object)
}

func reportStatus() {
    emitIfChanged("mic", ["t": "mic", "on": micRunning()])
    emitIfChanged("camera", ["t": "camera", "on": cameraRunning()])
    emitIfChanged("wifi", wifiState(location.state))
}

func reportBluetooth() {
    DispatchQueue.global(qos: .utility).async {
        let devices = bluetoothDevices()
        DispatchQueue.main.async { emitIfChanged("bluetooth", ["t": "bluetooth", "devices": devices]) }
    }
}

func watchStatus(_ on: Bool) {
    statusTimers.forEach { $0.invalidate() }
    statusTimers = []
    guard on else { return }
    location.onChange = { reportStatus() }
    reportStatus()
    reportBluetooth()
    statusTimers = [
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in reportStatus() },
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in reportBluetooth() },
    ]
}
var statusTimers: [Timer] = []

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
    reportNotches()
}

let parent = getppid()
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
    if getppid() != parent { exit(0) }
}

reportNotches()
app.run()
