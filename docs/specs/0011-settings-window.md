# 0011. Move Settings out of the notch into its own window

**Date**: 2026-10-31
**Status**: In Progress

## Summary

Settings stops being a view inside the notch and becomes a normal app window, like Raycast or Vox: a small frosted window with a sidebar of sections and the controls on the right. You open it with a global shortcut (Cmd+Option+, on Mac, Ctrl+Alt+, on Windows) from any app. The notch loses its Settings view completely, so it only shows glance content. Changes still apply live to the notch, because both windows read and write the same saved settings.

## Context

Today Settings is one of the notch views. `home.tsx` has a `'settings'` view, a gear button on the dock, a fixed notch size for it (`SETTINGS_PANE`), and renders `SettingsPanel` (about 1000 lines) inside the notch shape. That means a long list of controls is squeezed into a 620 by 312 pane that has to animate open, and changing the notch style or size while looking at it moves the thing you are editing.

The pieces needed for a separate window already exist. Settings live in the main process store (`desknotch-store.json`) and `store:set` already tells every other window through `store:changed` (`main/ipc/store.ts`), which is how a notch on a second display stays in sync. `SettingsPanel` only takes four props: `settings`, `onChange`, `aiLimits` and `desktimeInstalled`, so it can be hosted by any page that owns those. The app is an accessory app on macOS (`LSUIElement`, `app.dock.hide()`), so it has no Dock icon, no menu bar and is never the focused app by default.

No design tool or `design.md` exists. The design source is the existing `SettingsPanel` sections plus the installed `macos-design-guidelines` and `liquid-glass` skills for window chrome.

## Requirements

**User stories**:
- As a user, I want Settings in its own window so I can change options without the notch resizing around me.
- As a user, I want to open Settings from any app with one shortcut.
- As a user, I want the notch to update as I change a setting so I can see the effect.

**Acceptance criteria**:
- **AC-1**: Pressing the global shortcut (Cmd+Option+, on macOS, Ctrl+Alt+, on Windows) from any app opens the settings window, focused and in front. If it is already open, the shortcut focuses it and does not open a second one.
- **AC-2**: The window is fixed at 720 by 520, not resizable, titled "DeskNotch Settings". macOS: hidden title bar with traffic lights, sidebar vibrancy, dark. Windows: mica material (plain dark background if mica is unsupported) with the standard frame.
- **AC-3**: The window shows the same sections and controls `SettingsPanel` has today, with a sidebar on the left. No control is lost.
- **AC-4**: Changing a setting in the window updates the notch on every display within about a second, with no restart, and a change made elsewhere (another notch window) shows in the window if it is open.
- **AC-5**: The notch no longer has a Settings view: no `'settings'` view id, no `SETTINGS_PANE` size, no gear button on the dock. The Claude sessions "set it up" link opens the settings window instead of the old view.
- **AC-6**: Closing the window with the red button destroys it. The next open creates a fresh one on the first section.
- **AC-7**: macOS: while the window exists the app shows a Dock icon and appears in Cmd+Tab; when it closes the Dock icon hides again and the notch keeps working with no focus change.
- **AC-8**: The settings window is never treated as a notch: it does not get notch hit testing, the notch fullscreen logic, or a notch display sync.
- **AC-9**: Existing saved settings load unchanged (no new setting keys, no renamed ones).
- **AC-10**: If the shortcut cannot be registered (another app owns it), the app still starts and logs the failure; settings can still be opened from the Claude sessions link.

## Options considered

### Option 1: Separate BrowserWindow with a new Next page (chosen)

A new `renderer/pages/settings.tsx` renders `SettingsPanel` in a sidebar layout. The main process creates one `BrowserWindow` for it on demand and loads `/settings`.

**Pros**:
- Reuses `SettingsPanel`, the store, `store:changed` sync and the preload bridge as they are.
- Real window chrome, vibrancy, Dock and Cmd+Tab behaviour come from Electron, not from CSS tricks.
- Notch code shrinks.

**Cons**:
- A second renderer process while it is open (memory cost, only while open).
- Two writers of the `settings` object (see Key invariants).

### Option 2: Make the notch window bigger and show a centered panel

Keep Settings inside the notch window but draw a centered floating panel.

**Pros**:
- One renderer, no new IPC.

**Cons**:
- The notch window is a transparent click through strip with hit testing; a large interactive panel fights that, and it has no real window behaviour (no Dock, Cmd+Tab, focus). Rejected.

