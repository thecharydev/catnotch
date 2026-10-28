/**
 * The Swift helper (native/mac): one child process that prints a JSON line per
 * change. A missing or crashing helper only turns its features off.
 */
import { app, BrowserWindow, ipcMain, screen } from 'electron'
import { spawn, type ChildProcess } from 'child_process'
import { existsSync } from 'fs'
import path from 'path'

type Notch = { w: number; h: number }
type HelperLine =
  | ({ t: 'notch'; display: number } & Notch)
  | { t: 'foreground'; self: true }
  | { t: 'foreground'; fullscreen: boolean; display: number; bundle: string }
  | { t: 'mic'; on: boolean }
  | { t: 'camera'; on: boolean }
  | { t: 'wifi'; connected: boolean; ssid: string | null; signal: number; location: 'granted' | 'denied' | 'unknown' }
  | { t: 'bluetooth'; devices: { name: string; connected: boolean; battery: number | null }[] }

export type HelperEvent<T extends HelperLine['t']> = Extract<HelperLine, { t: T }>

/** One listener per event type, set by the feature that wants it. */
const listeners = new Map<string, (line: any) => void>()
/** Watches asked for, replayed to a restarted helper. */
const watches = new Map<string, boolean>()

const notches = new Map<number, Notch>()
let child: ChildProcess | null = null
let stopped = false
let crashes = 0

const binary = () => {
  const root = app.isPackaged ? process.resourcesPath : path.join(process.cwd(), 'native', 'mac', 'build')
  return path.join(root, 'DeskNotchHelper.app', 'Contents', 'MacOS', 'DeskNotchHelper')
}

/** The hardware notch on the display a window is on, or null for the pill. */
const notchFor = (window: BrowserWindow | null): Notch | null => {
  if (!window) return null
  const n = notches.get(screen.getDisplayMatching(window.getBounds()).id)
  return n && n.w > 0 && n.h > 0 ? n : null
}

const handle = (line: HelperLine) => {
  const id = (line as { id?: number }).id
  if (id !== undefined) return waiting.get(id)?.(line), void waiting.delete(id)
  if (line.t !== 'notch') return listeners.get(line.t)?.(line)
  notches.set(line.display, { w: line.w, h: line.h })
  for (const window of BrowserWindow.getAllWindows()) window.webContents.send('notch:hardware', notchFor(window))
}

const start = () => {
  const file = binary()
  if (stopped || !existsSync(file)) return
  const proc = spawn(file, [], { stdio: ['pipe', 'pipe', 'ignore'] })
  child = proc
  proc.on('error', () => {})
  proc.stdin?.on('error', () => {})
  for (const [cmd, on] of watches) send({ cmd, on })
  let buffer = ''
  proc.stdout?.on('data', (chunk: Buffer) => {
    buffer += chunk.toString()
    const lines = buffer.split('\n')
    buffer = lines.pop() ?? ''
    for (const line of lines) {
      try {
        handle(JSON.parse(line))
      } catch {}
    }
  })
  proc.on('exit', () => {
    child = null
    // Restart a crash a few times, then leave the feature off.
    if (!stopped && ++crashes <= 3) setTimeout(start, 1000)
  })
}

const send = (request: object) => child?.stdin?.write(`${JSON.stringify(request)}\n`)

/** Listens for an event type, and turns its watch (`watchForeground`,
 *  `watchStatus`) on or off. The helper only polls while a watch is on. */
export function watchHelper<T extends HelperLine['t']>(cmd: string, types: T[], on: boolean, listener?: (line: HelperEvent<T>) => void) {
  if (listener) for (const type of types) listeners.set(type, listener as (line: any) => void)
  watches.set(cmd, on)
  send({ cmd, on })
}

const waiting = new Map<number, (reply: any) => void>()
let nextId = 1

/** Asks the helper something and waits for the answer (null if it is gone or silent for 3 s). */
export const askHelper = <T>(cmd: string): Promise<T | null> =>
  new Promise((resolve) => {
    if (!child) return resolve(null)
    const id = nextId++
    const timer = setTimeout(() => (waiting.delete(id), resolve(null)), 3000)
    waiting.set(id, (reply) => (clearTimeout(timer), resolve(reply)))
    send({ id, cmd })
  })

export const requestLocation = () => send({ cmd: 'requestLocation' })

export function startHelper() {
  ipcMain.handle('notch:hardware', (event) => notchFor(BrowserWindow.fromWebContents(event.sender)))
  start()
}

export function stopHelper() {
  stopped = true
  child?.kill()
}
