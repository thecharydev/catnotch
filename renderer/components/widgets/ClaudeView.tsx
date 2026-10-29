import React, { useEffect, useRef, useState } from 'react'
import { motion, useReducedMotion } from 'motion/react'
import { ArrowLeft, ChevronDown, ChevronUp, Terminal } from 'lucide-react'
import type { ClaudeChoice, ClaudeQuestion, ClaudeRequest, ClaudeSession } from '../../hooks/useClaude'

export const CLAUDE_WIDTH = 420
export const CLAUDE_QUESTION_HEIGHT = 300
export const CLAUDE_ROW = 30
export const CLAUDE_CHAT_HEIGHT = 340
export const CLAUDE_SESSIONS_MAX = 6
/** Header and padding around the session rows. */
export const claudeSessionsHeight = (count: number) => 44 + Math.max(1, Math.min(count, CLAUDE_SESSIONS_MAX)) * CLAUDE_ROW

const LINES = 6

const ring = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-white'
const pill = `h-[26px] shrink-0 whitespace-nowrap rounded-full px-4 text-[11px] font-semibold ${ring}`
const quietPill = `${pill} bg-white/[0.08] font-medium text-white/70 transition-colors hover:bg-white/[0.14] hover:text-white`

export const CLAUDE_STRIP_PERMISSION = 44
export const CLAUDE_STRIP_QUESTION = 76
/** Height of what is shown for a request: the strip, the expanded command, or the card. */
export const claudeStripHeight = (request: ClaudeRequest, open: boolean) =>
  request.kind === 'permission'
    ? CLAUDE_STRIP_PERMISSION + (open ? Math.min(110, Math.min(LINES, request.text.split('\n').length) * 16 + 12) : 0)
    : open ? CLAUDE_QUESTION_HEIGHT : CLAUDE_STRIP_QUESTION

/**
 * Claude Code is waiting on you, as a slim strip over the open tab. Nothing
 * here is a default or a shortcut: only a click on this request's own button
 * or chip answers it, and the terminal icon hands it back to Claude's prompt.
 * A question that needs reading or typing opens the card (ClaudeView).
 */
