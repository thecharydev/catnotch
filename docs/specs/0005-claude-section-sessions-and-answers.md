# 0005. Claude section: every session, and answer questions from the notch

**Date**: 2026-10-29
**Status**: In Progress

## Summary

The notch gets a "Claude" tab that lists every Claude Code session on your machine, whether it runs in a terminal or in the VS Code extension, with what each one is doing right now: working, waiting for you, or idle. When Claude asks a question, you can read the whole thing on the notch, tap an option, or type your own answer, and Claude carries on. This builds on the permission and question popup in [0002](0002-claude-code-notch-popup/index.md): the same small local server and the same Settings switch, with four more hooks (Claude's built in "run this when X happens" feature) so DeskNotch hears about sessions, plus a scan of recent session files so sessions that are already open show up too.

## Context

Spec 0002 shows one waiting request at a time, as a popup. It has no view of Claude when nothing is asking: you cannot see how many sessions are open, which one is busy, or which one is stuck waiting for you. It also cannot take a typed answer; a question that needs your own words is handed back to the terminal.

Facts checked on this machine (Claude Code 2.1.x, 2026-10-29): every hook body carries `session_id`, `cwd` and `transcript_path`. Each session writes a transcript file under `~/.claude/projects/<project>/<session_id>.jsonl`, and its lines carry `"entrypoint":"cli"` for a terminal session and `"entrypoint":"claude-vscode"` for the VS Code extension. That is the reliable way to tell the two apart; the hook body itself does not say. The `AskUserQuestion` answer shape (a map from question text to answer text) was confirmed in 0002's spike, but only with option labels, so free typed text still needs one check (build task 1).

This is an ENHANCEMENT of 0002 (built, In Progress) on the existing Electron, Next.js and TypeScript app. The code touched is `main/ipc/claude.ts`, `renderer/components/widgets/ClaudeView.tsx`, `renderer/hooks/useClaude.ts` and `renderer/pages/home.tsx`. Not deciding means the popup stays an isolated interruption and typed answers stay in the terminal.

## Requirements

**User stories**:
- As someone running several Claude sessions, I want one list of all of them, so that I can see which are busy and which are waiting for me.
- As the same person, I want to tell a terminal session from a VS Code one, so that I know where to go.
- As the same person, I want to read a Claude question in full and answer it by tapping or typing on the notch, so that I never switch windows for it.
- As a user, I want the Claude tab in the dock like the others and hideable in Settings, and the popup to still jump in when Claude needs me.

**Acceptance criteria** (the contract, each independently checkable):
- **AC-1**: The dock has a "Claude" tab, hideable in Settings like the other tabs. It lists up to 20 sessions, most recently active first, each row showing the project folder name, a "CLI" or "VS Code" badge, and a state: Working, Waiting for you, or Idle.
- **AC-2**: With "Claude Code" turned on, a session started from a terminal and one from the VS Code extension each appear in the list within 2 seconds of their first prompt, with the correct badge.
- **AC-3**: Sessions already open before DeskNotch started (or before the switch was turned on) appear within 20 seconds as Idle if their transcript file changed in the last 3 hours, with the correct badge.
- **AC-4**: State follows Claude: sending a prompt sets Working; Claude finishing its turn sets Idle; a pending permission or question for that session shows Waiting for you, overriding the other two until it is answered, passed or dropped.
- **AC-5**: A session leaves the list when it ends, or when its transcript file has not changed for 3 hours. A session shown as Working whose transcript has not changed for 10 minutes is shown as Idle.
- **AC-6**: Pending permission and question requests from 0002 still open the notch by themselves (AC-3, AC-10 of 0002 still hold). In the Claude tab, waiting requests are shown above the session list, oldest first.
- **AC-7**: A Claude question shows its full text, scrollable, with every option's label and description. Tapping an option selects it. Single select answers on tap plus a clear Send; multi select has a Confirm.
- **AC-8**: Every question part also has a text box. Typed text is sent as that part's answer. On a multi select question, typed text is sent together with any ticked labels, joined by a comma. Empty or whitespace only text is not sendable. Text over 2000 characters is cut at 2000.
- **AC-9**: A question with several parts shows them one at a time, and Send is enabled only when every part has an answer. "Answer in terminal" stays as a small control that hands the question straight back to Claude's own prompt.
- **AC-10**: Typing in the notch takes keyboard focus only when you click the text box, and gives it back to the previous app when you send, pass or click away. A popup arriving never takes focus.
- **AC-11**: Turning on "Claude Code" writes the four new hook entries as well as the two from 0002, with the same preview, backup and removal rules (AC-1, AC-2 of 0002). If hooks are already installed but lack the new ones, Settings shows "Update hooks" and nothing changes until you confirm.
- **AC-12**: The new session hooks never delay Claude: they get an empty reply at once. With DeskNotch closed or the switch off, Claude behaves as if the feature did not exist.
- **AC-13**: The new route has the same guards as 0002 (correct token, own `Host`, `POST` only, body cap) and shows nothing on a refusal.
- **AC-14**: Works on macOS and Windows, honours `CLAUDE_CONFIG_DIR`, and the transcript scan reads files only under `<config dir>/projects`.

## Options considered

### Option 1: Hooks plus a scan of recent transcripts

Four extra hooks give live state; a scan of transcript files seeds sessions already open and gives the CLI or VS Code badge.

**Pros**:
- Live and accurate state, and nothing already running is missed.
- Reuses the 0002 server, token and Settings switch.

**Cons**:
- Two sources of truth to reconcile (one rule: the session id).
- Users who already enabled 0002 must accept an hook update.

### Option 2: Hooks only

**Pros**: simplest, one source.

**Cons**: open sessions stay invisible until they act; the badge still needs the transcript.

### Option 3: Scan and process polling only

**Pros**: no new hooks.

**Cons**: cannot tell working from waiting, and guesses the source from process names.

## Decision

**Chosen option**: Option 1: Hooks plus a scan of recent transcripts

A new `claude:sessions` feed in the main process merges hook events and a 15 second transcript scan into one list, and the existing question view gains full text and a typed answer.

## Rationale

Option 1 is the only one that is both live and complete. The scan costs a few file stats every 15 seconds, and each transcript is read only for its first line that holds `entrypoint` and `cwd`, once per session, then cached. The hook events are the only signal for Working and Idle, since transcripts alone do not say whether Claude is mid turn. One rule joins the two: the key is `session_id`, which is the transcript file name and also in every hook body.

Typed answers reuse the answer map 0002 already sends. Claude's own interface lets you pick "Other" and type, which goes into the same map, so sending text there is the same shape with a free string in place of a label. This is the one place we relax 0002's strict "must be one of the labels" check, and only for text we cap and trim.

## Feature design

**Data model sketch**:
Nothing new is stored on disk. In memory in the main process, `Map<session_id, Session>`:
- `id` (session_id), `cwd`, `project` (basename of cwd), `source` (`'cli' | 'vscode' | 'unknown'`), `state` (`'working' | 'idle'`), `lastEventAt`, `transcriptPath`, `transcriptMtime`, `endedAt` (null while live).
"Waiting for you" is not stored: it is derived, true when any pending request (0002's map) has this `session_id`. 0002's `Pending` view gains one field, `sessionId`, taken from the hook body.

**State transitions**:
- A session appears on any hook event, or from the scan. State is Idle on appearance, except `UserPromptSubmit` which sets Working.
- `UserPromptSubmit` → working · `Stop` → idle · `SessionStart` → idle (and resets `endedAt`) · `SessionEnd` → removed.
- Expiry: transcript untouched 3 hours → removed; Working with transcript untouched 10 minutes → idle.
- Any state → shown as Waiting for you while a pending request holds its id.

**API surface** (added to the 0002 server, `POST`, JSON, same guards):
| Endpoint | Method | Key inputs | Key outputs | Auth | Key errors |
|---|---|---|---|---|---|
| `/desknotch/event` | POST | hook body: `hook_event_name`, `session_id`, `cwd`, `transcript_path` | 200 `{}` at once, always | `Authorization: Bearer <token>` | 401, 403, 405, 413 |

IPC added (in `main/ipc/claude.ts`):
| Channel | Direction | Purpose |
|---|---|---|
| `claude:sessions` | renderer invoke | the current list (display fields only) |
| `claude:sessions-changed` | main to renderer | the list changed (sent at most once per second) |
| `claude:answer` | renderer invoke | existing; for a question the value for a part may now be typed text |

The answer reply keeps 0002's shape; for each question the value is the chosen label, the typed text, or both comma joined.

**Value sourcing** (every shown or sent value and where it comes from):
| Action | Value produced / displayed | Source |
|---|---|---|
| Show a session row | Project name | basename of `cwd` (hook body, else the first transcript line with `cwd`); "Claude" if neither |
| Show a session row | Source badge | `entrypoint` from the first transcript line that has one: `cli` is CLI, `claude-vscode` is VS Code, anything else or unreadable is no badge |
| Show a session row | State | derived as in State transitions |
| Show a session row | Sort order | `max(lastEventAt, transcriptMtime)` |
| Scan | Which files | `<config dir>/projects/*/*.jsonl` with mtime in the last 3 hours; `<config dir>` is `$CLAUDE_CONFIG_DIR` else `~/.claude` |
| Scan | session id | the file name without `.jsonl` |
| Hook entry | URL, token, timeout | same as 0002 (`127.0.0.1`, `claudeHooks.port`, `claudeHooks.token`); timeout 5 seconds for event hooks |
| Waiting for you | which session | `session_id` of the pending request |
| Typed answer | answer text | the text box, trimmed, cut at 2000 characters |
| Typed answer | answer key | the question's `question` text, exactly as sent |
| Focus for typing | when to take and give back | click in the text box takes it; send, pass or blur gives it back |

**Key invariants**:
- The event route replies `{}` before doing any work; it can never hold Claude up.
- The transcript scan only stats files and reads a bounded first part (first 64 KB) of a file once per session. It never sends transcript text to the renderer and never stores it.
- Only the display fields above reach the renderer. No prompts, no commands beyond what 0002 already shows for a waiting request.
- A request is still answered exactly once (0002 invariant). Typed text is sent only from a click on that request's own Send.
- We write only hook entries whose URL starts `http://127.0.0.1:` with the path prefix `/desknotch/`.

**Hook entries written** (added to the two from 0002, one group each, no `matcher`):
`SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Stop`, each `{ "type": "http", "url": "http://127.0.0.1:<port>/desknotch/event", "timeout": 5, "headers": { "Authorization": "Bearer <token>" } }`.

**Security model**: same as 0002. The new route gives no power over Claude (its reply is always `{}`), so the extra surface is a source of display data only. The typed answer is data the user chose to send to their own session. Compliance scope: none; nothing leaves the machine or is stored.

**Configuration required**: none new. Settings gains a "Claude" entry in the existing dock tab visibility list.

**Critical test scenarios**:
- Open one terminal session and one VS Code session, send a prompt in each; both rows appear with the right badge, verifies **AC-1**, **AC-2**.
- Quit and relaunch DeskNotch with sessions open; they come back as Idle within 20 seconds, verifies **AC-3**.
- Send a prompt, watch Working, let it finish, watch Idle; trigger a permission request and see Waiting for you, verifies **AC-4**.
- `/exit` a session and leave another untouched; the first leaves at once, verifies **AC-5**.
- Ask a three part question with a long text, answer one part by tap and one by typing, Send, verifies **AC-7**, **AC-8**, **AC-9**.
- Click into the text box while another app is in front; type; send; the other app has focus again, verifies **AC-10**.
- Already enabled install: Settings shows "Update hooks", nothing changes until confirmed, then six entries exist, verifies **AC-11**.
- Quit DeskNotch and run a prompt; Claude is unaffected, verifies **AC-12**.
- `curl` the event route with a bad token and a bad Host, verifies **AC-13**.
- Run on both systems, verifies **AC-14**.

## Build plan

No build approach is recorded for the project, so this uses end to end thin slices (Tracer Bullet): a thread through every layer first, then thicker.

1. Spike, no product code: with a throwaway server, confirm in a real session (a) that Claude accepts typed text as an `AskUserQuestion` answer in the answers map, for single and multi select, (b) that `SessionStart`, `SessionEnd`, `UserPromptSubmit` and `Stop` fire with an http hook from both the CLI and the VS Code extension, and their body field names. Record results in Follow-up. If (a) fails, ship tap only and keep "Answer in terminal" for text, satisfies **AC-8**, **AC-2**
2. Thin thread: `/desknotch/event`, the in memory session map, `claude:sessions`, and a bare Claude tab listing project and state. Hand written hook entries, satisfies **AC-1**, **AC-4**, **AC-12**, **AC-13**
3. Transcript scan: stat and bounded first read, badge from `entrypoint`, seeding, the 3 hour and 10 minute expiries, satisfies **AC-2**, **AC-3**, **AC-5**, **AC-14**
4. Waiting overlay: add `sessionId` to pending views, derive Waiting for you, show waiting requests above the list in the tab while the popup behaviour from 0002 is untouched, satisfies **AC-4**, **AC-6**
5. Question view: full scrollable text, per part text box, Send and Confirm rules, relax the label check in `answer()` for trimmed capped text, keep "Answer in terminal", focus take and release for the text box, satisfies **AC-7**, **AC-8**, **AC-9**, **AC-10**
6. Settings: add the four hooks to `entries()`, "Update hooks" detection and confirm, the dock tab visibility entry, satisfies **AC-1**, **AC-11**
7. Docs: README "Claude on the notch" section, `PRIVACY.md` note that sessions are read locally and never stored or sent, `doc/Functionality.md`, and a line in 0002 pointing here for typed answers, satisfies **AC-14**

## Consequences

**Positive**:
- One place to see all your Claude sessions and what each needs.
- Long or open ended questions can be answered without leaving what you are doing.
- Reuses the 0002 server, token and switch, so there is little new surface.

**Negative / tradeoffs**:
- DeskNotch now reads Claude's transcript files (first lines only, nothing stored) and edits four more hook entries in a file owned by another tool.
- Idle detection for a crashed session is time based, so it can linger for up to 3 hours.
- Taking focus to type is the first time the popup can take focus, so a mis click can steal a keystroke meant for another app; it only happens after you click the box.
- This amends 0002: typed text is no longer handed to the terminal, and the strict label check is relaxed for text.

**Neutral**:
- Two sessions in folders with the same name look alike (the badge and state help, a prompt snippet was left out on purpose).
- Hook changes may need a new Claude session to take effect, as in 0002.
- No git branch, no click to jump to a session's window, no "Always allow", all left out on purpose.

## Follow-up

- [x] Build task 1 spike, run 2026-10-29 on Claude Code 2.1.312: typed text is accepted as an answer in the map (interactive CLI); UserPromptSubmit, Stop and SessionEnd fire as http hooks with the fields used here; SessionStart does NOT fire as an http hook, so it is not registered (any other event creates the session). VS Code extension not yet checked by hand.
- [ ] Spec 0007 relaxes the "never sends transcript text to the renderer" rule for the one session you open.
- [ ] After build, add one line to 0002 saying its AC-9 typed text rule is superseded by AC-8 here.
- [ ] A later spec could add click to focus a session's terminal or VS Code window.
- [ ] This feature has no row in `docs/scope/` (no scope folder exists). Run `/scope` to enroll it if you want it tracked.
