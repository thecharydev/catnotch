# DeskNotch
<img width="1672" height="941" alt="2416cea1-b2ba-47ae-9ad4-26a41e42804e" src="https://github.com/user-attachments/assets/563721fc-c8a3-4829-b07b-ef03b5b1143d" />


**The MacBook notch, reimagined for Windows.**

DeskNotch sits at the top centre of your screen as a slim bar. Hover it, and it opens into your music, a focus timer with a small companion, your tasks, a shelf for files, your AI usage and the apps you use most. Move away, and it folds back out of your way.

> **Beta.** DeskNotch is in public testing. Things may break; [feedback](#feedback) is very welcome.

---

## Highlights

### A notch that is always useful, even closed
- **Now playing**: album art and a live pulse while anything plays, from Spotify to a YouTube tab.
- **Focus countdown**: a tiny ring and the time left while a session runs.
- **Clock**: 12-hour time whenever nothing else needs the space.
- **AI usage**: your Claude and Codex limits as two small rings, 5-hour inside and weekly outside.
- **Screen time**: today's total from [ScreenWise](https://www.bruhlabs.top/download), if you have it installed.
- **Privacy dots**: orange while any app uses the microphone, green for the camera, and the app's name for a moment when it starts.
- **Just connected**: headphones, Wi-Fi and Bluetooth devices get a brief moment of their own when they connect, with the battery level for earbuds and mice that report one.
- **Battery**: a moment when you plug in or unplug, a warning at 20% and 10%, and the charge kept in view while it is low.

### Three views, one hover away
- **Glance**: up to four cards: your companion, now playing with controls, your next tasks, and AI usage, plus a **Right now** card whenever an app is on your mic or camera or the battery has something to say; flip it over for CPU, GPU and memory usage as three rings.
- **Desk**: a focus timer beside your whole task list.
- **Shelf**: drop files anywhere on the notch to park them, with thumbnails; drag them back out one at a time, or all at once.

### A companion with a job
- **One mode at a time**: Timer, Reminder, Clock or Screen time (needs ScreenWise), each with its own look and body language.
- **Focus timer**: 1 to 60 minutes, or any custom length down to the second.
- **Reminders**: pick a time and an optional message; when it comes, the notch opens on its own with your companion ringing, and you can snooze it or let it go.
- **It reacts**: watches what it is working on, celebrates a finished task, and sleeps at night.

### Moments that come to you
- **Screenshot catcher**: take a screenshot and the notch opens on it: drag it into any app, keep it on the Shelf, rename it, open it, or discard it.
- **Focus complete**: when a session ends, the notch opens and your companion tells you.

### Claude Code, answered from the notch
- **Permission popups**: when Claude Code (in the terminal or the VS Code extension) wants to run a command or edit a file, the notch opens on it with the command, the project name and three buttons: **Allow**, **Deny**, or **Ask in terminal**.
- **Questions**: when Claude asks you a multiple choice question, tap an answer on the notch.
- **Safe by default**: it never takes keyboard focus, waits 30 seconds, then hands the question back to Claude's own prompt. If DeskNotch is closed, Claude simply asks as usual.
- **Setup**: Settings, General, **Claude Code popups**. It shows exactly what it will add to `~/.claude/settings.json`, saves a backup the first time, and only ever touches its own two entries. Start a new Claude session after turning it on.

### Your apps, your way
- **Apps bar**: Windows' own most-used apps, or your favourites, one tap to open. Four in view, the rest a scroll away.

### Looks that fit your desktop
- **Two styles**: Default (a soft charcoal) and Glass (a smoked, live blur of whatever is behind it).
- **Your layout**: put the tabs dock and the apps bar left, right or below the notch; hide the tabs you don't use.
- **Settings that read like System Settings**: one section at a time, every option explained in a line.

---

## Install

1. Download the latest `DeskNotch Setup.exe` from [**Releases**](https://github.com/yashsrivasta7a/deskNotch/releases).
2. Run it. The beta is not code-signed yet, so Windows may show **"Windows protected your PC"**: click **More info**, then **Run anyway**.
3. A slim bar appears at the top centre of your screen. Hover it to open; Settings is the gear icon on the dock.

**Requires** Windows 10 or 11.

## Install on macOS

Requires macOS 13 or newer. On a MacBook with a notch, DeskNotch wraps the real notch. On any other screen it shows the same pill as Windows.

**With Homebrew (recommended):**

```bash
brew install --cask <owner>/desknotch/desknotch
```

**Or by hand:** download `DeskNotch-<version>-universal.dmg` from [**Releases**](https://github.com/yashsrivasta7a/deskNotch/releases) and drag DeskNotch to Applications. The build is not notarized (that needs a paid Apple account), so the first open is blocked. Open **System Settings, Privacy and Security**, scroll down and click **Open Anyway**. The Homebrew cask clears that block for you.

Update with `brew upgrade --cask desknotch`, or download the new DMG. DeskNotch never installs updates by itself on macOS; Settings tells you when a newer version is out.

**Permissions**, each asked only when its feature needs it:
- **Location**: to show the Wi-Fi network name. Say no and you get a plain "Wi-Fi" moment.
- **Screen Recording**: only when you turn on Glass. Say no and the style stays Default.
- **Keychain**: only after you agree to AI usage, so DeskNotch can read the Claude Code sign in.

macOS ties these approvals to the app's signature, which changes with every build. After an update you may be asked again.

## Build from source

Requires Node.js 20+.

```bash
npm install     # install dependencies
npm run dev     # run in development, with hot reload
npm run build   # build the Windows installer into dist/
```

### Releasing an update

Installed copies update themselves from GitHub Releases: they check a minute after start and every six hours, download in the background, and install themselves once the PC has been left alone for a minute (or when the app quits).

1. Raise `version` in `package.json` (updates only go to a higher version).
2. Build and publish with a GitHub token that can create releases:
   ```bash
   GH_TOKEN=<token> npm run build -- --publish always
   ```
   This uploads the installer and `latest.yml`, the file the app reads, to a draft release.
3. Publish the draft on GitHub. Installed apps pick it up on their next check.

Keep `appId` in `electron-builder.yml` unchanged, or an update installs as a second app. Only builds that include the updater can update themselves; earlier betas need one manual install.

## Privacy

Everything stays on your PC. Media, microphone and camera state, Wi-Fi, Bluetooth, screenshots and app usage are read from Windows locally and never leave it. AI usage is read with the logins Claude Code and Codex already keep on your machine, and those tokens are sent only to their own providers (Anthropic and OpenAI).

## Known limits (beta)

- **Start with Windows** works for the installed app only, not `npm run dev`.
- **Screen time** needs [ScreenWise](https://www.bruhlabs.top/download); without it the option is greyed out. It updates about once a minute.
- **Glass** hides the notch from screenshots and screen sharing while it is on; that is how Windows lets an app capture what is behind it.
- **Screenshots** are caught when Snipping Tool saves them, which is its default.
- **AI usage** appears only if you use Claude Code or Codex on the same PC.

### macOS differences

- The microphone and camera moments say "Microphone" or "Camera" but not which app, because macOS only tells us which device is running.
- Screen time (ScreenWise) is Windows only, so that tile is hidden.
- Recent files, most used apps and screenshot catching rely on Spotlight. If Spotlight indexing is switched off, they stay empty.
- Now playing uses a private Apple interface that Apple can change in a future macOS release.

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/yashsrivasta7a/deskNotch/issues) with what you did, what happened, and a screenshot if something looked off.

---

Copyright © 2026 Devezio.tech · App ID `com.devezio.desknotch`
