import Darwin
import Foundation
import Testing
@testable import CatNotchCore

// The hook server, driven the way Claude Code drives it: raw HTTP on loopback. Ported from main/ipc/claude.test.ts.
// Every test gets a temp Claude config folder and a temp store, never the real ~/.claude.

private let token = "test-token"
/// One parent for every suite here: each binds loopback ports, and suites run in parallel unless nested under a serialized one.
@MainActor @Suite(.serialized) enum ClaudeHookServer {}

private let reportingEvents = ["SessionEnd", "UserPromptSubmit", "Stop", "PreCompact", "PostCompact", "PostToolUse"]

/// One test's world.
@MainActor private final class Rig {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store: CatNotchStore
    var hooks: ClaudeHooks!
    var inFront = false
    var asked: [ClaudeSource] = []
    var blockers: [Int32] = []
    private(set) var port = 0

    var claudeDir: URL { root.appendingPathComponent("claude") }
    var settingsFile: URL { claudeDir.appendingPathComponent("settings.json") }

    init(enabled: Bool = true, saved: Int? = nil, fallThrough: TimeInterval = 60) throws {
        let dir = root.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = CatNotchStore(directory: root.appendingPathComponent("CatNotch"), legacyDirectory: root.appendingPathComponent("DeskNotch"))
        let first = saved ?? Rig.freePort()
        store.update { $0.claudeHooks = ClaudeHooksSetting(enabled: enabled, token: token, port: first) }
        hooks = ClaudeHooks(store: store, configDir: dir, isTerminalInFront: { [unowned self] source in
            asked.append(source)
            return inFront
        }, fallThrough: fallThrough)
    }

    /// Starts the way the app does at launch, once the saved "on" is read.
    func launch() async {
        await hooks.start()
        port = hooks.port
    }

