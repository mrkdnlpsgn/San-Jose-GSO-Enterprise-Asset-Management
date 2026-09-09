import { NavLink, useLocation } from 'react-router-dom'
import { useSelector } from 'react-redux'
import { useEffect, useState, useRef } from 'react'
import { getAuditLogs } from '../../services/auditLogService'

const LAST_SEEN_KEY = 'lastSeenAuditLogId'

function useAuditLogPing(pathname) {
  const [hasNew, setHasNew] = useState(false)
  const intervalRef = useRef(null)

  const check = async () => {
    try {
      const { data } = await getAuditLogs()
      if (!data?.length) return
      const latestId = String(data[0].id)
      const lastSeen = localStorage.getItem(LAST_SEEN_KEY)
      setHasNew(lastSeen !== latestId)
    } catch {}
  }

  useEffect(() => {
    check()
    intervalRef.current = setInterval(check, 60000)
    return () => clearInterval(intervalRef.current)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (pathname === '/audit-logs') {
      getAuditLogs().then(({ data }) => {
        if (data?.length) localStorage.setItem(LAST_SEEN_KEY, String(data[0].id))
        setHasNew(false)
      }).catch(() => {})
    }
  }, [pathname])

  return hasNew
}

const navItems = [
  {
    to: '/dashboard',
    label: 'Dashboard',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path d="M5 3a2 2 0 00-2 2v2a2 2 0 002 2h2a2 2 0 002-2V5a2 2 0 00-2-2H5zM5 11a2 2 0 00-2 2v2a2 2 0 002 2h2a2 2 0 002-2v-2a2 2 0 00-2-2H5zM11 5a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V5zM11 13a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
      </svg>
    ),
  },
  {
    to: '/assets',
    label: 'Assets',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path d="M11 17a1 1 0 001.447.894l4-2A1 1 0 0017 15V9.236a1 1 0 00-1.447-.894l-4 2a1 1 0 00-.553.894V17zM15.211 6.276a1 1 0 000-1.788l-4.764-2.382a1 1 0 00-.894 0L4.789 4.488a1 1 0 000 1.788l4.764 2.382a1 1 0 00.894 0l4.764-2.382zM4.447 8.342A1 1 0 003 9.236V15a1 1 0 00.553.894l4 2A1 1 0 009 17v-5.764a1 1 0 00-.553-.894l-4-2z" />
      </svg>
    ),
  },
  {
    to: '/asset-history',
    label: 'Asset History',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clipRule="evenodd" />
      </svg>
    ),
  },
  {
    to: '/maintenance',
    label: 'Maintenance',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" />
      </svg>
    ),
  },
  {
    to: '/disposal',
    label: 'Disposal',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clipRule="evenodd" />
      </svg>
    ),
  },
  {
    to: '/qr-scanner',
    label: 'QR Scanner',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M3 4a1 1 0 011-1h3a1 1 0 011 1v3a1 1 0 01-1 1H4a1 1 0 01-1-1V4zm2 2V5h1v1H5zM3 13a1 1 0 011-1h3a1 1 0 011 1v3a1 1 0 01-1 1H4a1 1 0 01-1-1v-3zm2 2v-1h1v1H5zM13 3a1 1 0 00-1 1v3a1 1 0 001 1h3a1 1 0 001-1V4a1 1 0 00-1-1h-3zm1 2v1h1V5h-1zM11 7a1 1 0 112 0v1h1a1 1 0 110 2h-2a1 1 0 01-1-1V7zM7 11a1 1 0 100 2h1v1a1 1 0 102 0v-2a1 1 0 00-1-1H7zM13 11a1 1 0 100 2h.01a1 1 0 100-2H13zM15 13a1 1 0 100 2h.01a1 1 0 100-2H15zM13 15a1 1 0 100 2h.01a1 1 0 100-2H13z" clipRule="evenodd" />
      </svg>
    ),
  },
  {
    to: '/reports',
    label: 'Reports',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path d="M2 11a1 1 0 011-1h2a1 1 0 011 1v5a1 1 0 01-1 1H3a1 1 0 01-1-1v-5zM8 7a1 1 0 011-1h2a1 1 0 011 1v9a1 1 0 01-1 1H9a1 1 0 01-1-1V7zM14 4a1 1 0 011-1h2a1 1 0 011 1v12a1 1 0 01-1 1h-2a1 1 0 01-1-1V4z" />
      </svg>
    ),
  },
]

