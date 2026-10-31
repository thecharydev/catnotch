// @vitest-environment node
import fs from 'fs'
import http from 'http'
import net from 'net'
import os from 'os'
import path from 'path'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const ctx = vi.hoisted(() => ({
  userData: '',
  handlers: new Map<string, (...args: any[]) => any>(),
  windows: [{ webContents: { send: () => {} } }],
  inFront: (() => false) as any,
}))

vi.mock('electron', () => ({
  app: { getPath: () => ctx.userData },
  ipcMain: { handle: (channel: string, fn: (...args: any[]) => any) => ctx.handlers.set(channel, fn) },
  BrowserWindow: { getAllWindows: () => ctx.windows },
}))
vi.mock('../fullscreen', () => ({
  claudeIsInFront: (source: string) => ctx.inFront(source),
  setClaudeWaiting: () => {},
  checkAndApplyFullscreenState: () => {},
}))

const TOKEN = 'test-token'
const EVENTS = ['PermissionRequest', 'PreToolUse', 'SessionEnd', 'UserPromptSubmit', 'Stop']
const OURS = /^http:\/\/127\.0\.0\.1:\d+\/desknotch\//

let claudeDir = ''
let blockers: net.Server[] = []
let live = 0
let savedEnv: string | undefined
let inFront: ReturnType<typeof vi.fn>

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const ipc = (channel: string, ...args: unknown[]) => ctx.handlers.get(channel)!({}, ...args)
const settingsFile = () => path.join(claudeDir, 'settings.json')
const readSettings = () => JSON.parse(fs.readFileSync(settingsFile(), 'utf8'))
const writeSettings = (value: unknown) => fs.writeFileSync(settingsFile(), typeof value === 'string' ? value : JSON.stringify(value, null, 2))
const readStoreFile = () => JSON.parse(fs.readFileSync(path.join(ctx.userData, 'desknotch-store.json'), 'utf8'))

const freePort = () =>
  new Promise<number>((resolve) => {
    const s = net.createServer()
    s.listen(0, '127.0.0.1', () => {
      const { port } = s.address() as net.AddressInfo
      s.close(() => resolve(port))
    })
  })

const occupy = (port: number) =>
  new Promise<void>((resolve) => {
    const s = net.createServer()
    blockers.push(s)
    s.listen(port, '127.0.0.1', () => resolve())
  })

/** Our hook entries in a settings object, flattened per event. */
const ours = (root: any) =>
  Object.fromEntries(
    EVENTS.map((event) => [
      event,
      (root.hooks?.[event] ?? []).flatMap((g: any) => g.hooks.filter((h: any) => h.type === 'http' && OURS.test(h.url)).map((h: any) => ({ ...h, matcher: g.matcher }))),
    ]),
  ) as Record<string, any[]>

const seed = async (port: number, enabled = true) => {
  fs.writeFileSync(path.join(ctx.userData, 'desknotch-store.json'), JSON.stringify({ claudeHooks: { enabled, token: TOKEN, port } }))
}

/** Loads a fresh module and lets it start itself, the way the app does at launch. */
const start = async () => {
  vi.resetModules()
  const mod = await import('./claude')
  mod.registerClaudeIpc()
  for (let i = 0; i < 200; i++) {
    const status = await ipc('claude:status')
    if (status.running) {
      live = status.port
      return mod
    }
    await sleep(10)
  }
  throw new Error('server did not start')
}

type Options = { method?: string; token?: string | null; host?: string; body?: unknown }
const call = (route: string, { method = 'POST', token = TOKEN, host, body = {} }: Options = {}) =>
  new Promise<{ status: number; json: any }>((resolve, reject) => {
    const headers: Record<string, string> = { 'content-type': 'application/json' }
    if (token) headers.authorization = `Bearer ${token}`
    if (host) headers.host = host
    const req = http.request({ host: '127.0.0.1', port: live, path: route, method, headers, agent: false }, (res) => {
      let text = ''
      res.on('data', (c) => (text += c))
      res.on('end', () => {
        let json: any = null
        try {
          json = text ? JSON.parse(text) : null
        } catch {}
        resolve({ status: res.statusCode!, json })
      })
    })
    req.on('error', reject)
    req.end(JSON.stringify(body))
  })

