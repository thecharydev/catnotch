/**
 * The Swift helper (native/mac): one child process that prints a JSON line per
 * change. A missing or crashing helper only turns its features off.
 */
import { app, BrowserWindow, ipcMain, screen } from 'electron'
import { spawn, type ChildProcess } from 'child_process'
import { existsSync } from 'fs'
import path from 'path'

type Notch = { w: number; h: number }
type HelperLine = { t: 'notch'; display: number } & Notch

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
  if (line.t !== 'notch') return
  notches.set(line.display, { w: line.w, h: line.h })
  for (const window of BrowserWindow.getAllWindows()) window.webContents.send('notch:hardware', notchFor(window))
}

const start = () => {
  const file = binary()
  if (stopped || !existsSync(file)) return
  const proc = spawn(file, [], { stdio: ['ignore', 'pipe', 'ignore'] })
  child = proc
  proc.on('error', () => {})
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

export function startHelper() {
  ipcMain.handle('notch:hardware', (event) => notchFor(BrowserWindow.fromWebContents(event.sender)))
  start()
}

export function stopHelper() {
  stopped = true
  child?.kill()
}
