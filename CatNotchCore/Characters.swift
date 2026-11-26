import CoreGraphics
import Foundation

/// Who sits on Home's companion tile: the Catppuccin cat, the seven bots of the Electron app, Claude Code's mascot and the user's own photo.
/// The bots are the `bot-avatars` library's outlines (MIT), the orange `cat` among them; the Catppuccin cat is our own.
public enum CompanionCharacter: String, CaseIterable, Sendable {
    case catppuccin, cat, claude, ghost, blob, clover, droid, alien, cloud, photo

    /// The saved `avatar`. Unset or unknown is the ghost, as in the Electron app.
    public init(setting: String?) { self = setting.flatMap(CompanionCharacter.init(rawValue:)) ?? .ghost }

    public var label: String {
        switch self {
        case .catppuccin: "Catppuccin cat"
        case .claude: "Claude Code"
        default: rawValue.capitalized
        }
    }

    /// The body's colour, 0xRRGGBB. The Catppuccin cat's body is the flavour's base; the photo has none.
    public func body(flavor: Flavor) -> UInt32 {
        switch self {
        case .catppuccin: flavor.base
        case .ghost: 0xf4f2fa
        case .cat: 0xff8c42
        case .claude: 0xd77757 // Claude Code's own orange
        case .blob: 0x2fcb7a
        case .clover: 0x35b8ff
        case .droid: 0xd5dbea
        case .alien: 0x9be85a
        case .cloud: 0xcfe6ff
        case .photo: 0xffffff
        }
    }

    /// The colour the companion lends the Notch (the ambient video follows it): the cat's face, a bot's own colour, white for a photo.
    public func accent(flavor: Flavor, coat: UInt32? = nil) -> UInt32 { self == .catppuccin ? coat ?? flavor.mauve : body(flavor: flavor) }

    /// Where the face sits on the 100 by 100 outline, and how big it is.
    var face: (x: Double, y: Double, scale: Double) {
        switch self {
        case .ghost: (50, 48, 0.95)
        case .cat: (50, 58, 1)
        case .claude: (50, 44, 1)
        case .blob: (49.5, 50, 1)
        case .droid: (50, 60, 0.95)
        case .alien: (50, 45, 1.05)
        case .cloud: (50, 58, 0.95)
        case .catppuccin, .clover, .photo: (50, 50, 1)
        }
    }

    /// Claude Code's eyes are solid blocks, not dots: its strokes end square.
    var squareEyes: Bool { self == .claude }

    /// Dark ink on a light body, light ink on a dark one (`bot-avatars`' `autoInk`).
    public static func autoInk(on body: UInt32) -> UInt32 {
        func linear(_ shift: UInt32) -> Double {
            let c = Double(body >> shift & 255) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0) < 0.13 ? 0xf7f5f2 : 0x1e1a33
    }

    /// The outline, in a 100 by 100 box. Nil for the photo, which is not drawn.
    public var outline: CGPath? { Self.outlines[self] }

