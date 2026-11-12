import AppKit
import SwiftUI
import CatNotchCore

@MainActor @Observable
final class NotchModel {
    var isOpen = false
    /// Open only because a Claude request is waiting and the pointer is elsewhere: the request alone, no page, no dock.
    var peek = false
    /// The lock on the dock: the Notch stays open with the pointer away, until it is unlocked (Electron's pin).
    var locked = false
    /// The pointer is on the Notch (or its dock), so a locked Notch shows the dock again.
    var pointerInside = false
    var hover: NotchHover
    /// Width of the black hardware cutout, 0 on a display without one.
    var cutout: CGFloat = 0
    var style = NotchStyle.black
    var flavor = Flavor.mocha
    var tint = NotchTint()
    /// The cat's coat, an accent name from the flavour (nil is Mauve).
    var coatName: String?
    var coat: UInt32? { coatName.map(flavor.accent(named:)) }
    /// The companion: who it is and the three motion switches (all off until saved on).
    var character = CompanionCharacter.ghost
    var photo: FileRef?
    var companionLook = false
    var companionSleeps = false
    var companionReacts = false
    /// The ambient glow while music plays.
    var ambientVideo = true
    var closedClock = true
    /// Sections switched off in Settings.
    var pagesOff = Set<NotchPage>()
    var showAvatar = true
    var showMusic = true
    /// How wide each side of the closed Notch is on a hardware notch; follows what the closed Notch shows.
    var wing = NotchSize.wing
    var closedCompanion = true
    var page = NotchPage.home
    /// The companion's clock is unfolded to the day's wave, which makes its tile wider.
    var dayOpen = false
    /// The Calendar page's chosen day; lives here so a key can move it.
    var calendarDay: Date?
    /// The month the Calendar page shows (its first day). Lives here because the Notch is as tall as the month has weeks.
    var calendarMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    /// A file is being dragged over the open Notch, so the shelf shows where it goes.
    var fileDrag = false
    /// Called when the open size changes, so the panel can follow it.
    var resized: (() -> Void)?
    /// Called when the lock is pressed, so the panel can look again.
    var onLock: (() -> Void)?

    init(open: CGSize) { hover = NotchHover(closed: NotchSize.fallback, open: open) }
}

/// The colour the companion lends the Notch, as Electron's one `accent`: the cat's face, a bot's own colour, white for a
/// photo. Set once on `NotchView`; the views that used fixed colours read it.
private struct CompanionAccentKey: EnvironmentKey { static let defaultValue = Color(hex: 0xcba6f7) }
extension EnvironmentValues {
    var companionAccent: Color {
        get { self[CompanionAccentKey.self] }
        set { self[CompanionAccentKey.self] = newValue }
    }
}

private struct NotchTintKey: EnvironmentKey { static let defaultValue = NotchTint() }
extension EnvironmentValues {
    var notchTint: NotchTint {
        get { self[NotchTintKey.self] }
        set { self[NotchTintKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

/// The Notch's outline, Vibe Notch's `NotchShape`: the sides sit `topCornerRadius` in from the frame's edge, and the top
/// corners curve outward into the screen's edge (the concave flare of the MacBook's own notch). Both radii animate, so the
/// flare swells as the Notch opens and tightens as it closes, rather than the corners popping in and out. Quadratic curves.
private struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set { (topCornerRadius, bottomCornerRadius) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let t = topCornerRadius, b = bottomCornerRadius
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// A behind-window blur that looks the same whether or not the panel is key. SwiftUI materials and Liquid Glass render
/// differently in a key window, and the panel becomes key when clicked, so the colour shifted on every click.
private struct ActiveBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active // not .followsWindowActiveState, the default
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The Notch's fill, the same in every window state. Black is solid; Transparent is the flavour as a flat colour like
/// the Electron version (nothing captured); Glass is the flavour over a blur of the desktop behind it.
private struct NotchFill<S: Shape>: View {
    let style: NotchStyle
    let flavor: Flavor
    let shape: S
    @Environment(\.notchTint) private var tint

    var body: some View {
        fill.overlay { if let rim = tint.rim { shape.stroke(Color(hex: rim).opacity(0.5), lineWidth: 1) } }
    }

    @ViewBuilder private var fill: some View {
        let base = Color(hex: tint.fill ?? flavor.base)
        switch style {
        case .black: shape.fill(.black)
        case .transparent: shape.fill(base.opacity(tint.opacity))
        case .glass: ActiveBlur().overlay(base.opacity(tint.opacity * 0.65)).clipShape(shape) // 0.45 at the default 0.7
        }
    }
}

/// The closed clock: 12-hour, with a small AM or PM. Redraws on the minute, no timer of ours.
/// What the closed Notch's left side holds, most urgent first.
private enum ClosedLeft { case headphones, focus, companion, clock, none }

private struct ClosedClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let text = WallClock.text(context.date)
            HStack(alignment: .firstTextBaseline, spacing: 3) { // the Electron Notch's sizes and tints
                Text(text.time).font(.system(size: 10.5, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.75))
                Text(text.meridiem).font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
            }
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1) // keeps it readable over a light wallpaper
        }
    }
}

/// A ring that fills to `fraction`, starting at the top.
private struct FocusRing: View {
    let fraction: Double
    let width: CGFloat
    var color = Color.white

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: width)
            Circle().trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.linear(duration: 1), value: fraction) // one tick a second, so it glides rather than steps
    }
}