export const ClaudeStrip: React.FC<{
  request: ClaudeRequest
  index: number
  total: number
  accent: string
  open: boolean
  onOpen: (open: boolean) => void
  onAnswer: (choice: ClaudeChoice) => void
}> = ({ request, index, total, accent, open, onOpen, onAnswer }) => {
  const reduce = useReducedMotion()
  const count = total > 1 ? <span className="shrink-0 text-[10px] text-white/60">{index + 1} of {total}</span> : null
  const dot = <span aria-hidden className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ background: '#fbbf24' }} />
  const frame = 'w-full overflow-hidden px-1'
  const hover = (on: boolean) => void window.bridge?.invoke('claude:hold', request.id, on, 'hover')
  // Leaving the strip (or it being answered) lets the timer run again.
  useEffect(() => () => hover(false), [request.id])
  const motionProps = reduce
    ? {}
    : { initial: { opacity: 0, y: -10 }, animate: { opacity: 1, y: 0 }, exit: { opacity: 0 }, transition: { duration: 0.15 } }

  if (request.kind === 'question' && open) {
    return (
      <motion.div key={request.id} {...motionProps} className="h-full w-full" style={{ height: CLAUDE_QUESTION_HEIGHT }} onMouseEnter={() => hover(true)} onMouseLeave={() => hover(false)}>
        <ClaudeView request={request} index={index} total={total} accent={accent} onAnswer={onAnswer} onCollapse={() => onOpen(false)} />
      </motion.div>
    )
  }

  if (request.kind === 'permission') {
    const lines = request.text.split('\n')
    return (
      <motion.div key={request.id} {...motionProps} className={frame} onMouseEnter={() => (hover(true), onOpen(true))} onMouseLeave={() => (hover(false), onOpen(false))} onClick={(event) => event.stopPropagation()}>
        <div className="flex items-center gap-2" style={{ height: CLAUDE_STRIP_PERMISSION }}>
          {dot}
          <span className="max-w-[110px] shrink-0 truncate text-[11px] font-semibold text-white">{request.tool}</span>
          <span className="max-w-[70px] shrink-0 truncate text-[11px] text-white/60">{request.project}</span>
          <button
            type="button"
            aria-expanded={open}
            aria-label="Show the whole command"
            onClick={() => onOpen(!open)}
            className={`min-w-0 flex-1 truncate rounded-[8px] bg-black/40 px-2 py-1 text-left font-mono text-[11px] text-white ${ring}`}
          >
            {lines[0]}
          </button>
          {count}
          <button type="button" className={quietPill} onClick={() => onAnswer('deny')}>Deny</button>
          <motion.button whileTap={{ scale: 0.94 }} type="button" className={`${pill} text-black`} style={{ background: accent }} onClick={() => onAnswer('allow')}>
            Allow
          </motion.button>
          <button
            type="button"
            title="Ask in terminal"
            aria-label="Ask in terminal"
            onClick={() => onAnswer('pass')}
            className={`flex h-[26px] w-[26px] shrink-0 items-center justify-center rounded-full bg-white/[0.08] text-white/70 transition-colors hover:bg-white/[0.14] hover:text-white ${ring}`}
          >
            <Terminal size={12} strokeWidth={2.4} />
          </button>
        </div>
        {open && (
          <pre className="mb-2 max-h-[110px] overflow-auto whitespace-pre-wrap break-all rounded-[8px] bg-black/40 px-2.5 py-1.5 font-mono text-[11px] leading-[16px] text-white">
            {lines.join('\n')}
          </pre>
        )}
      </motion.div>
    )
  }

  const q = request.questions[0]
  const simple = request.questions.length === 1 && !q.multiSelect
  const chips = simple ? (q.options.length > 3 ? q.options.slice(0, 2) : q.options) : []
  const more = simple && q.options.length > 3 ? q.options.length - 2 : 0
  return (
    <motion.div key={request.id} {...motionProps} className={`${frame} cursor-pointer`} onMouseEnter={() => (hover(true), onOpen(true))} onMouseLeave={() => hover(false)} onClick={(event) => (event.stopPropagation(), onOpen(true))}>
      <div className="flex flex-col justify-center gap-1.5" style={{ height: CLAUDE_STRIP_QUESTION }}>
        <div className="flex items-center gap-2">
          {dot}
          <span className="max-w-[70px] shrink-0 truncate text-[11px] text-white/60">{request.project}</span>
          <span className="min-w-0 flex-1 truncate text-[12px] font-semibold text-white">{q.question}</span>
          {count}
          <button
            type="button"
            title="Open the question"
            aria-label="Open the question"
            onClick={() => onOpen(true)}
            className={`flex h-[26px] w-[26px] shrink-0 items-center justify-center rounded-full bg-white/[0.08] text-white/70 hover:bg-white/[0.14] hover:text-white ${ring}`}
          >
            <ChevronDown size={12} strokeWidth={2.4} />
          </button>
        </div>
        <div className="flex gap-1.5 pl-3.5">
          {chips.map((option) => (
            <button
              key={option.label}
              type="button"
              className={`${quietPill} max-w-[130px] truncate px-3`}
              onClick={(event) => (event.stopPropagation(), onAnswer({ answers: { [q.question]: [option.label] } }))}
            >
              {option.label}
            </button>
          ))}
          {more > 0 && (
            <button type="button" className={`${quietPill} px-3`} aria-label={`${more} more options, open the question`}>
              +{more}
            </button>
          )}
          {!simple && <span className="text-[11px] text-white/60">Open to answer</span>}
        </div>
      </div>
    </motion.div>
  )
}

