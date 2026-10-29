import { useEffect, useRef, useState } from 'react'
import { onStoreChange } from '../lib/store'
export type Task = { id: string; label: string; done: boolean; due?: string }

/** A Mac local day as YYYY-MM-DD (never toISOString, that is UTC and shifts the day). */
export const dayKey = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

/**
 * The one copy of the task list.
 *
 * Both views read and write through this, so ticking something in the notch's
 * glance row and opening the Tasks view show the same thing. Two components
 * each loading their own copy would drift apart the moment either changed.
 */
export interface TaskStore {
  tasks: Task[]
  setTasks: React.Dispatch<React.SetStateAction<Task[]>>
  add: (label: string, due?: string) => void
  toggle: (id: string) => void
  remove: (id: string) => void
}

export function useTasks(): TaskStore {
  const [tasks, setTasks] = useState<Task[]>([])

  // Guards the save effect: without it the empty initial state would overwrite
  // the stored list before the load has come back.
  const loaded = useRef(false)

  useEffect(() => {
    window.bridge
      ?.invoke<Task[]>('store:get', 'todos')
      .then((stored) => setTasks(stored ?? []))
      .catch(() => setTasks([]))
      .finally(() => {
        loaded.current = true
      })
  }, [])

  useEffect(() => onStoreChange<Task[]>('todos', setTasks), [])

  useEffect(() => {
    if (!loaded.current) return
    void window.bridge?.invoke('store:set', 'todos', tasks)
  }, [tasks])

  const add = (label: string, due?: string) => {
    const trimmed = label.trim()
    if (!trimmed) return
    setTasks((prev) => [...prev, { id: crypto.randomUUID(), label: trimmed, done: false, ...(due && { due }) }])
  }

  const toggle = (id: string) =>
    setTasks((prev) =>
      prev.map((task) => (task.id === id ? { ...task, done: !task.done } : task))
    )

  const remove = (id: string) => setTasks((prev) => prev.filter((task) => task.id !== id))

  return { tasks, setTasks, add, toggle, remove }
}
