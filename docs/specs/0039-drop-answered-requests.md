# 0039 Drop a Request that was answered elsewhere

Issue #56. Builds on [0002](0002-claude-code-notch-popup/index.md) and [0005](0005-claude-section-sessions-and-answers.md).

Today a **Request** (a question or a tool permission) answered in the Claude Code CLI or VS Code stays on the Notch until the 60 s fall-through. Claude does not close the held hook connection when the user answers elsewhere, so nothing tells the Notch.

## Requirements

- **AC-1** When a question is answered in the CLI or VS Code, its **Request** leaves the Notch right away.
- **AC-2** When a tool permission is approved in the CLI or VS Code, its **Request** leaves the Notch right away.
- **AC-3** A finished tool only drops the **Request** it matches. Another tool finishing in the same session leaves the **Request** alone.
- **AC-4** The 60 s fall-through and the hover/typing hold are unchanged. The new signal only adds a way out.
- **AC-5** The new hook entry is written and removed with the others, on the live port, on every launch.

## Design

- Add `PostToolUse` to the hook entries `ClaudeSettingsFile` writes, on the `event` route, same port and token.
- Store on each waiting **Request** what it needs to match: `tool_use_id` for a question (`PreToolUse` carries it); session, tool name and `tool_input` for a permission (`PermissionRequest` has no `tool_use_id`).
- On a `PostToolUse` report, `leave` the matching **Request** and `changed()`. `agent_id` is ignored: tool and input already identify the call.
- The held connection gets an empty reply as on timeout. Claude has already moved on, so the reply is harmless.
- A **Request** being typed into is dropped too; the answer is already given.

## Known limit

Denying or pressing Esc elsewhere fires no hook (`PostToolUseFailure` and `PermissionDenied` do not fire for it, and `Stop` does not run after an interrupt). That **Request** still waits for the 60 s fall-through.

## Tests

In `CatNotchCoreTests`, with `CLAUDE_CONFIG_DIR` at a temp folder and fake `PostToolUse` posts to the local server:

- a matching post drops a question and a permission;
- a post for another tool, or another session, drops nothing;
- the settings file gains and loses the `PostToolUse` entry with the others.

## Out of scope

Watching the transcript to catch denials; the done alert; a prompt on the Notch.
