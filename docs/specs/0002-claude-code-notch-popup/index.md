# 0002. Claude Code permission and question popup on the notch

**Date**: 2026-10-28
**Status**: In Progress

## Summary

When Claude Code (in the terminal or in the VS Code extension) wants to run a command, or asks you a multiple choice question, the notch opens by itself and shows it. You tap Allow, Deny or an answer, and Claude carries on without you switching windows. It works through a small local web address that DeskNotch listens on, which Claude's hooks (its built in "run this when X happens" feature) call. If DeskNotch is closed, hidden or ignored, Claude simply shows its normal prompt, so nothing can get stuck.

## Requirements

**User stories**:
- As someone running Claude Code, I want the notch to show me when Claude needs permission, so that I do not leave Claude waiting while I work elsewhere.
- As the same person, I want to Allow or Deny right on the notch, so that I do not switch windows.
- As the same person, I want Claude's multiple choice questions on the notch too, so that I can answer with one tap.
- As a cautious user, I want to see what I am approving and to be able to decline the popup, so that a click is never a blind guess.
- As a user, I want to switch this on and off in Settings without editing JSON, so that setup takes a minute and is reversible.

**Acceptance criteria** (the contract, each independently checkable):
- **AC-1**: Turning on "Claude Code" in Settings first shows exactly what will be added to `settings.json`. After you confirm, the file contains our two hook entries and every other key is unchanged. A backup `settings.json.deskNotch.bak` is saved the first time only, and never overwritten after that.
- **AC-2**: Turning it off removes only our entries and leaves the rest of the file unchanged. If `settings.json` is not valid JSON, turning on or off changes nothing and Settings shows the snippet to paste by hand instead.
- **AC-3**: When Claude needs permission for a tool, the notch opens within 1 second and shows a tool badge, the project folder name, and the first 6 lines of the command (for file tools, the file path), with a "Show all" control. Opening it never moves keyboard focus into the notch.
- **AC-4**: Allow lets Claude run the tool with no terminal prompt. Deny stops that call and Claude is told "Denied from DeskNotch", and it carries on and may try another approach. "Ask in terminal" closes the popup at once and Claude shows its normal prompt.
- **AC-5**: With no answer for 30 seconds the popup closes and Claude shows its normal terminal prompt.
- **AC-6**: With DeskNotch not running, or its Claude switch off, Claude behaves exactly as if the feature did not exist.
- **AC-7**: A request without the correct secret token gets 401 and shows nothing. A request whose `Host` is not our own address is refused. Only `POST` to our two paths is served.
- **AC-8**: Several waiting requests show one at a time, oldest first, with a "1 of 3" count and each one's project folder name. Answering one shows the next.
- **AC-9**: A Claude question shows its text and each option (label and description) as a tap target. A multi select question has a Confirm button. A question with several parts shows them one at a time. A question that needs typed text shows "Answer in terminal", which falls through at once.
- **AC-10**: With "Hide in fullscreen" on and a fullscreen app in front, a request still opens the notch, and it hides again once no request is waiting.
- **AC-11**: If port 47821 is taken, DeskNotch uses the next free port and rewrites its own hook entries to match, without asking again.
- **AC-12**: If Claude drops the connection before you answer (it moved on, or the session ended), that popup disappears.
- **AC-13**: A single question from Claude produces one popup, not two, even if both hooks fire for it.
- **AC-14**: Everything above works on Windows and macOS, honours `CLAUDE_CONFIG_DIR` when set, and works for sessions started from the terminal and from the VS Code extension.

## Decision

**Chosen option**: Option 1: Local web hook, answer from the notch

DeskNotch runs a token protected server on `127.0.0.1:47821`, registers two Claude hooks through a Settings toggle, and shows permission requests and questions as notch popups that return Claude's decision.

## Rationale

Why this was chosen, the options weighed and the context are in [rationale.md](rationale.md).

## Feature design

**Data model sketch**:
Nothing new is stored per request; pending requests live in memory only. One new store field in `StoreShape` (`main/store.ts`):
- `claudeHooks: { enabled: boolean; token: string; port: number } | null` (`null` means never turned on; `token` is 32 random bytes as hex, made once; `port` is the port last used).

