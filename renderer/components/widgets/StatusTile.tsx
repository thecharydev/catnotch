import React from 'react'
import { AnimatePresence, motion } from 'motion/react'
import { Activity, BatteryCharging, BatteryFull, BatteryLow, BatteryMedium, Camera, Mic } from 'lucide-react'
import { Tile } from '../ui/tile'
import { CAMERA, LOW, LOW_LEVEL, MIC } from '../notch/CollapsedStatus'
import type { PrivacyState } from '../../hooks/usePrivacy'
import type { BatteryState } from '../../hooks/useBattery'
import { useUsage } from '../../hooks/useUsage'
import { ScrollingText } from '../notch/ScrollingText'

export const STATUS_WIDTH = 186

/** The card's two faces: what is happening, and how hard the machine is working. */
export type StatusPage = 'now' | 'usage'

const spring = { type: 'spring' as const, stiffness: 420, damping: 32 }

/** Charging accent green & quiet grey */
const CHARGING = '#10B981'
const PLAIN = '#CBD5E1'

/** Always show battery whenever supported on the machine (even at 100% full or charging). */
export const batteryShown = (battery: BatteryState) => battery.supported

/** The Status tile is active whenever the setting is enabled. */
export const statusShown = (_privacy: PrivacyState, _battery: BatteryState) => true

/** Check if there are active "Right now" items (Mic, Camera, or Battery). */
export const hasRightNowContent = (privacy: PrivacyState, battery: BatteryState) =>
  privacy.micApps.length > 0 || privacy.cameraApps.length > 0 || batteryShown(battery)

/** Row component for Right Now items with ScrollingText for overflowing app names */
const Row: React.FC<{ icon: React.ReactNode; color: string; name: string; note: string }> = ({ icon, color, name, note }) => (
  <motion.div
    layout
    initial={{ opacity: 0, scale: 0.95, y: 4 }}
    animate={{ opacity: 1, scale: 1, y: 0 }}
    exit={{ opacity: 0, scale: 0.9, x: 8 }}
    transition={spring}
    className="group flex h-[28px] min-w-0 items-center gap-2 rounded-[10px] px-2 py-1 bg-white/[0.04] hover:bg-white/[0.08] border border-white/[0.04] transition-all"
  >
    <span
      className="grid h-[22px] w-[22px] shrink-0 place-items-center transition-transform"
      style={{ color }}
    >
      {icon}
    </span>
    <ScrollingText className="min-w-0 flex-1 text-[12px] font-medium leading-none text-t1">
      {name}
    </ScrollingText>
    <span className="shrink-0 text-[9.5px] font-semibold tracking-wider uppercase text-t3">{note}</span>
  </motion.div>
)

/** The three readings, outermost ring first. Each takes a shade of the companion's colour. */
const READINGS = [
  { key: 'cpu', label: 'CPU', shade: 22 },
  { key: 'gpu', label: 'GPU', shade: 0 },
  { key: 'memory', label: 'Memory', shade: -16 },
] as const

/**
 * Derives lighter/darker shades of the companion's accent color (HSL based)
 */
const shade = (hex: string, delta: number) => {
  const safeHex = hex && hex.startsWith('#') && hex.length >= 7 ? hex : '#35B8FF'
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(safeHex.slice(i, i + 2), 16) / 255)
  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  const l = (max + min) / 2
  const d = max - min
  const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1))
  const h = d === 0 ? 0 : max === r ? ((g - b) / d + 6) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4
  return `hsl(${Math.round(h * 60)} ${Math.round(s * 100)}% ${Math.round(Math.min(100, Math.max(0, l * 100 + delta)))}%)`
}

const RINGS = 64
const STROKE = 5
const radius = (index: number) => RINGS / 2 - STROKE / 2 - index * (STROKE + 2.5)

const Ring: React.FC<{ r: number; share: number | null; color: string }> = ({ r, share, color }) => {
  const length = 2 * Math.PI * r
  return (
    <>
      <circle cx={RINGS / 2} cy={RINGS / 2} r={r} fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth={STROKE} />
      <motion.circle
        cx={RINGS / 2}
        cy={RINGS / 2}
        r={r}
        fill="none"
        stroke={color}
        strokeWidth={STROKE}
        strokeLinecap="round"
        strokeDasharray={length}
        initial={false}
        animate={{
          strokeDashoffset: length * (1 - Math.min(1, Math.max(0, share ?? 0))),
          opacity: share == null ? 0.3 : 1,
        }}
        transition={spring}
        style={{ filter: `drop-shadow(0 0 4px ${color}60)` }}
      />
    </>
  )
}

const percent = (share: number | null) => (share == null ? '—' : `${Math.round(share * 100)}%`)

