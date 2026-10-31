// @vitest-environment node
import { describe, expect, it, vi } from 'vitest'

// Mocked only so the file can be imported without Electron or the helper.
vi.mock('electron', () => ({ BrowserWindow: class {}, screen: {} }))
vi.mock('./store', () => ({ readStore: () => ({}) }))
vi.mock('./display', () => ({ notchWindows: () => new Map() }))
vi.mock('./mac/helper', () => ({ watchHelper: () => {} }))

import { isTerminalInFront } from './fullscreen'

// Raw line: "fullscreen,left,top,right,bottom,app"
const raw = (app: string) => `0,0,0,1920,1080,${app}`

describe('isTerminalInFront', () => {
  it.each(['com.apple.Terminal', 'com.googlecode.iterm2', 'dev.warp.Warp-Stable', 'WindowsTerminal', 'pwsh', 'CMD'])('%s counts as a terminal, any case', (app) => {
    expect(isTerminalInFront(raw(app), 'cli')).toBe(true)
  })

  it.each(['com.google.Chrome', 'chrome', 'com.apple.Safari', 'Code'])('%s is not a terminal', (app) => {
    expect(isTerminalInFront(raw(app), 'cli')).toBe(false)
  })

  it('is false for empty or short input', () => {
    expect(isTerminalInFront('', 'cli')).toBe(false)
    expect(isTerminalInFront('0,0,0,0,0,', 'cli')).toBe(false)
    expect(isTerminalInFront('0,0,0', 'cli')).toBe(false)
  })

  it('applies to cli and unknown sources, never vscode', () => {
    expect(isTerminalInFront(raw('com.apple.Terminal'), 'cli')).toBe(true)
    expect(isTerminalInFront(raw('com.apple.Terminal'), 'unknown')).toBe(true)
    expect(isTerminalInFront(raw('com.apple.Terminal'), 'vscode')).toBe(false)
  })
})
