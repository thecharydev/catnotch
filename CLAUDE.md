# DeskNotch

A notch style bar at the top of the screen (macOS and Windows) built with Electron and Next.js (via nextron). Hover it and it opens into music, a focus timer, tasks, a file shelf, AI usage, a calendar and Claude Code prompts. Version and release details are in `package.json` and `README.md`.

## Run, build, test

- `npm run dev`: run the app in development.
- `npm run build -- --mac --universal`: build the mac app into `dist/mac-universal/DeskNotch.app`.
- `npm run build:helper`: rebuild the native Swift helper (`native/mac`).
- `npm test`: run vitest once.

## Layout

- `main/`: Electron main process. `main/ipc/` holds one file per feature (claude, calendar, battery, and so on). `main/mac/` holds macOS specific code.
- `renderer/`: the Next.js UI (`pages`, `components`, `hooks`, `lib`). It has its own `AGENTS.md`, read it before editing Next.js code.
- `native/mac/`: Swift helper for calendar and status.
- `docs/specs/`: numbered build specs. Read the matching one before changing a feature.
- `doc/`: older user facing notes.
- `.github/workflows/`: CI and release.

## Easy to miss

- Claude hook server (`main/ipc/claude.ts`): it listens on a local port (47821 and up) and writes hook entries into the user's `~/.claude/settings.json`. The entries must always match the live port, so `startClaudeServer` re-syncs them on every launch. A stale port fails silently and no question reaches the notch.
- A prompt is skipped when a terminal is in front (Claude's own prompt is already visible). VS Code is never skipped.
- `app/` and `dist/` are build output. Do not edit them.
- Never touch the real `~/.claude` in tests. Point `CLAUDE_CONFIG_DIR` at a temp folder.
- Git flow: there is one long lived branch, `main`. There is no `master` and no `dev`.
  - Every change goes on a short branch off `main` (like `fix/something`). Never commit or push straight to `main`.
  - To ship, raise a pull request from that branch into `main`, then delete the branch. Write the PR description with the `/document pr` skill.
  - Always confirm before each step: show the commit message and wait for a yes before `git commit`; wait for a yes before `git push`; wait for a yes before `gh pr create`. Approval for one step does not cover the next.
  - Do not run `git commit`, `git push` or `gh pr create` unless asked for that exact action (`.agents/rules/no_git_push.md`).

## Testing rules

- Framework is vitest (`test-preferences.json`). Tests sit beside the source as `*.test.ts(x)`.
- `vitest.config.mts` only includes `renderer/**` today. Add `main/**` there when you add main process tests.
- Run one file with `npx vitest run path/to/file.test.ts`.

## Specs

New work gets the next numbered file in `docs/specs/` (`/architect` writes it). Keep specs small and name them `NNNN-short-name.md`.
