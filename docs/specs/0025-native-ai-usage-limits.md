# 0025. Native AI usage limits

**Date**: 2026-11-05
**Status**: Accepted

## Summary

Issue #27 (native rewrite, ADR 0001). The plan limits of Claude Code and Codex (session, week, month), read with the login each tool already keeps on disk, shown as dotted orbs (a globe filled like a tank, the percent used under it) as the third tile of the Home view (after the companion and now playing, as in the Electron Notch). Port of `main/ipc/limits.ts`; the orb is ported from `thinking-orbs` as a SwiftUI `Canvas`, since the npm package is JavaScript. The fetch logic is in CatNotchCore, behind two closures (read the login, send a request) so tests run on fixtures.

## Requirements

- **AC-1** Claude shows its 5 hour (SESSION) and 7 day (WEEK) windows; Codex shows its primary and secondary windows, each named by its length (up to a day SESSION, up to 7 days WEEK, else MONTH). Each window is an orb (64pt in a 72pt column, as in Electron; the whole row shrinks together only when the room beside the companion and a playing track is short) with the percent used under it, one card per tool; under each orb its name ("Claude 5h") turns into what is left and when it refills ("88% left · 4h") while the pointer is on it.
- **AC-2** A provider whose login is rejected (401 or 403) shows "Sign in again"; one that cannot be reached, answers with an error or sends something unreadable shows "Tap to retry". Tapping the card checks again past any back-off. A tool that is not signed in at all (no login on disk) has no card.
- **AC-3** A failed check (`unavailable`) shows the last good reading instead. An `expired` login does not: a stale number must not hide that the login needs attention (the Electron app showed it; this is the one deliberate difference).
- **AC-4** Checks closer than 15 s (60 s until spec 0041) reuse the last good reading. A provider that answered "unavailable" is left alone for 5 minutes (the endpoints rate limit, and Claude Code shares Claude's), unless the user taps retry.
- **AC-5** Last good readings are saved in `limits-cache.json` beside the store, so a relaunch shows numbers while the endpoint is rate limiting.
- **AC-6** A limit at 80% or more is drawn in the warning orange.
- **AC-7** Nothing reads a login before the user says yes. The first time Home opens the tile is a question that explains it, with Allow and Not now buttons (an alert did not work from the Notch panel); "Not now" turns AI usage off. Settings has "Show AI usage"; switching it back on asks again. Off, the tile is gone and nothing is read or sent. With no tool signed in the tile says so.

## Design

- `CatNotchCore/AiLimits.swift`: `Limit`, `ProviderLimits`, `LimitsProvider` (`claude`, `codex`: request, `parse`), `Credentials` (`claude(from:)`, `codex(from:)`), `ResetText`, `StoreData.showAiUsage` / `aiConsent` (settings keys `showAiUsage`, `aiConsent`), and the `LimitsReader` actor: caching, back-off, fallback and the cache file.
- `CatNotch/UsageModel.swift`: an `@Observable` model shared by every display. Supplies the real login reader (Claude: Keychain item `Claude Code-credentials` through `/usr/bin/security`, then `~/.claude/.credentials.json`; Codex: `~/.codex/auth.json`) and `URLSession`, shows the consent card, and refreshes every 30 s (2 minutes until spec 0041) while Home is open (no timer otherwise).
- `CatNotch/UsageViews.swift`: `UsageTile` (a `Gauge` with an `Orb` per window, `RetryGauge` for a failed tool, `ConsentBody` for the question). `GlanceViews.swift` has the shared `homeTile` (132 tall) and the `CompanionTile` placeholder; Home is Companion (112 wide), Now Playing (276, only while playing) and AI usage (the rest of the 644pt row, a card being 24pt plus 72pt per orb) in one row, with the glance row under it, so the open Notch stays 700 x 300. The next event card is no longer on Home.
- Tokens are never refreshed here (refreshing rotates the token the tool itself relies on) and never leave the Mac except to their own provider.

## Out of scope

Hiding single limits (`hiddenLimits`), the closed Notch's AI reading (`collapsedRight`), the Electron consent flag (`aiConsent` is asked again once, as ADR 0001 says). The orb drawing, the Keychain prompt and the consent card are platform behaviour, checked by hand against real logins.
