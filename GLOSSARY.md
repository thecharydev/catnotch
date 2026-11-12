# CatNotch

A notch-style bar at the top of the Mac screen that opens into music, a focus timer, tasks, a file shelf, AI usage, a calendar and Claude Code prompts.

## Language

**Supported platform**:
macOS 14 or newer on Apple silicon, the only platform CatNotch is built, tested and released for.
_Avoid_: cross-platform, Windows support, Intel support

**Notch**:
The bar at the top of the screen, closed by default and opened by hovering it.
_Avoid_: island, pill, bar (alone)

**Release**:
A version tag on `thecharydev/catnotch` that publishes the native Apple silicon build as a dmg and an update zip.
_Avoid_: Windows release, Store release

**Update**:
Replacing the installed CatNotch with a newer Release when the user asks for it in Settings. Never happens without the user pressing the button. The new version starts running only when the user restarts, which they choose after the install.
_Avoid_: auto-update, upgrade

**Bridge release**:
The first native Release (2.0.0), published under the old Electron update file names so installed 1.0.x apps can still find and install it.
_Avoid_: migration release, v2 build
