import AppKit
import SwiftUI
import CatNotchCore

// The open size: the Home row of tiles, and the focus tile and task list side by side (see NotchView). Grows as features fill the pages.
private let openSize = CGSize(width: 700, height: 300)
// The dock under the open Notch: a 32pt pill and the 4pt gap above it, as in the Electron version.
private let dockHeight: CGFloat = 36
// The apps tray beside the open Notch: a 42pt column and the 6pt gap before it.
private let trayRoom: CGFloat = 48 + NotchLayout.openEar // and past the open Notch's flared top corners

/// Hosting view with a tracking area, so the pointer leaving the panel is seen while it takes mouse events.
private final class TrackedHostingView<Content: View>: NSHostingView<Content> {
    var onPointer: () -> Void = {}
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) } // only ours: the hosting view keeps its own for SwiftUI hover
        let new = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(new)
        area = new
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true } // the panel can be key now; a first click must still land
    // Always call super: SwiftUI's own tracking areas deliver through these, so without it `onHover` never fires (no remove cross, no row highlight).
    override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: event); HandCursor.cursor.set(); onPointer() }
    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); HandCursor.cursor.set(); onPointer() }
    override func cursorUpdate(with event: NSEvent) { HandCursor.cursor.set() } // AppKit's own reset to the arrow
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); onPointer() }
}

/// A panel AppKit may not nudge below the menu bar: the drawn Notch must sit where the hit rect says.
private final class TopPanel: NSPanel {
    override var canBecomeKey: Bool { true } // the quick-add field needs the keyboard; a nonactivating panel takes it without activating the app
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// One transparent panel at the top centre of one display. It ignores the mouse (clicks fall through) except while open.
/// Pointer input is event driven: NotchController owns the monitors and calls `update()`; the tracking area does too.
@MainActor
final class NotchPanel {
    let displayID: UInt32
    private let model = NotchModel(open: openSize)
    private let panel: TopPanel
    private let claude: ClaudeModel
    private let agenda: AgendaModel
    private var held = CGSize.zero // the open size the panel is framed for
    private var windowHeight: CGFloat = 0 // the window's height; see `place`
    private let headroom: CGFloat = 24 // how much taller than needed the window may stay before it shrinks back
    private var shrink: Task<Void, Never>?
    private var peeking = false // a request opened the closed Notch
    private var pinned = false // the shortcut opened it: stays open with the pointer away (spec 0031)
    private var suppressed = false // Esc closed it: stays closed until the pointer has left
    private var leave = LeaveIntent() // whether the pointer is leaving the open Notch (Electron's away timer)
    private var leaveTimer: Task<Void, Never>?
    private var leaveExpired = false // the pointer stopped past the reach for long enough
    private var resizedAt = Date.distantPast
    /// Told when whether this Notch wants the bare arrow keys may have changed (see `wantsHoverKeys`).
    var onKeysChanged: () -> Void = {}

