import Foundation
import Observation
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
    private var refreshing = false

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
    var available: Bool { data.showAiUsage }

    /// Switching it back on after "Not now" asks the question again.
    func setAvailable(_ on: Bool) {
        store.update {
            $0.showAiUsage = on
            if on && $0.aiConsent == false { $0.aiConsent = nil }
        }
    }

    /// Checks now and every 30 s for as long as the view is showing (the caller's task is cancelled when it goes).
    func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    /// `force` (a retry) skips the reader's back-off.
    func refresh(force: Bool = false) async {
        guard available, !refreshing else { return }
        guard data.aiConsent == true else { return }
        refreshing = true
        defer { refreshing = false }
        providers = await reader.read(force: force)
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