/** The question card: full text, every option, a text box. Questions only. */
export const ClaudeView: React.FC<{
  request: Extract<ClaudeRequest, { kind: 'question' }>
  index: number
  total: number
  accent: string
  onAnswer: (choice: ClaudeChoice) => void
  onCollapse: () => void
}> = ({ request, index, total, accent, onAnswer, onCollapse }) => {
  const [part, setPart] = useState(0)
  const [picked, setPicked] = useState<Record<string, string[]>>({})
  const [typed, setTyped] = useState<Record<string, string>>({})
  // A new request starts clean.
  useEffect(() => {
    setPart(0)
    setPicked({})
    setTyped({})
  }, [request.id])
  // The timer waits while you type or have an option picked; leaving the card hands it back.
  const [focused, setFocused] = useState(false)
  const working = focused || Object.values(typed).some((v) => v.trim()) || Object.values(picked).some((l) => l.length > 0)
  useEffect(() => void window.bridge?.invoke('claude:hold', request.id, working, 'type'), [request.id, working])
  useEffect(() => () => void window.bridge?.invoke('claude:hold', request.id, false, 'type'), [request.id])

  const button = pill
  const quiet = quietPill

  const head = (
    <div className="flex items-center gap-2 text-[11px] font-semibold" style={{ color: accent }}>
      <Terminal size={12} strokeWidth={2.4} />
      <span className="truncate">{request.project}</span>
      {total > 1 && <span className="shrink-0 font-normal text-white/60">{index + 1} of {total}</span>}
      <button type="button" aria-label="Back to the strip" title="Back to the strip" onClick={onCollapse} className={`ml-auto flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full bg-white/[0.08] text-white/70 hover:text-white ${ring}`}>
        <ChevronUp size={12} strokeWidth={2.4} />
      </button>
    </div>
  )

  const question = request.questions[part]
  const chosen = picked[question.question] ?? []
  const text = typed[question.question] ?? ''
  const last = part === request.questions.length - 1
  // What this part sends: ticked labels, then the typed words.
  const answerOf = (q: ClaudeQuestion) => [...(picked[q.question] ?? []), ...((typed[q.question] ?? '').trim() ? [(typed[q.question] ?? '').trim()] : [])]
  const ready = answerOf(question).length > 0
  const all_ready = request.questions.every((q) => answerOf(q).length > 0)
  const send = () => onAnswer({ answers: Object.fromEntries(request.questions.map((q) => [q.question, answerOf(q)])) })
  const choose = (label: string) => {
    if (question.multiSelect) {
      setPicked({ ...picked, [question.question]: chosen.includes(label) ? chosen.filter((l) => l !== label) : [...chosen, label] })
    } else {
      // One choice replaces any typed words, and the other way round.
      setPicked({ ...picked, [question.question]: [label] })
      setTyped({ ...typed, [question.question]: '' })
    }
  }
  const type = (value: string) => {
    setTyped({ ...typed, [question.question]: value })
    if (!question.multiSelect && value) setPicked({ ...picked, [question.question]: [] })
  }
  const release = () => window.bridge?.send('notch:pinned', false)
  return (
    <div
      className="flex h-full flex-col justify-center gap-2 px-1"
      onClick={(event) => event.stopPropagation()}
      onKeyDown={(event) => {
        // Enter on an action button does its own thing; anywhere else it moves on: next question, then the Send button.
        if (event.key !== 'Enter' || (event.target as HTMLElement).closest('[data-act]')) return
        event.preventDefault()
        if (!ready) return
        if (!last) setPart(part + 1)
        else if (all_ready) event.currentTarget.querySelector<HTMLButtonElement>('[data-send]')?.focus()
      }}
    >
      {head}
      <p className="max-h-[64px] overflow-auto whitespace-pre-wrap text-[13px] font-semibold leading-snug text-white">
        {question.question}
        {request.questions.length > 1 && <span className="ml-1.5 text-[10px] font-medium text-white/60">{part + 1}/{request.questions.length}</span>}
      </p>
      <div className="flex max-h-[104px] flex-col gap-1 overflow-auto">
        {question.options.map((option) => (
          <motion.button
            key={option.label}
            whileTap={{ scale: 0.97 }}
            type="button"
            onClick={() => choose(option.label)}
            className="flex shrink-0 flex-col rounded-lg px-2.5 py-1 text-left text-[11px] text-white transition-colors hover:bg-white/[0.14]"
            style={{ background: chosen.includes(option.label) ? `${accent}55` : 'rgba(255,255,255,0.08)' }}
          >
            <span className="font-semibold">{option.label}</span>
            {option.description && <span className="whitespace-pre-wrap text-white/55">{option.description}</span>}
          </motion.button>
        ))}
      </div>
      <input
        value={text}
        maxLength={2000}
        placeholder="Or type your own answer"
        aria-label="Your own answer"
        spellCheck={false}
        onChange={(event) => type(event.target.value)}
        onFocus={() => (window.bridge?.send('notch:pinned', true), setFocused(true))}
        onBlur={() => (release(), setFocused(false))}
        className="h-[26px] w-full min-w-0 shrink-0 rounded-[8px] border border-white/15 bg-white/[0.08] px-2 text-[11px] text-white outline-none placeholder:text-white/35 focus:border-white/40 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
      />
      <div className="flex gap-1.5">
        {part > 0 && (
          <motion.button whileTap={{ scale: 0.94 }} type="button" data-act className={quiet} onClick={() => setPart(part - 1)}>
            Back
          </motion.button>
        )}
        <motion.button
          whileTap={{ scale: 0.94 }}
          type="button"
          data-act
          data-send={last ? '' : undefined}
          disabled={last ? !all_ready : !ready}
          className={`${button} text-black disabled:opacity-40`}
          style={{ background: accent }}
          onClick={() => (last ? (release(), send()) : setPart(part + 1))}
        >
          {last ? 'Send' : 'Next'}
        </motion.button>
        <motion.button whileTap={{ scale: 0.94 }} type="button" data-act className={`${quiet} ml-auto`} onClick={() => (release(), onAnswer('pass'))}>
          Answer in terminal
        </motion.button>
      </div>
    </div>
  )
}

