# DeskNotch — functionality

Every feature, built or planned. Status marks what exists today, not what is intended.

**Status:** `[ ]` planned · `[~]` in progress · `[x]` done

Anything under Behaviour is togglable from the settings panel. None of it is
fixed — the user decides what runs.

---

## Collapsed bar

The always-visible strip, a fixed 240px. Space is tight, so these are glanceable indicators rather than controls. One thing at a time on the left, most urgent first.

- [x] **Focus countdown**: a tiny ring and the time left, while a session runs.
- [x] **Now playing**: album art and a pulse (no title: too much for the bar); the glance card shows art, title, a rounded progress bar in the cover's colour (dims when paused, a light sweeps along it when the length is unknown; no minutes and seconds since Windows reports position only every few seconds) and controls. Tap the art to bring the player forward, maximised.
- [x] **Time**: 12-hour, on the left whenever no session or music is running.
- [x] **Right of the bar**: the time, the AI limits as two rings (weekly outside, 5-hour inside) and `5h% / 7d%`, orange past 80%, or today's **screen time** from [ScreenWise](https://www.bruhlabs.top/download). Settings → Closed notch picks which; the time is not shown twice. Screen time is greyed out, with a **Get ScreenWise** link, until ScreenWise is installed.
- [x] **Privacy dots**: orange while any app uses the microphone, green for the camera, from Windows' own ConsentStore records.
- [x] **Just connected moments**: headphones, a Wi-Fi network or a Bluetooth device connecting takes the bar for about a second and a half (icon, name, "Connected"), then it returns. No permanent Wi-Fi or Bluetooth icons.
- [x] **AI usage**: plan limits for Claude (session, week) and Codex (its plan's windows), % used, from the same endpoints as `/usage` and `/status`. A failed read keeps the last good one (saved across restarts) and backs off after a rate limit.
- [ ] **Weather icon**: current conditions at the user's location.
- [ ] **Battery**: charge level and charging state.
- [ ] **Bluetooth device battery**: headphones, mouse, controller.
- [ ] **Laptop temperature**: glanceable CPU/chassis thermal readout or warning icon when running hot.

## Expanded

Shown when the notch opens. Room for real controls.

- [x] **Companion**: a bot (or the user's photo) in one mode at a time, each with its own look and body language:
  - **Focus**: a timer in the companion's colour. `›` opens every length (1 to 60 minutes) and a custom one in minutes and seconds (5 s to 3 h, then Set). One pill starts, pauses, resumes; reset beside it. While it runs, a breathing dotted ring around the bot lights up clockwise and the bot watches its lit edge.
  - **Reminder**: the next reminder's time, big, and its message. Tap to open the list (removable) beside a New reminder form: the time picker, an optional message, and 10 min / 30 min / 1 hour shortcuts. When one comes due, the notch opens on it by itself for a minute: the companion rings (ripples and a swinging bell), with Got it and Snooze 5 min. A reminder missed while the app was closed rings when it opens. Replaced the Tasks mode (a saved Tasks mode becomes Reminder).
  - **Time**: clock and date; tap to open the day as a wave with the sun (or moon) riding it and the daylight left.
  - **Screen time**: today's total from ScreenWise as a big figure (replaced the AI mode; a saved AI mode becomes this). Greyed out in Settings without ScreenWise.
  - Still unless hovered; then it looks at and leans toward what its mode is about. Reacts to moments (a task done, a session starting or ending, a new track). Sleeps 23:00 to 06:00, when idle, or never; in Time mode it keeps the clock's night.
- [x] **Media controls**: play, pause and skip from the glance card, sent as the system media keys; the card glows with the artwork's colour.
- [x] **Todos**: add, tick, delete and clear on the desk (clicking a row ticks it); the next one on the glance, as a Reminders-style card with round checkboxes. Persisted to disk.
- [x] **AI usage monitor**: one card per tool (Claude, Codex), each window a globe filled by % used; hover shows what is left and when it resets; settings picks which windows. A card that cannot be read becomes a retry button.
- [x] **Screenshot catcher**: every capture Windows saves opens the closed notch on it for a few seconds, with a shutter flash: drag it anywhere, rename it (the pencil beside the name opens a field with its own Save; Enter saves, Esc cancels; the extension is kept and an existing name is refused), Save to Shelf, Open it, or Discard it (to the Recycle Bin). A setting.
- [x] **Focus done**: when a session ends, the notch opens on its own card: the bot says "Done!" in a speech bubble, with how long you went and Again / Done.
- [x] **Apps bar**: a tray of apps, one tap to open: Windows' most used (by time in focus, top 12) or any number of favourites picked from every installed app. Four in view under the notch, two beside it; the rest scroll. Position: Auto, Left, Bottom or Right, never the same side as the tabs dock (Auto puts it on the right when the dock is below, else under the notch). On the views chosen in Settings (the Shelf by default).
- [~] **Calendar**: the date leads the time card. No events source yet.
- [ ] **Volume slider**
- [ ] **Stopwatch**
- [ ] **Clipboard history**
- [ ] **Weather**: fuller forecast than the collapsed icon.
- [ ] **Focus / DND toggle**
- [ ] **Notification peek**: notifications surface here instead of the corner.
- [ ] **Laptop temperature & thermals**

## Claude Code popups
- A local server (`main/ipc/claude.ts`, `127.0.0.1:47821`, secret token) receives Claude Code's `PermissionRequest` hook and its `PreToolUse` hook for `AskUserQuestion`. The notch opens on a request (`ClaudeView`) and the click becomes the hook's reply.
- Allow, Deny (Claude is told "Denied from DeskNotch"), Ask in terminal, question options with Confirm for multi select. One at a time, "1 of N".
- Any failure or 30 s of silence is an empty reply, so Claude shows its own prompt. It never takes focus and shows over a fullscreen app while a request waits.
- Settings, General, Claude Code popups adds and removes only our two hook entries in `settings.json` (`CLAUDE_CONFIG_DIR` honoured), after a preview, with a one time `.deskNotch.bak`.
- Spec: `docs/specs/0002-claude-code-notch-popup/index.md`.

## Behaviour

All of these are settings, not hardcoded behaviour.

- [x] **Views**: Glance (up to 4 cards), Desk and Shelf, plus Settings; the dock names them Home, Focus & tasks and Files, with a gear for Settings, a lock to keep it open and a power button to close the app. No top bar when open: the views, settings and the lock are circles on a small dock right against the notch, on the left, right or bottom (Settings → Controls), each naming itself on hover. Every view has the same tight 12px padding. The notch closes only once the pointer is clearly away and still heading away, so a view shrinking under the cursor never closes it.
- [x] **Shelf**: after the Mac notch shelves: drop files anywhere on the notch (even closed, which then opens and locks; a drop on the bar, or while it is still opening, still lands), they sit left to right with thumbnails inside a dashed well, the notch widens per file up to a limit and then scrolls. Drag one out and drop it elsewhere and it leaves the shelf. Clear all sits at the row's end. Recent and Pinned are built but parked (commented out).
- [x] **Desk**: the same companion card as the glance, always in Focus, beside the whole task list; as tall as the glance.
- [x] **Styles**: Default (a soft charcoal) and Glass (a live blur of whatever is behind, under a smoked tint with a hairline edge so it stands out from what it covers). The notch, the dock and the apps tray all wear the chosen material. Glass hides the notch from screenshots and screen sharing while it is on. Mica was removed; a saved Mica becomes Default.
- [x] **Hide tabs**: Glance, Desk and Shelf can each be taken off the dock; Settings and the lock always stay.
- [x] **Long tasks wrap**: on the Home task card and the Focus & tasks list, a long task reads as a paragraph, and the add field grows line by line while typing (Enter adds).
- [x] **GitHub link** — at the bottom of the Settings sidebar, in every section; opens the project's repo.
- [x] **Updates over the air** — from GitHub Releases via `electron-updater`: checked a minute after start and every six hours, downloaded in the background, installed by itself once the PC is idle for a minute or on quit (Settings → General → System shows the version and progress). Installed app only.
- [x] **Tabs size**: Default, Large (1.25×) or Larger (1.5×) dock buttons and icons, for screens where they come out small (e.g. 100% display scaling on a high-resolution laptop). Label text keeps its size.
- [x] **Pin open** — the lock on the dock holds the notch open (clicking the bar no longer does); while locked, the dock and apps bar hide until the pointer is back on the notch, so it does
  not close while typing or reading.
- [x] **Click-through** — the strip only takes clicks over the notch itself;
  everything else passes through to the window underneath.
- [x] **Ambient glow** — a looping light along the bottom edge while music plays.
- [x] **Album tint** — the shell picks up colour from the current artwork.

- [x] **Auto-expand on event**: opens by itself on a finished focus session and on a new screenshot, then folds away (hovering keeps it; using it closes it).
- [ ] **Multi-monitor support** — the notch is pinned to the primary display
  and does not follow a change of monitor.
- [x] **Startup on boot** — registers with Windows via `setLoginItemSettings`, installed app only (a dev run would launch bare Electron at login, so it refuses and clears any old entry).
- [x] **Hide in fullscreen** — hides during true fullscreen (F11, a video's fullscreen button, games) on that monitor only. A maximized window never counts.
- [x] **Hide in screenshots** — off by default; leaves the notch out of screenshots, recordings and screen sharing (Windows' capture exclusion, the same one Glass uses).
- [x] **Shrink over browsers** — off by default. While Chrome, Edge, Firefox, Brave, Opera or Vivaldi is in front, the closed notch shrinks to a 6px sliver so tabs stay visible; hovering it opens the full notch.
- [x] **Close** — a power button right of the lock on the dock quits DeskNotch until it is opened again from the Start menu.
- [x] **Settings panel**: laid out like System Settings: four sections (Notch: home cards / closed notch; Companion; Layout: tabs / apps bar; General: appearance / system), one section at a time as grouped rows: a plain label and one control, with a short note only where the label alone would not say it. New installs open Home on the companion (Clock), Now playing and AI usage. A side taken by the dock or the apps bar is greyed out for the other.
- [ ] **Keyboard shortcut to open** — the notch is hover-only otherwise, so there
  is no way to reach it without the mouse.

---

## What each feature needs

How the built ones reach Windows (media, the player, the shelf, screenshots, privacy dots, Wi-Fi and Bluetooth, most used apps) is drawn out in [HowItWorks.md](HowItWorks.md).

Most of this list needs no native Windows code. Worth knowing before reaching
for a native library.

### Electron built-in

| Feature | API |
|---|---|
| Clipboard history | `clipboard` (main process only) |
| Screenshot tools | `desktopCapturer` |
| Multi-monitor | `screen` |
| Tray + quit | `Tray` |
| Startup on boot | `app.setLoginItemSettings()` |
| Keyboard shortcut | `globalShortcut` |
| Notes, todos, timer, calendar UI, settings | React + a JSON file |

### Plain web APIs

| Feature | API |
|---|---|
| Battery (laptop) | `navigator.getBattery()` |
| Weather | `fetch` against a weather API |
| AI API token tracking | `fetch` against AI provider usage APIs / local Ollama endpoint |

### Needs native Windows access

| Feature | Needs |
|---|---|
| Now playing, media controls | SMTC |
| Volume slider | Core Audio, or a small npm package |
| Headphones connected | Done without native code: the browser's `devicechange` over Windows' audio devices |
| Hide on fullscreen | Win32 window query |
| Mic / camera in-use dot | Done: the ConsentStore registry, read by PowerShell (see caveat) |
| Bluetooth device battery | WinRT — see caveat |
| Laptop temperature | WMI (`MSAcpi_ThermalZoneTemperature`), `systeminformation`, or LibreHardwareMonitor — see caveat |
| Local AI / NPU usage | Windows Performance Counters (PDH) / Task Manager NPU metrics — see caveat |

### Library choice

**`node-windows-smtc-monitor`** for media. Purpose-built, Rust/napi-rs bindings,
event-based rather than polled, and covers both reading now-playing and sending
controls.

**NodeRT** is a general WinRT bridge — powerful, but it generates a module per
Windows namespace and needs a native rebuild against each Electron version. Add
it when a specific feature requires a namespace nothing else wraps, not as a
foundation.

Unrelated but easy to trip over: Electron does not enable Chromium's
`HardwareMediaKeyHandling` and `MediaSessionService` flags, so `mediaSession`
does not register an Electron app as a media source on Windows. That concerns
*publishing* media info, not reading it, and does not affect now-playing.

### Media controls

`@coooookies/windows-smtc-monitor` only *observes* SMTC, so the buttons send
the system media keys instead (`keybd_event` through user32, from one
PowerShell kept alive for the purpose). Every player honours those whether or
not it has focus, and SMTC reports the change back within a moment.

### Features that need caveats or special handling

**Bluetooth device battery.** UWP exposes no battery API for Bluetooth Classic
devices, which is what most headphones are. Web Bluetooth reads battery only
from BLE devices advertising the battery GATT service. No library choice fixes
this — expect partial coverage at best.

**Mic / camera in-use dot.** Windows has no supported API for this. It can be
read from the registry under `CapabilityAccessManager\ConsentStore`, but classic
apps can access the microphone without going through the privacy service and
will not appear there. Best-effort, not reliable.

**Laptop temperature.** Windows exposes no simple, unprivileged API for CPU core
temperatures. `MSAcpi_ThermalZoneTemperature` via WMI often returns static readings
or is unsupported on modern laptop hardware without OEM ACPI drivers; per-core
temperatures usually need ring-0 driver access (e.g. LibreHardwareMonitor or
WinRing0) or a helper tool like `systeminformation`. WMI queries are also
notoriously slow and synchronous, so reading thermals must run in a worker thread
to avoid hitching the notch animation.

**AI usage.** Has two distinct directions with different requirements:
- *Cloud API tokens / spend*: Polling provider usage endpoints (OpenAI, Anthropic,
  Gemini) or a local proxy to track daily tokens and cost limits.
- *Local model / NPU compute*: Querying Windows Performance Counters (PDH) or
  DirectML compute engines to measure active local LLM inference and NPU engine
  utilization.

---

## Ideas

### Announce, then settle (partly built)

When a device connects, show its icon briefly, then let it shrink into a small
persistent dot. The icon says what happened; the dot says it is still true.

The collapsed bar has very little room, so a permanent icon per device does not
scale. An icon that announces itself and then settles into a dot costs almost no
space once the moment has passed.

Bluetooth is the first case. The same shape fits anything that connects,
finishes or changes state — headphones, chargers, a finished timer, a completed
download. Worth building once as a shared component rather than per feature.

Built so far: the announce half, for headphones, Wi-Fi and Bluetooth (the "just connected" moment). Undecided: whether it should settle into a persistent dot, whether dots stack, and what a click on one does.

### Lower priority

- ~~**Pomodoro**~~: built, as the companion's Focus mode.
- ~~**Quick launch**~~: built, as the apps bar's favourites.
- **Themes** — accent color, notch dimensions.
- **Idle auto-collapse** — closes itself after a period untouched.
