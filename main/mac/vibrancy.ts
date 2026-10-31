/** Glass on macOS: a native blur view cut to the notch's shapes (spec 0013). */
import { app, BrowserWindow } from 'electron'
import path from 'path'

export type GlassShape = { x: number; y: number; width: number; height: number; radii: [number, number, number, number]; ear?: 'left' | 'right' }

type Addon = {
  attach(handle: Buffer): void
  update(handle: Buffer, shapes: GlassShape[]): void
}

const load = (): Addon | null => {
  if (process.platform !== 'darwin') return null
  try {
    const root = app.isPackaged ? process.resourcesPath : path.join(process.cwd(), 'native', 'mac', 'build')
    // dlopen, not require: the bundler rewrites require and cannot see this file.
    const module = { exports: {} as Addon }
    process.dlopen(module as unknown as NodeJS.Module, path.join(root, 'vibrancy.node'))
    return module.exports
  } catch (error) {
    console.error('[glass] native blur unavailable:', error)
    return null
  }
}

const addon = load()
export const glassAvailable = addon !== null

/** The last list per window, reapplied when the window is shown again. */
const last = new Map<number, GlassShape[]>()

export const attachGlass = (window: BrowserWindow) => {
  if (!addon) return
  addon.attach(window.getNativeWindowHandle())
  window.on('show', () => applyGlass(window, last.get(window.id) ?? []))
  window.on('closed', () => last.delete(window.id))
}

const finite = (n: unknown): n is number => typeof n === 'number' && Number.isFinite(n)

/** Keeps only well formed shapes, so a bad message cannot reach the addon. */
export const cleanShapes = (input: unknown): GlassShape[] => {
  if (!Array.isArray(input)) return []
  const out: GlassShape[] = []
  for (const s of input.slice(0, 16)) {
    const radii = s?.radii
    if (![s?.x, s?.y, s?.width, s?.height].every(finite)) continue
    if (!Array.isArray(radii) || radii.length !== 4 || !radii.every(finite)) continue
    out.push({ x: s.x, y: s.y, width: s.width, height: s.height, radii: radii as GlassShape['radii'], ...(s.ear === 'left' || s.ear === 'right' ? { ear: s.ear } : {}) })
  }
  return out
}

export const applyGlass = (window: BrowserWindow, shapes: GlassShape[]) => {
  if (!addon || window.isDestroyed()) return
  last.set(window.id, shapes)
  addon.update(window.getNativeWindowHandle(), shapes)
}
