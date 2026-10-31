import React, { useEffect, useRef } from 'react'
import { BotAvatarSim, BOT_AVATAR_OVERSCAN, BOT_AVATAR_RISE, autoInk, drawBotAvatarFrame, restPose, type BotAvatarState } from 'bot-avatars'
import { FLAVORS, DEFAULT_FLAVOR, type Flavor } from '../../lib/catppuccin'

interface CatProps {
  size: number
  /** The face colour (eyes), a hex from the flavour's accents. */
  coat: string
  flavor?: Flavor
  state?: BotAvatarState
  /** One frame, no loop: the collapsed notch and the settings thumbnail. */
  still?: boolean
  /** The head follows the pointer and a click makes it hop. Default on. */
  interactive?: boolean
  /** Seconds between idle hops; 0 for none. */
  jumpEvery?: number
  turn?: number
}

// Our own outline of the official mascot (100 by 100), drawn on the bot-avatars engine.
const BODY_D =
  'M14 24 Q14 11 20 14 L36 25 Q50 20 63 24 L77 12 Q83 10 83 21 Q88 33 89 52 Q89 67 79 78 Q76 87 77 100 L23 100 Q24 87 21 78 Q11 67 11 52 Q11 38 14 24 Z'
const BOW_D = 'M59 88 L51 84 L51 94 Z M59 88 L67 83 L68 93 Z'
// Built on first draw: Path2D does not exist while Next renders on the server.
let shapes: { BODY: Path2D; BOW: Path2D } | null = null

const pointer = { x: NaN, y: NaN }
let listening = false
function listen() {
  if (listening) return
  listening = true
  document.addEventListener('pointermove', (e) => ((pointer.x = e.clientX), (pointer.y = e.clientY)), { passive: true })
  document.addEventListener('pointerleave', () => (pointer.x = pointer.y = NaN))
}

export const CatppuccinCat: React.FC<CatProps> = ({
  size,
  coat,
  flavor = DEFAULT_FLAVOR,
  state = 'default',
  still,
  interactive = true,
  jumpEvery = 8,
  turn = 1,
}) => {
  const ref = useRef<HTMLCanvasElement>(null)
  const sim = useRef<BotAvatarSim | undefined>(undefined)
  const { base, accents } = FLAVORS[flavor] ?? FLAVORS[DEFAULT_FLAVOR]
  const bow = coat === accents.Red ? accents.Pink : accents.Red
  const live = useRef({ coat, bow, base, state, interactive, still })
  live.current = { coat, bow, base, state, interactive, still }
  const reduced = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches

  useEffect(() => {
    const canvas = ref.current
    if (!canvas) return
    const dpr = Math.min(2, window.devicePixelRatio || 1)
    const px = Math.round(size * BOT_AVATAR_OVERSCAN * dpr)
    canvas.width = canvas.height = px
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    const s = (sim.current ??= new BotAvatarSim(Math.random(), live.current.state))
    s.setTurn(turn)
    s.setJump({ every: jumpEvery })

    const paint = () => {
      shapes ??= { BODY: new Path2D(BODY_D), BOW: new Path2D(BOW_D) }
      const { BODY, BOW } = shapes
      const l = live.current
      const pose = l.still || reduced ? restPose(l.state) : s.pose
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
      ctx.clearRect(0, 0, px, px)
      drawBotAvatarFrame(ctx, size, pose, {
        path: BODY, face: 'eyes', faceX: 50, faceY: 50, faceScale: 1,
        color: l.base, ink: l.coat || autoInk(l.base), shading: 'plastic', typeKey: 'catppuccin',
        theme: 'dark', dpr, still: !!l.still || reduced,
      })
      // The bow sits on the front, so it hides when the spin shows the back, and slides against the head's turn.
      if (Math.cos(pose.yaw) > 0) {
        const k = size / 100
        const m = (size * (BOT_AVATAR_OVERSCAN - 1)) / 2
        ctx.save()
        ctx.translate(m + pose.x * k, m + size * BOT_AVATAR_RISE + pose.y * k)
        ctx.scale(k * pose.sx, k * pose.sy)
        ctx.translate(-Math.sin(pose.yaw) * 6, 0)
        ctx.fillStyle = ctx.strokeStyle = l.bow
        ctx.lineWidth = 1.5
        ctx.lineJoin = 'round'
        ctx.fill(BOW)
        ctx.stroke(BOW)
        ctx.beginPath()
        ctx.arc(59, 88, 2.6, 0, Math.PI * 2)
        ctx.fill()
        ctx.restore()
      }
    }
    paint()
    if (still || reduced) return

    listen()
    let raf = 0
    let last = 0
    let visible = true
    const tick = (t: number) => {
      const dt = last ? Math.min(0.1, (t - last) / 1000) : 0
      last = t
      const l = live.current
      if (s.state !== l.state) s.setState(l.state)
      if (l.interactive && !Number.isNaN(pointer.x)) {
        const r = canvas.getBoundingClientRect()
        const w = r.width / BOT_AVATAR_OVERSCAN || 1
        const dx = (pointer.x - (r.left + r.width / 2)) / w
        const dy = (pointer.y - (r.top + r.height / 2 + BOT_AVATAR_RISE * w)) / w
        const d = Math.hypot(dx, dy)
        s.setPointer(dx / Math.max(1, d), dy / Math.max(1, d), d < 1 ? 1 : d > 3 ? 0 : (3 - d) / 2)
      } else s.setPointer(0, 0, 0)
      s.update(dt)
      paint()
      raf = requestAnimationFrame(tick)
    }
    const io = new IntersectionObserver((e) => {
      visible = e[0]?.isIntersecting ?? true
      cancelAnimationFrame(raf)
      last = 0
      if (visible && !document.hidden) raf = requestAnimationFrame(tick)
    })
    io.observe(canvas)
    return () => {
      cancelAnimationFrame(raf)
      io.disconnect()
    }
  }, [size, still, reduced, jumpEvery, turn, coat, bow, base, state])

  const box = size * BOT_AVATAR_OVERSCAN
  const m = (box - size) / 2
  return (
    <canvas
      ref={ref}
      role="img"
      aria-label="Catppuccin cat"
      onClick={() => live.current.interactive && !live.current.still && sim.current?.poke()}
      style={{
        display: 'inline-block', flex: 'none', verticalAlign: 'middle', width: box, height: box,
        margin: `${-m - BOT_AVATAR_RISE * size}px ${-m}px ${-m + BOT_AVATAR_RISE * size}px`,
      }}
    />
  )
}
