# 0009. Birthdays, holidays and festivals in the calendar

**Date**: 2026-10-29
**Status**: In Progress

## Summary

Your Mac's Calendar app already holds birthdays and holidays or festivals (for example an India holidays calendar you subscribed to). The notch already receives them, but they look like any other event, so a birthday is easy to miss. This change marks them: a small cake icon for birthdays and a flag icon for holidays and festivals, shown in the Today and Tomorrow list, and in a "Special days" strip at the top of a day's pane. Data still comes only from the Calendar app, so there is no new permission and no new network use. The Swift helper sends one extra field per event (the calendar's kind: birthday, one you cannot edit, or one you can) so the app can tell them apart.

## Context

Enhancement of the Calendar view (specs 0003 and 0008). Stack: Electron 43, Next 16, React 19, Tailwind 4, macOS only for the calendar. No `AGENTS.md` and no `docs/scope/` exist, so this is a standalone spec, not linked to a scope row. Spec 0008 is still In Progress; this spec builds on its day pane and does not change its acceptance criteria.

How it works today, read from the code:
- `native/mac/Calendar.swift` asks EventKit for events with `calendars: nil`, which means every calendar on the Mac, including the Birthdays calendar and any holiday calendar. Each event is sent with `calendarId` and `calendarColor`, but not the calendar's kind, so the app cannot tell a birthday from a meeting.
- Checked on the author's Mac (2026-10-29): the Birthdays calendar (EventKit type birthday) is returned, and its events arrive with that type. The holiday calendars are not all of one type: "India Holidays" is a subscribed calendar, but both "Holidays in India" calendars come through a Google account (type calDAV). What they all share is that you cannot edit them. Your own calendars (Home, Work, your Gmail one) are editable.
- `CalendarView.tsx` draws every event with the same row (`EventRow`): colour dot, title, time. All day items such as holidays and birthdays are sorted first but look like any other row.
- The Home next event line uses `nextToday`, which only looks at timed events, so all day items never reach it.
- Settings can switch a calendar off by `calendarId`; the Birthdays or Holidays calendar can be hidden the same way as any other.

Build approach: none is recorded for this project, so this plan assumes a thin end to end slice first (Tracer Bullet): send the field, show the icon in one place, then the strip.

This spec amends spec 0008 in one place: it said the helper is unchanged. Here the helper sends one extra field. It stays read only and no write API of EventKit is used.

## Requirements

**User stories**:
- As a Mac user, I want birthdays and festivals to stand out on the notch, so that I do not miss them when I look ahead.
- As someone who clicks a day, I want its birthdays and holidays listed at the top of that day, the way Calendar shows them, so that I know what the day is before the meetings.

**Acceptance criteria** (each independently checkable):
- **AC-1**: Every event the helper returns has a `calendarType` of `birthday` (an EventKit birthday calendar), `readonly` (any other calendar whose content you cannot edit, `allowsContentModifications` is false: a subscribed calendar, a Google holidays calendar) or `other` (a calendar you can edit). Nothing is written to any calendar.
- **AC-2**: An event is a **birthday** when its `calendarType` is `birthday`. It is a **holiday or festival** when its `calendarType` is `readonly` and it is an all day event. Everything else is a normal event, including timed events from a read only calendar and all day items on a calendar you can edit (a trip or day off you added yourself).
- **AC-3**: In the Today and Tomorrow list, a birthday row shows a cake icon and a holiday row a flag icon, in place of the colour dot, in the calendar's colour. The row keeps its title and position (all day items first). It shows no time text and no Join button. Clicking it opens Calendar, as for any event.
- **AC-4**: In the day pane of spec 0008, birthdays and holidays are listed first in a strip headed "Special days", above the normal events, with the same icons and no time text. They are not greyed on a past day. The strip is left out when the day has none.
- **AC-5**: The pane count line adds "1 special day" or "N special days" before the event count, only when N is above zero. The event count no longer includes special days, so "3 events" means three normal events.
- **AC-6**: Special days from a calendar switched off in Settings are not listed, not counted and give no dot. Switching it on brings them back, with no restart.
- **AC-7**: The grid dot rule of spec 0008 is unchanged: a special day gives the same dot as any event. No new colour or shape in the grid.
- **AC-8**: The Home next event line and the Join buttons are unchanged. A birthday or holiday never appears on the Home line.
- **AC-9**: If the helper does not send `calendarType` (an older helper binary), every event is treated as normal, and nothing breaks or is missing.
- **AC-10**: The Calendar view stays 580 by 200. The strip scrolls with the rest of the pane, and a day with several special days is not clipped.
- **AC-11**: Titles of birthdays and holidays are never logged or written anywhere. They stay in memory, like all events.

## Options considered

### Option 1: Calendar kind from the helper, icons and a strip (chosen)

The helper adds `calendarType` (birthday, readonly, other); the app derives the kind from it and the all day flag, and draws an icon plus a "Special days" strip. Revised 2026-10-29: the first draft said `subscribed` instead of `readonly`, which missed the Google holiday calendars.

**Pros**:
- Uses what the Mac already has. No new permission, no network, no list of dates to keep up to date, and moving festivals (Diwali, Eid) are right because the calendar owner publishes them.
- One extra field, a few lines of Swift.

**Cons**:
- A holiday only shows if the person has a holiday calendar in the Calendar app. The notch cannot invent one.
- Any all day item in a calendar you cannot edit (for example moon phases, or a colleague's shared calendar) is also treated as a holiday. The Settings switch for that calendar is the way out.

### Rules weighed for what counts as a holiday

- **Any all day event from a non birthday calendar**: rejected. It would flag your own all day entries (a trip, a day off) as holidays.
- **Match the calendar name ("holiday", "festival")**: rejected. It guesses from a title, and fails for other languages.
- **A per calendar "Treat as holidays" switch**: kept as a later option, not needed now, because the editable or not signal already separates them on this Mac.
- **Only subscribed calendars (the first draft)**: rejected, it missed both Google holiday calendars.

### Option 2: Ship a built in holiday list for a chosen country

**Pros**:
- Works with nothing set up in Calendar.

**Cons**:
- Needs a data source and yearly upkeep, a country setting, and a way to keep moving festival dates right.
- Duplicates what Calendar already shows, so holidays would appear twice for people who subscribed.

### Option 3: Read birthdays straight from Contacts

**Pros**:
- Could show age.

**Cons**:
- A second macOS permission and a second read path in the helper, for something the Birthdays calendar already provides.

## Decision

**Chosen option**: Option 1: Calendar kind from the helper, icons and a strip. A holiday is an all day event from a calendar you cannot edit.

## Rationale

The data is already on the notch; the gap is that nothing marks it. The calendar's type and whether it can be edited are the facts EventKit gives that separate a birthday or a holiday calendar from a person's own events, so sending that one field is the smallest change that makes the difference visible. Choosing the Calendar app as the only source keeps the read only promise of spec 0003, avoids a new permission, and lets moving festivals stay correct without any date table in this app. Limiting the "holiday" meaning to all day items of calendars you cannot edit keeps your own all day entries out, and works for subscribed and Google holiday calendars without guessing from names. A read only fixture list with all day items would also count, and the Settings switch is the way out.

## Feature design

**Data model** (no database, no stored change):

| Entity | Fields | Notes |
|---|---|---|
| CalendarEvent | adds `calendarType: 'birthday' \| 'readonly' \| 'other'` | Optional in the type, because an older helper does not send it. Missing means `other`. |
| Kind (derived, not stored) | `birthday`, `holiday`, `event` | Computed by one function `kindOf(event)` in `useCalendar.ts`, from `calendarType` and `allDay` (AC-2). |

**Where code goes**:
- `native/mac/Calendar.swift`: in the `calendarEvents` map add `"calendarType"`, from `$0.calendar.type` and `$0.calendar.allowsContentModifications`: `.birthday` gives `"birthday"` (checked first, the Birthdays calendar is also not editable), a calendar that cannot be edited gives `"readonly"`, anything else `"other"`. No other change.
- `renderer/hooks/useCalendar.ts`: add `calendarType` to `CalendarEvent`, and export `kindOf(event)`.
- `renderer/components/widgets/CalendarView.tsx`: `EventRow` shows the `Cake` or `Flag` icon from `lucide-react` (already used here) instead of the colour dot when `kindOf` is not `event`, and drops the time text. `DayPane` splits its list by `kindOf`, draws the "Special days" strip, and changes the count line.
- No change to `main/ipc/calendar.ts` (it relays events whole; `calendarType` passes through), to the settings keys, or to `home.tsx`.
- The helper binary must be rebuilt with the project's usual helper build before this works. Windows is untouched.

**Value sourcing** (every value an action shows or produces, with its source):

| Action | Value | Source |
|---|---|---|
| Classify an event | birthday, holiday or event | `kindOf(event)`: `calendarType === 'birthday'`, or `calendarType === 'readonly' && allDay`, else event |
| Send the type | `calendarType` | `EKCalendar.type` and `allowsContentModifications` of the event's calendar, in the helper |
| Row icon | cake or flag | `kindOf`: birthday gives `Cake`, holiday gives `Flag` |
| Row icon colour | colour | the event's existing `calendarColor` |
| Row title | name | the event's `title`, unchanged ("Rahul's Birthday" comes from Calendar as is) |
| Strip contents | special days of the day | the day's overlapping visible events where `kindOf` is not `event` (same overlap rule as spec 0008) |
| Count line | special days, events, tasks | strip length; events minus special days; tasks as in 0008 |
| Hidden by Settings | which are removed | the existing `hidden` calendar id list, applied before classifying |

**Edge cases decided here**:
- A birthday with no event id (Calendar does not always give one): clicking falls back to opening the Calendar app, which `calendar:openEvent` already does for an empty id.
- A holiday that spans several days shows in the strip of every day it covers.
- Two calendars with the same holiday show it twice; Settings can switch one off. No de duplication.
- A read only calendar's timed event is a normal event.
- An all day event on a calendar you can edit is a normal event, even if it is named like a holiday.
- A birthday in a Birthdays calendar that the person has switched off in Calendar itself is not returned by EventKit, so it is not shown. Nothing to do here.

**Security model**: no new surface. No new ipc channel, no new permission. Birthday names are personal data from Contacts via Calendar; they stay in memory and are never logged or stored (AC-11).

**Critical test scenarios**:
- A date with a birthday: cake row in Today or Tomorrow, strip in the day pane, no time text, no Join, verifies **AC-3**, **AC-4**.
- A festival from a read only holidays calendar (the subscribed one and the Google ones): flag row and strip entry, verifies **AC-2**, **AC-3**, **AC-4**.
- A read only calendar with a timed event: shows as a normal event, verifies **AC-2**.
- Count line on a day with 1 birthday, 2 meetings, 1 task: "1 special day, 2 events, 1 task", verifies **AC-5**.
- Switch the Holidays calendar off in Settings, then on, verifies **AC-6**.
- Home line with only a birthday today shows no birthday, verifies **AC-8**.
- Run with the old helper binary: nothing breaks, verifies **AC-9**.
- A day with four special days in the pane scrolls, verifies **AC-10**.

## Build plan

1. Thin thread: helper sends `calendarType`, add the field to the type and `kindOf` in `useCalendar.ts`, show the icon in `EventRow`. Rebuild the helper and see a birthday with a cake in the Today and Tomorrow list. Satisfies **AC-1**, **AC-2**, **AC-3**, **AC-9**.
2. Day pane: split by `kindOf`, the "Special days" strip, the count line. Satisfies **AC-4**, **AC-5**, **AC-10**.
3. Check the Settings switch, the Home line, the grid dot and the Join rules still hold. Satisfies **AC-6**, **AC-7**, **AC-8**, **AC-11**.
4. Docs: add special days to `doc/Functionality.md` and `README.md`. Satisfies **AC-3**, **AC-4**.

## Consequences

**Positive**:
- Birthdays and festivals stand out, with no new permission and no data to maintain.
- Moving festivals are correct because the calendar owner publishes them.
- Tiny change: one Swift field, one function, one icon, one strip.

**Negative / tradeoffs**:
- If no holiday calendar is in the Calendar app, no festivals show. The Follow up covers a nudge.
- Any all day item in a calendar you cannot edit is called a holiday.
- The helper must be rebuilt, so this is not a renderer only change like most of 0008.

**Neutral**:
- Spec 0008 AC-3 and AC-2 still hold; special days are events that are drawn and counted differently.

## Follow-up

- [ ] Rebuild the helper with the normal helper build before testing step 1.
- [x] Confirmed 2026-10-29 on the author's Mac: the Birthdays calendar is returned and its events have type birthday (one found in the next year). No second read path needed.
- [ ] Optional later: a one line hint in the Calendar view when no holiday calendar exists ("Add a holidays calendar in Calendar to see festivals here").
- [ ] Optional later: a "Treat as holidays" switch per calendar in Settings, for an editable calendar someone wants counted as holidays.
- [ ] Optional later: Apple Reminders due dates as tasks on a day (needs a Reminders permission, left out here by choice).
- [ ] Add a scope row for this feature if a `docs/scope/` is started.
