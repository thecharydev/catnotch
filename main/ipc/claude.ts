/**
 * Claude Code on the notch: when Claude wants to run a tool, or asks a
 * question, its hooks call this small server and the notch shows it. The
 * click comes back as the hook's reply. Anything that goes wrong (no answer
 * in 30 s, the app closed, a bad request) is an empty reply or no reply, and
 * Claude then shows its own prompt, so this can never leave a session stuck.
 *
 * Only 127.0.0.1, only POST, only with the secret token, so nothing else on
 * the machine (or a web page) can approve a command.
 */
import { BrowserWindow, ipcMain } from 'electron'
import crypto from 'crypto'
import fs from 'fs'
import http from 'http'
import os from 'os'
import path from 'path'
import { readStore, writeStore } from '../store'
import { setClaudeWaiting } from '../fullscreen'

const BASE_PORT = 47821
const FALL_THROUGH_MS = 30_000
const MAX_BODY = 1_000_000
const MAX_PENDING = 20
const MAX_TEXT = 20_000
/** Longer than ours, so our own empty reply always arrives first. */
const HOOK_TIMEOUT_S = 35
const OURS = /^http:\/\/127\.0\.0\.1:\d+\/desknotch\//

export type ClaudeQuestion = {
  question: string
  header: string
  multiSelect: boolean
  options: { label: string; description: string }[]
}
/** What the notch is shown; never the open connection. */
export type ClaudeRequest =
  | { id: string; kind: 'permission'; tool: string; project: string; text: string }
  | { id: string; kind: 'question'; project: string; questions: ClaudeQuestion[] }

type Pending = {
  view: ClaudeRequest
  res: http.ServerResponse
  timer: ReturnType<typeof setTimeout>
  at: number
}

const pending = new Map<string, Pending>()
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

function add(route: 'permission' | 'question', body: any, res: http.ServerResponse) {
  const input = body && typeof body.tool_input === 'object' && body.tool_input ? (body.tool_input as Record<string, unknown>) : {}
  const tool = str(body?.tool_name, 80)
  // A question reaches us on its own route; the permission route must not show it twice.
  if (route === 'permission' && tool === 'AskUserQuestion') return reply(res)
  if (pending.size >= MAX_PENDING) return reply(res)

  const id = crypto.randomUUID()
  const project = path.basename(str(body?.cwd, 1000)) || 'Claude'
  let view: ClaudeRequest
  if (route === 'permission') {
    view = { id, kind: 'permission', tool: tool || 'Tool', project, text: describe(tool, input) }
  } else {
    const questions = questionsOf(input)
    if (!questions.length || questions.some((q) => !q.options.length)) return reply(res)
    view = { id, kind: 'question', project, questions }
  }

  const timer = setTimeout(() => {
    leave(id)
    reply(res)
  }, FALL_THROUGH_MS)
  pending.set(id, { view, res, timer, at: Date.now() })
  // Claude gave up on this request (moved on, session ended): drop the popup.
  res.on('close', () => !res.writableFinished && leave(id))
  setClaudeWaiting(true)
  broadcast('claude:request', view)
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
  const route = req.url === '/desknotch/permission' ? 'permission' : req.url === '/desknotch/question' ? 'question' : null
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
    const picked = Array.isArray(given) ? given : [given]
    const labels = q.options.map((o) => o.label)
    if (!picked.length || picked.some((l) => typeof l !== 'string' || !labels.includes(l)) || (!q.multiSelect && picked.length > 1)) return false
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
}

// ── Claude's settings.json ──────────────────────────────────────────────────

const configPath = () => path.join(process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude'), 'settings.json')

const hook = (route: string, token: string) => ({
  type: 'http',
  url: `http://127.0.0.1:${port || settings()?.port || BASE_PORT}/desknotch/${route}`,
  timeout: HOOK_TIMEOUT_S,
  headers: { Authorization: `Bearer ${token}` },
})
const entries = (token: string): Record<string, { matcher?: string; hooks: unknown[] }> => ({
  PermissionRequest: { hooks: [hook('permission', token)] },
  PreToolUse: { matcher: 'AskUserQuestion', hooks: [hook('question', token)] },
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
  try {
    const text = fs.readFileSync(configPath(), 'utf8')
    if (text.trim()) JSON.parse(text)
  } catch (error) {
    valid = (error as NodeJS.ErrnoException).code === 'ENOENT'
  }
  return { enabled: stored?.enabled === true, running: server !== null, port, configPath: configPath(), valid }
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

export function registerClaudeIpc() {
  ipcMain.handle('claude:pending', () => queue())
  ipcMain.handle('claude:answer', (_event, id: unknown, choice: unknown) => answer(id, choice))
  ipcMain.handle('claude:status', () => state())
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
    return { ok: true }
  })

  void startClaudeServer()
}
