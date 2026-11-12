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

**Request**:
A question or a tool permission that Claude Code is waiting on, shown on the Notch until it is answered. Answering it on the Notch, or approving or answering it in the terminal or VS Code, ends it. Denying or pressing Esc elsewhere is not noticed; the Request then leaves on its own after about a minute.
_Avoid_: prompt, notification, card

**Session**:
A Claude Code conversation, shown as one row on the Notch and named by its title. The title is Claude's latest generated title for it, else the start of the user's first message, else the folder name.
_Avoid_: instance, Claude row, project (for the name)
