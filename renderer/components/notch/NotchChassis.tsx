import React, { useEffect, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'motion/react'
import { Lock, LockOpen, Power } from 'lucide-react'
import { useHardwareNotch } from '../../hooks/useHardwareNotch'
import { DockSideContext, RailButton, railLabel, type DockSide } from './ViewSwitcher'

/** The top bar: the notch itself when closed. Open, the controls live on the
 *  rail beside the notch, so the bar shrinks to a sliver of top margin. */
export const BAR_CLOSED = 30
export const BAR_OPEN = 6
/** Closed and tucked behind a browser: a sliver at the screen's edge, still easy to hover. */
const BAR_TUCKED = 6
/** The open notch's padding around its content: tight and even on every side
 *  (the sliver of bar plus PAD_TOP makes the top match). Views size themselves
 *  as content + CHROME_X / CHROME_Y. */
export const PAD = 12
const PAD_TOP = PAD - BAR_OPEN
export const CHROME_X = PAD * 2
export const CHROME_Y = BAR_OPEN + PAD_TOP + PAD

/** On a notched display, how far the closed notch grows past each side of the
 *  cutout while it has something to say (an icon left, a time or dot right). */
export const WING = 64
/** Closed on a cutout the shape is this much bigger on each side and below, so no
 *  hairline of the real notch's edge shows around it. Pure black to match it too. */
const CUTOUT_BLEED = 2
/** How far past its edge the pointer may drift before the notch lets go. */
const LEAVE_MARGIN = 48
/** Past the margin but not moving (a quick flick away, then stillness): how
 *  long before the notch lets go anyway. */
const AWAY_STILL_MS = 700
/** After the notch changes size, how long the pointer's distance is not trusted. */
const SETTLE_MS = 900

/** The notch's spring: a soft, slightly bouncy open like Boring Notch's, and a
 *  critically damped close, so it settles without ever overshooting its edge. */
const spring = { type: 'spring' as const, stiffness: 224, damping: 24 }
const closeSpring = { type: 'spring' as const, stiffness: 195, damping: 28 }

/**
 * Motion animates numbers, not custom properties, so the notch radius cannot
 * be a class the way the cards' is. Reading the token at runtime keeps
 * globals.css the single place these values are defined.
 */
const radiusToken = (name: string, fallback: number) => {
  if (typeof window === 'undefined') return fallback
  const raw = getComputedStyle(document.documentElement).getPropertyValue(name)
  const parsed = Number.parseFloat(raw)
  return Number.isFinite(parsed) ? parsed : fallback
}

import type { NotchStyle } from '../widgets/SettingsPanel'
import { Backdrop } from './Backdrop'

interface NotchChassisProps {
  /** The collapsed bar's content. A function gets the open state, for content
   *  that should step aside once the notch opens. */
  children?: React.ReactNode | ((isOpen: boolean, cutout?: number) => React.ReactNode)
  /** Closed on a notched display: how far to grow a wing out of each side of the cutout. */
  wings?: number
  /** Rendered only while expanded, below the collapsed bar. */
  expandedContent?: React.ReactNode
  /** Must stay under STRIP_HEIGHT in main.ts, or the window clips it. */
  expandedWidth?: number
  expandedHeight?: number
  /** Rendered behind everything, inside the shell's rounded clip. Receives the
   *  open state so it can stay out of the way while collapsed. */
  ambient?: (isOpen: boolean) => React.ReactNode
  /** The dock's circles, views and controls, floating under the notch while
   *  it is open. The lock is added at its end. */
  rail?: React.ReactNode
  /** Where the dock sits. */
  dockSide?: DockSide
  /** A bar floating under the notch while open (the apps), below the dock if that is under it too. */
  below?: React.ReactNode
  /** Where that bar sits: under the notch, or hanging beside it. */
  belowSide?: 'left' | 'right' | 'bottom'
  /** Holds the notch open regardless of hover — for a running timer, say. */
  keepOpen?: boolean
  /** Show the lock as locked without pinning (pinning would take focus). */
  lockShown?: boolean
  /** Told whenever the notch opens or closes. */
  onOpenChange?: (open: boolean) => void
  /** Bumped to fold the notch away now, even under the pointer. */
  closeKey?: number
  /** A browser is in front: closed, the notch shrinks to a sliver out of its tabs' way. */
  tucked?: boolean
  /** How big the dock's buttons and icons are, 1 = default. Its labels keep their size. */
  dockScale?: number
  className?: string
  /** Material / theme appearance of the notch shell. */
  notchStyle?: NotchStyle
}

/** The little inverted corners where the notch meets the screen's edge, and
 *  the dock and apps tray: the surface's own colour, solid. */
const CORNER_FILLS: Record<NotchStyle, string> = {
  black: '#000000',
  transparent: 'transparent',
  glass: 'transparent',
}

/** How far the curves at the notch's top corners reach out along the screen's edge. */
const EAR = 8

/**
 * One of the two small curves where the notch meets the top of the screen,
 * flaring outward so the notch reads as part of the edge, like a MacBook's.
 * It shows the notch's own surface: the Default colour, or the same Glass
 * backdrop, lined up with it.
 */
const Ear: React.FC<{ side: 'left' | 'right'; notchStyle: NotchStyle }> = ({ side, notchStyle }) => {
  const ref = useRef<HTMLDivElement>(null)
  return (
    <div
      ref={ref}
      aria-hidden
      className="pointer-events-none absolute top-0 isolate"
      style={{
        width: EAR,
        height: EAR,
        [side]: -EAR,
        background: notchStyle === 'black' ? CORNER_FILLS.black : CORNER_FILLS[notchStyle],
        // Everything but a quarter circle at the corner away from the notch:
        // a concave curve from the screen's edge down into the notch's side.
        maskImage: `radial-gradient(circle at ${side === 'left' ? '0' : '100%'} 100%, transparent ${EAR}px, black ${EAR + 0.5}px)`,
      }}
    >
      {notchStyle !== 'black' && <Backdrop kind={notchStyle} host={ref} ear={side} />}
    </div>
  )
}

/** Closes deskNotch until it is opened again from the Start menu. */
const QuitButton: React.FC = () => (
  <RailButton label="Close DeskNotch" onClick={() => window.bridge?.send('app:quit')}>
    <Power size={11} strokeWidth={2.2} />
  </RailButton>
)

/**
 * The notch itself, drawn inside the full-width invisible strip window.
 *
 * Geometry lives here rather than in the BrowserWindow, so sizes and motion
 * hot-reload. The only hard limit is STRIP_HEIGHT in main.ts: the expanded
 * height must stay under it or the window clips the element.
 */
export const NotchChassis: React.FC<NotchChassisProps> = ({
  children,
  wings = 0,
  expandedContent,
  expandedWidth = 340,
  expandedHeight = 132,
  ambient,
  rail,
  dockSide = 'bottom',
  below,
  belowSide = 'bottom',
  keepOpen = false,
  lockShown = false,
  onOpenChange,
  closeKey = 0,
  tucked = false,
  dockScale = 1,
  className = '',
  notchStyle: chosenStyle = 'black',
}) => {
  const hardware = useHardwareNotch()
  const [isHovered, setIsHovered] = useState(false)


  const [isPinned, setIsPinned] = useState(false)

  const isOpen = isHovered || isPinned || keepOpen
  // The lock reads as locked while Settings holds the notch open too.
  const locked = isPinned || lockShown
  // The cutout is black, so closed on one with nothing beside it the notch is
  // too, whatever is chosen. With wings, the wings show the style and a black
  // block covers the cutout itself.
  const notchStyle: NotchStyle = hardware && !isOpen && wings === 0 ? 'black' : chosenStyle
  // A cutout is already there to hide behind: nothing to tuck.
  const sliver = tucked && !isOpen && !hardware
  // Open on a cutout the content starts below it, and the shape has a neck.
  const topBar = hardware ? hardware.h : BAR_OPEN
  const shellHeight = expandedHeight + topBar - BAR_OPEN
  const necked = Boolean(hardware) && isOpen
  // Locked open, the dock and apps bar step away until the pointer is back on
  // the notch, so a pinned notch is just its content. Hovering brings them
  // back, and with them the lock to unpin.
  const showChrome = isOpen && (!isPinned || isHovered)
  useEffect(() => onOpenChange?.(isOpen), [isOpen])

  // Resolved after mount so server-rendered markup and the client agree.
  const [radius, setRadius] = useState({ closed: 11, open: 26 })
  useEffect(() => {
    setRadius({
      closed: radiusToken('--radius-notch-closed', 11),
      open: radiusToken('--radius-notch-open', 26),
    })
  }, [])


  const setHover = (over: boolean) => {
    console.log('[dbg] setHover', over, new Error().stack?.split('\n')[2]?.trim())
    setIsHovered(over)
  }

  /** Everything that belongs to the notch: itself, the dock, the apps tray, and
   *  any popover marked `data-notch-part` (the favourites picker). */
  const parts = () =>
    [
      shellRef.current,
      railBottomRef.current,
      railLeftRef.current,
      railRightRef.current,
      belowBottomRef.current,
      belowLeftRef.current,
      belowRightRef.current,
      ...Array.from(document.querySelectorAll<HTMLElement>('[data-notch-part]')),
    ].filter((el): el is HTMLElement => Boolean(el))
  const distance = (x: number, y: number) =>
    Math.min(
      ...parts()
        .map((el) => {
          const r = el.getBoundingClientRect()
          return Math.hypot(Math.max(r.left - x, 0, x - r.right), Math.max(r.top - y, 0, y - r.bottom))
        }),
    )
  // Asked to fold away: let go of the hover. The pointer has to leave and
  // come back to open it again, so it does not spring straight back open.
  useEffect(() => {
    if (!closeKey) return
    setHover(false)
  }, [closeKey])

  // Leaving is judged from the real pointer, not from the DOM's mouseleave.
  // The window turns click-through the moment the pointer is off the notch,
  // and a quick exit could beat the mouseleave: it never came, and the notch
  // stayed open. So while hovered, the pointer's position from the main
  // process (sent whenever it moves) decides, by intent rather than the edge:
  // - within LEAVE_MARGIN of the notch, the dock or the tray: stay;
  // - past it and still heading away: close;
  // - past it and then still (a flick away): close after AWAY_STILL_MS;
  // - heading back: stay. The notch also changes size under a still pointer
  //   (a smaller view), which is why the edge alone never closes it.
  // A smaller view moves the dock away from a pointer that has not moved:
  // not the pointer leaving. Size changes are given a beat to settle.
  const resizedAt = useRef(0)
  useEffect(() => {
    resizedAt.current = Date.now()
  }, [expandedWidth, expandedHeight])

  useEffect(() => {
    if (!isHovered) return
    let last = 0
    let away: ReturnType<typeof setTimeout> | undefined
    const close = () => setHover(false)
    const unsubscribe = window.bridge?.on<{ x: number; y: number }>('notch:cursor', ({ x, y }) => {
      const d = distance(x, y)
      console.log('[dbg] cursor d=', Math.round(d), 'last=', Math.round(last), 'away=', Boolean(away), 'sinceResize=', Date.now() - resizedAt.current)
      if (d <= LEAVE_MARGIN || Date.now() - resizedAt.current < SETTLE_MS) {
        clearTimeout(away)
        away = undefined
      } else if (away && d > last) {
        // Out past the margin before, and further now: going.
        close()
      } else if (!away) {
        away = setTimeout(close, AWAY_STILL_MS)
      } else if (d < last) {
        // Coming back: give it a fresh beat.
        clearTimeout(away)
        away = setTimeout(close, AWAY_STILL_MS)
      }
      last = d
    })
    return () => {
      unsubscribe?.()
      clearTimeout(away)
    }
  }, [isHovered])

  const onEnter = () => setHover(true)

  // The window is a full-width strip, so the main process cannot simply stop
  // ignoring mouse events — that would hand the whole strip clicks meant for
  // whatever is underneath. It gets the notch's rectangle instead and tests
  // the cursor against it.
  const shellRef = useRef<HTMLDivElement>(null)
  const railBottomRef = useRef<HTMLDivElement>(null)
  const railLeftRef = useRef<HTMLDivElement>(null)
  const railRightRef = useRef<HTMLDivElement>(null)
  const belowBottomRef = useRef<HTMLDivElement>(null)
  const belowLeftRef = useRef<HTMLDivElement>(null)
  const belowRightRef = useRef<HTMLDivElement>(null)
  const mainRef = useRef<HTMLElement>(null)

  useEffect(() => {
    const report = () => {
      const element = shellRef.current
      if (!element) return

      // The notch, and the dock under it when it is out.
      const rects = parts().flatMap((el) => {
        const r = el.getBoundingClientRect()
        return [{ x: r.left, y: r.top, width: r.width, height: r.height }]
      })
      window.bridge?.send('notch:bounds', rects)
    }

    report()

    // The shell springs between sizes, so its bounds are only final once the
    // animation settles; an observer catches every frame of that.
    const observer = new ResizeObserver(report)
    if (shellRef.current) observer.observe(shellRef.current)
    // The dock mounts and springs in a beat after opening; catch it once settled.
    const late = setTimeout(report, 500)
    // Popovers open and close without resizing anything; a slow re-check while
    // open keeps them clickable.
    const tick = isOpen ? setInterval(report, 250) : undefined

    return () => {
      observer.disconnect()
      clearTimeout(late)
      clearInterval(tick)
    }
  }, [isOpen, expandedWidth, expandedHeight, dockSide, belowSide, hardware, wings])

  useEffect(() => {
    window.bridge?.send('notch:pinned', isPinned)
  }, [isPinned])

  /** The apps tray, in the notch's own surface so the two read as one object:
   *  a short row under the notch, or a column hanging beside it. */
  const tray = (side: 'left' | 'right' | 'bottom') => {
    const ref = side === 'left' ? belowLeftRef : side === 'right' ? belowRightRef : belowBottomRef;
    return (
      <motion.div
        key={`tray-${side}`}
        ref={ref}
        initial={{ opacity: 0, scale: 0.94, ...(side === 'bottom' ? { y: -10 } : { x: side === 'right' ? -10 : 10 }) }}
        animate={{ opacity: 1, scale: 1, x: 0, y: 0 }}
        exit={{ opacity: 0, scale: 0.96, transition: { duration: 0.12 } }}
        transition={{ ...spring, delay: 0.06 }}
        className={`pointer-events-auto relative isolate border ${side === 'bottom' ? 'rounded-[12px] px-3 py-1' : 'rounded-b-[12px] border-t-0 px-1 pb-1.5 pt-2'} ${
          notchStyle === 'black' ? 'bg-[#000000] border-white/[0.07]' : 'border-white/[0.1]'
        }`}
        style={notchStyle === 'black' ? undefined : { background: CORNER_FILLS[notchStyle] }}
      >
        {notchStyle !== 'black' && <Backdrop kind={notchStyle} host={ref} />}
        {below}
      </motion.div>
    )
  }

  return (
    <motion.div
      ref={shellRef}
      onMouseEnter={onEnter}
      // A drag opens it like a hover, without locking it. Leaving is left to the
      // pointer watch below, which follows a drag too: dragleave fires on every
      // child the drag crosses, so closing on it made the notch flicker.
      onDragEnter={onEnter}
      initial={false}
      animate={{
        width: isOpen ? expandedWidth : hardware ? hardware.w + 2 * wings + CUTOUT_BLEED * 2 : 240,
        height: isOpen ? shellHeight : sliver ? BAR_TUCKED : hardware ? hardware.h + CUTOUT_BLEED : BAR_CLOSED,
      }}
      transition={isOpen ? spring : closeSpring}
      // The dock reads these: its buttons and icons grow, its label text does not.
      style={{ willChange: 'width, height', '--dock-btn': `${24 * dockScale}px`, '--dock-icon': dockScale } as React.CSSProperties}
      className={`relative select-none cursor-default ${className}`}
    >


      {!sliver && !necked && <Ear side="left" notchStyle={notchStyle} />}
      {!sliver && !necked && <Ear side="right" notchStyle={notchStyle} />}

      <motion.main
        ref={mainRef}
        data-notch-style={notchStyle}
        initial={false}
        animate={{
          borderBottomLeftRadius: isOpen ? radius.open : radius.closed,
          borderBottomRightRadius: isOpen ? radius.open : radius.closed,
        }}
        transition={isOpen ? spring : closeSpring}
        className={`relative isolate w-full h-full text-white overflow-hidden flex flex-col
                   transition-colors duration-300 ${notchStyle === 'black' ? 'bg-[#000000]' : ''}`}
        style={{
          borderTopLeftRadius: 0,
          borderTopRightRadius: 0,
          willChange: 'border-radius',
          ...(notchStyle === 'black' ? {} : { background: CORNER_FILLS[notchStyle] }),
        }}
      >
        {/* Glass: what the surface shows through, open or closed. */}
        {notchStyle !== 'black' && <Backdrop kind={notchStyle} host={mainRef} />}
        {hardware && notchStyle !== 'black' && (
          <div
            aria-hidden
            className="pointer-events-none absolute left-1/2 top-0 -translate-x-1/2 bg-black"
            // The real notch's bottom corners are curved: a square block would poke out of them.
            style={{
              width: hardware.w + 2 * CUTOUT_BLEED,
              height: hardware.h,
              borderBottomLeftRadius: radius.closed,
              borderBottomRightRadius: radius.closed,
            }}
          />
        )}

        {ambient?.(isOpen)}

        {/* The bar is the notch when closed, and a toolbar when open: it grows
            so the tabs and buttons in it get air rather than filling it. */}
        <motion.div
          // No click-to-lock here: clicking the bar locked the notch open by
          // surprise. Locking is only the lock button on the dock.
          initial={false}
          animate={{ height: isOpen ? topBar : hardware?.h ?? BAR_CLOSED }}
          transition={isOpen ? spring : closeSpring}
          className={`shrink-0 flex items-center justify-between relative ${hardware ? 'px-2' : 'px-5'}`}
        >
          <div className="flex min-w-0 flex-1 items-center gap-2">
            {!sliver && (typeof children === 'function' ? children(isOpen, hardware?.w) : children)}
          </div>
        </motion.div>

        <AnimatePresence>
          {isOpen && expandedContent && (
            <motion.div
              // No blur: a filter repaints the whole content every frame and stuttered.
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              transition={{ ...spring, opacity: { duration: 0.15 } }}
              // Laid out once at the open size, centred, and only uncovered as
              // the shell springs around it. Sized by the shell instead, it was
              // laid out and repainted on every frame of the spring.
              className="absolute"
              style={{
                top: topBar,
                left: '50%',
                marginLeft: -expandedWidth / 2,
                width: expandedWidth,
                height: expandedHeight - BAR_OPEN,
                padding: `${PAD_TOP}px ${PAD}px ${PAD}px`,
                willChange: 'opacity, transform',
              }}
            >
              {expandedContent}
            </motion.div>
          )}
        </AnimatePresence>
      </motion.main>

      {/* Around the notch while it is open: the dock of tabs and the apps tray.
          Under the notch they stack in one column (tray first, against the
          notch); beside it they hang from the screen's edge, the dock nearest
          the notch and the tray just outside it. The notch grows about its
          centre, so nothing under it slides sideways between views. */}
      <DockSideContext.Provider value={dockSide}>
        <div className="pointer-events-none absolute inset-x-0 top-full flex flex-col items-center gap-1.5 pt-1">
          <AnimatePresence>{showChrome && below && belowSide === 'bottom' && tray('bottom')}</AnimatePresence>
          <AnimatePresence>
            {showChrome && rail && dockSide === 'bottom' && (
              <motion.div
                  key="rail-bottom"
                  ref={railBottomRef}
                  initial={{ opacity: 0, scale: 0.92, y: -10 }}
                  animate={{ opacity: 1, scale: 1, x: 0, y: 0 }}
                  exit={{ opacity: 0, scale: 0.94, transition: { duration: 0.12 } }}
                  transition={{ ...spring, delay: 0.04 }}
                  style={{
                    transformOrigin: 'top center',
                    ...(notchStyle === 'black' ? {} : { background: CORNER_FILLS[notchStyle] }),
                  }}
                  className={`pointer-events-auto relative isolate flex items-center gap-[3px] border h-[calc(var(--dock-btn,24px)_+_8px)] rounded-full px-1 ${
                    notchStyle === 'black' ? 'bg-[#000000] border-white/[0.08]' : 'border-white/[0.1]'
                  }`}
                >
                  {notchStyle !== 'black' && <Backdrop kind={notchStyle} host={railBottomRef} />}
                  <DockSideContext.Provider value="bottom">
                    {rail}
                  </DockSideContext.Provider>
                  <div className="mx-0.5 h-3.5 w-px bg-white/[0.1]" />
                  {/* The lock: pinning is something you can see and do. */}
                  <motion.button
                    type="button"
                    aria-label={locked ? 'Unpin' : 'Pin open'}
                    aria-pressed={locked}
                    whileTap={{ scale: 0.88 }}
                    transition={spring}
                    onClick={(event) => {
                      event.stopPropagation()
                      setIsPinned((pinned) => !pinned)
                    }}
                    className={`group/rail relative grid h-[var(--dock-btn,24px)] w-[var(--dock-btn,24px)] shrink-0 place-items-center rounded-full outline-none transition-colors duration-200 ${
                      locked ? 'bg-white text-black' : 'text-white/45 hover:bg-white/[0.1] hover:text-white'
                    }`}
                  >
                    <span className="[transform:scale(var(--dock-icon,1))]">{locked ? <Lock size={11} strokeWidth={2.2} /> : <LockOpen size={11} strokeWidth={2} />}</span>
                    <span className={railLabel('bottom')}>{locked ? 'Unlock' : 'Keep open'}</span>
                  </motion.button>
                  <QuitButton />
                </motion.div>
            )}
          </AnimatePresence>
        </div>
        {(['left', 'right'] as const).map((side) => (
          <div
            key={side}
            className={`pointer-events-none absolute top-0 flex items-start gap-1.5 ${side === 'right' ? 'left-full pl-1.5' : 'right-full flex-row-reverse pr-1.5'}`}
          >
            <AnimatePresence>
              {showChrome && rail && dockSide === side && (
                <motion.div
                key={`rail-${side}`}
                ref={side === 'left' ? railLeftRef : railRightRef}
                initial={{ opacity: 0, scale: 0.92, x: side === 'right' ? -10 : 10 }}
                animate={{ opacity: 1, scale: 1, x: 0, y: 0 }}
                exit={{ opacity: 0, scale: 0.94, transition: { duration: 0.12 } }}
                transition={{ ...spring, delay: 0.04 }}
                style={{
                  transformOrigin: side === 'right' ? 'top left' : 'top right',
                  ...(notchStyle === 'black' ? {} : { background: CORNER_FILLS[notchStyle] }),
                }}
                className={`pointer-events-auto relative isolate flex flex-col items-center gap-[3px] border w-[calc(var(--dock-btn,24px)_+_8px)] rounded-b-[16px] border-t-0 px-1 pb-1 pt-1.5 ${
                  notchStyle === 'black' ? 'bg-[#000000] border-white/[0.08]' : 'border-white/[0.1]'
                }`}
              >
                {notchStyle !== 'black' && <Backdrop kind={notchStyle} host={side === 'left' ? railLeftRef : railRightRef} />}
                <DockSideContext.Provider value={side}>
                  {rail}
                </DockSideContext.Provider>
                <div className="my-0.5 h-px w-3.5 bg-white/[0.1]" />
                {/* The lock: pinning is something you can see and do. */}
                <motion.button
                  type="button"
                  aria-label={locked ? 'Unpin' : 'Pin open'}
                  aria-pressed={locked}
                  whileTap={{ scale: 0.88 }}
                  transition={spring}
                  onClick={(event) => {
                    event.stopPropagation()
                    setIsPinned((pinned) => !pinned)
                  }}
                  className={`group/rail relative grid h-[var(--dock-btn,24px)] w-[var(--dock-btn,24px)] shrink-0 place-items-center rounded-full outline-none transition-colors duration-200 ${
                    locked ? 'bg-white text-black' : 'text-white/45 hover:bg-white/[0.1] hover:text-white'
                  }`}
                >
                  <span className="[transform:scale(var(--dock-icon,1))]">{locked ? <Lock size={11} strokeWidth={2.2} /> : <LockOpen size={11} strokeWidth={2} />}</span>
                  <span className={railLabel(side)}>{locked ? 'Unlock' : 'Keep open'}</span>
                </motion.button>
                <QuitButton />
              </motion.div>
              )}
            </AnimatePresence>
            <AnimatePresence>{showChrome && below && belowSide === side && tray(side)}</AnimatePresence>
          </div>
        ))}
      </DockSideContext.Provider>
    </motion.div>
  )
}
