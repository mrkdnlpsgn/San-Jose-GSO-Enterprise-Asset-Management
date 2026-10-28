import { useState } from 'react'
import { useLocation } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'
import ConfirmDialog from '../common/ConfirmDialog'
import NotificationBell from '../common/NotificationBell'
import AccountMenu from '../common/AccountMenu'
import { roleLabel as labelOfRole } from '../../utils/roles'

const pageMeta = {
  '/home':          'Home',
  '/assets':        'Assets',
  '/asset-history': 'Asset History',
  '/maintenance':   'Maintenance',
  '/disposal':      'Disposal',
  '/offices':       'Offices',
  '/categories':    'Categories',
  '/reports':       'Reports',
  '/transfer':      'Transfer Asset',
  '/accounts':      'Accounts',
  '/audit-logs':    'Audit Logs',
  '/my-account':    'My Account',
  '/personnel':     'Personnel',
  '/deleted-records': 'Recovery',
  '/privacy':       'Privacy, Terms & Conditions',
}

function Header({ onMenuOpen }) {
  const { user, signOut } = useAuth()
  const { pathname } = useLocation()
  const [showLogoutConfirm, setShowLogoutConfirm] = useState(false)

  const title = pageMeta[pathname] ?? 'San Jose GSO'
  const name = user?.fullName ?? user?.username ?? 'Administrator'
  const roleLabel = user?.role === 'ADMIN' ? 'System Administrator' : labelOfRole(user?.role)

  return (
    <header className="h-[3.75rem] bg-white dark:bg-zinc-950 border-b border-slate-200 dark:border-zinc-800 px-4 sm:px-6 flex items-center justify-between flex-shrink-0 gap-3">
      {/* Hamburger - mobile only */}
      <button
        onClick={onMenuOpen}
        className="lg:hidden p-2 -ml-2 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150 flex-shrink-0"
        aria-label="Open menu"
      >
        <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M4 6h16M4 12h16M4 18h16" />
        </svg>
      </button>

      <div className="flex-1 min-w-0">
        <h1 className="text-base font-semibold text-gov-700 dark:text-white leading-tight truncate">{title}</h1>
      </div>

      {/* Icons only: notifications, then the account menu (My Account, Appearance, Sign Out) */}
      <div className="flex items-center gap-1 flex-shrink-0">
        <NotificationBell />
        <AccountMenu user={user} name={name} roleLabel={roleLabel} onSignOut={() => setShowLogoutConfirm(true)} />
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