    func finish() {
        hooks.disable()
        blockers.forEach { close($0) }
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ text: String) { try! text.write(to: settingsFile, atomically: true, encoding: .utf8) }
    func write(_ value: Any) { try! JSONSerialization.data(withJSONObject: value).write(to: settingsFile) }
    func readText() -> String { (try? String(contentsOf: settingsFile, encoding: .utf8)) ?? "" }
    func read() -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(readText().utf8))) as? [String: Any] ?? [:] }

    /// Holds a port, the way another program would.
    func occupy(_ port: Int) {
        blockers.append(Rig.listenSocket(port))
    }

    static func listenSocket(_ port: Int) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(fd, 8)
        return fd
    }

    static func freePort() -> Int {
        let fd = listenSocket(0)
        var addr = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        close(fd)
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

/// Our hook entries in a settings object, flattened per event.
private func ours(_ root: [String: Any]) -> [String: [[String: Any]]] {
    let hooks = root["hooks"] as? [String: Any] ?? [:]
    var out: [String: [[String: Any]]] = [:]
    for event in ["PermissionRequest", "PreToolUse"] + reportingEvents {
        for group in hooks[event] as? [[String: Any]] ?? [] {
            for hook in group["hooks"] as? [[String: Any]] ?? [] where (hook["url"] as? String ?? "").hasPrefix("http://127.0.0.1:") && (hook["url"] as? String ?? "").contains("/desknotch/") {
                var entry = hook
                entry["matcher"] = group["matcher"]
                out[event, default: []].append(entry)
            }
        }
    }
    return out
}

private func route(_ entry: [String: Any]) -> String { (entry["url"] as! String).components(separatedBy: "/desknotch/")[1] }

private var foreign: [String: Any] { [
    "permissions": ["allow": ["Bash(ls)"]],
    "hooks": [
        "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "echo hi"]]]],
        "PermissionRequest": [["hooks": [["type": "http", "url": "http://example.com/hook", "timeout": 5]]]],
        "Notification": [["hooks": [["type": "command", "command": "echo n"]]]],
    ],
] }

private func same(_ a: Any, _ b: Any) -> Bool { NSDictionary(dictionary: a as! [String: Any]).isEqual(to: b as! [String: Any]) }

// MARK: hook sync

extension ClaudeHookServer {
@MainActor @Suite struct HookSync {
    @Test func staleEntriesMoveToTheLivePortAndForeignHooksStay() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        let other = Rig.freePort()
        let stale: (String, Int) -> [String: Any] = { route, timeout in
            ["type": "http", "url": "http://127.0.0.1:\(other)/desknotch/\(route)", "timeout": timeout, "headers": ["Authorization": "Bearer old"]]
        }
        let keep: [String: Any] = ["type": "command", "command": "echo keep"]
        rig.write(["hooks": [
            "PermissionRequest": [["hooks": [stale("permission", 65), keep]]],
            "PreToolUse": [["matcher": "AskUserQuestion", "hooks": [stale("question", 65)]]],
            "SessionEnd": [["hooks": [stale("event", 5)]]],
            "Stop": [["hooks": [stale("event", 5)]]],
        ]])
        await rig.launch()
        #expect(rig.port == rig.store.data.claudeHooks.port)
        let root = rig.read()
        let found = ours(root)
        for event in ["PermissionRequest", "PreToolUse"] + reportingEvents { // the reporting ones too, including those an older version never had
            #expect(found[event]?.count == (event == "PreToolUse" ? 2 : 1)) // the question, and the report of every tool call
            #expect((found[event]![0]["url"] as! String).hasPrefix("http://127.0.0.1:\(rig.port)/desknotch/"))
            #expect((found[event]![0]["headers"] as! [String: String])["Authorization"] == "Bearer \(token)")
        }
        #expect(!rig.readText().contains(":\(other)/"))
        let groups = (root["hooks"] as! [String: Any])["PermissionRequest"] as! [[String: Any]]
        #expect(groups.flatMap { $0["hooks"] as! [[String: Any]] }.contains { same($0, keep) })
    }

    @Test func writesTheRightRouteMatcherAndTimeoutAndNeverDuplicates() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        await rig.launch()
        #expect(await rig.hooks.enable() == .ok)
        #expect(await rig.hooks.enable() == .ok)
        let found = ours(rig.read())
        #expect(found["PermissionRequest"]?.count == 1 && found["PreToolUse"]?.count == 2)
        #expect(route(found["PermissionRequest"]![0]) == "permission")
        #expect(route(found["PreToolUse"]![0]) == "question")
        #expect(found["PreToolUse"]![0]["matcher"] as? String == "AskUserQuestion")
        #expect(found["PermissionRequest"]![0]["timeout"] as? Int == 65)
        #expect(found["PreToolUse"]![0]["timeout"] as? Int == 65)
        // Spec 0042: every tool call is reported too (for the row's activity), at once and with no matcher.
        #expect(route(found["PreToolUse"]![1]) == "event" && found["PreToolUse"]![1]["matcher"] == nil && found["PreToolUse"]![1]["timeout"] as? Int == 5)
        for event in reportingEvents { // replied to at once, so a short timeout
            #expect(found[event]?.count == 1)
            #expect(route(found[event]![0]) == "event")
            #expect(found[event]![0]["timeout"] as? Int == 5)
        }
    }

    @Test func aFileAlreadyRightIsNotRewritten() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        await rig.launch()
        let old = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: rig.settingsFile.path)
        #expect(await rig.hooks.enable() == .ok) // the same port and token again
        let after = try FileManager.default.attributesOfItem(atPath: rig.settingsFile.path)[.modificationDate] as? Date
        #expect(after == old)
    }

    @Test func nothingIsWrittenWhileOff() async throws {
        let rig = try Rig(enabled: false)
        defer { rig.finish() }
        await rig.launch()
        #expect(!rig.hooks.isRunning)
        #expect(!FileManager.default.fileExists(atPath: rig.settingsFile.path))
    }
}
}

// MARK: port fallback