const waitPending = async () => {
  for (let i = 0; i < 200; i++) {
    const queue = await ipc('claude:pending')
    if (queue.length) return queue[0]
    await sleep(10)
  }
  throw new Error('nothing queued')
}

const question = (extra: Record<string, unknown> = {}) => ({
  hook_event_name: 'PreToolUse',
  tool_name: 'AskUserQuestion',
  session_id: 's1',
  cwd: '/work/proj',
  tool_input: {
    questions: [
      { question: 'Which?', header: 'Pick', multiSelect: false, options: [{ label: 'A', description: 'a' }, { label: 'B', description: 'b' }] },
      { question: 'Many?', header: 'Pick', multiSelect: true, options: [{ label: 'X', description: 'x' }, { label: 'Y', description: 'y' }] },
    ],
  },
  ...extra,
})
const permission = (tool = 'Bash', input: unknown = { command: 'ls -la' }) => ({ hook_event_name: 'PermissionRequest', tool_name: tool, tool_input: input, session_id: 's1', cwd: '/work/proj' })

beforeEach(() => {
  ctx.userData = fs.mkdtempSync(path.join(os.tmpdir(), 'desknotch-ud-'))
  claudeDir = fs.mkdtempSync(path.join(os.tmpdir(), 'desknotch-claude-'))
  savedEnv = process.env.CLAUDE_CONFIG_DIR
  process.env.CLAUDE_CONFIG_DIR = claudeDir
  inFront = vi.fn(() => false)
  ctx.inFront = inFront
  ctx.handlers.clear()
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

afterEach(async () => {
  await ctx.handlers.get('claude:disable')?.({})
  await Promise.all(blockers.map((s) => new Promise((r) => s.close(r))))
  blockers = []
  fs.rmSync(ctx.userData, { recursive: true, force: true })
  fs.rmSync(claudeDir, { recursive: true, force: true })
  if (savedEnv === undefined) delete process.env.CLAUDE_CONFIG_DIR
  else process.env.CLAUDE_CONFIG_DIR = savedEnv
  vi.restoreAllMocks()
})

const foreign = {
  permissions: { allow: ['Bash(ls)'] },
  hooks: {
    PreToolUse: [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'echo hi' }] }],
    PermissionRequest: [{ hooks: [{ type: 'http', url: 'http://example.com/hook', timeout: 5 }] }],
    Notification: [{ hooks: [{ type: 'command', command: 'echo n' }] }],
  },
}

describe('hook sync (AC-2, AC-3)', () => {
  it('moves stale entries to the live port when the saved port is free (regression)', async () => {
    const P = await freePort()
    let Q = await freePort()
    while (Q === P) Q = await freePort()
    await seed(P)
    const stale = (route: string, timeout = 65) => ({ type: 'http', url: `http://127.0.0.1:${Q}/desknotch/${route}`, timeout, headers: { Authorization: 'Bearer old' } })
    const keep = { type: 'command', command: 'echo keep' }
    writeSettings({
      hooks: {
        PermissionRequest: [{ hooks: [stale('permission'), keep] }],
        PreToolUse: [{ matcher: 'AskUserQuestion', hooks: [stale('question')] }],
        SessionEnd: [{ hooks: [stale('event', 5)] }],
        UserPromptSubmit: [{ hooks: [stale('event', 5)] }],
        Stop: [{ hooks: [stale('event', 5)] }],
      },
    })
    await start()
    expect(live).toBe(P)
    const root = readSettings()
    const found = ours(root)
    for (const event of EVENTS) {
      expect(found[event]).toHaveLength(1)
      expect(found[event][0].url).toMatch(new RegExp(`^http://127\\.0\\.0\\.1:${P}/desknotch/`))
      expect(found[event][0].headers.Authorization).toBe(`Bearer ${TOKEN}`)
    }
    expect(JSON.stringify(root)).not.toContain(`:${Q}/`)
    expect(root.hooks.PermissionRequest.flatMap((g: any) => g.hooks)).toContainEqual(keep)
  })

  it('writes the right route, matcher and timeout, and never duplicates', async () => {
    await seed(await freePort())
    await start()
    await ipc('claude:enable')
    await ipc('claude:enable')
    const found = ours(readSettings())
    for (const event of EVENTS) expect(found[event]).toHaveLength(1)
    const route = (e: string) => found[e][0].url.split('/desknotch/')[1]
    expect(route('PermissionRequest')).toBe('permission')
    expect(route('PreToolUse')).toBe('question')
    for (const e of ['SessionEnd', 'UserPromptSubmit', 'Stop']) expect(route(e)).toBe('event')
    expect(found.PreToolUse[0].matcher).toBe('AskUserQuestion')
    expect(found.PermissionRequest[0].timeout).toBe(65)
    expect(found.PreToolUse[0].timeout).toBe(65)
    for (const e of ['SessionEnd', 'UserPromptSubmit', 'Stop']) expect(found[e][0].timeout).toBe(5)
  })
})

