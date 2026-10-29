# 0007. Claude session chat: read the conversation and send a message from the notch

**Date**: 2026-10-29
**Status**: Accepted

## Summary

Click a session in the Claude tab and the notch shows that session's conversation (your messages and Claude's replies) with a text box under it. Type a message and send, and Claude answers inside the same session. A Back button returns to the list. Messages go out by running Claude Code in its quiet "print" mode on that session (`claude -p --resume`), because no supported way exists to type into a terminal or VS Code window that is already open. This builds on [0005](0005-claude-section-sessions-and-answers.md) (the session list) and [0002](0002-claude-code-notch-popup/index.md) (the popup for permissions and questions).

## Context

Spec 0005 lists every Claude Code session and its state, and lets you answer a question Claude asked. It cannot show what a session said, and you cannot start a new turn from the notch. You have to find the terminal or VS Code window first.

Facts from the code and from 0005's checks: each session has a transcript file at `<config dir>/projects/<project>/<session_id>.jsonl`, and the main process already knows its path and the session's folder (`main/ipc/claude.ts`, the `Session` record). Hooks from 0002 are written to Claude's own settings, so any Claude process started on this machine, including a quiet one we start, reports to DeskNotch the same way. That means permission popups for a message sent from the notch still arrive on the notch.

This is an ENHANCEMENT of 0005, on the existing Electron, Next.js and TypeScript app, desktop only. The code touched is `main/ipc/claude.ts`, `renderer/components/widgets/ClaudeView.tsx`, `renderer/hooks/useClaude.ts`, `renderer/pages/home.tsx` and the privacy text. Not deciding means the Claude tab stays a status board you have to leave to act on.

One deliberate reversal: 0005's invariant "never sends transcript text to the renderer" no longer holds for the one session you open. The rest of that invariant (nothing stored, nothing logged) stays.

## Requirements

**User stories**:
- As someone running several Claude sessions, I want to click one and read what was said, so that I know where it stands without opening its window.
- As the same person, I want to send a message from the notch and see the reply, so that I can keep a session going without switching windows.
- As a user, I want Claude's permission questions for that message to still reach me on the notch, so that nothing runs unseen.

**Acceptance criteria** (the contract, each independently checkable):
- **AC-1**: Clicking a session row opens a chat view in the Claude tab, replacing the list, with a Back button. Back returns to the list. Clicking never changes any session.
- **AC-2**: The chat shows the last 30 turns of that session, oldest at the top, newest at the bottom, scrolled to the bottom on open. Your messages and Claude's text replies are shown; each tool call is one muted line "Ran <tool name>"; tool results, thinking and side chain (sub agent) turns are not shown. Each turn's text is cut at 4000 characters with a "…" mark.
- **AC-3**: The chat refreshes within 3 seconds of the transcript file changing while it is open, and keeps your scroll place unless you were already at the bottom.
- **AC-4**: A text box and Send sit under the chat. Enter sends. Empty or whitespace only text is not sendable. Text over 4000 characters is cut at 4000.
- **AC-5**: Sending runs `claude -p --resume <session_id>` in that session's folder. The reply appears in the chat when Claude finishes. While it runs, the chat shows "Claude is replying…" and Send is disabled. The run is stopped after 10 minutes and the chat shows "Timed out".
- **AC-6**: Send is disabled with a short reason when the session is Working or Waiting for you ("Claude is busy in its own window"), when the session's folder is unknown or gone, or when the Claude program cannot be found ("Claude was not found on this machine"; a setting to point at it is left for later, see Follow up).
- **AC-7**: A permission or question from the message you sent shows through the existing 0002 popup and answers as before. The chat view does not hide it, and a run waiting on it is not stopped by us.
- **AC-8**: Typing takes keyboard focus only when you click the text box and gives it back on send, Back or click away (same rule as 0005 AC-10).
- **AC-9**: A failed run (non zero exit, no reply) shows one error line in the chat with the first 200 characters of what Claude printed, and Send works again.
- **AC-10**: Transcript text goes to the renderer only for the session you opened, only on your click, and is never stored or logged. The chat feed is refused for a session id that is not in the list, and for a transcript path outside `<config dir>/projects`.
- **AC-11**: The message is passed as one argument, never through a shell, so quotes, `$`, backticks or a leading `-` in it do nothing special. The session id must look like a UUID before it is used.
- **AC-12**: With "Claude Code" switched off, the chat and send routes refuse and the list is empty as in 0005.
- **AC-13**: Works on macOS and Windows and honours `CLAUDE_CONFIG_DIR`.

