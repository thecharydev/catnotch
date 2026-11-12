import Darwin
import Foundation
import Testing
@testable import CatNotchCore

// Spec 0033: the sessions, driven by hook events and Claude's own files in a temp config folder, never the real ~/.claude.
// Ported from the "interrupted sessions" tests in main/ipc/claude.test.ts.

private final class Clock: @unchecked Sendable {
    var now = Date()
    var alive = true
}

/// One test's world: a live session ("sess", in /work/proj) with a transcript.
@MainActor private final class World {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let clock = Clock()
    let sessions: ClaudeSessions
    let transcript: URL
    private var bump = 0

    init(staleAfter: TimeInterval = 600) throws {
        let dir = root.appendingPathComponent("sessions")
        transcript = root.appendingPathComponent("projects/-work-proj/sess.jsonl")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["sessionId": "sess", "pid": Int(getpid()), "cwd": "/work/proj"]).write(to: dir.appendingPathComponent("a.json"))
        let clock = clock
        sessions = ClaudeSessions(configDir: root, now: { clock.now }, alive: { _ in clock.alive }, staleAfter: staleAfter)
        try write(entry("user", "build it"))
    }

    func finish() { try? FileManager.default.removeItem(at: root) }

    /// A transcript line. `at` is when it was written, as the entry's own timestamp.
    func entry(_ type: String, _ text: String, at: Date? = nil, extra: [String: Any] = [:]) -> String {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var object: [String: Any] = ["type": type, "timestamp": stamp.string(from: at ?? clock.now), "message": ["content": [["type": "text", "text": text]]]]
        object.merge(extra) { $1 }
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
    }

    /// The marker, then the entries Claude writes after it (neither is a message).
    func marker(_ text: String = "[Request interrupted by user]", at: Date? = nil) -> String {
        entry("user", text, at: at ?? clock.now.addingTimeInterval(1)) + "{\"type\":\"system\"}\n{\"type\":\"cost-state\"}\n"
    }

    func write(_ text: String) throws {
        if let handle = FileHandle(forWritingAtPath: transcript.path) {
            try handle.seekToEnd(); try handle.write(contentsOf: Data(text.utf8)); try handle.close()
        } else {
            try text.write(to: transcript, atomically: true, encoding: .utf8)
        }
        // Writes in the same instant would leave the modification time as it was.
        bump += 1
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(bump))], ofItemAtPath: transcript.path)
    }

    @discardableResult
    func event(_ name: String, trigger: String? = nil, tool: String? = nil, input: [String: Any] = [:]) -> Bool {
        var body: [String: Any] = ["hook_event_name": name, "session_id": "sess", "cwd": "/work/proj", "transcript_path": transcript.path]
        if let trigger { body["trigger"] = trigger }
        if let tool { body["tool_name"] = tool; body["tool_input"] = input }
        return sessions.seen(body)
    }

    var state: ClaudeSession.State? { sessions.list.first?.state }
    var last: String? { sessions.list.first?.last }
    var title: String? { sessions.list.first?.title }
    var activity: String? { sessions.list.first?.activity }
}

@MainActor @Suite struct ClaudeSessionStates {
    @Test func theHooksSayWhatASessionIsDoing() throws {
        let w = try World(); defer { w.finish() }
        #expect(!w.event("UserPromptSubmit") && w.state == .working)
        w.event("PreCompact", trigger: "auto")
        #expect(w.state == .compacting)
        w.event("PostCompact", trigger: "auto") // mid turn: the turn goes on
        #expect(w.state == .working)
        #expect(w.event("Stop") && w.state == .done) // a turn ended: the moment for the banner and sound
        #expect(!w.event("Stop")) // already idle: nothing ended
        w.event("PreCompact", trigger: "manual")
        #expect(w.state == .compacting)
        w.event("PostCompact", trigger: "manual") // a /compact typed by hand ends with no Stop
        #expect(w.state == .idle)
        w.event("UserPromptSubmit")
        w.event("SessionEnd")
        #expect(w.sessions.list.isEmpty)
    }

    @Test func aSessionWithARequestWaitingShowsAsWaiting() throws {
        let w = try World(); defer { w.finish() }
        w.event("UserPromptSubmit")
        w.sessions.waiting = ["sess"]
        #expect(w.state == .waiting)
        w.sessions.waiting = []
        #expect(w.state == .working)
    }

