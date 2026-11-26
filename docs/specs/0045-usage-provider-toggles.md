# 0045 Usage provider toggles

Settings → AI usage gets one on/off toggle per usage provider (Claude, Codex), under the existing "Show usage on Home" master switch.

## Decisions

- The master switch (`showAiUsage`) stays. The provider toggles show only while it is on.
- Both providers default to on, so existing Homes do not change.
- An off provider is skipped completely: its login is not read (no Keychain prompt for Claude) and no network call is made for it.
- Both providers off counts as usage off: the tile is hidden and Home falls back to the time tile. The master toggle keeps the value the user set.
- One consent answer covers both providers. Turning a provider back on does not ask again. Master off then on after "Not now" still asks again.
- Settings labels say "Claude" and "Codex". "Claude Code prompts" is a separate feature and is untouched.

## Build notes

- Store: two bool keys in `settings` next to `showAiUsage` (`CatNotchCore/AiLimits.swift`), default true.
- Core: `LimitsReader` takes the enabled providers and reads only those. Test it in `CatNotchCoreTests`.
- App: `UsageModel.available` is false when the master is off or no provider is enabled. Add the two toggles in `SettingsWindow.usageSection`.
- Update the "No sign-in found" text so it only names enabled providers.

## Done when

- Turning Codex off hides its gauge and its `~/.codex/auth.json` is not read. Same for Claude.
- Both off hides the tile.
- Existing stores with neither key behave as both on.
