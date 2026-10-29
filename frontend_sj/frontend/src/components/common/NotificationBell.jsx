import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { NOTIFICATION_CATEGORIES, useNotifications } from '../../hooks/useNotifications'

// The header's bell, like the mobile app's: everything someone has to act on in one panel,
// filterable by the kind of action it is about. Opening the panel marks it all as read; the
// ones that were new when it opened keep their dot until it closes.

const ICONS = {
  reminder: 'M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9',
  approval: 'M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4',
  pending:  'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z',
  rejected: 'M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636',
  account:  'M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4',
  asset:    'M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z',
}

const TONE = {
  amber: 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-400',
  red:   'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-400',
  slate: 'bg-slate-100 text-slate-600 dark:bg-zinc-800 dark:text-zinc-300',
}

function Icon({ d, className = 'h-4 w-4' }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" className={className} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2} aria-hidden="true">
      <path strokeLinecap="round" strokeLinejoin="round" d={d} />
    </svg>
  )
}

function NotificationBell() {
  const navigate = useNavigate()
  const { items, loading, failed, unreadCount, isUnread, markAllSeen, refresh } = useNotifications()
  const [open, setOpen] = useState(false)
  const [filter, setFilter] = useState('all')
  const [newKeys, setNewKeys] = useState(() => new Set())
  const [expanded, setExpanded] = useState(null)   // key of the notification whose asset list is open
  const [closing, setClosing] = useState(false)    // the panel's exit animation is playing
  const ref = useRef(null)
  const closeTimer = useRef(null)

  // The panel shrinks back into the bell before it's removed.
  const close = useCallback(() => {
    if (closeTimer.current) return
    setClosing(true)
    closeTimer.current = setTimeout(() => {
      closeTimer.current = null
      setClosing(false)
      setOpen(false)
    }, 140)
  }, [])
  useEffect(() => () => clearTimeout(closeTimer.current), [])

  // The bell swings and the badge pops each time the unread count goes up - not for what is
  // already there when the page loads.
  const [ringKey, setRingKey] = useState(0)
  const lastUnread = useRef(null)
  useEffect(() => {
    if (loading) return
    if (lastUnread.current !== null && unreadCount > lastUnread.current) setRingKey((k) => k + 1)
    lastUnread.current = unreadCount
  }, [unreadCount, loading])

  // While the panel is open, notifications that arrive slide in; the ones it opened with don't.
  const knownKeys = useRef(new Set())
  const arrived = open ? new Set(items.filter((n) => !knownKeys.current.has(n.key)).map((n) => n.key)) : new Set()
  useEffect(() => {
    knownKeys.current = open ? new Set([...knownKeys.current, ...items.map((n) => n.key)]) : new Set()
  }, [open, items])

  useEffect(() => {
    if (!open) return
    const onClick = (e) => { if (!ref.current?.contains(e.target)) close() }
    const onKey = (e) => { if (e.key === 'Escape') close() }
    document.addEventListener('mousedown', onClick)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onClick)
      document.removeEventListener('keydown', onKey)
    }
  }, [open, close])

  // Whatever arrives while the panel is open is read straight away.
  useEffect(() => { if (open) markAllSeen() }, [open, markAllSeen])

  const toggle = () => {
    if (open) { close(); return }
    setNewKeys(new Set(items.filter(isUnread).map((n) => n.key)))
    knownKeys.current = new Set(items.map((n) => n.key))
    refresh()
    setOpen(true)
  }

  // Only the kinds there is something for, in a fixed order.
  const categories = useMemo(() => Object.keys(NOTIFICATION_CATEGORIES)
    .map((id) => ({ id, count: items.filter((n) => n.category === id).length }))
    .filter((c) => c.count > 0), [items])
  const activeFilter = filter === 'all' || categories.some((c) => c.id === filter) ? filter : 'all'
  const shown = activeFilter === 'all' ? items : items.filter((n) => n.category === activeFilter)

  // Opens the page and highlights the records the notification is about (see useHighlight).
  const go = (to, ids, title) => {
    close()
    navigate(to, ids?.length ? { state: { highlight: { ids, title } } } : undefined)
  }

  const chip = (id, label, count) => (
    <button key={id} type="button" onClick={() => setFilter(id)} aria-pressed={activeFilter === id}
      className={`shrink-0 inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium transition-colors duration-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 ${
        activeFilter === id
          ? 'bg-slate-900 text-white dark:bg-white dark:text-zinc-900'
          : 'bg-slate-100 text-slate-700 hover:bg-slate-200 dark:bg-zinc-800 dark:text-zinc-300 dark:hover:bg-zinc-700'
      }`}>
      {label}
      <span className={activeFilter === id ? 'opacity-70' : 'text-slate-500 dark:text-zinc-400'}>{count}</span>
    </button>
  )

  return (
    <div ref={ref} className="relative">
      <button type="button" onClick={toggle} aria-haspopup="dialog" aria-expanded={open}
        aria-label={unreadCount > 0 ? `Notifications, ${unreadCount} unread` : 'Notifications'} title="Notifications"
        className="relative flex items-center justify-center min-w-[2.5rem] min-h-[2.5rem] rounded-md text-slate-600 dark:text-zinc-300 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-zinc-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 transition-colors duration-150">
        {/* keyed so each new arrival replays the swing; it pivots from the top, where a bell hangs */}
        <span key={ringKey} className={`inline-flex origin-top ${ringKey > 0 ? 'animate-bell-ring' : ''}`}>
          <Icon className="h-5 w-5" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
        </span>
        {unreadCount > 0 && (
          <span key={`badge-${ringKey}`} aria-hidden="true" className={`absolute top-1 right-1 min-w-[1.05rem] h-[1.05rem] px-1 rounded-full bg-red-500 text-white text-[0.65rem] font-semibold leading-[1.05rem] text-center ring-2 ring-white dark:ring-zinc-950 ${ringKey > 0 ? 'animate-badge-pop' : ''}`}>
            {unreadCount > 9 ? '9+' : unreadCount}
          </span>
        )}
      </button>

      {open && (
        <div role="dialog" aria-label="Notifications"
          className={`fixed inset-x-4 top-[4.25rem] sm:absolute sm:inset-x-auto sm:top-auto sm:right-0 sm:mt-2 sm:w-[24rem] z-50 rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 shadow-lg overflow-hidden origin-top-right ${
            closing ? 'animate-panel-out pointer-events-none' : 'animate-panel-in'}`}>
          <div className="px-4 pt-3 pb-2 flex items-center justify-between gap-3">
            <p className="text-sm font-semibold text-slate-800 dark:text-zinc-100">Notifications</p>
            {items.length > 0 && <p className="text-xs text-slate-500 dark:text-zinc-400">{items.length} to look at</p>}
          </div>

          {categories.length > 0 && (
            <div className="px-4 pb-2.5 flex gap-1.5 overflow-x-auto" role="group" aria-label="Filter notifications by kind">
              {chip('all', 'All', items.length)}
              {categories.map((c) => chip(c.id, NOTIFICATION_CATEGORIES[c.id].label, c.count))}
            </div>
          )}

          <div className="border-t border-slate-100 dark:border-zinc-800 max-h-[min(26rem,calc(100vh-9rem))] overflow-y-auto">
            {loading ? (
              <p className="px-4 py-6 text-sm text-slate-500 dark:text-zinc-400 text-center">Loading…</p>
            ) : shown.length === 0 ? (
              <p className="px-4 py-6 text-sm text-slate-500 dark:text-zinc-400 text-center">
                {failed ? "Couldn't load notifications. Try again in a moment." : "You're all caught up."}
              </p>
            ) : (
              <ul className="divide-y divide-slate-100 dark:divide-zinc-800">
                {shown.map((n) => {
                  const body = (
                    <>
                      <span className={`mt-0.5 shrink-0 inline-flex items-center justify-center w-8 h-8 rounded-full ${TONE[n.tone] ?? TONE.slate}`}>
                        <Icon d={ICONS[n.category]} />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block text-xs font-medium text-slate-500 dark:text-zinc-400">{NOTIFICATION_CATEGORIES[n.category].label}</span>
                        <span className="block text-sm font-medium text-slate-800 dark:text-zinc-100">{n.title}</span>
                        {n.detail && <span className={`block text-xs text-slate-500 dark:text-zinc-400 mt-0.5 ${n.to ? 'truncate' : ''}`}>{n.detail}</span>}
                      </span>
                      {newKeys.has(n.key) && <span className="mt-2 shrink-0 w-2 h-2 rounded-full bg-brand-500" aria-label="New" />}
                    </>
                  )
                  const listOpen = expanded === n.key
                  return (
                    <li key={n.key} className={arrived.has(n.key) ? 'animate-slide-down' : undefined}>
                      {n.to ? (
                        <button type="button" onClick={() => go(n.to, n.highlight, n.title)}
                          className="w-full flex items-start gap-3 px-4 py-3 text-left hover:bg-slate-50 dark:hover:bg-zinc-800/60 focus:outline-none focus-visible:bg-slate-50 dark:focus-visible:bg-zinc-800/60 transition-colors duration-100">
                          {body}
                        </button>
                      ) : (
                        <div className="flex items-start gap-3 px-4 py-3">{body}</div>
                      )}
                      {/* The assets behind an asset problem, each opening that asset (the Assets
                          page has no filter for things like "no accountable person"). */}
                      {n.assets?.length > 0 && (
                        <div className="pl-[3.75rem] pr-4 pb-3 -mt-1">
                          <button type="button" onClick={() => setExpanded(listOpen ? null : n.key)} aria-expanded={listOpen}
                            className="text-xs font-medium text-brand-700 dark:text-brand-300 hover:underline focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 rounded">
                            {listOpen ? 'Hide the list' : `Show the list (${n.assets.length}${n.count > n.assets.length ? ` of ${n.count}` : ''})`}
                          </button>
                          {listOpen && (
                            <ul className="mt-1.5 space-y-1">
                              {n.assets.map((a) => (
                                <li key={a.id} className="text-xs truncate">
                                  <button type="button" onClick={() => go('/assets', [a.id], `${a.propertyNumber}: ${n.title}`)}
                                    className="max-w-full truncate text-left text-slate-600 dark:text-zinc-300 hover:text-brand-600 dark:hover:text-brand-400">
                                    <span className="font-mono text-slate-500 dark:text-zinc-400 mr-1.5">{a.propertyNumber}</span>
                                    {a.description || 'N/A'}
                                  </button>
                                </li>
                              ))}
                              {n.count > n.assets.length && (
                                <li className="text-xs text-slate-500 dark:text-zinc-400">and {n.count - n.assets.length} more</li>
                              )}
                            </ul>
                          )}
                        </div>
                      )}
                    </li>
                  )
                })}
              </ul>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

export default NotificationBell
