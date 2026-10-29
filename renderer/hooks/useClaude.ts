import { useEffect, useState } from 'react'

export type ClaudeQuestion = {
  question: string
  header: string
  multiSelect: boolean
  options: { label: string; description: string }[]
}
export type ClaudeRequest =
  | { id: string; kind: 'permission'; sessionId: string; tool: string; project: string; text: string }
  | { id: string; kind: 'question'; sessionId: string; project: string; questions: ClaudeQuestion[] }

export type ClaudeSession = { id: string; project: string; source: 'cli' | 'vscode' | 'unknown'; state: 'working' | 'idle' | 'waiting'; at: number }
type SessionsPayload = { enabled: boolean; sessions: ClaudeSession[] }

export type ClaudeChoice = 'allow' | 'deny' | 'pass' | { answers: Record<string, string[]> }

/**
 * Claude Code's waiting requests, oldest first (the main process holds them
 * and drops each after 60 s). The notch shows the first.
 */
export function useClaude() {
  const [requests, setRequests] = useState<ClaudeRequest[]>([])
  const [feed, setFeed] = useState<SessionsPayload>({ enabled: false, sessions: [] })

  useEffect(() => {
    let live = true
    void window.bridge?.invoke<ClaudeRequest[]>('claude:pending').then((list) => live && setRequests(list ?? []))
    const offAdd = window.bridge?.on<ClaudeRequest>('claude:request', (request) =>
      setRequests((list) => (list.some((r) => r.id === request.id) ? list : [...list, request])),
    )
    const offGone = window.bridge?.on<string>('claude:resolved', (id) => setRequests((list) => list.filter((r) => r.id !== id)))
    void window.bridge?.invoke<SessionsPayload>('claude:sessions').then((f) => live && f && setFeed(f))
    const offFeed = window.bridge?.on<SessionsPayload>('claude:sessions-changed', setFeed)
    return () => {
      live = false
      offAdd?.()
      offGone?.()
      offFeed?.()
    }
  }, [])

  const answer = (id: string, choice: ClaudeChoice) => void window.bridge?.invoke('claude:answer', id, choice)
  return { requests, answer, enabled: feed.enabled, sessions: feed.sessions }
}
