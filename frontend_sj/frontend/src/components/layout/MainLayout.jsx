import { useState, useCallback } from 'react'
import { useLocation } from 'react-router-dom'
import Sidebar from './Sidebar'
import Header from './Header'
import GovMasthead from './GovMasthead'
import IdleWarningModal from '../common/IdleWarningModal'
import OnboardingModal, { useOnboarding } from '../common/OnboardingModal'
import PrivacyAcknowledgmentModal from '../common/PrivacyAcknowledgmentModal'
import { useIdleTimeout } from '../../hooks/useIdleTimeout'
import { useAuth } from '../../hooks/useAuth'

const IDLE_MS = 15 * 60 * 1000  // 15 minutes
const WARN_MS = 14 * 60 * 1000  // warn at 14 minutes (1 minute before logout)

function MainLayout({ children }) {
  const { show: showOnboarding, dismiss: dismissOnboarding, reset: resetOnboarding } = useOnboarding()

  const [isCollapsed, setIsCollapsed] = useState(
    () => localStorage.getItem('sidebar-collapsed') === 'true'
  )
  const [isMobileSidebarOpen, setIsMobileSidebarOpen] = useState(false)

  const handleToggle = () => setIsCollapsed((prev) => {
    const next = !prev
    localStorage.setItem('sidebar-collapsed', String(next))
    return next
  })
  const [showWarning, setShowWarning]  = useState(false)
  const [ackLoading, setAckLoading]    = useState(false)
  const { pathname } = useLocation()
  const { signOut, user, acknowledgePrivacy } = useAuth()

  const showPrivacyModal = !!user && !user.privacyAcknowledgedAt

  const handleAcknowledgePrivacy = async () => {
    setAckLoading(true)
    try { await acknowledgePrivacy() } finally { setAckLoading(false) }
  }

  const handleWarn = useCallback(() => setShowWarning(true),  [])
  const handleIdle = useCallback(() => { setShowWarning(false); signOut() }, [signOut])

  const { reset } = useIdleTimeout({
    idleAfterMs: IDLE_MS,
    warnAfterMs: WARN_MS,
    onWarn: handleWarn,
    onIdle: handleIdle,
  })

  const handleStay = () => {
    setShowWarning(false)
    reset()
  }

  const handleLogoutNow = () => {
    setShowWarning(false)
    signOut()
  }

  return (
    <div className="h-screen flex flex-col overflow-hidden bg-white dark:bg-zinc-950">
      <GovMasthead />
      <div className="flex flex-1 min-h-0 overflow-hidden">
        <Sidebar
          isCollapsed={isCollapsed}
          onToggle={handleToggle}
          onHelp={resetOnboarding}
          isMobileOpen={isMobileSidebarOpen}
          onMobileClose={() => setIsMobileSidebarOpen(false)}
        />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <Header onMenuOpen={() => setIsMobileSidebarOpen(true)} />
          <main className="flex-1 overflow-auto p-4 sm:p-5 lg:p-6 xl:p-8">
            <div key={pathname} className="animate-fade-slide">
              {children}
            </div>
          </main>
        </div>
      </div>

      {showWarning && (
        <IdleWarningModal onStay={handleStay} onLogout={handleLogoutNow} />
      )}

      {showPrivacyModal ? (
        <PrivacyAcknowledgmentModal onAcknowledge={handleAcknowledgePrivacy} loading={ackLoading} />
      ) : showOnboarding && (
        <OnboardingModal onDismiss={dismissOnboarding} />
      )}
    </div>
  )
}

export default MainLayout