## Options considered

### Option 1: Resume the session with a quiet run

Run `claude -p --resume <id> -- "<message>"` in the session's folder, then read the new turns from the transcript.

**Pros**:
- Supported by Claude Code, same conversation and same transcript file.
- Works for terminal and VS Code sessions alike.
- Hooks still fire, so 0002 popups cover permissions.

**Cons**:
- The window that has the session open does not update live, and its in memory history will not include turns sent this way until it is resumed.
- Sending while that session is mid turn can clash, so we block it.

### Option 2: Type into the real window

Use macOS accessibility to paste text into the terminal or VS Code window.

**Pros**:
- Fully live, the window shows everything.

**Cons**:
- Fragile (which window, which VS Code panel), needs a new permission, and macOS only.

### Option 3: Only sessions DeskNotch starts

Launch sessions from DeskNotch with a stream protocol for full control.

**Pros**:
- Clean, live, no clash.

**Cons**:
- Your existing sessions stay read only, which misses the point.

## Decision

**Chosen option**: Option 1: Resume the session with a quiet run

The main process reads the opened session's transcript tail for display and sends a message by running Claude Code in print mode on that session.

## Rationale

Option 1 is the only one that works on sessions you already have open without a new permission or an unreliable window hunt. Its costs are honest and small for a notch: you see the reply on the notch and in the transcript, and the other window catches up when you next use it. Blocking Send while the session is Working or Waiting removes the one real clash. Hooks already installed by 0002 make permission handling free: the quiet run asks through the same popup.

Reading the transcript on demand for one session, instead of streaming it, keeps the privacy change as small as possible. Polling the file's modified time every 2 seconds while the chat is open is cheap and needs no file watcher.

## Feature design

**Data model sketch**:
Nothing is stored on disk. In memory only: `running: Set<session_id>` in the main process for sends in flight. The chat view model sent to the renderer is `Turn[]` with `Turn = { role: 'user' | 'assistant' | 'tool'; text: string }` (for `tool`, text is the tool name).

**State transitions**:
- Chat view: list, then open(session), then back to list. A new Waiting request still switches the notch to its popup as in 0002; Back afterwards returns to the list.
- Send: idle, then running (Send disabled, "Claude is replying…"), then done (reply shown, Send enabled) or failed (error line, Send enabled).
- While running, the hooks from the quiet run set the session Working, which also keeps a second send blocked from the renderer side.

**Interface surface** (IPC added in `main/ipc/claude.ts`, no new HTTP route):
| Channel | Direction | Inputs | Output | Key errors |
|---|---|---|---|---|
| `claude:chat` | renderer invoke | `id` (session id) | `{ turns: Turn[], mtime: number, busy: boolean }` | `{ error: 'unknown' }` for a session not in the list or a path outside the projects folder, `{ error: 'off' }` when switched off |
| `claude:send` | renderer invoke | `id`, `text` | `{ ok: true }` at once, the run continues | `{ error: 'busy' }` (Working, Waiting or already running), `{ error: 'folder' }`, `{ error: 'notfound' }` (no Claude program), `{ error: 'off' }`, `{ error: 'unknown' }` |
| `claude:chat-changed` | main to renderer | none | sent when a run starts or ends so the open chat refreshes at once | none |

Run result is read from the transcript, not from the process output, so the chat has one source of truth. Process output (first 200 characters of stderr or stdout on a non zero exit) is used only for the error line.

