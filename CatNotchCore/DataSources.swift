/// Plain words on where a reading comes from and where it goes, shown next to the question that asks for it
/// (an info icon opens `lines`) and in Settings. One place, so the words and the code that does the reading are
/// changed together.
public struct DataSource: Equatable, Sendable {
    /// The icon's tooltip and the first line.
    public let summary: String
    /// One fact per line: what is read, from where, what is sent, and what is never done.
    public let lines: [String]

    public static let aiUsage = DataSource(
        summary: "Reads your Claude Code and Codex sign-ins on this Mac and sends them only to Anthropic or OpenAI.",
        lines: [
            "Claude Code: the sign-in it keeps in your Keychain (item \"Claude Code-credentials\", macOS may ask once), else ~/.claude/.credentials.json.",
            "Codex: ~/.codex/auth.json.",
            "Each token goes only to its own company (api.anthropic.com or chatgpt.com) to ask for your plan limits, about every 30 seconds while Home is open.",
            "CatNotch never refreshes or keeps a token. It keeps only the last numbers, in limits-cache.json.",
        ])

    public static let claude = DataSource(
        summary: "Claude Code calls CatNotch on this Mac when it needs your answer. Nothing leaves the Mac.",
        lines: [
            "On, CatNotch adds two hooks (one for permission requests, one for Claude's questions) to settings.json in Claude's config folder (~/.claude unless CLAUDE_CONFIG_DIR is set), and keeps a backup of the file the first time.",
            "Claude Code posts the tool and its command, or the question, to 127.0.0.1 only, with a secret token that only CatNotch and that file hold.",
            "Allow, Deny or an answer goes back as the hook's reply. After 60 seconds, or if CatNotch is closed, Claude shows its own prompt.",
            "Off, the two hooks are removed and everything else in the file stays.",
        ])

    public static let calendar = DataSource(
        summary: "Reads the events in your Mac's Calendar app. They stay on your Mac and nothing is changed.",
        lines: ["macOS asks first. Allowed, CatNotch reads events through Apple's EventKit, the same way the Calendar app does."])

    public static let reminders = DataSource(
        summary: "Reads the reminders in your Mac's Reminders app. They stay on your Mac and nothing is changed.",
        lines: ["macOS asks first. Allowed, CatNotch reads reminders through Apple's EventKit, the same way the Reminders app does."])
}