const BADGE: Record<ClaudeSession['source'], string | null> = { cli: 'CLI', vscode: 'VS Code', unknown: null }
const STATE: Record<ClaudeSession['state'], string> = { working: 'Working', idle: 'Idle', waiting: 'Waiting for you' }

/** Every Claude Code session on this machine, and what each is doing. */
export const ClaudeSessions: React.FC<{ sessions: ClaudeSession[]; enabled: boolean; accent: string; onSettings: () => void; onOpen: (id: string) => void }> = ({ sessions, enabled, accent, onSettings, onOpen }) => (
  <div className="flex h-full flex-col justify-center gap-1.5 px-1" onClick={(event) => event.stopPropagation()}>
    <div className="flex items-center gap-2 text-[11px] font-semibold" style={{ color: accent }}>
      <Terminal size={12} strokeWidth={2.4} />
      <span>Claude sessions, {sessions.length}</span>
    </div>
    {sessions.length === 0 ? (
      enabled ? (
      <p className="text-[11px] text-white/50">No Claude sessions yet. Start one in a terminal or VS Code.</p>
    ) : (
      <div className="flex flex-col items-start gap-2">
        <p className="text-[11px] text-white/60">Switched off. Turn on Claude Code on the notch to see your sessions and answer questions here.</p>
        <button type="button" onClick={onSettings} className="h-[26px] rounded-full px-4 text-[11px] font-semibold text-black" style={{ background: accent }}>
          Open Settings
        </button>
      </div>
    )
    ) : (
      <div className="flex flex-col overflow-auto" style={{ maxHeight: CLAUDE_SESSIONS_MAX * CLAUDE_ROW }}>
        {sessions.map((s) => (
          <button
            key={s.id}
            type="button"
            onClick={() => onOpen(s.id)}
            className={`flex shrink-0 items-center gap-2 rounded-md px-1 text-left text-[11px] text-white transition-colors hover:bg-white/[0.08] ${ring}`}
            style={{ height: CLAUDE_ROW }}
          >
            <span
              className="h-1.5 w-1.5 shrink-0 rounded-full"
              style={{ background: s.state === 'waiting' ? '#fbbf24' : s.state === 'working' ? accent : 'rgba(255,255,255,0.3)' }}
            />
            <span className="min-w-0 flex-1 truncate font-semibold">{s.project}</span>
            {BADGE[s.source] && <span className="shrink-0 rounded-full bg-white/[0.1] px-1.5 py-px text-[9px] font-semibold text-white/70">{BADGE[s.source]}</span>}
            <span className={`shrink-0 text-[10px] ${s.state === 'waiting' ? 'font-semibold text-amber-300' : 'text-white/50'}`}>{STATE[s.state]}</span>
          </button>
        ))}
      </div>
    )}
  </div>
)

type Turn = { role: 'user' | 'assistant' | 'tool'; text: string }
type Chat = { turns: Turn[]; busy: boolean } | { error: string }

const SEND_ERROR: Record<string, string> = {
  busy: 'Claude is busy in its own window.',
  folder: "This session's folder is gone.",
  notfound: 'Claude was not found on this machine.',
  off: 'Claude Code is switched off.',
  unknown: 'This session is not available.',
}

