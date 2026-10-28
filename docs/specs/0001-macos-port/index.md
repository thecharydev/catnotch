# 0001. Port DeskNotch to macOS behind platform adapters

**Date**: 2026-10-28
**Status**: In Progress

## Summary

DeskNotch gets a macOS version from the same repo as the Windows app. The React notch UI stays shared, and every place that talks to Windows gets a macOS twin chosen by `process.platform`. On a notched MacBook the notch grows out of the real hardware cutout; on any other screen it is the same pill as today. Mac users install it from a free unsigned DMG or a Homebrew cask, so it does not need a paid Apple account.

## Requirements

**User stories**:
- As a Mac user, I want the notch to appear at the top of my screen and open on hover, so that it feels like part of the machine.
- As a MacBook user, I want it to wrap the real notch, so that it looks native and does not overlap the cutout.
- As a Mac user, I want now playing, the Shelf, screenshots, status moments, most used apps, usage and AI limits to work like the Windows version, so that I do not lose features.
- As a maintainer, I want one repo and one release, so that a fix lands on both platforms once.
- As a Mac user, I want one command or one download to install it, so that I can try it in a minute.

**Acceptance criteria** (the contract, each independently checkable):
- **AC-1**: On macOS 13 or newer, the packaged app launches with no Dock icon and no app switcher entry, draws one notch window per target display (the existing `selectedDisplayId` setting), opens on hover, and never blocks clicks outside the notch rectangles.
- **AC-2**: On a display with a hardware notch, the closed notch matches the cutout width and height reported by the helper and sits flush with it. On a display with no notch, it renders the existing pill.
- **AC-3**: Now playing shows title, artist, artwork, play state and position for any player that macOS reports (Spotify, Music, Chrome, VLC). Play/pause, next and previous work, and tapping the artwork brings the player forward.
- **AC-4**: The Shelf accepts dropped files, drags the real file out, opens it, reveals it in Finder, and shows thumbnails. Recent shows files opened in the last 7 days, newest first, 12 at most.
- **AC-5**: A new screenshot (any system language, saved to the folder in `com.apple.screencapture`, default Desktop) opens the capture card within 2 s of the file being complete. Discard moves it to the Trash. Keep, open and drag out work.
- **AC-6**: The orange dot appears while any microphone input is running and the green dot while any camera is running, and a moment says "Microphone" or "Camera". Both clear within 3 s of stopping.
- **AC-7**: A Wi-Fi connect moment shows the network name when Location is allowed, and a plain "Wi-Fi" moment when it is denied. A Bluetooth connect moment shows the device name and battery percentage when the device reports one.
- **AC-8**: The headphones and battery moments work unchanged (they use Chromium, not Windows).
- **AC-9**: Most used shows the top 4 apps by Spotlight launch count with real names and icons, and tapping one launches it. Favourites can be picked from the installed apps list.
- **AC-10**: The Usage face shows CPU, memory and GPU load. GPU is the device utilisation figure from the graphics driver.
- **AC-11**: With Hide in fullscreen on, the notch hides on a display showing a full screen app, and returns when it leaves. With Shrink over browsers on, the notch tucks while a listed browser is frontmost on that display.
- **AC-12**: AI limits reads the Claude sign in from the Keychain only after the user agrees on the existing consent page, and the Codex sign in from `~/.codex/auth.json`. Declining, or an empty Keychain, shows the same "unavailable" state as Windows.
- **AC-13**: Mica draws the current wallpaper, with no permission prompt. Turning Glass on first explains the Screen Recording permission, then requests it. If denied, Glass falls back to Mica and says so in Settings.
- **AC-14**: Start at login works from Settings for the installed app, Quit closes the app, and the screen time tile (ScreenWise) is not shown on macOS.
- **AC-15**: A failing or missing helper, adapter or permission disables only the feature that needs it. The notch, tasks, focus and Shelf keep working, and nothing crashes the main process.
- **AC-16**: Pushing a version tag runs GitHub Actions on a macOS runner and attaches a universal (Apple Silicon and Intel) DMG, a zip and `latest-mac.yml` to the release. `brew install --cask` from the project tap installs and opens that build.
- **AC-17**: On macOS the app never downloads or installs an update by itself. When a newer release exists, Settings shows the new version and the line `brew upgrade --cask desknotch`.
- **AC-18**: The Windows build is unchanged in behaviour. `npm install` and `npm run dev` succeed on macOS, and no macOS module is loaded on Windows.

## Decision

**Chosen option**: Option 1: One repo, platform adapters, one bundled Swift helper

