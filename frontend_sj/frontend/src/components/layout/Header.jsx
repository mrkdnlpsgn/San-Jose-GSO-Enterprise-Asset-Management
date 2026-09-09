import { useState } from 'react'
import { useLocation, Link } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'
import { useTheme } from '../../context/ThemeContext'
import ConfirmDialog from '../common/ConfirmDialog'

const pageMeta = {
  '/dashboard':     'Dashboard',
  '/assets':        'Assets',
  '/asset-history': 'Asset History',
  '/maintenance':   'Maintenance',
  '/disposal':      'Disposal',
  '/offices':       'Offices',
  '/categories':    'Categories',
  '/reports':       'Reports',
  '/qr-scanner':    'QR Scanner',
  '/accounts':      'Accounts',
  '/audit-logs':    'Audit Logs',
  '/my-account':    'My Account',
}

function Header({ onMenuOpen }) {
  const { user, signOut } = useAuth()
  const { pathname } = useLocation()
  const { isDark, toggle } = useTheme()
  const [showLogoutConfirm, setShowLogoutConfirm] = useState(false)

  const title = pageMeta[pathname] ?? 'San Jose GSO Inventory Management System'
  const name = user?.fullName ?? user?.username ?? 'Administrator'
  const initials = name.split(' ').map((n) => n[0]).join('').slice(0, 2).toUpperCase()
  const roleLabel = user?.role === 'ADMIN' ? 'System Administrator' : user?.role === 'STAFF' ? 'ICT Staff' : (user?.role ?? 'Staff')

  return (
    <header className="h-[60px] bg-white dark:bg-zinc-950 border-b border-slate-200 dark:border-zinc-800 px-4 sm:px-6 flex items-center justify-between flex-shrink-0 gap-3">
      {/* Hamburger — mobile only */}
      <button
        onClick={onMenuOpen}
        className="lg:hidden p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150 flex-shrink-0"
        aria-label="Open menu"
      >
        <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M4 6h16M4 12h16M4 18h16" />
        </svg>
      </button>

      <div className="flex-1 min-w-0">
        <h1 className="text-base font-semibold text-gov-700 dark:text-white leading-tight">{title}</h1>
      </div>

      <div className="flex items-center gap-2">
        <Link
          to="/my-account"
          className="flex items-center gap-2.5 rounded-lg px-2 py-1 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-colors duration-150 group"
        >
          <div className="text-right hidden sm:block">
            <p className="text-sm font-medium text-slate-700 dark:text-zinc-200 group-hover:text-slate-900 dark:group-hover:text-white leading-tight transition-colors duration-150">{name}</p>
            <p className="text-xs text-slate-400 dark:text-zinc-500 leading-tight mt-px">{roleLabel}</p>
          </div>
          <div className="w-8 h-8 rounded-full bg-brand-500 text-white text-xs font-bold flex items-center justify-center select-none flex-shrink-0 ring-2 ring-transparent group-hover:ring-brand-400 transition-all duration-150">
            {initials}
          </div>
        </Link>

        <div className="w-px h-5 bg-slate-200 dark:bg-zinc-800 mx-1" />

        <button
          onClick={toggle}
          title={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
          className="p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150"
          aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
        >
          {isDark ? (
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z" clipRule="evenodd" />
            </svg>
          ) : (
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
              <path d="M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z" />
            </svg>
          )}
        </button>

        <div className="w-px h-5 bg-slate-200 dark:bg-zinc-800 mx-1" />

        <button
          onClick={() => setShowLogoutConfirm(true)}
          title="Sign Out"
          className="flex items-center gap-1.5 text-xs text-slate-400 dark:text-zinc-500 hover:text-red-500 dark:hover:text-red-400 transition-colors duration-150 font-medium"
        >
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
          </svg>
          <span className="hidden sm:inline">Sign Out</span>
        </button>
      </div>

      {showLogoutConfirm && (
        <ConfirmDialog
          title="Sign out of your account?"
          message="You will be returned to the login page and will need to sign in again to continue."
          confirmLabel="Sign Out"
          onConfirm={signOut}
          onCancel={() => setShowLogoutConfirm(false)}
        />
      )}
    </header>
  )
}

export default Header
