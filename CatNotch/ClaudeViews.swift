import AppKit
import SwiftUI
import CatNotchCore

private let waitingColor = Color(red: 0.98, green: 0.75, blue: 0.14) // amber #fbbf24: waiting for you

/// Hover state plus the hand cursor for anything that clicks. A request answered under the pointer leaves with the pointer
/// still on it, so the cursor is put back when the view goes away, or it would stay a hand.
private struct Hovering<Content: View>: View {
    @ViewBuilder var content: (Bool) -> Content
    @State private var on = false

    var body: some View {
        content(on)
            .onHover { inside in
                guard inside != on else { return }
                on = inside
                if inside { HandCursor.enter() } else { HandCursor.leave() }
            }
            .onDisappear { if on { on = false; HandCursor.leave() } }
    }
}

extension ClaudeRequest {
    /// The height of the strip for this request, which the Notch is sized from. `open` is the hovered state:
    /// a permission shows its whole command, a question its card (the Electron `claudeStripHeight`).
    func stripHeight(open: Bool) -> CGFloat {
        switch kind {
        case .permission: NotchLayout.claudePermission + (open ? NotchLayout.claudeCommandGrow : 0)
        case .question(let questions): open ? NotchLayout.claudeCard(questions) : NotchLayout.claudeQuestion
        }
    }
}

/// "<title> finished": the closed Notch opens on it for about 1 second (spec 0040). The pointer on it pauses the timer.
struct ClaudeFinishedBanner: View {
    let title: String
    let accent: Color
    var claude: ClaudeModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(accent).accessibilityHidden(true)
            Text("\(title) finished").font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: NotchLayout.claudeFinished)
        .onHover { claude.holdFinished($0) }
        .onDisappear { claude.holdFinished(false) }
        .accessibilityElement(children: .combine)
    }
}

/// A slow pulse on its own animation, so it is smooth between the 0.15 s ticks of the page clock.
private struct PulsingDot: View {
    let color: Color
    let still: Bool
    @State private var dim = false
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7).opacity(still || !dim ? 1 : 0.35)
            .onAppear { if !still { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true } } }
    }
}

/// The Claude page: every live session and what it is doing (spec 0033, the Electron `ClaudeSessions`).
struct ClaudeSessionsPage: View {
    var claude: ClaudeModel
    let accent: Color

    private static let badge: [ClaudeSource: String] = [.cli: "CLI", .vscode: "VS Code"]
    private static let spinner = ["·", "✢", "✳", "∗", "✻", "✽"]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Only while the page is on screen does the clock run.
    @State private var visible = false

    private func label(_ state: ClaudeSession.State) -> String {
        switch state {
        case .working: "Working"
        case .compacting: "Compacting"
        case .idle: "Idle"
        case .waiting: "Needs your input"
        case .done: "Done"
        }
    }

