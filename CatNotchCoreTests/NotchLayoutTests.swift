import CoreGraphics
import Testing
@testable import CatNotchCore

@Test func homeIsAsWideAsItsTilesAndNeverUnder320() {
    let wide = NotchLayout.homeContent(tiles: [236, 328, 192])
    #expect(wide.width == 236 + 328 + 192 + 2 * NotchLayout.gap)
    #expect(wide.height == NotchLayout.tile)
    #expect(NotchLayout.homeContent(tiles: [236]).width + 2 * NotchLayout.side == NotchLayout.homeMinWidth)
}

@Test func openAddsPaddingAroundContent() {
    let open = NotchLayout.open(content: NotchLayout.deskContent, closedHeight: 30)
    #expect(open == CGSize(width: 720, height: 30 + 6 + 136 + 12))
}

@Test func calendarFollowsTheWeeks() {
    #expect(NotchLayout.calendarContent(weeks: 6).height - NotchLayout.calendarContent(weeks: 5).height == 22)
    #expect(NotchLayout.calendarContent(weeks: 5).width + 2 * NotchLayout.side == 580)
}

@Test func aRequestStripSitsAboveThePageAndWidensItToAtLeast420() {
    let page = NotchLayout.homeContent(tiles: [236])
    let with = NotchLayout.withStrip(page, strip: NotchLayout.claudePermission)
    #expect(with.width == NotchLayout.claudeWidth)
    #expect(with.height == page.height + NotchLayout.gap + NotchLayout.claudePermission)
    #expect(NotchLayout.withStrip(NotchLayout.deskContent, strip: 60).width == NotchLayout.deskContent.width)
}

@Test func aClosedNotchOpensToTheStripAlone() {
    #expect(NotchLayout.withStrip(nil, strip: NotchLayout.claudeQuestion) == CGSize(width: NotchLayout.claudeWidth, height: NotchLayout.claudeQuestion))
}

@Test func aSmallQuestionCardHugsItsContentAndALongOneStaysUnderTheMax() {
    func question(_ text: String, options: Int, description: String = "") -> ClaudeQuestion {
        .init(question: text, header: "", multiSelect: true, options: (0..<options).map { .init(label: "Option \($0)", description: description) })
    }
    let small = NotchLayout.claudeCard([question("Pick one?", options: 2)])
    #expect(small < 220)
    #expect(NotchLayout.claudeCard([question("Pick one?", options: 2), question("Which?", options: 4, description: String(repeating: "x", count: 300))]) > small)
    #expect(NotchLayout.claudeCard([question(String(repeating: "word ", count: 200), options: 12, description: String(repeating: "x", count: 300))]) > 280)
    #expect(NotchLayout.claudeCard([question("Pick one?", options: 2)]) <= NotchLayout.claudeCardMax)
}

@Test func homeGrowsByTheNextEventLine() {
    let plain = NotchLayout.homeContent(tiles: [236])
    #expect(NotchLayout.homeContent(tiles: [236], nextEvent: true).height - plain.height == NotchLayout.nextEventLine)
}