extension ClaudeHookServer {
@MainActor @Suite struct PortFallback {
    @Test func movesToTheNextFreePortSavesItAndTheEntriesFollow() async throws {
        let first = Rig.freePort()
        let rig = try Rig(saved: first)
        defer { rig.finish() }
        rig.occupy(first)
        await rig.launch()
        #expect(rig.port > first && rig.port < first + 20)
        #expect(rig.store.data.claudeHooks.port == rig.port)
        let found = ours(rig.read())
        for event in ["PermissionRequest", "PreToolUse"] {
            #expect((found[event]![0]["url"] as! String).contains("127.0.0.1:\(rig.port)/"))
        }
    }
}
}

// MARK: other tools and bad files

extension ClaudeHookServer {
@MainActor @Suite struct OtherToolsAndBadFiles {
    @Test func foreignHooksAndKeysSurviveEnableASecondStartAndDisable() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        rig.write(foreign)
        await rig.launch()
        #expect(await rig.hooks.enable() == .ok)
        // Without our entries the file is the one we were given.
        #expect(rig.hooks.disable())
        #expect(same(rig.read(), foreign))
    }

    @Test func aFileThatIsNotJSONIsNeverWrittenAndEnableSaysInvalid() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        rig.write("{ not json")
        await rig.launch()
        #expect(await rig.hooks.enable() == .invalid)
        #expect(rig.readText() == "{ not json")
        #expect(!FileManager.default.fileExists(atPath: rig.settingsFile.path + ".deskNotch.bak"))
    }

    @Test func theFirstBackupIsWrittenOnceAndNeverOverwritten() async throws {
        let rig = try Rig()
        defer { rig.finish() }
        let first = #"{"model":"one"}"#
        rig.write(first)
        await rig.launch()
        let backup = rig.settingsFile.path + ".deskNotch.bak"
        #expect(try String(contentsOfFile: backup, encoding: .utf8) == first)
        rig.write(["model": "two"])
        _ = await rig.hooks.enable()
        #expect(try String(contentsOfFile: backup, encoding: .utf8) == first)
    }
}
}

// MARK: raw HTTP, the way Claude Code calls

private struct Reply: @unchecked Sendable { var status: Int; var json: Any? }

