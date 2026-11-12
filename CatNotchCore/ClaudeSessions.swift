import Foundation

/// One Claude Code session, as the Claude page lists it (spec 0033).
public struct ClaudeSession: Equatable, Identifiable, Sendable {
    public enum State: Equatable, Sendable { case working, compacting, idle, waiting, done }
    public var id: String
    public var project: String
    public var source: ClaudeSource
    public var state: State
    /// The last activity: a hook event or a write to the transcript, whichever is later.
    public var at: Date
    /// What you last typed, on one line, 120 characters at most.
    public var last: String
    /// What names it: Claude's latest title for it, else the start of your first message, else the folder (spec 0042).
    public var title: String = ""
    /// The tool it is running right now, as "Bash: swift test". Empty unless it is working.
    public var activity: String = ""
}

/// What Claude writes to a session's transcript (`<config dir>/projects/<folder>/<id>.jsonl`, one JSON object a line).
enum ClaudeTranscript {
    /// The whole lines in the last `bytes` of the file, parsed. A first line cut in half is dropped.
    static func tail(_ path: String, bytes: Int) -> [[String: Any]] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return [] }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines.compactMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
    }

    /// The text blocks of a user or assistant entry (a plain string counts as one).
    static func texts(_ entry: [String: Any]) -> [String] {
        let content = (entry["message"] as? [String: Any])?["content"]
        if let text = content as? String { return [text] }
        return (content as? [[String: Any]] ?? []).compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
    }

    static let interrupt = "[Request interrupted by user"

    /// Esc sends no Stop hook, but Claude writes "[Request interrupted by user…]" as a user message. Other entries
    /// (snapshots, costs) come after it, so only user and assistant entries count; and a marker older than `since` is
    /// from an earlier turn.
    static func interrupted(_ path: String, since: Date) -> Bool {
        let last = tail(path, bytes: 4096).last { ($0["type"] as? String == "user" || $0["type"] as? String == "assistant") && $0["isSidechain"] as? Bool != true }
        guard let last, last["type"] as? String == "user", texts(last).first?.hasPrefix(interrupt) == true,
              let stamp = last["timestamp"] as? String else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (formatter.date(from: stamp) ?? .distantPast) >= since
    }

    /// What you typed in a user entry, one string a text block. Sidechains, slash command echoes and the interrupt marker are not.
    private static func typed(_ entry: [String: Any]) -> [String] {
        guard entry["type"] as? String == "user", entry["isSidechain"] as? Bool != true, entry["isMeta"] as? Bool != true else { return [] }
        return texts(entry).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
            !($0.isEmpty || $0.hasPrefix("<command-") || $0.hasPrefix("<local-command") || $0.hasPrefix("Caveat:") || $0.hasPrefix(interrupt))
        }
    }

    private static func oneLine(_ text: String, limit: Int) -> String { String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit)) }

    /// The last thing you typed, on one line.
    static func lastSaid(_ path: String, limit: Int = 120) -> String {
        oneLine(tail(path, bytes: 256 * 1024).flatMap(typed).last ?? "", limit: limit)
    }

    /// The first thing you typed, from the head of the file: the name of a session Claude has not titled yet.
    static func firstSaid(_ path: String, limit: Int = 50) -> String {
        guard let handle = FileHandle(forReadingAtPath: path), let data = try? handle.read(upToCount: 65536) else { return "" }
        try? handle.close()
        let lines = data.split(separator: UInt8(ascii: "\n")) // a line cut at 64KB just fails to parse
        let entries = lines.compactMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        return oneLine(entries.flatMap(typed).first ?? "", limit: limit)
    }

    /// Claude's own title for the session: the newest `ai-title` entry (they repeat through the file as it is retitled).
    static func aiTitle(_ path: String) -> String {
        let title = tail(path, bytes: 256 * 1024).last { $0["type"] as? String == "ai-title" }?["aiTitle"] as? String
        return oneLine(title ?? "", limit: 100)
    }
}

/// The tool a session is running, as one short line for its row (spec 0042).
public enum ClaudeActivity {
    public static func describe(tool: String, input: [String: Any]) -> String {
        func field(_ key: String) -> String? { (input[key] as? String).map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") } }
        let detail: String?
        switch tool {
        case "Bash": detail = field("command")
        case "Read", "Edit", "Write", "MultiEdit": detail = field("file_path").map { URL(fileURLWithPath: $0).lastPathComponent }
        case "NotebookEdit": detail = field("notebook_path").map { URL(fileURLWithPath: $0).lastPathComponent }
        case "Grep", "Glob": detail = field("pattern")
        case "WebFetch": detail = field("url")
        case "WebSearch": detail = field("query")
        case "Task", "Agent": detail = field("description")
        default: detail = nil
        }
        // An MCP tool is "mcp__server__name": the name is what says what it does.
        let name = tool.hasPrefix("mcp__") ? String(tool.components(separatedBy: "__").last ?? tool) : tool
        return String((detail.map { "\(name): \($0)" } ?? name).prefix(100))
    }
}

/// Every live Claude session and what it is doing, from the hook events and Claude's own files. Use from the main actor.
@MainActor
public final class ClaudeSessions {
    private final class Entry {
        enum Phase { case working, compacting, idle }
        let id: String
        var cwd = ""
        var source = ClaudeSource.unknown
        var phase = Phase.idle
        var at = Date.distantPast
        var transcript = ""
        var mtime = Date.distantPast
        var sourceRead = false
        /// The transcript time the interrupt check last looked at, and the last message was last read at.
        var checked = Date.distantPast
        var tailed = Date.distantPast
        var last = ""
        var aiTitle = ""
        var firstSaid = ""
        var activity = ""
        var pid = 0
        init(id: String) { self.id = id }
    }

