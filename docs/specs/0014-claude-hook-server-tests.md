# 0014. Automated tests and a CI workflow for the Claude hook server

**Date**: 2026-10-31
**Status**: Accepted

## Summary

The Claude hook server (`main/ipc/claude.ts`) is the part of DeskNotch that fails silently: if it breaks, Claude's questions simply never reach the notch and nobody sees an error. This spec adds a focused set of tests for it, plus one small GitHub Actions workflow that runs every test on each push and pull request. The tests run in plain Node with Electron faked, use a temporary Claude folder and a temporary store, and never touch your real `~/.claude`. The only production code change is one tiny export so the "terminal in front" rule can be tested.

## Context

Workspace: single repo, an ENHANCEMENT of existing code (Electron main process). Stack from `CLAUDE.md`: vitest, tests beside the source as `*.test.ts(x)`, `npm test` runs `vitest run`. Today 3 test files (17 tests) pass, and all of them are in `renderer/`. Nothing in `main/` is tested, and `vitest.config.mts` only includes `renderer/**` (CLAUDE.md already says to add `main/**` when main tests arrive).

The hook server starts on port 47821 (or the next free one, up to 20 tries) and writes five hook entries into Claude's `settings.json`: `PermissionRequest`, `PreToolUse` (matcher `AskUserQuestion`), and the reporting events `SessionEnd`, `UserPromptSubmit`, `Stop`. The URLs inside must always match the live port. A bug just fixed in the working tree (uncommitted) showed how this breaks: `startClaudeServer` only rewrote the entries when the port changed, so a `settings.json` that pointed at an old port stayed wrong while the saved port looked fine. Questions then went to a dead port.

Most of `claude.ts` is private (`listen`, `edit`, `handle`, `answer` are not exported). The public surface is `startClaudeServer`, `registerClaudeIpc`, and the IPC handlers it registers (`claude:enable`, `claude:disable`, `claude:answer`, `claude:pending`, `claude:status`, `claude:sessions`). The server itself is a plain Node `http` server, so tests can talk to it over real loopback HTTP. The module only needs Electron for `ipcMain`, `BrowserWindow` and `app.getPath('userData')` (through `main/store.ts`), and it calls `main/fullscreen.ts` for `claudeIsInFront`.

## Requirements

**User stories**:
- As the maintainer, I want the hook server covered by tests so a change that breaks questions or permissions fails in CI instead of failing silently for users.
- As the maintainer, I want the exact "stale port in settings.json" bug pinned by a test so it cannot return.
- As a user with other Claude tools configured, I want proof that DeskNotch never edits or removes hooks that are not its own.

**Acceptance criteria**:
- **AC-1** (port fallback): when the saved port is already taken, the server listens on the next free port within 20 tries, saves that port to the store, and `claude:status` reports it.
- **AC-2** (hook sync, regression for the bug): with a saved port that is free and a `settings.json` whose DeskNotch entries point at a different, older port, after `startClaudeServer()` all five entries point at the live port and carry `Authorization: Bearer <stored token>`. The same holds when the saved port is busy and the server moves to a new one.
- **AC-3** (sync shape): the five entries have the right route (`permission`, `question`, `event`), the `AskUserQuestion` matcher on `PreToolUse`, timeout 65 for permission and question and 5 for the reporting events, and running the sync twice leaves no duplicates.
- **AC-4** (other tools untouched): hooks that are not ours (a command hook, an http hook to another host, a hook for another event, other top level keys like `permissions`) are unchanged after enable, after a second start, and after `claude:disable`; disable removes only our entries.
- **AC-5** (bad file safety): a `settings.json` that is not JSON is never written (the file stays byte for byte the same), and `claude:enable` returns `{ ok: false, error: 'invalid' }`. A first backup `settings.json.deskNotch.bak` is written once and not overwritten later.
- **AC-6** (reply shapes): an `AskUserQuestion` reaches the notch, and answering it replies to Claude with `{ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'allow', updatedInput: { questions, answers } } }` where `answers` maps each question text to the chosen label (several joined by `, ` only for multi select). A permission request replies `{ hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'allow' } } }` for allow, and `decision: { behavior: 'deny', message: 'Denied from DeskNotch', interrupt: false }` for deny. Choosing `pass` replies `{}`. An invalid choice is refused (`claude:answer` returns `false`) and the request stays queued.
- **AC-7** (no double popup): a `PermissionRequest` for the tool `AskUserQuestion` is answered with `{}` at once and never queued, because the question route shows it.
- **AC-8** (gate): the server answers 401 with a wrong or missing token, 405 for a non POST, 404 for an unknown path, 403 for a wrong `Host` header; reporting events reply `{}` at once and the session shows up in `claude:sessions`.
- **AC-9** (terminal rule): when a terminal is in front, a CLI or unknown source request is answered `{}` at once and not queued; when nothing is in front it is queued; a VS Code source is never skipped, even with a terminal in front. The pure rule is tested directly for terminal ids (macOS bundle ids and Windows process names, case insensitive), browsers, empty input, and each source.
- **AC-10** (isolation): no test reads or writes the real `~/.claude` or the real DeskNotch store, none needs Electron installed or running, and none listens on 47821 (each seeds its own free port).
- **AC-11** (CI): a workflow runs `npm test` on every push and pull request, builds and releases nothing, and needs no secrets.
- **AC-12** (no behavior change): the existing renderer tests still pass, and the only production edit is the pure function export in `main/fullscreen.ts`, with identical behavior.

