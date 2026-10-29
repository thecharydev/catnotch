import { useCallback, useEffect, useState } from 'react'

export type CalendarAccess = 'unknown' | 'granted' | 'denied' | 'unavailable'
export type CalendarEvent = {
  id: string
  title: string
  start: string
  end: string
  allDay: boolean
  calendarId: string
  calendarColor: string
  /** Missing when an older helper binary sent the event: treated as `other`. */
  calendarType?: 'birthday' | 'readonly' | 'other'
  joinUrl: string | null
}

/** Birthday, holiday (all day item of a calendar you cannot edit) or a normal event. */
export const kindOf = (e: CalendarEvent): 'birthday' | 'holiday' | 'event' =>
  e.calendarType === 'birthday' ? 'birthday' : e.calendarType === 'readonly' && e.allDay ? 'holiday' : 'event'
export type CalendarInfo = { id: string; title: string; color: string; account: string }

/** Midnight of the Mac's local day `offset` days from `from`. */
export const dayStart = (from: Date, offset = 0) => new Date(from.getFullYear(), from.getMonth(), from.getDate() + offset)

/**
 * The Mac calendar's events for the shown month plus today and tomorrow (read
 * only, held in memory only). Asked again when the view opens, when the Calendar app
 * changes, and every 5 minutes. `on` is false off macOS or with Calendar off.
 */
export function useCalendar(on: boolean, open: boolean) {
  const [access, setAccess] = useState<CalendarAccess>('unknown')
  const [events, setEvents] = useState<CalendarEvent[]>([])
  const [month, setMonth] = useState(() => new Date(new Date().getFullYear(), new Date().getMonth(), 1))

  // Each time the view opens it starts on the current month.
  useEffect(() => {
    if (open) setMonth(new Date(new Date().getFullYear(), new Date().getMonth(), 1))
  }, [open])

  const refresh = useCallback(async () => {
    const now = new Date()
    const from = new Date(Math.min(+month, +dayStart(now)))
    const to = new Date(Math.max(+new Date(month.getFullYear(), month.getMonth() + 1, 1), +dayStart(now, 2)))
    const reply = await window.bridge?.invoke<{ status: CalendarAccess; events: CalendarEvent[] }>(
      'calendar:events',
      from.toISOString(),
      to.toISOString(),
    )
    if (!reply) return
    setAccess(reply.status)
    setEvents(reply.status === 'granted' ? reply.events : [])
  }, [month])

  useEffect(() => {
    if (!on) return
    void refresh()
    const timer = setInterval(() => void refresh(), 5 * 60_000)
    return () => clearInterval(timer)
  }, [on, refresh, open])

  const watching = on && access === 'granted'
  useEffect(() => {
    if (!watching) return
    void window.bridge?.invoke('calendar:watch', true)
    const off = window.bridge?.on('calendar:changed', () => void refresh())
    return () => {
      off?.()
      void window.bridge?.invoke('calendar:watch', false)
    }
  }, [watching, refresh])

  /** Only the Allow button calls this: it is what makes macOS ask. */
  const allow = async () => {
    const status = await window.bridge?.invoke<CalendarAccess>('calendar:request')
    if (status) setAccess(status)
    void refresh()
  }

  return { access, events, allow, month, setMonth }
}

/** Events from calendars that are switched on, ended ones included (the day pane greys them). */
export const visible = (events: CalendarEvent[], hidden: string[]) => dedupe(events.filter((e) => !hidden.includes(e.calendarId)))

/** The same special day from two calendars (two holiday calendars) shows once. */
const dedupe = (events: CalendarEvent[]) => {
  const seen = new Set<string>()
  return events.filter((e) => {
    if (kindOf(e) === 'event') return true
    const key = `${e.title.trim().toLowerCase()}|${e.start}`
    return !seen.has(key) && !!seen.add(key)
  })
}

/** What is still to come or on now, in the order the view shows it. */
export const upcoming = (events: CalendarEvent[], hidden: string[], now: Date) =>
  dedupe(events.filter((e) => !hidden.includes(e.calendarId)))
    .filter((e) => new Date(e.end) > now)
    .sort((a, b) => Number(b.allDay) - Number(a.allDay) || +new Date(a.start) - +new Date(b.start))

/** The next timed event today, for the Home line. */
export const nextToday = (list: CalendarEvent[], now: Date) => {
  const midnight = +dayStart(now, 1)
  return list.find((e) => !e.allDay && +new Date(e.start) < midnight)
}

export const untilText = (event: CalendarEvent, now: Date) => {
  const minutes = Math.ceil((+new Date(event.start) - +now) / 60_000)
  if (minutes <= 0) return 'now'
  return minutes < 60 ? `in ${minutes} min` : `in ${Math.floor(minutes / 60)} h${minutes % 60 ? ` ${minutes % 60} min` : ''}`
}