    private let configDir: URL
    private let clock: () -> Date
    private let alive: (Int) -> Bool
    private let staleAfter: TimeInterval
    private var entries: [String: Entry] = [:]
    private var lastSent: [ClaudeSession] = []

    private static let maxSessions = 20

    /// Called with the list whenever it really changed.
    public var onChange: ([ClaudeSession]) -> Void = { _ in }
    /// The sessions with a request waiting on a click: they show as `waiting`, and are not judged interrupted.
    public var waiting: Set<String> = [] { didSet { if waiting != oldValue { emit() } } }

    /// Sessions that finished a turn and have not been looked at since: they show as `done` instead of `idle`.
    public private(set) var done: Set<String> = []
    /// The user looked at the list: "Done" goes back to idle.
    public func markSeen() { if !done.isEmpty { done = []; emit() } }

    public init(configDir: URL, now: @escaping () -> Date = Date.init, alive: @escaping (Int) -> Bool = ClaudeSessions.isAlive, staleAfter: TimeInterval = 600) {
        self.configDir = configDir
        clock = now
        self.alive = alive
        self.staleAfter = staleAfter
    }

    /// A process that exists, even if it is not ours to signal.
    public nonisolated static func isAlive(_ pid: Int) -> Bool {
        guard pid > 0, let id = pid_t(exactly: pid) else { return false }
        return kill(id, 0) == 0 || errno == EPERM
    }

    private static func text(_ value: Any?, max: Int) -> String { (value as? String).map { String($0.prefix(max)) } ?? "" }

    public var list: [ClaudeSession] {
        entries.values
            .map { e in
                let project = e.cwd.isEmpty ? "" : URL(fileURLWithPath: e.cwd).lastPathComponent
                let state: ClaudeSession.State = waiting.contains(e.id) ? .waiting : e.phase == .working ? .working : e.phase == .compacting ? .compacting : done.contains(e.id) ? .done : .idle
                return ClaudeSession(id: e.id, project: project.isEmpty || project == "/" ? "Claude" : project, source: e.source, state: state, at: max(e.at, e.mtime), last: e.last,
                                     title: !e.aiTitle.isEmpty ? e.aiTitle : !e.firstSaid.isEmpty ? e.firstSaid : project.isEmpty || project == "/" ? "Claude" : project,
                                     activity: e.phase == .working && !waiting.contains(e.id) ? e.activity : "")
            }
            .sorted { $0.at > $1.at }
            .prefix(Self.maxSessions).map { $0 }
    }

    /// The process of a session, for finding its window.
    public func pid(of id: String) -> Int? { entries[id].flatMap { $0.pid > 0 ? $0.pid : nil } }

    public func clear() {
        entries = [:]
        emit()
    }

    private func emit() {
        let next = list
        guard next != lastSent else { return }
        lastSent = next
        onChange(next)
    }

    /// A hook event (or a request) for a session: note it, and what it says about the state.
    /// True when it ended a turn that was working: the moment for the sound.
    @discardableResult
    public func seen(_ body: [String: Any]) -> Bool {
        let id = Self.text(body["session_id"], max: 100)
        guard !id.isEmpty else { return false }
        let event = Self.text(body["hook_event_name"], max: 40)
        if event == "SessionEnd" {
            entries[id] = nil
            done.remove(id)
            emit()
            return false
        }
        let now = clock()
        let entry = entries[id] ?? Entry(id: id)
        let cwd = Self.text(body["cwd"], max: 1000)
        if !cwd.isEmpty { entry.cwd = cwd }
        let transcript = Self.text(body["transcript_path"], max: 1000)
        if !transcript.isEmpty { entry.transcript = transcript }
        let was = entry.phase
        // A manual /compact is a turn of its own and, as far as the docs say, ends with PostCompact and no Stop: idle then.
        // An auto compact happens mid turn, so the turn goes on.
        let ends = event == "Stop" || (event == "PostCompact" && body["trigger"] as? String == "manual")
        if !ends { done.remove(id) }
        entry.phase = ends ? .idle : event == "PreCompact" ? .compacting : .working
        entry.at = now
        entry.activity = event == "PreToolUse" ? ClaudeActivity.describe(tool: Self.text(body["tool_name"], max: 80), input: body["tool_input"] as? [String: Any] ?? [:]) : ""
        entries[id] = entry
        readSource(entry)
        if entry.firstSaid.isEmpty, !entry.transcript.isEmpty { entry.firstSaid = ClaudeTranscript.firstSaid(entry.transcript) }
        let finished = event == "Stop" && was == .working
        if finished { done.insert(id) }
        emit()
        return finished
    }