describe('port fallback (AC-1, AC-2)', () => {
  it('moves to the next free port, saves it, and the entries follow', async () => {
    const P = await freePort()
    await seed(P)
    await occupy(P)
    await start()
    expect(live).toBeGreaterThan(P)
    expect(live).toBeLessThan(P + 20)
    expect((await ipc('claude:status')).port).toBe(live)
    expect(readStoreFile().claudeHooks.port).toBe(live)
    const found = ours(readSettings())
    for (const event of EVENTS) {
      expect(found[event][0].url).toContain(`127.0.0.1:${live}/`)
      expect(found[event][0].headers.Authorization).toBe(`Bearer ${TOKEN}`)
    }
  })
})

describe('other tools and bad files (AC-4, AC-5)', () => {
  it('leaves foreign hooks and keys alone through enable, a second start and disable', async () => {
    await seed(await freePort())
    writeSettings(foreign)
    await start()
    const notOurs = (root: any) => ({
      ...root,
      hooks: Object.fromEntries(
        Object.entries<any[]>(root.hooks ?? {}).flatMap(([e, groups]) => {
          const rest = groups.map((g) => ({ ...g, hooks: g.hooks.filter((h: any) => !(h.type === 'http' && OURS.test(h.url))) })).filter((g) => g.hooks.length)
          return rest.length ? [[e, rest]] : []
        }),
      ),
    })
    expect(notOurs(readSettings())).toEqual(foreign)
    await ipc('claude:enable')
    expect(notOurs(readSettings())).toEqual(foreign)
    expect(await ipc('claude:disable')).toEqual({ ok: true })
    expect(readSettings()).toEqual(foreign)
  })

  it('never writes a file that is not JSON, and enable says invalid', async () => {
    await seed(await freePort())
    const bad = '{ not json'
    writeSettings(bad)
    await start()
    expect(await ipc('claude:enable')).toEqual({ ok: false, error: 'invalid' })
    expect(fs.readFileSync(settingsFile(), 'utf8')).toBe(bad)
    expect(fs.existsSync(`${settingsFile()}.deskNotch.bak`)).toBe(false)
  })

  it('writes the first backup once and never overwrites it', async () => {
    await seed(await freePort())
    const first = JSON.stringify({ model: 'one' })
    writeSettings(first)
    await start()
    const bak = `${settingsFile()}.deskNotch.bak`
    expect(fs.readFileSync(bak, 'utf8')).toBe(first)
    writeSettings({ model: 'two' })
    await ipc('claude:enable')
    expect(fs.readFileSync(bak, 'utf8')).toBe(first)
  })
})