In memory, a `Map<id, Pending>` in the main process: `id` (random), `kind` (`'permission' | 'question'`), the parsed display payload, the open HTTP response, a 30 second timer, and `createdAt`. Capped at 20 pending; the 21st gets an empty reply (falls through).

**State transitions**:
pending → answered (Allow, Deny, option chosen) · pending → passed (Ask in terminal, or Answer in terminal) · pending → timed out (30 s) · pending → dropped (connection closed by Claude). Every exit sends `claude:resolved` to the renderer, removes the entry and clears the timer. Each request is answered exactly once.

**API surface** (served by DeskNotch; all `POST`, JSON body, body up to 1 MB):
| Endpoint | Method | Key inputs | Key outputs | Auth | Key errors |
|---|---|---|---|---|---|
| `/desknotch/permission` | POST | Claude's `PermissionRequest` body: `tool_name`, `tool_input`, `cwd`, `session_id` | 200 with the decision JSON, or 200 with `{}` to fall through | `Authorization: Bearer <token>` | 401 bad token, 403 bad Host, 405 not POST, 413 too large |
| `/desknotch/question` | POST | Claude's `PreToolUse` body for `AskUserQuestion`: `tool_input.questions`, `cwd` | 200 with answer JSON, or `{}` | same | same |

Replies (permission):
- Allow: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
- Deny: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from DeskNotch","interrupt":false}}}`
- Ask in terminal, timeout, over capacity: `{}`

Reply (question, shape to be confirmed by build task 1): `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"questions":[…original…],"answers":{"<question text>":"<chosen label>"}}}}`. A multi select answer joins the chosen labels with a comma. Fall through is `{}`.

`/desknotch/permission` replies `{}` immediately when `tool_name` is `AskUserQuestion`, so the question is only shown by the question route (AC-13).

IPC between main and renderer (a new `main/ipc/claude.ts`, registered in `main/ipc/index.ts`):
| Channel | Direction | Purpose |
|---|---|---|
| `claude:request` | main to renderer | a new pending request, display payload only (never the open response) |
| `claude:resolved` | main to renderer | an id left the queue (any reason) |
| `claude:answer` | renderer invoke | `(id, 'allow' | 'deny' | 'pass')` or `(id, answers)` |
| `claude:status` | renderer invoke | `{ enabled, port, running, configPath, valid }` |
| `claude:preview` | renderer invoke | the exact JSON that turning on would add, for the confirm step |
| `claude:enable` / `claude:disable` | renderer invoke | edit `settings.json` (see Security model) |

**Value sourcing** (every shown or sent value and where it comes from):
| Action | Value produced / displayed | Source |
|---|---|---|
| Show permission popup | Tool badge | `tool_name` in the hook body |
| Show permission popup | Project folder name | basename of `cwd` in the hook body (falls back to "Claude" if absent) |
| Show permission popup | Command text | `tool_input.command` for `Bash`; `tool_input.file_path` for `Edit`, `Write`, `Read`, `NotebookEdit`; for any other tool, `tool_input` as JSON cut to 300 characters |
| Show permission popup | "1 of N" | position in the in memory queue, oldest first by `createdAt` |
| Show question | Question text, options, labels, descriptions, `multiSelect` | `tool_input.questions[]` in the hook body |
| Reply to question | answer key | the question's `question` text, exactly as sent |
| Reply to question | answer value | the chosen option `label`; multi select labels joined by a comma |
| Reply to permission | deny message | the fixed text "Denied from DeskNotch" |
| Hook entry URL | host and port | `127.0.0.1` and `claudeHooks.port` from the store |
| Hook entry header | token | `claudeHooks.token` from the store |
| Hook entry | timeout | fixed 35 seconds (5 more than our 30 second fallback, so our own empty reply always wins) |
| Settings file path | location | `$CLAUDE_CONFIG_DIR/settings.json` when set, else `~/.claude/settings.json` |
| Popup visibility | whether to override Hide in fullscreen | whether the in memory queue is non empty |

