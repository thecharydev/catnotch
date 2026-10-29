# 0008. Calendar day details and tasks per day

**Date**: 2026-10-29
**Status**: In Progress

## Summary

Today the Calendar view shows a small month grid that you cannot use, and a fixed list of today and tomorrow. This change makes the grid work. You click any day and the right side switches to that day: its date, how many events and tasks it has, the events with their times, and the tasks due that day. You can tick, add and remove tasks right there. You can also move between months, and days that have something on them get a small dot. To make "tasks for a day" mean something, a task gets an optional due day. Nothing changes in the Swift helper or in what is read from your calendar, and Windows is not touched.

## Context

Enhancement of the Calendar view built under spec 0003 (`renderer/components/widgets/CalendarView.tsx`, `renderer/hooks/useCalendar.ts`, `main/ipc/calendar.ts`, `native/mac/Calendar.swift`). Stack: Electron 43, Next 16, React 19, Tailwind 4, macOS only for the calendar. No `AGENTS.md` and no `docs/scope/` exist, so this is a standalone spec, not linked to a scope row.

How it works today, read from the code:
- `Month` draws the current month only. Days are plain spans with no click and no arrows.
- `useCalendar` asks the helper for events from now to the end of tomorrow (`dayStart(now, 2)`). Ended events are removed in the renderer by `upcoming`, not in the helper. The helper returns every event inside whatever `from` and `to` it is given, so it needs no change.
- Tasks are `{ id, label, done }` held by `useTasks` in the store key `todos`. They have no date, so there is nothing to show "for a day" yet.
- `main/ipc/calendar.ts` keeps one `joins` map (event id to join link) and clears it on every `calendar:events` call. That is fine as long as there is only ever one events query at a time, so this spec uses one query, not two.

Build approach: none is recorded for this project, so this plan assumes a thin end to end slice first (Tracer Bullet): select a day, show its events, then grow.

This spec amends spec 0003 in one place. AC-4 there says ended events are not shown. That stays true for the default Today and Tomorrow list. The new day pane shows ended events greyed, because a past day would otherwise always look empty.

## Requirements

**User stories**:
- As a Mac user, I want to click a day on the calendar and see what is on it, so that I can look ahead or back without opening Calendar.
- As someone who plans with tasks, I want to see the tasks for that day beside its events, so that I can see my whole day in one place.
- As someone planning ahead, I want to add a task to a day from the calendar, so that I do not have to switch views.

**Acceptance criteria** (each independently checkable):
- **AC-1**: Clicking a day number in the month grid selects it and the right side shows that day's pane. The selected day has its own ring, different from today's filled accent. Clicking the selected day again, or the Today button (AC-6), clears the selection and brings back the Today and Tomorrow list exactly as it is now.
- **AC-2**: The pane starts with a heading of the weekday and date in the Mac's locale (for example "Thursday, 29 October"), then a count line such as "3 events, 2 tasks". Zero reads "No events" or "No tasks". One reads "1 event" or "1 task".
- **AC-3**: The pane lists that day's events, all day ones first and then by start time, using the same row as today (colour dot, title, "start to end" or "All day", Join when allowed, click opens the event in Calendar). An event that has already ended is shown greyed, not hidden. Events from calendars switched off in Settings are not listed or counted. Declined and cancelled events never appear (the helper already drops them).
- **AC-4**: Below the events the pane lists that day's tasks: tasks whose due day is that day, and, only when the selected day is today, tasks with no due day. Open tasks come first, done tasks after, greyed with a ticked box. If `showTasks` is off in Settings, the task part of the pane is not shown and tasks are left out of the count line and the dots.
- **AC-5**: In the pane you can tick or untick a task, remove it, and add one. A task added there gets that day as its due day. Changes go through the shared `useTasks` store, so they show at once in the Tasks view and the glance row, and survive a restart. A task with no label is not added.
- **AC-6**: The month heading has previous and next arrows. The grid shows the real days of any month. A Today button appears whenever the shown month is not the current month or a day is selected, and clicking it returns to the current month with nothing selected.
- **AC-7**: A day shows a small dot under its number when it has at least one visible event or at least one open task due that day. The dot updates when events or tasks change. Undated tasks never make a dot.
- **AC-8**: Events for the shown month load without leaving the view: after an arrow click the new month's events show within 2 seconds. The existing refresh rules (Calendar app changes within 5 seconds, 5 minute safety query, per minute clock) keep working for the month on screen. The helper and the helper commands are unchanged and nothing is written to any calendar.
- **AC-9**: Browsing another month, or selecting a day, never changes the Home next event line, the Today and Tomorrow list, or the Join buttons. Join and open in Calendar work for events on any day shown.
- **AC-10**: With calendar access not granted, the grid still works and a selected day shows its tasks, with one line "Calendar access is off" where the events would be. The unselected right side still shows the existing explainer, Allow button and access states from spec 0003.
- **AC-11**: A task may have an optional `due` field. Tasks saved before this change have none and keep working with no migration. The Tasks view and Quick add behave as before and never set a due day.
- **AC-12**: The Calendar view stays 580 by 200 (no size change). The pane scrolls inside itself, and a month that needs six rows still fits the grid without clipping.