### Option 3: Native SwiftUI settings app

**Pros**:
- Most native look.

**Cons**:
- A second codebase, nothing on Windows, and a second place that must read the store. Rejected for cost.

## Decision

**Chosen option**: Option 1: Separate BrowserWindow with a new Next page

Add one main process module that owns a single settings window, a `/settings` page that hosts the existing `SettingsPanel` in a sidebar layout, and remove the Settings view from the notch.

**Implementation skills**: `macos-design-guidelines`, `liquid-glass` (`.agents/skills/`), consulted for window chrome and sidebar styling only.

## Rationale

The notch is built for glanceable content and has a hard problem to solve (clicks through to apps beneath). Settings is the opposite: long, rarely used, wants real window behaviour. The store already broadcasts changes, so the window is mostly wiring. A fixed size with a sidebar avoids resize edge cases and matches how Raycast and Vox look.

Calls made in this spec, with the runner up:
- **Dark only, frosted**: force a dark window so the existing white on dark styles in `SettingsPanel` work unchanged. Runner up: follow the system theme, which means restyling about 1000 lines.
- **Window closes, not hides**: no renderer held in memory. Runner up: hide on close for instant reopen.
- **No separate local Cmd+, handler**: the global shortcut already works when the window is focused. Runner up: an app menu with a Settings item while the Dock icon shows.
- **Settings does its own data**: the page calls `useAiLimits` and `useScreenTime` itself rather than receiving them from the notch.

## Feature design

**Data model sketch**: none new. `settings` in the store keeps its shape (`Settings` in `SettingsPanel.tsx`).

**Windows and surfaces**:
| Surface | Where | Notes |
|---|---|---|
| `main/settingsWindow.ts` | main process | `openSettingsWindow()`: create or focus; owns Dock show/hide; registers the global shortcut |
| `renderer/pages/settings.tsx` | new Next page | loads settings, hosts `SettingsPanel` with sidebar layout |
| IPC `settings-window:open` | `ipcMain.on` | fixed channel, no payload, so the renderer can only open this one window |
| Notch `home.tsx` | edit | remove view, gear, size, hook arg; Claude link calls `settings-window:open` |

**Window options** (macOS / Windows):
- Common: `width 720`, `height 520`, `resizable: false`, `fullscreenable: false`, `minimizable: true`, `title: 'DeskNotch Settings'` (must not equal exactly `DeskNotch`, which `fullscreen.ts` uses to find the notch), `show: false` then `show()` on `ready-to-show`.
- macOS: `titleBarStyle: 'hidden'`, `trafficLightPosition`, `vibrancy: 'sidebar'`, `visualEffectState: 'active'`, transparent background.
- Windows: `backgroundMaterial: 'mica'`, `backgroundColor` dark fallback.
- `nativeTheme.themeSource` is not changed (it would recolor the notch dialogs); the page sets its own dark colors.

**Value sourcing**:
| Action | Value produced / displayed | Source |
|---|---|---|
| Page load | current settings | `store:get 'settings'`, merged over `DEFAULT_SETTINGS` (same merge `home.tsx` does) |
| Control change | saved settings | `store:set 'settings'` (main persists, then announces to other windows) |
| Another window changes settings | updated settings in the window | `store:changed` through `onStoreChange` |
| AI usage controls | provider limits | `useAiLimits` in the settings page |
| ScreenWise availability | `desktimeInstalled` | `useScreenTime(true).installed` in the settings page |
| Display picker | display list | `display:get-all`, `display:changed` (already in `SettingsPanel`) |
| Update row, Claude row, photo, store build flag | as today | already IPC based inside `SettingsPanel` |
| Open at login | applied to OS | `settings:start-on-boot`, called from the notch effect that already does it |

**Key invariants**:
- The `settings` object is replaced whole on save. Two writers could overwrite each other, so: the settings page applies a `store:changed` value before the user's next edit (already how `onStoreChange` works), and saves only after the first load has finished (the `settingsLoaded` guard `home.tsx` uses). The notch and the window never save a value they just received (the existing JSON equality check in `store:set` handles that echo).
- Exactly one settings window exists. `openSettingsWindow` returns the existing one if not destroyed.
- The Dock icon is shown only while the window exists, and hidden again on `closed`, not on `close`, so a cancelled close keeps it.
- The notch Dock hide at startup (`app.dock?.hide()`) still runs first; showing the Dock is the exception, not the default.
- Content protection is applied to all windows by `applyContentProtection()`. The settings window follows `hideInScreenshots`, which is acceptable.