    // The droid's antenna is part of its outline here (the library draws it as a thin part behind the body).
    nonisolated(unsafe) private static let outlines: [CompanionCharacter: CGPath] = {
        let d: [CompanionCharacter: String] = [
            .catppuccin: "M14 24 Q14 11 20 14 L36 25 Q50 20 63 24 L77 12 Q83 10 83 21 Q88 33 89 52 Q89 67 79 78 Q76 87 77 100 L23 100 Q24 87 21 78 Q11 67 11 52 Q11 38 14 24 Z",
            // Claude Code's mascot, blocky as in its banner: a wide body, an arm either side, four legs.
            .claude: "M20 25H80V70H20ZM8 42H20V58H8ZM80 42H92V58H80ZM28 70H36V84H28ZM40 70H48V84H40ZM52 70H60V84H52ZM64 70H72V84H64Z",
            .cat: "M50 20A36 36 0 1 1 50 92A36 36 0 1 1 50 20ZM24.72 44.64A4.5 4.5 0 0 1 17.35 40.67L20.21 16.66A4.5 4.5 0 0 1 26.86 13.26L42.3 21.83A4.5 4.5 0 0 1 43.02 29.21L24.72 44.64ZM82.65 40.67A4.5 4.5 0 0 1 75.28 44.64L56.98 29.21A4.5 4.5 0 0 1 57.7 21.83L73.14 13.26A4.5 4.5 0 0 1 79.79 16.66L82.65 40.67Z",
            .ghost: "M17 50C17 31.78 31.78 17 50 17C68.22 17 83 31.78 83 50V81.5Q72 93.5 61 81.5Q50 93.5 39 81.5Q28 93.5 17 81.5Z",
            .blob: "M93.92 50C94.18 51.9 94.24 53.9 93.99 55.79C93.73 57.68 93.18 59.61 92.39 61.36C91.6 63.1 90.48 64.78 89.27 66.27C88.07 67.76 86.58 69.08 85.14 70.29C83.7 71.49 82.1 72.5 80.62 73.5C79.14 74.49 77.64 75.34 76.24 76.24C74.84 77.15 73.51 78 72.2 78.93C70.88 79.86 69.66 80.83 68.36 81.8C67.06 82.76 65.78 83.82 64.39 84.74C63 85.67 61.55 86.63 60.01 87.35C58.47 88.08 56.82 88.73 55.15 89.1C53.48 89.47 51.71 89.64 50 89.57C48.29 89.5 46.55 89.16 44.91 88.68C43.27 88.21 41.67 87.47 40.16 86.72C38.65 85.96 37.24 85.02 35.86 84.13C34.48 83.24 33.19 82.29 31.89 81.37C30.58 80.46 29.32 79.56 28.03 78.63C26.74 77.71 25.44 76.82 24.16 75.84C22.88 74.86 21.57 73.87 20.36 72.74C19.15 71.62 17.95 70.42 16.91 69.1C15.88 67.79 14.92 66.35 14.15 64.85C13.38 63.35 12.76 61.73 12.29 60.1C11.81 58.48 11.52 56.78 11.29 55.1C11.06 53.41 10.98 51.71 10.91 50C10.83 48.29 10.83 46.59 10.83 44.84C10.84 43.1 10.85 41.34 10.93 39.53C11.02 37.72 11.09 35.86 11.34 33.99C11.59 32.12 11.88 30.16 12.43 28.31C12.99 26.46 13.69 24.56 14.66 22.88C15.64 21.21 16.86 19.58 18.27 18.27C19.69 16.96 21.4 15.84 23.17 15.03C24.93 14.22 26.95 13.71 28.89 13.43C30.83 13.15 32.9 13.21 34.82 13.36C36.74 13.5 38.66 13.92 40.43 14.28C42.2 14.65 43.87 15.16 45.46 15.54C47.06 15.93 48.52 16.31 50 16.58C51.48 16.85 52.87 17.02 54.32 17.17C55.77 17.32 57.22 17.36 58.71 17.49C60.2 17.62 61.74 17.7 63.28 17.95C64.81 18.19 66.39 18.5 67.91 18.98C69.43 19.46 70.95 20.08 72.38 20.83C73.81 21.58 75.19 22.5 76.5 23.5C77.81 24.5 79.03 25.63 80.22 26.81C81.41 27.99 82.54 29.25 83.65 30.57C84.76 31.89 85.85 33.26 86.89 34.72C87.93 36.18 88.98 37.69 89.9 39.31C90.82 40.92 91.73 42.64 92.4 44.42C93.07 46.2 93.66 48.1 93.92 50Z",
            .clover: "M26.53 22.38A25 25 0 0 1 73.47 22.38A7 7 0 0 0 77.62 26.53A25 25 0 0 1 77.62 73.47A7 7 0 0 0 73.47 77.62A25 25 0 0 1 26.53 77.62A7 7 0 0 0 22.38 73.47A25 25 0 0 1 22.38 26.53A7 7 0 0 0 26.53 22.38Z",
            .droid: "M16 50C16 38.95 24.95 30 36 30H64C75.05 30 84 38.95 84 50V70C84 81.05 75.05 90 64 90H36C24.95 90 16 81.05 16 70ZM4 62A7 7 0 1 1 18 62A7 7 0 1 1 4 62ZM82 62A7 7 0 1 1 96 62A7 7 0 1 1 82 62ZM47.5 14H52.5V32H47.5ZM43 11A7 7 0 1 1 57 11A7 7 0 1 1 43 11Z",
            .alien: "M50 10C70 10 83 27 83 46C83 65 64 92 50 92C36 92 17 65 17 46C17 27 30 10 50 10Z",
            .cloud: "M19 44A25 25 0 1 1 69 44A25 25 0 1 1 19 44ZM47 50A21 21 0 1 1 89 50A21 21 0 1 1 47 50ZM7 68A17 17 0 1 1 41 68A17 17 0 1 1 7 68ZM32 73A18 18 0 1 1 68 73A18 18 0 1 1 32 73ZM60 70A16 16 0 1 1 92 70A16 16 0 1 1 60 70Z",
        ]
        return d.compactMapValues { SVGPath.cgPath($0) }
    }()
}

extension StoreData {
    /// The companion's character. Saved under `avatar`, the Electron key.
    public var avatar: CompanionCharacter {
        get { CompanionCharacter(setting: settings["avatar"]?.string) }
        set { settings["avatar"] = .string(newValue.rawValue) }
    }

