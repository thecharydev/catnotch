import AppKit
import Observation
import CatNotchCore

/// Claude Code's questions for every display's Notch: one hook server, one queue, shared. The Notch shows the first
/// request and its buttons answer it.
@MainActor @Observable
final class ClaudeModel {
    /// Waiting for a click, oldest first.
    private(set) var requests: [ClaudeRequest] = []
    /// Every live session, and the ones hidden from the page until they have news.
    private var all: [ClaudeSession] = []
    private var archived: [String: Double]
    /// What the last switch in Settings could not do, in words. Nil when it worked.
    private(set) var problem: String?
    private(set) var enabled: Bool
    /// The sessions the Claude page shows: not the hidden ones. Empty while Claude Code is off.
    var sessions: [ClaudeSession] { ClaudeArchive.visible(all, archived: archived) }
    /// The session that just finished, shown for about 1 second as "<title> finished". Nil: nothing to show.
    private(set) var finished: (id: String, title: String)?
    private var finishedTimer: Task<Void, Never>?
    private var finishedHeld = false
    /// The system sound for a finished session. Nil: silent.
    private(set) var sound: String?
    /// The first request is opened out: a permission's whole command, or a question's card. Hovering opens it;
    /// each new first request starts shut.
    var open = false
    /// The arrow shut the card with the pointer still on it: it stays shut until the pointer leaves and comes back.
    var shut = false
    private let hooks: ClaudeHooks
    private let store: CatNotchStore
    /// A switch-on is still starting, so a second click does not bind a second port.
    private var switching = false
    /// Held while it plays, or it can be cut short.
    private var player: NSSound?

    init(store: CatNotchStore) {
        self.store = store
        enabled = store.data.claudeHooks.enabled
        sound = store.data.claudeHooks.sound
        archived = store.data.claudeArchived
        hooks = ClaudeHooks(store: store, configDir: ClaudeHooks.standardConfigDir(), isTerminalInFront: { source in
            // Claude's own prompt is already in front of you when its terminal is.
            ForegroundState.isTerminalInFront(bundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "", for: source)
        })
        hooks.onChange = { [weak self] next in
            guard let self else { return }
            if next.first?.id != requests.first?.id { open = false; shut = false }
            requests = next
        }
        hooks.sessions.onChange = { [weak self] list in self?.all = list }
        hooks.onTurnEnd = { [weak self] id, title in
            guard let self else { return }
            finished = (id, title)
            startFinishedTimer()
            play(sound)
        }
        // Lives as long as the app.
        _ = store.observe { [weak self] data in
            MainActor.assumeIsolated {
                self?.enabled = data.claudeHooks.enabled
                self?.sound = data.claudeHooks.sound
                self?.archived = data.claudeArchived
            }
        }
    }

    private func startFinishedTimer() {
        finishedTimer?.cancel()
        guard !finishedHeld else { return }
        finishedTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.finished = nil
        }
    }

    /// The pointer on the banner pauses its 1 second timer; letting go restarts it.
    func holdFinished(_ on: Bool) {
        finishedHeld = on
        if on { finishedTimer?.cancel() } else if finished != nil { startFinishedTimer() }
    }

    /// The Claude page was looked at: "Done" rows go back to idle.
    func markSeen() { hooks.sessions.markSeen() }

    /// Settings' sound picker; the pick plays once, so you hear it.
    func setSound(_ name: String?) {
        store.update { $0.claudeHooks.sound = name }
        play(name)
    }

    private func play(_ name: String?) {
        guard let name, let url = ClaudeSounds.url(name) else { return }
        player = NSSound(contentsOf: url, byReference: true)
        player?.play()
    }

    /// At launch: a saved "on" starts the server and points the hook entries at the live port.
    func start() { Task { await hooks.start() } }

    /// Settings' switch. On: starts the server and writes the hooks; off: removes them.
    func setEnabled(_ on: Bool) {
        problem = nil
        guard on else {
            if !hooks.disable() { problem = "Could not remove the hooks from Claude's settings file." }
            return
        }
        guard !switching else { return }
        switching = true
        Task {
            defer { switching = false }
            switch await hooks.enable() {
            case .ok: break
            case .port: problem = "No free port to listen on."
            case .invalid: problem = "Claude's settings file is not valid JSON, so it was left alone. Fix it, then switch this on again."
            case .write: problem = "Could not write Claude's settings file."
            }
        }
    }

    /// The × on a row: hidden until the session has news.
    func archive(_ id: String) {
        archived = ClaudeArchive.archiving(id, in: archived, now: Date())
        store.update { $0.claudeArchived = archived }
    }

    /// The button on a row: brings forward the app that owns the session (VS Code, the terminal).
    func focus(_ id: String) {
        guard let pid = hooks.sessions.pid(of: id) else { return }
        Task.detached {
            let ps = Self.processes()
            guard let path = ClaudeFocus.appPath(pid: pid, ps: ps) else { return }
            await MainActor.run { _ = NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        }
    }

    private nonisolated static func processes() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,ppid=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        guard (try? task.run()) != nil else { return "" }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    func answer(_ id: String, _ choice: ClaudeChoice) { hooks.answer(id, choice) }
    /// The pointer on a request, or an answer being typed, pauses its 60 second timer.
    func hold(_ id: String, _ on: Bool, _ why: ClaudeHooks.Hold) { hooks.hold(id, on, why) }
}
