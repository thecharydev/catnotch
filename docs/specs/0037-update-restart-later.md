# 0037 Update installs first, restart is the user's choice

Builds on [0034](0034-native-release-and-bridge.md). The Update button no longer quits the app by itself.

## Requirements

- **AC-1** "Update to X" downloads, verifies and swaps the new app in, then stops. The old version keeps running.
- **AC-2** After the install, Settings shows "X installed. Restart to use it" and a **Restart now** button. Restart now quits the old app and opens the new one.
- **AC-3** No Later button. If the user quits another way, the new version runs at the next launch.
- **AC-4** While installed, "Check for updates" and "Update" are hidden (the installed app is already the newest).

## Design

- `UpdateState.installed(version:)`; `UpdateModel.install()` ends in it and `restart()` is the old `relaunch()`.
- Settings only; the Notch shows nothing.

## Out of scope

A prompt on the Notch; restarting on a timer.
