import { useEffect, useState } from 'react'

export type ClaudeQuestion = {
  question: string
  header: string
  multiSelect: boolean
  options: { label: string; description: string }[]
}
export type ClaudeRequest =
  | { id: string; kind: 'permission'; tool: string; project: string; text: string }
  | { id: string; kind: 'question'; project: string; questions: ClaudeQuestion[] }

export type ClaudeChoice = 'allow' | 'deny' | 'pass' | { answers: Record<string, string[]> }

/**
 * Claude Code's waiting requests, oldest first (the main process holds them
 * and drops each after 30 s). The notch shows the first.
 */
export function useClaude() {
  const [requests, setRequests] = useState<ClaudeRequest[]>([])

  useEffect(() => {
    let live = true
    void window.bridge?.invoke<ClaudeRequest[]>('claude:pending').then((list) => live && setRequests(list ?? []))
    const offAdd = window.bridge?.on<ClaudeRequest>('claude:request', (request) =>
      setRequests((list) => (list.some((r) => r.id === request.id) ? list : [...list, request])),
    )
    const offGone = window.bridge?.on<string>('claude:resolved', (id) => setRequests((list) => list.filter((r) => r.id !== id)))
    return () => {
      live = false
      offAdd?.()
      offGone?.()
    }
  }, [])

  const answer = (id: string, choice: ClaudeChoice) => void window.bridge?.invoke('claude:answer', id, choice)
  return { requests, answer }
}
