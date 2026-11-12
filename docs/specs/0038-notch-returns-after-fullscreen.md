# 0038. Notch returns after leaving fullscreen

**Date**: 2026-11-12
**Status**: Accepted

## Summary

Issue #49. After leaving a fullscreen app by a Space swipe or Mission Control, the Notch could stay hidden on the desktop landed on until the user switched apps or Spaces again.

## Requirements

- **AC-1** Leaving a fullscreen Space shows the Notch again on a normal desktop, even if CatNotch is the frontmost app on arrival.
- **AC-2** Still event driven, no polling timer (spec 0016).

## Design

- `refreshForeground` no longer returns early when CatNotch is frontmost and the last state was fullscreen: it clears that stale state and re-applies it.
- One more one shot re-check at 2.5s after a Space or app change, for a slow fullscreen exit animation.
- `ForegroundState.detect` also tests the bounding box of the app's layer 0 windows on a display: Ghostty's fullscreen is a tab bar window plus a content window, neither reaching both edges. Tested in `ForegroundStateTests`.
- Hiding is `alphaValue = 0` plus click through, not `orderOut`. An ordered out panel came back on the current Space only, so the other desktops lost the Notch. `update()` does nothing while hidden. Showing resets to closed and orders the panel front (also the first show).
