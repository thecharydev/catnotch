import SwiftUI
import CatNotchCore

private let orbColor = Tint(r: 0xB4 / 255, g: 0xBE / 255, b: 0xFE / 255) // Catppuccin lavender, like the rest of the Notch's accents
private let warningColor = Tint(r: 1, g: 95 / 255, b: 46 / 255) // the old Notch's orange, for a limit nearly gone

/// Dots on latitude rings, so a turning globe reads as turning (the same lattice as the Electron Notch's orbs).
private let globe: [(lat: Double, lon: Double)] = (0..<9).flatMap { ring -> [(lat: Double, lon: Double)] in
    let lat = (Double(ring) + 0.5) / 9 * .pi - .pi / 2
    let count = max(4, Int((24 * cos(lat)).rounded()))
    return (0..<count).map { (lat, Double($0) / Double(count) * 2 * .pi) }
}

/// A dotted globe turning left to right, filled like a tank from the bottom. A port of the globe `Complication` draws
/// with `thinking-orbs` (same lattice, projection and ink): dots above the waterline stay a faint outline, and the line
/// ripples so a full or empty globe still reads as liquid.
private struct Orb: View {
    let fraction: Double
    let tint: Tint

    var body: some View {
        ZStack {
            Circle().fill(tint.color).blur(radius: 8).padding(8).opacity(0.06 + 0.22 * fraction) // light from the filled part
            // 20 fps is plenty for slow dots; the timeline only runs while the tile is on screen.
            TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    let projection = Projection(yaw: t * 0.55, tilt: 0.35, cx: size.width / 2, cy: size.height / 2, scale: size.width * 0.44)
                    let unit = size.width / 64
                    let dots = globe.map { dot -> (x: Double, y: Double, z: Double, r: Double, white: Double, alpha: Double) in
                        let wy = sin(dot.lat)
                        let (x, y, z) = projection(cos(dot.lat) * cos(dot.lon), wy, cos(dot.lat) * sin(dot.lon))
                        let near = (z + 1) / 2
                        let level = -1 + 2 * fraction + sin(dot.lon * 3 + t * 2.2) * 0.05
                        return wy > level
                            ? (x, y, z, max(0.25 * unit, (0.25 + 0.4 * near) * unit), 0.7 - 0.3 * near, 0.22)
                            : (x, y, z, max(0.25 * unit, (0.4 + 0.75 * near) * unit), 0.5 - 0.48 * near, 1)
                    }
                    for dot in dots.sorted(by: { $0.z < $1.z }) { // far dots first, so near ones sit on top
                        let rect = CGRect(x: dot.x - dot.r, y: dot.y - dot.r, width: dot.r * 2, height: dot.r * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(tint.ink(white: dot.white).opacity(dot.alpha)))
                    }
                }
            }
        }
    }
}

/// `makeProj` of thinking-orbs: spin by `yaw`, lean by `tilt`, drop the depth onto the screen (z stays for ordering).
private struct Projection {
    let yaw: Double, tilt: Double, cx: Double, cy: Double, scale: Double

    func callAsFunction(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
        let x1 = x * cos(yaw) + z * sin(yaw), z1 = -x * sin(yaw) + z * cos(yaw)
        return (cx + x1 * scale, cy - (y * cos(tilt) - z1 * sin(tilt)) * scale, y * sin(tilt) + z1 * cos(tilt))
    }
}

/// An orb's colour as RGB 0 to 1, since the dots shade it toward black the way the library's dark theme does.
private struct Tint {
    let r: Double, g: Double, b: Double
    var color: Color { Color(red: r, green: g, blue: b) }
    func ink(white: Double) -> Color { let k = 1 - min(1, max(0, white)); return Color(red: r * k, green: g * k, blue: b * k) }
}

/// "Claude 5h · 58% used · resets in 2h 14m", for VoiceOver.
private func detail(_ name: String, _ limit: Limit) -> String {
    "\(name) \(limit.short.lowercased()) · \(Int(limit.used.rounded()))% used"
        + (limit.resetsAt.map { " · resets in \(ResetText.full($0, now: Date()))" } ?? "")
}

/// One window of one tool, as the Electron Notch drew it: an orb with the percent used under it, and then the name
/// ("Claude 5h") that turns into what is left and when it refills ("88% left · 4h") while the pointer is on it.
private struct Gauge: View {
    let name: String
    let limit: Limit
    /// Set while the numbers are old or their window has reset (spec 0046): the orb is dimmed and this replaces the name.
    var note: String?
    /// 1 is the Electron Notch's size (a 64pt orb in a 72pt column); less only when the row is short of room.
    let scale: CGFloat
    @State private var on = false

