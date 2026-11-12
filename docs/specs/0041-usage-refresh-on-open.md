# 0041. AI usage refreshes on open and stays near live

**Date**: 2026-11-12
**Status**: Proposed

## Summary

AI usage looked stuck: it only checked while Home was open, every 2 minutes, and reused any reading under 60 s old, so opening Home after a while showed an old number for a long time. Amends 0025 (AC-4 and the 2 minute poll). The Electron app polled the same way but its hook stayed mounted, so it felt fresher.

## Requirements

- **AC-1** Opening Home checks right away. A reading older than 15 s is fetched again (was 60 s); a newer one is reused, so opening and closing the Notch fast does not hit the endpoints.
- **AC-2** While Home stays open it checks every 30 s (was 2 minutes).
- **AC-3** Nothing is checked while Home is not showing, and never when AI usage is off or not allowed (0025 AC-7 stands).
- **AC-4** The last good reading shows at once on open and changes in place when the new one arrives. No spinner (the very first open after a launch still shows "Checking…" until the first reading arrives; prefilling it from `limits-cache.json` is a later change).
- **AC-5** The 5 minute back-off after "unavailable" and the retry tap (0025 AC-2, AC-4) are unchanged.

## Design

- `CatNotchCore/AiLimits.swift`: `LimitsReader.minGap` 60 -> 15.
- `CatNotch/UsageModel.swift`: `poll()` sleeps 30 s, not 120.
- Test: a read 20 s after a good one fetches again; one 10 s after reuses it.

## Out of scope

Polling while the Notch is closed, the closed Notch's AI reading (`collapsedRight`), refreshing on hover. Each would be its own spec.
