import Testing
@testable import CatNotchCore

// The reload button's motion as numbers: one continuous object going refresh icon -> ring -> refresh icon (spec 0046).

private let step = 0.001

/// Every frame from `start` until it settles, 1 ms apart.
private func frames(_ motion: ReloadMotion, from start: Double, until end: Double) -> [ReloadMotion.Frame] {
    stride(from: start, through: end, by: step).map { motion.frame(at: $0) }
}

@Test func beforeItStartsItIsTheRefreshIcon() {
    let frame = ReloadMotion(start: 10).frame(at: 9)
    #expect(frame.rotation == 0 && frame.sweep == ReloadMotion.iconSweep && frame.head == 1)
}

@Test func theArrowheadIsGoneAndTheArcIsOpenOnceTheMorphEnds() {
    let motion = ReloadMotion(start: 0)
    let frame = motion.frame(at: ReloadMotion.morph)
    #expect(frame.head == 0)
    #expect(abs(frame.sweep - 270) < 0.001) // where the loading arc starts, so nothing jumps
    #expect(frame.rotation > 0)
}

@Test func theArcBreathesWhileItSpins() {
    let motion = ReloadMotion(start: 0)
    let sweeps = frames(motion, from: ReloadMotion.morph, until: ReloadMotion.morph + 3).map(\.sweep)
    #expect(sweeps.min()! < 40 && sweeps.max()! > 260)
    #expect(sweeps.allSatisfy { $0 >= 30 - 0.001 && $0 <= 300 })
}

@Test func aSpinTakesAboutASecondPerTurn() {
    let motion = ReloadMotion(start: 0)
    let t = ReloadMotion.morph + 2
    #expect(abs(motion.frame(at: t + 1).rotation - motion.frame(at: t).rotation - 360) < 1) // 1.0 s a turn, inside 900 to 1200 ms
}

@Test(arguments: stride(from: 0.0, through: 3.0, by: 0.173).map { $0 })
func itAlwaysLandsOnTheExactIconWithoutJumpingOrTurningBackwards(finishAt: Double) {
    var motion = ReloadMotion(start: 0)
    motion.finish(at: finishAt)
    let settled = try! #require(motion.settledAt)
    let all = frames(motion, from: 0, until: settled + 0.1)
    for (a, b) in zip(all, all.dropFirst()) {
        #expect(b.rotation >= a.rotation) // never backwards
        #expect(b.rotation - a.rotation < 2) // under 2000 deg/s: no snap
        #expect(abs(b.sweep - a.sweep) < 2)
        #expect(abs(b.head - a.head) < 0.02)
    }
    let last = all.last!
    #expect(last.rotation.truncatingRemainder(dividingBy: 360) < 0.001 || 360 - last.rotation.truncatingRemainder(dividingBy: 360) < 0.001)
    #expect(last.sweep == ReloadMotion.iconSweep && last.head == 1) // the icon as it began
    #expect(settled - max(finishAt, ReloadMotion.morph) <= ReloadMotion.slowDown + 0.5) // follows the real operation, at most half a second late
}

@Test func anAnswerBeforeTheMorphEndsStillShowsTheWholeMorph() {
    var motion = ReloadMotion(start: 0)
    motion.finish(at: 0.02) // an immediate answer
    #expect(motion.settledAt! >= ReloadMotion.morph + ReloadMotion.slowDown)
    #expect(motion.frame(at: ReloadMotion.morph).head == 0)
}