## Options considered

### Option 1: Test through the public surface, fake Electron with `vi.mock`

Start the real server with `startClaudeServer`, talk to it over loopback HTTP with `fetch`, drive answers through the captured IPC handlers, and read `settings.json` from a temp folder. `vi.mock('electron')` supplies `ipcMain`, `BrowserWindow` and `app.getPath` (pointing at a temp folder, so the real `store.ts` runs unchanged). `vi.mock('../fullscreen')` supplies a controllable `claudeIsInFront`.

**Pros**:
- No refactor of `claude.ts`; tests exercise the same path Claude's hooks use.
- The real store code runs against a temp folder, so "temp store" is real, not another fake.
- Catches wiring bugs (a wrong route, a header typo) that unit tests of inner functions would miss.

**Cons**:
- Module state (`server`, `port`, `pending`, `sessions`) lives for the whole process, so each test needs `vi.resetModules()` plus a dynamic import and a teardown that calls `claude:disable`.
- Real sockets mean a little more care with ports.

### Option 2: Export the private functions and unit test them

Export `edit`, `listen`, `answer`, `handle` and call them directly.

**Pros**:
- Smaller, faster tests that need no HTTP.

**Cons**:
- Changes a security sensitive module's surface only for tests.
- Misses the real request path, so it would not have caught reply shape or header regressions end to end.

### Option 3: Extract the server into a Node only module with injected dependencies

Split `claude.ts` into a core with no Electron import and a thin Electron shell.

**Pros**:
- Cleanest long term shape.

**Cons**:
- Large diff on code that works, against the "keep changes small, do not change behavior" rule.
- Risk of breaking the hook server to add tests for it.

## Decision

**Chosen option**: Option 1: public surface, real HTTP, faked Electron.

Test `claude.ts` as it ships, with one tiny export from `fullscreen.ts` for the pure terminal rule.

## Rationale

You asked for small changes, no behavior change, and tests that run without Electron. Option 1 is the only one that needs no change to `claude.ts` at all (Context: the HTTP server is plain Node, and only three Electron symbols are used). It also tests the thing that actually broke, the full path from `startClaudeServer` to the file on disk, which an inner function test would only partly cover. Option 3 is the right shape if the server grows, but it spends risk on a working module now.

The one exception is the terminal rule. `claudeIsInFront` reads a private `lastRawResult` that only the real fullscreen watcher sets, so it cannot be driven from a test without the Electron screen and the Swift helper. Pulling the pure part out as `isTerminalInFront(raw, source)` and having `claudeIsInFront` call it is a three line change with the same behavior. The fallback if you prefer zero production edits is to mock `./display` and `./mac/helper` and feed the watcher a fake line, which is more brittle.

## Feature design

**Where tests live** (beside the source, per `test-preferences.json`):

| File | What it covers |
|---|---|
| `main/ipc/claude.test.ts` | AC-1 to AC-9 (server, sync, replies, gate, the skip wiring) |
| `main/fullscreen.test.ts` | AC-9, the pure rule `isTerminalInFront` |

