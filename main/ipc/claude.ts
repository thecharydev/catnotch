/**
 * Claude Code on the notch: when Claude wants to run a tool, or asks a
 * question, its hooks call this small server and the notch shows it. The
 * click comes back as the hook's reply. Anything that goes wrong (no answer
 * in 60 s, the app closed, a bad request) is an empty reply or no reply, and
 * Claude then shows its own prompt, so this can never leave a session stuck.
 *
 * Only 127.0.0.1, only POST, only with the secret token, so nothing else on
 * the machine (or a web page) can approve a command.
 */
import { BrowserWindow, ipcMain } from 'electron'
import { execFile } from 'child_process'
import crypto from 'crypto'
import fs from 'fs'
import http from 'http'
import os from 'os'
import path from 'path'
import { readStore, writeStore } from '../store'
import { setClaudeWaiting, claudeIsInFront, checkAndApplyFullscreenState } from '../fullscreen'

const BASE_PORT = 47821
const FALL_THROUGH_MS = 60_000
const MAX_BODY = 1_000_000
const MAX_PENDING = 20
const MAX_TEXT = 20_000
/** Longer than ours, so our own empty reply always arrives first. */
const HOOK_TIMEOUT_S = 65
const OURS = /^http:\/\/127\.0\.0\.1:\d+\/desknotch\//
const MAX_ANSWER = 2000
const SCAN_MS = 5_000
const WORKING_STALE_MS = 10 * 60_000
const MAX_SESSIONS = 20
/** Hook events that only report, so they get an empty reply at once. */
const EVENTS = ['SessionEnd', 'UserPromptSubmit', 'Stop']

export type ClaudeQuestion = {
  question: string
  header: string
  multiSelect: boolean
  options: { label: string; description: string }[]
}
/** What the notch is shown; never the open connection. */
export type ClaudeRequest =
  | { id: string; kind: 'permission'; sessionId: string; tool: string; project: string; text: string }
  | { id: string; kind: 'question'; sessionId: string; project: string; questions: ClaudeQuestion[] }

/** One Claude session, as the Claude tab lists it. */
export type ClaudeSession = { id: string; project: string; source: 'cli' | 'vscode' | 'unknown'; state: 'working' | 'idle' | 'waiting'; at: number }

type Session = { id: string; cwd: string; source: ClaudeSession['source']; state: 'working' | 'idle'; at: number; transcript: string; mtime: number; read: boolean }

type Pending = {
  view: ClaudeRequest
  res: http.ServerResponse
  timer: ReturnType<typeof setTimeout>
  at: number
  /** The renderer is typing an answer: no timer runs. */
  /** Why the 60 s timer is off: 'type' (an answer is being typed), 'hover' (the pointer is on it). */
  held: Set<'type' | 'hover'>
}

const pending = new Map<string, Pending>()
const sessions = new Map<string, Session>()
/** Sessions with a quiet run in flight (a message sent from the notch). */
const running = new Set<string>()
let scanTimer: ReturnType<typeof setInterval> | null = null
let lastSent = ''
let server: http.Server | null = null
let port = 0

const settings = () => readStore().claudeHooks
const save = (next: NonNullable<ReturnType<typeof settings>>) => writeStore({ ...readStore(), claudeHooks: next })
const broadcast = (channel: string, ...args: unknown[]) => {
  for (const window of BrowserWindow.getAllWindows()) window.webContents.send(channel, ...args)
}
const queue = () => [...pending.values()].sort((a, b) => a.at - b.at).map((p) => p.view)

// ── Requests ────────────────────────────────────────────────────────────────

const reply = (res: http.ServerResponse, body: unknown = {}) => {
  if (res.writableEnded) return
  res.writeHead(200, { 'content-type': 'application/json' })
  res.end(JSON.stringify(body))
}
const refuse = (res: http.ServerResponse, status: number) => {
  res.writeHead(status, { connection: 'close' })
  res.end()
  // Let the unread body go, so the sender sees the status, not a reset.
  res.req.resume()
}

