# 0003. Calendar agenda view on the notch (macOS)

**Date**: 2026-10-29
**Status**: In Progress

## Summary

DeskNotch gets a Calendar view that shows what is on your Mac's calendar today and tomorrow, with a colour dot per calendar, the time, and a Join button for Zoom, Meet and Teams meetings. It reads the calendars you already have in the Mac Calendar app (Google, iCloud, Outlook), so there is no new sign in. It only reads, it never creates or changes events. A small "next event" line also appears on Home. Windows is not part of this spec, so the view is simply not there on Windows.

## Context

DeskNotch is an Electron and Next app. On macOS, system features come from one Swift helper (`native/mac`) that talks to the main process in JSON lines, and the same helper already owns a permission (Location). There is no calendar code today, and no `docs/scope/` row, so this is a standalone feature spec. No `AGENTS.md` exists, so the stack was read from `package.json` and the code (Electron 43, Next 16, React 19, Tailwind 4, Swift helper, macOS 13 or newer).

The notch is small and glanceable. What you want from a calendar there is "what is next, when, and how do I join", not a full calendar. Windows has no clean way to read the system calendar from Electron, so Windows is deliberately left for a later spec rather than shipping a brittle workaround.

Build approach: none is recorded for this project, so this plan assumes an end to end thin slice first (Tracer Bullet), then thickens.

## Requirements

**User stories**:
- As a Mac user, I want to see today's and tomorrow's events on the notch, so that I know what is next without opening Calendar.
- As someone in meetings, I want a Join button on events that have a video link, so that I get into the call in one tap.
- As someone with several calendars, I want to switch off noisy ones (Holidays, Birthdays), so that the list stays useful.
- As a privacy minded user, I want the app to ask before it touches my calendar and to never change it, so that I can trust it.

