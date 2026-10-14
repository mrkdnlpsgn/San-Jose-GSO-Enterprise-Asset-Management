import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'

// Material-style calendar popover replacing the browser's native <input type="date">,
// which looks different on every browser (and centred/oversized on iOS Safari).
// Drop-in for the old inputs: `value` is 'YYYY-MM-DD' (or ''), and onChange receives an
// input-like event ({ target: { name, value } }) so existing `set(key)` handlers still work.

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
const WEEKDAYS = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
const POPOVER_WIDTH = 320
const GAP = 6
const EDGE = 8

const pad = (n) => String(n).padStart(2, '0')
const toKey = (y, m, d) => `${y}-${pad(m + 1)}-${pad(d)}`
// Parsed by hand — `new Date('2026-10-15')` is UTC midnight and can land on the previous day locally.
const parseKey = (key) => {
  if (!key || !/^\d{4}-\d{2}-\d{2}$/.test(key)) return null
  const [y, m, d] = key.split('-').map(Number)
  return { y, m: m - 1, d }
}
const todayKey = () => { const t = new Date(); return toKey(t.getFullYear(), t.getMonth(), t.getDate()) }
const daysIn = (y, m) => new Date(y, m + 1, 0).getDate()
const shiftKey = (key, days) => {
  const { y, m, d } = parseKey(key)
  const dt = new Date(y, m, d + days)
  return toKey(dt.getFullYear(), dt.getMonth(), dt.getDate())
}
const shiftMonthKey = (key, months) => {
  const { y, m, d } = parseKey(key)
  const target = new Date(y, m + months, 1)
  const ty = target.getFullYear(), tm = target.getMonth()
  return toKey(ty, tm, Math.min(d, daysIn(ty, tm)))
}
const formatDisplay = (key) => {
  const p = parseKey(key)
  return p ? `${MONTHS[p.m].slice(0, 3)} ${p.d}, ${p.y}` : ''
}

function CalendarIcon({ className }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" className={className} viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
      <path fillRule="evenodd" d="M6 2a1 1 0 00-1 1v1H4a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V6a2 2 0 00-2-2h-1V3a1 1 0 10-2 0v1H7V3a1 1 0 00-1-1zm0 5a1 1 0 000 2h8a1 1 0 100-2H6z" clipRule="evenodd" />
    </svg>
  )
}

function Chevron({ dir }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
      {dir === 'left'
        ? <path fillRule="evenodd" d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z" clipRule="evenodd" />
        : <path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clipRule="evenodd" />}
    </svg>
  )
}