    private func button(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Hovering { hover in
            Button(action: action) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(hover ? 0.9 : 0.45))
                    .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(hover ? 0.12 : 0))).contentShape(Circle())
            }
            .buttonStyle(.plain).help(title).accessibilityLabel(title)
        }
    }

    /// The state as a glyph (spec 0042): one clock, `tick` counts 0.15 s steps, drives every looping one. Reduce Motion: still.
    @ViewBuilder private func glyph(_ state: ClaudeSession.State, tick: Int) -> some View {
        switch state {
        case .working:
            Text(reduceMotion ? "✻" : Self.spinner[tick % Self.spinner.count]).font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
        case .compacting:
            Circle().fill(accent).frame(width: reduceMotion ? 6 : [9, 6, 3, 6][tick % 4], height: reduceMotion ? 6 : [9, 6, 3, 6][tick % 4]) // a dot being squeezed
        case .waiting:
            PulsingDot(color: waitingColor, still: reduceMotion)
        case .done:
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(accent).transition(.scale.combined(with: .opacity))
        case .idle:
            Circle().fill(.white.opacity(0.3)).frame(width: 6, height: 6)
        }
    }

    private func row(_ s: ClaudeSession, tick: Int) -> some View {
        HStack(spacing: 8) {
            glyph(s.state, tick: tick)
                .frame(width: 14, height: 14).animation(reduceMotion ? nil : .spring(duration: 0.3), value: s.state)
                .help(label(s.state)).accessibilityLabel(label(s.state))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(s.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    if s.project != s.title { Text(s.project).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).lineLimit(1).fixedSize() }
                }
                Text(s.activity.isEmpty ? (s.last.isEmpty ? "" : "You: \(s.last)") : s.activity)
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(s.activity.isEmpty ? 0.45 : 0.6)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let badge = Self.badge[s.source] {
                Text(badge).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(.white.opacity(0.1)))
            }
            button("arrow.up.forward.app", "Go to its window") { claude.focus(s.id) }
            button("xmark", "Hide until it has news") { claude.archive(s.id) }
        }
        .frame(height: NotchLayout.claudeRow)
    }

    var body: some View {
        let sessions = claude.sessions
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal").font(.system(size: 11, weight: .semibold))
                Text("Claude sessions, \(sessions.count)").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(accent).frame(height: NotchLayout.claudeHeading, alignment: .top)
            if sessions.isEmpty {
                Text("No Claude sessions yet. Start one in a terminal or VS Code.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            } else {
                // One clock for every row, stopped when the page is not showing or motion is off.
                TimelineView(.animation(minimumInterval: 0.15, paused: !visible || reduceMotion)) { timeline in
                    let tick = Int(timeline.date.timeIntervalSinceReferenceDate / 0.15)
                    ScrollView { VStack(spacing: 0) { ForEach(sessions) { row($0, tick: tick) } } }.scrollIndicators(.never)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { visible = true }
        .onDisappear { visible = false; claude.markSeen() } // "Done" stays until you have looked at the list
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// A Claude Code request on the Notch, laid out as the Electron strip (`ClaudeView.tsx`): a permission is a header, one
/// command line and Terminal, Deny, Allow; a question is a line with up to three chips. Hovering the text of a permission
/// opens its whole command, hovering a question opens the card with every option and a text box. Allow is the one
/// solid button. Only a click here answers; nothing is ever approved on its own. The pointer on the strip, or an
/// answer being typed or picked, pauses the 60 second timer.
struct ClaudeStrip: View {
    let request: ClaudeRequest
    /// How many are waiting, this one included.
    let count: Int
    let accent: Color
    var claude: ClaudeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSource = false
    @State private var step = 0
    @State private var picked: [String: [String]] = [:]
    @State private var typed: [String: String] = [:]
    @FocusState private var typing: Bool
    @FocusState private var sendFocused: Bool
    @FocusState private var cardFocused: Bool // the card itself, so Enter lands even when no field or button has focus

    private var open: Bool { claude.open }
    private var isPermission: Bool { if case .permission = request.kind { true } else { false } }
    /// The timer waits while a box has focus, text is typed, or an option is picked.
    private var working: Bool { typing || typed.values.contains { !$0.trimmed.isEmpty } || picked.values.contains { !$0.isEmpty } }

    var body: some View {
        let height = request.stripHeight(open: open)
        Group {
            switch request.kind {
            case .permission(let tool, let text): permission(tool: tool, text: text)
            case .question(let questions): if open { card(questions) } else { strip(questions) }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .top)
        .background(PointerOver { on in
            claude.hold(request.id, on, .hover)
            if isPermission, !on { claude.open = false } // leaving a permission folds the command; a question's card stays
            if !isPermission, on, !claude.shut { claude.open = true }
            if !isPermission, !on { claude.shut = false }
        })
        .onChange(of: working) { claude.hold(request.id, working, .typing) }
        .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: -10)))
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    private var dot: some View { Circle().fill(waitingColor).frame(width: 6, height: 6).accessibilityHidden(true) }

    private var countLabel: some View {
        Group { if count > 1 { Text("1 of \(count)").font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(0.6)) } }
    }

    private func icon(_ symbol: String, _ label: String, size: CGFloat = 26, action: @escaping () -> Void) -> some View {
        Hovering { hover in
            Button(action: action) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(hover ? 1 : 0.7))
                    .frame(width: size, height: size).background(Circle().fill(.white.opacity(hover ? 0.16 : 0.08))).contentShape(Circle())
            }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
        }
    }

    private func pill(_ title: String, solid: Bool = false, inset: CGFloat = 16, action: @escaping () -> Void) -> some View {
        Hovering { hover in
            Button(action: action) {
                Text(title).font(.system(size: 11, weight: solid ? .semibold : .medium)).lineLimit(1)
                    .foregroundStyle(solid ? .black : .white.opacity(hover ? 1 : 0.7))
                    .padding(.horizontal, inset).frame(height: 26)
                    .background(Capsule().fill(solid ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(hover ? 0.16 : 0.08))))
                    .brightness(solid && hover ? 0.1 : 0)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var sourceLines: some View {
        ScrollView { SourceLines(source: .claude, size: 10).frame(maxWidth: .infinity, alignment: .leading) }.scrollIndicators(.never)
    }

    // MARK: Permission

    private func permission(tool: String, text: String) -> some View {
        VStack(spacing: 6) {
            // Only the text (header and command) opens it; hovering the buttons leaves it as it is.
            HStack(spacing: 8) {
                dot
                Text(tool).font(.system(size: 11, weight: .semibold)).lineLimit(1).fixedSize().frame(maxWidth: 160, alignment: .leading)
                Text(request.project).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                countLabel
                SourceInfo(source: .claude, open: $showSource)
            }
            .frame(height: 20).contentShape(Rectangle())
            .onHover { if $0 { claude.open = true } }

            if showSource {
                sourceLines.frame(maxHeight: .infinity)
            } else {
                if open {
                    ScrollView {
                        Text(text).font(.system(size: 11, design: .monospaced)).lineSpacing(3).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    .frame(height: 108).background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.4)))
                } else {
                    Hovering { hover in
                        Button { claude.open = true } label: {
                            Text(text.components(separatedBy: "\n")[0]).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.tail)
                                .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(hover ? 0.55 : 0.4))).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Show the whole command")
                    }
                    .onHover { if $0 { claude.open = true } }
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    icon("terminal", "Ask in terminal") { claude.answer(request.id, .pass) }
                    pill("Deny") { claude.answer(request.id, .deny) }
                    if request.always { pill("Always allow") { claude.answer(request.id, .always) }.help("Allow, and don't ask again for this") }
                    pill("Allow", solid: true) { claude.answer(request.id, .allow) }
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Question strip

    /// One line and up to three chips (more than three: two, then "+N"). A tap on a chip answers at once. Several parts
    /// or a multiple choice open the card to answer.
    private func strip(_ questions: [ClaudeQuestion]) -> some View {
        let q = questions[0]
        let simple = questions.count == 1 && !q.multiSelect
        let chips = simple ? (q.options.count > 3 ? Array(q.options.prefix(2)) : q.options) : []
        let more = simple && q.options.count > 3 ? q.options.count - 2 : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                dot
                Text(request.project).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1).fixedSize().frame(maxWidth: 70, alignment: .leading)
                Text(q.question).font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                countLabel
                SourceInfo(source: .claude, open: $showSource)
                icon("chevron.down", "Open the question") { claude.shut = false; claude.open = true }
            }
            if showSource {
                sourceLines
            } else {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.label) { option in
                        pill(option.label, inset: 12) { claude.answer(request.id, .answers([q.question: [option.label]])) }
                            .frame(maxWidth: 130).help(option.description)
                    }
                    if more > 0 { pill("+\(more)", inset: 12) { claude.shut = false; claude.open = true }.accessibilityLabel("\(more) more options, open the question") }
                    if !simple { Text("Open to answer").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)) }
                }
                .padding(.leading, 14)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture { claude.shut = false; claude.open = true }
        .pointerCursor()
    }

    // MARK: Question card

    /// What this question sends: the ticked labels, then the typed words.
    private func answerOf(_ q: ClaudeQuestion) -> [String] {
        let words = (typed[q.question] ?? "").trimmed
        return (picked[q.question] ?? []) + (words.isEmpty ? [] : [words])
    }

    private func card(_ questions: [ClaudeQuestion]) -> some View {
        let part = min(step, questions.count - 1)
        let q = questions[part]
        let last = part == questions.count - 1
        let chosen = picked[q.question] ?? []
        let ready = !answerOf(q).isEmpty
        let allReady = questions.allSatisfy { !answerOf($0).isEmpty }
        let text = Binding(
            get: { typed[q.question] ?? "" },
            set: { value in
                typed[q.question] = String(value.prefix(2000))
                if !q.multiSelect, !value.isEmpty { picked[q.question] = [] } // one choice or typed words, not both
            })
        let next = {
            guard ready else { return }
            if !last { step = part + 1 } else if allReady { send(questions) } // Enter moves on, or sends once Send is lit
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "terminal").font(.system(size: 11, weight: .semibold))
                Text(request.project).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                if count > 1 { Text("1 of \(count)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)) }
                Spacer(minLength: 0)
                SourceInfo(source: .claude, open: $showSource)
                icon("chevron.up", "Back to the strip", size: 22) { claude.shut = true; claude.open = false }
            }
            .foregroundStyle(accent)
            if showSource {
                sourceLines.frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    (Text(q.question).font(.system(size: 13, weight: .semibold))
                     + Text(questions.count > 1 ? "  \(part + 1)/\(questions.count)" : "").font(.system(size: 10, weight: .medium)).foregroundColor(.white.opacity(0.6)))
                        .lineSpacing(2).frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic).frame(height: NotchLayout.claudeQuestionText(q))
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(q.options, id: \.label) { option in
                            Hovering { hover in
                            Button {
                                cardFocused = true // a plain button takes no focus on a click, which left Enter with nowhere to go
                                if q.multiSelect {
                                    picked[q.question] = chosen.contains(option.label) ? chosen.filter { $0 != option.label } : chosen + [option.label]
                                } else {
                                    picked[q.question] = [option.label]
                                    typed[q.question] = ""
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(option.label).font(.system(size: 11, weight: .semibold))
                                    if !option.description.isEmpty { Text(option.description).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.leading) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 8).fill(chosen.contains(option.label) ? accent.opacity(hover ? 0.45 : 0.33) : .white.opacity(hover ? 0.14 : 0.08)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(chosen.contains(option.label) ? .isSelected : [])
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic).frame(height: NotchLayout.claudeOptionsHeight(q))
                TextField("Or type your own answer", text: text).textFieldStyle(.plain).font(.system(size: 11)).focused($typing)
                    .onSubmit(next).accessibilityLabel("Your own answer")
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(typing ? 0.4 : 0.15))))
                HStack(spacing: 6) {
                    if part > 0 { pill("Back") { step = part - 1 } }
                    pill(last ? "Send" : "Next", solid: true) {
                        if last { send(questions) } else { step = part + 1 }
                    }
                    .focusable().focused($sendFocused)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1.5).padding(-3).opacity(last && allReady ? 1 : 0)) // lit: Enter sends
                    .animation(.easeOut(duration: 0.15), value: last && allReady)
                    .opacity((last ? allReady : ready) ? 1 : 0.4).disabled(!(last ? allReady : ready))
                    Spacer(minLength: 0)
                    pill("Answer in terminal") { claude.answer(request.id, .pass) }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .focusable().focused($cardFocused).focusEffectDisabled()
        .onAppear { cardFocused = true }
        .onChange(of: step) { cardFocused = true } // a new part: Enter still moves on
        // Enter moves on to the next part, or sends from the last (Send is ringed once every part has an answer).
        .onKeyPress(.return) {
            next()
            return .handled
        }
    }

    private func send(_ questions: [ClaudeQuestion]) {
        claude.answer(request.id, .answers(Dictionary(questions.map { ($0.question, answerOf($0)) }, uniquingKeysWith: { first, _ in first })))
    }
}
