import Foundation
import Network
import os

private let claudeLogger = Logger(subsystem: "com.thecharydev.catnotch", category: "claude")

/// Claude Code on the Notch: when Claude wants to run a tool, or asks a question, its hooks call this small
/// server and the Notch shows it. The click comes back as the hook's reply. Anything that goes wrong (no answer
/// in 60 s, the app closed, a bad request) is an empty reply or none, and Claude then shows its own prompt,
/// so this can never leave a session stuck.
///
/// Only 127.0.0.1, only POST, only with the secret token, so nothing else on the machine (or a web page)
/// can approve a command. Use it from the main actor.
public struct ClaudeQuestion: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public var label: String
        public var description: String
    }
    public var question: String
    public var header: String
    public var multiSelect: Bool
    public var options: [Option]
}

/// What the Notch is shown. Never the open connection.
public struct ClaudeRequest: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case permission(tool: String, text: String)
        case question([ClaudeQuestion])
    }
    public var id: String
    public var sessionId: String
    /// The folder name Claude is working in.
    public var project: String
    public var kind: Kind
    /// A permission Claude offered "always allow" rules for. The rules themselves stay in the server.
    public var always = false
}

/// A click on a request. Only these shapes ever reach Claude.
public enum ClaudeChoice: Equatable, Sendable {
    case allow, deny
    /// Allow, and keep the rule Claude suggested so it does not ask again. Only for a request that came with one.
    case always
    /// Back to Claude's own prompt in the terminal.
    case pass
    /// The chosen labels (or typed text) per question text.
    case answers([String: [String]])
}

/// A flag only the main queue touches (the listener's handlers run there).
private final class Once: @unchecked Sendable { var done = false }

@MainActor
public final class ClaudeHooks {
    public enum Enabled: Equatable, Sendable { case ok, port, invalid, write }

    private let store: CatNotchStore
    private let configDir: URL
    private let isTerminalInFront: (ClaudeSource) -> Bool
    private let fallThrough: TimeInterval
    /// Every live session, from the reporting events and Claude's own files (spec 0033).
    public let sessions: ClaudeSessions
    private var scanning: Task<Void, Never>?
    private var listener: NWListener?
    private var waiting: [Waiting] = []
    /// Connections still sending their request, so a silent one can be dropped.
    private var reading: Set<ObjectIdentifier> = []

    private struct Waiting {
        var view: ClaudeRequest
        var connection: NWConnection
        var timer: Task<Void, Never>?
        var held: Set<Hold> = []
        /// Claude's `permission_suggestions`, handed back as `updatedPermissions` for `.always`.
        var suggestions: [Any] = []
        /// What a finished tool must match to drop this request: `tool_use_id` for a question, tool and input for a permission.
        var toolUseId = ""
        var tool = ""
        var input = ""
    }

    /// Why the 60 s timer is off: an answer is being typed, or the pointer is on the request.
    public enum Hold: Sendable { case typing, hover }

    private static let maxBody = 1_000_000
    private static let maxWaiting = 20
    private static let maxSuggestions = 10

    /// The requests waiting for a click, oldest first.
    public var requests: [ClaudeRequest] { waiting.map(\.view) }
    /// Called with the queue whenever it changes.
    public var onChange: ([ClaudeRequest]) -> Void = { _ in }
    /// Called with the session id and title (spec 0042) when a turn ends (`Stop` on a session that was working), unless that
    /// session's terminal is in front: the moment for the banner and the sound (spec 0040).
    public var onTurnEnd: (_ id: String, _ title: String) -> Void = { _, _ in }
    /// The live port, 0 while not running.
    public private(set) var port = 0
    public var isRunning: Bool { port != 0 }

    public init(store: CatNotchStore, configDir: URL, isTerminalInFront: @escaping (ClaudeSource) -> Bool = { _ in false }, fallThrough: TimeInterval = 60) {
        self.store = store
        self.configDir = configDir
        self.isTerminalInFront = isTerminalInFront
        self.fallThrough = fallThrough
        sessions = ClaudeSessions(configDir: configDir)
    }