**Value sourcing** (every shown or sent value and where it comes from):
| Action | Value produced / displayed | Source |
|---|---|---|
| Open chat | Which file to read | the session's `transcript` path already held in main; if empty, built as in 0005 from `<config dir>`, the folder with non letters and digits turned to dashes, and the id |
| Open chat | Allowed location | the real path (symlinks resolved) must start with the real path of `<config dir>/projects` |
| Open chat | Turns | the last 256 KB of the file, split into lines, the first partial line dropped; lines with `type` of `user` or `assistant`, not `isSidechain`, not `isMeta`; text blocks shown, `tool_use` blocks become "Ran <name>", `tool_result`, `thinking` and image blocks skipped; a user line whose content is only tool results is skipped; last 30 kept |
| Open chat | Refresh signal | the file's modified time, polled every 2 seconds by the renderer while the chat is open |
| Open chat | Busy | session state is Working or Waiting, or the id is in `running` |
| Send | Session id | the row you clicked, checked against the UUID pattern and the session list |
| Send | Working folder | the session's `cwd` (hook body or first transcript line, as in 0005); must exist as a directory |
| Send | Program to run | first existing of: `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, `~/.claude/local/claude` on macOS; on Windows `claude.exe` or `claude.cmd` found on `PATH`; if none, ask the user's login shell once (`$SHELL -lc 'command -v claude'`) and cache the path for the app run. A Finder launched app has a short `PATH`, which is why `PATH` alone is not enough |
| Send | Message text | the text box, trimmed, cut at 4000 characters |
| Send | Arguments | fixed array: `-p`, `--resume`, `<id>`, `--permission-mode`, `default`, `--`, `<text>`; run with `execFile` (no shell), `cwd` set, `timeout` 600000 ms |
| Send | Permission handling | the hooks already in Claude's settings (0002); nothing extra is passed |
| Focus for typing | when to take and give back | click in the box takes it (`notch:pinned` true); send, Back or blur gives it back |

**Key invariants**:
- A message is sent only from a click on Send or Enter in that chat's own box. Nothing is sent automatically, from a timer, or from a hook.
- One run per session at a time. A run is never started for a session that is Working or Waiting.
- The permission mode is `default`. We never pass a bypass or accept edits mode, so a quiet run cannot do more than a normal session would allow.
- Transcript text is read per request, held only in the renderer's memory while the chat is open, and dropped on Back. It is never written to disk or to logs.
- The chat feed only opens files under `<config dir>/projects` after resolving symlinks.
- Arguments are an array. No string is ever built into a shell command.

**Security model**: The renderer is our own page, but it is the only caller of the two new channels, and each validates its input in main (UUID pattern, known session, allowed path, length caps). The message is data the user chose to send to their own session. Transcript text can contain secrets that were typed or printed in that session; it is shown on the notch only after a click, which is the new exposure, and `PRIVACY.md` says so. Compliance scope: none; nothing leaves the machine except what Claude Code itself sends to its own service, as it would in a normal run.

**Configuration required**: none. No new setting; the chat is part of the Claude tab and follows the existing "Claude Code" switch.

**Critical test scenarios**:
- Click a session with a long history; the chat opens at the bottom with the last 30 turns, tool calls as "Ran" lines, verifies **AC-1**, **AC-2**.
- Append a line to the transcript by hand; the chat updates within 3 seconds, verifies **AC-3**.
- Send "say hi" to an Idle session; "Claude is replying…" shows, then the reply appears and the transcript file gained the turns, verifies **AC-4**, **AC-5**.
- Send while the session is Working in its terminal; Send is disabled with the reason, verifies **AC-6**.
- Send a message that makes Claude run a command; a permission popup appears, Allow it, the run finishes, verifies **AC-7**.
- Click in the box while another app is in front, type, send; the other app has focus again, verifies **AC-8**.
- Send to a session whose folder was deleted, and with Claude removed from the machine; clear one line errors each, verifies **AC-6**, **AC-9**.
- Message text `"; touch /tmp/x #` and `--help`; nothing runs, they arrive as plain text, verifies **AC-11**.
- Call `claude:chat` with a made up id and with a transcript path pointing at a symlink outside the folder; both refused, verifies **AC-10**.
- Switch "Claude Code" off; the routes refuse, verifies **AC-12**.
- Run on both systems, verifies **AC-13**.