    /// The three companion motion switches, all off unless saved on (the Electron keys).
    public var companionLook: Bool {
        get { settings["companionLook"]?.bool == true }
        set { settings["companionLook"] = .bool(newValue) }
    }
    public var companionSleepOn: Bool {
        get { settings["companionSleepOn"]?.bool == true }
        set { settings["companionSleepOn"] = .bool(newValue) }
    }
    public var companionReact: Bool {
        get { settings["companionReact"]?.bool == true }
        set { settings["companionReact"] = .bool(newValue) }
    }

    /// The glow of the ambient video while music plays on Home. On unless saved off.
    public var ambientVideo: Bool {
        get { settings["ambientVideo"]?.bool != false }
        set { settings["ambientVideo"] = .bool(newValue) }
    }

    /// What the closed Notch shows beside the cutout: the time and the companion. Both on unless saved off.
    public var closedClock: Bool {
        get { settings["closedClock"]?.bool != false }
        set { settings["closedClock"] = .bool(newValue) }
    }
    public var closedCompanion: Bool {
        get { settings["closedCompanion"]?.bool != false }
        set { settings["closedCompanion"] = .bool(newValue) }
    }

    /// Which sections the open Notch shows (the Electron `show*` keys). All on unless saved off.
    public var showAvatar: Bool {
        get { settings["showAvatar"]?.bool != false }
        set { settings["showAvatar"] = .bool(newValue) }
    }
    public var showMusic: Bool {
        get { settings["showMusic"]?.bool != false }
        set { settings["showMusic"] = .bool(newValue) }
    }
    public var showBluetooth: Bool {
        get { settings["showBluetooth"]?.bool != false }
        set { settings["showBluetooth"] = .bool(newValue) }
    }
    public var showDesk: Bool {
        get { settings["showDesk"]?.bool != false }
        set { settings["showDesk"] = .bool(newValue) }
    }
    public var showReminders: Bool {
        get { settings["showReminders"]?.bool != false }
        set { settings["showReminders"] = .bool(newValue) }
    }
    public var showFiles: Bool {
        get { settings["showFiles"]?.bool != false }
        set { settings["showFiles"] = .bool(newValue) }
    }
    /// The Claude sessions page in the dock; on unless saved off. It also needs Claude Code on (see `pagesOff`).
    public var showClaude: Bool {
        get { settings["showClaude"]?.bool != false }
        set { settings["showClaude"] = .bool(newValue) }
    }
    /// The pages switched off (Calendar has its own switch, `showCalendar`).
    public var pagesOff: Set<NotchPage> {
        var off = Set<NotchPage>()
        if !showDesk { off.insert(.desk) }
        if !showReminders { off.insert(.reminders) }
        if !showFiles { off.insert(.files) }
        if !showClaude || !claudeHooks.enabled { off.insert(.claude) } // the page lists Claude Code's sessions: nothing to list while it is off
        return off
    }

    /// Hide the Notch over a fullscreen app (the Electron key). On unless saved off.
    public var hideOnFullscreen: Bool {
        get { settings["hideOnFullscreen"]?.bool != false }
        set { settings["hideOnFullscreen"] = .bool(newValue) }
    }
}

extension JSONValue {
    fileprivate var string: String? { if case .string(let s) = self { s } else { nil } }
    fileprivate var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
}

/// How to bend the ambient video's colour towards the companion's: a hue turn in degrees and a saturation factor
/// (the Electron app's `shiftFor`). The video's own light is a teal blue.
public struct AmbientShift: Equatable, Sendable {
    public var rotate: Int
    public var saturation: Double

    public init(rotate: Int, saturation: Double) { (self.rotate, self.saturation) = (rotate, saturation) }

    /// The video's own hue, in degrees.
    public static let videoHue = 198.0

    /// Blues through lavenders and near greys already match the video and are left alone, with a little colour. Warm and
    /// green companions turn it round to their hue, with more colour so it shows.
    public init(accent: UInt32?) {
        guard let accent else { self.init(rotate: 0, saturation: 0.35); return }
        let r = Double(accent >> 16 & 255) / 255, g = Double(accent >> 8 & 255) / 255, b = Double(accent & 255) / 255
        let hi = max(r, g, b), lo = min(r, g, b), d = hi - lo
        guard d > 0 else { self.init(rotate: 0, saturation: 0.35); return }
        let sector = hi == r ? ((g - b) / d).truncatingRemainder(dividingBy: 6) : hi == g ? (b - r) / d + 2 : (r - g) / d + 4
        let hue = (sector * 60 + 360).truncatingRemainder(dividingBy: 360)
        let saturation = d / (1 - abs(hi + lo - 1))
        if (170...275).contains(hue) || saturation < 0.35 { self.init(rotate: 0, saturation: 0.35) }
        else { self.init(rotate: Int((hue - Self.videoHue).rounded()), saturation: 0.7) }
    }
}