    /// Claude's config folder: `CLAUDE_CONFIG_DIR`, else `~/.claude`.
    public static func standardConfigDir() -> URL {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty { return URL(fileURLWithPath: dir) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    private var settingsFile: URL { configDir.appendingPathComponent("settings.json") }
    private var setting: ClaudeHooksSetting { store.data.claudeHooks }

    // MARK: Server

    /// Listens on `first`, or the next free port (20 tries). Returns the port, or 0.
    private func listen(from first: Int) async -> Int {
        for candidate in first..<(first + 20) where candidate <= 65535 {
            guard let found = await bind(candidate) else { continue }
            listener = found
            return candidate
        }
        return 0
    }

    private func bind(_ port: Int) async -> NWListener? {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: UInt16(port))!)
        guard let listener = try? NWListener(using: params) else { return nil }
        listener.newConnectionHandler = { [weak self] connection in MainActor.assumeIsolated { self?.accept(connection) } }
        let ready: Bool = await withCheckedContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { state in
                guard !once.done else { return }
                switch state {
                case .ready: once.done = true; continuation.resume(returning: true)
                case .failed, .cancelled: once.done = true; continuation.resume(returning: false)
                default: break
                }
            }
            listener.start(queue: .main)
        }
        if !ready { listener.cancel(); return nil }
        // A listener that dies later must not leave `port` set: the hooks would then fail silently.
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard case .failed = state else { return }
            MainActor.assumeIsolated { if let self, self.listener === listener { self.stop() } }
        }
        return listener
    }

    private func stop() {
        // Quitting answers everything empty, so no Claude session is left waiting.
        for item in waiting { leave(item.view.id).map { reply($0.connection, [:]) } }
        listener?.cancel()
        listener = nil
        port = 0
        scanning?.cancel()
        scanning = nil
        sessions.clear()
    }

    /// Looks at Claude's session files now and every 5 s, for as long as the server runs.
    private func startScanning() {
        scanning?.cancel()
        scanning = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sessions.scan()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: HTTP

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        let key = ObjectIdentifier(connection)
        reading.insert(key)
        read(connection, Data())
        // Whoever has not finished asking after 10 s is dropped; a request we hold has left `reading` by then.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            MainActor.assumeIsolated { if self?.reading.remove(key) != nil { connection.cancel() } }
        }
    }

    private func read(_ connection: NWConnection, _ have: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, self.reading.contains(ObjectIdentifier(connection)) else { return }
                var buffer = have
                if let data { buffer.append(data) }
                if error != nil || (complete && !self.consume(connection, buffer)) { return connection.cancel() }
                if !complete, !self.consume(connection, buffer) { self.read(connection, buffer) }
            }
        }
    }

    /// Looks at what has arrived. True once the request has been dealt with, false if more is needed.
    private func consume(_ connection: NWConnection, _ buffer: Data) -> Bool {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > 65536 { refuse(connection, 431) }
            return buffer.count > 65536
        }
        let lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { refuse(connection, 400); return true }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        // The gate, in order, before any body is read.
        if headers["host"] != "127.0.0.1:\(port)" { refuse(connection, 403); return true }
        if first[0] != "POST" { refuse(connection, 405); return true }
        if !tokenOK(headers["authorization"]) { refuse(connection, 401); return true }
        let route = first[1].hasPrefix("/desknotch/") ? String(first[1].dropFirst("/desknotch/".count)) : ""
        guard ["permission", "question", "event"].contains(route) else { refuse(connection, 404); return true }
        guard let length = Int(headers["content-length"] ?? "0"), length >= 0 else { refuse(connection, 400); return true }
        if length > Self.maxBody { refuse(connection, 413); return true }

        let body = buffer[end.upperBound...]
        if body.count < length { return false }
        reading.remove(ObjectIdentifier(connection))
        let json = (try? JSONSerialization.jsonObject(with: body.prefix(length))) as? [String: Any]
        guard let json, route != "event" else {
            reply(connection, [:]) // reports never wait, and a body we cannot read gets Claude's own prompt
            if let json, Self.text(json["hook_event_name"], max: 40) == "PostToolUse" { dropAnswered(json) }
            if let json, ClaudeSettingsFile.reporting.contains(Self.text(json["hook_event_name"], max: 40)), sessions.seen(json),
               !isTerminalInFront(sourceOf(transcript: Self.text(json["transcript_path"], max: 1000))) {
                let id = Self.text(json["session_id"], max: 100)
                onTurnEnd(id, sessions.list.first { $0.id == id }?.title ?? "Claude")
            }
            return true
        }
        add(route, json, connection)
        return true
    }

    private func tokenOK(_ header: String?) -> Bool {
        guard !setting.token.isEmpty, let header else { return false }
        let want = Array("Bearer \(setting.token)".utf8), got = Array(header.utf8)
        guard want.count == got.count else { return false }
        return zip(want, got).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0 // the same time whatever the guess
    }

    private static let reasons = [400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large", 431: "Request Header Fields Too Large"]

    /// Closes the connection after sending `head` and `body`.
    private func finish(_ connection: NWConnection, _ head: String, _ body: Data, linger: Bool) {
        reading.remove(ObjectIdentifier(connection))
        let data = Data((head + "\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n").utf8) + body
        connection.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated {
                guard linger else { return connection.cancel() }
                self?.drain(connection)
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { connection.cancel() }
            }
        })
    }

    private func reply(_ connection: NWConnection, _ body: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: .withoutEscapingSlashes)) ?? Data("{}".utf8)
        finish(connection, "HTTP/1.1 200 OK\r\nContent-Type: application/json", data, linger: false)
    }

    private func refuse(_ connection: NWConnection, _ status: Int) {
        finish(connection, "HTTP/1.1 \(status) \(Self.reasons[status] ?? "Error")", Data(), linger: true)
    }

    /// Lets the unread rest of a refused request go by, so the sender sees the status, not a reset.
    private func drain(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, complete, error in
            MainActor.assumeIsolated { if complete || error != nil { connection.cancel() } else { self?.drain(connection) } }
        }
    }

    // MARK: Requests

    private static func text(_ value: Any?, max: Int = 500) -> String { (value as? String).map { String($0.prefix(max)) } ?? "" }

    /// The line a permission shows: the command, the file, or the input cut short.
    private static func describe(_ tool: String, _ input: [String: Any]) -> String {
        if tool == "Bash", let command = input["command"] as? String { return String(command.prefix(20_000)) }
        if let file = input["file_path"] as? String { return file }
        if let file = input["notebook_path"] as? String { return file }
        let json = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return String(json.prefix(300))
    }

    private static func questions(_ input: [String: Any]) -> [ClaudeQuestion] {
        (input["questions"] as? [[String: Any]] ?? []).prefix(8).map { q in
            ClaudeQuestion(question: text(q["question"]), header: text(q["header"], max: 60), multiSelect: q["multiSelect"] as? Bool == true,
                           options: (q["options"] as? [[String: Any]] ?? []).prefix(12).map { .init(label: text($0["label"], max: 200), description: text($0["description"], max: 400)) })
        }
    }

    /// Where the session runs, read from its transcript (CLI or VS Code), so the terminal rule can tell them apart.
    private func sourceOf(transcript path: String) -> ClaudeSource {
        let projects = configDir.appendingPathComponent("projects").resolvingSymlinksInPath().path + "/"
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard !path.isEmpty, file.path.hasPrefix(projects), let handle = try? FileHandle(forReadingFrom: file) else { return .unknown }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 65536)) ?? Data(), as: UTF8.self)
        guard let key = head.range(of: "\"entrypoint\":\"") else { return .unknown }
        switch head[key.upperBound...].prefix(while: { $0 != "\"" }) {
        case "cli": return .cli
        case "claude-vscode": return .vscode
        default: return .unknown
        }
    }

    private func add(_ route: String, _ body: [String: Any], _ connection: NWConnection) {
        let input = body["tool_input"] as? [String: Any] ?? [:]
        let tool = Self.text(body["tool_name"], max: 80)
        // A question reaches us on its own route; the permission route must not show it twice.
        if (route == "permission" && tool == "AskUserQuestion") || waiting.count >= Self.maxWaiting { return reply(connection, [:]) }

        let kind: ClaudeRequest.Kind
        if route == "permission" {
            kind = .permission(tool: tool.isEmpty ? "Tool" : tool, text: Self.describe(tool, input))
        } else {
            let questions = Self.questions(input)
            if questions.isEmpty || questions.contains(where: { $0.options.isEmpty }) { return reply(connection, [:]) }
            kind = .question(questions)
        }
        sessions.seen(body)
        // You are already in the window where Claude is asking: its own prompt is in front of you.
        if isTerminalInFront(sourceOf(transcript: Self.text(body["transcript_path"], max: 1000))) { return reply(connection, [:]) }

        let id = UUID().uuidString.lowercased()
        let project = URL(fileURLWithPath: Self.text(body["cwd"], max: 1000)).lastPathComponent
        let suggestions = route == "permission" ? Array((body["permission_suggestions"] as? [Any] ?? []).prefix(Self.maxSuggestions)) : []
        let view = ClaudeRequest(id: id, sessionId: Self.text(body["session_id"], max: 100), project: project.isEmpty || project == "/" ? "Claude" : project, kind: kind, always: !suggestions.isEmpty)
        var item = Waiting(view: view, connection: connection, timer: timer(id), suggestions: suggestions)
        item.tool = tool
        if route == "permission" { item.input = Self.canonical(input) } else { item.toolUseId = Self.text(body["tool_use_id"], max: 100) }
        waiting.append(item)
        watch(connection, id)
        changed()
    }

    private static func canonical(_ input: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes])).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// A tool finished, so whoever answered did it elsewhere (CLI, VS Code): drop the request it matches (spec 0039).
    private func dropAnswered(_ body: [String: Any]) {
        let session = Self.text(body["session_id"], max: 100), tool = Self.text(body["tool_name"], max: 80)
        let useId = Self.text(body["tool_use_id"], max: 100), input = Self.canonical(body["tool_input"] as? [String: Any] ?? [:])
        for item in waiting where item.view.sessionId == session {
            let same = item.toolUseId.isEmpty ? (item.tool == tool && item.input == input) : item.toolUseId == useId
            if same { leave(item.view.id).map { reply($0.connection, [:]) } }
        }
    }

    /// The queue changed: the sessions with a request waiting show as such, and the Notch is told.
    private func changed() {
        sessions.waiting = Set(waiting.map(\.view.sessionId))
        onChange(requests)
    }

    /// The 60 s fall through: an empty reply, so Claude shows its own prompt.
    private func timer(_ id: String) -> Task<Void, Never> {
        Task { @MainActor [weak self, fallThrough] in
            try? await Task.sleep(for: .seconds(fallThrough))
            guard !Task.isCancelled, let self else { return }
            leave(id).map { reply($0.connection, [:]) }
        }
    }

    /// Claude gave up on this request (moved on, the session ended): drop it.
    private func watch(_ connection: NWConnection, _ id: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, complete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if complete || error != nil { self.leave(id) } else { self.watch(connection, id) }
            }
        }
    }

    /// Takes a request out of the queue, whatever the reason.
    @discardableResult
    private func leave(_ id: String) -> Waiting? {
        guard let i = waiting.firstIndex(where: { $0.view.id == id }) else { return nil }
        let item = waiting.remove(at: i)
        item.timer?.cancel()
        changed()
        return item
    }

    /// Typing an answer, or the pointer on the request, pauses the 60 s timer; letting go of both restarts it.
    public func hold(_ id: String, _ on: Bool, _ why: Hold = .typing) {
        guard let i = waiting.firstIndex(where: { $0.view.id == id }), waiting[i].held.contains(why) != on else { return }
        if on { waiting[i].held.insert(why) } else { waiting[i].held.remove(why) }
        waiting[i].timer?.cancel()
        waiting[i].timer = waiting[i].held.isEmpty ? timer(id) : nil
    }

    /// The click. False (and the request stays) for a choice a request of that kind cannot be answered with.
    @discardableResult
    public func answer(_ id: String, _ choice: ClaudeChoice) -> Bool {
        guard let item = waiting.first(where: { $0.view.id == id }) else { return false }
        if choice == .pass {
            leave(id); reply(item.connection, [:])
            return true
        }
        switch item.view.kind {
        case .permission:
            let decision: [String: Any]
            switch choice {
            case .allow: decision = ["behavior": "allow"]
            case .deny: decision = ["behavior": "deny", "message": "Denied from CatNotch", "interrupt": false]
            case .always:
                guard !item.suggestions.isEmpty else { return false }
                decision = ["behavior": "allow", "updatedPermissions": item.suggestions]
            default: return false
            }
            leave(id)
            reply(item.connection, ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
        case .question(let questions):
            guard case .answers(let given) = choice else { return false }
            // A label or typed text, either way a non empty string; several only on a multi select.
            var chosen: [String: String] = [:]
            for q in questions {
                let picked = (given[q.question] ?? []).map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000)) }
                if picked.isEmpty || picked.contains(where: \.isEmpty) || (!q.multiSelect && picked.count > 1) { return false }
                chosen[q.question] = picked.joined(separator: ", ")
            }
            // Claude needs its own question list back with the answers added.
            let list = questions.map { q -> [String: Any] in
                ["question": q.question, "header": q.header, "multiSelect": q.multiSelect, "options": q.options.map { ["label": $0.label, "description": $0.description] }]
            }
            leave(id)
            reply(item.connection, ["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": ["questions": list, "answers": chosen]]])
        }
        return true
    }

    // MARK: Lifecycle

    /// At launch: starts the server for a saved "on", and points the hook entries at the live port.
    /// Always re-synced: settings.json can hold an older port (another instance moved it), and Claude then fails silently.
    public func start() async {
        guard setting.enabled, !isRunning else { return }
        guard await run() else {
            claudeLogger.error("No free port for the Claude hook server")
            return
        }
        do {
            try ClaudeSettingsFile.edit(settingsFile, add: true, port: port, token: setting.token)
        } catch {
            claudeLogger.error("Could not sync hooks to the server port (code: \((error as NSError).code, privacy: .public))")
        }
    }

    /// Starts the server and writes the hook entries; `.invalid` leaves a settings file that is not JSON alone.
    public func enable() async -> Enabled {
        // Field by field, so the saved sound survives.
        store.update {
            $0.claudeHooks.enabled = true
            if $0.claudeHooks.token.isEmpty { $0.claudeHooks.token = Self.newToken() }
        }
        let running = if isRunning { true } else { await run() }
        guard running else {
            store.update { $0.claudeHooks.enabled = false }
            return .port
        }
        do {
            try ClaudeSettingsFile.edit(settingsFile, add: true, port: port, token: setting.token)
        } catch ClaudeSettingsFile.Failure.invalid {
            return .invalid // the server keeps running, so a snippet pasted in by hand still works
        } catch {
            stop()
            store.update { $0.claudeHooks.enabled = false }
            return .write
        }
        return .ok
    }

    /// Removes our entries and stops. A file that is not JSON holds none of ours to remove.
    @discardableResult
    public func disable() -> Bool {
        var ok = true
        do { try ClaudeSettingsFile.edit(settingsFile, add: false, port: port, token: setting.token) } catch ClaudeSettingsFile.Failure.invalid {} catch { ok = false }
        stop()
        if setting.enabled { store.update { $0.claudeHooks.enabled = false } }
        return ok
    }

    private func run() async -> Bool {
        let got = await listen(from: setting.port)
        guard got != 0 else { return false }
        port = got
        startScanning()
        if got != setting.port { store.update { $0.claudeHooks.port = got } }
        return true
    }

    private static func newToken() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