    /// CLI or VS Code, from the first lines of the transcript. Read once per session.
    private func readSource(_ entry: Entry) {
        guard !entry.sourceRead, !entry.transcript.isEmpty, let handle = FileHandle(forReadingAtPath: entry.transcript) else { return }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 65536)) ?? Data(), as: UTF8.self)
        guard let key = head.range(of: "\"entrypoint\":\"") else { return }
        switch head[key.upperBound...].prefix(while: { $0 != "\"" }) {
        case "cli": entry.source = .cli
        case "claude-vscode": entry.source = .vscode
        default: entry.source = .unknown
        }
        entry.sourceRead = true
    }

    /// Claude keeps one file per running session in `<config dir>/sessions` (its pid, id and folder). That is the
    /// list of live sessions. Called every few seconds.
    public func scan() {
        let now = clock()
        var live: Set<String> = []
        let dir = configDir.appendingPathComponent("sessions")
        for file in ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []) where file.hasSuffix(".json") {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
                  let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let id = Self.text(info["sessionId"], max: 100)
            guard !id.isEmpty, let pid = (info["pid"] as? NSNumber)?.intValue, alive(pid) else { continue }
            live.insert(id)
            let entry = entries[id] ?? Entry(id: id)
            let cwd = Self.text(info["cwd"], max: 1000)
            if !cwd.isEmpty { entry.cwd = cwd }
            entry.pid = pid
            // The transcript lives in a folder named after the cwd (letters and digits kept, the rest a dash).
            if entry.transcript.isEmpty {
                let folder = String(entry.cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
                entry.transcript = configDir.appendingPathComponent("projects/\(folder)/\(id).jsonl").path
            }
            if let modified = (try? FileManager.default.attributesOfItem(atPath: entry.transcript))?[.modificationDate] as? Date { entry.mtime = modified }
            entries[id] = entry
        }
        for (id, entry) in entries {
            if !live.contains(id) {
                entries[id] = nil
            } else if entry.phase != .idle && now.timeIntervalSince(max(entry.at, entry.mtime)) > staleAfter {
                entry.phase = .idle // the last resort: Claude said nothing for a long time
            } else {
                readSource(entry)
                if entry.mtime != entry.tailed {
                    entry.tailed = entry.mtime
                    entry.last = ClaudeTranscript.lastSaid(entry.transcript)
                    entry.aiTitle = ClaudeTranscript.aiTitle(entry.transcript)
                    if entry.firstSaid.isEmpty { entry.firstSaid = ClaudeTranscript.firstSaid(entry.transcript) }
                }
                // Only when the transcript changed, and not while Claude waits on a request: a quiet transcript means
                // nothing (long builds write nothing for minutes).
                if entry.phase == .working, !waiting.contains(id), entry.mtime != entry.checked {
                    entry.checked = entry.mtime
                    if ClaudeTranscript.interrupted(entry.transcript, since: entry.at) { entry.phase = .idle }
                }
            }
        }
        emit()
    }
}

/// Sessions hidden from the page until they have news (spec 0033 AC-5): session id to the time it was archived.
public enum ClaudeArchive {
    /// A session stays hidden while it was archived at or after its last activity.
    public static func visible(_ sessions: [ClaudeSession], archived: [String: Double]) -> [ClaudeSession] {
        sessions.filter { session in
            guard let at = archived[session.id] else { return true }
            return at < session.at.timeIntervalSince1970
        }
    }

    /// `archived` with `id` added now, and what is over a month old gone, so the list cannot grow for ever.
    public static func archiving(_ id: String, in archived: [String: Double], now: Date) -> [String: Double] {
        var next = archived.filter { now.timeIntervalSince1970 - $0.value < 30 * 86_400 }
        next[id] = now.timeIntervalSince1970
        return next
    }
}

extension StoreData {
    public var claudeArchived: [String: Double] {
        get {
            guard case .object(let o)? = settings["claudeArchived"] else { return [:] }
            return o.compactMapValues { if case .number(let n) = $0 { n } else { nil } }
        }
        set { settings["claudeArchived"] = .object(newValue.mapValues { .number($0) }) }
    }
}

/// Which app owns a session (spec 0033 AC-6).
public enum ClaudeFocus {
    /// From `pid`, up the parents to the first process inside an `.app` bundle, and that bundle's path. `ps` is the output
    /// of `ps -axo pid=,ppid=,comm=`. Nil when there is none (a terminal that is not an app).
    public static func appPath(pid: Int, ps: String) -> String? {
        var table: [Int: (parent: Int, command: String)] = [:]
        for line in ps.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let id = Int(parts[0]), let parent = Int(parts[1]) else { continue }
            table[id] = (parent, parts[2].trimmingCharacters(in: .whitespaces))
        }
        var at = pid
        for _ in 0..<50 {
            guard at > 1, let process = table[at] else { return nil }
            if let bundle = process.command.range(of: ".app/") { return String(process.command[..<bundle.upperBound].dropLast()) }
            at = process.parent
        }
        return nil
    }
}