/** Takes a request out of the queue, whatever the reason, and tells every notch. */
const leave = (id: string) => {
  const item = pending.get(id)
  if (!item) return null
  clearTimeout(item.timer)
  pending.delete(id)
  broadcast('claude:resolved', id)
  setClaudeWaiting(pending.size > 0)
  emit()
  return item
}

const str = (value: unknown, max = 500) => (typeof value === 'string' ? value.slice(0, max) : '')

/** The line a permission popup shows: the command, the file, or the input cut short. */
const describe = (tool: string, input: Record<string, unknown>) => {
  if (tool === 'Bash' && typeof input.command === 'string') return input.command.slice(0, MAX_TEXT)
  if (typeof input.file_path === 'string') return input.file_path
  if (typeof input.notebook_path === 'string') return input.notebook_path
  return JSON.stringify(input).slice(0, 300)
}

const questionsOf = (input: Record<string, unknown>): ClaudeQuestion[] =>
  (Array.isArray(input.questions) ? input.questions : []).slice(0, 8).map((q: any) => ({
    question: str(q?.question, 500),
    header: str(q?.header, 60),
    multiSelect: q?.multiSelect === true,
    options: (Array.isArray(q?.options) ? q.options : []).slice(0, 12).map((o: any) => ({ label: str(o?.label, 200), description: str(o?.description, 400) })),
  }))

const fallThrough = (id: string, res: http.ServerResponse) =>
  setTimeout(() => {
    leave(id)
    reply(res)
  }, FALL_THROUGH_MS)

function add(route: 'permission' | 'question', body: any, res: http.ServerResponse) {
  const input = body && typeof body.tool_input === 'object' && body.tool_input ? (body.tool_input as Record<string, unknown>) : {}
  const tool = str(body?.tool_name, 80)
  // A question reaches us on its own route; the permission route must not show it twice.
  if (route === 'permission' && tool === 'AskUserQuestion') return reply(res)
  if (pending.size >= MAX_PENDING) return reply(res)

  const id = crypto.randomUUID()
  const project = path.basename(str(body?.cwd, 1000)) || 'Claude'
  const sessionId = str(body?.session_id, 100)
  let view: ClaudeRequest
  if (route === 'permission') {
    view = { id, kind: 'permission', sessionId, tool: tool || 'Tool', project, text: describe(tool, input) }
  } else {
    const questions = questionsOf(input)
    if (!questions.length || questions.some((q) => !q.options.length)) return reply(res)
    view = { id, kind: 'question', sessionId, project, questions }
  }
  seen(body)
  // You are already in the window where Claude is asking: its own prompt is in front of you.
  if (claudeIsInFront(sessions.get(sessionId)?.source ?? 'unknown')) return reply(res)

  pending.set(id, { view, res, timer: fallThrough(id, res), at: Date.now(), held: new Set() })
  // Claude gave up on this request (moved on, session ended): drop the popup.
  res.on('close', () => !res.writableFinished && leave(id))
  setClaudeWaiting(true)
  broadcast('claude:request', view)
  emit()
}

// ── Sessions ────────────────────────────────────────────────────────────────

const configDir = () => process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude')

/** The source and folder, from the first lines of the transcript. Read once per session. */
function readMeta(session: Session) {
  if (session.read || !session.transcript) return
  try {
    const fd = fs.openSync(session.transcript, 'r')
    const buffer = Buffer.alloc(65_536)
    const n = fs.readSync(fd, buffer, 0, buffer.length, 0)
    fs.closeSync(fd)
    const head = buffer.toString('utf8', 0, n)
    const entry = /"entrypoint":"([^"]*)"/.exec(head)?.[1]
    const cwd = /"cwd":"((?:[^"\\]|\\.)*)"/.exec(head)?.[1]
    if (entry) {
      session.source = entry === 'cli' ? 'cli' : entry === 'claude-vscode' ? 'vscode' : 'unknown'
      session.read = true
    }
    if (cwd && !session.cwd) session.cwd = cwd.replace(/\\\\/g, '\\')
  } catch {
    // No file yet: try again on the next scan.
  }
}

