# DeskNotch Privacy Policy

_Last updated: 29 September 2026_

DeskNotch is a Windows app that shows a notch at the top of your screen. It has no account, no analytics, no advertising and no server of its own. This page explains what it reads, what it keeps, and what, if anything, leaves your PC.

## What stays on your PC

DeskNotch reads the following from Windows to show them in the notch. None of it is sent anywhere.

- **Media playing**: the title, artist and artwork of what is playing, so you can see and control it.
- **Microphone and camera in use**: which apps are currently using them, read from Windows' own privacy records. DeskNotch never accesses your microphone or camera itself, and never records audio or video.
- **Wi-Fi and Bluetooth**: the name of the network you are connected to, and the names and battery levels of connected Bluetooth devices.
- **Battery, CPU, GPU and memory use.**
- **Screenshots**: new images in your Screenshots folder, so the notch can offer them to you. Renaming or discarding one only happens when you ask.
- **Your most used apps**, from Windows' own list, for the apps bar.
- **Screen time**, if you have the separate app ScreenWise installed: DeskNotch reads today's total from ScreenWise's local database.
- **Glass style**: a live image of the screen area behind the notch, used only to draw the blur. It is processed in memory and never saved or sent.

- **Claude Code popups (optional)**: if you turn this on, DeskNotch listens on `127.0.0.1` only (this PC, never the network) so Claude Code can send it the command or question it is asking about. A secret token in the hook stops anything else from using it. What is shown is held in memory until you answer or 30 seconds pass; it is never saved or sent anywhere. For the Claude tab, DeskNotch also reads the first lines of Claude's own session files on this PC (to learn the folder and whether a session is the terminal or VS Code) and keeps only that in memory. If you click a session to open its chat, DeskNotch reads the recent text of that one session's file and shows it on the notch; it is held in memory while the chat is open and never saved or sent anywhere. A message you send from the chat is passed to your own `claude` program on this PC, like typing it in a terminal. Turning it on adds entries to Claude's `settings.json` (with a one time backup), and turning it off removes them.

- **Calendar (macOS only, optional)**: after you click Allow in the Calendar view, DeskNotch reads the events in your Mac's Calendar app for today and tomorrow (title, time, calendar colour, and any Zoom, Meet or Teams link) to show what is next. It stays in memory on your Mac, is never saved, logged or sent anywhere, and DeskNotch never creates, changes or deletes an event. macOS only offers read and write together as one permission, so the prompt says full access; the promise that we only read is kept by the code. Turn it off any time in Settings, or in System Settings, Privacy, Calendars.

## What DeskNotch saves

Your settings, tasks, reminders, focus history, the files you put on the Shelf (as file paths) and, if you choose one, your companion photo, are saved in a file on your PC. Uninstalling DeskNotch removes the app; you can delete this file at any time.

## What leaves your PC

- **AI usage (optional)**: if you use Claude Code or Codex on the same PC, DeskNotch reads the sign-in those tools already keep and sends it only to their own providers, Anthropic (`api.anthropic.com`) and OpenAI (`chatgpt.com`), to fetch how much of your usage limit is used. It is never sent anywhere else. You can turn AI usage off in Settings.
- **Updates**: the version downloaded from GitHub checks GitHub Releases for new versions. The Microsoft Store version is updated by the Microsoft Store. As with any web request, GitHub or Microsoft can see your IP address.

Links you choose to open (for example "Get ScreenWise") open in your web browser.

## Children

DeskNotch does not knowingly collect any information from anyone, including children.

## Changes

If this policy changes, the new version will be published at this address with a new date.

## Contact

Questions or concerns: [open an issue on GitHub](https://github.com/thecharydev/deskNotch/issues).