// Open to every authenticated user — offices, categories, and the audit trail are
// shared operational data, not account-management functions.
const systemNavItems = [
  {
    to: '/offices',
    label: 'Offices',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M4 4a2 2 0 012-2h8a2 2 0 012 2v12a1 1 0 110 2h-3a1 1 0 01-1-1v-2a1 1 0 00-1-1H9a1 1 0 00-1 1v2a1 1 0 01-1 1H4a1 1 0 110-2V4zm3 1h2v2H7V5zm2 4H7v2h2V9zm2-4h2v2h-2V5zm2 4h-2v2h2V9z" clipRule="evenodd" />
      </svg>
    ),
  },
  {
    to: '/categories',
    label: 'Categories',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path d="M7 3a1 1 0 000 2h6a1 1 0 100-2H7zM4 7a1 1 0 011-1h10a1 1 0 110 2H5a1 1 0 01-1-1zM2 11a2 2 0 012-2h12a2 2 0 012 2v4a2 2 0 01-2 2H4a2 2 0 01-2-2v-4z" />
      </svg>
    ),
  },
  {
    to: '/audit-logs',
    label: 'Audit Logs',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M2.166 4.999A11.954 11.954 0 0010 1.944 11.954 11.954 0 0017.834 5c.11.65.166 1.32.166 2.001 0 5.225-3.34 9.67-8 11.317C5.34 16.67 2 12.225 2 7c0-.682.057-1.35.166-2.001zm11.541 3.708a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
      </svg>
    ),
  },
  {
    to: '/deleted-records',
    label: 'Recycle Bin',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clipRule="evenodd" />
      </svg>
    ),
  },
  {
    to: '/privacy',
    label: 'Privacy, Terms & Conditions',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M10 1L3 5v6c0 5.25 3.5 8.75 7 9.5 3.5-.75 7-4.25 7-9.5V5l-7-4zm-1.5 12.5L5 10l1.4-1.4 2.1 2.1 4.1-4.1L14 8l-5.5 5.5z" clipRule="evenodd" />
      </svg>
    ),
  },
]

// Account management is the one area that stays ADMIN-exclusive.
const adminNavItems = [
  {
    to: '/accounts',
    alsoActiveOn: ['/my-account'],
    label: 'Accounts',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path d="M9 6a3 3 0 11-6 0 3 3 0 016 0zM17 6a3 3 0 11-6 0 3 3 0 016 0zM12.93 17c.046-.327.07-.66.07-1a6.97 6.97 0 00-1.5-4.33A5 5 0 0119 16v1h-6.07zM6 11a5 5 0 015 5v1H1v-1a5 5 0 015-5z" />
      </svg>
    ),
  },
]

function NavItemLink({ to, label, icon, alsoActiveOn, isCollapsed, pathname, hasNewAuditLog }) {
  const showPing = to === '/audit-logs' && hasNewAuditLog

  return (
    <div className="relative group">
      <NavLink
        to={to}
        className={({ isActive }) => {
          const active = isActive || (alsoActiveOn?.includes(pathname) ?? false)
          return [
            'flex items-center gap-2.5 px-2.5 py-2 w-full rounded-md text-sm font-medium transition-all duration-150',
            isCollapsed ? 'lg:justify-center lg:w-10 lg:h-10 lg:mx-auto lg:gap-0 lg:px-0 lg:py-0' : '',
            active
              ? 'bg-slate-900 text-white dark:bg-white dark:text-zinc-900'
              : 'text-slate-600 dark:text-zinc-400 hover:bg-slate-100 dark:hover:bg-zinc-800 hover:text-slate-900 dark:hover:text-zinc-100',
          ].join(' ')
        }}
      >
        <span className="relative flex-shrink-0">
          {icon}
          {showPing && (
            <span className="absolute -top-1 -right-1 flex h-2.5 w-2.5">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-brand-400 opacity-75" />
              <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-brand-500" />
            </span>
          )}
        </span>
        <span className={`whitespace-nowrap overflow-hidden flex-1 ${isCollapsed ? 'lg:hidden' : ''}`}>{label}</span>
      </NavLink>

      {isCollapsed && (
        <div className="
          hidden lg:block
          absolute left-full ml-3 top-1/2 -translate-y-1/2 z-50
          bg-slate-800 dark:bg-zinc-800 border border-slate-700 dark:border-zinc-700 text-white text-xs font-medium
          px-2.5 py-1.5 rounded-lg shadow-xl pointer-events-none whitespace-nowrap
          opacity-0 scale-95 origin-left
          [@media(hover:hover)_and_(pointer:fine)]:group-hover:opacity-100
          [@media(hover:hover)_and_(pointer:fine)]:group-hover:scale-100
          transition-[opacity,transform] duration-150
        ">
          {label}
          <span className="absolute right-full top-1/2 -translate-y-1/2 border-4 border-transparent border-r-slate-800 dark:border-r-zinc-800" />
        </div>
      )}
    </div>
  )
}

