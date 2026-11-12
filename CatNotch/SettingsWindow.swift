import AppKit
import ServiceManagement
import SwiftUI
import CatNotchCore
import os

private let loginLogger = Logger(subsystem: "com.thecharydev.catnotch", category: "login")

/// The one line of how a reading is got, with the whole list under a disclosure.
private struct SourceNote: View {
    let source: DataSource
    @State private var open = false

    var body: some View {
        Text(source.summary).font(.caption).foregroundStyle(.secondary)
        // Not a DisclosureGroup: its label only toggles from the arrow.
        Button { withAnimation { open.toggle() } } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0)).font(.caption2.weight(.semibold))
                Text("How CatNotch gets this")
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .font(.caption)
        if open {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(source.lines, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

extension Notification.Name {
    /// Posted by the Notch's dock gear; the app delegate shows the Settings window.
    static let openSettings = Notification.Name("CatNotch.openSettings")
}

/// The one Settings window. Later features add their own controls to `SettingsView`.
@MainActor
final class SettingsWindow {
    private let window: NSWindow

    init(store: CatNotchStore, focus: FocusModel, agenda: AgendaModel, usage: UsageModel, claude: ClaudeModel, update: UpdateModel) {
        window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store, focus: focus, agenda: agenda, usage: usage, claude: claude, update: update)))
        window.title = "CatNotch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false // closing hides it; the shortcut shows the same window again
        // The app is an accessory (no Dock icon, no menu bar); show both while this window is open, like the Electron app.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
        }
    }

    /// Just Quit, so the menu bar is not empty. ponytail: add Settings/Edit items if they are missed.
    private static func installMainMenu() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu(), app = NSMenuItem(), menu = NSMenu()
        menu.addItem(withTitle: "Quit CatNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = menu
        main.addItem(app)
        NSApp.mainMenu = main
    }

    /// Opens it, or brings the open one to the front.
    func show() {
        Self.installMainMenu()
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !window.isVisible { window.layoutIfNeeded(); window.center() } // after the content has its size, or it centers the wrong size
        window.makeKeyAndOrderFront(nil)
        NSApp.activate() // the app has no Dock icon, so it is never active by itself
    }
}

/// The Settings window's sections, listed on the left like System Settings.
private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, companion, focus, calendar, usage
    var id: Self { self }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .companion: "Companion"
        case .focus: "Focus timer"
        case .calendar: "Calendar"
        case .usage: "AI usage"
        }
    }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .companion: "pawprint"
        case .focus: "timer"
        case .calendar: "calendar"
        case .usage: "gauge.with.needle"
        }
    }
}

private struct SettingsView: View {
    let store: CatNotchStore
    let focus: FocusModel
    let agenda: AgendaModel
    let usage: UsageModel
    let claude: ClaudeModel
    let update: UpdateModel
    @State private var section = SettingsSection.general
    @State private var selection: DisplaySelection
    @State private var style: NotchStyle
    @State private var flavor: Flavor
    @State private var tint: NotchTint
    @State private var coat: String?
    @State private var photo: FileRef?
    @State private var character: CompanionCharacter
    @State private var look: Bool
    @State private var sleeps: Bool
    @State private var reacts: Bool
    @State private var ambient: Bool
    @State private var showAvatar: Bool
    @State private var showDesk: Bool
    @State private var showReminders: Bool
    @State private var showFiles: Bool
    @State private var showClaude: Bool
    @State private var closedClock: Bool
    @State private var hideFullscreen: Bool
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var screens = NSScreen.screens