## Options considered

### Option 1: Optional due day on tasks, day pane on the right (chosen)

Add `due` to a task, widen the event query to the shown month, add selection and month state, and add a day pane beside the grid.

**Pros**:
- Gives every day a real answer to "which tasks", with the smallest data change (one optional field).
- No helper, ipc or permission change; the renderer already has all the pieces.
- Old tasks need no migration.

**Cons**:
- Undated tasks only show on Today, so a task without a date is easy to miss on other days. That is the intended meaning.
- Overdue open tasks do not follow you to Today (see Follow-up).

### Option 2: Show all open tasks on every day

**Pros**:
- No data change.

**Cons**:
- Every day looks the same, so it adds nothing.

### Option 3: Tasks by the day they were finished

**Pros**:
- No due date to enter.

**Cons**:
- Needs a completed at stamp, shows nothing for future days, and does not help planning.

## Decision

**Chosen option**: Option 1: Optional due day on tasks, day pane on the right.

## Rationale

The question "what tasks are on this day" can only be answered if a task knows its day, and an optional field is the smallest thing that does it without touching existing data. Putting the pane on the right reuses the space that already shows the agenda, so the notch size and layout stay as they are. One widened query (instead of one per day, or two) keeps the helper untouched and keeps the single join map in `main/ipc/calendar.ts` correct.

## Feature design

**Data model** (no database; the store keeps one list):

| Entity | Fields | Notes |
|---|---|---|
| Task (store key `todos`) | `id` string, `label` string, `done` boolean, `due` optional string `YYYY-MM-DD` | `due` is a local day, built from the local year, month and day, never from `toISOString()` (that is UTC and shifts the day). Missing `due` means undated. |
| CalendarEvent | unchanged | from spec 0003 |
| UI state (not stored) | `month` (first day of the shown month), `selected` (a local day or none) | `month` lives in `useCalendar`, `selected` in `CalendarView`. Both reset when the view closes. |

**Where code goes**:
- `renderer/hooks/useTasks.ts`: `Task` gains `due?: string`. `add(label, due?)` stores it. Export `dayKey(date: Date)` returning the local `YYYY-MM-DD`.
- `renderer/hooks/useCalendar.ts`: the hook owns `month` and `setMonth` and returns them. The query window is one range, `from = min(first day of month, today)` to `to = max(first day of the next month, end of tomorrow)`. Re query whenever `month` changes. Add `visible(events, hidden)` that only removes events from hidden calendars (no ended filter), used for the dots and the pane. `upcoming` stays as is for Home and the default list.
- `renderer/components/widgets/CalendarView.tsx`: `Month` becomes interactive (arrows, day buttons, dots, selected ring, Today button). A new `DayPane` renders the heading, count line, events and tasks. `CalendarView` receives the new props: `month`, `onMonth`, the visible events (calendars switched off already removed), `tasks: TaskStore`, and `showTasks`.
- `renderer/pages/home.tsx`: pass the new props. The Home line keeps using `upcoming` and `nextToday`, which still work on the wider event list because they filter by time.
- No change to `native/mac`, `main/ipc/calendar.ts`, or the settings keys.

**Value sourcing** (every value an action shows or produces, with its source):

