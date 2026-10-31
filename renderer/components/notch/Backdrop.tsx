import React, { useEffect, useRef, useState } from 'react'

/**
 * What a surface shows through under the Glass style: a live view of the
 * screen behind, blurred. Used by the notch, the tabs dock and the apps tray,
 * so they read as one material. The window is excluded from capture (see
 * `glass:protect` in main/ipc/system.ts), so the capture shows what is
 * underneath. One capture at 15 fps is shared by every surface, and runs
 * while this style is on.
 *
 * Each layer is sized to the whole display and shifted by its surface's own
 * position, so every surface acts as a window onto the right part of the
 * screen, even while it springs between sizes.
 */

// ── One shared capture ──────────────────────────────────────────────────────

let users = 0
let pending: Promise<MediaStream | null> | null = null
let shared: MediaStream | null = null

const acquire = () => {
  users++
  if (users === 1) void window.bridge?.invoke('glass:protect', true)
  pending ??= (async () => {
    const id = await window.bridge?.invoke<string | null>('glass:source')
    if (!id) return null
    try {
      shared = await navigator.mediaDevices.getUserMedia({
        audio: false,
        // Chromium's desktop-capture constraints, which Electron accepts.
        video: { mandatory: { chromeMediaSource: 'desktop', chromeMediaSourceId: id, maxFrameRate: 15 } } as unknown as MediaTrackConstraints,
      })
      return shared
    } catch {
      return null
    }
  })()
  return pending
}

const release = () => {
  users = Math.max(0, users - 1)
  if (users > 0) return
  void window.bridge?.invoke('glass:protect', false)
  const stream = shared
  pending = null
  shared = null
  stream?.getTracks().forEach((t) => t.stop())
}

// ── The layer ───────────────────────────────────────────────────────────────

/** The one place the look is tuned: blur and light per style (spec 0010). */
const RECIPES = {
  transparent: {
    large: 'blur(4px) saturate(1.3) brightness(0.95)',
    small: 'blur(2px) saturate(1.3) brightness(0.95)',
    tint: 'linear-gradient(180deg, rgba(8, 8, 12, 0.18) 0%, rgba(8, 8, 12, 0.26) 100%)',
    rim: 'inset 1px 0 0 rgba(255,255,255,0.22), inset -1px 0 0 rgba(255,255,255,0.22), inset 0 -1px 0 rgba(255,255,255,0.22)',
    top: false,
  },
  glass: {
    large: 'blur(24px) saturate(1.8) brightness(0.9)',
    small: 'blur(10px) saturate(1.8) brightness(0.9)',
    tint: 'linear-gradient(180deg, rgba(8, 8, 12, 0.28) 0%, rgba(8, 8, 12, 0.42) 100%)',
    rim: 'inset 1px 0 0 rgba(255,255,255,0.22), inset -1px 0 0 rgba(255,255,255,0.22), inset 0 -1px 0 rgba(255,255,255,0.22)',
    top: true,
  },
} as const

export const Backdrop: React.FC<{ kind: keyof typeof RECIPES; host: React.RefObject<HTMLElement | null> }> = ({ kind, host }) => {
  const layer = useRef<HTMLDivElement>(null)
  const video = useRef<HTMLVideoElement>(null)
  const [live, setLive] = useState(false)
  const recipe = RECIPES[kind]

  // Join the shared capture while mounted.
  useEffect(() => {
    let cancelled = false
    void acquire().then((stream) => {
      if (cancelled || !stream || !video.current) return
      video.current.srcObject = stream
      void video.current.play()
    })
    return () => {
      cancelled = true
      setLive(false)
      release()
    }
  }, [kind])

  // Keep the layer aligned with the surface's place on screen while it
  // animates. Small surfaces (the closed bar, the dock) blur less, so what is
  // behind them stays recognisable instead of smearing into one colour.
  useEffect(() => {
    let frame = 0
    let small: boolean | null = null
    if (video.current) video.current.style.filter = ''
    const follow = () => {
      const box = host.current?.getBoundingClientRect()
      if (box && layer.current) {
        layer.current.style.transform = `translate(${-box.left}px, ${-box.top}px)`
        layer.current.style.width = `${window.screen.width}px`
        layer.current.style.height = `${window.screen.height}px`
        const isSmall = Math.min(box.width, box.height) < 60
        if (isSmall !== small && video.current) {
          small = isSmall
          // Dimmed a touch rather than brightened: a brighter copy of the
          // background is exactly what made the notch vanish into it.
          video.current.style.filter = isSmall ? recipe.small : recipe.large
        }
      }
      frame = requestAnimationFrame(follow)
    }
    follow()
    return () => cancelAnimationFrame(frame)
  }, [host, recipe])

  return (
    <div aria-hidden className="pointer-events-none absolute inset-0 -z-10 overflow-hidden" style={{ borderRadius: 'inherit' }}>
      <div ref={layer} className="absolute left-0 top-0 origin-top-left">
        <video
          ref={video}
          muted
          playsInline
          onPlaying={() => setLive(true)}
          className="absolute inset-0 h-full w-full object-fill transition-opacity duration-300"
          style={{ opacity: live ? 1 : 0 }}
        />
      </div>
      {/* A smoked tint, so the glass reads as a surface over anything and its
          text stays legible, darker toward the bottom where most text sits. */}
      <div className="absolute inset-0" style={{ background: recipe.tint }} />
      {/* A hairline catching the light on the sides and bottom, where the glass
          ends; none on top, which meets the screen's edge. */}
      <div
        className="absolute inset-0"
        style={{
          borderRadius: 'inherit',
          boxShadow: recipe.rim,
        }}
      />
      {recipe.top && <div className="absolute inset-x-0 top-0 h-3" style={{ background: 'linear-gradient(180deg, rgba(255,255,255,0.14), transparent)' }} />}
    </div>
  )
}