**Acceptance criteria** (the contract, each independently checkable):
- **AC-1**: On macOS with `showCalendar` on, a Calendar view appears in the view dock after Files. With `showCalendar` off it is gone, along with the Home line. On Windows there is no Calendar view, no Calendar setting and no Home line, and nothing calendar related runs.
- **AC-2**: Before access is decided, opening the Calendar view shows a short explainer and an Allow button. The macOS permission prompt appears only after Allow is clicked. DeskNotch never asks for calendar access at launch or from any other screen.
- **AC-3**: If access is denied, restricted, or only "add events" access was given, the view shows "Calendar access is off" and an Open System Settings button that opens the Calendars privacy pane. The Home line stays hidden. Nothing crashes.
- **AC-4**: With access, the view shows a Today heading and a Tomorrow heading (the Mac's local days). Each lists events by start time, all day events first. Each row shows a colour dot (the calendar's own colour), the title, and either "start to end" (in the Mac's 12 or 24 hour format) or "All day". An event happening now is marked "Now". Events that already ended are not shown. The list fills within 2 seconds of opening the view.
- **AC-5**: Events you declined and events that are cancelled never appear, in the view or on Home.
- **AC-6**: A Join button appears on a row only when a link on the allowlist (Zoom, Google Meet, Microsoft Teams, `https` only) is found in the event's URL, then location, then notes. Clicking it opens that link in the default browser. A link not on the allowlist never gets a button.
- **AC-7**: Clicking a row opens that event in the Calendar app. The helper contains no call that creates, edits or deletes an event, and no change is ever written to any calendar.
- **AC-8**: With the view open, an event added, moved or deleted in the Calendar app shows up within 5 seconds with no reopening, and an event that ends disappears within 60 seconds.
- **AC-9**: After access is granted, Settings lists every calendar (title and account) with a toggle. Switching one off hides its events from the view and the Home line at once, and is remembered after restart. A saved id for a calendar that no longer exists is ignored without error.
- **AC-10**: Home shows one line with the next event's title and "in 25 min" (counting down each minute), or "now" while one is on. All day events never count as next. The line is hidden when nothing is left today, when access is not granted, or when `showCalendar` is off.
- **AC-11**: Empty states read clearly: "Nothing planned today" when today has nothing left (tomorrow still shows), and "Nothing planned" when both days are empty. No calendars at all shows the same "Nothing planned" state.
- **AC-12**: If the helper is missing or crashes, only the calendar features turn off (the view shows "Calendar unavailable"). The notch, tasks, focus and Shelf keep working.
- **AC-13**: Event titles, times and notes are never written to disk or logs by DeskNotch. `PRIVACY.md` and `README.md` say what is read, that it stays on the Mac, and that nothing is changed.
- **AC-14**: The Windows build behaves exactly as before, and no macOS calendar module is loaded on Windows.

## Options considered

### Option 1: System calendar through EventKit in the existing Swift helper (read only)

Add calendar commands to the helper you already ship, read events with Apple's EventKit, and show them in a new React view.

**Pros**:
- Covers every account already in the Mac Calendar app with no OAuth, tokens or review.
- Reuses the helper, its JSON line protocol and its permission pattern.
- Real calendar colours, accepted or declined status and recurring events come for free.

**Cons**:
- macOS only, so Windows waits for its own spec.
- Adds a permission prompt and a TCC (Apple's privacy permissions) entry for the helper.

### Option 2: Google Calendar sign in

Sign in with Google inside DeskNotch and read events through the Google API.

**Pros**:
- Same behaviour on both platforms.

**Cons**:
- Needs a Google Cloud project, a token store, sensitive scope review and refresh handling.
- Covers only Google accounts, and only by storing credentials in DeskNotch.

### Option 3: Subscribe to a private ICS link

Paste a private `.ics` URL and poll it.

**Pros**:
- Works on both platforms with no OAuth.

**Cons**:
- The user must find and paste a secret URL, which is also a credential.
- Read only, delayed, and no join or decline information that is reliable.

## Decision

**Chosen option**: Option 1: System calendar through EventKit in the existing Swift helper (read only)

Add calendar commands to `native/mac`, read the system calendars with EventKit after an explicit consent step, and show a Today and Tomorrow agenda in a new Calendar view plus a next event line on Home.

## Rationale

The helper already exists, already holds a permission, and the app already spawns it and restarts it on a crash. EventKit gives the user's real accounts, colours, declines and recurrences with no credentials stored by DeskNotch, which is both the least code and the lowest risk. Google sign in and ICS both add a secret to look after for less coverage. Leaving Windows out keeps this small and honest; a Windows path (Outlook or an ICS link) can be its own decision later.

Read only is chosen on purpose. On macOS 14 and later EventKit only offers "full access" (read and write together) as the permission, so the promise "we never change your calendar" is kept by the code (AC-7), not by the permission. That is why AC-7 is checkable and why the spec forbids any write call.

## Feature design

**Data model sketch** (no database; the first two come from the helper and are never stored):

| Entity | Fields | Notes |
|---|---|---|
| CalendarEvent | `id` string (EventKit `eventIdentifier`), `title` string (empty becomes "Untitled"), `start` and `end` ISO strings, `allDay` boolean, `calendarId` string, `calendarColor` hex string, `joinUrl` string or null | `location` and `notes` are read only to find the join link, then dropped |
| CalendarInfo | `id`, `title`, `color`, `account` | feeds the Settings toggles |
| Settings keys (existing store) | `showCalendar` boolean (default true), `hiddenCalendarIds` string list (default empty), `calendarConsent` boolean (default false) | `calendarConsent` is set when Allow is clicked on the explainer |

Relationship: CalendarInfo 1 to many CalendarEvent through `calendarId`. Declined and cancelled events are dropped inside the helper.

**State transitions**: access is `unknown` (not decided) → `granted` or `denied` (decided by the macOS prompt) → `denied` can only change in System Settings; the view re-checks each time it opens. `restricted` and "add events only" are treated as `denied`.

**Interface surface** (the helper follows the existing `usage` request and reply pattern with an `id`; main process channels sit in a new `main/ipc/calendar.ts` registered like the other ipc files):

| Channel or helper command | Inputs | Outputs | Key errors |
|---|---|---|---|
| `calendar:status` → helper `calendarStatus` | none | `unknown` · `granted` · `denied` · `unavailable` | helper missing gives `unavailable` |
| `calendar:request` → helper `calendarRequest` | none (only sent after Allow is clicked) | the new status | declined gives `denied` |
| `calendar:calendars` → helper `calendarList` | none | `CalendarInfo[]` | not granted gives an empty list |
| `calendar:events` → helper `calendarEvents` | `from`, `to` ISO strings (now to end of tomorrow) | `CalendarEvent[]`, declined and cancelled removed, ended removed | not granted gives an empty list |
| pushed helper line `{t:'calendarChanged'}` | none | tells main to tell the view to re query | none |
| `calendar:openEvent` | event `id` | opens it in Calendar | unknown id opens Calendar itself |
| `calendar:join` | event `id` | opens `joinUrl` in the default browser | main re checks the url is `https` and on the allowlist before opening |
| `calendar:openPrivacy` | none | opens the Calendars pane of System Settings | none |

**Value sourcing** (every value an action produces or displays, with its source):

| Action | Value | Source |
|---|---|---|
| Show the agenda | "today" and "tomorrow" boundaries | the Mac's current time zone and calendar, computed in the helper (`Calendar.current`) and in the renderer with the same local day; no setting |
| Show the agenda | `from`, `to` window | `from` is now, `to` is the end of tomorrow, both sent by the renderer |
| Row time text | 12 or 24 hour format | the system locale through `Intl.DateTimeFormat` with no override |
| Row colour dot | `calendarColor` | EventKit `calendar.cgColor`, turned into hex in the helper |
| "Now" mark | whether an event is on | `start <= now < end`, using the renderer clock ticking each minute |
| Home line text | "in 25 min" | `start - now`, rounded up to whole minutes, from the next timed event today |
| Join button | `joinUrl` | first allowlisted link found in EventKit `url`, then `location`, then `notes` (helper does the search) |
| Drop declined | decision | the current user's attendee status from EventKit (`participantStatus == declined`); an event with no attendees is never declined |
| Drop cancelled | decision | EventKit `status == canceled` |
| Open in Calendar | the target | `ical://ekevent/<id>?method=show&options=more`; if that fails, plain `open -a Calendar` |
| Settings toggles | the list | `calendar:calendars`, filtered by `hiddenCalendarIds` in the renderer |

**Key invariants**:
- The helper never calls a write API of EventKit (`save`, `remove`, `commit`). A repo wide search for them in `native/mac` must return nothing.
- The permission prompt is only ever triggered by `calendarRequest`, and `calendarRequest` is only sent from the Allow button.
- Join links are validated in the main process (`https`, host on the allowlist), never trusted from the renderer.

**Allowlist hosts** (decided here): `zoom.us` and `*.zoom.us`, `meet.google.com`, `teams.microsoft.com`, `teams.live.com`.

**Security model**: everything runs locally in the signed in user's own session. Events are held in memory only, passed between helper, main and renderer, and never logged or written. The renderer cannot ask the main process to open an arbitrary URL, only an event id.

**Configuration required**:
- helper `Info.plist`: `NSCalendarsUsageDescription` (macOS 13) and `NSCalendarsFullAccessUsageDescription` (macOS 14 and later), with text such as "DeskNotch reads your calendar to show your next events. It never changes it."
- helper code: `requestFullAccessToEvents` on macOS 14 and later, `requestAccess(to: .event)` on macOS 13.

**Edge cases decided here** (so the build does not invent them):
- Multi day events overlapping the window show as "All day" on each day they cover.
- An all day event's end is exclusive, so a one day event does not leak into tomorrow.
- Recurring events appear per occurrence (EventKit expands them).
- More than the view can hold scrolls inside the view; no row limit.
- Refresh: the helper emits `calendarChanged` on EventKit's `EKEventStoreChanged`, the view re queries on that, and also every 5 minutes as a safety. Ended events and the "Now" mark are re derived from the clock each minute with no query.
- Access revoked while open: the next query returns `denied` and the view switches to the access off state.
- Titles that are empty become "Untitled"; very long titles truncate to one line.

**Critical test scenarios** (each maps to an acceptance criterion):
- Happy path: grant access, open the view, see today's and tomorrow's events with colour, time and Join, verifies **AC-2**, **AC-4**, **AC-6**.
- Denied: refuse the prompt, see "Calendar access is off", Home line hidden, verifies **AC-3**, **AC-10**.
- No prompt without consent: launch fresh, wait, open Home and Settings, verify no prompt appeared, verifies **AC-2**.
- Declined, cancelled, ended events hidden, verifies **AC-5**, **AC-4**.
- Add and delete an event in Calendar while the view is open, verifies **AC-8**.
- Toggle a calendar off, restart, still hidden, verifies **AC-9**.
- Unsafe link (non allowlisted host, `http`, `javascript:`) gets no Join, and `calendar:join` refuses it, verifies **AC-6**.
- Search `native/mac` for write calls, verifies **AC-7**.
- Kill the helper, the notch keeps working, verifies **AC-12**.
- Windows build has no calendar anything, verifies **AC-1**, **AC-14**.

## Build plan

1. Helper thin thread: add `calendarStatus` and `calendarEvents` (no prompt yet, read when already granted), the two `Info.plist` keys, and rebuild with `scripts/build-helper.sh`. Satisfies **AC-4**, **AC-7**, **AC-12**.
2. Main side: `main/ipc/calendar.ts` with `calendar:status` and `calendar:events`, registered in `main/ipc/index.ts` on macOS only, plus the three new settings keys in `main/store.ts`. Satisfies **AC-1**, **AC-14**.
3. Renderer thin thread: `useCalendar` hook and a bare `CalendarView.tsx` (plain list), added to `VIEWS` in `renderer/pages/home.tsx` only when macOS and `showCalendar`, with size constants like the other views. Satisfies **AC-1**, **AC-4**.
4. Consent flow: `calendarRequest`, the explainer, the Allow button, the access off state with `calendar:openPrivacy`. Satisfies **AC-2**, **AC-3**.
5. Row detail: colour dot, time text, "All day", "Now", ended events dropped, declined and cancelled dropped in the helper, empty states. Satisfies **AC-4**, **AC-5**, **AC-11**.
6. Join and open: helper join link search, `calendar:join` with allowlist check, `calendar:openEvent`, row click. Satisfies **AC-6**, **AC-7**.
7. Live refresh: helper `calendarChanged` push, minute tick, 5 minute safety query. Satisfies **AC-8**.
8. Settings: Calendar on or off, the per calendar toggles, `hiddenCalendarIds` filtering in the view. Satisfies **AC-9**, **AC-1**.
9. Home line: next event with "in N min" and "now", hidden by the rules in AC-10. Satisfies **AC-10**.
10. Docs and checks: update `PRIVACY.md`, `README.md`, `doc/Functionality.md`; verify the Windows build shows nothing calendar related and the write call search is empty. Satisfies **AC-13**, **AC-14**, **AC-7**.

## Consequences

**Positive**:
- Useful on day one with the accounts already on the Mac, and no secrets stored.
- Small: one helper extension, one ipc file, one hook, one view, one Home line.
- Windows and Mac stay isolated, so a calendar bug cannot touch the Windows build.

**Negative / tradeoffs**:
- macOS only, so Windows users get nothing until a later spec.
- macOS asks for full calendar access (read and write together) even though DeskNotch only reads. The privacy text must be plain about that.
- Another permission to explain, and a new `Info.plist` key set that must be present or the prompt silently fails.

**Neutral**:
- The helper needs a rebuild, and the `usage` style request and reply pattern gains a few more commands.
- Calendar colour and join detection depend on what the calendar account provides, so a few events will show no Join button.

## Follow-up

- [ ] Verify on a real Mac that `ical://ekevent/<id>` opens the right event on macOS 13, 14 and 15; if not, fall back to opening Calendar only.
- [ ] Verify the TCC prompt appears for the helper (it is a `LSUIElement` child process) and names DeskNotch Helper clearly.
- [ ] A separate spec for Windows (Outlook through PowerShell, or an ICS link).
- [ ] Optional later: a notch pop up a few minutes before an event, like the Reminder view.