| Action | Value | Source |
|---|---|---|
| Select a day | the day | the grid cell clicked, built as a local midnight `Date` from the shown month and the cell number |
| Query a month | `from`, `to` | computed by `useCalendar` from `month`, today and end of tomorrow (rule above), local time of the Mac |
| Day's events | which events are on a day | the existing overlap rule: `start < next midnight` and `end > this midnight`, on the visible list |
| Event row time | "All day" or "start to end" | the existing `timeText(event, day)` with the selected day |
| Greyed event | ended | `end <= now`, from the per minute clock `now` |
| Day's tasks | tasks shown | `task.due === dayKey(day)`, plus `!task.due` when `dayKey(day) === dayKey(now)` |
| Dot | has something | any visible event overlapping the day, or any open task with `due === dayKey(day)` |
| Count line | the numbers | the lists above, counted; tasks counted are the ones shown in the pane |
| New task's due | `due` | `dayKey(selected day)`; never set from anywhere else |
| Heading text | weekday and date | `Intl.DateTimeFormat` with the system locale, no override |
| Month label | month and year | `month` state, formatted with the system locale |
| Grid cells | leading blanks and day count | `new Date(year, month, 1).getDay()` (Sunday first, as the header already reads) and days in month |

**Edge cases decided here**:
- A multi day event shows in the pane of every day it covers, as "All day" (same as spec 0003).
- A task added on a past day is allowed.
- Open tasks whose due day has passed stay on their own day and keep its dot. They do not move to Today.
- Many events or tasks scroll inside the pane. No row limit.
- Selecting a day, then moving to another month, keeps the selection only if it is inside the new month; otherwise it clears.
- The selected day and `month` reset to nothing and the current month each time the view is opened.
- Event and task text is never logged or written by this feature (events stay in memory, tasks follow the existing store).

**Security model**: no new surface. The renderer still only passes event ids to open or join, and the main process still validates join links. No new ipc channel.

**Critical test scenarios**:
- Click a day with events and tasks, see heading, counts, events and tasks, verifies **AC-1**, **AC-2**, **AC-3**, **AC-4**.
- Click the selected day again, see the Today and Tomorrow list return, verifies **AC-1**.
- Add, tick and remove a task in the pane, then open the Tasks view and see the same state, restart and still there, verifies **AC-5**.
- Next and previous month, events appear, Today button resets, verifies **AC-6**, **AC-8**.
- Dots on busy days, and none for undated tasks, verifies **AC-7**.
- Browse another month and confirm the Home line and Join buttons still work, verifies **AC-9**.
- Deny calendar access, select a day, see tasks and the one line note, verifies **AC-10**.
- Load an old `todos` list with no `due`, nothing breaks, verifies **AC-11**.
- A six row month and a day with many items, nothing clipped, verifies **AC-12**.
- Turn `showTasks` off, tasks vanish from the pane, count and dots, verifies **AC-4**, **AC-7**.

## Build plan

1. Data: add `due` to `Task`, `add(label, due?)`, and export `dayKey` in `useTasks.ts`. Satisfies **AC-5**, **AC-11**.
2. Hook thin thread: `month` and `setMonth` in `useCalendar`, the widened query window, re query on month change, and `visible()`. Satisfies **AC-8**, **AC-9**.
3. Grid: make `Month` interactive with arrows, day buttons, selected ring, Today button and month label from state. Satisfies **AC-1**, **AC-6**, **AC-12**.
4. Day pane events: `DayPane` with heading, count line and the event rows (greyed when ended), wired in `CalendarView` and `home.tsx`. Satisfies **AC-2**, **AC-3**, **AC-9**.
5. Day pane tasks: the task list, tick, remove, add with `due`, the `showTasks` rule, and the no access note. Satisfies **AC-4**, **AC-5**, **AC-10**.
6. Dots: event and open task dots on the grid. Satisfies **AC-7**.
7. Checks and docs: walk the test scenarios above, run type check and build, add the day pane to `doc/Functionality.md` and `README.md`. Satisfies **AC-11**, **AC-12**.

## Consequences

**Positive**:
- The calendar becomes useful beyond today and tomorrow, and tasks finally have a place in time.
- Small: no helper rebuild, no new ipc, one optional field.
- The old data and the Windows build are untouched.

**Negative / tradeoffs**:
- Undated tasks only show on Today, and overdue tasks do not roll forward.
- The grid is tight in a 200 pixel high view, so the dots and arrows must be drawn without adding height.
- A wider query reads more events into memory (still only in memory, a month at most).

**Neutral**:
- Spec 0003 AC-4 is amended for the day pane only (ended events greyed, not hidden).

## Follow-up

- [ ] Decide whether open overdue tasks should also show on Today.
- [ ] Optional later: a date field in Quick add and the Tasks view, and an "add to this day" action on undated tasks.
- [ ] Optional later: show an event's location in the pane (needs the helper to send it, a privacy change to spec 0003).
- [ ] Add a scope row for this feature if a `docs/scope/` is started.