    var body: some View {
        let used = Int(limit.used.rounded())
        let color = limit.isNearlyOut ? warningColor : orbColor
        let column = 72 * scale, size = 64 * scale
        let hint = "\(100 - used)% left" + (limit.resetsAt.map { " · \(ResetText.short($0, now: Date()))" } ?? "")
        VStack(spacing: 8 * scale) {
            Orb(fraction: limit.used / 100, tint: color)
                .frame(width: size, height: size)
                .scaleEffect(on ? 1.04 : 1)
                .opacity(note == nil ? 1 : 0.4)
            HStack(alignment: .firstTextBaseline, spacing: 0) { // the percent under the orb, its unit small beside it
                Text("\(used)").font(.system(size: 17 * max(scale, 0.8), weight: .semibold).monospacedDigit()).tracking(-0.5)
                Text("%").font(.system(size: 10 * max(scale, 0.8), weight: .medium)).opacity(0.4)
            }
            .foregroundStyle(color.color)
            .opacity(note == nil ? 1 : 0.5)
            Text(on ? hint : note ?? "\(name) \(limit.short.lowercased())")
                .font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(on ? 0.8 : 0.45))
                .lineLimit(1).minimumScaleFactor(0.7).frame(width: column)
        }
        .frame(width: column)
        .contentShape(Rectangle())
        .background(PointerOver { on = $0 })
        .animation(.easeOut(duration: 0.15), value: on)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(detail(name, limit)), \(used) percent used" + (note.map { ", \($0)" } ?? ""))
    }
}

/// A tool whose reading failed, in place of its orbs: why, and a retry. The arrow turns while it checks.
private struct RetryGauge: View {
    let name: String
    let error: LimitsError
    var usage: UsageModel
    @State private var busy = false

