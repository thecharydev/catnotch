import Foundation

/// The reload button's motion as plain numbers, so it can be tested: one object that is the refresh icon at rest, folds its
/// arrowhead into the path while it speeds up into a spinning ring (a Material style arc that breathes as it turns), and
/// when the real operation is done slows down, closes the arc and unfolds the arrowhead exactly where it began (spec 0046).
///
/// Times are seconds on any clock, as long as `start`, `finish(at:)` and `frame(at:)` use the same one. Angles are degrees.
public struct ReloadMotion: Sendable {
    /// What to draw at one instant. The arc ends (its head) at `iconHead + rotation` and reaches back `sweep` degrees.
    public struct Frame: Equatable, Sendable {
        /// Total turn so far, clockwise, never decreasing. A whole number of turns once settled.
        public var rotation: Double
        /// How much of the circle the arc covers.
        public var sweep: Double
        /// 1 is the full arrowhead, 0 is folded into the path.
        public var head: Double
    }

    /// Speeding up into the ring, and the arrowhead folding away.
    public static let morph = 0.3
    /// Slowing down, closing the arc and unfolding the arrowhead.
    public static let slowDown = 0.28
    /// One turn takes a second while it loads.
    public static let turnsPerSecond = 1.0
    /// The refresh icon's arc, and where its arrowhead sits (just left of the top, pointing clockwise into the gap).
    public static let iconSweep = 300.0
    public static let iconHead = -100.0

    /// The icon at rest, before it starts and after it settles.
    public static let rest = Frame(rotation: 0, sweep: iconSweep, head: 1)

    private static let speed = 360 * turnsPerSecond
    private static let breath = 1.4 // one in and out of the arc
    private static let fewest = 30.0, most = 270.0
    /// The slowing down starts when at most this far from a whole turn, so it never has to rush or wait a full turn.
    private static let reach = 235.0, least = 50.0

    public let start: Double
    /// When the slowing down begins and how far it still has to turn; nil while the operation is running.
    private var slow: (at: Double, from: Double, by: Double)?

    public init(start: Double) { self.start = start }

    /// When the icon is back at rest, once the operation has finished.
    public var settledAt: Double? { slow.map { $0.at + Self.slowDown } }

    /// The operation is done. An answer during the morph waits for it to end, so a tap always shows the whole motion; then
    /// the ring keeps turning until it is within reach of a whole turn and slows into it.
    public mutating func finish(at time: Double) {
        guard slow == nil else { return }
        let from = max(time, start + Self.morph)
        let turned = Self.turned(from - start)
        var remaining = 360 - turned.truncatingRemainder(dividingBy: 360)
        if remaining < Self.least { remaining += 360 }
        let wait = max(0, (remaining - Self.reach) / Self.speed)
        slow = (from + wait, turned + Self.speed * wait, remaining - Self.speed * wait)
    }

    public func frame(at time: Double) -> Frame {
        let elapsed = time - start
        if elapsed <= 0 { return Self.rest }
        if let slow, time >= slow.at {
            let p = min(1, (time - slow.at) / Self.slowDown)
            // Hermite: leaves at the spinning speed and comes to rest exactly on the turn.
            let rotation = slow.from + (p * p * p - 2 * p * p + p) * Self.slowDown * Self.speed + (3 * p * p - 2 * p * p * p) * slow.by
            let begun = Self.breathing(slow.at - start - Self.morph)
            return Frame(rotation: rotation, sweep: begun + (Self.iconSweep - begun) * Self.ease(p), head: Self.ease(p))
        }
        if elapsed < Self.morph {
            let p = Self.ease(elapsed / Self.morph)
            return Frame(rotation: Self.turned(elapsed), sweep: Self.iconSweep + (Self.most - Self.iconSweep) * p, head: 1 - p)
        }
        return Frame(rotation: Self.turned(elapsed), sweep: Self.breathing(elapsed - Self.morph), head: 0)
    }

    /// Total turn after `elapsed` seconds: the speed builds up linearly over the morph, then stays.
    private static func turned(_ elapsed: Double) -> Double {
        elapsed < morph ? speed * elapsed * elapsed / (2 * morph) : speed * (elapsed - morph / 2)
    }

    /// The arc growing and shrinking, starting from its widest so the morph's end joins it without a jump.
    private static func breathing(_ elapsed: Double) -> Double {
        fewest + (most - fewest) * (0.5 + 0.5 * cos(2 * .pi * elapsed / breath))
    }

    private static func ease(_ p: Double) -> Double { p * p * (3 - 2 * p) }
}
