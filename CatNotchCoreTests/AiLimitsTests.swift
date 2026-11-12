import Foundation
import Testing
@testable import CatNotchCore

// MARK: fixtures (shaped like the providers' answers)

private let claudeBody = Data(#"""
{"five_hour":{"utilization":42.5,"resets_at":"2025-11-05T12:00:00.123456+00:00"},
 "seven_day":{"utilization":120,"resets_at":"2025-11-10T00:00:00+00:00"},
 "seven_day_opus":null}
"""#.utf8)

private let codexPlusBody = Data(#"""
{"plan_type":"plus","rate_limit":{
 "primary_window":{"limit_window_seconds":18000,"used_percent":10,"reset_at":1762000000},
 "secondary_window":{"limit_window_seconds":604800,"used_percent":55.5,"reset_at":1762500000}}}
"""#.utf8)

private let codexGoBody = Data(#"""
{"rate_limit":{"primary_window":{"limit_window_seconds":2592000,"used_percent":7,"reset_at":1764000000},"secondary_window":null}}
"""#.utf8)

private let claudeLogin = Data(#"{"claudeAiOauth":{"accessToken":"sk-claude","refreshToken":"r"}}"#.utf8)
private let codexLogin = Data(#"{"tokens":{"access_token":"tok-codex","account_id":"acct-1"}}"#.utf8)

// MARK: parsing

@Test func claudeReadsSessionAndWeek() throws {
    let limits = try #require(LimitsProvider.claude.parse(claudeBody))
    #expect(limits.map(\.label) == ["SESSION", "WEEK"])
    #expect(limits[0].used == 42.5)
    #expect(limits[1].used == 100) // clamped
    // Six fractional digits and a +00:00 offset still make the right instant.
    #expect(abs(limits[0].resetsAt!.timeIntervalSince1970 - 1_762_344_000.123) < 0.01)
    #expect(limits[1].resetsAt == Date(timeIntervalSince1970: 1_762_732_800))
}

@Test func codexNamesWindowsByLength() throws {
    let plus = try #require(LimitsProvider.codex.parse(codexPlusBody))
    #expect(plus.map(\.label) == ["SESSION", "WEEK"])
    #expect(plus.map(\.used) == [10, 55.5])
    #expect(plus[0].resetsAt == Date(timeIntervalSince1970: 1_762_000_000))
    #expect(try #require(LimitsProvider.codex.parse(codexGoBody)).map(\.label) == ["MONTH"]) // one 30 day window
}

@Test(arguments: LimitsProvider.allCases, ["", "not json", "[]", "{}", #"{"rate_limit":{}}"#, #"{"five_hour":null}"#])
func answersWithNoLimitsAreUnreadable(provider: LimitsProvider, body: String) {
    #expect(provider.parse(Data(body.utf8)) == nil)
}

@Test func limitShortNamesAndWarning() {
    #expect(["SESSION", "WEEK", "MONTH", "X"].map { Limit(label: $0, used: 0, resetsAt: nil).short } == ["5H", "7D", "30D", "X"])
    #expect(!Limit(label: "WEEK", used: 79.4, resetsAt: nil).isNearlyOut)
    #expect(Limit(label: "WEEK", used: 79.5, resetsAt: nil).isNearlyOut) // the orb shows 80
}

// MARK: logins and requests

@Test func readsEachToolsLogin() {
    #expect(Credentials.claude(from: claudeLogin) == Credentials(token: "sk-claude"))
    #expect(Credentials.codex(from: codexLogin) == Credentials(token: "tok-codex", accountId: "acct-1"))
}

@Test(arguments: ["", "nope", "{}", #"{"claudeAiOauth":{"accessToken":""}}"#, #"{"tokens":{"access_token":""}}"#, #"{"tokens":{}}"#])
func aLoginWithoutATokenIsNotSignedIn(body: String) {
    #expect(Credentials.claude(from: Data(body.utf8)) == nil)
    #expect(Credentials.codex(from: Data(body.utf8)) == nil)
}

@Test func requestsCarryTheLoginToTheirOwnProvider() {
    let claude = LimitsProvider.claude.request(Credentials(token: "T"))
    #expect(claude.url?.host == "api.anthropic.com")
    #expect(claude.value(forHTTPHeaderField: "Authorization") == "Bearer T")
    #expect(claude.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    let codex = LimitsProvider.codex.request(Credentials(token: "T", accountId: "A"))
    #expect(codex.url?.host == "chatgpt.com")
    #expect(codex.value(forHTTPHeaderField: "Authorization") == "Bearer T")
    #expect(codex.value(forHTTPHeaderField: "chatgpt-account-id") == "A")
    #expect(LimitsProvider.codex.request(Credentials(token: "T")).value(forHTTPHeaderField: "chatgpt-account-id") == nil)
}

// MARK: reset text

@Test func resetTextReadsLikeTheOrb() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func text(_ seconds: Double) -> String { ResetText.full(now.addingTimeInterval(seconds), now: now) }
    #expect(text(14 * 60) == "14m")
    #expect(text(2 * 3600 + 14 * 60) == "2h 14m")
    #expect(text(26 * 86400 + 3600) == "26d 1h")
    #expect(text(-500) == "0m")
    #expect(ResetText.short(now.addingTimeInterval(2 * 3600 + 14 * 60), now: now) == "2h")
    #expect(ResetText.short(now.addingTimeInterval(14 * 60), now: now) == "14m")
}

// MARK: settings

@Test func aiUsageSettings() {
    var data = StoreData()
    #expect(data.showAiUsage && data.aiConsent == nil)
    data.aiConsent = true
    data.showAiUsage = false
    #expect(data.aiConsent == true && !data.showAiUsage)
    data.aiConsent = nil
    #expect(data.settings["aiConsent"] == nil) // asked again, not "false"
}

// MARK: the reader

private final class Clock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

/// Plays one provider's answers in turn (the last repeats) and counts the calls.
private actor Server {
    private var script: [String: [Result<(Data, Int), URLError>]] = [:]
    private(set) var calls: [String: Int] = [:]

    func say(_ host: String, _ replies: Result<(Data, Int), URLError>...) { script[host] = replies }

    func handle(_ request: URLRequest) throws -> (Data, Int) {
        let host = request.url!.host!
        calls[host, default: 0] += 1
        var replies = script[host] ?? [.failure(URLError(.notConnectedToInternet))]
        let next = replies.count > 1 ? replies.removeFirst() : replies[0]
        script[host] = replies
        return try next.get()
    }
}

private func ok(_ body: Data) -> Result<(Data, Int), URLError> { .success((body, 200)) }
private func status(_ code: Int) -> Result<(Data, Int), URLError> { .success((Data(), code)) }

private let claudeHost = "api.anthropic.com", codexHost = "chatgpt.com"

private func makeReader(_ server: Server, _ clock: Clock, cache: URL? = nil, signedIn: Set<LimitsProvider> = [.claude, .codex]) -> LimitsReader {
    LimitsReader(cache: cache,
                 credentials: { signedIn.contains($0) ? Credentials(token: "t") : nil },
                 send: { try await server.handle($0) },
                 now: { clock.date })
}

private func claudeOnly(_ readings: [ProviderLimits]) -> Reading? { readings.first { $0.name == "Claude" }?.reading }

@Test func readerShowsEachSignedInProvider() async {
    let server = Server(), clock = Clock()
    await server.say(claudeHost, ok(claudeBody))
    await server.say(codexHost, ok(codexPlusBody))
    let readings = await makeReader(server, clock).read()
    #expect(readings.map(\.name) == ["Claude", "Codex"])
    guard case .limits(let claude) = readings[0].reading, case .limits(let codex) = readings[1].reading else { Issue.record("expected limits"); return }
    #expect(claude.map(\.used) == [42.5, 100] && codex.map(\.used) == [10, 55.5])
}

@Test func aToolThatIsNotSignedInHasNoCard() async {
    let server = Server(), clock = Clock()
    await server.say(claudeHost, ok(claudeBody))
    let readings = await makeReader(server, clock, signedIn: [.claude]).read()
    #expect(readings.map(\.name) == ["Claude"])
    #expect(await server.calls[codexHost] == nil) // nothing was sent for it
}

@Test(arguments: [401, 403])
func aRejectedLoginIsExpired(code: Int) async {
    let server = Server()
    await server.say(claudeHost, status(code))
    #expect(claudeOnly(await makeReader(server, Clock(), signedIn: [.claude]).read()) == .failed(.expired))
}

@Test(arguments: [status(429), status(500), .failure(URLError(.timedOut)), ok(Data("garbage".utf8))])
func aFailedCheckWithNothingBeforeIsUnavailable(reply: Result<(Data, Int), URLError>) async {
    let server = Server()
    await server.say(claudeHost, reply)
    #expect(claudeOnly(await makeReader(server, Clock(), signedIn: [.claude]).read()) == .failed(.unavailable))
}

@Test func aFailedCheckReusesTheLastGoodReading() async {
    let server = Server(), clock = Clock()
    await server.say(claudeHost, ok(claudeBody), status(429))
    let reader = makeReader(server, clock, signedIn: [.claude])
    let good = claudeOnly(await reader.read())
    clock.advance(120)
    #expect(claudeOnly(await reader.read()) == good) // the 429 shows the earlier numbers
    #expect(await server.calls[claudeHost] == 2)
}

@Test func anExpiredLoginIsNotHiddenByAnOldReading() async {
    let server = Server(), clock = Clock()
    await server.say(claudeHost, ok(claudeBody), status(401))
    let reader = makeReader(server, clock, signedIn: [.claude])
    _ = await reader.read()
    clock.advance(120)
    #expect(claudeOnly(await reader.read()) == .failed(.expired))
}

@Test func checksCloserThanFifteenSecondsReuseTheReading() async {
    let server = Server(), clock = Clock()
    await server.say(claudeHost, ok(claudeBody))
    let reader = makeReader(server, clock, signedIn: [.claude])
    _ = await reader.read()
    clock.advance(14)
    _ = await reader.read()
    _ = await reader.read(force: true) // even a retry: the reading is that fresh
    #expect(await server.calls[claudeHost] == 1)
    clock.advance(2)
    _ = await reader.read()
    #expect(await server.calls[claudeHost] == 2)
}

@Test func anUnavailableProviderIsLeftAloneForFiveMinutesUnlessRetried() async {
    let server = Server(), clock = Clock()
    await server.say(claudeHost, status(429))
    let reader = makeReader(server, clock, signedIn: [.claude])
    _ = await reader.read()
    clock.advance(240)
    #expect(claudeOnly(await reader.read()) == .failed(.unavailable))
    #expect(await server.calls[claudeHost] == 1) // backed off
    _ = await reader.read(force: true)
    #expect(await server.calls[claudeHost] == 2) // retry skips it
    clock.advance(301)
    _ = await reader.read()
    #expect(await server.calls[claudeHost] == 3) // and it ends by itself
}

@Test func lastGoodReadingsSurviveARelaunch() async throws {
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("catnotch-\(UUID().uuidString)/limits-cache.json")
    defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
    let clock = Clock()
    let first = Server()
    await first.say(claudeHost, ok(claudeBody))
    let good = claudeOnly(await makeReader(first, clock, cache: cache, signedIn: [.claude]).read())
    #expect(good != nil)

    clock.advance(3600)
    let second = Server() // after a relaunch the endpoint is rate limiting
    await second.say(claudeHost, status(429))
    #expect(claudeOnly(await makeReader(second, clock, cache: cache, signedIn: [.claude]).read()) == good)
}