function DatePicker({ value, onChange, name, min, max, required = false, placeholder = 'Select date', className = '', id }) {
  const [open, setOpen] = useState(false)
  const [view, setView] = useState('days') // 'days' | 'years'
  const [focusKey, setFocusKey] = useState(value || todayKey())
  const [pos, setPos] = useState(null)
  const triggerRef = useRef(null)
  const popRef = useRef(null)
  const gridRef = useRef(null)
  const yearListRef = useRef(null)

  const focus = parseKey(focusKey)
  const isDisabled = (key) => (min && key < min) || (max && key > max)

  const emit = (v) => onChange?.({ target: { name, value: v } })
  const close = (refocus = true) => {
    setOpen(false)
    setView('days')
    if (refocus) triggerRef.current?.focus()
  }
  const select = (key) => {
    if (isDisabled(key)) return
    emit(key)
    close()
  }
  const openPicker = () => {
    setFocusKey(value || (max && todayKey() > max ? max : todayKey()))
    setView('days')
    setOpen(true)
  }

  // Fixed-position popover so it isn't clipped by a modal's scrolling body; flips above
  // the field when there isn't room below, and stays inside the viewport horizontally.
  const place = () => {
    const r = triggerRef.current?.getBoundingClientRect()
    if (!r) return
    const h = popRef.current?.offsetHeight || 400
    const vw = window.innerWidth, vh = window.innerHeight
    const width = Math.min(POPOVER_WIDTH, vw - EDGE * 2)
    const below = vh - r.bottom
    const top = below >= h + GAP || below >= r.top ? r.bottom + GAP : Math.max(EDGE, r.top - h - GAP)
    const left = Math.min(Math.max(EDGE, r.left), vw - width - EDGE)
    setPos({ top, left, width })
  }

  useLayoutEffect(() => { if (open) place() }, [open, view])

  useEffect(() => {
    if (!open) return
    const onDown = (e) => {
      if (popRef.current?.contains(e.target) || triggerRef.current?.contains(e.target)) return
      close(false)
    }
    // Capture phase on document runs before the surrounding Modal's own Escape listener,
    // wherever focus happens to be — so Escape closes only the calendar, never the form.
    const onEsc = (e) => {
      if (e.key !== 'Escape') return
      e.stopImmediatePropagation()
      e.preventDefault()
      close()
    }
    window.addEventListener('resize', place)
    window.addEventListener('scroll', place, true)
    document.addEventListener('mousedown', onDown)
    document.addEventListener('touchstart', onDown)
    document.addEventListener('keydown', onEsc, true)
    return () => {
      window.removeEventListener('resize', place)
      window.removeEventListener('scroll', place, true)
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('touchstart', onDown)
      document.removeEventListener('keydown', onEsc, true)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  // Keep keyboard focus on the highlighted day as it moves. Waits for `pos`: the popover
  // renders hidden until it's positioned, and hidden elements can't take focus.
  useEffect(() => {
    if (open && pos && view === 'days') gridRef.current?.querySelector(`[data-key="${focusKey}"]`)?.focus()
  }, [open, pos, view, focusKey])

  useEffect(() => {
    if (open && pos && view === 'years') {
      const el = yearListRef.current?.querySelector('[data-selected="true"]')
      el?.scrollIntoView({ block: 'center' })
      el?.focus()
    }
  }, [open, pos, view])

  const onGridKey = (e) => {
    const moves = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }
    if (moves[e.key] != null) { e.preventDefault(); setFocusKey(shiftKey(focusKey, moves[e.key])) }
    else if (e.key === 'PageUp') { e.preventDefault(); setFocusKey(shiftMonthKey(focusKey, e.shiftKey ? -12 : -1)) }
    else if (e.key === 'PageDown') { e.preventDefault(); setFocusKey(shiftMonthKey(focusKey, e.shiftKey ? 12 : 1)) }
    else if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); select(focusKey) }
  }

  const today = todayKey()
  const firstWeekday = new Date(focus.y, focus.m, 1).getDay()
  const cells = [
    ...Array(firstWeekday).fill(null),
    ...Array.from({ length: daysIn(focus.y, focus.m) }, (_, i) => toKey(focus.y, focus.m, i + 1)),
  ]

  const minYear = min ? parseKey(min).y : 1980
  const maxYear = max ? parseKey(max).y : new Date().getFullYear() + 10
  const years = Array.from({ length: maxYear - minYear + 1 }, (_, i) => minYear + i)

  const navBtn = 'h-9 w-9 flex items-center justify-center rounded-full text-slate-600 dark:text-zinc-300 hover:bg-slate-100 dark:hover:bg-zinc-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 transition-colors duration-150'

  return (
    <>
      <button
        ref={triggerRef}
        id={id}
        type="button"
        onClick={() => (open ? close() : openPicker())}
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-required={required || undefined}
        className={`${className} flex items-center justify-between gap-2 text-left`}
      >
        <span className={value ? '' : 'text-slate-400 dark:text-zinc-500'}>{value ? formatDisplay(value) : placeholder}</span>
        <CalendarIcon className="h-4 w-4 shrink-0 text-slate-400 dark:text-zinc-500" />
      </button>

      {open && createPortal(
        <div
          ref={popRef}
          role="dialog"
          aria-label="Choose date"
          style={pos ? { top: pos.top, left: pos.left, width: pos.width } : { visibility: 'hidden', top: 0, left: 0 }}
          className="fixed z-[60] rounded-lg bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700 shadow-xl shadow-black/15 dark:shadow-black/60 p-3 select-none"
        >
          {/* Header: month/year (click to pick a year) + prev/next month */}
          <div className="flex items-center justify-between mb-2">
            <button
              type="button"
              onClick={() => setView(view === 'days' ? 'years' : 'days')}
              aria-label={view === 'days' ? 'Choose year' : 'Back to calendar'}
              className="flex items-center gap-1 px-2 py-1.5 rounded-md text-sm font-semibold text-slate-800 dark:text-zinc-100 hover:bg-slate-100 dark:hover:bg-zinc-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 transition-colors duration-150"
            >
              {MONTHS[focus.m]} {focus.y}
              <svg xmlns="http://www.w3.org/2000/svg" className={`h-4 w-4 transition-transform duration-150 ${view === 'years' ? 'rotate-180' : ''}`} viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
              </svg>
            </button>
            {view === 'days' && (
              <div className="flex items-center">
                <button type="button" className={navBtn} aria-label="Previous month" onClick={() => setFocusKey(shiftMonthKey(focusKey, -1))}>
                  <Chevron dir="left" />
                </button>
                <button type="button" className={navBtn} aria-label="Next month" onClick={() => setFocusKey(shiftMonthKey(focusKey, 1))}>
                  <Chevron dir="right" />
                </button>
              </div>
            )}
          </div>

          {view === 'days' ? (
            <>
              <div className="grid grid-cols-7 mb-1" aria-hidden="true">
                {WEEKDAYS.map((w) => (
                  <div key={w} className="h-8 flex items-center justify-center text-xs text-slate-400 dark:text-zinc-500">{w}</div>
                ))}
              </div>
              <div ref={gridRef} role="grid" onKeyDown={onGridKey} className="grid grid-cols-7 gap-y-1">
                {cells.map((key, i) => {
                  if (!key) return <div key={`b${i}`} />
                  const selected = key === value
                  const isToday = key === today
                  const disabled = isDisabled(key)
                  return (
                    <div key={key} className="flex items-center justify-center">
                      <button
                        type="button"
                        data-key={key}
                        tabIndex={key === focusKey ? 0 : -1}
                        disabled={disabled}
                        aria-selected={selected}
                        aria-current={isToday ? 'date' : undefined}
                        aria-label={formatDisplay(key)}
                        onClick={() => select(key)}
                        className={`h-10 w-10 rounded-full text-sm tabular-nums transition-colors duration-150 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-1 dark:focus-visible:ring-offset-zinc-900 ${
                          selected
                            ? 'bg-brand-600 text-white font-semibold hover:bg-brand-700'
                            : disabled
                              ? 'text-slate-300 dark:text-zinc-700 cursor-not-allowed'
                              : isToday
                                ? 'border border-brand-600 text-brand-700 dark:text-brand-400 font-medium hover:bg-brand-50 dark:hover:bg-zinc-800'
                                : 'text-slate-700 dark:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800'
                        }`}
                      >
                        {parseKey(key).d}
                      </button>
                    </div>
                  )
                })}
              </div>
            </>
          ) : (
            <div ref={yearListRef} className="grid grid-cols-4 gap-1 max-h-[17rem] overflow-y-auto py-1" style={{ scrollbarWidth: 'thin' }}>
              {years.map((y) => {
                const selected = y === focus.y
                return (
                  <button
                    key={y}
                    type="button"
                    data-selected={selected}
                    onClick={() => {
                      setFocusKey(toKey(y, focus.m, Math.min(focus.d, daysIn(y, focus.m))))
                      setView('days')
                    }}
                    className={`h-10 rounded-full text-sm tabular-nums transition-colors duration-150 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 ${
                      selected ? 'bg-brand-600 text-white font-semibold' : 'text-slate-700 dark:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800'
                    }`}
                  >
                    {y}
                  </button>
                )
              })}
            </div>
          )}

          {/* Footer actions */}
          <div className="flex items-center justify-between mt-2 pt-2 border-t border-slate-100 dark:border-zinc-800">
            {!required && value ? (
              <button type="button" onClick={() => { emit(''); close() }} className="px-3 py-1.5 rounded-md text-sm font-medium text-slate-500 dark:text-zinc-400 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-colors duration-150">
                Clear
              </button>
            ) : <span />}
            <button
              type="button"
              disabled={isDisabled(today)}
              onClick={() => select(today)}
              className="px-3 py-1.5 rounded-md text-sm font-semibold text-brand-700 dark:text-brand-400 hover:bg-brand-50 dark:hover:bg-zinc-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors duration-150"
            >
              Today
            </button>
          </div>
        </div>,
        document.body
      )}
    </>
  )
}

export default DatePicker