Keep the renderer and the IPC channel names as they are, branch each Windows only seam in `main/` on `process.platform`, and implement the macOS side with a Swift helper (system state), a MediaRemote adapter (media) and Electron or Spotlight where they are enough.

**Implementation skills**: none installed apply. `renderer/AGENTS.md` carries the Next.js 16 rule: read `node_modules/next/dist/docs/` before touching renderer code.

**Fixed choices from the engineer**: one repo with adapters; wrap the real notch with a pill fallback; full parity as the goal; unsigned DMG plus Homebrew cask; MediaRemote adapter for media; one Swift helper printing JSON lines; Spotlight use counts for most used; Keychain read through `security` after consent; Glass asks for Screen Recording only when turned on; Location asked only when the Wi-Fi moment is on; universal DMG built on GitHub Actions; macOS 13 minimum; Hide in fullscreen follows the existing setting.

**Decisions made in this spec** (each: pick, why, runner up):
- **Mic and camera moments carry no app name on macOS.** macOS exposes which device is running, not which app. Runner up: scrape `log stream` for the Control Center subsystem (fragile across versions, rejected).
- **Bluetooth state from `system_profiler SPBluetoothDataType -json` inside the helper**, every 30 s. It needs no Bluetooth permission and reports battery. Runner up: IOBluetooth (adds a permission prompt).
- **Screenshot detection by the `kMDItemIsScreenCapture` Spotlight flag**, not the file name, so any language works. Runner up: name prefix match (breaks on non English systems).
- **Recent files from Spotlight** (`kMDItemLastUsedDate` in the last 7 days, under the home folder, no `Library`). Runner up: the Finder shared file list (private format).
- **Wallpaper path from `NSWorkspace.desktopImageURL` in the helper**, decoded with `nativeImage` (handles HEIC). Runner up: AppleScript (needs an Automation prompt).
- **Update behaviour:** `electron-updater` with `autoDownload = false`, used only to learn the newest version, because installing needs a signed app. Runner up: a plain GitHub API call (more code, same result).
- **The helper ships inside `DeskNotchHelper.app`** (own `Info.plist`, `LSUIElement`), because Location permission cannot be requested by a bare command line tool. See Follow-up risk 1.
- **Platform seam:** the Windows code stays where it is. Each seam gets `if (process.platform === 'darwin') return mac.x()`, and macOS code lives in `main/mac/`. No shared interface file until a third platform exists.
- **Build approach:** none is recorded in the project, so this plan assumes Tracer Bullet (thin end to end slices, thickened one by one).

## Feature design

**Seams and their macOS replacement** (every row is one existing file that gets a branch):

| Seam (existing file) | Windows today | macOS replacement | AC |
|---|---|---|---|
| `main/main.ts` window | `type: 'toolbar'`, `skipTaskbar`, `setVisibleOnAllWorkspaces(true)` | `type: 'panel'`, level `screen-saver`, `setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })`, `app.dock.hide()`, `LSUIElement` | 1 |
| `main/display.ts` | strip at `display.bounds` | same, plus `notch:hardware` size per display from the helper | 1, 2 |
| `main/smtc.ts`, `smtc-worker.ts` | `windows-smtc-monitor` in a worker | `main/mac/nowplaying.ts` spawns the adapter, emits the same `smtc:now-playing` shape | 3 |
| `main/ipc/media.ts` | `keybd_event` and `user32` | adapter `send` for transport keys, `open -b <bundleId>` to focus | 3 |
| `main/ipc/files.ts` `RECENT` | Recent folder `.lnk` files | Spotlight query | 4 |
| `main/ipc/screenshots.ts` | `Pictures\Screenshots` | folder from `defaults read com.apple.screencapture location` | 5 |
| `main/ipc/privacy.ts` | PowerShell: ConsentStore, `netsh`, PnP | helper events `mic`, `camera`, `wifi`, `bluetooth` | 6, 7 |
| `main/ipc/apps.ts` | UserAssist, `AppsFolder`, C# icons | `mdfind`, `mdls`, `app.getFileIcon`, `shell.openPath` | 9 |
| `main/ipc/usage.ts` | GPU perf counter in PowerShell | helper `gpu` command (IOKit `IOAccelerator`) | 10 |
| `main/fullscreen.ts` | PowerShell C# helper | helper `foreground` events (`NSWorkspace` plus `CGWindowListCopyWindowInfo`) | 11 |
| `main/ipc/limits.ts` | `~/.claude/.credentials.json` | `security find-generic-password -s "Claude Code-credentials" -w` | 12 |
| `main/ipc/system.ts` | wallpaper file, `getAccentColor` | helper `wallpaper`, same accent call, `getMediaAccessStatus('screen')` | 13 |
| `main/ipc/desktime.ts` | ScreenWise SQLite | not available, tile hidden | 14 |
| `main/ipc/settings.ts` | login item, Store build flag | `setLoginItemSettings`, Store flag false | 14 |
| `main/updater.ts` | download and install | check only, show the `brew` line | 17 |

