import React from 'react'
import { render } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

// The avatars draw on a canvas; record the props they are given instead.
const seen = vi.hoisted(() => ({ bot: [] as any[], cat: [] as any[] }))
vi.mock('bot-avatars', () => ({
  BotAvatar: (p: any) => (seen.bot.push(p), null),
}))
vi.mock('./CatppuccinCat', () => ({
  CatppuccinCat: (p: any) => (seen.cat.push(p), null),
}))

import { CompanionTile } from './CompanionTile'

const timer: any = { remaining: 0, remainingMs: 0, durationMs: 0, isRunning: false, finished: false, start() {}, add() {}, stop() {}, reset() {} }
const tasks: any = { tasks: [], setTasks() {}, add() {}, toggle() {}, remove() {} }

const tile = (over: Record<string, unknown>) => (
  <CompanionTile
    avatar={'catppuccin' as any}
    photo={null}
    tasks={tasks}
    timer={timer}
    track={null}
    playing={false}
    mode="time"
    sleeps="time"
    accent="#cba6f7"
    flavor="mocha"
    look={false}
    canSleep={false}
    react={false}
    minutes={25}
    onMinutes={() => {}}
    open={false}
    onToggle={() => {}}
    {...over}
  />
)

const last = (list: any[]) => list[list.length - 1]

describe('CompanionTile pointer tracking', () => {
  beforeEach(() => {
    seen.bot.length = 0
    seen.cat.length = 0
  })

  it('does not let the cat follow the real pointer when Look around is off', () => {
    render(tile({ look: false }))
    expect(last(seen.cat).interactive).toBe(false)
  })

  it('does not let a bot follow the real pointer when Look around is off', () => {
    render(tile({ avatar: 'bot', look: false }))
    expect(last(seen.bot).interactive).toBe(false)
  })

  it('lets the avatar follow the gaze when Look around is on', () => {
    render(tile({ look: true }))
    expect(last(seen.cat).interactive).toBe(true)
  })
})