**Key invariants**:
- Every request gets exactly one reply, or its connection is closed by Claude. Never two.
- The server answers only on `127.0.0.1`, only `POST` to `/desknotch/permission` and `/desknotch/question`, only with the correct token and a `Host` of `127.0.0.1:<port>`.
- The notch never calls anything that takes focus when a request arrives.
- Allow is only ever sent as the direct result of a click on that exact request's Allow button. Nothing sends it by default, timer, or error.
- We write only hook entries whose URL starts `http://127.0.0.1:` and has the path prefix `/desknotch/`. Those are the only entries we add, change or remove.

**Hook entries written** (one in `PermissionRequest`, no `matcher`; one in `PreToolUse` with `matcher: "AskUserQuestion"`):
```json
{ "type": "http", "url": "http://127.0.0.1:47821/desknotch/permission", "timeout": 35,
  "headers": { "Authorization": "Bearer <token>" } }
```
The second is the same with `/desknotch/question`. The token is written literally (no environment variable), so VS Code and every terminal work without setup.

**Security model**:
- Anyone who can reach the port with the token could approve commands, so: bind `127.0.0.1` only, a 32 byte random token, constant time compare, `Host` check (blocks DNS rebinding from a web page), body size cap, pending cap, no logging of command text to disk.
- A web page cannot send our `Authorization` header cross site without a preflight that we never answer, so browsers cannot call it.
- Editing `settings.json`: show a preview and require confirm; save `settings.json.deskNotch.bak` once; parse the file, add or remove only our entries, write to a temp file in the same folder and rename it over the original; refuse on invalid JSON. Compliance scope: none beyond this (commands you see stay on your machine and are not stored).

**Configuration required**:
- `claudeHooks` store field (above). No new environment variables or credentials.

**Critical test scenarios**:
- Happy path: Claude asks to run a command, popup shows it, Allow, command runs with no terminal prompt, verifies **AC-3**, **AC-4**.
- Deny: click Deny, Claude reports the denial and carries on, verifies **AC-4**.
- Pass: "Ask in terminal" shows the terminal prompt at once, verifies **AC-4**.
- Timeout: do nothing, popup closes at 30 s and the terminal prompt shows, verifies **AC-5**.
- App closed: quit DeskNotch, ask Claude to run a command, normal prompt, verifies **AC-6**.
- Bad token and bad Host with `curl`: 401 and 403, nothing on screen, verifies **AC-7**.
- Three requests at once: "1 of 3", answered in order, verifies **AC-8**.
- Question with single, multi select and typed text options, verifies **AC-9**, **AC-13**.
- Fullscreen video with Hide in fullscreen on, verifies **AC-10**.
- Occupy port 47821 before launch, verifies **AC-11**.
- Interrupt the Claude session mid popup, popup vanishes, verifies **AC-12**.
- Turn on and off with a `settings.json` full of other keys; then with broken JSON, verifies **AC-1**, **AC-2**.
- Run on both systems and from the VS Code extension, verifies **AC-14**.

## Build plan

No build approach is recorded for the project, so this uses end to end thin slices (Tracer Bullet): a working thread first, then thicker.

