import React from 'react'
import { motion } from 'motion/react'
import { Cake, ChevronLeft, ChevronRight, Flag, Video, X } from 'lucide-react'
import { dayKey, type TaskStore } from '../../hooks/useTasks'
import { dayStart, kindOf, type CalendarAccess, type CalendarEvent } from '../../hooks/useCalendar'

export const CALENDAR_WIDTH = 580
/** Header and weekday row, plus one 22px row per week of the month, so a 5-week month leaves no dead space. */
export const calendarHeight = (month: Date) =>
  40 + 22 * Math.ceil((month.getDay() + new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()) / 7)

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

const overlaps = (e: CalendarEvent, day: Date) => new Date(e.start) < dayStart(day, 1) && new Date(e.end) > day
const sameDay = (a: Date, b: Date) => dayKey(a) === dayKey(b)
const heading = new Intl.DateTimeFormat(undefined, { weekday: 'long', day: 'numeric', month: 'long' })
const count = (n: number, one: string) => (n === 0 ? `No ${one}s` : `${n} ${one}${n === 1 ? '' : 's'}`)

/** The shown month as a grid: today filled in the accent, the selected day ringed, a dot when a day has something. */
const Month: React.FC<{
  month: Date
  now: Date
  accent: string
  selected: Date | null
  busy: (day: Date) => boolean
  onMonth: (m: Date) => void
  onSelect: (d: Date | null) => void
}> = ({ month, now, accent, selected, busy, onMonth, onSelect }) => {
  const days = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
  const cells = [...Array(month.getDay()).fill(0), ...Array.from({ length: days }, (_, i) => i + 1)]
  const thisMonth = month.getFullYear() === now.getFullYear() && month.getMonth() === now.getMonth()
  const go = (by: number) => onMonth(new Date(month.getFullYear(), month.getMonth() + by, 1))
  const arrow = 'grid h-4 w-4 place-items-center rounded-full text-white/60 hover:bg-white/[0.12] hover:text-white'
  return (
    <div className="flex w-[190px] shrink-0 flex-col px-2 py-1" onClick={(event) => event.stopPropagation()}>
      <div className="mb-1 flex items-center gap-1">
        <h3 className="min-w-0 flex-1 truncate text-[12px] font-semibold text-white">
          {month.toLocaleDateString(undefined, { month: 'long' })} <span className="text-white/50">{month.getFullYear()}</span>
        </h3>
        {(!thisMonth || selected) && (
          <button type="button" className="rounded-full px-1.5 text-[9px] font-bold uppercase text-black" style={{ background: accent }} onClick={() => { onMonth(new Date(now.getFullYear(), now.getMonth(), 1)); onSelect(null) }}>
            Today
          </button>
        )}
        <button type="button" aria-label="Previous month" className={arrow} onClick={() => go(-1)}><ChevronLeft size={12} /></button>
        <button type="button" aria-label="Next month" className={arrow} onClick={() => go(1)}><ChevronRight size={12} /></button>
      </div>
      <div className="grid grid-cols-7 gap-y-0 text-center text-[10px]">
        {['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d, i) => (
          <span key={i} className="font-semibold text-white/40">{d}</span>
        ))}
        {cells.map((d, i) => {
          if (!d) return <span key={i} />
          const day = new Date(month.getFullYear(), month.getMonth(), d)
          const today = sameDay(day, now)
          const chosen = !!selected && sameDay(day, selected)
          return (
            <button
              key={i}
              type="button"
              aria-pressed={chosen}
              aria-label={heading.format(day)}
              onClick={() => onSelect(chosen ? null : day)}
              className={`relative mx-auto grid h-[22px] w-[22px] place-items-center rounded-full ${today ? 'font-bold text-black' : 'text-white/80 hover:bg-white/[0.12]'}`}
              style={{ ...(today ? { background: accent } : undefined), ...(chosen ? { boxShadow: `0 0 0 1.5px ${accent}` } : undefined) }}
            >
              {d}
              {busy(day) && <span aria-hidden className="absolute bottom-[1px] h-[3px] w-[3px] rounded-full" style={{ background: today ? '#000' : accent }} />}
            </button>
          )
        })}
      </div>
    </div>
  )
}

const EventRow: React.FC<{ e: CalendarEvent; day: Date; now: Date; accent: string; grey?: boolean }> = ({ e, day, now, accent, grey }) => {
  const kind = kindOf(e)
  const special = kind !== 'event'
  const on = !special && new Date(e.start) <= now && now < new Date(e.end)
  const Icon = kind === 'birthday' ? Cake : Flag
  return (
    <div className={`flex items-center gap-2 rounded-lg px-1.5 py-1 hover:bg-white/[0.08] ${grey ? 'opacity-40' : ''}`}>
      <button type="button" className="flex min-w-0 flex-1 items-center gap-2 text-left" onClick={() => open('calendar:openEvent', e.id)}>
        {special ? (
          <Icon aria-hidden size={12} strokeWidth={2.2} className="shrink-0" style={{ color: e.calendarColor }} />
        ) : (
          <span aria-hidden className="h-2 w-2 shrink-0 rounded-full" style={{ background: e.calendarColor }} />
        )}
        <span className="truncate text-[12px] font-medium text-white">{e.title || 'Untitled'}</span>
        {!special && <span className="ml-auto shrink-0 text-[11px] text-white/50">{timeText(e, day)}</span>}
        {on && <span className="shrink-0 rounded-full px-1.5 text-[9px] font-bold uppercase text-black" style={{ background: accent }}>Now</span>}
      </button>
      {e.joinUrl && !grey && !special && (
        <button type="button" aria-label={`Join ${e.title}`} className={`${quiet} flex shrink-0 items-center gap-1`} onClick={() => open('calendar:join', e.id)}>
          <Video size={11} strokeWidth={2.2} />
          Join
        </button>
      )}
    </div>
  )
}