/// One request on a plain socket, so the method, host and headers are exactly what the test says. Blocks off the main actor.
@MainActor private func call(_ rig: Rig, _ path: String, method: String = "POST", token: String? = token, host: String? = nil, body: Any = [String: Any](), patience: Int32 = 10_000) async -> Reply {
    let port = rig.port
    let payload = (body as? String).map { Data($0.utf8) } ?? (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    // GCD, not a detached task: these block on a socket, and the test holds twenty at once, more than the task pool has threads.
    return await withCheckedContinuation { (done: CheckedContinuation<Reply, Never>) in DispatchQueue.global().async { done.resume(returning: {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var timeout = timeval(tv_sec: Int(patience / 1000), tv_usec: (patience % 1000) * 1000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let connected = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard connected == 0 else { return Reply(status: 0, json: nil) }
        var head = "\(method) \(path) HTTP/1.1\r\nHost: \(host ?? "127.0.0.1:\(port)")\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\n"
        if let token { head += "Authorization: Bearer \(token)\r\n" }
        let request = Data((head + "\r\n").utf8) + payload
        _ = request.withUnsafeBytes { send(fd, $0.baseAddress, request.count, 0) }
        var received = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { break }
            received.append(chunk, count: n)
        }
        let text = String(decoding: received, as: UTF8.self)
        guard let line = text.split(separator: "\r\n").first, let status = Int(line.split(separator: " ")[1]) else { return Reply(status: 0, json: nil) }
        let bodyText = text.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
        return Reply(status: status, json: bodyText.isEmpty ? nil : try? JSONSerialization.jsonObject(with: Data(bodyText.utf8)))
    }()) } }
}

extension Rig {
    /// The first waiting request, once it arrives.
    func waitPending() async -> ClaudeRequest? {
        for _ in 0..<300 {
            if let first = hooks.requests.first { return first }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }
}

private func question() -> [String: Any] {
    ["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion", "session_id": "s1", "cwd": "/work/proj",
     "tool_input": ["questions": [
        ["question": "Which?", "header": "Pick", "multiSelect": false, "options": [["label": "A", "description": "a"], ["label": "B", "description": "b"]]],
        ["question": "Many?", "header": "Pick", "multiSelect": true, "options": [["label": "X", "description": "x"], ["label": "Y", "description": "y"]]],
     ]]]
}
private func permission(_ tool: String = "Bash", _ input: [String: Any] = ["command": "ls -la"]) -> [String: Any] {
    ["hook_event_name": "PermissionRequest", "tool_name": tool, "tool_input": input, "session_id": "s1", "cwd": "/work/proj"]
}
private func isEmpty(_ json: Any?) -> Bool { (json as? [String: Any])?.isEmpty == true }

// MARK: replies

extension ClaudeHookServer {
@MainActor @Suite struct Replies {
    @Test func answersAQuestionWithThePreToolUseAllowShape() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        async let sent = call(rig, "/desknotch/question", body: question())
        let view = try #require(await rig.waitPending())
        guard case .question(let questions) = view.kind else { Issue.record("not a question"); return }
        #expect(questions.map(\.question) == ["Which?", "Many?"] && questions[1].multiSelect)
        #expect(rig.hooks.answer(view.id, .answers(["Which?": ["A"], "Many?": ["X", "Y"]])))
        let reply = await sent
        #expect(reply.status == 200)
        let expected: [String: Any] = ["hookSpecificOutput": [
            "hookEventName": "PreToolUse", "permissionDecision": "allow",
            "updatedInput": ["questions": (question()["tool_input"] as! [String: Any])["questions"]!, "answers": ["Which?": "A", "Many?": "X, Y"]],
        ]]
        #expect(same(reply.json as Any, expected))
        #expect(rig.hooks.requests.isEmpty)
    }

    @Test func refusesSeveralLabelsOnASingleChoiceAndKeepsItQueued() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        async let sent = call(rig, "/desknotch/question", body: question())
        let view = try #require(await rig.waitPending())
        #expect(!rig.hooks.answer(view.id, .answers(["Which?": ["A", "B"], "Many?": ["X"]])))
        #expect(!rig.hooks.answer(view.id, .answers(["Which?": ["A"]]))) // a question left unanswered
        #expect(rig.hooks.requests.count == 1)
        #expect(rig.hooks.answer(view.id, .pass))
        #expect(isEmpty(await sent.json))
    }

    @Test func repliesAllowAndDenyToAPermissionRequest() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        for choice in [ClaudeChoice.allow, .deny] {
            async let sent = call(rig, "/desknotch/permission", body: permission())
            let view = try #require(await rig.waitPending())
            #expect(view.kind == .permission(tool: "Bash", text: "ls -la") && view.project == "proj")
            #expect(rig.hooks.answer(view.id, choice))
            let decision: [String: Any] = choice == .allow ? ["behavior": "allow"] : ["behavior": "deny", "message": "Denied from CatNotch", "interrupt": false]
            #expect(same(await sent.json as Any, ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]))
        }
    }

    @Test func repliesAllowWithUpdatedPermissionsForAlwaysAndRefusesItWithoutSuggestions() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        let suggestions: [[String: Any]] = [["type": "addRules", "rules": [["toolName": "Bash", "ruleContent": "ls:*"]], "behavior": "allow", "destination": "localSettings"]]
        async let sent = call(rig, "/desknotch/permission", body: permission().merging(["permission_suggestions": suggestions]) { $1 })
        let view = try #require(await rig.waitPending())
        #expect(view.always)
        #expect(rig.hooks.answer(view.id, .always))
        #expect(same(await sent.json as Any, ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "allow", "updatedPermissions": suggestions]]]))

        async let plain = call(rig, "/desknotch/permission", body: permission())
        let next = try #require(await rig.waitPending())
        #expect(!next.always)
        #expect(!rig.hooks.answer(next.id, .always)) // nothing to keep
        #expect(rig.hooks.requests.count == 1)
        #expect(rig.hooks.answer(next.id, .pass))
        _ = await plain
    }

    @Test func repliesEmptyForPassAndRefusesAnUnknownRequestWithoutDequeuing() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        async let sent = call(rig, "/desknotch/permission", body: permission())
        let view = try #require(await rig.waitPending())
        #expect(!rig.hooks.answer("no-such-id", .allow))
        #expect(!rig.hooks.answer(view.id, .answers(["x": ["y"]]))) // a permission takes allow, deny or pass
        #expect(rig.hooks.requests.count == 1)
        #expect(rig.hooks.answer(view.id, .pass))
        #expect(isEmpty(await sent.json))
    }

    @Test func answersEmptyAtOnceToAskUserQuestionOnThePermissionRouteAndNeverQueuesIt() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        let reply = await call(rig, "/desknotch/permission", body: permission("AskUserQuestion", (question()["tool_input"] as! [String: Any])))
        #expect(isEmpty(reply.json))
        #expect(rig.hooks.requests.isEmpty)
    }

    @Test func aRequestClaudeGaveUpOnLeavesTheQueue() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        // The caller waits 300 ms, then hangs up.
        async let sent = call(rig, "/desknotch/permission", body: permission(), patience: 300)
        _ = try #require(await rig.waitPending())
        _ = await sent
        for _ in 0..<100 where !rig.hooks.requests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(rig.hooks.requests.isEmpty)
    }

    @Test func quittingAnswersEveryWaitingRequestEmpty() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        async let sent = call(rig, "/desknotch/permission", body: permission())
        _ = try #require(await rig.waitPending())
        rig.hooks.disable()
        #expect(isEmpty(await sent.json))
        #expect(rig.hooks.requests.isEmpty)
    }

    @Test func aRequestNobodyAnswersFallsThroughEmpty() async throws {
        let rig = try Rig(fallThrough: 0.2); defer { rig.finish() }
        await rig.launch()
        let reply = await call(rig, "/desknotch/permission", body: permission())
        #expect(isEmpty(reply.json))
        #expect(rig.hooks.requests.isEmpty)
    }

    @Test func holdingARequestPausesTheTimerUntilLetGo() async throws {
        let rig = try Rig(fallThrough: 0.3); defer { rig.finish() }
        await rig.launch()
        async let sent = call(rig, "/desknotch/permission", body: permission())
        let view = try #require(await rig.waitPending())
        rig.hooks.hold(view.id, true)
        try await Task.sleep(for: .milliseconds(600))
        #expect(rig.hooks.requests.count == 1)
        rig.hooks.hold(view.id, false)
        #expect(isEmpty(await sent.json))
        #expect(rig.hooks.requests.isEmpty)
    }
}
}