1. Spike, no product code: with a throwaway local server, confirm in a real session (a) the exact reply that answers `AskUserQuestion`, (b) that `PermissionRequest` fires from the VS Code extension, (c) that a hook change reaches an already running session or needs a restart, (d) whether the connection closes when you answer in the terminal first. Record the results in this spec's Follow-up and fix the question reply shape above. If (a) fails, ship questions as "notify with Answer in terminal", satisfies **AC-9**, **AC-14**
2. Thin thread: `main/ipc/claude.ts` with the server, token and Host checks, `/desknotch/permission`, an in memory pending map, `claude:request` to the renderer, and a bare Allow and Deny popup in the notch. Test with a hand written hook entry, satisfies **AC-3**, **AC-4**, **AC-6**, **AC-7**
3. Lifecycle: 30 second timeout, connection close detection, "Ask in terminal", the queue and "1 of N", the 20 request cap, satisfies **AC-5**, **AC-8**, **AC-12**
4. Full permission popup: tool badge, project name, 6 lines plus "Show all", no focus steal, and the override of Hide in fullscreen while the queue is non empty (extend the tuck logic in `main/fullscreen.ts`), satisfies **AC-3**, **AC-10**
5. Questions: `/desknotch/question`, the question view (options, Confirm for multi select, parts one at a time, "Answer in terminal"), and the `AskUserQuestion` guard on the permission route, satisfies **AC-9**, **AC-13**
6. Settings toggle: `claudeHooks` in the store, `claude:status`, `claude:preview`, confirm dialog, backup, atomic edit, removal, invalid JSON fallback snippet, port in use handling with entry rewrite, `CLAUDE_CONFIG_DIR`, satisfies **AC-1**, **AC-2**, **AC-11**, **AC-14**
7. Docs: a README section ("Claude Code on the notch"), a note in `PRIVACY.md` that requests are shown locally and not stored, and the feature in `doc/Functionality.md`, satisfies **AC-14**

## Consequences

**Positive**:
- You stop leaving Claude waiting, and you can approve from wherever you are.
- One setup serves the CLI and VS Code.
- Every failure ends in Claude's own prompt, so adopting it is low risk.

**Negative / tradeoffs**:
- A new open local port and a feature that can approve commands. It is guarded, but it is real surface to keep secure.
- DeskNotch now edits a file owned by another tool, which can break if Claude changes the settings format.
- If you answer in the terminal first, the popup may linger until Claude drops the connection or the 30 second timer ends (build task 1 checks this).
- It relies on documented hook behaviour, and the question answer shape is still unconfirmed.
- Clicking Allow is easier than typing in a terminal, so it is easier to approve by habit.

**Neutral**:
- Session labels are the project folder name only, so two sessions in folders with the same name look alike.
- Hook changes may need a new Claude session to take effect.
- No "Always allow" and no keyboard shortcuts in this version.

## Follow-up

- [x] Build task 1 spike, run 2026-10-28 against Claude Code 2.1.312 with a throwaway local server: (a) the question reply shape in the spec works exactly as written (interactive CLI, Claude received the answer); (b) the permission hook fires for Bash in the CLI, Allow runs the command and Deny delivers "Denied from DeskNotch" to Claude; (c) the hook body also carries `permission_suggestions`, `prompt_id`, `tool_use_id` (questions only), unused here; (d) an `AskUserQuestion` call fired only the question route, so the permission route guard stays as a cheap safety net.
- [ ] Still unverified, check by hand: the VS Code extension fires both hooks; a hook change reaches an already running session; the connection closes when you answer in the terminal first.
- [x] Build tasks 2 to 7 built and checked on 2026-10-28. Checked with the real server code and the real Claude CLI: AC-1, 2, 3 (data), 4, 5, 7, 8, 9, 11, 12, 13 and AC-6. Checked in the running dev app through its debug port: the permission and question popups render, and clicking Allow, Ask in terminal and an answer sends the right reply.
- [ ] Not yet checked by hand: AC-10 (popup over a real fullscreen app), AC-14 on Windows, the VS Code extension (see above), and the Settings toggle written into a real `~/.claude/settings.json` (it was exercised only on a temporary copy).
- [ ] While testing, the dev Electron app crashed three times (native SIGTRAP, reports in `~/Library/Logs/DiagnosticReports`) with the feature on, and could not be made to happen again on purpose (dropped connections, two requests at once and questions all passed). It did not crash in a 220 second run with the feature off. Watch for it; if it comes back, capture the report.
- [ ] A later spec could add a "Claude finished" moment and an "Always allow" button, both left out on purpose.
- [ ] This feature has no row in `docs/scope/` (no scope folder exists yet). Run `/scope` to enroll it if you want it tracked.
- [ ] `renderer/AGENTS.md` only carries the Next.js notice, and the project has no root `AGENTS.md`. Run `/audit` so later skills know the stack.
