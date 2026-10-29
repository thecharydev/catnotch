/**
 * The Mac's calendars on the notch (docs/specs/0003-notch-calendar-agenda.md).
 * The Swift helper reads them with EventKit; this file only relays, and holds
 * the join links of the last read so the page can only ask by event id.
 * Events are never logged or written anywhere.
 */
import { BrowserWindow, ipcMain, shell } from 'electron'
import { execFile } from 'child_process'
import { askHelper, watchHelper } from '../mac/helper'

type Status = 'unknown' | 'granted' | 'denied' | 'unavailable'
type Reply = { status: Status; events?: { id: string; joinUrl: string | null }[]; calendars?: unknown[] }

const HOSTS = ['meet.google.com', 'teams.microsoft.com', 'teams.live.com']
/** An https link to Zoom, Meet or Teams, and nothing else. */
const joinable = (link: string) => {
  try {
    const url = new URL(link)
    return url.protocol === 'https:' && (url.hostname === 'zoom.us' || url.hostname.endsWith('.zoom.us') || HOSTS.includes(url.hostname))
  } catch {
    return false
  }
}

/** Event id to join link, from the last read. */
const joins = new Map<string, string>()

export function registerCalendarIpc() {
  const status = async (command: string, wait?: number): Promise<Status> =>
    (await askHelper<Reply>(command, {}, wait))?.status ?? 'unavailable'

  ipcMain.handle('calendar:status', () => status('calendarStatus'))
  // Only the Allow button sends this; the macOS prompt waits for the person, so wait long.
  ipcMain.handle('calendar:request', () => status('calendarRequest', 120_000))
  ipcMain.handle('calendar:calendars', async () => (await askHelper<Reply>('calendarList'))?.calendars ?? [])

  ipcMain.handle('calendar:events', async (_event, from: unknown, to: unknown) => {
    if (typeof from !== 'string' || typeof to !== 'string') return { status: 'unavailable', events: [] }
    const reply = await askHelper<Reply>('calendarEvents', { from, to })
    if (!reply) return { status: 'unavailable', events: [] }
    joins.clear()
    for (const event of reply.events ?? []) {
      if (event.joinUrl && joinable(event.joinUrl)) joins.set(event.id, event.joinUrl)
      else event.joinUrl = null
    }
    return reply
  })

  ipcMain.handle('calendar:watch', (_event, on: boolean) =>
    watchHelper('watchCalendar', ['calendarChanged'], on === true, () => {
      for (const window of BrowserWindow.getAllWindows()) window.webContents.send('calendar:changed')
    }),
  )

  ipcMain.handle('calendar:join', (_event, id: unknown) => {
    const link = typeof id === 'string' ? joins.get(id) : undefined
    if (link && joinable(link)) void shell.openExternal(link)
  })

  ipcMain.handle('calendar:openEvent', (_event, id: unknown) => {
    const openCalendar = () => execFile('open', ['-a', 'Calendar'], () => {})
    if (typeof id !== 'string' || !id) openCalendar()
    else shell.openExternal(`ical://ekevent/${encodeURIComponent(id)}?method=show&options=more`).catch(openCalendar)
  })

  ipcMain.handle('calendar:openPrivacy', () =>
    shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars'),
  )
}