const list = (): ClaudeSession[] => {
  const waiting = new Set([...pending.values()].map((p) => p.view.sessionId))
  return [...sessions.values()]
    .map((s) => ({
      id: s.id,
      project: path.basename(s.cwd) || 'Claude',
      source: s.source,
      state: waiting.has(s.id) ? ('waiting' as const) : s.state,
      at: Math.max(s.at, s.mtime),
    }))
    .sort((a, b) => b.at - a.at)
    .slice(0, MAX_SESSIONS)
}

const payload = () => ({ enabled: settings()?.enabled === true, sessions: settings()?.enabled === true ? list() : [] })

/** Tells every notch the list changed, but only when it really did. */
function emit() {
  const next = payload()
  const text = JSON.stringify(next)
  if (text === lastSent) return
  lastSent = text
  broadcast('claude:sessions-changed', next)
}

/** A hook event for a session: note it, and what it says about the state. */
function seen(body: any) {
  const id = str(body?.session_id, 100)
  if (!id) return
  const event = str(body?.hook_event_name, 40)
  if (event === 'SessionEnd') {
    // Our own quiet run ending is not the session ending.
    if (running.has(id)) return
    sessions.delete(id)
    return emit()
  }
  const now = Date.now()
  const session = sessions.get(id) ?? { id, cwd: '', source: 'unknown' as const, state: 'idle' as const, at: now, transcript: '', mtime: 0, read: false }
  const cwd = str(body?.cwd, 1000)
  if (cwd) session.cwd = cwd
  const transcript = str(body?.transcript_path, 1000)
  if (transcript) session.transcript = transcript
  // Any activity means Claude is mid turn, until it says Stop.
  session.state = event === 'Stop' ? 'idle' : 'working'
  session.at = now
  sessions.set(id, session)
  readMeta(session)
  emit()
}

const alive = (pid: unknown) => {
  if (typeof pid !== 'number') return false
  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    // EPERM: the process exists but is not ours to signal.
    return (error as NodeJS.ErrnoException).code === 'EPERM'
  }
}

/** Claude keeps one file per running session in `<config dir>/sessions` (its pid, id and folder).
 *  That is the list of live sessions: a file whose process is gone is not one. */
function scan() {
  const now = Date.now()
  const live = new Set<string>()
  const dir = path.join(configDir(), 'sessions')
  let files: string[] = []
  try {
    files = fs.readdirSync(dir).filter((f) => f.endsWith('.json'))
  } catch {
    // No sessions folder yet.
  }
  for (const file of files) {
    let info: any
    try {
      info = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'))
    } catch {
      continue
    }
    const id = str(info?.sessionId, 100)
    if (!id || !alive(info?.pid)) continue
    live.add(id)
    const cwd = str(info?.cwd, 1000)
    const known = sessions.get(id)
    const session = known ?? { id, cwd, source: 'unknown' as const, state: 'idle' as const, at: 0, transcript: '', mtime: 0, read: false }
    if (cwd) session.cwd = cwd
    // The transcript lives in a folder named after the cwd (letters and digits kept, the rest a dash).
    if (!session.transcript) session.transcript = path.join(configDir(), 'projects', session.cwd.replace(/[^a-zA-Z0-9]/g, '-'), `${id}.jsonl`)
    try {
      session.mtime = fs.statSync(session.transcript).mtimeMs
    } catch {
      // Not written yet.
    }
    sessions.set(id, session)
  }
  for (const [id, session] of sessions) {
    if (!live.has(id)) sessions.delete(id)
    else if (session.state === 'working' && now - Math.max(session.at, session.mtime) > WORKING_STALE_MS) session.state = 'idle'
    else readMeta(session)
  }
  emit()
}

const startScan = () => {
  if (scanTimer) return
  scan()
  scanTimer = setInterval(scan, SCAN_MS)
}

const tokenOk = (header: string | undefined) => {
  const token = settings()?.token
  if (!token || !header) return false
  const want = Buffer.from(`Bearer ${token}`)
  const got = Buffer.from(header)
  return want.length === got.length && crypto.timingSafeEqual(want, got)
}

