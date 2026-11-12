import Foundation

/// One plan window of an AI tool, as its provider reports it.
public struct Limit: Codable, Equatable, Sendable {
    /// SESSION, WEEK or MONTH: a window named by its length, so every provider reads the same way.
    public var label: String
    /// Percent of the limit used, 0 to 100.
    public var used: Double
    public var resetsAt: Date?

    public init(label: String, used: Double, resetsAt: Date?) { self.label = label; self.used = used; self.resetsAt = resetsAt }

    /// The window's length, short enough to sit under an orb.
    public var short: String { ["SESSION": "5H", "WEEK": "7D", "MONTH": "30D"][label] ?? label }
    /// The warning colour starts here, judged on the number the orb shows.
    public var isNearlyOut: Bool { used.rounded() >= 80 }
}

public enum LimitsError: String, Codable, Sendable {
    /// The provider turned the login down: the tool needs signing in again.
    case expired
    /// Unreachable, rate limited, or an answer we cannot read.
    case unavailable
}

public enum Reading: Equatable, Sendable {
    case limits([Limit])
    case failed(LimitsError)
}

public struct ProviderLimits: Equatable, Sendable, Identifiable {
    public var name: String
    public var reading: Reading
    public var id: String { name }

    public init(name: String, reading: Reading) { self.name = name; self.reading = reading }
}

/// The sign-in a tool keeps on disk. It only ever goes to that tool's own provider.
public struct Credentials: Equatable, Sendable {
    public var token: String
    public var accountId: String?

    public init(token: String, accountId: String? = nil) { self.token = token; self.accountId = accountId }

    private static func object(_ data: Data, _ key: String) -> [String: Any]? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?[key] as? [String: Any]
    }

    /// Claude Code's login (Keychain item or `.credentials.json`): `{"claudeAiOauth": {"accessToken": …}}`.
    public static func claude(from data: Data) -> Credentials? {
        (object(data, "claudeAiOauth")?["accessToken"] as? String).flatMap { $0.isEmpty ? nil : Credentials(token: $0) }
    }

    /// Codex's `auth.json`: `{"tokens": {"access_token": …, "account_id": …}}`.
    public static func codex(from data: Data) -> Credentials? {
        guard let tokens = object(data, "tokens"), let token = tokens["access_token"] as? String, !token.isEmpty else { return nil }
        return Credentials(token: token, accountId: tokens["account_id"] as? String)
    }
}

/// The tools whose limits are shown, each with its endpoint and its answer's shape.
public enum LimitsProvider: String, CaseIterable, Sendable {
    case claude = "Claude", codex = "Codex"

    public var name: String { rawValue }