// MARK: the gate

extension ClaudeHookServer {
@MainActor @Suite struct Gate {
    @Test func refusesAWrongOrMissingTokenABadMethodAnUnknownPathAndAWrongHost() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        #expect(await call(rig, "/desknotch/event", token: "wrong").status == 401)
        #expect(await call(rig, "/desknotch/event", token: nil).status == 401)
        #expect(await call(rig, "/desknotch/event", method: "GET").status == 405)
        #expect(await call(rig, "/desknotch/nope").status == 404)
        #expect(await call(rig, "/desknotch/event", host: "evil.example").status == 403)
        #expect(await call(rig, "/desknotch/event").status == 200)
    }

    @Test func refusesABodyOverOneMegabyteAndAnswersEmptyToOneThatIsNotJSON() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        #expect(await call(rig, "/desknotch/permission", body: ["pad": String(repeating: "x", count: 1_100_000)]).status == 413)
        #expect(await call(rig, "/desknotch/permission", body: "not an object").status == 200) // Claude then shows its own prompt
        #expect(rig.hooks.requests.isEmpty)
    }

    @Test func aTwentyFirstWaitingRequestGoesStraightBack() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        var sends: [Task<Reply, Never>] = []
        for _ in 0..<20 { sends.append(Task { await call(rig, "/desknotch/permission", body: permission()) }) }
        for _ in 0..<500 where rig.hooks.requests.count < 20 { try await Task.sleep(for: .milliseconds(20)) }
        try #require(rig.hooks.requests.count == 20)
        #expect(isEmpty(await call(rig, "/desknotch/permission", body: permission()).json)) // the 21st goes straight back
        #expect(rig.hooks.requests.count == 20)
        rig.hooks.disable()
        for s in sends { _ = await s.value }
    }
}
}