/// What the closed Notch says while a session runs: the ring draining and the time left, in the clock's place.
private struct ClosedFocus: View {
    var focus: FocusModel
    @Environment(\.companionAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            FocusRing(fraction: 1 - focus.progress, width: 2, color: accent).frame(width: 11, height: 11)
            Text(FocusLength.clock(seconds: focus.remaining)).font(.system(size: 10, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(.white.opacity(0.8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Focus, \(FocusLength.clock(seconds: focus.remaining)) left")
    }
}

/// The focus tile on the Focus & tasks view: ring, time, today's tally and the controls.
private struct FocusTile: View {
    var focus: FocusModel
    @Environment(\.companionAccent) private var accent

    private var time: String {
        switch focus.phase {
        case .idle: FocusLength.format(focus.minutes)
        case .running, .paused: FocusLength.clock(seconds: focus.remaining)
        case .finished: "Break"
        }
    }

    var body: some View {
        let today = focus.today
        HStack(spacing: 16) {
            FocusRing(fraction: focus.phase == .idle ? 1 : focus.progress, width: 6, color: accent)
                .opacity(focus.phase == .idle ? 0.35 : 1)
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(focus.phase.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.white.opacity(0.55))
                Text(time).font(.system(size: 26, weight: .semibold).monospacedDigit()).foregroundStyle(focus.phase == .idle ? .white : accent)
                Text(today.sessions == 0 ? "No sessions today" : "Today: \(today.sessions) \(today.sessions == 1 ? "session" : "sessions"), \(Int(today.minutes)) min")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            VStack(spacing: 6) {
                Button(action: focus.toggle) {
                    Text(focus.phase.action).font(.system(size: 12, weight: .semibold)).foregroundStyle(focus.phase == .running ? .white : .black)
                        .frame(width: 64).padding(.vertical, 6).background(Capsule().fill(focus.phase == .running ? .white.opacity(0.1) : accent))
                }
                if focus.phase != .idle {
                    Button("Reset", action: focus.reset).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .buttonStyle(.lively)
        }
    }
}

/// One task: the whole row ticks it, the cross (on hover) removes it.
struct TaskRow: View {
    @Environment(\.companionAccent) private var accent
    let task: StoreTask
    var tasks: TaskModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(task.done ? .white.opacity(0.6) : accent.opacity(hovering ? 1 : 0.5))
            Text(task.label)
                .font(.system(size: 13)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.white.opacity(task.done ? 0.3 : 0.9)).strikethrough(task.done)
            Button { tasks.remove(task.id) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.lively).foregroundStyle(.white.opacity(0.5))
                .opacity(hovering ? 1 : 0).allowsHitTesting(hovering).accessibilityLabel("Delete task")
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { tasks.toggle(task.id) }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .pointerCursor()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(task.label), \(task.done ? "done" : "not done")")
    }
}

/// The task list: a line to type on, the open tasks, and the done ones folded below.
private struct TasksList: View {
    var tasks: TaskModel
    @State private var draft = ""
    @State private var showDone = false

    var body: some View {
        let open = tasks.open, done = tasks.done
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                TextField("What needs doing", text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .onChange(of: draft) { if draft.count > StoreData.taskMaxLength { draft = String(draft.prefix(StoreData.taskMaxLength)) } }
                    .onSubmit { tasks.add(draft); draft = "" }
                if !open.isEmpty { Text("\(open.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.35)) }
            }
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(showDone ? open + done : open, id: \.id) { TaskRow(task: $0, tasks: tasks) }
                    if open.isEmpty && !showDone {
                        Text("Nothing left. Type the next thing above.")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }
                }
            }
            .scrollIndicators(.never)

            if !done.isEmpty {
                HStack(spacing: 12) {
                    Button("\(done.count) done\(showDone ? " · hide" : "")") { showDone.toggle() }
                    Button("Clear", action: tasks.clearDone)
                }
                .buttonStyle(.lively).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}

/// Album art, or a note on grey when the player published none.
private struct Art: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack { Color.white.opacity(0.12); Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.5)) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .accessibilityHidden(true)
    }
}

/// The closed Notch's art: it swells and eases back while audio plays. Read off the clock rather than a repeatForever
/// animation (that shared the wing resize's transaction and slid the art sideways); a scale never touches layout.
private struct PulsingArt: View {
    let image: NSImage?
    let tint: Color
    var playing = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { context in // paused: no frames at all
            let wave = playing ? (1 - cos(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.2)) / 2 : 0
            Art(image: image, size: 16, radius: 4)
                .scaleEffect(1 + 0.18 * wave)
                .shadow(color: tint.opacity(0.35 + 0.5 * wave), radius: 2 + 3 * wave) // a glow in the art's colour that breathes with the swell
        }
        .frame(width: 16, height: 16)
        .accessibilityElement()
        .accessibilityLabel(playing ? "Playing" : "Paused")
    }
}

/// Reports the pointer entering and leaving whatever it is the background of. It was written when `onHover` seemed to
/// wait for a click; the real cause was the panel's hosting view not calling `super` on mouse events (fixed in
/// NotchPanel.swift), so plain `onHover` works too.
struct PointerOver: NSViewRepresentable {
    var onChange: (Bool) -> Void

    final class Area: NSView {
        var onChange: (Bool) -> Void = { _ in }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        /// A resize re-makes the tracking area and AppKit can say "entered" or "exited" again with the pointer never having
        /// moved, so only a real change is passed on.
        private var inside = false
        override func mouseEntered(with event: NSEvent) {
            guard !inside else { return }
            inside = true
            onChange(true)
        }
        override func mouseExited(with event: NSEvent) {
            if let window, bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) { return }
            guard inside else { return }
            inside = false
            onChange(false)
        }
    }

    func makeNSView(context: Context) -> Area { Area() }
    func updateNSView(_ view: Area, context: Context) { view.onChange = onChange }
}

/// The progress bar like the macOS one: a thin track filled in the accent colour, a dot on hover or drag, and the
/// time played and left under it. It ticks only while the track plays.
private struct TrackProgress: View {
    let track: NowPlaying
    var onSeek: (TimeInterval) -> Void
    @State private var scrub: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !track.isPlaying || scrub != nil)) { context in
            let fraction = scrub ?? track.fraction(at: context.date)
            let elapsed = fraction * track.duration
            VStack(spacing: 1) {
                GeometryReader { geo in
                    let height: CGFloat = hovering || scrub != nil ? 6 : 4
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(Color.accentColor).frame(width: max(height, geo.size.width * fraction))
                        // The dot sits at the playhead while the pointer is on the bar or dragging.
                        Circle().fill(.white).frame(width: 12, height: 12).shadow(color: .black.opacity(0.3), radius: 2)
                            .offset(x: min(max(0, geo.size.width * fraction - 6), geo.size.width - 12))
                            .opacity(hovering || scrub != nil ? 1 : 0)
                    }
                    .frame(height: height)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { scrub = min(1, max(0, $0.location.x / geo.size.width)) }
                        .onEnded { value in
                            onSeek(min(1, max(0, value.location.x / geo.size.width)) * track.duration)
                            scrub = nil
                        })
                    .animation(.easeOut(duration: 0.15), value: height)
                    .animation(.easeOut(duration: 0.15), value: hovering)
                }
                .frame(height: 14)
                .background(PointerOver { hovering = $0 })
                HStack {
                    Text(TrackTime.text(elapsed))
                    Spacer()
                    Text("-" + TrackTime.text(track.duration - elapsed))
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(TrackTime.text(track.fraction(at: Date()) * track.duration)) of \(TrackTime.text(track.duration))")
    }
}

