# What changed in this update

A walkthrough of everything added, fixed and removed in this round of work, so you can understand each change, find it in the code, and test it. Each section says **what** changed, **why**, **where** it lives, and anything to **watch out for**.

> None of this is committed yet. `git status` also shows some earlier uncommitted work of yours (the multi-display store sync in `renderer/lib/store.ts`, `main/display.ts`, `useFiles`, `useTasks` and friends). That work is not described here.

---

## Contents

1. [Screen time from ScreenWise](#1-screen-time-from-screenwise)
2. [Start with Windows showed "Electron"](#2-start-with-windows-showed-electron)
3. [Hide in fullscreen hid on maximize](#3-hide-in-fullscreen-hid-on-maximize)
4. [Shrink over browsers](#4-shrink-over-browsers)
5. [Close button on the dock](#5-close-button-on-the-dock)
6. [Companion: Reminder mode (Tasks removed)](#6-companion-reminder-mode-tasks-removed)
7. [Companion: Screen time mode (AI removed)](#7-companion-screen-time-mode-ai-removed)
8. [Typing in a card no longer toggles it](#8-typing-in-a-card-no-longer-toggles-it)
9. [Long tasks wrap](#9-long-tasks-wrap)
10. [Screenshot card: rename and Save to Shelf](#10-screenshot-card-rename-and-save-to-shelf)
11. [Look: shadows, border, Glass, Mica](#11-look-shadows-border-glass-mica)
12. [Hide in screenshots](#12-hide-in-screenshots)
13. [Dock: icons, names, size, hiding when locked](#13-dock-icons-names-size-hiding-when-locked)
14. [Settings: simpler, fewer sections, new defaults](#14-settings-simpler-fewer-sections-new-defaults)
15. [Closed notch: task count removed](#15-closed-notch-task-count-removed)
16. [Start-up lag and memory](#16-start-up-lag-and-memory)
17. [Updates over the air (OTA)](#17-updates-over-the-air-ota)
18. [New app icon](#18-new-app-icon)
19. [How to release the next version](#19-how-to-release-the-next-version) (GitHub and Microsoft Store)
20. [Not done yet](#20-not-done-yet)
21. [Files at a glance](#21-files-at-a-glance)
22. [After 1.0: rename, fixes and releases](#22-after-10-rename-fixes-and-releases)
23. [Where things stand](#23-where-things-stand)

---

## 1. Screen time from ScreenWise

**What.** The notch can show today's screen time, taken from your friend's app [ScreenWise](https://www.bruhlabs.top/download). It appears in two places:

- **Closed notch, right side**: Settings → Notch → Closed notch → Right side → **Screen time**. Shows an hourglass and "3h 44m".
- **Companion**: mode **Screen time** shows the figure large, with "Today, from ScreenWise".

If ScreenWise is **not installed**, both options are greyed out and a **Get ScreenWise** button opens its releases page. If someone picked Screen time and later uninstalls ScreenWise, the clock shows instead.

**Why it works this way.** ScreenWise has no publisher/subscriber or API to connect to. It writes everything into a local SQLite database, `%APPDATA%\ScreenWise`. So DeskNotch simply **reads that file, read-only**, and runs the same "today" sum ScreenWise's own dashboard uses (active + idle time, apps hidden in ScreenWise left out, and ScreenWise's own "day starts at" hour respected). Nothing needs to change in ScreenWise.

**Where.**
- `main/ipc/desktime.ts`: opens the database with Node's built-in `node:sqlite` (no new package), IPC `desktime:screen-time` and `desktime:download`.
- `renderer/hooks/useScreenTime.ts`: asks once on start (to know if ScreenWise is installed) and every 60 s while a screen-time view is picked.

**ScreenWise.** Your friend's app (formerly DeskTime) is now ScreenWise, downloaded from [bruhlabs.top/download](https://www.bruhlabs.top/download). DeskNotch only recognises ScreenWise:

- **Installed?** Windows' list of installed programs must contain **ScreenWise**.
- **Data file**: `%APPDATA%\ScreenWise\screenwise.db`, or `%APPDATA%\ScreenWise\desktime.db` if the file kept the old name. If ScreenWise saves somewhere else, add that path to `DB_FILES` in `main/ipc/desktime.ts`.
- **Get ScreenWise** opens `https://www.bruhlabs.top/download`.

**Installed means installed.** DeskNotch checks Windows' list of installed programs, not just the database: uninstalling ScreenWise leaves its database behind in AppData, and reading that used to show old screen time for an app that was gone. The check runs at most once a minute, so installing ScreenWise unlocks the option within a minute.

**Watch out.** ScreenWise saves to disk every 15 s, so the figure can lag slightly. If a future ScreenWise changes its database layout, the reading shows "—" instead of crashing.

---

## 2. Start with Windows showed "Electron"

**What.** Turning on Start with Windows from a `npm run dev` session registered bare `electron.exe` at login. At the next sign-in, Windows opened Electron's default welcome window instead of the notch.

**Fix.** Only the **installed** app can register itself to start with Windows. A dev run refuses, and also **clears** any old entry an earlier dev run left behind.

**Where.** `main/ipc/settings.ts`.

**Test.** Build and install (`npm run build`), turn the switch on, sign out and back in.

---

## 3. Hide in fullscreen hid on maximize

**What.** With Hide in fullscreen on, the notch also hid when you **maximized** a window. It should only hide for **real fullscreen**: F11 in a browser, a video's fullscreen button (YouTube, Netflix), games.

**Why it happened.** The check was only "does the front window cover the whole monitor?". A maximized window can pass that: with an auto-hiding taskbar, or because its invisible 8 px border overshoots the screen.

**Fix.** The check now also asks Windows whether the window is maximized (`IsZoomed`). Maximized means not fullscreen. It still hides only on the monitor where the fullscreen window is.

**Where.** `main/fullscreen.ts`: the small C# helper inside the PowerShell script.

**Watch out.** Chrome and Edge leave the maximized state when they go fullscreen, so they work. If F11 in **Firefox** does not hide the notch, tell me; Firefox may behave differently.

---

## 4. Shrink over browsers

**What.** A new setting, off by default: Settings → General → System → **Shrink over browsers**. While Chrome, Edge, Firefox, Brave, Opera or Vivaldi is the active window, the closed notch shrinks to a thin 6 px strip at the top edge, so it doesn't cover tabs. Hover the strip and the full notch opens as usual.

**Where.**
- `main/fullscreen.ts`: the same watcher now also reports which app is in front, and tells each notch window `notch:tucked` true/false.
- `renderer/components/notch/NotchChassis.tsx`: the `tucked` prop shrinks the closed bar.

**Watch out.** If a fullscreen video is playing, hiding wins over shrinking.

---

## 5. Close button on the dock

**What.** A **power** button sits right of the lock on the dock (bottom or side). It quits DeskNotch until you open it again from the Start menu.

**Where.** `renderer/components/notch/NotchChassis.tsx` (`QuitButton`), `main/ipc/settings.ts` (`app:quit`).

---

## 6. Companion: Reminder mode (Tasks removed)

**What.** The companion's **Tasks** mode is gone (tasks still live on the Home card and in the Focus & tasks tab). In its place is **Reminder**:

- **Folded card**: the next reminder's time, large, its message, and how long until it rings ("in 12 min").
- **Tap to open**: your reminders on the left (hover one for its × to remove it), and a **New reminder** form on the right: a time picker, an optional message, quick **10 min / 30 min / 1 hour** buttons, then **Set**.
- **When one is due**: the notch opens on its own, whatever it was showing. The companion rings (ripples pulse out, a bell swings on its shoulder) and the message sits beside it, centred, with **Got it** and **Snooze 5 min**. It stays open for a minute, longer while you hover.
- **Missed while closed**: a reminder whose time passed while DeskNotch was not running rings as soon as it starts.

Anyone who had Tasks mode saved is moved to Reminder automatically.

**Where.**
- `renderer/hooks/useReminders.ts`: the list, saved in the store under `reminders` and synced across displays; wakes exactly when the next one is due (no polling).
- `renderer/components/widgets/CompanionTile.tsx`: `ReminderMode` and `ReminderForm`.
- `renderer/components/widgets/ReminderView.tsx`: the ringing card.
- `renderer/pages/home.tsx`: opens the notch when one comes due.
- `main/store.ts`: adds `reminders` to the saved data.

**Watch out.**
- You pick a **time**, not a date, so a reminder is always within the next 24 hours. A time that has already passed today means tomorrow.
- If you ignore a ring, it stays in the list marked "Now" but does not pop up again until the app restarts.

**Also renamed** in Settings → Companion → Mode: **Timer, Reminder, Clock, Screen time** (they were Focus, Tasks, Time, AI, which sounded too alike). **Sleep** now reads **11 PM – 6 AM** instead of 23:00 – 06:00. The companion now starts in **Clock** mode on a fresh install.

---

## 7. Companion: Screen time mode (AI removed)

The companion's **AI** mode was replaced by **Screen time** (see section 1). AI usage is still available as its own Home card and on the closed notch. A saved AI mode moves to Screen time.

---

## 8. Typing in a card no longer toggles it

**What was wrong.** In the companion, typing a task with spaces made the card open or close by itself, and the text you had typed disappeared.

**Why.** The card was an HTML `<button>` with a text field inside it. In Chrome, pressing **Space** (or Enter) in a field that sits inside a button counts as a click on the button. So every space toggled the card, which rebuilt the field and lost the text.

**Fix.** Cards are no longer real buttons; they behave like one only when the card itself has keyboard focus. This fixes every clickable card, not just the companion.

**Where.** `renderer/components/ui/tile.tsx`.

---

## 9. Long tasks wrap

**What.** A long task used to be cut off with "…". Now it wraps into a paragraph, both in the list and while you type it:

- Home **Tasks** card and the **Focus & tasks** tab: the text wraps; ticked tasks are struck through on every line.
- The add-task field grows line by line as you type (up to a few lines, then scrolls). **Enter** still adds the task.

**Where.** `renderer/components/widgets/QuickAdd.tsx` (the field is now a `<textarea>` that sizes itself with CSS `field-sizing: content`), `GlanceTiles.tsx`, `DeskView.tsx`.

---

## 10. Screenshot card: rename and Save to Shelf

**What.** When you take a screenshot, the card that pops up now:

- shows the **file name** with a **pencil** icon. Click the pencil to get a proper text box with a ✓ button. Enter or ✓ saves, Esc cancels. The `.png` / `.jpg` ending is kept; an empty name or one that already exists is refused.
- says **"Save it to the Shelf to use later"** under the name ("Saved. Find it anytime on the Shelf" after saving).
- has **Save to Shelf** (was "Keep"), **Open** and **Discard**.
- no longer says "Drag it anywhere" (dragging the picture out still works).

**Where.** `renderer/components/widgets/CaptureView.tsx`; the rename itself in `main/ipc/screenshots.ts` (`screenshot:rename`). It only touches images inside your Screenshots folder, the same safety rule as Discard.

**Catch screenshots** was already on by default; it is now called **Open on screenshot** in Settings.

---

## 11. Look: shadows, border, Glass, Mica

- **Shadows removed** from the notch, the dock and the apps bar.
- **The white line removed**: the notch had a thin white border and a white inner highlight, which showed as a line against the screen edge.
- **Mica removed.** Only **Default** and **Glass** remain. Anyone on Mica is moved to Default.
- **Glass is easier to see.** It used to blend into the background. Now it has a darker smoky tint, the background behind it is no longer brightened, and a thin light edge runs along the sides and bottom (none on top, so no line against the screen edge).

**Where.** `renderer/components/notch/NotchChassis.tsx`, `renderer/components/notch/Backdrop.tsx`.

---

## 12. Hide in screenshots

**What.** Settings → General → System → **Hide in screenshots**, off by default. Leaves the notch out of screenshots, screen recordings and screen sharing, using Windows' own "exclude from capture" feature.

**Important: Glass always hides.** Glass works by capturing the screen behind the notch; for that capture not to include the notch itself, Windows must leave the notch out of **every** capture, including your screenshots. So with Glass on, the switch shows as on, locked, with "Always on with Glass". Switch to Default to appear in screenshots.

**Where.** `main/ipc/system.ts` (`applyContentProtection`), applied when settings change and when a notch window is created.

---

## 13. Dock: icons, names, size, hiding when locked

- **Clearer names and icons**: Home (grid), **Focus & tasks** (checklist, was "Desk" with a lamp), **Files** (folder, was "Shelf" with an inbox), Settings (**gear**, was sliders). The **lock** stays as it was.
- **Tabs size**: Settings → Layout → Tabs → **Size**: Default, Large (1.25×), Larger (1.5×). Makes the dock buttons and icons bigger for screens where they look small (for example a laptop at 100% display scaling). The label text keeps its size.
- **Hidden while locked**: when the notch is locked open, the dock and the apps bar disappear until your cursor is back on the notch. Hover to bring them back (including the lock, to unlock).

**Where.** `renderer/pages/home.tsx`, `renderer/components/notch/ViewSwitcher.tsx`, `renderer/components/notch/NotchChassis.tsx` (`showChrome`, the `--dock-btn` / `--dock-icon` CSS variables).

---

## 14. Settings: simpler, fewer sections, new defaults

- **7 sections became 4**: **Notch** (Home cards, Closed notch), **Companion**, **Layout** (Tabs, Apps bar), **General** (Appearance, System). Each section has small plain headings inside it.
- **Plain wording**: most explanation lines were removed; each row is a label and one control, like Windows Settings. A short note stays only where the label alone would not say enough.
- **Renamed**: Next task → Tasks, Right now → Status, Sleeps → Sleep, Catch screenshots → Open on screenshot, Ambient glow → Music glow, Album tint → Album colours, Tuck behind browsers → Shrink over browsers, Hide on Fullscreen → Hide in fullscreen.
- **A thin scrollbar** now shows when a section is longer than the panel.
- **New-install defaults**: the Home cards are only **Companion** (in Clock mode), **Now playing** and **AI usage**. Tasks and Status start off. Existing users keep their own choices.
- **Updates row**: General → System shows the version, download progress and **Check for updates**; a downloaded update installs by itself (section 17).

**Where.** `renderer/components/widgets/SettingsPanel.tsx`.

---

## 15. Closed notch: task count removed

The small dot and number ("1", "2") on the closed notch was the count of open tasks. It has been removed.

**Where.** `renderer/components/notch/CollapsedStatus.tsx`.

---

## 16. Start-up lag and memory

### Lag on first launch

**Why.** In the first half-second the app started about six PowerShell processes at once, two of which compile C# code. On a PC's first run .NET is still "cold", so they all fought the notch's first paint.

**Fix.** They now start in turns:

| What | Before | Now |
|---|---|---|
| Fullscreen watcher | at launch | after 2 s |
| App lists (most used, installed) | after 0.5 s | after 8 s, or when the apps bar opens |
| GPU reading | after 0.5 s | only when the Usage card asks |

### Memory

Measured on the installed app: about **510 MB** in total, of which Task Manager's "DeskNotch" group shows only ~250 MB. The PowerShell helpers are listed separately as "Windows PowerShell".

**A real leak, fixed.** The GPU sampler (a PowerShell reading every GPU engine, ~90 MB plus constant CPU) was meant to stop 6 s after the Usage card closed, but an earlier commit removed that stop, so it ran for the app's whole life. It stops again now, and keeps the last reading so the card isn't blank when reopened.

**Also.** The fullscreen watcher (~60–80 MB) now runs only while Hide in fullscreen or Shrink over browsers is on.

**Where the rest goes** (not changed, see section 20):

| Process | Memory | Why |
|---|---|---|
| GPU process | ~220 MB | Chromium's graphics process, mostly the graphics driver |
| Main | ~110 MB | Node plus the now-playing reader |
| Privacy PowerShell | ~70 MB | mic, camera, Wi-Fi, Bluetooth checks |
| Fullscreen PowerShell | ~60 MB | the front-window check |
| Renderer | ~70 MB | the notch's page |
| Video-capture service | ~50 MB | started by the headphone detector's device list |

**Where.** `main/ipc/usage.ts`, `main/ipc/apps.ts`, `main/fullscreen.ts`, `main/main.ts`.

---

## 17. Updates over the air (OTA)

**What.** The installed app updates itself from your **GitHub Releases**:

- It checks a minute after starting, then every 6 hours.
- A newer version downloads in the background.
- It installs **by itself** once the PC has been left alone for a minute (no mouse or keyboard), or when the app quits, whichever comes first. The app starts again on its own. There is no button to press.
- In `npm run dev` it never checks; the row says "Updates run in the installed app".

**How it works.** When you publish a build, electron-builder uploads the installer **and a small file, `latest.yml`**, which holds the version number. The installed app reads `latest.yml` from the latest release; if the version is higher than its own, it downloads the installer and runs it silently.

**Where.**
- `main/updater.ts`: the updater (package `electron-updater`).
- `electron-builder.yml`: `publish` now points at `yashsrivasta7a/deskNotch`, with tags like `0.3.0` (no `v`), matching your existing releases.
- `renderer/components/widgets/SettingsPanel.tsx`: the Updates row.

**No environment variable is needed inside the app.** The repo is public, so installed copies can check it without a token. You only need a `GH_TOKEN` on your own PC when you publish (section 19).

**Watch out.**
- **Never change `appId`** in `electron-builder.yml` (`com.yashsrivasta7a.desknotch`). If it changes, an update installs as a second, separate app.
- The installer is not code-signed, so updates are trusted only because they come from GitHub over HTTPS.
- Only builds that include the updater can update themselves. People on 0.1.0 / 0.2.0 install the next version by hand once; after that it is automatic.
- A first version of the updater crashed on start ("Cannot destructure property 'autoUpdater'…"). That was an import issue with how webpack loads the package, and it is fixed (`import { autoUpdater } from 'electron-updater'`).

---

## 18. New app icon

**What.** A flat, two-colour mark: a white **laptop with a notch** cut into the top of its screen, on a near-black rounded tile. No gradients or faces, so it looks clean and stays sharp from 16 px (taskbar) to 256 px.

**Where.**
- `resources/icon.svg`: the source; edit this one.
- `resources/icon.ico`: used by the installer and the app, all 7 sizes (16 to 256 px).
- `resources/icon.png`: 512 px, for GitHub and the README.
- `scripts/make-icon.cjs`: rebuilds the `.ico` and `.png` from the SVG: `node scripts/make-icon.cjs`.

`resources/icon.icns` (the Mac icon) still has the old logo.

---

## 19. How to release the next version

1. In `package.json`, set `version` to **0.3.0**. It currently says `1.0.0`, while your GitHub releases are 0.1.0 and 0.2.0. Every release must be higher than the one before.
2. Make a GitHub token once: GitHub → Settings → Developer settings → Personal access tokens. Either a classic token with the `repo` scope, or a fine-grained one with **Contents: Read and write** on `DeskNotch`. Keep it private; never put it in the code.
3. Build and publish:
   - Git Bash: `GH_TOKEN=ghp_xxx npm run build -- --publish always`
   - cmd: `set GH_TOKEN=ghp_xxx` then `npm run build -- --publish always`
4. electron-builder creates a **draft** release with the installer and `latest.yml`. Open it on GitHub, write the notes, and click **Publish**.
5. From then on, installed copies of 0.3.0 pick up every later release by themselves.

---

### Microsoft Store version

The same build also makes a **Store package** (`dist/*.appx`) next to the GitHub installer. Microsoft signs it for free when you submit it, so Store users never see the "Windows protected your PC" warning.

**One-time setup**

1. Create a free individual developer account at [Microsoft Partner Center](https://partner.microsoft.com/dashboard) (Apps and games).
2. Reserve the name **DeskNotch** (Apps and games → New product → MSIX or PWA app).
3. Open the app → **Product management → Product identity**. Copy these three values into `electron-builder.yml` under `appx`, replacing the `REPLACE_WITH_…` placeholders exactly:
   - `Package/Identity/Name` → `identityName`
   - `Package/Identity/Publisher` → `publisher` (starts with `CN=`)
   - `Package/Properties/PublisherDisplayName` → `publisherDisplayName`
4. For the listing you will need: a description, 1+ screenshots, a category (Productivity), the age-rating questionnaire, and a **privacy policy URL**. Use `PRIVACY.md` on GitHub: `https://github.com/thecharydev/deskNotch/blob/master/PRIVACY.md`.
5. When asked about the **runFullTrust** capability, explain that DeskNotch is a desktop (Electron) app packaged for the Store.

**Each release**

1. Build as usual (step 3 above). `dist/` now also holds `DeskNotch <version>.appx`.
2. Partner Center → your app → **Start update** (or the first submission) → Packages → upload the `.appx` → submit.
3. Certification usually takes 1–3 days; Store users then get the update automatically.

**How the Store build differs** (the app detects it with `process.windowsStore`):

- **Updates**: the OTA updater stays off; Settings shows "Updates come from the Microsoft Store".
- **Start with Windows**: Store apps cannot register themselves at login. The package declares a Windows startup task instead (`addAutoLaunchExtension`), and the Settings row opens Windows' **Startup apps** page, where the user turns it on or off.
- **Saved data** lives in the Store app's private folder, so it is separate from the GitHub version's.
- Everything else (PowerShell helpers, ScreenWise, screenshots, media) works the same.

**Tiles**: the Store's images (`resources/appx/*.png`) are made from the logo by `node scripts/make-icon.cjs`.

## 20. Not done yet

Ideas that came up but were left for later:

- **Less memory** (roughly half the total is possible):
  - Merge the two PowerShell helpers into one: about 60 MB saved. Or replace them with a small native helper: about 120 MB.
  - Drop the headphone detector's device list: about 50 MB (wired headphones would lose their "connected" moment; Bluetooth ones are announced another way).
  - A "Low memory" option that turns off hardware acceleration: about 150 MB, at the cost of more CPU during animations.
- **Reminders with a date**, repeating reminders, and a reminder that keeps nagging when ignored.
- **The Mac icon** (`icon.icns`) with the new logo.
- **Code signing the GitHub installer** (the Store version is signed by Microsoft), which would remove the "Windows protected your PC" warning for the GitHub download and let the updater verify updates.

---

## 21. Files at a glance

**New**

| File | What it is |
|---|---|
| `main/ipc/desktime.ts` | Reads screen time from ScreenWise's database |
| `main/updater.ts` | Updates over the air |
| `renderer/hooks/useScreenTime.ts` | Screen time for the renderer |
| `renderer/hooks/useReminders.ts` | The reminders list and when one is due |
| `renderer/components/widgets/ReminderView.tsx` | The ringing reminder card |
| `resources/icon.svg`, `resources/icon.png` | The new logo |
| `scripts/make-icon.cjs` | Rebuilds the icon files from the SVG |

**Changed (main process)**: `main/main.ts`, `main/fullscreen.ts`, `main/store.ts`, `main/ipc/settings.ts`, `main/ipc/system.ts`, `main/ipc/store.ts`, `main/ipc/index.ts`, `main/ipc/screenshots.ts`, `main/ipc/usage.ts`, `main/ipc/apps.ts`.

**Changed (renderer)**: `pages/home.tsx`, `components/notch/NotchChassis.tsx`, `CollapsedStatus.tsx`, `ViewSwitcher.tsx`, `Backdrop.tsx`, `components/ui/tile.tsx`, `components/widgets/CompanionTile.tsx`, `SettingsPanel.tsx`, `CaptureView.tsx`, `QuickAdd.tsx`, `GlanceTiles.tsx`, `DeskView.tsx`.

**Changed (config and docs)**: `package.json` (`electron-updater`), `electron-builder.yml` (publish), `resources/icon.ico`, `README.md`, `doc/Functionality.md`, `doc/HowItWorks.md`.

---

## 22. After 1.0: rename, fixes and releases

### The app is called DeskNotch

Renamed from "deskNotch" in the product name, the installer, the Store display name, the window title, the "Close DeskNotch" label, the README and these docs. Links and repo paths keep `deskNotch`, because that is the GitHub repo's name.

- Existing users lose nothing: Windows ignores capitalisation in folder names, so saved settings are still found, and the app ID is unchanged, so updates keep working.
- The fullscreen watcher recognises the notch's own window by its title. That check was changed to `DeskNotch` too; otherwise the notch would treat itself as "the app in front".

### Top bar no longer locks

Clicking the notch's top bar used to lock it open by surprise. Now only the **lock button on the dock** locks it. Dropping a file on the notch still keeps it open until you unlock it. (`renderer/components/notch/NotchChassis.tsx`)

### GitHub link in Settings

A **GitHub** item, with GitHub's own logo, sits at the bottom of the Settings sidebar, visible in every section. It opens `github.com/thecharydev/deskNotch`. It is opened from the main process (`app:open-repo`), so the settings page cannot open any other address. It is fine for the Store version too, since it links to the project rather than asking people to download the app elsewhere.

### Microsoft Store identity

`electron-builder.yml` → `appx` holds the values from Partner Center → Product identity:

| Field | Value |
|---|---|
| `identityName` | `Devezio.DeskNotch` |
| `publisher` | `CN=F35F3C2B-A4E0-4061-BA7F-5EB9B3EE1446` |
| `publisherDisplayName` | `Devezio` |

These must match Partner Center exactly, or the Store rejects the package.

### 1.0.0 crashed on launch; 1.0.1 fixes it

**What happened.** The 1.0.0 installer showed "A JavaScript error occurred in the main process" and never started.

**Why.** The packaged app and `npm run dev` load the `electron-updater` package in two different ways. The packaged app loads it as a real ES module, where the named import `autoUpdater` does not exist; dev loads it through webpack, where there is no default export. The first fix only made dev work, and 1.0.0 was published without launching the packaged build.

**Fix.** `main/updater.ts` imports the whole package and reads `autoUpdater` from whichever form is there. 1.0.1 was checked by launching the packaged app itself (`dist/win-unpacked/DeskNotch.exe`): it loaded the notch page and logged no main-process error.

**Release state on GitHub.**

| Release | State |
|---|---|
| 1.0.1 | **Latest.** Installer, blockmap and `latest.yml`. Updates start from this version. |
| 1.0.0 | Renamed "(broken, use 1.0.1)", marked pre-release, notes replaced with a warning. Its installer can still be downloaded; delete the release if you want it gone. |
| 0.1.0, 0.2.0 | Old betas, with no updater. |

**Two lessons for every release:**
- **Launch the packaged app before publishing.** Dev mode passing is not enough.
- **Testing from a VS Code terminal:** VS Code sets `ELECTRON_RUN_AS_NODE=1`, which makes `DeskNotch.exe` run as plain Node and exit at once without an error. Unset it first (in Git Bash: `env -u ELECTRON_RUN_AS_NODE ./DeskNotch.exe`).

### The `doc/` folder was deleted and restored

During the 1.0.1 work the whole `doc/` folder was deleted by mistake, and the 1.0.1 commit (made with `git add -A`) recorded that deletion on `master`. All four files were restored from the commit before it (`c17246b`) and updated for ScreenWise. **Until they are committed again, `master` on GitHub has no `doc/` folder.** Check the file list before every commit (`git status`), rather than adding everything blindly.

---

## 23. Where things stand

**Published**
- GitHub release **1.0.1** is live and is the first version that updates itself.
- `master` on GitHub has the DeskNotch code up to 1.0.1, and `PRIVACY.md`.

**Done on your PC, not yet committed**
- ScreenWise rename and the "installed means installed" check.
- The restored `doc/` folder, and this section.

**Still to do**
1. Commit and push the changes above.
2. Build the next version for the Store: raise `version` in `package.json` (1.0.2 or higher), `npm run build`, then upload `dist/DeskNotch <version>.appx` in Partner Center. The 1.0.0 `.appx` has the launch crash; do not submit it.
3. Fill in the Store submission (pricing, properties, age rating, listing with screenshots) and submit for certification.
4. Test an update end to end: with 1.0.1 installed, publish 1.0.2 and use **Check for updates** in Settings.