## Build plan

No build approach is recorded for the project, so this uses end to end thin slices (Tracer Bullet): a thread through every layer first, then thicker.

1. Spike, no product code: in a real session folder, run `claude -p --resume <id> -- "say hi"` and confirm (a) it appends to the same `<id>.jsonl` rather than creating a new session id, (b) a VS Code session resumes the same way, (c) the 2.1.x hook events fire from the quiet run so state and popups work, (d) the exit code and output on failure. Record results in Follow up. If (a) fails, add `--fork-session` handling or ship read only chat and say so, satisfies **AC-5**, **AC-7**
2. Thin thread: `claude:chat` returning turns for a known session (tail read, parse, filter, cap), a bare chat view with Back, row click in `ClaudeSessions`, satisfies **AC-1**, **AC-2**, **AC-10**
3. Refresh: renderer polls `claude:chat` every 2 seconds while open, keeps scroll place, drops state on Back, satisfies **AC-3**
4. Send: program lookup with cache, `claude:send` with the `running` set and the busy checks, `execFile` with timeout, `claude:chat-changed`, the text box, Send, "Claude is replying…" and error line, satisfies **AC-4**, **AC-5**, **AC-6**, **AC-9**, **AC-11**
5. Focus: take focus on the box, give it back on send, Back and blur, and make sure a Waiting popup arriving over an open chat still works, satisfies **AC-7**, **AC-8**
6. Guards: the switch check, the symlink safe path check, the UUID check, satisfies **AC-10**, **AC-12**
7. Layout and cross platform: a chat height in `home.tsx` and `ClaudeView.tsx`, Windows program lookup, `CLAUDE_CONFIG_DIR`, satisfies **AC-13**
8. Docs: `PRIVACY.md` (the opened session's text is shown on the notch, not stored), README and `doc/Functionality.md` for the chat and the "other window does not live update" note, and a line in 0005 saying its "never sends transcript text to the renderer" rule is relaxed by this spec, satisfies **AC-10**

## Consequences

**Positive**:
- You can read and continue any session from the notch, with permissions still on the notch.
- No new permission, no new HTTP route, no new setting.

**Negative / tradeoffs**:
- The terminal or VS Code window with that session open does not update live, and its own memory of the conversation will not include turns sent from the notch until it is resumed, so it can answer as if they never happened.
- DeskNotch now shows transcript text, which can include secrets from that session, after a click.
- Finding the Claude program can fail on unusual installs; the error says so and a setting is left for later.
- Each send starts a new Claude process, so a reply has the usual start up delay, and no partial reply is shown while it works.

**Neutral**:
- Messages sent from the notch appear in the session's history and in any usage Claude Code reports, as any prompt would.
- Long replies are shown as plain text, no formatting, and cut at 4000 characters per turn in the chat only.
- Hook changes from 0005 are unaffected.

## Follow-up

- [x] Build task 1 spike, run 2026-10-29 on Claude Code 2.1.x: `claude -p --resume <id>` keeps the same session id and appends to the same `<id>.jsonl` (34 to 47 lines). The quiet run fires `SessionEnd`, so DeskNotch ignores that event while its own send is running. VS Code resume and a permission popup from a quiet run not yet checked by hand.
- [ ] A later spec could stream the reply as it is written (`--output-format stream-json`) and add a "Claude program path" setting.
- [ ] A later spec could add click to focus the session's own window, and live update of that window.
- [ ] After build, add one line to 0005 noting its transcript text rule is relaxed by this spec.
- [ ] This feature has no row in `docs/scope/` (no scope folder exists). Run `/scope` to enroll it if you want it tracked.
