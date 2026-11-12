# 0042 Tell sessions apart, show activity, animate state

Builds on [0033](0033-native-claude-sessions.md) and [0040](0040-session-finished-alert.md).

Two **Sessions** in one repo look identical (the row shows the folder name), you only see your last message, and the state is a text label.

## Requirements

- **AC-1** Title: the newest `ai-title` entry in the transcript tail, else the first user message cut to 50 characters (read once from the file head, then cached), else the folder name. The newest `ai-title` wins when it changes.
- **AC-2** Row: title bold, folder dim after it. Two lines high: line 1 as above, line 2 the subtitle.
- **AC-3** Subtitle: while working, the live tool and its input from `PreToolUse` (`Bash: <command>`, `Read: <path>`, MCP tools shortened). Otherwise "You: …". Cleared on `Stop`, `PostToolUse` and interrupt. The assistant's last text is not shown.
- **AC-4** The finished banner (spec 0040 AC-1) reads "<title> finished", not "<project> finished".
- **AC-5** State glyph replaces the text label: working = `· ✢ ✳ ∗ ✻ ✽` cycle in the accent colour; compacting = a different loop; waiting = slow amber pulse; done = checkmark pops in once; idle = static dim dot. The label stays as `.help` and `.accessibilityLabel`.
- **AC-6** Reduce Motion shows a static glyph per state. One shared `TimelineView` for the page, paused unless the Claude page is open. The generic glyph is used, not the cat characters.

## Design

- `ClaudeSession` gains `title` and `activity`. Core holds the title pick and the tool-input formatter; `ClaudeViews` draws.
- `NotchLayout.claudeRow` goes 30 → about 40. `claudeRowsMax` stays 6, so the page is about 60pt taller at the cap.
- No `summary` entries exist in current transcripts; `ai-title` repeats through the file, so the tail read finds the latest.

## Out of scope (separate changes)

- **Token count:** incremental read from a saved byte offset per session, de-duplicated by `message.id` (about 78% of assistant messages span several lines), keeping the highest usage per id. Total is input + output + cache creation; cache reads excluded. Shown as `12.3k`, dim, monospaced.
- **Exact window focus:** deferred. If wanted, Terminal.app and iTerm2 by TTY via AppleScript, falling back to today's app activation. No yabai or tmux.

## Tests

`CatNotchCoreTests`: title picks newest `ai-title`, falls back to first message then folder; tool input formatting per tool; activity cleared on `Stop`, `PostToolUse`, interrupt.