/// The Home view's music tile, laid out like the macOS Now Playing: the art on the left, and beside it the title,
/// the artist, the controls and the progress bar. Neutral glass with only a hint of the art's colour.
private struct NowPlayingCard: View {
    var nowPlaying: NowPlayingModel

    private func control(_ symbol: String, _ label: String, _ key: Transport) -> some View {
        Button { nowPlaying.send(key) } label: {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                .frame(width: 40, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.lively).accessibilityLabel(label)
    }

    var body: some View {
        Group {
            if let track = nowPlaying.current {
                HStack(spacing: 12) {
                    Art(image: nowPlaying.art, size: 104, radius: 10)
                    VStack(spacing: 4) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Text(track.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "waveform").font(.system(size: 11))
                                .symbolEffect(.variableColor.iterative, isActive: track.isPlaying)
                                .foregroundStyle(.white.opacity(0.5)).accessibilityHidden(true)
                        }
                        HStack(spacing: 8) {
                            control("backward.fill", "Previous", .previous)
                            control(track.isPlaying ? "pause.fill" : "play.fill", track.isPlaying ? "Pause" : "Play", .playPause)
                            control("forward.fill", "Next", .next)
                        }
                        // A live stream has no length, so no bar.
                        if track.duration > 0 { TrackProgress(track: track, onSeek: nowPlaying.seek) } else { Spacer(minLength: 0) }
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.white.opacity(0.35)).accessibilityHidden(true)
                    Text("Nothing playing").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .homeTile(width: NotchLayout.musicWidth, tint: nowPlaying.current == nil ? nil : nowPlaying.tint)
        .animation(.easeInOut(duration: 0.4), value: nowPlaying.tint)
    }
}

/// The most used apps, in a column hanging from the screen's edge beside the open Notch (the Electron version's apps tray).
private struct AppsTray: View {
    var system: SystemModel
    let style: NotchStyle
    let flavor: Flavor

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
        VStack(spacing: 14) {
            ForEach(system.apps.prefix(2)) { app in
                Button { system.launch(app) } label: { Image(nsImage: app.icon).resizable().frame(width: 32, height: 32).frame(width: 34, height: 34) }
                    .buttonStyle(.lively).help(app.name).accessibilityLabel("Open \(app.name)")
            }
        }
        .padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 6)
        .background(NotchFill(style: style, flavor: flavor, shape: shape))
        .overlay(shape.strokeBorder(.white.opacity(0.07)))
        .task { system.refreshApps() } // the Notch opening is the moment to look again; it skips itself when it looked recently
    }
}