**Security model**: no new capability. The settings window uses the same preload bridge as the notch. The only new IPC channel takes no payload.

**Configuration required**: none. Shortcut is fixed in code (`CommandOrControl+Alt+,`), not a setting.

**Critical test scenarios**:
- Happy path: press the shortcut in another app, the window appears, toggle `showMusic`, the notch glance updates, verifies **AC-1**, **AC-3**, **AC-4**.
- Reopen: press the shortcut twice, only one window; close it, press again, a fresh window on the first section, verifies **AC-1**, **AC-6**.
- Dock: open, a Dock icon appears; close, it disappears and the notch still receives clicks, verifies **AC-7**.
- Sync: with two displays, change style in the window, both notches follow; change a setting from one notch, the open window updates, verifies **AC-4**.
- Notch cleanup: the notch dock has no gear, no `settings` view id exists, the Claude link opens the window, verifies **AC-5**.
- Shortcut taken: pre register the key from another app, start the app, no crash, one log line, verifies **AC-10**.
- Old settings file loads with no key changes, verifies **AC-9**.
- The settings window does not appear in `notchBounds`, is not moved by `syncNotchWindows`, and does not hide when a fullscreen app is active, verifies **AC-8**.

## Build plan

Approach: none recorded, so a Tracer Bullet default. Thin end to end first (shortcut opens a window showing the real panel), then remove the old view, then polish.

1. [x] Add `renderer/pages/settings.tsx`: load and save settings like `home.tsx` does (reuse the load and merge code by lifting it into a small hook `useSettingsStore` in `renderer/hooks/`, used by both pages), render `SettingsPanel` with `useAiLimits(true)` and `useScreenTime(true)`, satisfies **AC-3**, **AC-4**, **AC-9**.
2. [x] Add `main/settingsWindow.ts` with `openSettingsWindow()`, the window options above, the `settings-window:open` handler, the global shortcut (try, log on failure, unregister on `will-quit`), satisfies **AC-1**, **AC-2**, **AC-6**, **AC-10**.
3. [x] Dock show on create and hide on `closed` (macOS only), with `app.focus({ steal: true })` when opening, satisfies **AC-7**.
4. [x] Register it from `main/main.ts` after `app.whenReady`; confirm `display.ts`, `fullscreen.ts` and the notch hit test only act on notch windows, adjusting if they iterate all windows, satisfies **AC-8**.
5. [x] Lay out the page: left sidebar from the existing `SECTIONS` list, content pane on the right, drag region on the top strip (macOS), `-webkit-app-region: no-drag` on controls. If `SettingsPanel` already draws its own section sidebar, reuse it and only restyle the container, satisfies **AC-2**, **AC-3**.
6. [x] Remove from the notch: the `'settings'` view id and size entry, `SETTINGS_PANE`, the gear button, `view === 'settings'` in the `useAiLimits` argument; point the Claude sessions link at `window.bridge.send('settings-window:open')`, satisfies **AC-5**.
7. Run the scenarios above on macOS; run the Windows ones (mica, shortcut, no Dock logic) on a Windows build, satisfies all.

## Consequences

**Positive**:
- Notch code and states shrink (no settings view, no special size).
- Settings gets real window behaviour and room to grow.

**Negative / tradeoffs**:
- With no gear on the notch and no tray icon, the shortcut is the only everyday entry. A user who does not know it has only the Claude sessions link until onboarding mentions it.
- A Chromium renderer runs while the window is open.
- Two windows write the same settings object, so the whole object write race stays a (small) risk.

**Neutral**:
- Cmd+, does not get its own handler; the global shortcut covers it.
- The settings window is always dark, regardless of system theme.

## Follow-up

- [ ] Discoverability: add a gear back on the notch dock, or a tray icon, if people do not find the shortcut. Both are one line each since `openSettingsWindow` exists.
- [ ] Mention the shortcut in the README and the docs.
- [ ] Optional: let the shortcut be rebound (needs a recorder row and a stored setting).
- [ ] Optional: follow the system light and dark theme.
- [ ] Later `/sync` should note the new window and shortcut in `AGENTS.md`.