function Sidebar({ isCollapsed, onToggle, onHelp, isMobileOpen, onMobileClose }) {
  const user    = useSelector((s) => s.auth.user)
  const isAdmin = user?.role === 'ADMIN'
  const { pathname } = useLocation()
  const hasNewAuditLog = useAuditLogPing(pathname)
  const othersOnline = useSelector((s) => s.presence.onlineUsers).filter((u) => u !== user?.username)

  // Close mobile sidebar on navigation
  useEffect(() => { onMobileClose?.() }, [pathname]) // eslint-disable-line

  return (
    <>
      {/* Mobile backdrop */}
      {isMobileOpen && (
        <div
          className="fixed inset-0 z-30 bg-zinc-950/60 lg:hidden"
          onClick={onMobileClose}
        />
      )}
    <aside
      className={`
        fixed lg:relative inset-y-0 left-0 z-40 lg:z-auto
        w-60 ${isCollapsed ? 'lg:w-[60px]' : 'lg:w-60'}
        ${isMobileOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'}
        h-full bg-white dark:bg-zinc-950 border-r border-slate-200 dark:border-zinc-800
        flex flex-col flex-shrink-0 overflow-x-hidden
        transition-[transform,width] duration-300 ease-in-out
      `}
    >
      {/* Brand */}
      <div className={`flex items-center h-[60px] flex-shrink-0 border-b border-slate-200 dark:border-zinc-800 justify-between px-4 ${isCollapsed ? 'lg:justify-center lg:px-0' : ''}`}>
        <div className={`flex items-center gap-2.5 min-w-0 overflow-hidden ${isCollapsed ? 'lg:hidden' : ''}`}>
          <img
            src="/logo.jpg"
            alt="San Jose Municipal Hall seal"
            className="rounded-full object-cover bg-white flex-shrink-0 ring-1 ring-slate-200 dark:ring-white/10 w-8 h-8"
          />
          <div className="overflow-hidden">
            <p className="text-sm font-semibold text-gov-700 dark:text-white whitespace-nowrap leading-tight">San Jose GSO</p>
            <p className="text-2xs text-slate-400 dark:text-zinc-500 whitespace-nowrap leading-tight mt-px">Inventory Management</p>
            <p className="text-2xs text-slate-400 dark:text-zinc-500 whitespace-nowrap leading-tight">System</p>
          </div>
        </div>
        {/* Collapse toggle — desktop only */}
        <button
          onClick={onToggle}
          className="hidden lg:flex p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150 flex-shrink-0"
          title={isCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
        >
          {isCollapsed ? (
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clipRule="evenodd" />
            </svg>
          ) : (
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z" clipRule="evenodd" />
            </svg>
          )}
        </button>
        {/* Close button — mobile only */}
        <button
          onClick={onMobileClose}
          className="lg:hidden p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150 flex-shrink-0"
          aria-label="Close menu"
        >
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
          </svg>
        </button>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-2 py-3 overflow-y-auto overflow-x-hidden flex flex-col gap-0.5">
        <p className={`text-2xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-widest px-2 mb-1.5 whitespace-nowrap ${isCollapsed ? 'lg:hidden' : ''}`}>
          Main Menu
        </p>

        {navItems.map(({ to, label, icon, alsoActiveOn }) => (
          <NavItemLink key={to} to={to} label={label} icon={icon} alsoActiveOn={alsoActiveOn} isCollapsed={isCollapsed} pathname={pathname} hasNewAuditLog={hasNewAuditLog} />
        ))}

        <p className={`text-2xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-widest px-2 mt-3 mb-1.5 whitespace-nowrap ${isCollapsed ? 'lg:hidden' : ''}`}>
          System
        </p>
        {systemNavItems.map(({ to, label, icon, alsoActiveOn }) => (
          <NavItemLink key={to} to={to} label={label} icon={icon} alsoActiveOn={alsoActiveOn} isCollapsed={isCollapsed} pathname={pathname} hasNewAuditLog={hasNewAuditLog} />
        ))}

        {isAdmin && (
          <>
            <p className={`text-2xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-widest px-2 mt-3 mb-1.5 whitespace-nowrap ${isCollapsed ? 'lg:hidden' : ''}`}>
              Admin
            </p>
            {adminNavItems.map(({ to, label, icon, alsoActiveOn }) => (
              <NavItemLink key={to} to={to} label={label} icon={icon} alsoActiveOn={alsoActiveOn} isCollapsed={isCollapsed} pathname={pathname} hasNewAuditLog={hasNewAuditLog} />
            ))}
          </>
        )}

        {!isAdmin && (
          <>
            <p className={`text-2xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-widest px-2 mt-3 mb-1.5 whitespace-nowrap ${isCollapsed ? 'lg:hidden' : ''}`}>
              Account
            </p>
            <NavItemLink
              to="/my-account"
              label="My Account"
              icon={
                <svg xmlns="http://www.w3.org/2000/svg" className="h-[18px] w-[18px] flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M10 9a3 3 0 100-6 3 3 0 000 6zm-7 9a7 7 0 1114 0H3z" clipRule="evenodd" />
                </svg>
              }
              isCollapsed={isCollapsed}
              pathname={pathname}
              hasNewAuditLog={false}
            />
          </>
        )}
      </nav>

      {/* Footer */}
      <div
        className={`border-t border-slate-200 dark:border-zinc-800 overflow-hidden transition-all duration-300 max-h-40 px-4 py-4 ${isCollapsed ? 'lg:max-h-0 lg:py-0 lg:px-0' : ''}`}
      >
        {othersOnline.length > 0 && (
          <div
            className="flex items-center gap-1.5 mb-2"
            title={othersOnline.join(', ')}
          >
            <span className="relative flex h-1.5 w-1.5 flex-shrink-0">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
              <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-emerald-500" />
            </span>
            <span className="text-2xs text-slate-500 dark:text-zinc-400 truncate">
              {othersOnline.length === 1 ? `${othersOnline[0]} is online` : `${othersOnline.length} others online`}
            </span>
          </div>
        )}
        <p className="text-xs text-slate-500 dark:text-zinc-500 whitespace-nowrap">San Jose Municipal Hall</p>
        <p className="text-2xs text-slate-400 dark:text-zinc-600 mt-0.5 whitespace-nowrap">Republic of the Philippines</p>
        <NavLink
          to="/privacy"
          className="text-2xs text-slate-400 dark:text-zinc-600 hover:text-brand-500 dark:hover:text-brand-400 mt-1.5 inline-block transition-colors duration-150"
        >
          Privacy, Terms & Conditions
        </NavLink>
        {onHelp && (
          <button
            onClick={onHelp}
            className="mt-3 w-full flex items-center gap-2.5 px-3 py-2.5 rounded-lg border border-brand-500/30 bg-brand-500/8 hover:bg-brand-500/15 hover:border-brand-500/50 transition-all duration-150 group"
          >
            <span className="flex-shrink-0 w-6 h-6 rounded-md bg-brand-500/20 group-hover:bg-brand-500/30 flex items-center justify-center transition-colors duration-150">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5 text-brand-400" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-3a1 1 0 00-.867.5 1 1 0 11-1.731-1A3 3 0 0113 8a3.001 3.001 0 01-2 2.83V11a1 1 0 11-2 0v-1a1 1 0 011-1 1 1 0 100-2zm0 8a1 1 0 100-2 1 1 0 000 2z" clipRule="evenodd" />
              </svg>
            </span>
            <div className="text-left min-w-0">
              <p className="text-xs font-semibold text-brand-400 whitespace-nowrap leading-tight">Getting Started</p>
              <p className="text-2xs text-slate-400 dark:text-zinc-500 whitespace-nowrap leading-tight mt-px">New user guide</p>
            </div>
          </button>
        )}
      </div>
    </aside>
    </>
  )
}

export default Sidebar