**Shared setup inside `claude.test.ts`** (kept in the file, no helper module, since only one file uses it):
- First line `// @vitest-environment node`, because the global config uses jsdom and the server tests need real Node `http` and `fetch`.
- `vi.hoisted` state holding the temp `userData` path, a `Map` of captured IPC handlers, and fake windows whose `webContents.send` is a spy.
- `vi.mock('electron')`: `app.getPath` returns the temp folder, `ipcMain.handle(channel, fn)` stores `fn`, `BrowserWindow.getAllWindows` returns the fake windows.
- `vi.mock('../fullscreen')`: `claudeIsInFront` is a `vi.fn()` the test controls and whose arguments it can read; `setClaudeWaiting` and `checkAndApplyFullscreenState` are no ops.
- `beforeEach`: make two temp folders (`userData` and the Claude config), set `process.env.CLAUDE_CONFIG_DIR`, write `desknotch-store.json` with `claudeHooks: { enabled: true, token: 'test-token', port: <free port> }`, `vi.resetModules()`, then `await import('./claude')`. A `freePort()` helper listens on port 0, reads the port and closes.
- `afterEach`: call the captured `claude:disable` handler (stops the server, the scan timer and any pending timers), close any blocker server, delete the temp folders, restore the env var.
- Requests go out with `fetch('http://127.0.0.1:<port>/desknotch/<route>', { method: 'POST', headers: { Authorization: 'Bearer test-token' }, body })`. A question or permission request stays open, so the test starts the `fetch` without awaiting, polls `claude:pending` for the id, calls `claude:answer`, then awaits the response body.

**The regression test (AC-2), exact steps**:
1. Pick a free port `P` and a different old port `Q`. Store has `port: P`, so the old code path `got !== stored.port` is false.
2. Write `settings.json` with all five DeskNotch entries pointing at `http://127.0.0.1:Q/desknotch/...`, plus one foreign hook in the same event group.
3. `await startClaudeServer()`.
4. Assert every one of the five entries now has `http://127.0.0.1:P/desknotch/<route>` and `Bearer test-token`, and the foreign hook is unchanged.
5. Variant: occupy `P` with a blocker server first. Assert the server comes up on a port in `P+1..P+19`, the store has that port, and `settings.json` matches it.
Mutation check (done once by hand, not committed): temporarily put the old guard back (`if (got !== stored.port) edit(true)`) and confirm test 2 fails. A regression test that cannot fail is not a test.

**Key invariants the tests protect**:
- The hook URLs in `settings.json` equal the live port after every start.
- Only entries whose URL matches `^http://127.0.0.1:\d+/desknotch/` are ever touched.
- Every reply to a hook is one of the exact shapes above, or `{}` (which makes Claude show its own prompt).

**Security model**: tests assert the gate (token, host, method, path) because it is what stops a web page from approving a command. Tests use a fake token only.

**Configuration required**: none. No secrets, no environment values beyond the test's own `CLAUDE_CONFIG_DIR`.

**Critical test scenarios**:
- Happy path: start, post a question, answer it, Claude gets the `PreToolUse` allow reply with `updatedInput.answers`, verifies **AC-6**.
- Failure case: stale port in `settings.json` fixed on startup, verifies **AC-2**.
- Failure case: saved port busy, server moves, entries follow, verifies **AC-1**, **AC-2**.
- Safety: foreign hooks and invalid JSON left alone, verifies **AC-4**, **AC-5**.
- Gate: wrong token 401, wrong host 403, verifies **AC-8**.
- Rule: terminal in front skips CLI, never VS Code, verifies **AC-9**.

## The one production edit (`main/fullscreen.ts`)

```ts
/** Pure rule behind claudeIsInFront: a terminal is in front, and the session is not VS Code. */
export const isTerminalInFront = (raw: string, source: 'cli' | 'vscode' | 'unknown') =>
  source !== 'vscode' && TERMINALS.has((raw.split(',')[5] ?? '').toLowerCase())

export const claudeIsInFront = (source: 'cli' | 'vscode' | 'unknown') => isTerminalInFront(lastRawResult, source)
```

Same inputs, same output as today. `fullscreen.test.ts` mocks `electron`, `./store`, `./display` and `./mac/helper` only so the file can be imported.

## The workflow (`.github/workflows/test.yml`)

- Name `Tests`. Triggers: `push` on branches `['**']` (not tags, so release tags do not also run it) and `pull_request`.
- `permissions: contents: read`. `concurrency` group per ref with `cancel-in-progress: true`. `timeout-minutes: 10`.
- One job on `ubuntu-latest`: `actions/checkout@v4`, `actions/setup-node@v4` (Node 22, `cache: npm`, same as the release workflow), `npm ci --ignore-scripts`, `npm test`.
- No build, no helper, no release, no secrets, no artifacts.

