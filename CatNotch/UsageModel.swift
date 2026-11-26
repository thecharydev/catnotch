import Foundation
import Observation
import OSLog
import CatNotchCore

/// The AI usage limits for every display's Notch. One reader and one answer, shared; the logins are only read after the
/// user has said yes (see `consented`), and only while the AI usage view is showing.
@MainActor @Observable
final class UsageModel {
    /// Nil until the first reading; empty when neither tool is signed in.
    private(set) var providers: [ProviderLimits]?
    private var data: StoreData
    private let store: CatNotchStore
    private let reader: LimitsReader
    /// True while a check is running, whoever asked (the Notch opening, the poll, a reload), so the reload arrow can turn.
    private(set) var refreshing = false
    /// A reload asked for while a check was running: runs once that one is done instead of being dropped.
    private var reloadQueued = false
    private let log = Logger(subsystem: "com.thecharydev.catnotch", category: "usage")

    init(store: CatNotchStore) {
        self.store = store
        data = store.data
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        reader = LimitsReader(cache: support.appending(path: "CatNotch/limits-cache.json"), credentials: Self.credentials, send: { request in
            let (body, response) = try await URLSession.shared.data(for: request)
            return (body, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
        // Lives as long as the app.
        _ = store.observe { [weak self] next in MainActor.assumeIsolated { self?.data = next } }
    }

    /// Whether the AI usage view is on (Settings, or a "Not now" to the question, turns it off).
    var available: Bool { data.showAiUsage && !data.enabledProviders.isEmpty }

    /// "Claude or Codex", for the "no sign-in" card.
    var enabledNames: String { data.enabledProviders.map(\.name).joined(separator: " or ") }

    /// The master switch alone (Settings shows the provider toggles while it is on).
    var masterOn: Bool { data.showAiUsage }

    func isEnabled(_ provider: LimitsProvider) -> Bool { data.isEnabled(provider) }

    func setEnabled(_ provider: LimitsProvider, _ on: Bool) {
        store.update { $0.setEnabled(provider, on) }
        prune()
        Task { await refresh() }
    }

    /// Switching it back on after "Not now" asks the question again.
    func setAvailable(_ on: Bool) {
        store.update {
            $0.showAiUsage = on
            if on && $0.aiConsent == false { $0.aiConsent = nil }
        }
    }

    /// Checks now and every 30 s for as long as the view is showing (the caller's task is cancelled when it goes),
    /// and right after the soonest window resets, so the old percent does not outlive its window.
    func poll() async {
        while !Task.isCancelled {
            await refresh()
            let now = Date()
            let reset = providers?.compactMap { $0.nextReset(after: now) }.min()
            let wait = reset.map { min(30, max(5, $0.timeIntervalSince(now) + 1)) } ?? 30
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    /// `force` (a reload or a retry) skips the reader's gap and back-off, and waits its turn behind a check already running.
    func refresh(force: Bool = false) async {
        guard available, data.aiConsent == true else { return }
        if refreshing {
            if force { reloadQueued = true }
            return
        }
        refreshing = true
        defer { refreshing = false }
        var force = force
        repeat {
            reloadQueued = false
            providers = await reader.read(force: force, providers: data.enabledProviders)
            prune() // a toggle flipped while the read was running
            #if DEBUG
            for p in providers ?? [] { // what the tile is really showing, to tell a slow endpoint from a stale reading (spec 0046)
                log.debug("\(p.name, privacy: .public): \(String(describing: p.reading), privacy: .public), \(p.at.map { Int(Date().timeIntervalSince($0)) } ?? -1)s old, force \(force)")
            }
            #endif
            force = true
        } while reloadQueued
    }

    /// An off provider drops out of the readings at once, even while both are off and no read runs.
    private func prune() {
        let on = Set(store.data.enabledProviders.map(\.name))
        providers = providers?.filter { on.contains($0.name) }
    }

    /// True until the user has answered the question on the view; nothing is read before then.
    var needsConsent: Bool { data.aiConsent == nil }

    /// The answer to the card on the view. "Not now" turns AI usage off; switching it on in Settings asks again.
    func answer(_ allowed: Bool) {
        store.update {
            $0.aiConsent = allowed
            if !allowed { $0.showAiUsage = false }
        }
        if allowed { Task { await refresh() } }
    }

    /// Each tool's login as it keeps it: Claude Code in the Keychain (macOS shows its own prompt the first time) or in
    /// `~/.claude/.credentials.json`, Codex in `~/.codex/auth.json`. Nil means not signed in.
    nonisolated private static func credentials(_ provider: LimitsProvider) async -> Credentials? {
        func file(_ path: String) -> Data? { try? Data(contentsOf: FileManager.default.homeDirectoryForCurrentUser.appending(path: path)) }
        switch provider {
        case .claude:
            let secret = await SystemModel.run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
            return Credentials.claude(from: Data(secret.utf8)) ?? file(".claude/.credentials.json").flatMap(Credentials.claude)
        case .codex:
            return file(".codex/auth.json").flatMap(Credentials.codex)
        }
    }
}
