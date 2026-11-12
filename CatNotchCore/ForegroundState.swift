import CoreGraphics

/// One on-screen window, as CGWindowList reports it.
public struct WindowInfo: Equatable, Sendable {
    public var pid: Int32
    public var layer: Int
    public var bounds: CGRect
    public init(pid: Int32, layer: Int, bounds: CGRect) {
        self.pid = pid; self.layer = layer; self.bounds = bounds
    }
}

/// A display and its bounds, in the same top-left-origin space as window bounds (CGDisplayBounds).
public struct DisplayBounds: Equatable, Sendable {
    public var id: UInt32
    public var bounds: CGRect
    /// Height of the hardware notch. A fullscreen window starts below it, not at the display's top edge.
    public var topInset: CGFloat
    public init(id: UInt32, bounds: CGRect, topInset: CGFloat = 0) {
        self.id = id; self.bounds = bounds; self.topInset = topInset
    }
}

/// Where a Claude Code question came from. A terminal in front already shows the CLI's own prompt.
public enum ClaudeSource: Sendable { case cli, vscode, unknown }

/// The frontmost app: which display it is on, whether it fills it, and its bundle id.
public struct ForegroundState: Equatable, Sendable {
    public var fullscreen: Bool
    public var display: UInt32
    public var bundle: String

    /// Terminals a CLI session runs in, by lower case bundle id.
    private static let terminals: Set<String> = [
        "com.apple.terminal", "com.googlecode.iterm2", "dev.warp.warp-stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm",
    ]

    /// Reads the frontmost app's windows. Covering a whole display, menu bar included, is full screen;
    /// a maximised window stops below the menu bar. The display is the one the windows overlap most.
    public static func detect(pid: Int32, bundle: String, windows: [WindowInfo], displays: [DisplayBounds], mainDisplay: UInt32) -> ForegroundState {
        var fullscreen = false
        var display = mainDisplay
        var best = 0.0
        // ponytail: 2pt edge tolerance and the terminal list are fixed; widen if a fullscreen app stops short of the top.
        // ponytail: on a notched display a Dock set to auto-hide makes a maximised window look like this too; no window-list tell exists.
        for window in windows where window.pid == pid && window.layer == 0 {
            for d in displays {
                let overlap = d.bounds.intersection(window.bounds)
                let area = overlap.isNull ? 0 : Double(overlap.width * overlap.height)
                // A fullscreen hit sets best to infinity so no later overlap can change the display.
                if area > best { best = area; display = d.id }
            }
        }
        // Some apps (Ghostty) split a fullscreen window in two, a tab bar and the content: only together do they reach both edges.
        // ponytail: the union is a bounding box, so two tiled windows reaching opposite edges also count; add a gap check if that bites.
        for d in displays {
            let mine = windows.filter { $0.pid == pid && $0.layer == 0 && !d.bounds.intersection($0.bounds).isNull }
            guard let first = mine.first else { continue }
            let (r, b) = (mine.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }, d.bounds)
            if r.minX <= b.minX + 2 && r.minY <= b.minY + d.topInset + 2 && r.maxX >= b.maxX - 2 && r.maxY >= b.maxY - 2 {
                fullscreen = true; display = d.id; break
            }
        }
        return ForegroundState(fullscreen: fullscreen, display: display, bundle: bundle)
    }

    /// The Notch hides on the display a fullscreen app fills.
    public func hides(display id: UInt32) -> Bool { fullscreen && display == id }

    /// Whether a terminal is in front. VS Code questions are never skipped: its prompt sits in a side panel.
    public func isTerminalInFront(for source: ClaudeSource) -> Bool { Self.isTerminalInFront(bundle: bundle, for: source) }

    public static func isTerminalInFront(bundle: String, for source: ClaudeSource) -> Bool {
        source != .vscode && terminals.contains(bundle.lowercased())
    }
}