    init(store: CatNotchStore, focus: FocusModel, agenda: AgendaModel, usage: UsageModel, claude: ClaudeModel, update: UpdateModel) {
        self.store = store
        self.focus = focus
        self.agenda = agenda
        self.usage = usage
        self.claude = claude
        self.update = update
        _selection = State(initialValue: store.data.displaySelection)
        _style = State(initialValue: store.data.notchStyle)
        _flavor = State(initialValue: store.data.notchFlavor)
        _tint = State(initialValue: store.data.notchTint)
        _coat = State(initialValue: store.data.catAccent)
        _photo = State(initialValue: store.data.photo)
        _character = State(initialValue: store.data.avatar)
        _look = State(initialValue: store.data.companionLook)
        _sleeps = State(initialValue: store.data.companionSleepOn)
        _reacts = State(initialValue: store.data.companionReact)
        _ambient = State(initialValue: store.data.ambientVideo)
        _showAvatar = State(initialValue: store.data.showAvatar)
        _showDesk = State(initialValue: store.data.showDesk)
        _showReminders = State(initialValue: store.data.showReminders)
        _showFiles = State(initialValue: store.data.showFiles)
        _showClaude = State(initialValue: store.data.showClaude)
        _closedClock = State(initialValue: store.data.closedClock)
        _hideFullscreen = State(initialValue: store.data.hideOnFullscreen)
    }

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            Form {
                switch section {
                case .general: generalSection
                case .appearance: appearanceSection
                case .companion: companionSection
                case .focus: focusSection
                case .calendar: calendarSection
                case .usage: usageSection
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 700, height: 520)
        // Displays may come and go while the window is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = NSScreen.screens }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            opensAtLogin = SMAppService.mainApp.status == .enabled // changed in System Settings meanwhile
        }
    }

    @ViewBuilder private var generalSection: some View {
        Section("General") {
            Toggle("Open at login", isOn: Binding(get: { opensAtLogin }, set: { setLogin($0) }))
            Picker("Show the Notch on", selection: Binding(get: { shown }, set: { choice in selection = choice; store.update { $0.displaySelection = choice } })) {
                Text("Primary display").tag(DisplaySelection.primary)
                Text("All displays").tag(DisplaySelection.all)
                ForEach(screens, id: \.self) { screen in
                    if let id = screen.displayID { Text(screen.localizedName).tag(DisplaySelection.chosen(id)) }
                }
            }
            Toggle("Hide in fullscreen", isOn: Binding(get: { hideFullscreen }, set: { on in hideFullscreen = on; store.update { $0.hideOnFullscreen = on } }))
            Text("Videos, games and other fullscreen apps.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Notch pages") {
            sectionToggle("Focus & tasks", $showDesk) { $0.showDesk = $1 }
            Toggle("Calendar", isOn: Binding(get: { agenda.showCalendar }, set: { on in store.update { $0.showCalendar = on } }))
            sectionToggle("Reminders", $showReminders) { $0.showReminders = $1 }
            sectionToggle("Files", $showFiles) { $0.showFiles = $1 }
            sectionToggle("Claude sessions", $showClaude) { $0.showClaude = $1 }
        }
        closedSection
        updateSection
        Section { Button("Quit CatNotch") { NSApp.terminate(nil) } }
    }

    /// A switch for one Notch section, kept in a local copy so it answers at once.
    private func sectionToggle(_ title: String, _ value: Binding<Bool>, save: @escaping (inout StoreData, Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { value.wrappedValue }, set: { on in value.wrappedValue = on; store.update { save(&$0, on) } }))
    }


    @ViewBuilder private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Style", selection: Binding(get: { style }, set: { choice in style = choice; store.update { $0.notchStyle = choice } })) {
                ForEach(NotchStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            // A new flavour drops the custom background and accent, as in the Electron app.
            Picker("Flavour", selection: Binding(get: { flavor }, set: { choice in
                flavor = choice; tint.fill = nil; tint.rim = nil
                store.update { $0.notchFlavor = choice; $0.notchColor = nil; $0.notchAccent = nil }
            })) {
                ForEach(Flavor.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            ColorPicker("Background", selection: colorBinding(get: { tint.fill ?? flavor.base }) { hex in tint.fill = hex; store.update { $0.notchColor = hex } }, supportsOpacity: false)
            LabeledContent("Accent") {
                HStack(spacing: 6) {
                    ForEach(flavor.accents, id: \.name) { accent in swatch(accent.name, accent.hex, chosen: tint.rim == accent.hex) { tint.rim = accent.hex; store.update { $0.notchAccent = accent.hex } } }
                    ColorPicker("Custom accent", selection: colorBinding(get: { tint.rim ?? flavor.mauve }) { hex in tint.rim = hex; store.update { $0.notchAccent = hex } }, supportsOpacity: false).labelsHidden()
                }
            }
            LabeledContent("Opacity") {
                HStack {
                    Slider(value: Binding(get: { tint.opacity }, set: { value in tint.opacity = value; store.update { $0.notchOpacity = value } }), in: 0.2...1, step: 0.05).frame(width: 140)
                    Text("\(Int((tint.opacity * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
            }
            Text("Background and opacity colour the Transparent and Glass styles; Black stays black. The accent is a thin line along the sides and bottom.").font(.caption).foregroundStyle(.secondary)
            Toggle("Ambient glow", isOn: Binding(get: { ambient }, set: { on in ambient = on; store.update { $0.ambientVideo = on } }))
            Text("A soft video light on Home while music plays, in the companion's colour.").font(.caption).foregroundStyle(.secondary)
        }
    }


    @ViewBuilder private var closedSection: some View {
        Section("Closed Notch") {
            Toggle("Show the time", isOn: Binding(get: { closedClock }, set: { on in closedClock = on; store.update { $0.closedClock = on } }))
            Text("Music, headphones, a focus session and the mic or camera dots still take their place when they happen.").font(.caption).foregroundStyle(.secondary)
        }
    }


    @ViewBuilder private var focusSection: some View {
        Section("Focus timer") {
            Picker("Session length", selection: Binding(get: { focus.minutes }, set: { focus.setMinutes($0) })) {
                ForEach(FocusLength.options(including: focus.minutes), id: \.self) { Text(FocusLength.format($0)).tag($0) }
            }
            LabeledContent(focus.phase.title) {
                HStack {
                    if focus.phase != .idle && focus.phase != .finished {
                        Text(FocusLength.clock(seconds: focus.remaining)).monospacedDigit()
                    }
                    Button(focus.phase.action, action: focus.toggle)
                    Button("Reset", action: focus.reset).disabled(focus.phase == .idle)
                }
            }
        }
    }


    @ViewBuilder private var companionSection: some View {
        Section("Companion") {
            sectionToggle("Show on Home", $showAvatar) { $0.showAvatar = $1 }
            LabeledContent("Character") {
                HStack(spacing: 2) {
                    ForEach(CompanionCharacter.allCases.filter { $0 != .photo }, id: \.self) { character in
                        characterButton(character) { CompanionStill(character: character, flavor: flavor, coat: coat.map(flavor.accent(named:)), size: 22) }
                    }
                    // The photo: the first click (or a click while it is chosen) asks for the picture.
                    characterButton(.photo) {
                        if let image = CompanionTile.thumbnail(photo) {
                            Image(nsImage: image).resizable().scaledToFill().frame(width: 22, height: 22).clipShape(Circle())
                        } else {
                            Image(systemName: "photo.badge.plus").font(.system(size: 14))
                        }
                    }
                }
            }
            if character == .catppuccin {
                LabeledContent("Coat") {
                    HStack(spacing: 6) {
                        ForEach(flavor.accents, id: \.name) { accent in
                            swatch(accent.name, accent.hex, chosen: (coat ?? "Mauve") == accent.name) { coat = accent.name; store.update { $0.catAccent = accent.name } }
                        }
                    }
                }
            }
            if photo != nil {
                LabeledContent("Your photo") { Button("Remove") { removePhoto() } }
            }
            Toggle("Look around", isOn: Binding(get: { look }, set: { on in look = on; store.update { $0.companionLook = on } }))
            Text("It turns its head and eyes on its own and follows the pointer.").font(.caption).foregroundStyle(.secondary)
            Toggle("Sleep at night", isOn: Binding(get: { sleeps }, set: { on in sleeps = on; store.update { $0.companionSleepOn = on } }))
            Text("It sleeps from 23:00 to 06:00.").font(.caption).foregroundStyle(.secondary)
            Toggle("React to events", isOn: Binding(get: { reacts }, set: { on in reacts = on; store.update { $0.companionReact = on } }))
            Text("It perks up on a new track, a finished task or a timer.").font(.caption).foregroundStyle(.secondary)
        }
    }


    @ViewBuilder private var calendarSection: some View {
        Section("Calendar") {
            // Calendars are only listed once the Calendar view has been allowed; Settings never asks.
            ForEach(agenda.calendars) { calendar in
                Toggle(isOn: Binding(get: { !agenda.hidden.contains(calendar.id) }, set: { store.setCalendar(calendar.id, shown: $0) })) {
                    Label {
                        Text(calendar.title)
                        if !calendar.account.isEmpty { Text(calendar.account).foregroundStyle(.secondary) }
                    } icon: { Image(systemName: "circle.fill").foregroundStyle(Color(hex: calendar.color)) }
                }
            }
        }
    }


    @ViewBuilder private var usageSection: some View {
        Section("AI usage") {
            Toggle("Show usage on Home", isOn: Binding(get: { usage.available }, set: { usage.setAvailable($0) }))
            SourceNote(source: .aiUsage)
        }
        Section("Claude Code") {
            Toggle("Show Claude Code prompts on the Notch", isOn: Binding(get: { claude.enabled }, set: { claude.setEnabled($0) }))
            if claude.enabled {
                Picker("Sound when Claude needs you", selection: Binding(get: { claude.sound ?? "" }, set: { claude.setSound($0.isEmpty ? nil : $0) })) {
                    Text("None").tag("")
                    ForEach(ClaudeSounds.all, id: \.self) { Text($0).tag($0) }
                }
            }
            SourceNote(source: .claude)
            if let problem = claude.problem { Text(problem).font(.caption).foregroundStyle(.red) }
        }
    }


    @ViewBuilder private var updateSection: some View {
        Section("Update") {
            LabeledContent("CatNotch \(update.version)") {
                HStack {
                    Text(updateStatus).foregroundStyle(.secondary)
                    if update.isInstalled {
                        Button("Restart now") { update.restart() }
                    } else if case .available(let version) = update.state {
                        Button("Update to \(version)") { Task { await update.install() } }
                    } else if update.state == .failed {
                        Button("Try again") { Task { await update.install() } }
                    } else {
                        Button("Check for updates") { Task { await update.check() } }.disabled(update.busy)
                    }
                }
            }
        }
    }



    private var updateStatus: String {
        switch update.state {
        case .idle: ""
        case .checking: "Checking…"
        case .upToDate: "Up to date"
        case .available: "A new version is out"
        case .downloading(let percent): "Downloading \(percent)%"
        case .installing: "Installing…"
        case .installed(let version): "\(version) installed. Restart to use it"
        case .unwritable: "Move CatNotch to Applications to update it"
        case .checkFailed: "Could not check for updates"
        case .failed: "Update failed"
        }
    }

    /// An unplugged chosen display shows as the primary, which is what the Notch does with it.
    private var shown: DisplaySelection {
        if case .chosen(let id) = selection, !screens.contains(where: { $0.displayID == id }) { return .primary }
        return selection
    }

    /// A round colour button, ringed when chosen.
    private func swatch(_ name: String, _ hex: UInt32, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(Color(hex: hex)).frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.primary.opacity(chosen ? 0.9 : 0.15), lineWidth: chosen ? 2 : 1))
        }
        .buttonStyle(.plain).help(name).accessibilityLabel(name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// A SwiftUI colour picker over a 0xRRGGBB value.
    private func colorBinding(get: @escaping () -> UInt32, set: @escaping (UInt32) -> Void) -> Binding<Color> {
        Binding(get: { Color(hex: get()) }, set: { color in
            guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
            func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
            set(byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent))
        })
    }

    /// One round button of the character picker, ringed when it is the chosen one.
    private func characterButton<Content: View>(_ item: CompanionCharacter, @ViewBuilder content: () -> Content) -> some View {
        Button {
            if item == .photo, photo == nil || character == .photo { guard choosePhoto() else { return } }
            character = item
            store.update { $0.avatar = item }
        } label: {
            content().opacity(character == item ? 1 : 0.55)
                .frame(width: 28, height: 28)
                .background { if character == item { Circle().fill(.primary.opacity(0.14)) } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(item == .photo ? (photo == nil ? "Use your own photo" : "Your photo. Click again to change it") : item.label)
        .accessibilityLabel(item == .photo ? "Your photo" : item.label)
        .accessibilityAddTraits(character == item ? .isSelected : [])
    }

    /// Asks for a picture. False when none was chosen.
    private func choosePhoto() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        store.setPhoto(url)
        photo = store.data.photo
        return true
    }

    /// Removing the photo while it is the companion hands the tile back to the ghost.
    private func removePhoto() {
        store.update { $0.photo = nil; if $0.avatar == .photo { $0.avatar = .ghost } }
        photo = nil
        if character == .photo { character = .ghost }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginLogger.error("Could not turn open at login \(on ? "on" : "off", privacy: .public) (code: \((error as NSError).code, privacy: .public))")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}