    public func request(_ credentials: Credentials) -> URLRequest {
        var request = URLRequest(url: URL(string: self == .claude ? "https://api.anthropic.com/api/oauth/usage" : "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        switch self {
        case .claude:
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        case .codex:
            request.setValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
            if let id = credentials.accountId { request.setValue(id, forHTTPHeaderField: "chatgpt-account-id") }
        }
        return request
    }

    /// The limits in a provider's answer, or nil when it holds none we can read.
    public func parse(_ data: Data) -> [Limit]? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func percent(_ value: Any?) -> Double { min(100, max(0, (value as? NSNumber)?.doubleValue ?? 0)) }
        let limits: [Limit]
        switch self {
        case .claude:
            limits = [("five_hour", "SESSION"), ("seven_day", "WEEK")].compactMap { key, label in
                guard let window = body[key] as? [String: Any] else { return nil }
                return Limit(label: label, used: percent(window["utilization"]), resetsAt: (window["resets_at"] as? String).flatMap(Self.date))
            }
        case .codex:
            // Plans differ: Go has one 30 day window, Plus and Pro a 5 hour and a weekly one.
            let rate = body["rate_limit"] as? [String: Any]
            limits = ["primary_window", "secondary_window"].compactMap { key in
                guard let window = rate?[key] as? [String: Any] else { return nil }
                let seconds = (window["limit_window_seconds"] as? NSNumber)?.doubleValue ?? 0
                return Limit(label: seconds <= 86_400 ? "SESSION" : seconds <= 7 * 86_400 ? "WEEK" : "MONTH",
                             used: percent(window["used_percent"]),
                             resetsAt: (window["reset_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) })
            }
        }
        return limits.isEmpty ? nil : limits
    }

    /// ISO 8601 with or without fractional seconds ("2025-11-05T12:00:00.123456+00:00").
    static func date(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

/// When a limit refills, in the words the orb uses.
public enum ResetText {
    /// "14m", "2h 14m", "26d 1h". Already past is "0m".
    public static func full(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours)h \(minutes % 60)m" : "\(hours / 24)d \(hours % 24)h"
    }

    /// Just the leading unit: "14m", "2h", "26d".
    public static func short(_ date: Date, now: Date) -> String { String(full(date, now: now).split(separator: " ")[0]) }
}

extension StoreData {
    /// Whether the AI usage view is on. Unset is on; asking for the login happens when the view is first opened.
    public var showAiUsage: Bool {
        get { if case .bool(let on)? = settings["showAiUsage"] { on } else { true } }
        set { settings["showAiUsage"] = .bool(newValue) }
    }

    /// The answer to "may CatNotch read the Claude Code and Codex logins?": nil is not asked yet.
    public var aiConsent: Bool? {
        get { if case .bool(let yes)? = settings["aiConsent"] { yes } else { nil } }
        set { settings["aiConsent"] = newValue.map(JSONValue.bool) }
    }
}

/// Reads every provider's limits and remembers the last good reading of each.
///
/// - A failed check shows the last good reading instead (an expired login does not: see spec 0025).
/// - Checks closer than 15 s reuse it outright, and a provider that answered "unavailable" is left alone for five
///   minutes: the endpoints rate limit, and Claude Code polls the same one.
/// - Readings are also kept in `cache`, so a relaunch shows numbers while the endpoint is rate limiting.
public actor LimitsReader {
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, Int)

    static let minGap: TimeInterval = 15
    static let backoff: TimeInterval = 5 * 60

    private struct Entry: Codable { var at: Date; var limits: [Limit] }

    private let credentials: @Sendable (LimitsProvider) async -> Credentials?
    private let send: Send
    private let now: @Sendable () -> Date
    private let cache: URL?
    private var lastGood: [String: Entry]
    private var blockedUntil: [String: Date] = [:]

    /// `credentials` is nil for a tool that is not signed in; `send` returns the body and the HTTP status.
    public init(cache: URL?, credentials: @escaping @Sendable (LimitsProvider) async -> Credentials?, send: @escaping Send, now: @escaping @Sendable () -> Date = { Date() }) {
        self.cache = cache
        self.credentials = credentials
        self.send = send
        self.now = now
        lastGood = cache.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    /// The readings of the tools that are signed in. `force` (a retry) skips the back-off.
    public func read(force: Bool = false) async -> [ProviderLimits] {
        let providers = LimitsProvider.allCases
        var results = [Reading?](repeating: nil, count: providers.count)
        await withTaskGroup(of: (Int, Reading?).self) { group in
            for (i, provider) in providers.enumerated() { group.addTask { (i, await self.read(provider, force: force)) } }
            for await (i, reading) in group { results[i] = reading }
        }
        return zip(providers, results).compactMap { provider, reading in reading.map { ProviderLimits(name: provider.name, reading: $0) } }
    }

    private func read(_ provider: LimitsProvider, force: Bool) async -> Reading? {
        let name = provider.name
        let previous = lastGood[name].map { Reading.limits($0.limits) }
        if let entry = lastGood[name], now().timeIntervalSince(entry.at) < Self.minGap { return previous }
        if !force, let until = blockedUntil[name], until > now() { return previous ?? .failed(.unavailable) }
        guard let credentials = await credentials(provider) else { return nil } // not signed in: no card

        let reading = await fetch(provider, credentials)
        switch reading {
        case .limits(let limits):
            lastGood[name] = Entry(at: now(), limits: limits)
            blockedUntil[name] = nil
            save()
            return reading
        case .failed(.unavailable):
            blockedUntil[name] = now().addingTimeInterval(Self.backoff)
            return previous ?? reading
        case .failed(.expired):
            return reading
        }
    }

    private func fetch(_ provider: LimitsProvider, _ credentials: Credentials) async -> Reading {
        do {
            let (data, status) = try await send(provider.request(credentials))
            if status == 401 || status == 403 { return .failed(.expired) }
            guard (200..<300).contains(status), let limits = provider.parse(data) else { return .failed(.unavailable) }
            return .limits(limits)
        } catch {
            return .failed(.unavailable)
        }
    }

    private func save() {
        guard let cache, let data = try? JSONEncoder().encode(lastGood) else { return }
        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cache, options: .atomic)
    }
}