describe('replies (AC-6, AC-7)', () => {
  it('answers a question with the PreToolUse allow shape', async () => {
    await seed(await freePort())
    await start()
    const sent = call('/desknotch/question', { body: question() })
    const view = await waitPending()
    expect(view.kind).toBe('question')
    expect(await ipc('claude:answer', view.id, { answers: { 'Which?': 'A', 'Many?': ['X', 'Y'] } })).toBe(true)
    const { status, json } = await sent
    expect(status).toBe(200)
    expect(json).toEqual({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'allow',
        updatedInput: { questions: question().tool_input.questions, answers: { 'Which?': 'A', 'Many?': 'X, Y' } },
      },
    })
    expect(await ipc('claude:pending')).toEqual([])
  })

  it('refuses several labels on a single choice question and keeps it queued', async () => {
    await seed(await freePort())
    await start()
    const sent = call('/desknotch/question', { body: question() })
    const view = await waitPending()
    expect(await ipc('claude:answer', view.id, { answers: { 'Which?': ['A', 'B'], 'Many?': 'X' } })).toBe(false)
    expect(await ipc('claude:answer', view.id, { answers: { 'Which?': 'A' } })).toBe(false)
    expect(await ipc('claude:pending')).toHaveLength(1)
    await ipc('claude:answer', view.id, 'pass')
    expect((await sent).json).toEqual({})
  })

  it('replies allow and deny to a permission request', async () => {
    await seed(await freePort())
    await start()
    for (const choice of ['allow', 'deny'] as const) {
      const sent = call('/desknotch/permission', { body: permission() })
      const view = await waitPending()
      expect(view).toMatchObject({ kind: 'permission', tool: 'Bash', text: 'ls -la', project: 'proj' })
      expect(await ipc('claude:answer', view.id, choice)).toBe(true)
      const decision = choice === 'allow' ? { behavior: 'allow' } : { behavior: 'deny', message: 'Denied from CatNotch', interrupt: false }
      expect((await sent).json).toEqual({ hookSpecificOutput: { hookEventName: 'PermissionRequest', decision } })
    }
  })

  it('replies {} for pass, and refuses a bad choice without dequeuing', async () => {
    await seed(await freePort())
    await start()
    const sent = call('/desknotch/permission', { body: permission() })
    const view = await waitPending()
    expect(await ipc('claude:answer', view.id, 'maybe')).toBe(false)
    expect(await ipc('claude:answer', 'no-such-id', 'allow')).toBe(false)
    expect(await ipc('claude:pending')).toHaveLength(1)
    expect(await ipc('claude:answer', view.id, 'pass')).toBe(true)
    expect((await sent).json).toEqual({})
  })

  it('answers {} at once to AskUserQuestion on the permission route and never queues it', async () => {
    await seed(await freePort())
    await start()
    const { json } = await call('/desknotch/permission', { body: permission('AskUserQuestion', question().tool_input) })
    expect(json).toEqual({})
    expect(await ipc('claude:pending')).toEqual([])
  })
})

describe('the gate (AC-8)', () => {
  it('refuses wrong or missing token, bad method, unknown path and wrong host', async () => {
    await seed(await freePort())
    await start()
    expect((await call('/desknotch/event', { token: 'wrong' })).status).toBe(401)
    expect((await call('/desknotch/event', { token: null })).status).toBe(401)
    expect((await call('/desknotch/event', { method: 'GET' })).status).toBe(405)
    expect((await call('/desknotch/nope')).status).toBe(404)
    expect((await call('/desknotch/event', { host: 'evil.example' })).status).toBe(403)
    expect((await call('/desknotch/event')).status).toBe(200)
  })

  it('replies {} at once to a reporting event and lists the session', async () => {
    await seed(await freePort())
    await start()
    const { status, json } = await call('/desknotch/event', { body: { hook_event_name: 'UserPromptSubmit', session_id: 'abc', cwd: '/work/proj' } })
    expect(status).toBe(200)
    expect(json).toEqual({})
    const { sessions } = await ipc('claude:sessions')
    expect(sessions).toEqual([expect.objectContaining({ id: 'abc', project: 'proj', state: 'working' })])
  })
})

describe('the terminal rule wiring (AC-9)', () => {
  it('answers {} at once and queues nothing when a terminal is in front', async () => {
    await seed(await freePort())
    await start()
    inFront.mockReturnValue(true)
    const { json } = await call('/desknotch/question', { body: question() })
    expect(json).toEqual({})
    expect(await ipc('claude:pending')).toEqual([])
  })

  it('queues the request when nothing is in front', async () => {
    await seed(await freePort())
    await start()
    const sent = call('/desknotch/question', { body: question() })
    const view = await waitPending()
    expect(inFront).toHaveBeenCalledWith('unknown')
    await ipc('claude:answer', view.id, 'pass')
    await sent
  })

  it.each([
    ['claude-vscode', 'vscode'],
    ['cli', 'cli'],
  ])('asks the rule with the source read from a %s transcript', async (entrypoint, source) => {
    await seed(await freePort())
    await start()
    const transcript = path.join(claudeDir, 'projects', 't.jsonl')
    fs.mkdirSync(path.dirname(transcript), { recursive: true })
    fs.writeFileSync(transcript, `{"entrypoint":"${entrypoint}","cwd":"/work/proj"}\n`)
    const sent = call('/desknotch/question', { body: question({ transcript_path: transcript }) })
    const view = await waitPending()
    expect(inFront).toHaveBeenLastCalledWith(source)
    await ipc('claude:answer', view.id, 'pass')
    await sent
  })
})
