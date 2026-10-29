import React, { useEffect, useState } from 'react'
import { motion } from 'motion/react'
import { Terminal } from 'lucide-react'
import type { ClaudeChoice, ClaudeRequest } from '../../hooks/useClaude'

export const CLAUDE_WIDTH = 420
export const CLAUDE_PERMISSION_HEIGHT = 196
export const CLAUDE_QUESTION_HEIGHT = 244

const LINES = 6

/**
 * Claude Code is waiting on you: a command to allow, or a question to answer.
 * One request at a time, oldest first. Nothing here is a default, a timer or a
 * keyboard shortcut: only a click on this request's own button answers it,
 * and "Ask in terminal" hands it straight back to Claude's own prompt.
 */
export const ClaudeView: React.FC<{
  request: ClaudeRequest
  index: number
  total: number
  accent: string
  onAnswer: (choice: ClaudeChoice) => void
}> = ({ request, index, total, accent, onAnswer }) => {
  const [all, setAll] = useState(false)
  const [part, setPart] = useState(0)
  const [picked, setPicked] = useState<Record<string, string[]>>({})
  // A new request starts clean.
  useEffect(() => {
    setAll(false)
    setPart(0)
    setPicked({})
  }, [request.id])

  const button = 'h-[26px] shrink-0 whitespace-nowrap rounded-full px-4 text-[11px] font-semibold'
  const quiet = `${button} bg-white/[0.08] font-medium text-white/70 transition-colors hover:bg-white/[0.14] hover:text-white`

  const head = (
    <div className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-[0.12em]" style={{ color: accent }}>
      <Terminal size={12} strokeWidth={2.4} />
      <span className="truncate">
        {request.kind === 'permission' ? request.tool : 'Question'} · {request.project}
      </span>
      {total > 1 && <span className="ml-auto shrink-0 text-white/50">{index + 1} of {total}</span>}
    </div>
  )

  if (request.kind === 'permission') {
    const lines = request.text.split('\n')
    const shown = all ? lines : lines.slice(0, LINES)
    return (
      <div className="flex h-full flex-col justify-center gap-2 px-1" onClick={(event) => event.stopPropagation()}>
        {head}
        <pre className={`min-h-0 whitespace-pre-wrap break-all rounded-lg bg-black/40 px-2.5 py-1.5 font-mono text-[11px] leading-snug text-white ${all ? 'max-h-[110px] overflow-auto' : 'overflow-hidden'}`}>
          {shown.join('\n')}
        </pre>
        {lines.length > LINES && !all && (
          <button type="button" className="-mt-1 self-start text-[10px] text-white/50 hover:text-white" onClick={() => setAll(true)}>
            Show all {lines.length} lines
          </button>
        )}
        <div className="flex gap-1.5">
          <motion.button whileTap={{ scale: 0.94 }} type="button" className={`${button} text-black`} style={{ background: accent }} onClick={() => onAnswer('allow')}>
            Allow
          </motion.button>
          <motion.button whileTap={{ scale: 0.94 }} type="button" className={quiet} onClick={() => onAnswer('deny')}>
            Deny
          </motion.button>
          <motion.button whileTap={{ scale: 0.94 }} type="button" className={`${quiet} ml-auto`} onClick={() => onAnswer('pass')}>
            Ask in terminal
          </motion.button>
        </div>
      </div>
    )
  }

  const question = request.questions[part]
  const chosen = picked[question.question] ?? []
  const last = part === request.questions.length - 1
  const next = (answers: Record<string, string[]>) => {
    if (last) onAnswer({ answers })
    else setPart(part + 1)
  }
  const choose = (label: string) => {
    if (question.multiSelect) {
      setPicked({ ...picked, [question.question]: chosen.includes(label) ? chosen.filter((l) => l !== label) : [...chosen, label] })
    } else {
      const answers = { ...picked, [question.question]: [label] }
      setPicked(answers)
      next(answers)
    }
  }
  return (
    <div className="flex h-full flex-col justify-center gap-2 px-1" onClick={(event) => event.stopPropagation()}>
      {head}
      <p className="line-clamp-2 text-[13px] font-semibold leading-snug text-white">
        {question.question}
        {request.questions.length > 1 && <span className="ml-1.5 text-[10px] font-medium text-white/50">{part + 1}/{request.questions.length}</span>}
      </p>
      <div className="flex max-h-[112px] flex-col gap-1 overflow-auto">
        {question.options.map((option) => (
          <motion.button
            key={option.label}
            whileTap={{ scale: 0.97 }}
            type="button"
            title={option.description || undefined}
            onClick={() => choose(option.label)}
            className="flex shrink-0 items-baseline gap-2 rounded-lg px-2.5 py-1 text-left text-[11px] text-white transition-colors hover:bg-white/[0.14]"
            style={{ background: chosen.includes(option.label) ? `${accent}55` : 'rgba(255,255,255,0.08)' }}
          >
            <span className="shrink-0 font-semibold">{option.label}</span>
            <span className="truncate text-white/50">{option.description}</span>
          </motion.button>
        ))}
      </div>
      <div className="flex gap-1.5">
        {question.multiSelect && (
          <motion.button whileTap={{ scale: 0.94 }} type="button" disabled={!chosen.length} className={`${button} text-black disabled:opacity-40`} style={{ background: accent }} onClick={() => next(picked)}>
            {last ? 'Confirm' : 'Next'}
          </motion.button>
        )}
        <motion.button whileTap={{ scale: 0.94 }} type="button" className={`${quiet} ml-auto`} onClick={() => onAnswer('pass')}>
          Answer in terminal
        </motion.button>
      </div>
    </div>
  )
}
