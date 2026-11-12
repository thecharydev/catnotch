import Foundation

/// The system sounds Claude may play, by name. Never a path: a name outside this list is not a sound.
public enum ClaudeSounds {
    public static let all = ["Pop", "Ping", "Tink", "Glass", "Blow", "Bottle", "Frog", "Funk", "Hero", "Morse", "Purr", "Sosumi", "Submarine", "Basso"]

    public static func url(_ name: String) -> URL? {
        all.contains(name) ? URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff") : nil
    }
}

/// What Settings saved about the Claude hook server: on or off, the secret the hooks send, the port last used, and the
/// sound for a request that needs you (nil: silent). Kept under `claudeHooks` in the store settings.
public struct ClaudeHooksSetting: Equatable, Sendable {
    public var enabled: Bool
    public var token: String
    public var port: Int
    public var sound: String?

    public init(enabled: Bool = false, token: String = "", port: Int = ClaudeSettingsFile.basePort, sound: String? = nil) {
        self.enabled = enabled; self.token = token; self.port = port; self.sound = sound
    }
}

extension StoreData {
    public var claudeHooks: ClaudeHooksSetting {
        get {
            guard case .object(let o)? = settings["claudeHooks"] else { return ClaudeHooksSetting() }
            var s = ClaudeHooksSetting()
            if case .bool(let v)? = o["enabled"] { s.enabled = v }
            if case .string(let v)? = o["token"] { s.token = v }
            if case .number(let v)? = o["port"], v >= 1024, v <= 65535 { s.port = Int(v) }
            if case .string(let v)? = o["sound"], ClaudeSounds.url(v) != nil { s.sound = v }
            return s
        }
        set {
            var o: [String: JSONValue] = ["enabled": .bool(newValue.enabled), "token": .string(newValue.token), "port": .number(Double(newValue.port))]
            if let sound = newValue.sound, ClaudeSounds.url(sound) != nil { o["sound"] = .string(sound) }
            settings["claudeHooks"] = .object(o)
        }
    }
}

/// Our hook entries in Claude Code's `settings.json`, added and removed without touching anything else in the file.
public enum ClaudeSettingsFile {
    public static let basePort = 47821
    /// Longer than the server's own 60 s, so its empty reply always arrives first.
    static let hookTimeout = 65
    /// Events that only report (for the Claude page), so they get an empty reply at once and a short timeout.
    static let reporting = ["SessionEnd", "UserPromptSubmit", "Stop", "PreCompact", "PostCompact", "PostToolUse", "PreToolUse"]
    static let reportTimeout = 5
    /// Events whose entries we write.
    static let events = ["PermissionRequest"] + reporting

    enum Failure: Error { case invalid, write }

    private static func isOurs(_ hook: Any) -> Bool {
        guard let h = hook as? [String: Any], h["type"] as? String == "http", let url = h["url"] as? String else { return false }
        return url.range(of: #"^http://127\.0\.0\.1:\d+/desknotch/"#, options: .regularExpression) != nil
    }

    private static func entry(_ route: String, port: Int, token: String, timeout: Int = hookTimeout) -> [String: Any] {
        ["type": "http", "url": "http://127.0.0.1:\(port)/desknotch/\(route)", "timeout": timeout, "headers": ["Authorization": "Bearer \(token)"]]
    }

    /// Adds our entries (for the live port), or with `add` false removes them. Every other key stays as it was.
    /// Throws `invalid` for a file that is not a JSON object: nothing is written then.
    static func edit(_ file: URL, add: Bool, port: Int, token: String) throws {
        var text = ""
        if let data = try? Data(contentsOf: file) { text = String(decoding: data, as: UTF8.self) } else if !add { return } // nothing to remove from no file
        var root: [String: Any] = [:]
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { throw Failure.invalid }
            root = object
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var wanted: [String: [[String: Any]]] = add ? [
            "PermissionRequest": [["hooks": [entry("permission", port: port, token: token)]]],
        ] : [:]
        if add {
            for event in reporting { wanted[event] = [["hooks": [entry("event", port: port, token: token, timeout: reportTimeout)]]] }
            // The question is held for an answer; every other tool call is only reported (spec 0042).
            wanted["PreToolUse"] = [["matcher": "AskUserQuestion", "hooks": [entry("question", port: port, token: token)]]] + wanted["PreToolUse"]!
        }
        for event in events {
            var kept: [Any] = []
            // Take our hooks out of every group; a group left empty by that goes too.
            for item in hooks[event] as? [Any] ?? [] {
                guard var group = item as? [String: Any], let inside = group["hooks"] as? [Any], inside.contains(where: isOurs) else { kept.append(item); continue }
                let rest = inside.filter { !isOurs($0) }
                if !rest.isEmpty { group["hooks"] = rest; kept.append(group) }
            }
            kept += wanted[event] ?? []
            hooks[event] = kept.isEmpty ? nil : kept
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks

        do {
            var out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            out.append(10)
            if out == Data(text.utf8) { return } // already right (every launch re-syncs): leave the user's file untouched
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            // One backup, the first time: never overwritten after that.
            let backup = URL(fileURLWithPath: file.path + ".deskNotch.bak")
            if !text.isEmpty && !FileManager.default.fileExists(atPath: backup.path) { try Data(text.utf8).write(to: backup) }
            try out.write(to: file, options: .atomic)
        } catch {
            throw Failure.write
        }
    }
}
