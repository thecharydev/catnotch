import AppKit
import Carbon.HIToolbox
import CatNotchCore

/// One Notch panel per target display, hidden on a display a fullscreen app fills.
/// Everything is event driven: pointer monitors, screen changes, app and Space switches. No polling timer.
@MainActor
final class NotchController {
    private var selection: DisplaySelection { didSet { sync() } }

    private let store: CatNotchStore
    private let focus: FocusModel
    private let tasks: TaskModel
    private let nowPlaying: NowPlayingModel
    private let agenda: AgendaModel
    private let shelf: ShelfModel
    private let screenshots: ScreenshotModel
    private let system: SystemModel
    private let usage: UsageModel
    private let claude: ClaudeModel
    private var panels: [UInt32: NotchPanel] = [:]
    private var foreground: ForegroundState?
    private var hoverKeys: [GlobalShortcut] = []

    init(store: CatNotchStore, focus: FocusModel, tasks: TaskModel, nowPlaying: NowPlayingModel, agenda: AgendaModel, shelf: ShelfModel, screenshots: ScreenshotModel, system: SystemModel, usage: UsageModel, claude: ClaudeModel) {
        self.store = store
        self.focus = focus
        self.tasks = tasks
        self.nowPlaying = nowPlaying
        self.agenda = agenda
        self.shelf = shelf
        self.screenshots = screenshots
        self.system = system
        self.usage = usage
        self.claude = claude
        selection = store.data.displaySelection
        // Settings changes the rule through the store; every Notch follows live. Lives as long as the app.
        _ = store.observe { [weak self] data in MainActor.assumeIsolated { // other settings share the store: only a real change re-syncs
            guard let self else { return }
            if data.displaySelection != self.selection { self.selection = data.displaySelection }
            self.panels.values.forEach { $0.apply(data) } // the look changed in Settings
            self.applyForeground() // Hide in fullscreen may have changed
        } }
        // Monitors live as long as the app. Global sees moves over other apps (panels ignore the mouse), local over ours.
        // A file dragged toward the Notch opens it on Files, so it can take the drop (drags send no mouse moved events).
        let press: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.pressed() } }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: press)
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in press(event); return event }
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in MainActor.assumeIsolated { self?.pointerMoved() } }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in MainActor.assumeIsolated { self?.pointerMoved(dragging: true) } }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in MainActor.assumeIsolated { self?.pointerMoved() }; return event }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = Int(event.keyCode), flags = event.modifierFlags // NSEvent itself is not Sendable
            return MainActor.assumeIsolated { self?.keyDown(code: code, flags: flags) == true } ? nil : event
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync(); self?.refreshForeground() }
        }
        // A fullscreen app lives in its own Space, so entering or leaving one switches the Space or the active app.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshForeground()
                    // The window list lags the Space switch animation; look again as it settles (a few one shots, not a poll).
                    for delay in [0.3, 0.7, 1.4, 2.5] { // the fullscreen exit animation can outlast 1.4s (issue #49)
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { self?.refreshForeground() } }
                    }
                }
            }
        }
        sync()
        refreshForeground()
    }

    /// The drag pasteboard as it was at the last mouse press. A drag that carries files changes it (the source app
    /// writes it when the drag starts) and leaves file URLs on it; the pasteboard alone would still hold the last drag's.
    private let dragBoard = NSPasteboard(name: .drag)
    private var boardAtPress = NSPasteboard(name: .drag).changeCount

    private func pressed() { boardAtPress = dragBoard.changeCount }

    private func pointerMoved(dragging: Bool = false) {
        let files = dragging && dragBoard.changeCount != boardAtPress
            && dragBoard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        panels.values.forEach { $0.update(fileDrag: files) }
    }

    
    /// Holds Left, Right and Esc as hot keys while a Notch is open by hover, so the arrows switch its sections and Esc closes it without it
    /// taking the keyboard. Released the moment none wants them, so typing elsewhere is untouched.
    private func syncHoverKeys() {
        let wanted = panels.values.contains(where: \.wantsHoverKeys)
        if !wanted { hoverKeys.forEach { $0.unregister() }; hoverKeys = []; return }
        guard hoverKeys.isEmpty else { return }
        hoverKeys = [(10, kVK_LeftArrow, NotchKey.left, "Left arrow"), (11, kVK_RightArrow, .right, "Right arrow"), (12, kVK_Escape, .escape, "Escape")].map { id, code, key, name in
            GlobalShortcut(id: UInt32(id), key: code, modifiers: 0, name: name) { [weak self] in
                _ = self?.panels.values.first(where: \.wantsHoverKeys)?.handle(key: key, option: false)
            }
        }
    }

    /// The shortcut: on the display the pointer is on (else the first).
    func toggleFromKeyboard() {
        let target = panels.values.first { $0.holds(NSEvent.mouseLocation) } ?? panels.values.first
        target?.toggleFromKeyboard()
    }

    /// Arrows and Esc for whichever Notch has the keyboard. Anything with Command or Control is not ours.
    private func keyDown(code: Int, flags: NSEvent.ModifierFlags) -> Bool {
        guard let panel = panels.values.first(where: \.isKey), flags.isDisjoint(with: [.command, .control]) else { return false }
        let key: NotchKey
        switch code {
        case kVK_LeftArrow: key = .left
        case kVK_RightArrow: key = .right
        case kVK_UpArrow: key = .up
        case kVK_DownArrow: key = .down
        case kVK_Escape: key = .escape
        default: return false
        }
        return panel.handle(key: key, option: flags.contains(.option))
    }

    /// Makes the panels match the display rule: adds, removes and resizes them.
    private func sync() {
        let screens = NSScreen.screens
        // The primary display is the one with the menu bar, first in the list.
        guard let primary = screens.first.flatMap(\.displayID) else { return }
        let targets = Set(selection.targets(available: screens.compactMap(\.displayID), primary: primary))

        for (id, panel) in panels where !targets.contains(id) {
            panel.setHidden(true)
            panels[id] = nil
        }
        for id in targets {
            if let panel = panels[id] { panel.reposition() } else { let panel = NotchPanel(displayID: id, data: store.data, focus: focus, tasks: tasks, nowPlaying: nowPlaying, agenda: agenda, shelf: shelf, screenshots: screenshots, system: system, usage: usage, claude: claude)
                panel.onKeysChanged = { [weak self] in self?.syncHoverKeys() }
                panels[id] = panel
            }
        }
        applyForeground()
        syncHoverKeys() // a removed Notch no longer wants them
    }

    private func refreshForeground() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        // CatNotch itself in front (hovered or clicked): leave everything as it was. Except a hidden Notch (issue #49):
        // it can only be in front after a Space switch landed on us, and a stale fullscreen would keep the Notch hidden there.
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            if foreground?.fullscreen == true { foreground?.fullscreen = false; applyForeground() }
            return
        }

        let displays = NSScreen.screens.compactMap { screen in
            screen.displayID.map { DisplayBounds(id: $0, bounds: CGDisplayBounds($0), topInset: screen.safeAreaInsets.top) }
        }
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let windows = list.compactMap { w -> WindowInfo? in
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, let layer = w[kCGWindowLayer as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: dict) else { return nil }
            return WindowInfo(pid: pid, layer: layer, bounds: rect)
        }
        foreground = ForegroundState.detect(pid: front.processIdentifier, bundle: front.bundleIdentifier ?? "", windows: windows, displays: displays, mainDisplay: CGMainDisplayID())
        applyForeground()
    }

    private func applyForeground() {
        let hide = store.data.hideOnFullscreen
        for (id, panel) in panels { panel.setHidden(hide && foreground?.hides(display: id) ?? false) }
    }
}