function handle(req: http.IncomingMessage, res: http.ServerResponse) {
  if (req.headers.host !== `127.0.0.1:${port}`) return refuse(res, 403)
  if (req.method !== 'POST') return refuse(res, 405)
  if (!tokenOk(req.headers.authorization)) return refuse(res, 401)
  const route =
    req.url === '/desknotch/permission' ? 'permission' : req.url === '/desknotch/question' ? 'question' : req.url === '/desknotch/event' ? 'event' : null
  if (!route) return refuse(res, 404)

  let size = 0
  const chunks: Buffer[] = []
  req.on('data', (chunk: Buffer) => {
    size += chunk.length
    if (size > MAX_BODY) {
      refuse(res, 413)
      req.destroy()
    } else chunks.push(chunk)
  })
  req.on('end', () => {
    if (res.writableEnded) return
    let body: unknown
    try {
      body = JSON.parse(Buffer.concat(chunks).toString('utf8'))
    } catch {
      return reply(res)
    }
    // Reports never wait: Claude gets its empty reply before we look at the body.
    if (route === 'event') {
      reply(res)
      const event = (body as { hook_event_name?: unknown } | null)?.hook_event_name
      if (typeof event === 'string' && EVENTS.includes(event)) seen(body)
      return
    }
    add(route, body, res)
  })
}

/** The click. Only the shapes a hook may be answered with get through. */
const answer = (id: unknown, choice: unknown) => {
  if (typeof id !== 'string') return false
  const item = pending.get(id)
  if (!item) return false
  const view = item.view

  if (choice === 'pass') {
    leave(id)
    reply(item.res)
    return true
  }
  if (view.kind === 'permission') {
    if (choice !== 'allow' && choice !== 'deny') return false
    const decision = choice === 'allow' ? { behavior: 'allow' } : { behavior: 'deny', message: 'Denied from DeskNotch', interrupt: false }
    leave(id)
    reply(item.res, { hookSpecificOutput: { hookEventName: 'PermissionRequest', decision } })
    return true
  }

  // Question: one chosen label (or several, joined by a comma) per question text.
  const answers = (choice as { answers?: Record<string, unknown> } | null)?.answers
  if (!answers || typeof answers !== 'object') return false
  const out: Record<string, string> = {}
  for (const q of view.questions) {
    const given = answers[q.question]
    const picked = (Array.isArray(given) ? given : [given]).map((l) => (typeof l === 'string' ? l.trim().slice(0, MAX_ANSWER) : ''))
    // A label or typed text, either way a non empty string; several only on a multi select.
    if (!picked.length || picked.some((l) => !l) || (!q.multiSelect && picked.length > 1)) return false
    out[q.question] = picked.join(', ')
  }
  const questions = view.questions.map(({ question, header, multiSelect, options }) => ({ question, header, multiSelect, options }))
  // Claude needs its own question list back with the answers added.
  leave(id)
  reply(item.res, {
    hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'allow', updatedInput: { questions, answers: out } },
  })
  return true
}

// ── The server ──────────────────────────────────────────────────────────────

/** Listens on the fixed port, or the next free one. Resolves the port, or 0. */
const listen = async (first: number) => {
  for (let candidate = first; candidate < first + 20; candidate++) {
    const found = await new Promise<http.Server | null>((resolve) => {
      const next = http.createServer(handle)
      next.once('error', () => resolve(null))
      next.listen(candidate, '127.0.0.1', () => resolve(next))
    })
    if (found) {
      server = found
      port = candidate
      startScan()
      return candidate
    }
  }
  return 0
}

const stop = () => {
  for (const id of [...pending.keys()]) {
    const item = leave(id)
    if (item) reply(item.res)
  }
  server?.close()
  server = null
  port = 0
  if (scanTimer) clearInterval(scanTimer)
  scanTimer = null
  sessions.clear()
  emit()
}

// ── Claude's settings.json ──────────────────────────────────────────────────

const configPath = () => path.join(configDir(), 'settings.json')

const hook = (route: string, token: string, timeout = HOOK_TIMEOUT_S) => ({
  type: 'http',
  url: `http://127.0.0.1:${port || settings()?.port || BASE_PORT}/desknotch/${route}`,
  timeout,
  headers: { Authorization: `Bearer ${token}` },
})
const entries = (token: string): Record<string, { matcher?: string; hooks: unknown[] }> => ({
  PermissionRequest: { hooks: [hook('permission', token)] },
  PreToolUse: { matcher: 'AskUserQuestion', hooks: [hook('question', token)] },
  // Reports for the Claude tab. Replied to at once, so a short timeout.
  ...Object.fromEntries(EVENTS.map((event) => [event, { hooks: [hook('event', token, 5)] }])),
})

