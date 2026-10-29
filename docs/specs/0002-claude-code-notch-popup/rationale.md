# 0002 rationale: Claude Code permission and question popup on the notch

The decision record for [0002](index.md). The build spec is in `index.md`.

## Context

The notch already opens on its own for things that need you: a due reminder, a new screenshot, a finished focus session. Claude Code is the same kind of moment, and a worse one to miss. A Claude session that asks "Run `npm test`?" sits frozen until you look at the right window, and people running Claude in a terminal or in an editor side panel often work in another app meanwhile.

Claude Code can call out to other programs at key moments through hooks, configured in `~/.claude/settings.json`. One of them, `PermissionRequest`, fires just before the terminal prompt and can return a decision. A hook can be a plain web request (`type: "http"`), which fits an Electron app that already runs a main process. The same settings file is read by the CLI and by the VS Code extension, so one setup covers both.

Constraints that shape the design: the popup can approve commands on your machine, so only Claude may be able to talk to it; the notch must never steal keyboard focus (a stray Enter must not approve anything); the app runs on Windows and macOS; and failure of any part must leave Claude's own prompt working, never a frozen session. Doing nothing means users keep missing prompts, and Claude sits idle.

## Options considered

### Option 1: Local web hook, answer from the notch

DeskNotch listens on `127.0.0.1` and Claude's hooks call it with a secret token. Permission requests come in on one path, questions on another. The notch holds the request open until you click, then replies with the decision.

**Pros**:
- One entry per event, no script to ship, and identical on Windows and macOS.
- Can answer, not only announce.
- Failure falls through to Claude's normal prompt.

**Cons**:
- Opens a local port, which needs a token and host check.
- Edits the user's `settings.json`, which needs care.
- Depends on hook features that are documented but may change.

### Option 2: Notify only

Use Claude's `Notification` hook to say "Claude needs you", and answer in the terminal.

**Pros**:
- Smallest and safest. Cannot approve anything by mistake.

**Cons**:
- You still switch windows, which was the point of the feature.
- The notification only fires after Claude has waited a few seconds.

### Option 3: Command hook with a socket or named pipe

A small script run by Claude forwards the event to DeskNotch over a Unix socket (macOS) or named pipe (Windows).

**Pros**:
- No open network port.

**Cons**:
- Two transports and a script to ship, update and keep working on both systems.
- A shell script on the hot path of every permission request.

## Rationale

The point of the feature is to answer without switching windows, which rules out Option 2. Between 1 and 3, a web hook is one setting entry on both systems and needs no script, while Option 3 needs two transports and a script that must keep working on every Claude update. The open port is the real cost, and it is answered by binding to `127.0.0.1` only, a random secret token, a `Host` check, and a hard cap on size and count.

Safety rests on one rule: every failure ends in Claude's normal prompt. Hook failures, timeouts and an empty reply all fall through in Claude's documented behaviour, so a bug here makes the feature quiet, never a frozen session. That is also why the popup never takes focus, has an "Ask in terminal" button, and times out at 30 seconds.

The engineer's choices applied: answer from the notch, permissions and questions only (no "Done" moment), no "Always allow" button, one request at a time, click only, 30 second fallback, fixed port, token written into the hook, confirm plus backup on edit, popups override Hide in fullscreen.

