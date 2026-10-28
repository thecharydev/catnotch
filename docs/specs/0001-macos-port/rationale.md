# 0001. Port DeskNotch to macOS: decision record

## Context

> ⚠️ Premise note: "Full parity" is not fully reachable. macOS does not say which app is using the microphone or camera, so those moments lose the app name. Unsigned distribution also costs in-app auto update and may reset permissions after each upgrade. This spec goes ahead with both costs stated, because the engineer chose a free install path for open source users.

DeskNotch is an Electron and Next.js app that draws a notch at the top of a Windows screen. Its React interface is platform neutral. Everything that reaches the machine lives in `main/` (about 2,300 lines) and is Windows specific: SMTC for now playing, `keybd_event` for media keys, PowerShell for status, the registry for privacy dots and most used apps, `netsh` for Wi-Fi, a Windows only SQLite file for screen time, and a Windows installer and updater.

The requested outcome is a Mac version for MacBooks, which have a physical notch. The app is open source on GitHub, and the goal is that Mac users can install it easily, without the maintainer paying for an Apple developer account.

Without a decision, the Mac build either does not exist or becomes a copy that drifts from the Windows app. The macOS facts that shape the design: there is no public now playing API (the private one was restricted in macOS 15.4), there is no UserAssist tally, Wi-Fi names need Location permission, screen capture needs Screen Recording permission, Claude Code keeps its sign in in the Keychain, and unsigned apps meet Gatekeeper.

## Options considered

### Option 1: One repo, platform adapters, one Swift helper

Keep the renderer and IPC names. Branch each Windows only seam on `process.platform` and write the macOS side in `main/mac/`, a Swift helper, and a MediaRemote adapter.

**Pros**:
- One codebase, one release, fixes land once.
- Windows risk is low because its code does not move.
- Mirrors the existing design (long lived child process printing one line per change).

**Cons**:
- Seams spread across about 12 files, so reviews must watch for Windows regressions.
- Adds a Swift build and a macOS CI runner.

### Option 2: Fork into a separate Mac repo

Copy the app and rewrite `main/` for macOS.

**Pros**:
- Fastest first commit, no regression risk for Windows.

**Cons**:
- The UI drifts. Every renderer fix is made twice.
- Two release processes for a small team.

### Option 3: Replace Windows with macOS

Delete the Windows code and ship only the Mac app.

**Pros**:
- Smallest code.

**Cons**:
- Abandons existing Windows users and the Microsoft Store listing.

### Option 4: Rewrite as a native SwiftUI app

A new Mac app with native notch handling and APIs.

**Pros**:
- Best fit with macOS, no helper process, smaller memory.

**Cons**:
- Discards the whole UI and animation work. A second app to maintain. Months of work for a feature set that Option 1 reaches faster.

## Rationale

Option 1 fits the forces in Context. The interface is already platform neutral and the Windows code is the only thing that is not, so adapters change exactly the part that must change. A fork (Option 2) buys a faster start but pays for it in every later fix, and the team is small. A native rewrite (Option 4) is the best product on paper but throws away the work that makes DeskNotch look the way it does.

The engineer's choices follow the same logic of reuse and low cost. A Swift helper over native Node addons keeps the existing rule that main never blocks and that the project has no addons to rebuild per Electron version. The MediaRemote adapter is the only route that keeps "any player works", which is the behaviour users see on Windows, even though it rests on a private API. Spotlight for most used gives data on day one with no permission, at the price of ranking by launches rather than focus time.

The engineer chose an unsigned DMG plus a Homebrew cask over notarization. That is a sound start for a free open source tool, but it is the choice with the most lasting cost: no auto update, possible permission resets, and a block on first open for anyone not using Homebrew. It is easy to reverse later, because signing changes only the build step. The spec therefore keeps signing out of the code paths, and lists notarization as a later follow up.

## Evidence from the code

- Window and hit test: `main/main.ts` already uses one full width transparent strip per display with a 60 ms cursor test, which suits a macOS notch (the strip covers the cutout, and the notch is a `div`).
- Windows only touchpoints found by search: `main/smtc-worker.ts`, `main/smtc.ts`, `main/ipc/media.ts`, `privacy.ts`, `usage.ts`, `apps.ts`, `files.ts` (Recent folder), `screenshots.ts`, `limits.ts`, `system.ts`, `desktime.ts`, `fullscreen.ts`, `settings.ts`, `updater.ts`.
- `main/fullscreen.ts` already returns early when `process.platform !== 'win32'`, so the macOS branch is a new implementation, not a fix.
- `package.json` runs `electron-builder install-app-deps` after install and lists a Windows only native package as a normal dependency, which is why task 1 comes first.
- `main/updater.ts` comments that the Windows installer is unsigned and trusted on HTTPS alone. That works for Windows, but macOS will not install an update into an unsigned app, which is why AC-17 is check only.
