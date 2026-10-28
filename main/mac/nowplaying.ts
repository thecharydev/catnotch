/**
 * Now playing on macOS, from the vendored mediaremote-adapter (native/mac/
 * mediaremote-adapter). It runs under Apple's own /usr/bin/perl, the only
 * thing still allowed to read MediaRemote. Emits the same shape as smtc.ts.
 */
import { app } from 'electron'
import { execFile, spawn, type ChildProcess } from 'child_process'
import { existsSync } from 'fs'
import path from 'path'
import { setNowPlaying, type NowPlaying } from '../smtc'

const COMMANDS = { play: 0, pause: 1, 'play-pause': 2, next: 4, previous: 5 } as const
export type TransportKey = keyof typeof COMMANDS

const dir = () => (app.isPackaged ? process.resourcesPath : path.join(process.cwd(), 'native', 'mac', 'build'))
const script = () => path.join(dir(), 'mediaremote', 'mediaremote-adapter.pl')
const framework = () => path.join(dir(), 'mediaremote', 'MediaRemoteAdapter.framework')
const adapterArgs = (...rest: string[]) => [script(), framework(), ...rest]

let child: ChildProcess | null = null
let stopped = false
let crashes = 0
let state: Record<string, any> = {}

const toNowPlaying = (s: Record<string, any>): NowPlaying | null => {
  if (!s.title || !s.bundleIdentifier) return null
  const playing = s.playing === true
  const seen = Number(s.elapsedTimeMicros ?? 0) / 1e6
  const at = Number(s.timestampEpochMicros ?? 0) / 1e3
  return {
    sourceAppId: s.bundleIdentifier,
    title: s.title,
    artist: s.artist ?? '',
    album: s.album ?? '',
    isPlaying: playing,
    // The adapter reports where the track was at `timestamp`; the renderer
    // wants where it is now.
    position: playing && at ? seen + (Date.now() - at) / 1000 : seen,
    duration: Number(s.durationMicros ?? 0) / 1e6,
    thumbnailUrl: s.artworkData ? `data:${s.artworkMimeType || 'image/jpeg'};base64,${s.artworkData}` : null,
  }
}

const handle = (line: string) => {
  const message = JSON.parse(line)
  if (message.type !== 'data') return
  const payload = message.payload ?? {}
  // A diff only carries what changed; a key set to null has gone away.
  state = message.diff ? { ...state, ...payload } : { ...payload }
  for (const key of Object.keys(state)) if (state[key] === null) delete state[key]
  setNowPlaying(toNowPlaying(state))
}

const start = () => {
  if (stopped || !existsSync(script())) return
  const proc = spawn('/usr/bin/perl', adapterArgs('stream', '--micros', '--debounce=100'), { stdio: ['ignore', 'pipe', 'ignore'] })
  child = proc
  proc.on('error', () => {})
  let buffer = ''
  proc.stdout?.on('data', (chunk: Buffer) => {
    buffer += chunk.toString()
    const lines = buffer.split('\n')
    buffer = lines.pop() ?? ''
    for (const line of lines) {
      try {
        handle(line)
      } catch {}
    }
  })
  proc.on('exit', () => {
    child = null
    state = {}
    setNowPlaying(null)
    if (!stopped && ++crashes <= 3) setTimeout(start, 1000)
  })
}

export const startMacNowPlaying = start

export function stopMacNowPlaying() {
  stopped = true
  child?.kill()
}

/** Play, pause, next or previous on whatever is playing. */
export const sendTransport = (key: TransportKey) =>
  execFile('/usr/bin/perl', adapterArgs('send', String(COMMANDS[key])), () => {})

/** Brings the player forward. The id is checked first: it is a bundle id from
 *  the adapter, but the page passes it back to us. */
export const focusPlayer = (bundleId: string) => {
  if (!/^[\w.-]+$/.test(bundleId)) return
  execFile('open', ['-b', bundleId], () => {})
}
