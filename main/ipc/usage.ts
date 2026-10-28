/**
 * The machine's load, for the Right now card's Usage page: CPU, GPU and
 * memory. Nothing here runs unless that page is showing.
 *
 * - CPU and memory: Node's own `os`, read on request. CPU is the share of
 *   busy time since the previous request, so the first reading is a guess.
 * - GPU: Windows' performance counter, read by one PowerShell kept alive while
 *   the page keeps asking, and killed a few seconds after it stops. It is what
 *   Task Manager shows: the busiest engine type (3D, video decode…), since one
 *   adapter has several and they add past 100.
 *
 * ponytail: the counter path is the English name, which is what Windows
 * exposes; on a Windows in another language it does not resolve, and GPU reads
 * as unavailable while CPU and memory still work.
 */
import { ipcMain } from 'electron'
import { type ChildProcess, spawn } from 'child_process'
import os from 'os'
import { askHelper } from '../mac/helper'

export interface Usage {
  /** Shares, 0–1. */
  cpu: number
  memory: number
  /** Percent, or null until the counter has answered. */
  gpu: number | null
}

/** Each Get-Counter takes about a second; the pause keeps it to a reading every ~2 s. */
const SCRIPT = (parent: number) => `
while ($true) {
  if (-not (Get-Process -Id ${parent} -ErrorAction SilentlyContinue)) { exit }
  $s = Get-Counter '\\GPU Engine(*)\\Utilization Percentage' -ErrorAction SilentlyContinue
  $byType = @{}
  foreach ($c in $s.CounterSamples) { if ($c.Path -match 'engtype_(\\w+)') { $byType[$Matches[1]] += $c.CookedValue } }
  $gpu = ($byType.Values | Measure-Object -Maximum).Maximum
  [Console]::Out.WriteLine([math]::Round([double]$gpu, 1)); [Console]::Out.Flush()
  Start-Sleep -Milliseconds 500
}`

/** How long after the last ask the sampler is kept: the page polls every 2 s. */
const IDLE = 6000

let sampler: ChildProcess | null = null
let gpu: number | null = null
let wantedUntil = 0
let reaper: ReturnType<typeof setInterval> | undefined

const stop = () => {
  sampler?.kill()
  sampler = null
  clearInterval(reaper)
  reaper = undefined
}

const start = () => {
  if (sampler) return
  sampler = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', SCRIPT(process.pid)], {
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'ignore'],
  })
  // No PowerShell (macOS): GPU just stays at 0 instead of crashing main.
  sampler.on('error', () => {})
  let buffer = ''
  sampler.stdout?.on('data', (chunk: Buffer) => {
    buffer += chunk.toString()
    const lines = buffer.split(/\r?\n/)
    buffer = lines.pop() ?? ''
    for (const line of lines) {
      const value = Number(line)
      if (Number.isFinite(value)) gpu = Math.min(100, value)
    }
  })
  sampler.on('exit', () => {
    sampler = null
  })
  // Without this the sampler (~90 MB, a Get-Counter over every GPU engine each
  // second) ran for the app's whole life.
  reaper = setInterval(() => {
    if (Date.now() > wantedUntil) stop()
  }, 2000)
}

/** Busy share of every core since the last call. */
let lastTimes = os.cpus().map((core) => core.times)
const cpu = () => {
  const now = os.cpus().map((core) => core.times)
  let busy = 0
  let total = 0
  now.forEach((times, i) => {
    const before = lastTimes[i]
    if (!before) return
    for (const key of Object.keys(times) as (keyof typeof times)[]) total += times[key] - before[key]
    busy += times.idle - before.idle
  })
  lastTimes = now
  return total > 0 ? 1 - busy / total : 0
}

export function registerUsageIpc() {
  // Asking is what keeps the sampler alive; the reaper stops it once nobody
  // has asked for a while. The last GPU reading is kept, so the page shows it
  // at once when it comes back while a fresh one arrives.
  ipcMain.handle('usage:get', async (): Promise<Usage> => {
    if (process.platform === 'darwin') {
      // The helper answers GPU and memory; no sampler to keep alive.
      const reply = await askHelper<{ gpu: number | null; memory: number }>('usage')
      return { cpu: cpu(), memory: reply?.memory ?? 1 - os.freemem() / os.totalmem(), gpu: reply?.gpu ?? null }
    }
    wantedUntil = Date.now() + IDLE
    start()
    return { cpu: cpu(), memory: 1 - os.freemem() / os.totalmem(), gpu }
  })
}


export function stopUsageIpc() {
  stop()
}
