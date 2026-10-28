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
