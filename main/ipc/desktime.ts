/**
 * Screen time from ScreenWise (bruhlabs.top/download), a separate app.
 *
 * ScreenWise has no API or pub/sub: it keeps everything in a local SQLite file.
 * So it is read directly, read-only, with the same sum ScreenWise's own
 * dashboard and tray use for "screen time today". Not installed, no reading:
 * the notch's option stays greyed out with a download link.
 *
 * "Installed" is Windows' own list of installed programs, not the database:
 * uninstalling leaves the database behind in AppData, and reading that showed
 * stale screen time for an app that was gone.
 */
import { ipcMain, shell } from 'electron'
import { execFile } from 'child_process'
import fs from 'fs'
import path from 'path'

/** Where installers register themselves: per user, per machine, and 32-bit per machine. */
const UNINSTALL_KEYS = [
  'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall',
  'HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall',
  'HKLM\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall',
]
const APP_NAME = /^\s*DisplayName\s+REG_SZ\s+ScreenWise\b/im

/** Every DisplayName under one uninstall key, as `reg query` prints them. */
const displayNames = (key: string) =>
  new Promise<string>((resolve) =>
    execFile('reg', ['query', key, '/s', '/v', 'DisplayName'], { windowsHide: true, maxBuffer: 8 << 20 }, (_error, stdout) => resolve(stdout ?? '')),
  )

/** Whether ScreenWise is installed. Asked at most once a minute. */
let installedCache: { at: number; value: boolean } | null = null
const isInstalled = async () => {
  if (installedCache && Date.now() - installedCache.at < 60_000) return installedCache.value
  const value = (await Promise.all(UNINSTALL_KEYS.map(displayNames))).some((out) => APP_NAME.test(out))
  installedCache = { at: Date.now(), value }
  return value
}

/** ScreenWise's download page. */
export const DESKTIME_URL = 'https://www.bruhlabs.top/download'

/** ScreenWise's database, in its data folder (named after the app). Its file
 *  may still carry the app's earlier name, so both are looked for. */
const DB_FILES = [
  ['ScreenWise', 'screenwise.db'],
  ['ScreenWise', 'desktime.db'],
]
const dbFile = () =>
  DB_FILES.map(([dir, file]) => path.join(process.env.APPDATA ?? '', dir, file)).find((file) => fs.existsSync(file)) ?? null

/** ScreenWise's own query (db.ts dayTotals): active + idle, hidden apps left out. */
const TODAY_SQL = `
  SELECT COALESCE(SUM(u.screen), 0) AS screen FROM (
    SELECT app_id, end_ts - start_ts AS screen FROM sessions WHERE day = ?
    UNION ALL
    SELECT app_id, active + idle FROM daily_totals WHERE day = ?
  ) u JOIN apps a ON a.id = u.app_id JOIN apps e ON e.id = COALESCE(a.merged_into, a.id)
  WHERE e.hidden = 0`

/** ScreenWise's day label: late nights before its day-start hour count toward yesterday. */
const dayLabel = (now: Date, dayStartHour: number) => {
  const d = new Date(now)
  if (d.getHours() < dayStartHour) d.setDate(d.getDate() - 1)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}

export interface ScreenTime {
  installed: boolean
  /** Today's screen time in ms, or null when it could not be read. */
  ms: number | null
}

async function readScreenTime(): Promise<ScreenTime> {
  // ScreenWise is Windows only: on macOS the tile stays hidden.
  if (process.platform !== 'darwin') return readWindowsScreenTime()
  return { installed: false, ms: null }
}

async function readWindowsScreenTime(): Promise<ScreenTime> {
  const file = dbFile()
  if (!file || !(await isInstalled())) return { installed: false, ms: null }
  let db: import('node:sqlite').DatabaseSync | undefined
  try {
    // getBuiltinModule, not import: the main bundle's webpack does not know node:sqlite.
    const { DatabaseSync } = process.getBuiltinModule('node:sqlite') as typeof import('node:sqlite')
    db = new DatabaseSync(file, { readOnly: true })
    const saved = db.prepare("SELECT value FROM settings WHERE key = 'settings'").get() as { value?: string } | undefined
    const hour = Number(JSON.parse(saved?.value ?? '{}').dayStartHour) || 0
    const day = dayLabel(new Date(), hour)
    const row = db.prepare(TODAY_SQL).get(day, day) as { screen: number }
    return { installed: true, ms: Number(row.screen) }
  } catch (err) {
    // A schema change in a newer ScreenWise, or the file mid-migration.
    console.error('[desktime] read failed:', err)
    return { installed: true, ms: null }
  } finally {
    db?.close()
  }
}

export function registerDesktimeIpc() {
  ipcMain.handle('desktime:screen-time', () => readScreenTime())
  ipcMain.handle('desktime:download', () => shell.openExternal(DESKTIME_URL))
}
