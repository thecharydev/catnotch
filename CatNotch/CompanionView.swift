import AppKit
import CatNotchCore
import SwiftUI

/// Holds the simulation between frames. A plain class: drawing a frame must not invalidate the view.
@MainActor
final class CompanionDriver {
    var sim = CompanionSim(seed: .random(in: 0..<1))
    weak var host: NSView?
    private var last: Date?
    private var burstUntil = Date.distantPast

    /// Something worth a cheer happened (a track, a task, the timer): busy for a moment.
    func burst(now: Date = Date()) { burstUntil = now.addingTimeInterval(1.8) }

    /// Advances to `now` and returns the pose to draw: the state from the clock and any burst, the head and eyes
    /// following the pointer when it comes within three boxes. `looks` and `sleeps` are the Look around and Sleep at
    /// night switches; with Look around off the pointer is not even read.
    func step(_ now: Date, box: CGFloat, looks: Bool, sleeps: Bool) -> CompanionPose {
        let dt = last.map { now.timeIntervalSince($0) } ?? 0
        last = now
        sim.looksAround = looks
        sim.setState(.current(hour: Calendar.current.component(.hour, from: now), bursting: now < burstUntil, sleeps: sleeps))
        if looks, let view = host, let window = view.window, view.bounds.width > 0 {
            // Read the pointer where it is, so it works while the panel is not the key window.
            let p = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            let size = Double(box)
            let dx = (p.x - view.bounds.midX) / size, dy = (p.y - (view.bounds.midY + CompanionRenderer.rise * size)) / size
            let d = hypot(dx, dy)
            sim.setPointer(x: dx / max(1, d), y: dy / max(1, d), strength: d < 1 ? 1 : d > 3 ? 0 : (3 - d) / 2)
        }
        sim.update(dt)
        return sim.pose
    }
}

/// Gives the driver the canvas's NSView, flipped so its origin is the top left like SwiftUI's.
private struct PointerHost: NSViewRepresentable {
    let driver: CompanionDriver

    final class Flipped: NSView { override var isFlipped: Bool { true } }

    func makeNSView(context: Context) -> Flipped {
        let view = Flipped()
        driver.host = view
        return view
    }

    func updateNSView(_ view: Flipped, context: Context) { driver.host = view }
}

/// A character, drawn on a canvas at 30 frames a second while it is on screen. A click makes it hop and turn round.
struct CompanionCat: View {
    let driver: CompanionDriver
    let look: CompanionLook
    let box: CGFloat
    var looks = false
    var sleeps = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let side = box * CompanionRenderer.overscan
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, _ in
                let pose = reduceMotion ? CompanionPose(rest: .idle) : MainActor.assumeIsolated { driver.step(timeline.date, box: box, looks: looks, sleeps: sleeps) }
                context.withCGContext { CompanionRenderer.draw($0, box: box, pose: pose, look: look) }
            }
        }
        .frame(width: side, height: side)
        .background(PointerHost(driver: driver))
        .contentShape(Rectangle())
        .onTapGesture { driver.sim.poke() }
        .pointerCursor()
        .offset(y: -CompanionRenderer.rise * box) // the body sits low in its canvas, to leave room for a hop
        .frame(width: box, height: box) // the hop and the turn spill past this, into the tile's padding
        .accessibilityElement()
        .accessibilityLabel("\(look.character.label) companion")
    }
}

/// The user's photo as the companion: a round picture that hops when it has something to cheer or is clicked.
private struct CompanionPhoto: View {
    let image: NSImage
    let box: CGFloat
    let pulse: Int
    @State private var lift = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(nsImage: image).resizable().scaledToFill()
            .frame(width: box, height: box).clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.15)))
            .offset(y: lift)
            .onTapGesture(perform: hop)
            .pointerCursor()
            .onChange(of: pulse) { hop() }
            .accessibilityElement().accessibilityLabel("Your photo companion")
    }

    private func hop() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.16)) { lift = -14 } completion: { withAnimation(.interpolatingSpring(stiffness: 260, damping: 9)) { lift = 0 } }
    }
}

/// The companion's place on Home, first in the row: the chosen character (or the user's photo). It hops when a track
/// starts, a task is done or the timer changes (React to events), turns to look around (Look around) and sleeps
/// through the night (Sleep at night).
struct CompanionTile: View {
    @Environment(\.companionAccent) private var accent
    var model: NotchModel
    var focus: FocusModel
    var tasks: TaskModel
    var nowPlaying: NowPlayingModel
    var system: SystemModel
    @State private var driver = CompanionDriver()
    @State private var pulse = 0
    @State private var photo: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if model.character == .photo, let photo {
                    CompanionPhoto(image: photo, box: 60, pulse: pulse)
                } else {
                    // A photo that is not chosen yet or cannot be read leaves the ghost, rather than an empty tile.
                    CompanionCat(driver: driver, look: CompanionLook(character: model.character == .photo ? .ghost : model.character, flavor: model.flavor, coat: model.coat),
                                 box: 68, looks: model.companionLook, sleeps: model.companionSleeps)
                }
            }
            .frame(width: 96).frame(maxHeight: .infinity)
            ClockMode(expanded: model.dayOpen, device: model.showBluetooth ? system.bluetooth.first { $0.battery != nil } : nil)
        }
        .homeTile(width: model.dayOpen ? NotchLayout.companionDayWidth : NotchLayout.companionWidth, tint: accent) // the glow behind the companion, in its colour
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture { withAnimation(notchPageSpring) { model.dayOpen.toggle() } } // a tap unfolds the day, as in Electron
        .pointerCursor()
        .help(model.dayOpen ? "Fold the day" : "Show the day")
        .onChange(of: focus.phase) { cheer() }
        .onChange(of: tasks.done.count) { old, new in if new > old { cheer() } }
        .onChange(of: nowPlaying.current?.title) { _, title in if title != nil { cheer() } }
        .task { system.refreshBluetooth() } // opening the Notch is the moment to look again; the call skips itself when it has looked recently
        .task(id: model.photo) { photo = model.character == .photo ? Self.thumbnail(model.photo) : nil }
        .onChange(of: model.character) { photo = model.character == .photo ? Self.thumbnail(model.photo) : nil }
    }

    private func cheer() {
        guard model.companionReacts else { return }
        driver.burst()
        pulse += 1
    }

    /// The photo shrunk to what the tile needs; a camera original can be many megabytes.
    static func thumbnail(_ file: FileRef?) -> NSImage? {
        guard let url = file?.url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 240] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
}

/// A character at rest, small, for the picker in Settings.
struct CompanionStill: View {
    let character: CompanionCharacter
    let flavor: Flavor
    var coat: UInt32?
    let size: CGFloat

    var body: some View {
        let look = CompanionLook(character: character, flavor: flavor, coat: coat)
        Canvas { context, _ in
            context.withCGContext { CompanionRenderer.draw($0, box: size, pose: CompanionPose(rest: .idle), look: look) }
        }
        .frame(width: size * CompanionRenderer.overscan, height: size * CompanionRenderer.overscan)
        .offset(y: -CompanionRenderer.rise * size)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