/** Adds or removes only our hook entries; every other key stays as it was.
 *  Throws 'invalid' for a file that is not JSON (nothing is written then). */
function edit(add: boolean) {
  const file = configPath()
  let text = ''
  try {
    text = fs.readFileSync(file, 'utf8')
  } catch {
    // No file yet: turning off has nothing to do, turning on starts one.
    if (!add) return
  }
  let root: any = {}
  if (text.trim()) {
    try {
      root = JSON.parse(text)
    } catch {
      throw new Error('invalid')
    }
  }
  if (!root || typeof root !== 'object' || Array.isArray(root)) throw new Error('invalid')

  const hooks = root.hooks && typeof root.hooks === 'object' ? root.hooks : {}
  const wanted = add ? entries(settings()?.token ?? '') : {}
  for (const event of Object.keys(entries(''))) {
    const groups: any[] = Array.isArray(hooks[event]) ? hooks[event] : []
    const isOurs = (h: any) => h?.type === 'http' && OURS.test(h.url ?? '')
    // Take our hooks out of every group; a group left empty by that goes too.
    const kept = groups.flatMap((group) => {
      if (!Array.isArray(group?.hooks) || !group.hooks.some(isOurs)) return [group]
      const rest = group.hooks.filter((h: any) => !isOurs(h))
      return rest.length ? [{ ...group, hooks: rest }] : []
    })
    if (wanted[event]) kept.push(wanted[event])
    if (kept.length) hooks[event] = kept
    else delete hooks[event]
  }
  if (Object.keys(hooks).length) root.hooks = hooks
  else delete root.hooks

  fs.mkdirSync(path.dirname(file), { recursive: true })
  // One backup, the first time: never overwritten after that.
  const backup = `${file}.deskNotch.bak`
  if (text && !fs.existsSync(backup)) fs.writeFileSync(backup, text, 'utf8')
  const temp = `${file}.deskNotch.tmp`
  fs.writeFileSync(temp, JSON.stringify(root, null, 2) + '\n', 'utf8')
  fs.renameSync(temp, file)
}

/** The hook JSON by hand, for a settings file we would not edit. */
const snippet = (masked: boolean) => JSON.stringify({ hooks: entries(masked ? '••••' : (settings()?.token ?? '')) }, null, 2)

const state = () => {
  const stored = settings()
  let valid = true
  let current = false
  try {
    const text = fs.readFileSync(configPath(), 'utf8')
    if (text.trim()) {
      const hooks = JSON.parse(text)?.hooks ?? {}
      // Every event we use has one of our entries: otherwise "Update hooks" is offered.
      current = Object.keys(entries('')).every((event) =>
        (Array.isArray(hooks[event]) ? hooks[event] : []).some((g: any) => Array.isArray(g?.hooks) && g.hooks.some((h: any) => h?.type === 'http' && OURS.test(h.url ?? ''))),
      )
    }
  } catch (error) {
    valid = (error as NodeJS.ErrnoException).code === 'ENOENT'
  }
  return { enabled: stored?.enabled === true, running: server !== null, port, configPath: configPath(), valid, current }
}

/** Starts the server for a saved "on", and moves the hook entries if the port had to change. */
export async function startClaudeServer() {
  const stored = settings()
  if (!stored?.enabled || server) return
  const got = await listen(stored.port || BASE_PORT)
  if (!got) return console.error('[claude] no free port')
  if (got !== stored.port) {
    save({ ...stored, port: got })
    try {
      edit(true)
    } catch (error) {
      console.error('[claude] could not move the hooks to the new port:', error)
    }
  }
}


// ── Chat ────────────────────────────────────────────────────────────────────

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const TAIL_BYTES = 256 * 1024
const MAX_TURNS = 30
const MAX_TURN_TEXT = 4000
const MAX_MESSAGE = 4000
const RUN_TIMEOUT_MS = 10 * 60_000

