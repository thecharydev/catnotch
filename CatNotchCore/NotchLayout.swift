import CoreGraphics

/// The open Notch's size on each page, the numbers the Electron Notch uses (`NotchChassis.tsx`, `home.tsx`).
/// Pure geometry: a page says how big its content is, and the Notch is that plus the padding around it.
public enum NotchLayout {
    /// Height of a Home tile, and the gap between tiles.
    public static let tile: CGFloat = 136
    public static let gap: CGFloat = 10
    /// Padding either side of the content, and under it. The top gap sits under the closed bar.
    public static let side: CGFloat = 12
    public static let topGap: CGFloat = 6
    public static let bottom: CGFloat = 12

    /// Closed on a hardware notch the shape is this much bigger each side and below it, so no hairline of the real
    /// notch's edge shows around it (the Electron `CUTOUT_BLEED`).
    public static let cutoutBleed: CGFloat = 2
    /// The closed Notch's content sits this far in from its edge: on a hardware notch, and on the pill (the Electron `px-2` / `px-5`).
    public static let closedInset: CGFloat = 8
    public static let closedInsetPill: CGFloat = 20
    /// How far the concave curves at the closed Notch's top corners reach along the screen's edge (the Electron `EAR`).
    public static let ear: CGFloat = 8
    /// The same curves on the open Notch, which grow from `ear` as it opens (Vibe Notch's open top radius).
    public static let openEar: CGFloat = 19

    public static let companionWidth: CGFloat = 236
    public static let musicWidth: CGFloat = 328
    /// The consent and "no sign-in" usage cards.
    public static let usageMessageWidth: CGFloat = 236
    public static let homeMinWidth: CGFloat = 320
    /// The companion once its clock is unfolded to the day's wave (`COMPANION_TIME_WIDTH`), the lone time tile (`TIME_WIDTH`)
    /// and the line of the next event under the row.
    public static let companionDayWidth: CGFloat = 330
    public static let timeWidth: CGFloat = 160
    public static let nextEventLine: CGFloat = 20

    /// Focus & tasks: a 696pt row of tiles (`DESK_WIDTH`).
    public static let deskContent = CGSize(width: 696, height: tile)
    public static let calendarWidth: CGFloat = 580
    public static let remindersContent = CGSize(width: 392 - 2 * side, height: tile)
    public static let filesContent = CGSize(width: 640 - 2 * side, height: tile)
    /// The strip of Bluetooth, mic and camera chips under the Home tiles, and the gap above it.
    public static let glanceRow: CGFloat = 30

    /// The Calendar's content height: the month grid is 40pt of heading and 22pt a week (`calendarHeight`).
    public static func calendarContent(weeks: Int) -> CGSize {
        CGSize(width: calendarWidth - 2 * side, height: 40 + 22 * CGFloat(weeks))
    }

    /// Home: as wide as its tiles side by side (never under 320), as tall as a tile and, when it has chips, the glance row
    /// and, when an event is next today, its line.
    public static func homeContent(tiles: [CGFloat], glance: Bool, nextEvent: Bool = false) -> CGSize {
        let gaps = CGFloat(max(0, tiles.count - 1))
        let row: CGFloat = tiles.reduce(0, +) + gap * gaps
        let width: CGFloat = max(homeMinWidth - 2 * side, row)
        var height: CGFloat = tile
        if glance { height += gap + glanceRow }
        if nextEvent { height += nextEventLine }
        return CGSize(width: width, height: height)
    }

    /// A Claude Code request: a strip over the page, at least this wide, as tall as its kind needs.
    public static let claudeWidth: CGFloat = 420
    /// The Electron strip's heights: a permission is a header, one command line and the buttons; hovering its text opens
    /// the command to six lines (`claudeCommandGrow` taller). A question is a line and chips; hovering opens the 300pt card.
    public static let claudePermission: CGFloat = 96
    public static let claudeCommandGrow: CGFloat = 82
    public static let claudeQuestion: CGFloat = 76
    /// The "<project> finished" banner (spec 0040).
    public static let claudeFinished: CGFloat = 44
    /// The question card hugs its content (a small question is a small card) up to this tall, then its text and options scroll.
    public static let claudeCardMax: CGFloat = 300
    public static let claudeCardText: CGFloat = 64
    public static let claudeCardOptions: CGFloat = 104
    /// Rough wrapped line counts (13pt semibold question, 11pt option text): the views scroll if a guess runs short.
    private static func lines(_ text: String, perLine: Int) -> Int {
        max(1, text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { $0 + max(1, ($1.count + perLine - 1) / perLine) })
    }
    public static func claudeQuestionText(_ q: ClaudeQuestion) -> CGFloat { min(claudeCardText, CGFloat(lines(q.question, perLine: 52)) * 17) }
    public static func claudeOptionsHeight(_ q: ClaudeQuestion) -> CGFloat {
        let rows: [CGFloat] = q.options.map { option in
            let descLines = option.description.isEmpty ? 0 : lines(option.description, perLine: 56)
            return 8 + 14 + CGFloat(descLines) * 14
        }
        let gaps = CGFloat(max(0, rows.count - 1))
        let total: CGFloat = rows.reduce(0, +) + 4 * gaps
        return min(claudeCardOptions, total)
    }
    /// Header, question, options, answer box and buttons with their gaps; the tallest part, so the Notch holds still between parts.
    public static func claudeCard(_ questions: [ClaudeQuestion]) -> CGFloat {
        let parts = questions.map { claudeQuestionText($0) + claudeOptionsHeight($0) }.max() ?? 0
        let chrome: CGFloat = 118 // 12 + 22 + 26 + 26 + 4 * 8; as a sum it times out Xcode 16.4's type checker
        return min(claudeCardMax, chrome + parts)
    }

    /// The Claude page (spec 0033): a heading and a row a session, up to six rows and then it scrolls; an empty list keeps one
    /// row's room for its sentence.
    public static let claudeHeading: CGFloat = 26
    public static let claudeRow: CGFloat = 40 // two lines: the title, and the tool or your last message
    public static let claudeRowsMax = 6
    public static func claudeSessionsContent(count: Int) -> CGSize {
        let rows = CGFloat(max(1, min(count, claudeRowsMax)))
        let width: CGFloat = claudeWidth - 2 * side
        let height: CGFloat = claudeHeading + claudeRow * rows
        return CGSize(width: width, height: height)
    }

    /// `content` with a request strip above it (as its own, when the Notch is only open for the request).
    public static func withStrip(_ content: CGSize?, strip: CGFloat) -> CGSize {
        guard let content else { return CGSize(width: claudeWidth, height: strip) }
        return CGSize(width: max(content.width, claudeWidth), height: content.height + gap + strip)
    }

    /// The open Notch around `content`, under a closed bar `closedHeight` tall.
    public static func open(content: CGSize, closedHeight: CGFloat) -> CGSize {
        let width: CGFloat = content.width + 2 * side
        let height: CGFloat = closedHeight + topGap + content.height + bottom
        return CGSize(width: width, height: height)
    }
}