    @Test func theListComesFromTheSessionFilesAndNamesTheProjectAndSource() throws {
        let w = try World(); defer { w.finish() }
        try w.write("{\"entrypoint\":\"claude-vscode\",\"cwd\":\"/work/proj\"}\n")
        w.sessions.scan() // no hook event yet: found from Claude's own file
        #expect(w.sessions.list == [ClaudeSession(id: "sess", project: "proj", source: .vscode, state: .idle, at: w.sessions.list[0].at, last: "build it", title: "build it")])
        #expect(w.sessions.pid(of: "sess") == Int(getpid()))
        w.clock.alive = false // its process is gone
        w.sessions.scan()
        #expect(w.sessions.list.isEmpty)
    }

    @Test func aSessionWithNoNewsForTenMinutesGoesIdle() throws {
        let w = try World(); defer { w.finish() }
        w.event("UserPromptSubmit")
        w.sessions.scan()
        #expect(w.state == .working)
        w.clock.now = w.clock.now.addingTimeInterval(11 * 60)
        w.sessions.scan()
        #expect(w.state == .idle)
    }

    @Test func onChangeSpeaksOnlyWhenTheListReallyChanged() throws {
        let w = try World(); defer { w.finish() }
        var calls = 0
        w.sessions.onChange = { _ in calls += 1 }
        w.event("UserPromptSubmit")
        w.event("UserPromptSubmit")
        #expect(calls == 1) // the second changed nothing
    }
}

@MainActor @Suite struct ClaudeInterrupts {
    @Test(arguments: ["[Request interrupted by user]", "[Request interrupted by user for tool use]"])
    func goesIdleOnTheMarkerEvenWithOtherEntriesAfterIt(text: String) throws {
        let w = try World(); defer { w.finish() }
        w.event("UserPromptSubmit")
        w.sessions.scan()
        #expect(w.state == .working) // the last message is a plain prompt
        try w.write(w.marker(text))
        w.sessions.scan()
        #expect(w.state == .idle)
    }

    @Test func staysWorkingForAQuietTranscriptAndForAMarkerOlderThanTheLastHookEvent() throws {
        let w = try World(); defer { w.finish() }
        w.event("UserPromptSubmit")
        try w.write(w.entry("assistant", "still building"))
        w.sessions.scan(); w.sessions.scan()
        #expect(w.state == .working)
        try w.write(w.marker(at: w.clock.now.addingTimeInterval(-60))) // an earlier turn's
        w.sessions.scan()
        #expect(w.state == .working)
    }

    @Test func doesNotDecideWhileARequestIsWaitingAndDoesOnceItIsGone() throws {
        let w = try World(); defer { w.finish() }
        w.event("UserPromptSubmit")
        w.sessions.waiting = ["sess"]
        try w.write(w.marker())
        w.sessions.scan()
        w.sessions.waiting = []
        #expect(w.state == .working) // not judged while it waited
        w.sessions.scan()
        #expect(w.state == .idle)
    }

    @Test func aSidechainMarkerIsNotTheSessions() throws {
        let w = try World(); defer { w.finish() }
        w.event("UserPromptSubmit")
        try w.write(w.entry("user", "[Request interrupted by user]", at: w.clock.now.addingTimeInterval(1), extra: ["isSidechain": true]))
        w.sessions.scan()
        #expect(w.state == .working)
    }
}

@MainActor @Suite struct ClaudeLastMessage {
    @Test func isYourLastMessageOnOneLineCutTo120AndNeverTheMarkerOrACommandEcho() throws {
        let w = try World(); defer { w.finish() }
        w.sessions.scan()
        #expect(w.last == "build it")
        try w.write(w.entry("assistant", "ok") + w.entry("user", "two\nlines " + String(repeating: "x", count: 300)))
        w.sessions.scan()
        #expect(w.last?.count == 120 && w.last?.hasPrefix("two lines x") == true)
        try w.write(w.entry("user", "<command-name>/clear</command-name>") + w.marker())
        w.sessions.scan()
        #expect(w.last?.hasPrefix("two lines") == true)
    }
}

@MainActor @Suite struct ClaudeArchiveAndFocus {
    private func session(_ id: String, at: Double) -> ClaudeSession {
        ClaudeSession(id: id, project: id, source: .cli, state: .idle, at: Date(timeIntervalSince1970: at), last: "")
    }

    @Test func archivedSessionsAreHiddenUntilTheyHaveNewActivity() {
        let list = [session("a", at: 100), session("b", at: 100)]
        #expect(ClaudeArchive.visible(list, archived: ["a": 150]).map(\.id) == ["b"])
        #expect(ClaudeArchive.visible(list, archived: ["a": 100]).map(\.id) == ["b"]) // archived at its last activity
        #expect(ClaudeArchive.visible([session("a", at: 200), session("b", at: 100)], archived: ["a": 150]).map(\.id) == ["a", "b"]) // news
    }