**Swift helper protocol** (`native/mac/`, built to `DeskNotchHelper.app`, universal):
- Started lazily by main, one process, killed on quit, and it exits by itself when its parent process is gone (same rule as the PowerShell watchers).
- Output: one JSON object per line, only when a value changed: `{"t":"notch","display":<CGDirectDisplayID>,"w":<pts>,"h":<pts>}` (zero means no notch), `{"t":"mic","on":bool}`, `{"t":"camera","on":bool}`, `{"t":"wifi","ssid":string|null,"connected":bool,"location":"granted"|"denied"|"unknown"}`, `{"t":"bluetooth","devices":[{"name","connected","battery"|null}]}`, `{"t":"foreground","fullscreen":bool,"display":<id>,"bundle":string}`.
- Input: one JSON line per request, `{"id":n,"cmd":"gpu"|"wallpaper"|"requestLocation"}`, answered by `{"id":n,...}`.
- Cadence: mic and camera on CoreAudio and CoreMediaIO property listeners (no polling), foreground on `NSWorkspace` notifications plus a 300 ms check only while a setting needs it, Wi-Fi on a CoreWLAN event, Bluetooth every 30 s.

**MediaRemote adapter**: the `mediaremote-adapter` project, vendored as a built resource, run through `/usr/bin/perl` (Apple's signed perl keeps the private MediaRemote entitlement). It streams JSON for the current session (title, artist, album, artwork as base64, playing, elapsed, duration, bundle id) and accepts `send play|pause|next|previous`. `main/mac/nowplaying.ts` maps that to the `toNowPlaying` shape the renderer already reads.

**State transitions**: none new. Settings stay in the existing JSON store (`main/store.ts`). No data model change.

**Value sourcing** (every value an action shows, and where it comes from):
| Action | Value | Source |
|---|---|---|
| Size the closed notch | hardware notch width and height | helper `notch`, from `NSScreen.safeAreaInsets.top` and the auxiliary top left and right areas; display matched by `CGDirectDisplayID` equal to Electron's `display.id` |
| Now playing | title, artist, artwork, position, duration, bundle id | adapter JSON stream |
| Open the player | bundle id | adapter, validated against `^[\w.-]+$` before `open -b` |
| Screenshot card | file path | `fs.watch` on the folder from `defaults read com.apple.screencapture location`, else `~/Desktop`; accepted when `mdls -name kMDItemIsScreenCapture` is 1 |
| Recent row | file path, name, opened date | `mdfind` then `mdls kMDItemLastUsedDate` |
| Privacy dots | mic and camera running | helper `mic`, `camera` |
| Privacy moment text | "Microphone" or "Camera" | fixed strings (no app name exists on macOS) |
| Wi-Fi moment | network name | helper `wifi`, only when `location` is `granted` |
| Bluetooth moment | device name, battery | helper `bluetooth` from `system_profiler` |
| Most used | app path, name, launch count | `mdfind` over `/Applications`, `/System/Applications`, `~/Applications`, then `mdls kMDItemDisplayName kMDItemUseCount` |
| App icon | PNG | `app.getFileIcon(appPath, { size: 'large' })` |
| Launch an app | app path | a path main itself listed, never one from the page |
| Usage GPU | percent | helper `gpu` |
| Fullscreen hide | fullscreen flag, display | helper `foreground`, display id matched to `notchWindows()` keys |
| Tuck for browsers | frontmost bundle id | helper `foreground`, compared with a bundle id set in `main/fullscreen.ts` (Safari, Chrome, Edge, Firefox, Brave, Arc, Opera, Vivaldi) |
| AI limits, Claude | OAuth token | Keychain item `Claude Code-credentials`, JSON key `claudeAiOauth`, read only after consent |
| AI limits, Codex | token | `~/.codex/auth.json` |
| Mica | wallpaper image | helper `wallpaper` path, decoded by `nativeImage`, resized to 1600 px wide |
| Glass allowed | permission state | `systemPreferences.getMediaAccessStatus('screen')` |
| Update notice | newest version | `electron-updater` check with `autoDownload = false` |

**Key invariants**:
- The renderer stays untrusted: no new `window.bridge` functions beyond `notch:hardware` and a permissions status channel; every new handler validates its input.
- No string built shell commands from page input. Bundle ids and paths are validated, and `execFile` is used with an argument array, never a shell string.
- Nothing slow runs on main's event loop. All macOS work is a child process (helper, adapter, `mdfind`, `mdls`, `security`).
- A macOS module is loaded only when `process.platform === 'darwin'`, so Windows startup cost and behaviour do not change.

**Security model**:
- The Keychain read is a deliberate, user consented action. macOS shows its own "allow" prompt on first read. The token stays in main and goes only to the provider's own endpoint, as on Windows.
- Permissions the app may request, each only when its feature is turned on: Location (Wi-Fi name), Screen Recording (Glass), Keychain access (Claude limits). It requests no Accessibility, Full Disk Access, Bluetooth or Automation permission.
- The app is ad hoc signed only. It is not notarized, so see Consequences for what that costs.

**Configuration required**:
- `NSLocationUsageDescription` and `NSLocationWhenInUseUsageDescription` in the helper's `Info.plist`, plus `LSUIElement` in both plists.
- Electron Builder `mac` block: targets `dmg` and `zip`, `arch: universal`, `minimumSystemVersion: 13.0`, `identity: null` with ad hoc signing, `extraResources` for the helper bundle and the adapter.
- GitHub Actions secrets: a token that can push to the Homebrew tap repo (`HOMEBREW_TAP_TOKEN`). No Apple secrets.

**Critical test scenarios** (each maps to an acceptance criterion):
- Happy path: install the DMG on a notched MacBook, launch, hover, play a Spotify track, drop a file on the Shelf, take a screenshot. Verifies **AC-1, 2, 3, 4, 5**.
- Non notched display: plug in an external monitor set to "All". It shows the pill and the notch window follows the display. Verifies **AC-1, 2**.
- Failure: delete the helper binary, then launch. The notch, tasks and Shelf work, and the helper dependent features show their empty state. Verifies **AC-15**.
- Permission denied: deny Location, then join a Wi-Fi network. The moment says "Wi-Fi" with no name. Deny Screen Recording, turn Glass on. It falls back to Mica. Verifies **AC-7, 13**.
- Auth and consent: decline the AI sign in consent. No `security` process is spawned. Verifies **AC-12**.
- Full screen: put a video in full screen on the notch's display. The notch hides, then returns on exit. Verifies **AC-11**.
- Regression: build and run the Windows app. Behaviour is unchanged. `npm install` on a clean macOS clone succeeds. Verifies **AC-18**.
- Release: push a test tag on a fork. The workflow attaches the DMG, and the cask installs it. Verifies **AC-16**.

## Build plan

Ordered by Tracer Bullet: the first three tasks prove a thin thread from source to an installed, running Mac app, then each feature thickens it.

1. Make `npm install` and `npm run dev` work on macOS: move `@coooookies/windows-smtc-monitor` to `optionalDependencies`, load it only on win32, replace the Windows only `set NEXTRON_NO_RESTART=1` with `cross-env`, make `scripts/patch-nextron.cjs` safe on macOS. Satisfies **AC-18**.
2. Mac notch window: the `main/main.ts` window options, `app.dock.hide()`, the `LSUIElement` plist key, and a `process.platform` branch for the Store flag in `settings.ts` and `updater.ts`. Result: the existing UI hovers open on a Mac with no features behind it. Satisfies **AC-1, 14**.
3. Packaging thread: the `mac` block in `electron-builder.yml`, a universal DMG and zip, and a GitHub Actions workflow on tag pushes (macOS runner, upload to the release). Install the result on a clean Mac. Satisfies **AC-16, 17, 18**.
4. Swift helper skeleton in `native/mac/`: `DeskNotchHelper.app`, the JSON line protocol, `main/mac/helper.ts` (spawn, parse, restart on crash, kill on quit, parent exit check), the build script, universal build, and the `notch` event. Wire `notch:hardware` into the renderer so the closed notch matches the cutout. Satisfies **AC-2, 15**.
5. Now playing: vendor and build the adapter, add `main/mac/nowplaying.ts`, the transport keys and the open player branch in `media.ts`. Satisfies **AC-3**.
6. Shelf and screenshots: Spotlight Recent in `files.ts`, the folder lookup and `kMDItemIsScreenCapture` check in `screenshots.ts`. Satisfies **AC-4, 5**.
7. Foreground events and fullscreen: helper `foreground`, the macOS branch in `fullscreen.ts`, the browser bundle id set. Satisfies **AC-11**.
8. Most used and favourites: `mdfind` and `mdls` listing, icons, launch by path, in `apps.ts`. Satisfies **AC-9**.
9. Status moments: helper `mic`, `camera`, `bluetooth`, `wifi`, the macOS branch in `privacy.ts`, the Location request, and the renderer's no app name wording. Satisfies **AC-6, 7, 8**.
10. Usage: helper `gpu` and the macOS branch in `usage.ts`. Satisfies **AC-10**.
11. AI limits: the Keychain read after consent in `limits.ts`. Satisfies **AC-12**.
12. Mica and Glass: helper `wallpaper`, the permission check and request flow, the Settings message on denial. Satisfies **AC-13**.
13. Updater notice and login item: `autoDownload = false` branch, the `brew upgrade` line in Settings, `setLoginItemSettings`. Satisfies **AC-14, 17**.
14. Homebrew tap: create the tap repo, the cask file (`depends_on macos: ">= :ventura"`, `postflight` removes the quarantine flag), and a workflow step that updates the cask version and checksum on each release. Satisfies **AC-16**.
15. Docs: a macOS section in `README.md`, a macOS chapter in `doc/HowItWorks.md` (what replaces each Windows mechanism, the permissions list, the mic app name gap), and the first run Gatekeeper steps for people who do not use Homebrew. Satisfies **AC-16**.

## Migration plan

**Strategy**: feature flagged by platform. The change is additive, and the Windows path is untouched.
**Phases**:
1. Tasks 1 to 4: an installable Mac app with the notch and the cutout, no features.
2. Tasks 5 to 13: features, one pull request each, in the order listed.
3. Tasks 14 and 15: Homebrew and docs, then the first public Mac release.
**Rollback**: every macOS change sits behind `process.platform === 'darwin'`, so reverting a pull request cannot affect Windows. A bad Mac release is withdrawn by deleting its release assets and the cask version.
**Risks**: see Follow-up.

## Consequences

**Positive**:
- One codebase and one set of fixes for both platforms.
- The renderer, the settings store and all IPC names are reused, so most of the UI is free.
- No paid Apple account and no native Node addons to rebuild per Electron version.
- Any player works for media, as it does on Windows.

**Negative / tradeoffs**:
- **Unsigned means friction.** Without Homebrew, macOS shows a block on first open, and since macOS 15 the user must go to System Settings, Privacy and Security, then "Open Anyway". The cask strips the quarantine flag to avoid this, so the cask is the recommended path.
- **Permissions can reset on every update.** macOS ties Screen Recording and Location approval to the app's code signature, and an ad hoc signature changes with each build. After each upgrade the user may have to approve again. A paid signing identity fixes this.
- **No in app auto update.** Users update with `brew upgrade --cask desknotch` or by downloading a new DMG.
- **Not full parity on one point:** the mic and camera moment cannot name the app.
- **The now playing path rests on a private Apple API.** It already needed a workaround on macOS 15.4, and Apple can close it.
- A Swift helper and a Mac CI runner add a build step the Windows only team has not had.
- Homebrew has said it will stop accepting casks that fail Gatekeeper in its main repository (check the current date). This plan uses the project's own tap, which is not affected.

**Neutral**:
- Every notched MacBook is Apple Silicon, but the universal build keeps Intel Macs working with the pill.
- The ScreenWise screen time tile stays Windows only.

## Follow-up

- [ ] **Risk 1, spike before task 9:** confirm that a nested `DeskNotchHelper.app`, ad hoc signed and spawned by Electron, can show the Location prompt and read the SSID on macOS 14 and 15. If not, drop the Wi-Fi name and keep the plain "Wi-Fi" moment.
- [ ] **Risk 2, spike in task 2:** confirm the notch window can overlap the menu bar and the cutout at `screen-saver` level on macOS 13, 14 and 15, including over a full screen Space.
- [ ] **Risk 3, spike in task 5:** confirm the adapter returns data on the newest macOS release available to you, and decide a fallback message for when it stops working.
- [ ] **Risk 4, spike in task 12:** confirm `setContentProtection(true)` keeps the notch out of the Glass capture on macOS 15 and later. If it does not, Glass needs a different exclusion method.
- [ ] Verify the Keychain service name `Claude Code-credentials` and its JSON shape against a current Claude Code install before task 11.
- [ ] Consider notarization later (the $99 Apple account). It would remove the Gatekeeper friction, keep permissions across updates, and allow real auto update.
- [ ] Add a one line macOS pointer to `AGENTS.md` once it exists (`/audit` owns it); `renderer/AGENTS.md` is Next.js only.
- [ ] No `docs/scope/` row exists for this work. Enroll it with `/scope` if you want the tasks tracked there.

## Rationale

Reasoning and options: see [rationale.md](rationale.md).