/** One day: heading, counts, its events, and its tasks with tick, remove and add. */
const DayPane: React.FC<{
  day: Date
  now: Date
  accent: string
  access: CalendarAccess
  events: CalendarEvent[]
  tasks: TaskStore
  showTasks: boolean
}> = ({ day, now, accent, access, events, tasks, showTasks }) => {
  const [draft, setDraft] = React.useState('')
  const list = events.filter((e) => overlaps(e, day)).sort((a, b) => Number(b.allDay) - Number(a.allDay) || +new Date(a.start) - +new Date(b.start))
  const key = dayKey(day)
  const isToday = key === dayKey(now)
  const mine = tasks.tasks.filter((t) => t.due === key || (!t.due && isToday)).sort((a, b) => Number(a.done) - Number(b.done))
  const days = list.filter((e) => kindOf(e) !== 'event')
  const normal = list.filter((e) => kindOf(e) === 'event')
  const counts = [access === 'granted' && days.length > 0 && count(days.length, 'special day'), access === 'granted' && count(normal.length, 'event'), showTasks && count(mine.length, 'task')].filter(Boolean).join(', ')
  return (
    <div className="h-full overflow-y-auto px-2 py-1" onClick={(event) => event.stopPropagation()}>
      <h3 className="text-[12px] font-semibold text-white">{heading.format(day)}</h3>
      <p className="mb-1 text-[10px] text-white/50">{counts}</p>
      {access !== 'granted' && <p className="py-1 text-[11px] text-white/50">Calendar access is off</p>}
      {days.length > 0 && (
        <section aria-label="Special days" className="mb-1">
          <h4 className="px-1.5 text-[9px] font-bold uppercase tracking-wide text-white/40">Special days</h4>
          {days.map((e) => <EventRow key={`${e.id}${e.start}`} e={e} day={day} now={now} accent={accent} />)}
        </section>
      )}
      {normal.map((e) => <EventRow key={`${e.id}${e.start}`} e={e} day={day} now={now} accent={accent} grey={new Date(e.end) <= now} />)}
      {showTasks && (
        <section className="mt-1">
          {mine.map((t) => (
            <div key={t.id} className={`flex items-center gap-2 rounded-lg px-1.5 py-0.5 hover:bg-white/[0.08] ${t.done ? 'opacity-40' : ''}`}>
              <input type="checkbox" checked={t.done} aria-label={t.label} onChange={() => tasks.toggle(t.id)} style={{ accentColor: accent }} />
              <span className={`min-w-0 flex-1 truncate text-[12px] text-white ${t.done ? 'line-through' : ''}`}>{t.label}</span>
              <button type="button" aria-label={`Remove ${t.label}`} className="text-white/40 hover:text-white" onClick={() => tasks.remove(t.id)}><X size={12} /></button>
            </div>
          ))}
          <form
            className="px-1.5 py-0.5"
            onSubmit={(event) => {
              event.preventDefault()
              tasks.add(draft, key)
              setDraft('')
            }}
          >
            <input value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="Add a task" className="w-full bg-transparent text-[12px] text-white outline-none placeholder:text-white/40" />
          </form>
        </section>
      )}
    </div>
  )
}

/** Today and tomorrow by default; click a day in the grid to see that day instead. */
export const CalendarView: React.FC<{
  access: CalendarAccess
  events: CalendarEvent[]
  shown: CalendarEvent[]
  month: Date
  onMonth: (m: Date) => void
  tasks: TaskStore
  showTasks: boolean
  now: Date
  accent: string
  onAllow: () => void
}> = ({ access, events, shown, month, onMonth, tasks, showTasks, now, accent, onAllow }) => {
  const [selected, setSelected] = React.useState<Date | null>(null)
  const busy = (day: Date) =>
    (access === 'granted' && shown.some((e) => overlaps(e, day))) || (showTasks && tasks.tasks.some((t) => !t.done && t.due === dayKey(day)))
  const changeMonth = (m: Date) => {
    onMonth(m)
    if (selected && (selected.getMonth() !== m.getMonth() || selected.getFullYear() !== m.getFullYear())) setSelected(null)
  }
  return (
    <div className="flex h-full">
      <Month month={month} now={now} accent={accent} selected={selected} busy={busy} onMonth={changeMonth} onSelect={setSelected} />
      <div className="min-w-0 flex-1 border-l border-white/10">
        {selected ? (
          <DayPane day={selected} now={now} accent={accent} access={access} events={shown} tasks={tasks} showTasks={showTasks} />
        ) : (
          <Events access={access} events={events} now={now} accent={accent} onAllow={onAllow} />
        )}
      </div>
    </div>
  )
}

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
          {list.map((e) => <EventRow key={`${e.id}${e.start}`} e={e} day={day} now={now} accent={accent} />)}
        </section>
      ))}
    </div>
  )
}
