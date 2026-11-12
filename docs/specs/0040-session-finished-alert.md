# 0040 Tell the user when a Claude session finishes

Builds on [0033](0033-native-claude-sessions.md) and [0039](0039-drop-answered-requests.md). Issue #57.

Today the one sound plays both for a new **Request** and for a finished turn, and the closed **Notch** shows nothing when a session finishes. The user wants to hear and see "finished", and not be pinged by a sound for every **Request**.

## Requirements

- **AC-1** When a session that was working ends its turn (`Stop`), the closed **Notch** opens briefly with "<project> finished". It does not take focus.
- **AC-2** The banner leaves after about 1 second. Hovering it pauses the timer.
- **AC-3** The sound plays on this event only. A new **Request** plays no sound.
- **AC-4** Skipped, for both banner and sound, when that session's terminal is in front. VS Code is never skipped (the same rule as a **Request**).
- **AC-5** Subagents finishing, an Esc interrupt and a manual `/compact` do not alert.
- **AC-6** The session row in the Claude tab reads "Done" after it finishes, until the user next looks at it.
- **AC-7** The sound picker in Settings is renamed "Sound when Claude finishes". "None" stays silent. The stored value is unchanged, so a saved pick survives.

## Design

- `ClaudeSessions.seen` already returns true for `Stop` on a working session; `onTurnEnd` already fires from it. Keep that as the single trigger.
- `ClaudeModel`: stop calling `play(sound)` when a new **Request** arrives. Add a `finished` value (session id, project) that `onTurnEnd` sets, with the 1 s timer and a hover hold like the **Request** hold.
- The terminal-in-front check reuses `isTerminalInFront` with the session's source.
- Settings only gains the new label. No new toggle.

## Out of scope

A separate switch for the banner; `SubagentStop`; alerts for interrupted sessions (see #36).

## Tests

In `CatNotchCoreTests`: `Stop` on a working session fires `onTurnEnd`; `Stop` on an idle session, `SubagentStop`, and a manual compact do not; a new **Request** no longer triggers a sound callback.