/** Usage Page (CPU, GPU, Memory metrics, derived from Companion accent color) */
const UsagePage: React.FC<{ accent: string }> = ({ accent }) => {
  const usage = useUsage(true)
  const shares: Record<(typeof READINGS)[number]['key'], number | null> = {
    cpu: usage?.cpu ?? null,
    gpu: usage?.gpu == null ? null : usage.gpu / 100,
    memory: usage?.memory ?? null,
  }

  return (
    <div className="flex h-full items-center gap-2.5 px-0.5 pt-0.5">
      <div className="relative grid place-items-center shrink-0">
        <svg viewBox={`0 0 ${RINGS} ${RINGS}`} width={RINGS} height={RINGS} className="-rotate-90">
          {READINGS.map((reading, index) => (
            <Ring key={reading.key} r={radius(index)} share={shares[reading.key]} color={shade(accent, reading.shade)} />
          ))}
        </svg>
        <div className="absolute grid place-items-center text-center">
          <Activity size={12} className="text-t3 animate-pulse" />
        </div>
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-[6px]">
        {READINGS.map((reading) => (
          <div key={reading.key} className="flex items-center gap-1.5">
            <span
              className="h-[6px] w-[6px] shrink-0 rounded-full"
              style={{ background: shade(accent, reading.shade), boxShadow: `0 0 6px ${shade(accent, reading.shade)}` }}
            />
            <span className="min-w-0 flex-1 truncate text-[8.5px] font-bold uppercase leading-none tracking-[0.08em] text-t2">
              {reading.label}
            </span>
            <span
              className="shrink-0 text-[10.5px] font-bold tabular-nums leading-none"
              style={{ color: shares[reading.key] == null ? 'rgba(255,255,255,0.3)' : shade(accent, reading.shade) }}
            >
              {percent(shares[reading.key])}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}

/** Right Now Page (Mic, Camera, Battery status) */
const NowPage: React.FC<{ privacy: PrivacyState; battery: BatteryState }> = ({ privacy, battery }) => {
  const low = !battery.charging && battery.level <= LOW_LEVEL
  const BatteryIcon = battery.charging ? BatteryCharging : low ? BatteryLow : battery.level < 0.6 ? BatteryMedium : BatteryFull

  return (
    <div className="flex flex-col gap-1.5 pt-0.5">
      <AnimatePresence initial={false}>
        {privacy.micApps.length > 0 && (
          <Row key="mic" icon={<Mic size={15} strokeWidth={2.2} />} color={MIC} name={privacy.micApps.join(', ')} note="Mic" />
        )}
        {privacy.cameraApps.length > 0 && (
          <Row key="camera" icon={<Camera size={15} strokeWidth={2.2} />} color={CAMERA} name={privacy.cameraApps.join(', ')} note="Camera" />
        )}
        {batteryShown(battery) && (
          <Row
            key="battery"
            icon={<BatteryIcon size={15} strokeWidth={2.2} />}
            color={battery.charging ? CHARGING : low ? LOW : PLAIN}
            name={`${Math.round(battery.level * 100)}%`}
            note={battery.charging ? 'Charging' : low ? 'Low' : 'Battery'}
          />
        )}
      </AnimatePresence>
    </div>
  )
}

/**
 * Premium StatusTile Component
 */
export const StatusTile: React.FC<{
  privacy: PrivacyState
  battery: BatteryState
  accent: string
  page: StatusPage
  onPage: (page: StatusPage) => void
}> = ({ privacy, battery, accent, page, onPage }) => {
  const hasNowContent = hasRightNowContent(privacy, battery)
  // Fallback to Usage if no active Right Now items exist
  const activeFace = hasNowContent ? page : 'usage'
  const dir = activeFace === 'usage' ? 1 : -1

  return (
    <Tile width={STATUS_WIDTH}>
      <div className="flex h-full flex-col justify-between">
        {/* Sleek Segmented Header Bar */}
        <div className="flex items-center justify-between gap-1 pb-1">
          {hasNowContent ? (
            <div className="relative flex items-center gap-0.5 rounded-full bg-white/[0.06] p-0.5 border border-white/[0.06]">
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onPage('now')
                }}
                className={`relative z-10 rounded-full px-2 py-0.5 text-[9px] font-bold uppercase tracking-wider transition-colors ${activeFace === 'now' ? 'text-white' : 'text-t3 hover:text-t1'
                  }`}
              >
                {activeFace === 'now' && (
                  <motion.div
                    layoutId="status-tab"
                    className="absolute inset-0 z-[-1] rounded-full bg-white/15 shadow-sm"
                    transition={spring}
                  />
                )}
                Active
              </button>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onPage('usage')
                }}
                className={`relative z-10 rounded-full px-2 py-0.5 text-[9px] font-bold uppercase tracking-wider transition-colors ${activeFace === 'usage' ? 'text-white' : 'text-t3 hover:text-t1'
                  }`}
              >
                {activeFace === 'usage' && (
                  <motion.div
                    layoutId="status-tab"
                    className="absolute inset-0 z-[-1] rounded-full bg-white/15 shadow-sm"
                    transition={spring}
                  />
                )}
                Usage
              </button>
            </div>
          ) : (
            <div className="flex items-center gap-1.5 px-0.5">
              <span className="relative flex h-2 w-2">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-sky-400 opacity-75" />
                <span className="relative inline-flex rounded-full h-2 w-2 bg-sky-500" />
              </span>
              <span className="text-[9px] font-bold uppercase tracking-[0.14em] text-t2">System Usage</span>
            </div>
          )}
        </div>

        {/* Content Area */}
        <div className="min-h-0 flex-1 overflow-hidden pt-0.5">
          <AnimatePresence mode="wait" initial={false}>
            <motion.div
              key={activeFace}
              className="h-full"
              initial={{ opacity: 0, x: 14 * dir }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -14 * dir }}
              transition={{ duration: 0.16 }}
            >
              {activeFace === 'now' ? <NowPage privacy={privacy} battery={battery} /> : <UsagePage accent={accent} />}
            </motion.div>
          </AnimatePresence>
        </div>
      </div>
    </Tile>
  )
}
