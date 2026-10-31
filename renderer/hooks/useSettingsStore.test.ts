import { renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useSettingsStore } from './useSettingsStore'
import { DEFAULT_SETTINGS } from '../components/widgets/SettingsPanel'

/** Fake the Electron bridge: `stored` is what 'store:get' returns. */
function bridge(stored: unknown, bootResult: unknown = undefined) {
  const invoke = vi.fn(async (channel: string) => {
    if (channel === 'store:get') return stored
    if (channel === 'settings:start-on-boot') return bootResult
  })
  ;(window as any).bridge = { invoke, on: vi.fn(() => () => {}) }
  return invoke
}

const load = async (stored: unknown, boot?: unknown) => {
  const invoke = bridge(stored, boot)
  const hook = renderHook(() => useSettingsStore())
  // Loaded once the first save happens (the store:set call).
  await waitFor(() => expect(invoke).toHaveBeenCalledWith('store:set', 'settings', expect.anything()))
  return { invoke, settings: () => hook.result.current[0] }
}

describe('useSettingsStore', () => {
  beforeEach(() => {
    delete (window as any).bridge
  })

  it('starts on the defaults with no bridge', () => {
    const { result } = renderHook(() => useSettingsStore())
    expect(result.current[0]).toEqual(DEFAULT_SETTINGS)
  })

  it('merges stored values over the defaults', async () => {
    const { settings } = await load({ showMusic: false, focusMinutes: 50 })
    expect(settings().showMusic).toBe(false)
    expect(settings().focusMinutes).toBe(50)
    expect(settings().dockSide).toBe(DEFAULT_SETTINGS.dockSide)
  })

  it.each([
    ['translucent', 'glass'],
    ['mica', 'black'],
    ['transparent', 'transparent'],
  ])('migrates notchStyle %s to %s', async (from, to) => {
    const { settings } = await load({ notchStyle: from })
    expect(settings().notchStyle).toBe(to)
  })

  it.each([
    [{ companionMode: 'ai' }, 'screen'],
    [{ companionMode: 'tasks' }, 'reminder'],
    [{ companionSays: ['music'] }, 'music'],
    [{}, DEFAULT_SETTINGS.companionMode],
  ])('migrates companion mode %j to %s', async (stored, mode) => {
    const { settings } = await load(stored)
    expect(settings().companionMode).toBe(mode)
  })

  it('always turns the retired Focus card off', async () => {
    const { settings } = await load({ showFocus: true })
    expect(settings().showFocus).toBe(false)
  })

  it('trusts the OS answer for start on boot', async () => {
    const { settings } = await load({ startOnBoot: true }, false)
    expect(settings().startOnBoot).toBe(false)
  })

  it('keeps the stored start on boot when the OS refuses to answer', async () => {
    const { settings } = await load({ startOnBoot: false }, undefined)
    expect(settings().startOnBoot).toBe(false)
  })

  it('falls back to defaults when the store read fails', async () => {
    const invoke = vi.fn(async () => {
      throw new Error('boom')
    })
    ;(window as any).bridge = { invoke, on: vi.fn(() => () => {}) }
    const { result } = renderHook(() => useSettingsStore())
    await waitFor(() => expect(invoke).toHaveBeenCalled())
    expect(result.current[0]).toEqual(DEFAULT_SETTINGS)
  })
})
