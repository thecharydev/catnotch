# Verify: Claude Code notch popup · spec 0002 · updated 2026-10-28
_Steps derived from spec 0002 acceptance criteria. `/check verify` runs these; `/test` locks the durable ones._

## UI / manual
- [ ] Settings, General, switch on "Claude Code popups" → a preview of the two hook entries shows with Add hooks / Cancel; Cancel changes nothing → AC-1
- [ ] Click Add hooks → `~/.claude/settings.json` has the two entries, every other key is unchanged, and `settings.json.deskNotch.bak` exists → AC-1
- [ ] Switch it on again, then off → entries are never duplicated, and after off only ours are gone; the backup file is not rewritten → AC-1, AC-2
- [ ] Break `settings.json` (invalid JSON), then switch on → file untouched and the snippet to paste by hand is shown with a Copy button → AC-2
- [ ] Start a new Claude session in a terminal, ask it to run `touch x` → the notch opens within 1 s with tool badge, project folder name and the command, and keyboard focus stays in the terminal → AC-3
- [ ] Click Allow → the command runs with no terminal prompt → AC-4
- [ ] Repeat and click Deny → Claude says it was "Denied from DeskNotch" and carries on → AC-4
- [ ] Repeat and click "Ask in terminal" → the popup closes and the terminal prompt appears at once → AC-4
- [ ] Repeat and do nothing → after 30 s the popup closes and the terminal prompt shows → AC-5
- [ ] Quit DeskNotch and ask Claude to run a command → the normal prompt shows, no delay or error → AC-6
- [ ] Run a command with 8+ lines → 6 lines show with "Show all 8 lines", and it expands → AC-3
- [ ] Run two Claude sessions in different folders and trigger both → "1 of 2" with each folder name, oldest first, answering one shows the next → AC-8
- [ ] Ask Claude a question with options → options show; tapping one answers it; Claude reports that answer → AC-9
- [ ] Ask a multi select question → a Confirm button appears and the answer joins the chosen labels → AC-9
- [ ] Ask a question with several parts → they show one at a time → AC-9
- [ ] Ask one question → only one popup appears, not two → AC-13
- [ ] Turn on Hide in fullscreen, put a video fullscreen, trigger a request → the notch appears over it and hides again after → AC-10
- [ ] Occupy port 47821 (`nc -l 47821`), start DeskNotch with the switch on → it uses 47822 and the hook entries now say 47822 → AC-11
- [ ] Interrupt Claude (Esc) while a popup waits → the popup disappears → AC-12
- [ ] Repeat the main flow on Windows and from the VS Code extension; set `CLAUDE_CONFIG_DIR` and confirm that folder's `settings.json` is the one edited → AC-14

## Commands
- [ ] `curl -i -XPOST http://127.0.0.1:47821/desknotch/permission -d '{}'` (no token) → 401, nothing on screen → AC-7
- [ ] same with `-H 'Authorization: Bearer <token>' -H 'Host: evil.com'` → 403 → AC-7
- [ ] `curl -i http://127.0.0.1:47821/desknotch/permission` (GET) → 405; a wrong path → 404; a body over 1 MB → 413 or a reset → AC-7
- [ ] `npx tsc --noEmit -p tsconfig.json` and `cd renderer && npx tsc --noEmit -p tsconfig.json` → no errors → all

## Value sourcing (one per row of the spec table)
- [ ] Tool badge equals `tool_name` for Bash, Edit and an MCP tool → AC-3
- [ ] Project name equals the folder name of `cwd`; with no `cwd` it reads "Claude" → AC-3, AC-8
- [ ] Command line: Bash shows `command`; Edit/Write/Read show `file_path`; another tool shows its input as JSON cut to 300 characters → AC-3
- [ ] "1 of N" follows arrival order → AC-8
- [ ] Question text, option labels, descriptions and multi select flag match what Claude sent → AC-9
- [ ] Answer key is the exact question text; multi select value is the labels joined by a comma → AC-9
- [ ] Deny message is exactly "Denied from DeskNotch" → AC-4
- [ ] Hook URL host and port equal 127.0.0.1 and the stored port; the token equals the stored token; timeout is 35 → AC-1, AC-11
- [ ] With `CLAUDE_CONFIG_DIR` set the file edited is `$CLAUDE_CONFIG_DIR/settings.json`, else `~/.claude/settings.json` → AC-14
- [ ] Fullscreen override is on exactly while a request is waiting → AC-10

## Acceptance-criteria coverage
- AC-1 … steps 1 to 3 · AC-2 … 3, 4 · AC-3 … 5, 11 · AC-4 … 6 to 8 · AC-5 … 9 · AC-6 … 10 · AC-7 … commands 1 to 3 · AC-8 … 12 · AC-9 … 13 to 15 · AC-10 … 17 · AC-11 … 18 · AC-12 … 19 · AC-13 … 16 · AC-14 … 20
