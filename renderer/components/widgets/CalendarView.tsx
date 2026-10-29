import React from 'react'
import { motion } from 'motion/react'
import { Video } from 'lucide-react'
import { dayStart, type CalendarAccess, type CalendarEvent } from '../../hooks/useCalendar'

export const CALENDAR_WIDTH = 580
export const CALENDAR_HEIGHT = 200

const open = (channel: string, id?: string) => void window.bridge?.invoke(channel, id)
const clock = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' })

/** "All day" for an event that fills the day (or the day is inside a longer one), else "start to end". */
const timeText = (event: CalendarEvent, day: Date) => {
  const start = new Date(event.start)
  const end = new Date(event.end)
  if (event.allDay || (start <= day && end >= dayStart(day, 1))) return 'All day'
  return `${clock.format(start)} to ${clock.format(end)}`
}

const quiet = 'rounded-full bg-white/[0.12] px-3 py-1 text-[11px] font-semibold text-white hover:bg-white/[0.2]'

const Message: React.FC<{ text: string; note?: string; action?: string; onAction?: () => void; accent: string }> = ({ text, note, action, onAction, accent }) => (
  <div className="flex h-full flex-col items-center justify-center gap-2 px-6 text-center" onClick={(event) => event.stopPropagation()}>
    <p className="text-[13px] font-semibold text-white">{text}</p>
    {note && <p className="text-[11px] leading-snug text-white/50">{note}</p>}
    {action && (
      <motion.button whileTap={{ scale: 0.94 }} type="button" className="rounded-full px-3 py-1 text-[11px] font-semibold text-black" style={{ background: accent }} onClick={onAction}>
        {action}
      </motion.button>
    )}
  </div>
)

/** The month as a small grid, today ringed in the accent. */
const Month: React.FC<{ now: Date; accent: string }> = ({ now, accent }) => {
  const first = new Date(now.getFullYear(), now.getMonth(), 1)
  const days = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
  const cells = [...Array(first.getDay()).fill(0), ...Array.from({ length: days }, (_, i) => i + 1)]
  return (
    <div className="flex w-[190px] shrink-0 flex-col px-2 py-1" onClick={(event) => event.stopPropagation()}>
      <h3 className="mb-1 text-[12px] font-semibold text-white">
        {now.toLocaleDateString(undefined, { month: 'long' })} <span className="text-white/50">{now.getFullYear()}</span>
      </h3>
      <div className="grid grid-cols-7 gap-y-0.5 text-center text-[10px]">
        {['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d, i) => (
          <span key={i} className="font-semibold text-white/40">{d}</span>
        ))}
        {cells.map((d, i) => (
          <span
            key={i}
            className={`mx-auto grid h-[22px] w-[22px] place-items-center rounded-full ${d === now.getDate() ? 'font-bold text-black' : 'text-white/80'}`}
            style={d === now.getDate() ? { background: accent } : undefined}
          >
            {d || ''}
          </span>
        ))}
      </div>
    </div>
  )
}

/** Today and tomorrow from the Mac's calendars: a dot, the title, the time, and Join when there is a call. */
export const CalendarView: React.FC<{
  access: CalendarAccess
  events: CalendarEvent[]
  now: Date
  accent: string
  onAllow: () => void
}> = ({ access, events, now, accent, onAllow }) => (
  <div className="flex h-full">
    <Month now={now} accent={accent} />
    <div className="min-w-0 flex-1 border-l border-white/10">
      <Events access={access} events={events} now={now} accent={accent} onAllow={onAllow} />
    </div>
  </div>
)

const Events: React.FC<{
  access: CalendarAccess
  events: CalendarEvent[]
  now: Date
  accent: string
  onAllow: () => void
}> = ({ access, events, now, accent, onAllow }) => {
  if (access === 'unavailable') return <Message accent={accent} text="Calendar unavailable" />
  if (access === 'unknown')
    return (
      <Message
        accent={accent}
        text="Show your calendar here"
        note="DeskNotch reads the events in your Mac's Calendar app to show what is next. It stays on your Mac and never changes anything."
        action="Allow"
        onAction={onAllow}
      />
    )
  if (access === 'denied')
    return <Message accent={accent} text="Calendar access is off" action="Open System Settings" onAction={() => open('calendar:openPrivacy')} />

  const days = [0, 1].map((offset) => {
    const from = dayStart(now, offset)
    const to = dayStart(now, offset + 1)
    return { label: offset ? 'Tomorrow' : 'Today', day: from, list: events.filter((e) => new Date(e.start) < to && new Date(e.end) > from) }
  })
  if (!days.some((d) => d.list.length)) return <Message accent={accent} text="Nothing planned" />

  return (
    <div className="h-full overflow-y-auto px-2 py-1" onClick={(event) => event.stopPropagation()}>
      {days.map(({ label, day, list }) => (
        <section key={label} className="mb-1.5">
          <h3 className="text-[10px] font-bold uppercase tracking-[0.12em]" style={{ color: accent }}>{label}</h3>
          {list.length === 0 && <p className="py-1 text-[11px] text-white/50">Nothing planned today</p>}
          {list.map((e) => {
            const on = new Date(e.start) <= now && now < new Date(e.end)
            return (
              <div key={`${e.id}${e.start}`} className="flex items-center gap-2 rounded-lg px-1.5 py-1 hover:bg-white/[0.08]">
                <button type="button" className="flex min-w-0 flex-1 items-center gap-2 text-left" onClick={() => open('calendar:openEvent', e.id)}>
                  <span aria-hidden className="h-2 w-2 shrink-0 rounded-full" style={{ background: e.calendarColor }} />
                  <span className="truncate text-[12px] font-medium text-white">{e.title || 'Untitled'}</span>
                  <span className="ml-auto shrink-0 text-[11px] text-white/50">{timeText(e, day)}</span>
                  {on && <span className="shrink-0 rounded-full px-1.5 text-[9px] font-bold uppercase text-black" style={{ background: accent }}>Now</span>}
                </button>
                {e.joinUrl && (
                  <button type="button" aria-label={`Join ${e.title}`} className={`${quiet} flex shrink-0 items-center gap-1`} onClick={() => open('calendar:join', e.id)}>
                    <Video size={11} strokeWidth={2.2} />
                    Join
                  </button>
                )}
              </div>
            )
          })}
        </section>
      ))}
    </div>
  )
}