/// The Notch's two springs, the Electron version's (stiffness 224/damping 24 and 195/28) and Vibe Notch's: a soft,
/// slightly bouncy open and a critically damped close, so it settles without overshooting its edge.
let notchOpenSpring = Animation.spring(response: 0.42, dampingFraction: 0.8)
let notchCloseSpring = Animation.spring(response: 0.45, dampingFraction: 1)
/// Moving between pages, and the Notch resizing to fit one: open, as in Electron where a resize uses the open spring.
let notchPageSpring = notchOpenSpring

/// What a page swaps in and out with. The new one eases in under the growing shape; the old one is gone in a beat, so two
/// pages never overlap on the way: Vibe Notch's content transition exactly (0.8 scale from the top, `.smooth(0.35)` in, 0.15s out).
private var pageTransition: AnyTransition {
    .asymmetric(
        insertion: .scale(scale: 0.8, anchor: .top).combined(with: .opacity).animation(.smooth(duration: 0.35)),
        removal: .opacity.animation(.easeOut(duration: 0.15)))
}

/// What the dock and the apps tray come in with: a beat after the Notch (Electron's 0.04s and 0.06s), and out fast.
private func chromeTransition(delay: Double, anchor: UnitPoint, offset: CGSize) -> AnyTransition {
    .asymmetric(
        insertion: .scale(scale: 0.92, anchor: anchor).combined(with: .offset(offset)).combined(with: .opacity)
            .animation(notchOpenSpring.delay(delay)),
        removal: .scale(scale: 0.94, anchor: anchor).combined(with: .opacity).animation(.easeOut(duration: 0.12)))
}