export type ClaudeTurn = { role: 'user' | 'assistant' | 'tool'; text: string }

const cut = (text: string) => (text.length > MAX_TURN_TEXT ? `${text.slice(0, MAX_TURN_TEXT)}…` : text)

/** The last turns of a transcript: what was said, and one line per tool call. Nothing else. */
function turnsOf(file: string): ClaudeTurn[] {
  const size = fs.statSync(file).size
  const start = Math.max(0, size - TAIL_BYTES)
  const buffer = Buffer.alloc(size - start)
  const fd = fs.openSync(file, 'r')
  try {
    fs.readSync(fd, buffer, 0, buffer.length, start)
  } finally {
    fs.closeSync(fd)
  }
  const lines = buffer.toString('utf8').split('\n')
  if (start > 0) lines.shift() // the first line is probably cut in half
  const turns: ClaudeTurn[] = []
  for (const line of lines) {
    let entry: any
    try {
      entry = JSON.parse(line)
    } catch {
      continue
    }
    if ((entry?.type !== 'user' && entry?.type !== 'assistant') || entry.isSidechain || entry.isMeta) continue
    const role = entry.type as 'user' | 'assistant'
    const content = entry.message?.content
    const blocks: any[] = typeof content === 'string' ? [{ type: 'text', text: content }] : Array.isArray(content) ? content : []
    for (const block of blocks) {
      if (block?.type === 'text' && typeof block.text === 'string' && block.text.trim()) {
        // Slash command echoes and caveats are Claude Code's own bookkeeping, not conversation.
        if (role === 'user' && /^<(command-|local-command)|^Caveat:/.test(block.text.trim())) continue
        turns.push({ role, text: cut(block.text.trim()) })
      } else if (block?.type === 'tool_use' && role === 'assistant') {
        turns.push({ role: 'tool', text: str(block.name, 80) || 'a tool' })
      }
    }
  }
  return turns.slice(-MAX_TURNS)
}

/** The session's transcript file, only if it really lives under `<config dir>/projects`. */
function transcriptOf(id: unknown) {
  if (typeof id !== 'string' || !UUID.test(id) || settings()?.enabled !== true) return null
  const session = sessions.get(id)
  if (!session?.transcript) return null
  try {
    const real = fs.realpathSync(session.transcript)
    const root = fs.realpathSync(path.join(configDir(), 'projects')) + path.sep
    return real.startsWith(root) ? { session, file: real } : null
  } catch {
    return null
  }
}

const busy = (id: string) => running.has(id) || list().find((s) => s.id === id)?.state !== 'idle'

function chat(id: unknown) {
  if (settings()?.enabled !== true) return { error: 'off' as const }
  const found = transcriptOf(id)
  if (!found) return { error: 'unknown' as const }
  try {
    return { turns: turnsOf(found.file), mtime: fs.statSync(found.file).mtimeMs, busy: busy(found.session.id) }
  } catch {
    return { error: 'unknown' as const }
  }
}

let claudeBin: string | null = null

/** Where the claude program is. An app opened from Finder has a short PATH, so look in the usual places, then ask the login shell. */
async function findClaude(): Promise<string | null> {
  if (claudeBin && fs.existsSync(claudeBin)) return claudeBin
  const exe = process.platform === 'win32' ? 'claude.exe' : 'claude'
  const home = os.homedir()
  const places = [
    path.join(home, '.local', 'bin', exe),
    path.join(home, '.claude', 'local', exe),
    ...(process.platform === 'darwin' ? ['/opt/homebrew/bin/claude', '/usr/local/bin/claude'] : []),
    ...(process.env.PATH ?? '').split(path.delimiter).filter(Boolean).map((dir) => path.join(dir, exe)),
  ]
  claudeBin = places.find((p) => fs.existsSync(p)) ?? null
  if (!claudeBin && process.platform !== 'win32') {
    claudeBin = await new Promise<string | null>((resolve) =>
      execFile(process.env.SHELL || '/bin/zsh', ['-lc', 'command -v claude'], { timeout: 5000 }, (error, out) => {
        const found = error ? '' : out.trim().split('\n').pop() ?? ''
        resolve(found && fs.existsSync(found) ? found : null)
      }),
    )
  }
  return claudeBin
}

