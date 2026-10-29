import { useCallback, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import UserAvatar from './UserAvatar'
import { AppearanceOptions } from './SettingsMenu'

function Icon({ d }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" className="h-[1.1rem] w-[1.1rem] flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2} aria-hidden="true">
      <path strokeLinecap="round" strokeLinejoin="round" d={d} />
    </svg>
  )
}

const ITEM = 'w-full flex items-center gap-2.5 px-2.5 py-2 rounded-md text-sm text-left transition-colors duration-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500'

// The header's account button: the avatar opens a menu with My Account, Appearance (theme and
// text size, folded open in place) and Sign Out.
function AccountMenu({ user, name, roleLabel, onSignOut }) {
  const [open, setOpen] = useState(false)
  const [showAppearance, setShowAppearance] = useState(false)
  const [closing, setClosing] = useState(false)    // the menu's exit animation is playing
  const ref = useRef(null)
  const closeTimer = useRef(null)

  // Like the notification panel: the menu shrinks back into the avatar before it's removed.
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

  useEffect(() => {
    if (!open) { setShowAppearance(false); return }
    const onClick = (e) => { if (!ref.current?.contains(e.target)) close() }
    const onKey = (e) => { if (e.key === 'Escape') close() }
    document.addEventListener('mousedown', onClick)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onClick)
      document.removeEventListener('keydown', onKey)
    }
  }, [open, close])

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        onClick={() => (open ? close() : setOpen(true))}
        aria-haspopup="menu"
        aria-expanded={open && !closing}
        aria-label={`Account: ${name}, ${roleLabel}`}
        title={`${name} (${roleLabel})`}
        className="flex items-center justify-center min-w-[2.5rem] min-h-[2.5rem] -mr-1 rounded-md hover:bg-slate-100 dark:hover:bg-zinc-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 transition-colors duration-150 group"
      >
        <UserAvatar user={user} className={`w-8 h-8 text-xs ring-2 transition-all duration-150 ${open ? 'ring-brand-400' : 'ring-transparent group-hover:ring-brand-400'}`} />
      </button>

      {open && (
        <div role="menu" aria-label="Account"
          className={`absolute right-0 mt-2 w-64 z-50 rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 shadow-lg p-1.5 max-h-[calc(100vh-5rem)] overflow-y-auto origin-top-right ${
            closing ? 'animate-panel-out pointer-events-none' : 'animate-panel-in'}`}>
          <div className="flex items-center gap-2.5 px-2.5 pt-1.5 pb-2.5">
            <UserAvatar user={user} className="w-9 h-9 text-sm flex-shrink-0" />
            <div className="min-w-0">
              <p className="text-sm font-semibold text-slate-800 dark:text-zinc-100 truncate">{name}</p>
              <p className="text-xs text-slate-500 dark:text-zinc-400 truncate">{roleLabel}</p>
            </div>
          </div>

          <div className="mb-1 h-px bg-slate-200 dark:bg-zinc-800" />

          <Link to="/my-account" role="menuitem" onClick={() => setOpen(false)}
            className={`${ITEM} text-slate-700 dark:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800`}>
            <Icon d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
            My Account
          </Link>

          <button type="button" role="menuitem" aria-expanded={showAppearance}
            onClick={() => setShowAppearance((p) => !p)}
            className={`${ITEM} text-slate-700 dark:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800`}>
            <Icon d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01" />
            <span className="flex-1">Appearance</span>
            <svg xmlns="http://www.w3.org/2000/svg" className={`h-4 w-4 text-slate-400 transition-transform duration-150 ${showAppearance ? 'rotate-180' : ''}`} viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
            </svg>
          </button>
          {showAppearance && (
            <div className="mx-1 mb-1 mt-0.5 rounded-md bg-slate-50 dark:bg-zinc-800/50 p-1 animate-fade-in">
              <AppearanceOptions />
            </div>
          )}

          <div className="my-1 h-px bg-slate-200 dark:bg-zinc-800" />

          <button type="button" role="menuitem" onClick={() => { setOpen(false); onSignOut() }}
            className={`${ITEM} text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-500/10`}>
            <Icon d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
            Sign Out
          </button>
        </div>
      )}
    </div>
  )
}

export default AccountMenu