// MARK: the terminal rule

extension ClaudeHookServer {
@MainActor @Suite struct TerminalRule {
    @Test func answersEmptyAtOnceAndQueuesNothingWhenATerminalIsInFront() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        rig.inFront = true
        #expect(isEmpty(await call(rig, "/desknotch/question", body: question()).json))
        #expect(rig.hooks.requests.isEmpty)
    }

    @Test func queuesTheRequestWhenNothingIsInFront() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        async let sent = call(rig, "/desknotch/question", body: question())
        let view = try #require(await rig.waitPending())
        #expect(rig.asked == [.unknown])
        #expect(rig.hooks.answer(view.id, .pass))
        _ = await sent
    }

    @Test(arguments: [("claude-vscode", ClaudeSource.vscode), ("cli", .cli)])
    func asksTheRuleWithTheSourceReadFromTheTranscript(entry: String, source: ClaudeSource) async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        let transcript = rig.claudeDir.appendingPathComponent("projects/t.jsonl")
        try FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"entrypoint\":\"\(entry)\",\"cwd\":\"/work/proj\"}\n".utf8).write(to: transcript)
        var body = question()
        body["transcript_path"] = transcript.path
        async let sent = call(rig, "/desknotch/question", body: body)
        let view = try #require(await rig.waitPending())
        #expect(rig.asked == [source])
        #expect(rig.hooks.answer(view.id, .pass))
        _ = await sent
    }

    @Test func ignoresATranscriptOutsideTheProjectsFolder() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        let elsewhere = rig.root.appendingPathComponent("t.jsonl")
        try Data(#"{"entrypoint":"claude-vscode"}"#.utf8).write(to: elsewhere)
        var body = question()
        body["transcript_path"] = elsewhere.path
        async let sent = call(rig, "/desknotch/question", body: body)
        let view = try #require(await rig.waitPending())
        #expect(rig.asked == [.unknown])
        #expect(rig.hooks.answer(view.id, .pass))
        _ = await sent
    }
}
}

// MARK: sound

extension ClaudeHookServer {
@MainActor @Suite struct Sound {
    @Test func onlyListedNamesBecomeSoundFilesNeverAPath() {
        #expect(ClaudeSounds.url("Pop")?.path == "/System/Library/Sounds/Pop.aiff")
        for bad in ["../../etc/passwd", "/System/Library/Sounds/Pop.aiff", "pop", ""] { #expect(ClaudeSounds.url(bad) == nil) }
    }

    @Test func theSavedPickRoundTripsAndANameOutsideTheListIsIgnored() {
        var data = StoreData()
        #expect(data.claudeHooks.sound == nil)
        data.claudeHooks = ClaudeHooksSetting(enabled: true, token: "t", port: 47821, sound: "Glass")
        #expect(data.claudeHooks.sound == "Glass")
        data.settings["claudeHooks"] = .object(["enabled": .bool(true), "token": .string("t"), "port": .number(47821), "sound": .string("../x")])
        #expect(data.claudeHooks.sound == nil)
        data.claudeHooks.sound = "../x" // refused on the way in as well
        #expect(data.claudeHooks.sound == nil)
    }

    @Test func switchingTheHooksOnAgainKeepsThePick() async throws {
        let rig = try Rig(enabled: false); defer { rig.finish() }
        rig.store.update { $0.claudeHooks.sound = "Glass" }
        #expect(await rig.hooks.enable() == .ok)
        #expect(rig.store.data.claudeHooks.sound == "Glass")
        #expect(rig.store.data.claudeHooks.enabled)
    }
}
}

// MARK: reports

extension ClaudeHookServer {
@MainActor @Suite struct Reports {
    @Test func aReportingEventRepliesAtOnceListsTheSessionAndSignalsATurnEndOnce() async throws {
        let rig = try Rig(); defer { rig.finish() }
        // Claude's own file for the session, so the periodic look keeps it.
        let dir = rig.claudeDir.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["sessionId": "abc", "pid": Int(getpid()), "cwd": "/work/proj"]).write(to: dir.appendingPathComponent("a.json"))
        await rig.launch()
        var ended: [String] = []
        rig.hooks.onTurnEnd = { id, title in ended.append("\(id) \(title)") }
        for name in ["UserPromptSubmit", "Stop", "Stop"] { // the second Stop ends nothing
            let reply = await call(rig, "/desknotch/event", body: ["hook_event_name": name, "session_id": "abc", "cwd": "/work/proj"])
            #expect(reply.status == 200 && isEmpty(reply.json))
        }
        #expect(ended == ["abc proj"])
        #expect(rig.hooks.sessions.list.map(\.project) == ["proj"] && rig.hooks.sessions.list.first?.state == .done)
        rig.hooks.sessions.markSeen()
        #expect(rig.hooks.sessions.list.first?.state == .idle)
        #expect(isEmpty(await call(rig, "/desknotch/event", body: ["hook_event_name": "SomethingElse", "session_id": "zzz"]).json)) // not ours: ignored
        #expect(rig.hooks.sessions.list.count == 1)
    }