/// The circles that move between views. The white highlight slides to the chosen one.
private struct ViewSwitcher: View {
    @Binding var page: NotchPage
    let pages: [NotchPage]
    let style: NotchStyle
    let flavor: Flavor
    @Binding var locked: Bool
    var onLock: () -> Void
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 3) {
            ForEach(pages, id: \.self) { item in
                Button { withAnimation(notchPageSpring) { page = item } } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item == page ? .black : .white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .background {
                            if item == page { Circle().fill(.white).matchedGeometryEffect(id: "highlight", in: highlight) }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.lively)
                .help(item.label)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(item == page ? .isSelected : [])
            }
            Capsule().fill(.white.opacity(0.1)).frame(width: 1, height: 14).padding(.horizontal, 2)
            // The lock: pinning is something you can see and do. Locked, it is the white circle like the chosen view.
            Button { locked.toggle(); onLock() } label: {
                Image(systemName: locked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(locked ? .black : .white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background { if locked { Circle().fill(.white) } }
                    .contentShape(Circle())
            }
            .buttonStyle(.lively)
            .help(locked ? "Unlock" : "Keep open")
            .accessibilityLabel(locked ? "Unlock" : "Keep open")
            .accessibilityAddTraits(locked ? .isSelected : [])
            Button { NotificationCenter.default.post(name: .openSettings, object: nil) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.lively)
            .help("Settings")
            .accessibilityLabel("Settings")
            // Quit sits at the dock's end, like the Electron version's power button.
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.lively)
            .help("Quit CatNotch")
            .accessibilityLabel("Quit CatNotch")
        }
        .padding(.horizontal, 4)
        .frame(height: 32)
        .background(NotchFill(style: style, flavor: flavor, shape: Capsule())) // the dock wears the Notch's own fill
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
    }
}

struct NotchView: View {
    var model: NotchModel
    var focus: FocusModel
    var tasks: TaskModel
    var nowPlaying: NowPlayingModel
    var agenda: AgendaModel
    var shelf: ShelfModel
    var screenshots: ScreenshotModel
    var system: SystemModel
    var usage: UsageModel
    var claude: ClaudeModel
    @State private var dropTargeted = false

    /// The next timed event today, for Home's line. ponytail: read when the view re-evaluates, so the line can outlive its event
    /// until the next change; a clock-driven refresh if that is noticed.
    private var nextEvent: AgendaEvent? {
        guard agenda.eventsAccess == .granted && agenda.showCalendar else { return nil }
        return Agenda.nextToday(Agenda.visible(agenda.events, hidden: agenda.hidden).filter { $0.kind == .event }, now: Date())
    }

    /// What the open Notch holds on the current page, sized as the Electron Notch sizes it.
    private func pageContent(glance: Bool) -> CGSize {
        switch model.page {
        case .home:
            var tiles: [CGFloat] = model.showAvatar ? [model.dayOpen ? NotchLayout.companionDayWidth : NotchLayout.companionWidth] : []
            if model.showMusic && nowPlaying.hasTrack { tiles.append(NotchLayout.musicWidth) }
            if usage.available { tiles.append(UsageTile.width(usage)) }
            if tiles.isEmpty { tiles.append(NotchLayout.timeWidth) } // the time is the last resort, when nothing else shows
            return NotchLayout.homeContent(tiles: tiles, glance: glance, nextEvent: nextEvent != nil)
        case .desk: return NotchLayout.deskContent
        case .calendar: return agenda.showCalendar ? NotchLayout.calendarContent(weeks: Agenda.weeks(model.calendarMonth)) : NotchLayout.filesContent
        case .reminders: return NotchLayout.remindersContent
        case .files: return NotchLayout.filesContent
        case .claude: return NotchLayout.claudeSessionsContent(count: claude.sessions.count)
        }
    }

