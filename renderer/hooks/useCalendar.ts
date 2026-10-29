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
  joinUrl: string | null
}
export type CalendarInfo = { id: string; title: string; color: string; account: string }

/** Midnight of the Mac's local day `offset` days from `from`. */
export const dayStart = (from: Date, offset = 0) => new Date(from.getFullYear(), from.getMonth(), from.getDate() + offset)

/**
 * The Mac calendar's events from now to the end of tomorrow (read only, held
 * in memory only). Asked again when the view opens, when the Calendar app
 * changes, and every 5 minutes. `on` is false off macOS or with Calendar off.
 */
export function useCalendar(on: boolean, open: boolean) {
  const [access, setAccess] = useState<CalendarAccess>('unknown')
  const [events, setEvents] = useState<CalendarEvent[]>([])

  const refresh = useCallback(async () => {
    const now = new Date()
    const reply = await window.bridge?.invoke<{ status: CalendarAccess; events: CalendarEvent[] }>(
      'calendar:events',
      now.toISOString(),
      dayStart(now, 2).toISOString(),
    )
    if (!reply) return
    setAccess(reply.status)
    setEvents(reply.status === 'granted' ? reply.events : [])
  }, [])

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

  return { access, events, allow }
}

/** What is still to come or on now, in the order the view shows it. */
export const upcoming = (events: CalendarEvent[], hidden: string[], now: Date) =>
  events
    .filter((e) => !hidden.includes(e.calendarId) && new Date(e.end) > now)
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