    @Test func aFinishedTurnIsSilentWhenItsTerminalIsInFront() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        var ended = 0
        rig.hooks.onTurnEnd = { _, _ in ended += 1 }
        rig.inFront = true
        for name in ["UserPromptSubmit", "Stop"] { _ = await call(rig, "/desknotch/event", body: ["hook_event_name": name, "session_id": "abc"]) }
        #expect(ended == 0)
        rig.inFront = false
        for name in ["UserPromptSubmit", "Stop"] { _ = await call(rig, "/desknotch/event", body: ["hook_event_name": name, "session_id": "abc"]) }
        #expect(ended == 1)
    }

    @Test func aFinishedToolDropsOnlyTheRequestItMatches() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        var q = question(); q["tool_use_id"] = "tu1"
        async let sentQ = call(rig, "/desknotch/question", body: q)
        _ = try #require(await rig.waitPending())
        async let sentP = call(rig, "/desknotch/permission", body: permission())
        for _ in 0..<300 where rig.hooks.requests.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        func done(_ session: String, _ tool: String, _ input: [String: Any], _ useId: String = "x") async {
            _ = await call(rig, "/desknotch/event", body: ["hook_event_name": "PostToolUse", "session_id": session, "tool_name": tool, "tool_input": input, "tool_use_id": useId])
        }
        await done("s1", "Bash", ["command": "pwd"]); await done("s2", "Bash", ["command": "ls -la"]); await done("s1", "AskUserQuestion", [:], "other")
        #expect(rig.hooks.requests.count == 2) // another input, another session, another tool_use_id: nothing dropped
        await done("s1", "Bash", ["command": "ls -la"])
        #expect(rig.hooks.requests.count == 1)
        await done("s1", "AskUserQuestion", [:], "tu1")
        #expect(rig.hooks.requests.isEmpty)
        let (rq, rp) = await (sentQ, sentP)
        #expect(isEmpty(rq.json) && isEmpty(rp.json))
    }

    @Test func aRequestWaitingMakesItsSessionWaitingUntilItIsAnswered() async throws {
        let rig = try Rig(); defer { rig.finish() }
        await rig.launch()
        async let sent = call(rig, "/desknotch/permission", body: permission())
        let view = try #require(await rig.waitPending())
        #expect(rig.hooks.sessions.list.first { $0.id == "s1" }?.state == .waiting)
        #expect(rig.hooks.answer(view.id, .pass))
        _ = await sent
        #expect(rig.hooks.sessions.list.first { $0.id == "s1" }?.state == .working) // seen at the request, and not waiting now
    }
}
}
