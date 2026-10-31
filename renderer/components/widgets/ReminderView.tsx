import React from 'react'
import { motion } from 'motion/react'
import { BotAvatar } from 'bot-avatars'
import { CatppuccinCat } from './CatppuccinCat'
import type { Flavor } from '../../lib/catppuccin'
import { BellRing } from 'lucide-react'
import { CALM } from './CompanionTile'
import { whenLabel, type Reminder } from '../../hooks/useReminders'
import type { Avatar } from './SettingsPanel'

export const REMINDER_WIDTH = 392
export const REMINDER_HEIGHT = 112

const spring = { type: 'spring' as const, stiffness: 420, damping: 22 }

/**
 * A reminder's time has come: the notch opens on this alone. The companion
 * rings like an alarm clock (ripples going out from it, a bell swinging on
 * its shoulder) while the message is said plainly beside it. Snooze brings
 * it back in five minutes; Got it lets it go.
 */
export const ReminderView: React.FC<{
  reminder: Reminder
  avatar: Avatar
  flavor: Flavor
  photo: string | null
  accent: string
  /** The companion's motion switches. */
  look: boolean
  react: boolean
  onSnooze: () => void
  onDismiss: () => void
}> = ({ reminder, avatar, flavor, photo, accent, look, react, onSnooze, onDismiss }) => (
  <div className="flex h-full items-center justify-center gap-4" onClick={(event) => event.stopPropagation()}>
    {/* The companion, ringing. */}
    <div className="relative grid h-[84px] w-[84px] shrink-0 place-items-center">
      {[0, 1, 2].map((i) => (
        <motion.span
          key={i}
          aria-hidden
          className="absolute inset-[14px] rounded-full border-2"
          style={{ borderColor: accent }}
          initial={{ scale: 0.7, opacity: 0 }}
          animate={{ scale: [0.7, 1.45], opacity: [0.55, 0] }}
          transition={{ duration: 1.8, repeat: Infinity, delay: i * 0.6, ease: 'easeOut' }}
        />
      ))}
      <motion.div
        className="relative"
        initial={{ y: 14, scale: 0.6, opacity: 0 }}
        animate={{ y: 0, scale: 1, opacity: 1, rotate: [0, -7, 7, -5, 5, 0] }}
        transition={{ ...spring, rotate: { duration: 0.7, repeat: Infinity, repeatDelay: 1.1 } }}
      >
        {avatar === 'photo' ? (
          photo && <img src={photo} alt="" className="h-[52px] w-[52px] rounded-full object-cover" />
        ) : (
          avatar === 'catppuccin' ? <CatppuccinCat size={56} coat={accent} flavor={flavor} state={react ? 'working' : 'default'} interactive={look} {...CALM} turn={look ? CALM.turn : 0} /> : <BotAvatar type={avatar} size={56} theme="dark" state={react ? 'working' : 'default'} interactive={look} {...CALM} turn={look ? CALM.turn : 0} />
        )}
      </motion.div>
      {/* The bell, swinging from its top like a real one. */}
      <motion.span
        aria-hidden
        className="absolute right-1 top-1 grid h-[24px] w-[24px] place-items-center rounded-full text-black shadow-[0_4px_10px_-4px_rgba(0,0,0,0.8)]"
        style={{ background: accent, originY: 0 }}
        animate={{ rotate: [0, 18, -16, 12, -8, 0] }}
        transition={{ duration: 0.8, repeat: Infinity, repeatDelay: 1 }}
      >
        <BellRing size={13} strokeWidth={2.4} />
      </motion.span>
    </div>

    {/* What it is about, then the two ways out. */}
    <motion.div
      className="flex min-w-0 max-w-[250px] flex-col"
      initial={{ opacity: 0, x: -6 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ delay: 0.15, duration: 0.22 }}
    >
      <span className="text-[10px] font-bold uppercase tracking-[0.12em]" style={{ color: accent }}>
        Reminder · {whenLabel(reminder.at)}
      </span>
      <p className="mt-1 line-clamp-2 break-words text-[15px] font-semibold leading-snug text-white" title={reminder.message || undefined}>
        {reminder.message || "It's time"}
      </p>
      <div className="mt-2.5 flex gap-1.5">
        <motion.button
          type="button"
          whileTap={{ scale: 0.94 }}
          onClick={onDismiss}
          className="h-[26px] shrink-0 whitespace-nowrap rounded-full px-4 text-[11px] font-semibold text-black"
          style={{ background: accent }}
        >
          Got it
        </motion.button>
        <motion.button
          type="button"
          whileTap={{ scale: 0.94 }}
          onClick={onSnooze}
          className="h-[26px] shrink-0 whitespace-nowrap rounded-full bg-white/[0.08] px-4 text-[11px] font-medium text-white/70 transition-colors hover:bg-white/[0.14] hover:text-white"
        >
          Snooze 5 min
        </motion.button>
      </div>
    </motion.div>
  </div>
)
