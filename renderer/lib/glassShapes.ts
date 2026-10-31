/**
 * Glass on macOS draws its blur natively, cut to the notch's shapes (spec
 * 0013). Every glass Backdrop registers its host here; one frame loop reads
 * their rectangles and radii and sends the list to main when it changed.
 */

type Shape = { x: number; y: number; width: number; height: number; radii: number[]; ear?: 'left' | 'right' }

const hosts = new Map<HTMLElement, 'left' | 'right' | undefined>()
let frame = 0
let sent = '[]'

let native: Promise<boolean> | null = null
/** Whether the native blur loaded in main; asked once. */
export const glassNative = () => (native ??= window.bridge?.invoke<boolean>('glass:native').catch(() => false) ?? Promise.resolve(false))

const px = (v: string) => (v.endsWith('px') ? parseFloat(v) || 0 : 0)
const r2 = (n: number) => Math.round(n * 100) / 100

const send = (list: Shape[]) => {
  const next = JSON.stringify(list)
  if (next === sent) return
  sent = next
  window.bridge?.send('notch:glass', list)
}

const tick = () => {
  frame = 0
  if (!hosts.size || document.hidden) return
  const list: Shape[] = []
  for (const [el, ear] of hosts) {
    const b = el.getBoundingClientRect()
    if (b.width <= 0 || b.height <= 0) continue
    const c = getComputedStyle(el)
    const radii = [c.borderTopLeftRadius, c.borderTopRightRadius, c.borderBottomRightRadius, c.borderBottomLeftRadius].map((v) => r2(px(v)))
    list.push({ x: r2(b.left), y: r2(b.top), width: r2(b.width), height: r2(b.height), radii, ...(ear ? { ear } : {}) })
  }
  send(list)
  frame = requestAnimationFrame(tick)
}

const wake = () => {
  if (!frame && hosts.size) frame = requestAnimationFrame(tick)
}
let listening = false

export const registerGlass = (host: HTMLElement, ear?: 'left' | 'right') => {
  if (!listening) {
    listening = true
    document.addEventListener('visibilitychange', wake)
  }
  hosts.set(host, ear)
  wake()
  return () => {
    hosts.delete(host)
    if (!hosts.size) {
      cancelAnimationFrame(frame)
      frame = 0
      send([])
    }
  }
}