    var body: some View {
        Button {
            guard !busy else { return }
            busy = true
            Task {
                async let turn: Void = (try? await Task.sleep(for: .milliseconds(700))) ?? () // one full turn, so a fast answer still reads as "checked"
                await usage.refresh(force: true)
                await turn
                busy = false
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    .rotationEffect(.degrees(busy ? 360 : 0))
                    .animation(busy ? .linear(duration: 0.7).repeatForever(autoreverses: false) : .default, value: busy)
                    .frame(width: 46, height: 46).background(Circle().fill(.white.opacity(0.1)))
                VStack(spacing: 3) {
                    Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                    Text(busy ? "Checking…" : error == .expired ? "Sign in again" : "Tap to retry")
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.lively)
        .accessibilityLabel("\(name): \(error == .expired ? "sign in again" : "could not be read"). Check again")
    }
}

/// Takes a fresh reading now, past the usual gap and back-off. One object throughout: the refresh icon folds its arrowhead
/// into the path while it speeds up into a spinning ring, runs as long as a check really is running (a tap, the Notch
/// opening, the poll), then slows, closes the arc and unfolds the arrowhead exactly as it was. The numbers come from
/// `ReloadMotion`; this only draws them. With Reduce Motion it stays still and dims while checking.
private struct ReloadButton: View {
    var usage: UsageModel
    @State private var tapping = false
    @State private var motion: ReloadMotion?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var loading: Bool { tapping || usage.refreshing }

    var body: some View {
        Button {
            guard !tapping, motion == nil else { return } // a tap during a check or while it settles does nothing more
            tapping = true
            Task {
                await usage.refresh(force: true)
                try? await Task.sleep(for: .milliseconds(350)) // an instant answer still shows the whole morph
                tapping = false
            }
        } label: {
            TimelineView(.animation(paused: motion == nil)) { timeline in
                let frame = motion?.frame(at: timeline.date.timeIntervalSinceReferenceDate) ?? ReloadMotion.rest
                Canvas { context, size in
                    context.stroke(Self.icon(frame, size: size), with: .color(.white.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: 18, height: 18)
            .opacity(reduceMotion && loading ? 0.4 : 1)
            .frame(width: 22, height: 22).contentShape(Circle())
        }
        .buttonStyle(.lively)
        .onChange(of: loading, initial: true) { _, on in
            guard !reduceMotion else { return }
            let now = Date.timeIntervalSinceReferenceDate
            if on {
                if motion?.settledAt != nil || motion == nil { motion = ReloadMotion(start: now) }
            } else if var running = motion, running.settledAt == nil {
                running.finish(at: now)
                motion = running
                let start = running.start, settled = running.settledAt ?? now
                Task { // paused again once it is back at rest
                    try? await Task.sleep(for: .seconds(max(0, settled - Date.timeIntervalSinceReferenceDate) + 0.05))
                    if motion?.start == start { motion = nil }
                }
            }
        }
        .help("Check AI usage now")
        .accessibilityLabel("Reload AI usage")
    }

    /// The arc from its tail to its head, and two wings at the head that fold back into the path as `head` goes to 0.
    private static func icon(_ frame: ReloadMotion.Frame, size: CGSize) -> Path {
        let center = CGPoint(x: size.width / 2, y: size.height / 2), radius = 4.3
        func point(_ degrees: Double) -> CGPoint { CGPoint(x: center.x + radius * cos(degrees * .pi / 180), y: center.y + radius * sin(degrees * .pi / 180)) }
        let head = ReloadMotion.iconHead + frame.rotation
        var path = Path()
        path.move(to: point(head - frame.sweep))
        for degrees in stride(from: head - frame.sweep + 3, to: head, by: 3) { path.addLine(to: point(degrees)) }
        path.addLine(to: point(head))
        guard frame.head > 0.001 else { return path }
        let tip = point(head), along = (head + 90) * .pi / 180 // clockwise along the path at the tip
        let length = 3.0 * frame.head, spread = 42 * frame.head * .pi / 180
        for side in [-1.0, 1.0] {
            let back = along + .pi + side * spread
            path.move(to: CGPoint(x: tip.x + length * cos(back), y: tip.y + length * sin(back)))
            path.addLine(to: tip)
        }
        return path
    }
}

/// The question asked once before any login is read.
private struct ConsentBody: View {
    var usage: UsageModel
    @State private var showSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Show AI usage limits?").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                SourceInfo(source: .aiUsage, open: $showSource)
            }
            // The icon swaps the one line for the whole list: what is read, from where, and where it is sent.
            if showSource {
                ScrollView { SourceLines(source: .aiUsage, size: 10) }.scrollIndicators(.never)
            } else {
                Text(DataSource.aiUsage.summary)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button { usage.answer(true) } label: {
                    Text("Allow").foregroundStyle(.black).padding(.horizontal, 16).frame(minHeight: 26).background(Capsule().fill(.white))
                }
                Button("Not now") { usage.answer(false) }.foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.lively).font(.system(size: 12, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The third place on Home: one card per signed-in tool (as in the Electron Notch), each with an orb per window.
/// `room` is what the other tiles leave. A card is 24pt of padding plus 72pt per orb, as in Electron; the whole row
/// shrinks together only when that does not fit (two tools beside a playing track).
struct UsageTile: View {
    var usage: UsageModel
    let room: CGFloat
    private let gap = NotchLayout.gap

    /// How wide the tile row wants to be, so the Notch can be as wide as its tiles (as in Electron).
    @MainActor static func width(_ usage: UsageModel) -> CGFloat {
        guard !usage.needsConsent, let providers = usage.providers, !providers.isEmpty else { return NotchLayout.usageMessageWidth }
        let natural = providers.map { p -> CGFloat in if case .limits(let l) = p.reading { 24 + 72 * CGFloat(l.count) } else { 96 } }
        return natural.reduce(0, +) + NotchLayout.gap * CGFloat(providers.count - 1)
    }

    var body: some View {
        if usage.needsConsent {
            ConsentBody(usage: usage).homeTile(width: min(room, NotchLayout.usageMessageWidth))
        } else if let providers = usage.providers, !providers.isEmpty {
            let columns = { (p: ProviderLimits) -> CGFloat in if case .limits(let l) = p.reading { CGFloat(l.count) } else { 1 } }
            let natural = providers.map { 24 + 72 * columns($0) }
            let scale = min(1, (room - gap * CGFloat(providers.count - 1)) / natural.reduce(0, +))
            TimelineView(.periodic(from: .now, by: 15)) { clock in // nothing else redraws the tile as readings age
                HStack(spacing: gap) {
                    ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                        HStack(spacing: 0) {
                            switch provider.reading {
                            case .limits(let limits):
                                ForEach(limits, id: \.label) { Gauge(name: provider.name, limit: $0, note: provider.note(for: $0, now: clock.date), scale: scale) }
                            case .failed(let error): RetryGauge(name: provider.name, error: error, usage: usage)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .homeTile(width: natural[index] * scale)
                        .overlay(alignment: .topTrailing) { // every card reloads (the same check for both tools); a failed one has its own retry
                            if case .limits = provider.reading { ReloadButton(usage: usage).padding(4) }
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                if usage.providers == nil { ProgressView().controlSize(.small).colorScheme(.dark) }
                Text(usage.providers == nil ? "Checking…" : "No \(usage.enabledNames) sign-in found on this Mac.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .homeTile(width: min(room, NotchLayout.usageMessageWidth))
        }
    }
}
