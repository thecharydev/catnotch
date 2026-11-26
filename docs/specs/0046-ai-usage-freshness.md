# 0046. AI usage freshness

**Date**: 2026-11-26
**Status**: Accepted

## Summary

The AI usage tile can show a wrong number without saying so: a failed check keeps the last good reading as if it were current (spec 0025 AC-3), a window can have reset while the old percent is still drawn, and the only reload is on a card that has already failed. This spec makes readings carry their age, shows old ones as stale, refreshes sooner, and adds a Reload button. It amends 0025 AC-3 and AC-4.

## Requirements

- **AC-1** Every reading carries the time it was taken (`ProviderLimits.at`, not inside `Reading`, so no case payload changes). A failed check keeps the old time. The reader's saved cache already has it.
- **AC-2** A reading is stale when older than 2 minutes, or when a window's `resetsAt` has passed. A stale orb is dimmed and its name line reads "updated 6m ago". A passed reset keeps the old percent dimmed with "updating…"; it is never guessed as 0%. The view re-evaluates on a periodic clock, since nothing else redraws it as time passes.
- **AC-3** While Home is open the tile checks on opening and then every 30 s, waking early when the earliest `resetsAt` passes. The 15 s minimum gap (0025 AC-4) stays for non forced checks, except that a reading holding a window whose `resetsAt` has passed is checked again at once (else the early wake would do nothing). Closed, nothing runs or is sent (0025 AC-7).
- **AC-4** The tile has one Reload button (`arrow.clockwise`, on every card that shows readings (it checks both tools)). While any check runs it morphs (arrowhead folds into the path, a ring spins with a breathing arc, then it slows and unfolds back to the exact icon); the motion is `CatNotchCore/ReloadMotion.swift`, drawn in a `Canvas`, and Reduce Motion only dims it. It is a forced refresh: `force` skips both the 60 s gap and the 5 minute back-off (today it skips only the back-off). The failed card keeps its own retry.
- **AC-5** A forced refresh made while a check is in flight runs after it instead of being dropped.
- **AC-6** 0025 AC-3 is amended: a failed check still shows the last good reading, but as stale (AC-2). An `expired` login still shows "Sign in again".

## Design

- `CatNotchCore/AiLimits.swift`: `ProviderLimits` carries `at`; `LimitsReader.read` lets `force` skip the gap check as well as the back-off; `ProviderLimits` gets `note(for:now:)` and `nextReset(after:)` so the rules are tested in Core.
- `CatNotch/UsageModel.swift`: `poll()` sleeps `min(30 s, time to earliest resetsAt)`; a forced `refresh` made during one in flight is run once more afterwards.
- `CatNotch/UsageViews.swift`: Reload button on `UsageTile`; `Gauge` dims and shows the age when stale, inside a periodic `TimelineView`.
- Debug log of reading and age per check, `#if DEBUG` only, to confirm whether the endpoint's own data is lagging.
- Tests in `CatNotchCoreTests`: force skips gap and back-off; failed check returns the old reading with its old time; stale rule (age, passed reset).

## Out of scope

A "last checked" label next to Reload, a Reload that checks only one tool, background refresh while the Notch is closed, push updates (the endpoints have none), a cooldown timer on Reload.

## Amends

0025 AC-3 and AC-4 (add a one line "amended by 0046" note there).