/** Sends a message into a session with a quiet run of Claude. The reply lands in the transcript; the chat reads it from there. */
async function send(id: unknown, text: unknown) {
  if (settings()?.enabled !== true) return { error: 'off' as const }
  const found = transcriptOf(id)
  if (!found || typeof text !== 'string') return { error: 'unknown' as const }
  const message = text.trim().slice(0, MAX_MESSAGE)
  if (!message) return { error: 'unknown' as const }
  const { session } = found
  if (busy(session.id)) return { error: 'busy' as const }
  let isDir = false
  try {
    isDir = !!session.cwd && fs.statSync(session.cwd).isDirectory()
  } catch {
    // Folder is gone.
  }
  if (!isDir) return { error: 'folder' as const }
  // Claim the session before the (async) lookup, so a second click cannot start a second run.
  running.add(session.id)
  const bin = await findClaude()
  if (!bin) {
    running.delete(session.id)
    return { error: 'notfound' as const }
  }
  broadcast('claude:chat-changed', session.id)
  // An array, no shell: nothing in the message is ever read as a command.
  execFile(bin, ['-p', '--resume', session.id, '--permission-mode', 'default', '--', message], { cwd: session.cwd, timeout: RUN_TIMEOUT_MS, maxBuffer: 10_000_000 }, (error, out, err) => {
    running.delete(session.id)
    const why = error ? (error as NodeJS.ErrnoException & { killed?: boolean }).killed ? 'Timed out' : (err || out || error.message).toString().trim().slice(0, 200) : ''
    broadcast('claude:chat-changed', session.id, why || undefined)
  })
  return { ok: true as const }
}

export function registerClaudeIpc() {
  ipcMain.handle('claude:chat', (_event, id: unknown) => chat(id))
  ipcMain.handle('claude:send', (_event, id: unknown, text: unknown) => send(id, text))
  ipcMain.handle('claude:pending', () => queue())
  ipcMain.handle('claude:answer', (_event, id: unknown, choice: unknown) => answer(id, choice))
  // Typing an answer, or hovering the request, pauses the 60 s timer; letting go
  // of both restarts it.
  ipcMain.handle('claude:hold', (_event, id: unknown, on: unknown, why: unknown) => {
    const item = typeof id === 'string' ? pending.get(id) : undefined
    const reason = why === 'hover' ? 'hover' : 'type'
    if (!item || typeof on !== 'boolean' || item.held.has(reason) === on) return
    on ? item.held.add(reason) : item.held.delete(reason)
    clearTimeout(item.timer)
    if (!item.held.size) item.timer = fallThrough(id as string, item.res)
  })
  ipcMain.handle('claude:status', () => state())
  ipcMain.handle('claude:sessions', () => payload())
  ipcMain.handle('claude:preview', () => snippet(true))
  ipcMain.handle('claude:snippet', () => snippet(false))

  ipcMain.handle('claude:enable', async () => {
    const stored = settings()
    save({ enabled: true, token: stored?.token || crypto.randomBytes(32).toString('hex'), port: stored?.port || BASE_PORT })
    if (!server && !(await listen(settings()!.port))) {
      save({ ...settings()!, enabled: false })
      return { ok: false, error: 'port' }
    }
    if (port !== settings()!.port) save({ ...settings()!, port })
    try {
      edit(true)
    } catch (error) {
      // Not JSON: the file stays untouched and the server keeps running, so
      // the snippet pasted in by hand works.
      if ((error as Error).message === 'invalid') return { ok: false, error: 'invalid' }
      stop()
      save({ ...settings()!, enabled: false })
      return { ok: false, error: 'write' }
    }
    emit()
    checkAndApplyFullscreenState()
    return { ok: true }
  })

  ipcMain.handle('claude:disable', () => {
    const stored = settings()
    try {
      edit(false)
    } catch (error) {
      // A file that is not JSON holds none of our entries to remove.
      if ((error as Error).message !== 'invalid') return { ok: false, error: 'write' }
    }
    stop()
    if (stored) save({ ...stored, enabled: false })
    checkAndApplyFullscreenState()
    return { ok: true }
  })

  void startClaudeServer()
}