    /// What each side of the closed Notch measures, so the wings fit it.
    @State private var leftWidth: CGFloat = 0
    @State private var rightWidth: CGFloat = 0

    var body: some View {
        let closed = model.hover.closed
        let wing = NotchSize.wing(content: max(leftWidth, rightWidth)) // fitted to what the closed Notch shows
        let glance = !system.bluetooth.isEmpty || system.micInUse || system.cameraInUse
        let request = claude.requests.first
        let finished = request == nil ? claude.finished : nil
        let stripOnly = model.peek && (request != nil || finished != nil)
        let stripHeight = request?.stripHeight(open: claude.open) ?? finished.map { _ in NotchLayout.claudeFinished }
        let content = stripHeight.map { NotchLayout.withStrip(stripOnly ? nil : pageContent(glance: glance), strip: $0) } ?? pageContent(glance: glance)
        let wanted = NotchLayout.open(content: content, closedHeight: closed.height)
        // On a hardware notch the closed shape overlaps the real one a little, so no edge of it shows around ours.
        let bleed = model.cutout > 0 ? NotchLayout.cutoutBleed : 0
        let size = model.isOpen ? wanted : CGSize(width: closed.width + 2 * bleed, height: closed.height + bleed)
        // Vibe Notch's radii: the top ones flare into the screen's edge and the bottom ones round it, all animated with the size.
        // The frame is `2 * top` wider than the Notch, since the shape's sides sit `top` in from its edge.
        let top = model.isOpen ? NotchLayout.openEar : NotchLayout.ear
        let shape = NotchShape(topCornerRadius: top, bottomCornerRadius: model.isOpen ? 24 : 14)
        let frameSize = CGSize(width: size.width + 2 * top, height: size.height)
        let spring = model.isOpen ? notchOpenSpring : notchCloseSpring
        VStack(spacing: 4) {
        ZStack(alignment: .top) {
            NotchFill(style: model.style, flavor: model.flavor, shape: shape)
            // The hardware cutout stays black in every style, so the Notch still grows out of it.
            // Its bottom corners are curved like the real notch's, or a square block would poke out of them.
            if model.cutout > 0 {
                UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14).fill(.black)
                    .frame(width: model.cutout + 2 * bleed, height: closed.height)
            }

            // The ambient glow along the bottom of Home while music plays, in the companion's colour. It is only made while
            // it shows, so a closed Notch or another page has no player running.
            let ambient = model.isOpen && !stripOnly && model.page == .home && model.ambientVideo && nowPlaying.isPlaying
            Group {
                if ambient {
                    AmbientVideo(shift: AmbientShift(accent: model.character.accent(flavor: model.flavor, coat: model.coat)))
                        .frame(width: frameSize.width, height: size.height * 0.9)
                        .frame(width: frameSize.width, height: size.height, alignment: .bottom)
                        .clipShape(shape)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.8), value: ambient)

            if model.isOpen {
                VStack(spacing: NotchLayout.gap) {
                    if let request { ClaudeStrip(request: request, count: claude.requests.count, accent: Color(hex: model.character.accent(flavor: model.flavor, coat: model.coat)), claude: claude).id(request.id) }
                    if let finished { ClaudeFinishedBanner(title: finished.title, accent: Color(hex: model.character.accent(flavor: model.flavor, coat: model.coat)), claude: claude) }
                    if stripOnly {
                        // the request alone: the page waits for the pointer
                    } else if model.page == .desk {
                        // Focus tile in a fixed column, centred in it and in the row's height; the list fills the rest and scrolls
                        // inside the page's own size, so nothing moves as the time, buttons or tasks change.
                        HStack(alignment: .center, spacing: 28) {
                            FocusTile(focus: focus)
                                .frame(width: 330, height: NotchLayout.deskContent.height, alignment: .center)
                                .offset(y: -4) // optically centred: the closed bar above is taller than the padding below
                            TasksList(tasks: tasks).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                        .frame(width: NotchLayout.deskContent.width, height: NotchLayout.deskContent.height, alignment: .top)
                    } else if model.page == .home {
                        VStack(spacing: 10) {
                            HStack(spacing: NotchLayout.gap) {
                                if model.showAvatar { CompanionTile(model: model, focus: focus, tasks: tasks, nowPlaying: nowPlaying) }
                                if model.showMusic && nowPlaying.hasTrack { NowPlayingCard(nowPlaying: nowPlaying) } // playing or paused; gone when stopped or stale
                                if usage.available { UsageTile(usage: usage, room: .infinity) } // the Notch is as wide as its tiles
                                if !model.showAvatar && !(model.showMusic && nowPlaying.hasTrack) && !usage.available { TimeTile() }
                            }
                            if glance { GlanceRow(system: system) }
                            if let nextEvent { NextEventLine(event: nextEvent) }
                        }
                        .task(id: usage.available) { if usage.available { await usage.poll() } } // looks again every 30 s while Home is open
                    } else if model.page == .calendar && agenda.showCalendar {
                        CalendarPage(agenda: agenda, tasks: tasks, month: Bindable(model).calendarMonth, selected: Bindable(model).calendarDay)
                    } else if model.page == .claude {
                        ClaudeSessionsPage(claude: claude, accent: Color(hex: model.character.accent(flavor: model.flavor, coat: model.coat)))
                    } else if model.page == .reminders {
                        RemindersPage(agenda: agenda)
                    } else {
                        FilesPage(shelf: shelf, screenshots: screenshots, targeted: dropTargeted || model.fileDrag)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, NotchLayout.side).padding(.bottom, NotchLayout.bottom)
                .padding(.top, closed.height + NotchLayout.topGap)
                // Laid out once at the open size and only uncovered as the shape springs around it, never squeezed into the
                // growing frame (it reflowed and repainted on every frame of the spring, and an outgoing page kept squashing).
                .frame(width: wanted.width, height: wanted.height, alignment: .top)
                .id(model.page) // a page change swaps the content: the old one fades out as the new one eases in under the growing shape
                .transition(pageTransition)
            } else {
                // The Electron Notch's closed bar: what is happening on the left, inset from the edge (8pt on a hardware notch,
                // 20pt on the pill); the time and the mic and camera dots on the right. Nothing is drawn inside the cutout.
                let left: ClosedLeft = system.headphones != nil ? .headphones : focus.phase == .running ? .focus : model.closedCompanion ? .companion : model.closedClock ? .clock : .none
                let rightClock = model.closedClock && left != .clock && left != .headphones && !nowPlaying.hasTrack // the clock moves over when the left has something else
                let dots = system.micInUse || system.cameraInUse
                ZStack {
                    Group {
                        switch left {
                        case .headphones: ClosedHeadphones(name: system.headphones ?? "")
                        case .focus: ClosedFocus(focus: focus)
                        // The companion (the ghost unless chosen), at rest: a still picture, so a closed Notch costs no frames.
                        // The photo is not drawn this small; it falls back to the ghost.
                        case .companion: CompanionStill(character: model.character == .photo ? .ghost : model.character, flavor: model.flavor, coat: model.coat, size: 20)
                        case .clock: ClosedClock()
                        case .none: EmptyView()
                        }
                    }
                    .fixedSize() // hug the content: a flexible frame would take all the room offered and read as a full wing
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { leftWidth = $0 }
                    .id(left)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        if rightClock { ClosedClock() }
                        if dots { PrivacyDots(system: system) }
                        if nowPlaying.hasTrack { PulsingArt(image: nowPlaying.art, tint: nowPlaying.tint, playing: nowPlaying.isPlaying) } // the art on the right, swelling and easing back while playing, still when paused
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { rightWidth = $0 }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, model.cutout > 0 ? NotchLayout.closedInset : NotchLayout.closedInsetPill)
                .frame(width: size.width, height: closed.height)
            }
        }
        // Top aligned: a taller page's content is at its full height at once while this frame springs to it, and a centred
        // frame would shift the whole Notch up by half the difference until the spring settles.
        .frame(width: frameSize.width, height: frameSize.height, alignment: .top)
        .clipShape(shape)
        // Vibe Notch's soft shadow while open, which fades in and out with the spring. Black only: a shadow shows through
        // a translucent fill.
        .shadow(color: model.isOpen && model.style == .black ? .black.opacity(0.7) : .clear, radius: 6)
        .onChange(of: model.page) { // the day and month are chosen per visit: leaving Calendar gives the arrows back to sections
            if model.page != .calendar { model.calendarDay = nil; model.calendarMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))! }
        }
        .onChange(of: wing, initial: true) { // the closed Notch is as wide as what it shows, on a hardware notch
            model.wing = wing
            if model.cutout > 0 { model.hover.closed.width = model.cutout + 2 * wing }
        }
        .animation(notchPageSpring, value: closed.width)
        .onChange(of: wanted, initial: true) { model.hover.open = wanted; model.resized?() } // the hit area and the panel follow the page
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: drop) // files dropped anywhere on the open Notch go on the shelf
        .overlay(alignment: .topTrailing) { // outside the clip, in the panel's side room
            if model.isOpen && !stripOnly && !system.apps.isEmpty {
                AppsTray(system: system, style: model.style, flavor: model.flavor)
                    .offset(x: 48)
                    .transition(chromeTransition(delay: 0.06, anchor: .topLeading, offset: CGSize(width: -10, height: 0)))
            }
        }
            // The dock hangs under the open Notch as its own pill, like the Electron version, and pops in a beat after it.
            // Locked open, the dock steps away until the pointer is back on the Notch (as in Electron), so a locked Notch is
            // just its content; hovering brings it back, and the lock with it.
            if model.isOpen && !stripOnly && (!model.locked || model.pointerInside) {
                ViewSwitcher(page: Bindable(model).page, pages: NotchPage.shown(calendar: agenda.showCalendar, off: model.pagesOff), style: model.style, flavor: model.flavor,
                             locked: Bindable(model).locked, onLock: { model.onLock?() })
                    .transition(chromeTransition(delay: 0.04, anchor: .top, offset: CGSize(width: 0, height: -10)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(spring, value: model.isOpen)
        .animation(notchPageSpring, value: wanted) // any resize (page, music starting, chips) glides, not only a page tap
        .environment(\.colorScheme, .dark) // materials stay dark whatever the system appearance is
        .environment(\.companionAccent, Color(hex: model.character.accent(flavor: model.flavor, coat: model.coat)))
        .environment(\.notchTint, model.tint)
        .ignoresSafeArea() // a hardware notch would otherwise push the drawing below the hit rect
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else { return false }
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { [shelf, model] url, _ in
                guard let url, url.isFileURL else { return }
                Task { @MainActor in
                    model.fileDrag = false
                    shelf.add([url])
                    withAnimation(notchPageSpring) { model.page = .files }
                }
            }
        }
        return true
    }
}

// 900pt wide: the Focus & tasks page alone is 720pt, and a narrower frame clips the Notch.
#Preview("Notch open", traits: .fixedLayout(width: 900, height: 340)) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("catnotch-preview")
    let store = CatNotchStore(directory: dir, legacyDirectory: dir)
    let model = NotchModel(open: CGSize(width: 620, height: 300))
    return NotchView(model: model, focus: FocusModel(store: store), tasks: TaskModel(store: store),
                     nowPlaying: NowPlayingModel(), agenda: AgendaModel(store: store),
                     shelf: ShelfModel(store: store), screenshots: ScreenshotModel(),
                     system: SystemModel(), usage: UsageModel(store: store), claude: ClaudeModel(store: store))
        .background(.gray.opacity(0.3))
        // ponytail: preview only, hovering anywhere in the frame opens it; the real hit area is the panel's pointer tracking
        .onHover { model.isOpen = $0 }
}