**Linux or macOS?** Linux does the job. Every test here is plain Node plus jsdom with Electron faked, and `claude.ts` has no macOS only code on the tested paths (`findClaude` is untested). Linux is faster to start and about ten times cheaper per minute than macOS on private repos. If you want a macOS check anyway, it is a one word change (`runs-on: macos-latest`) or a two entry matrix; I recommend adding it only when you start testing the Swift helper or the macOS only code in `main/mac/`.

**Why `--ignore-scripts`**: the `postinstall` runs `electron-builder install-app-deps`, which tries to rebuild native modules and fetch Electron headers, and none of the tests need that. If the first CI run shows a test that does need a script, the fallback is plain `npm ci` with `ELECTRON_SKIP_BINARY_DOWNLOAD=1`.

## Build plan

Build approach: none recorded in `CLAUDE.md`, so this uses a Tracer Bullet: one thin test through every layer first (mocks, temp dirs, real server, real file), then thicken. Run `npm test` first and confirm the baseline (3 files, 17 tests, green).

1. In `vitest.config.mts` change `include` to `['renderer/**/*.test.{ts,tsx}', 'main/**/*.test.ts']`. Confirm the renderer tests still pass, satisfies **AC-12**.
2. Create `main/ipc/claude.test.ts` with the shared setup and only the regression test (AC-2 steps 1 to 4). Run it, then do the mutation check by hand, satisfies **AC-2**, **AC-10**.
3. Add the port fallback test and the AC-2 busy port variant, satisfies **AC-1**, **AC-2**.
4. Add sync shape and other tools tests (idempotent, foreign hooks, disable, invalid JSON, backup), satisfies **AC-3**, **AC-4**, **AC-5**.
5. Add reply shape tests (question allow with several answers, multi select join, permission allow and deny, pass, bad choice stays queued, AskUserQuestion on the permission route), satisfies **AC-6**, **AC-7**.
6. Add gate tests (401, 403, 404, 405, event reply and session listing), satisfies **AC-8**.
7. Add the skip wiring tests in `claude.test.ts` (skipped when `claudeIsInFront` returns true, queued when false, and the mock is called with `'vscode'` for a session whose transcript says `claude-vscode` and `'cli'` for `cli`), satisfies **AC-9**.
8. Make the production edit in `main/fullscreen.ts`, then create `main/fullscreen.test.ts` for the pure rule, satisfies **AC-9**, **AC-12**.
9. Create `.github/workflows/test.yml`. Check it locally with `npm ci --ignore-scripts && npm test` in a clean checkout, satisfies **AC-11**.
10. Confirm no test touched real state: run the suite with `HOME` pointed at an empty folder and check nothing new appears there, and that port 47821 is never bound, satisfies **AC-10**.

Files this spec will create: `main/ipc/claude.test.ts`, `main/fullscreen.test.ts`, `.github/workflows/test.yml`. Files it will edit: `vitest.config.mts`, `main/fullscreen.ts` (the export above). `main/ipc/claude.ts` is not edited.

## Consequences

**Positive**:
- The silent failure that cost you a real bug is now caught on every push.
- Reply shapes become a written contract, so a refactor of `answer` cannot quietly change what Claude receives.
- Tests double as living documentation of how the hook entries should look.

**Negative / tradeoffs**:
- Real sockets and a per test module reset make these tests slower and more delicate than pure unit tests (expect a few seconds, not milliseconds).
- The tests know the exact reply JSON, so an intentional change to a reply shape means updating the test too (that is the point, but it is a cost).
- The fake Electron setup is a small piece of test code to keep in step if `claude.ts` starts using more Electron.

**Neutral**:
- The 60 second fall through timer, the 5 second session scan, the hold and hover logic, `chat`, `send` and `findClaude` are not covered by this spec.
- `vitest.config.mts` now runs two kinds of test, jsdom by default and Node by file docblock.

## Follow-up

- [ ] Heads up: the `claude.ts` fix and the `CompanionTile.tsx` change are still uncommitted. Commit them (your call, I will not run git) so CI has something to run against.
- [ ] Add an exhaustion test (all 20 ports busy returns no server) once there is a cheap way to find 20 free consecutive ports.
- [ ] Cover the 60 second fall through and the hold and hover pause with fake timers.
- [ ] Add `macos-latest` to the workflow when tests for `main/mac/` or the Swift helper arrive.
- [ ] After the first green CI run, confirm `--ignore-scripts` was enough; if not, switch to the `ELECTRON_SKIP_BINARY_DOWNLOAD=1` fallback above.
- [ ] `CLAUDE.md` says `vitest.config.mts` "only includes renderer today"; `/sync` should update that line after this lands.