/** One session's conversation, with a box to send it a message. */
export const ClaudeChat: React.FC<{ session: ClaudeSession | undefined; accent: string; onBack: () => void }> = ({ session, accent, onBack }) => {
  const id = session?.id
  const [chat, setChat] = useState<Chat | null>(null)
  const [text, setText] = useState('')
  const [note, setNote] = useState('')
  const box = useRef<HTMLDivElement>(null)
  const atBottom = useRef(true)

  useEffect(() => {
    if (!id) return
    let live = true
    const load = () => void window.bridge?.invoke<Chat>('claude:chat', id).then((c) => live && c && setChat(c))
    load()
    const timer = setInterval(load, 2000)
    const off = window.bridge?.on<string | undefined>('claude:chat-changed', (sid, why) => {
      if (sid !== id) return
      if (why) setNote(why)
      load()
    })
    return () => {
      live = false
      clearInterval(timer)
      off?.()
    }
  }, [id])

  // Stay at the bottom while it is the bottom you were reading.
  useEffect(() => {
    const el = box.current
    if (el && atBottom.current) el.scrollTop = el.scrollHeight
  }, [chat])

  const release = () => window.bridge?.send('notch:pinned', false)
  const back = () => (release(), onBack())
  const turns = chat && 'turns' in chat ? chat.turns : []
  const failed = chat && 'error' in chat ? chat.error : ''
  const replying = chat && 'busy' in chat && chat.busy && session?.state === 'idle'
  // A turn in progress in Claude's own window, or one we started: no second message on top of it.
  const blocked = !session || !chat || 'error' in chat || chat.busy || session.state !== 'idle'
  const reason = failed ? SEND_ERROR[failed] ?? SEND_ERROR.unknown : replying ? 'Claude is replying…' : session && session.state !== 'idle' ? SEND_ERROR.busy : ''

  const send = () => {
    const message = text.trim()
    if (!id || !message || blocked) return
    setNote('')
    void window.bridge?.invoke<{ ok?: true; error?: string }>('claude:send', id, message).then((r) => {
      if (r?.ok) setText('')
      else setNote(SEND_ERROR[r?.error ?? 'unknown'] ?? SEND_ERROR.unknown)
    })
  }

  return (
    <div className="flex h-full flex-col gap-1.5 px-1" onClick={(event) => event.stopPropagation()}>
      <div className="flex items-center gap-2 text-[11px] font-semibold" style={{ color: accent }}>
        <button type="button" onClick={back} aria-label="Back to sessions" className={`flex h-[22px] w-[22px] items-center justify-center rounded-full bg-white/[0.08] text-white/80 hover:bg-white/[0.14] ${ring}`}>
          <ArrowLeft size={12} strokeWidth={2.4} />
        </button>
        <span className="min-w-0 flex-1 truncate">{session?.project ?? 'Session ended'}</span>
        {session && BADGE[session.source] && <span className="shrink-0 rounded-full bg-white/[0.1] px-1.5 py-px text-[9px] font-semibold text-white/70">{BADGE[session.source]}</span>}
      </div>
      <div
        ref={box}
        role="log"
        aria-live="polite"
        onScroll={(event) => {
          const el = event.currentTarget
          atBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 24
        }}
        className="flex min-h-0 flex-1 flex-col gap-1.5 overflow-auto rounded-lg bg-black/30 p-2"
      >
        {turns.length === 0 && <p className="text-[11px] text-white/50">{failed ? SEND_ERROR[failed] ?? SEND_ERROR.unknown : chat ? 'Nothing said yet.' : 'Loading…'}</p>}
        {turns.map((turn, i) =>
          turn.role === 'tool' ? (
            <p key={i} className="text-[10px] text-white/40">Ran {turn.text}</p>
          ) : (
            <p
              key={i}
              className={`max-w-[88%] whitespace-pre-wrap break-words rounded-xl px-2.5 py-1 text-[11px] leading-snug text-white ${turn.role === 'user' ? 'self-end' : 'self-start bg-white/[0.08]'}`}
              style={turn.role === 'user' ? { background: `${accent}55` } : undefined}
            >
              {turn.text}
            </p>
          ),
        )}
      </div>
      {(reason || note) && <p className="text-[10px] text-white/60">{note || reason}</p>}
      <div className="flex gap-1.5">
        <input
          value={text}
          maxLength={4000}
          disabled={blocked}
          placeholder="Message Claude"
          aria-label="Message Claude"
          spellCheck={false}
          onChange={(event) => setText(event.target.value)}
          onFocus={() => window.bridge?.send('notch:pinned', true)}
          onBlur={release}
          onKeyDown={(event) => event.key === 'Enter' && (send(), event.preventDefault())}
          className="h-[26px] min-w-0 flex-1 rounded-[8px] border border-white/15 bg-white/[0.08] px-2 text-[11px] text-white outline-none placeholder:text-white/35 focus:border-white/40 disabled:opacity-40"
        />
        <motion.button
          whileTap={{ scale: 0.94 }}
          type="button"
          disabled={blocked || !text.trim()}
          onClick={() => (send(), release())}
          className={`${pill} text-black disabled:opacity-40`}
          style={{ background: accent }}
        >
          Send
        </motion.button>
      </div>
    </div>
  )
}