    @Test func archivingForgetsWhatIsOverAMonthOldAndTheStoreKeepsIt() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let next = ClaudeArchive.archiving("new", in: ["old": now.timeIntervalSince1970 - 31 * 86_400, "recent": now.timeIntervalSince1970 - 86_400], now: now)
        #expect(Set(next.keys) == ["new", "recent"])
        var data = StoreData()
        #expect(data.claudeArchived.isEmpty)
        data.claudeArchived = next
        #expect(data.claudeArchived == next)
    }

    private let ps = """
      4242   500 /Users/me/.local/share/claude/versions/2.1
       500   400 /bin/zsh
       400   300 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)
       300     1 /Applications/Visual Studio Code.app/Contents/MacOS/Electron
       900     1 /usr/bin/claude
    """

    @Test func theOwningAppIsTheFirstAppBundleUpTheProcessTreeSpacesAndAll() {
        #expect(ClaudeFocus.appPath(pid: 4242, ps: ps) == "/Applications/Visual Studio Code.app")
    }

    @Test func noAppAboveMeansNoPathAndSoDoesAnUnknownProcess() {
        #expect(ClaudeFocus.appPath(pid: 900, ps: ps) == nil)
        #expect(ClaudeFocus.appPath(pid: 31337, ps: ps) == nil)
        #expect(ClaudeFocus.appPath(pid: 4242, ps: "") == nil)
    }
}

// Spec 0042: a session is named by its title and shows the tool it is running.
@MainActor @Suite struct ClaudeTitleAndActivity {
    @Test func theTitleIsTheNewestAiTitleElseTheFirstMessageCutTo50ElseTheFolder() throws {
        let w = try World(); defer { w.finish() }
        w.sessions.scan()
        #expect(w.title == "build it") // the first message (World writes it)
        try w.write("{\"type\":\"ai-title\",\"aiTitle\":\"Old name\"}\n" + w.entry("assistant", "ok") + "{\"type\":\"ai-title\",\"aiTitle\":\"New name\"}\n")
        w.sessions.scan()
        #expect(w.title == "New name") // retitled: the newest wins
        let empty = try World(); defer { empty.finish() }
        try FileManager.default.removeItem(at: empty.transcript)
        empty.sessions.scan()
        #expect(empty.title == "proj")
    }

    @Test func aLongFirstMessageIsCutTo50AndAnEchoIsNotAMessage() throws {
        let w = try World(); defer { w.finish() }
        try FileManager.default.removeItem(at: w.transcript) // start over with these two lines only
        try w.write(w.entry("user", "<command-name>/clear</command-name>") + w.entry("user", String(repeating: "word ", count: 30)))
        w.sessions.scan()
        #expect(w.title?.count == 50 && w.title?.hasPrefix("word word") == true)
    }

    @Test func theToolShowsWhileWorkingAndClearsOnPostToolUseStopAndInterrupt() throws {
        let w = try World(); defer { w.finish() }
        w.event("UserPromptSubmit")
        #expect(w.activity == "")
        w.event("PreToolUse", tool: "Bash", input: ["command": "swift test"])
        #expect(w.activity == "Bash: swift test")
        w.event("PostToolUse", tool: "Bash", input: ["command": "swift test"])
        #expect(w.activity == "")
        w.event("PreToolUse", tool: "Read", input: ["file_path": "/work/proj/a.swift"])
        #expect(w.activity == "Read: a.swift")
        w.event("Stop")
        #expect(w.activity == "")
        w.event("UserPromptSubmit")
        w.event("PreToolUse", tool: "Bash", input: ["command": "sleep 99"])
        try w.write(w.marker()) // Esc: no hook event, the transcript says so
        w.sessions.scan()
        #expect(w.state == .idle && w.activity == "")
    }
}

@Suite struct ClaudeActivityText {
    @Test(arguments: [
        ("Bash", ["command": "swift   test\n  -v"], "Bash: swift test -v"),
        ("Edit", ["file_path": "/a/b/ClaudeViews.swift"], "Edit: ClaudeViews.swift"),
        ("Grep", ["pattern": "onTurnEnd"], "Grep: onTurnEnd"),
        ("WebFetch", ["url": "https://x.dev/a"], "WebFetch: https://x.dev/a"),
        ("mcp__claude_ai_Slack__send_message", ["channel": "c"], "send_message"),
        ("TodoWrite", ["todos": "x"], "TodoWrite"),
    ])
    func formatsTheToolInputPerTool(tool: String, input: [String: String], text: String) {
        #expect(ClaudeActivity.describe(tool: tool, input: input) == text)
    }

    @Test func aLongCommandIsCut() {
        #expect(ClaudeActivity.describe(tool: "Bash", input: ["command": String(repeating: "x", count: 500)]).count == 100)
    }
}