    init(displayID: UInt32, data: StoreData, focus: FocusModel, tasks: TaskModel, nowPlaying: NowPlayingModel, agenda: AgendaModel, shelf: ShelfModel, screenshots: ScreenshotModel, system: SystemModel, usage: UsageModel, claude: ClaudeModel) {
        self.displayID = displayID
        self.claude = claude
        self.agenda = agenda
        panel = TopPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let view = TrackedHostingView(rootView: NotchView(model: model, focus: focus, tasks: tasks, nowPlaying: nowPlaying, agenda: agenda, shelf: shelf, screenshots: screenshots, system: system, usage: usage, claude: claude))
        view.onPointer = { [weak self] in self?.update() }
        model.resized = { [weak self] in self?.resized() }
        model.onLock = { [weak self] in self?.update() }
        panel.contentView = view
        apply(data)
        reposition()
        watchRequests()
        // Another app took the keyboard (a click elsewhere): a pinned Notch lets go.
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.pinned == true { self?.pinned = false; self?.update() }; self?.onKeysChanged() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onKeysChanged() }
        }
    }

    /// A request arriving or leaving opens or folds the Notch; Observation calls back once per change, so look again each time.
    private func watchRequests() {
        withObservationTracking { _ = claude.requests.count; _ = claude.finished?.id } onChange: { [weak self] in
            Task { @MainActor in self?.update(); self?.watchRequests() }
        }
    }

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    /// Sizes the closed Notch from the hardware notch (or the default) and pins the panel to the display.
    func reposition() {
        guard let screen else { return }
        let bar = NotchSize.closedWithWings(
            screenWidth: screen.frame.width, safeTop: screen.safeAreaInsets.top,
            leftWidth: screen.auxiliaryTopLeftArea?.width, rightWidth: screen.auxiliaryTopRightArea?.width)
        model.hover.closed = bar.size
        model.cutout = bar.cutout
        if bar.cutout > 0 { model.hover.closed.width = bar.cutout + 2 * model.wing } // as wide as what it shows
        model.hover.chrome = dockHeight
        model.hover.side = trayRoom
        place(held == .zero ? model.hover.open : held)
        update()
    }

    /// The panel frame for an open size of `open`. The window is never shorter than the tallest page (Claude with six
    /// sessions) needs, so switching pages never resizes it in the middle of SwiftUI's own update: that laid the new page
    /// out in the old window for a frame and left the Notch off the top of the screen (Calendar, then Claude). It only
    /// grows past that for something taller (a request strip), and follows it back down once it is gone.
    private func place(_ open: CGSize) {
        guard let screen else { return }
        var hover = model.hover
        hover.open = open
        var frame = hover.panelFrame(in: screen.frame)
        let tallest = NotchLayout.open(content: NotchLayout.claudeSessionsContent(count: NotchLayout.claudeRowsMax), closedHeight: hover.closed.height).height + hover.chrome
        let target = max(frame.height, tallest)
        if target > windowHeight || windowHeight > target + headroom { windowHeight = target }
        frame.origin.y -= windowHeight - frame.height // the top stays on the screen's edge
        frame.size.height = windowHeight
        panel.setFrame(frame, display: true)
    }

    /// The page changed the open size. The panel grows at once so the Notch can spring into it, and shrinks once it
    /// has settled, so its transparent margin does not catch clicks meant for the apps below.
    private func resized() {
        let open = model.hover.open
        if held.height > open.height || held.width > open.width { model.hover.shrunkFrom = held } // the pointer may be on the old dock
        held = CGSize(width: max(held.width, open.width), height: max(held.height, open.height))
        resizedAt = Date()
        place(held)
        shrink?.cancel()
        shrink = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled, let self else { return }
            held = model.hover.open
            place(held)
        }
    }

    /// Takes the saved look.
    func apply(_ data: StoreData) {
        model.style = data.notchStyle
        model.flavor = data.notchFlavor
        model.tint = data.notchTint
        model.coatName = data.catAccent
        // Other settings share the store: set only what changed, so Home is not redrawn for a task.
        if model.character != data.avatar { model.character = data.avatar }
        if model.photo != data.photo { model.photo = data.photo }
        if model.companionLook != data.companionLook { model.companionLook = data.companionLook }
        if model.companionSleeps != data.companionSleepOn { model.companionSleeps = data.companionSleepOn }
        if model.companionReacts != data.companionReact { model.companionReacts = data.companionReact }
        if model.ambientVideo != data.ambientVideo { model.ambientVideo = data.ambientVideo }
        if model.closedClock != data.closedClock { model.closedClock = data.closedClock }
        if model.closedCompanion != data.closedCompanion { model.closedCompanion = data.closedCompanion }
        if model.showAvatar != data.showAvatar { model.showAvatar = data.showAvatar }
        if model.showMusic != data.showMusic { model.showMusic = data.showMusic }
        if model.pagesOff != data.pagesOff {
            model.pagesOff = data.pagesOff
            if data.pagesOff.contains(model.page) { model.page = .home } // the page it was on is gone
        }
    }

    /// `fileDrag`: a file is being dragged and the pointer is moving it. The Notch opens from further off, on Files,
    /// so the file can be dropped straight onto the shelf.
    func update(fileDrag: Bool = false) {
        guard let screen, panel.alphaValue > 0 else { return } // hidden: no hover, no clicks
        defer { onKeysChanged() }
        let cursor = NSEvent.mouseLocation
        var inside = model.hover.isOpen(cursor: cursor, in: screen.frame, wasOpen: model.isOpen, dragging: fileDrag)
        let near = inside
        if model.isOpen {
            // Past the reach it lets go by intent, as Electron does: heading away closes it, a pointer that stops there closes it
            // after a beat, and heading back (or a page resizing under a still pointer) keeps it.
            let settling = Date().timeIntervalSince(resizedAt) < LeaveIntent.settle
            switch leave.step(distance: model.hover.distance(from: cursor, in: screen.frame), settling: settling) {
            case .stay: leaveTimer?.cancel(); inside = true
            case .close: leaveTimer?.cancel()
            case .keep: inside = true
            case .wait:
                inside = true
                leaveTimer?.cancel()
                leaveTimer = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(LeaveIntent.still))
                    guard !Task.isCancelled, let self else { return }
                    leaveExpired = true
                    update()
                }
            }
            if leaveExpired && !near { inside = false }
        } else {
            leave.reset()
            leaveTimer?.cancel()
        }
        leaveExpired = false
        let waiting = !claude.requests.isEmpty || claude.finished != nil
        // The request that opened it alone was answered (or gone): fold, not open the page under the pointer that clicked it.
        if !waiting && peeking && !pinned { suppressed = true }
        if suppressed { if inside { inside = false } else { suppressed = false } } // Esc: not again until the pointer has left
        // A waiting request keeps the Notch open, to the request alone while the pointer is elsewhere.
        // The request alone stays alone for as long as it waits, even with the pointer on it (as the Electron strip does),
        // so hovering a question opens its card, not the whole page under it. It is alone only if it came to a closed Notch.
        if !waiting || pinned { peeking = false } else if !model.isOpen && !inside { peeking = true }
        model.peek = peeking
        model.pointerInside = inside && near // the pointer itself, not the beat the Notch waits before letting go
        let open = inside || waiting || pinned || model.locked
        model.fileDrag = fileDrag && inside
        if inside && fileDrag && model.page != .files { withAnimation(notchPageSpring) { model.page = .files } }
        // Open, the panel takes the mouse only over the Notch: the margin that keeps it open must let clicks through.
        let solid = open && model.hover.hits(cursor: cursor, in: screen.frame)
        if panel.ignoresMouseEvents == solid { panel.ignoresMouseEvents = !solid }
        guard open != model.isOpen else { return }
        model.isOpen = open
        if !open { model.hover.shrunkFrom = nil; releaseKeyboard() }
    }

    // MARK: keyboard (spec 0031)

    var isKey: Bool { panel.isKeyWindow }
    /// Open by hover, without the keyboard: the keys are still the app in front's, so the controller takes the bare
    /// arrows as hot keys for as long as this holds. Once the panel is key (a click, the shortcut) the key monitor has them.
    var wantsHoverKeys: Bool { model.isOpen && !model.peek && !panel.isKeyWindow }
    func holds(_ point: CGPoint) -> Bool { screen?.frame.contains(point) ?? false }
    /// A field is being typed in: the keys are the field's, except Esc.
    private var typing: Bool { panel.firstResponder is NSText }

    /// The shortcut: open and take the keyboard, or close.
    func toggleFromKeyboard() {
        guard panel.isVisible else { return }
        if model.isOpen && !model.peek { dismiss(); return } // a request peek is not the page: the shortcut opens that
        suppressed = false
        pinned = true
        update()
        panel.makeKey() // nonactivating: the app in front stays in front
    }

    /// Esc: closes now, and stays closed until the pointer has left.
    private func dismiss() {
        pinned = false
        model.locked = false
        suppressed = true
        update()
    }

    /// A closed Notch must not keep the keyboard, or the app the user was in would stop hearing keys. Ordering out a
    /// key window hands key back to the previous app's window; the panel comes straight back, still click-through.
    private func releaseKeyboard() {
        guard panel.isKeyWindow else { return }
        panel.makeFirstResponder(nil) // a field left in focus would swallow the arrows next time
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// Routes a key to what it means on the current page. False means it is not ours and goes on to its owner.
    func handle(key: NotchKey, option: Bool) -> Bool {
        guard model.isOpen, !model.peek else { return false }
        if typing && key != .escape { return false }
        switch NotchKeys.action(for: key, option: option, page: model.page, daySelected: model.calendarDay != nil) {
        case nil: return false
        case .close?: dismiss()
        case .section(let step)?:
            let next = NotchKeys.page(from: model.page, step: step, among: NotchPage.shown(calendar: agenda.showCalendar, off: model.pagesOff))
            withAnimation(notchPageSpring) { model.page = next }
        case .day(let key)?: model.calendarDay = NotchKeys.day(from: model.calendarDay, key: key, now: Date())
        }
        return true
    }

    /// Hidden over a fullscreen app. Shown again it starts closed.
    /// Hidden is alpha 0, not `orderOut`: an ordered out panel came back on the current Space only, so the other desktops lost the Notch (issue #49).
    func setHidden(_ hidden: Bool) {
        if hidden {
            pinned = false
            model.isOpen = false
            panel.ignoresMouseEvents = true
            panel.alphaValue = 0
        } else {
            if panel.alphaValue == 0 {
                model.isOpen = false
                panel.ignoresMouseEvents = true
                panel.alphaValue = 1
                update()
            }
            panel.orderFrontRegardless() // also the first show; idempotent, no key change
        }
    }
}

extension NSScreen {
    var displayID: UInt32? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}
